import AppKit
import ImageIO
import PDFKit
import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case convert = "Convert", compress = "Compress", resize = "Resize"
    case rotate = "Rotate", strip = "Remove Info", rename = "Rename"
    case combine = "Combine to PDF", split = "Split PDF"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .rotate: "rotate.right"
        case .strip: "eye.slash"
        case .rename: "character.cursor.ibeam"
        case .combine: "doc.on.doc"
        case .split: "scissors"
        }
    }
    var subtitle: String {
        switch self {
        case .convert: "Turn photos into another format, or PDF pages into images"
        case .compress: "Make photos and PDFs smaller while keeping them sharp"
        case .resize: "Scale photos down to a given size"
        case .rotate: "Turn photos or PDF pages"
        case .strip: "Remove camera, date and location info before sharing"
        case .rename: "Give a set of files consistent, numbered names"
        case .combine: "Put photos and PDFs together into one PDF"
        case .split: "Take pages out of a PDF or cut it into parts"
        }
    }
    var action: String {
        switch self {
        case .strip: "Remove Info"
        case .combine: "Create PDF"
        case .split: "Split"
        default: rawValue
        }
    }
    func accepts(_ k: Kind) -> Bool {
        switch self {
        case .resize: k == .image
        case .split: k == .pdf
        default: true
        }
    }
    /// Tools where the PDF page selection matters
    var usesPages: Bool { self == .convert || self == .rotate || self == .split }
    var writesFiles: Bool { self != .rename }
}

struct Item: Identifiable {
    let id = UUID()
    var url: URL
    let kind: Kind
    var pageCount = 1
    var date = Date.distantPast
    var selected: Set<Int> = []      // PDF: 0-based pages; empty = all pages
    var status = "Ready"
    var done = false
    var failed = false
    var output: URL? = nil           // compressed copy, for comparing

    var pages: [Int] { selected.isEmpty ? Array(0..<pageCount) : selected.sorted() }
    var pageSummary: String {
        selected.isEmpty ? "All \(pageCount) pages" : "\(selected.count) of \(pageCount) pages"
    }
}

/// What a background job needs to know about a file
struct Job: Sendable {
    let id: UUID
    let url: URL
    let kind: Kind
    let pages: [Int]
}

struct Outcome: Sendable {
    var message: String
    var files: [URL]
    var compareWith: URL? = nil
}

@MainActor
final class Model: ObservableObject {
    @Published var items: [Item] = []
    @Published var tool: Tool = .convert {
        didSet { if tool != oldValue { resetStatus() } }
    }
    @Published var outputFolder: URL? = nil   // nil = next to the original
    @Published var busy = false
    @Published var editing: Item.ID? = nil
    @Published var comparing: Item.ID? = nil
    @Published var summary: String? = nil
    @Published var lastOutputs: [URL] = []

    // Convert
    @Published var format: OutFormat = .jpg
    @Published var quality: Double = 0.9
    @Published var dpi: Int = 150
    // Compress
    @Published var compressBy: CompressBy = .level
    @Published var level: Level = .balanced
    @Published var targetMB: Double = 2
    // Resize
    @Published var resizeMode: ResizeMode = .longest
    @Published var resizeValue: Int = 2000
    // Rotate
    @Published var rotation: Int = 90
    // Remove info
    @Published var stripMode: StripMode = .all
    // Combine
    @Published var pageSize: PageSize = .a4
    @Published var pageMargin = true
    @Published var combinedName = "Combined"
    // Split
    @Published var splitMode: SplitMode = .extract
    @Published var chunkSize = 5
    // Rename
    @Published var renamePattern = "Photo ###"
    @Published var renameStart = 1
    @Published var lastRename: [(from: URL, to: URL)] = []

    var hasPDF: Bool { items.contains { $0.kind == .pdf } }
    var eligible: [Item] { items.filter { tool.accepts($0.kind) } }
    var pending: [Item] { eligible.filter { !$0.done } }

    // MARK: Files

