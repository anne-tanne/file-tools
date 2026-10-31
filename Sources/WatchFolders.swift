import SwiftUI
import PDFKit
import Combine

// MARK: - Model

/// A folder whose new files are run through a preset
struct WatchFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var presetID: UUID
    var enabled = true
}

/// One active watch: a dispatch source plus the names already seen. Everything but `preset` runs on `queue`.
private final class FolderWatch: @unchecked Sendable {
    let folder: WatchFolder
    private let queue: DispatchQueue
    private let report: @Sendable (WatchFolder.ID, String) -> Void
    private let lock = NSLock()
    private var _preset: Preset?
    private var known: Set<String>
    private var source: DispatchSourceFileSystemObject?
    private var scanPending = false

    var preset: Preset? {
        get { lock.lock(); defer { lock.unlock() }; return _preset }
        set { lock.lock(); _preset = newValue; lock.unlock() }
    }

    init?(_ folder: WatchFolder, preset: Preset?, queue: DispatchQueue,
          report: @escaping @Sendable (WatchFolder.ID, String) -> Void) {
        self.folder = folder
        self.queue = queue
        self.report = report
        self._preset = preset
        let fd = open(folder.url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        known = Set(FolderWatch.listing(folder.url))   // files already there are left alone
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
        src.setEventHandler { [weak self] in self?.scheduleScan() }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    func stop() { source?.cancel(); source = nil }

    /// Names of visible top-level regular files
    static func listing(_ dir: URL) -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map(\.lastPathComponent)
    }

    /// Waits 1 s so a burst of events becomes one scan
    private func scheduleScan() {
        guard !scanPending else { return }
        scanPending = true
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.scan() }
    }

    private func scan() {
        scanPending = false
        guard source != nil else { return }
        let skipped: Set<String> = ["download", "crdownload", "part"]
        for name in FolderWatch.listing(folder.url).sorted() where !known.contains(name) {
            let url = folder.url.appendingPathComponent(name)
            let ext = url.pathExtension.lowercased()
            if name.hasPrefix("~$") || name.hasPrefix(".") || skipped.contains(ext) { continue }   // may be renamed later
            // Ready when the size is unchanged after a second
            let before = fileSize(url)
            Thread.sleep(forTimeInterval: 1)
            guard source != nil else { return }
            if fileSize(url) != before || before == 0 {
                scheduleScan()
                continue
            }
            known.insert(name)
            process(url, ext: ext)
        }
    }

    private func process(_ url: URL, ext: String) {
        guard let kind = Kind(url: url) else { return }
        guard let preset else { report(folder.id, tr("Preset was deleted")); return }
        guard preset.accepts(kind) else { return }
        let out = folder.url.appendingPathComponent(tr("Processed"))
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let pages = kind == .pdf ? Array(0..<max(1, PDFDocument(url: url)?.pageCount ?? 1)) : [0]
            let o = try Steps.runPreset(preset, Job(id: UUID(), url: url, kind: kind, pages: pages), folder: out, progress: { _ in })
            report(folder.id, "✓ " + (o.files.first?.lastPathComponent ?? url.lastPathComponent))
        } catch is Skipped {
            report(folder.id, "\(url.lastPathComponent): " + tr("Nothing to do for this file"))
        } catch {
            report(folder.id, tr("Error: %@", error.localizedDescription))
        }
    }
}

/// Watches the enabled folders while the app is open and runs the chosen preset on new files
@MainActor
final class FolderWatcher: ObservableObject {
    static let shared = FolderWatcher()

    @Published var folders: [WatchFolder] {
        didSet { save(); reconcile() }
    }
    /// Last activity per folder
    @Published var status: [WatchFolder.ID: String] = [:]

    private let queue = DispatchQueue(label: "FileTools.watchFolders")   // serial: one file at a time
    private var watches: [WatchFolder.ID: FolderWatch] = [:]
    private var started = false
    private var bag = Set<AnyCancellable>()

    private init() {
        if let d = UserDefaults.standard.data(forKey: "watchFolders"),
           let saved = try? JSONDecoder().decode([WatchFolder].self, from: d) {
            folders = saved
        } else {
            folders = []
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(folders) { UserDefaults.standard.set(d, forKey: "watchFolders") }
    }

    /// Called once at launch
    func start() {
        guard !started else { return }
        started = true
        Model.shared.$presets.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }.store(in: &bag)
        reconcile()
    }

    /// Starts sources for enabled folders that have none, stops the others, refreshes presets
    private func reconcile() {
        guard started else { return }
        let presets = Model.shared.presets
        let ids = Set(folders.map(\.id))
        for (id, w) in watches where !ids.contains(id) || !(folders.first { $0.id == id }?.enabled ?? false)
            || folders.first(where: { $0.id == id })?.url != w.folder.url {
            w.stop()
            watches[id] = nil
        }
        let report: @Sendable (WatchFolder.ID, String) -> Void = { id, text in
            Task { @MainActor in FolderWatcher.shared.status[id] = text }
        }
        for f in folders {
            let preset = presets.first { $0.id == f.presetID }
            if preset == nil {
                status[f.id] = tr("Preset was deleted")
            } else if status[f.id] == tr("Preset was deleted") {
                status[f.id] = nil
            }
            guard f.enabled else { continue }
            if let w = watches[f.id] {
                w.preset = preset
            } else if let w = FolderWatch(f, preset: preset, queue: queue, report: report) {
                watches[f.id] = w
            } else {
                status[f.id] = tr("Error: %@", tr("Folder not found"))
            }
        }
    }

    /// Asks for a folder; the first preset is preselected
    func addFolder() {
        guard let preset = Model.shared.presets.first else { return }
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = tr("Watch")
        p.message = tr("Choose a folder to watch")
        guard p.runModal() == .OK, let url = p.url, !folders.contains(where: { $0.url == url }) else { return }
        folders.append(WatchFolder(url: url, presetID: preset.id))
    }
}

// MARK: - Sheet

/// Lists the watched folders: preset, on/off, last activity
struct WatchFoldersSheet: View {
    @EnvironmentObject var m: Model
    @ObservedObject private var watcher = FolderWatcher.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Watch Folders", systemImage: "folder.badge.gearshape").font(.headline)

            List {
                ForEach($watcher.folders) { $f in
                    HStack(spacing: 10) {
                        Label(f.url.lastPathComponent, systemImage: "folder")
                            .lineLimit(1)
                            .frame(width: 150, alignment: .leading)
                            .help(f.url.path)
                        Picker("Preset", selection: $f.presetID) {
                            if !m.presets.contains(where: { $0.id == f.presetID }) {
                                Text("Preset was deleted").tag(f.presetID)
                            }
                            ForEach(m.presets) { p in Text(p.name).tag(p.id) }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                        Toggle("Watch", isOn: $f.enabled).labelsHidden()
                        Text(watcher.status[f.id] ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { watcher.folders.removeAll { $0.id == f.id } } label: {
                            Label("Stop Watching", systemImage: "minus.circle.fill")
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help("Stop watching this folder")
                    }
                }
            }
            .frame(minHeight: 150, idealHeight: 190)
            .overlay {
                if watcher.folders.isEmpty {
                    ContentUnavailableView("No Watched Folders", systemImage: "folder.badge.gearshape",
                                           description: Text("Add a folder and choose a preset to run on every new file."))
                }
            }

            Text("Works while File Tools is open. Results go into a “Processed” folder inside the watched folder. Files already in the folder are left alone.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button { watcher.addFolder() } label: { Label("Add Folder…", systemImage: "plus") }
                    .disabled(m.presets.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640)
    }
}