    static let exifDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Date the photo was taken, otherwise the file's creation date
    static func date(of url: URL, kind: Kind) -> Date {
        if kind == .image, let s = CGImageSourceCreateWithURL(url as CFURL, nil),
           let exif = ImageOps.properties(s)[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let str = exif[kCGImagePropertyExifDateTimeOriginal] as? String, let d = exifDate.date(from: str) {
            return d
        }
        return (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    static let imageExtensions: Set = ["heic", "heif", "jpg", "jpeg", "png", "tif", "tiff", "webp", "avif"]

    func add(_ urls: [URL]) {
        var expanded: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                var found: [URL] = []
                while let f = e?.nextObject() as? URL { found.append(f) }
                expanded += found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            } else { expanded.append(u) }
        }
        let existing = Set(items.map { $0.url })
        for u in expanded where !existing.contains(u) {
            let ext = u.pathExtension.lowercased()
            if Self.imageExtensions.contains(ext) {
                items.append(Item(url: u, kind: .image, date: Self.date(of: u, kind: .image)))
            } else if ext == "pdf", let doc = PDFDocument(url: u), doc.pageCount > 0 {
                items.append(Item(url: u, kind: .pdf, pageCount: doc.pageCount, date: Self.date(of: u, kind: .pdf)))
            }
        }
    }

    func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.allowedContentTypes = [.image, .pdf, .folder]
        if p.runModal() == .OK { add(p.urls) }
    }

    func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.prompt = "Choose"
        if p.runModal() == .OK { outputFolder = p.url }
    }

    func remove(_ id: Item.ID) { items.removeAll { $0.id == id } }

    enum SortOrder { case name, date }
    func sort(_ order: SortOrder) {
        switch order {
        case .name: items.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        case .date: items.sort { $0.date < $1.date }
        }
    }

    func resetStatus() {
        for i in items.indices {
            items[i].status = "Ready"; items[i].done = false; items[i].failed = false; items[i].output = nil
        }
        summary = nil
        lastOutputs = []
    }

    func update(_ id: Item.ID, _ f: (inout Item) -> Void) {
        if let i = items.firstIndex(where: { $0.id == id }) { f(&items[i]) }
    }

    func showInFinder() { NSWorkspace.shared.activateFileViewerSelecting(lastOutputs) }

    // MARK: Running

    func run() {
        if pending.isEmpty && tool != .rename { resetStatus() }   // "… Again"
        summary = nil
        lastOutputs = []
        let folder = outputFolder
        switch tool {
        case .convert:
            let fmt = format, q = quality, dpi = dpi
            runEach { job, progress in
                if job.kind == .image {
                    let out = try ImageOps.convert(job.url, to: fmt, quality: q, folder: folder)
                    return Outcome(message: out.lastPathComponent, files: [out])
                }
                let outs = try PDFOps.toImages(job.url, pages: job.pages, to: fmt, quality: q, dpi: dpi, folder: folder) {
                    progress("Page \($0) of \(job.pages.count)…")
                }
                return Outcome(message: outs.count == 1 ? outs[0].lastPathComponent : "\(outs.count) images", files: outs)
            }
        case .compress:
            let level = level
            let target: Int64? = compressBy == .target ? Int64(max(0.05, targetMB) * 1_000_000) : nil
            runEach { job, progress in
                let before = fileSize(job.url)
                let out = try Compressor.run(job.url, kind: job.kind, level: level, target: target, folder: folder, progress: progress)
                let after = fileSize(out)
                var msg = "\(fmtSize(before)) → \(fmtSize(after)) (−\(Int((Double(before - after) / Double(before) * 100).rounded())) %)"
                if let target, after > target { msg += ", smallest possible" }
                return Outcome(message: msg, files: [out], compareWith: out)
            }
        case .resize:
            let mode = resizeMode, value = resizeValue
            runEach { job, _ in
                let (out, w, h) = try ImageOps.resize(job.url, mode: mode, value: value, folder: folder)
                return Outcome(message: "\(w)×\(h)", files: [out])
            }
        case .rotate:
            let deg = rotation
            runEach { job, _ in
                let out = job.kind == .image
                    ? try ImageOps.rotate(job.url, degrees: deg, folder: folder)
                    : try PDFOps.rotate(job.url, pages: job.pages, degrees: deg, folder: folder)
                return Outcome(message: out.lastPathComponent, files: [out])
            }
        case .strip:
            let mode = stripMode
            runEach { job, _ in
                let out = job.kind == .image
                    ? try ImageOps.strip(job.url, mode: mode, folder: folder)
                    : try PDFOps.stripInfo(job.url, folder: folder)
                return Outcome(message: out.lastPathComponent, files: [out])
            }
        case .split:
            let mode = splitMode, chunk = chunkSize
            runEach { job, _ in
                let outs = try PDFOps.split(job.url, pages: job.pages, mode: mode, chunk: chunk, folder: folder)
                return Outcome(message: outs.count == 1 ? outs[0].lastPathComponent : "\(outs.count) PDFs", files: outs)
            }
        case .combine: combine()
        case .rename: rename()
        }
    }

    /// Runs `work` for every eligible file in the background, one after another
    private func runEach(_ work: @escaping @Sendable (Job, @escaping @Sendable (String) -> Void) throws -> Outcome) {
        let jobs = pending.map { Job(id: $0.id, url: $0.url, kind: $0.kind, pages: $0.pages) }
        guard !jobs.isEmpty else { return }
        busy = true
        Task.detached {
            for job in jobs {
                await MainActor.run { self.update(job.id) { $0.status = "Working…" } }
                let progress: @Sendable (String) -> Void = { msg in
                    Task { @MainActor in self.update(job.id) { if !$0.done && !$0.failed { $0.status = msg } } }
                }
                let result = Result { try work(job, progress) }
                await MainActor.run {
                    if case .success(let o) = result { self.lastOutputs += o.files }
                    self.update(job.id) {
                        switch result {
                        case .success(let o):
                            $0.status = "✓ " + o.message; $0.done = true; $0.output = o.compareWith
                        case .failure(let e as Skipped):
                            $0.status = e.localizedDescription; $0.done = true
                        case .failure(let e):
                            $0.status = "Error: " + e.localizedDescription; $0.failed = true
                        }
                    }
                }
            }
            await MainActor.run { self.busy = false }
        }
    }

    // MARK: Combine

    private func combine() {
        let parts = eligible
        guard !parts.isEmpty else { return }
        let name = combinedName.trimmingCharacters(in: .whitespaces).isEmpty ? "Combined" : combinedName
        let out = uniqueURL(outputFolder ?? parts[0].url.deletingLastPathComponent(), name, "pdf")
        let entries = parts.map { (url: $0.url, kind: $0.kind) }
        let pageSize = pageSize, margin = pageMargin
        for p in parts { update(p.id) { $0.status = "Waiting…"; $0.done = false; $0.failed = false } }
        busy = true
        Task.detached {
            let result = Result {
                try PDFOps.combine(entries, pageSize: pageSize, margin: margin, to: out) { n in
                    let id = parts[n - 1].id
                    Task { @MainActor in self.update(id) { $0.status = "Adding…" } }
                }
            }
            await MainActor.run {
                switch result {
                case .success(let pages):
                    for p in parts { self.update(p.id) { $0.status = "✓ Added"; $0.done = true } }
                    self.summary = "Created “\(out.lastPathComponent)”: \(pages) pages, \(fmtSize(fileSize(out)))"
                    self.lastOutputs = [out]
                case .failure(let e):
                    for p in parts { self.update(p.id) { $0.status = "Ready" } }
                    self.summary = "Error: " + e.localizedDescription
                }
                self.busy = false
            }
        }
    }

    // MARK: Rename

    /// "Photo ###" + 7 → "Photo 007"; without # the number is appended
    static func renamed(_ pattern: String, number: Int, last: Int) -> String {
        let name: String
        if let r = pattern.range(of: "#+", options: .regularExpression) {
            let width = pattern.distance(from: r.lowerBound, to: r.upperBound)
            name = pattern.replacingCharacters(in: r, with: String(format: "%0\(width)d", number))
        } else {
            name = pattern + " " + String(format: "%0\(max(2, String(last).count))d", number)
        }
        return name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    /// New file name for every file, in list order
    func renamePreview() -> [Item.ID: String] {
        let pattern = renamePattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return [:] }
        let last = renameStart + items.count - 1
        var result: [Item.ID: String] = [:]
        for (n, it) in items.enumerated() {
            let ext = it.url.pathExtension
            result[it.id] = Self.renamed(pattern, number: renameStart + n, last: last) + (ext.isEmpty ? "" : "." + ext)
        }
        return result
    }

    var renameCount: Int {
        let p = renamePreview()
        return items.filter { p[$0.id] != nil && p[$0.id] != $0.url.lastPathComponent }.count
    }

    /// Moves files in two steps (via temporary names) so names can be swapped; undoes everything on failure
    private static func moveAll(_ moves: [(from: URL, to: URL)]) throws {
        let fm = FileManager.default
        var parked: [(tmp: URL, from: URL, to: URL)] = []
        var placed: [(tmp: URL, from: URL, to: URL)] = []
        do {
            for m in moves {
                let tmp = m.from.deletingLastPathComponent().appendingPathComponent(".renaming-\(UUID().uuidString)")
                try fm.moveItem(at: m.from, to: tmp)
                parked.append((tmp, m.from, m.to))
            }
            for p in parked {
                try fm.moveItem(at: p.tmp, to: p.to)
                placed.append(p)
            }
        } catch {
            for p in placed { try? fm.moveItem(at: p.to, to: p.tmp) }
            for p in parked { try? fm.moveItem(at: p.tmp, to: p.from) }
            throw error
        }
    }

    private func rename() {
        let preview = renamePreview()
        var moves: [(id: Item.ID, from: URL, to: URL)] = []
        for it in items {
            guard let name = preview[it.id], name != it.url.lastPathComponent else { continue }
            moves.append((it.id, it.url, it.url.deletingLastPathComponent().appendingPathComponent(name)))
        }
        guard !moves.isEmpty else { return }
        // Refuse if a new name is already taken by a file that isn't being renamed
        let sources = Set(moves.map { $0.from.path.lowercased() })
        var targets = Set<String>()
        for m in moves {
            let t = m.to.path.lowercased()
            if targets.contains(t) || (FileManager.default.fileExists(atPath: m.to.path) && !sources.contains(t)) {
                update(m.id) { $0.status = "Error: “\(m.to.lastPathComponent)” already exists"; $0.failed = true }
                summary = "Nothing renamed: a file with one of the new names already exists"
                return
            }
            targets.insert(t)
        }
        do {
            try Self.moveAll(moves.map { ($0.from, $0.to) })
        } catch {
            summary = "Nothing renamed: " + error.localizedDescription
            return
        }
        for m in moves {
            update(m.id) { $0.url = m.to; $0.status = "✓ was “\(m.from.lastPathComponent)”"; $0.done = true; $0.failed = false }
        }
        lastRename = moves.map { ($0.to, $0.from) }
        lastOutputs = moves.map { $0.to }
        summary = "Renamed \(moves.count) file\(moves.count == 1 ? "" : "s")"
    }

    func undoRename() {
        let moves = lastRename
        do {
            try Self.moveAll(moves)
        } catch {
            summary = "Undo failed: " + error.localizedDescription
            return
        }
        for m in moves {
            if let i = items.firstIndex(where: { $0.url == m.from }) {
                items[i].url = m.to; items[i].status = "Ready"; items[i].done = false
            }
        }
        lastRename = []
        lastOutputs = []
        summary = "Original names restored"
    }
}
