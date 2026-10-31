import AppKit
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum Tool: String, CaseIterable, Identifiable, Codable, Sendable, Titled {
    case convert = "Convert", compress = "Compress", resize = "Resize"
    case rotate = "Rotate", strip = "Remove Info", rename = "Rename"
    case combine = "Combine to PDF", split = "Split PDF", reorder = "Reorder Pages"
    case extractImages = "Extract Images", wordToPDF = "Word to PDF"
    case crop = "Crop", removeBackground = "Remove Background", watermark = "Watermark", blackWhite = "Black & White"
    case iconSet = "Make Icons", contactSheet = "Contact Sheet", duplicates = "Find Duplicates"
    case recognizeText = "Recognize Text", makeSearchable = "Make Searchable", pageNumbers = "Page Numbers"
    case password = "Password", flatten = "Flatten"
    case stitch = "Stitch Images", cleanScan = "Clean Up Scans", redact = "Redact"
    case extractTables = "Extract Tables", videoToGIF = "Video to GIF"
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
        case .reorder: "rectangle.2.swap"
        case .extractImages: "photo.on.rectangle.angled"
        case .wordToPDF: "doc.text"
        case .crop: "crop"
        case .removeBackground: "person.and.background.dotted"
        case .watermark: "signature"
        case .blackWhite: "circle.lefthalf.filled"
        case .iconSet: "app.dashed"
        case .contactSheet: "square.grid.2x2"
        case .duplicates: "square.on.square"
        case .recognizeText: "text.viewfinder"
        case .makeSearchable: "doc.text.magnifyingglass"
        case .pageNumbers: "number"
        case .password: "lock.doc"
        case .flatten: "square.stack.3d.down.right"
        case .stitch: "rectangle.split.1x2"
        case .cleanScan: "doc.viewfinder"
        case .redact: "rectangle.inset.filled"
        case .extractTables: "tablecells"
        case .videoToGIF: "film.stack"
        }
    }
    var subtitle: String {
        switch self {
        case .convert: tr("Turn photos into another format, or PDF pages into images")
        case .compress: tr("Make photos, PDFs and videos smaller while keeping them sharp")
        case .resize: tr("Scale photos down to a given size")
        case .rotate: tr("Turn photos or PDF pages")
        case .strip: tr("Remove camera, date and location info before sharing")
        case .rename: tr("Give a set of files consistent, numbered names")
        case .combine: tr("Put photos and PDFs together into one PDF")
        case .split: tr("Take pages out of a PDF or cut it into parts")
        case .reorder: tr("Drag PDF pages into a new order")
        case .extractImages: tr("Save the pictures inside a PDF as separate image files")
        case .wordToPDF: tr("Save Word documents as PDFs with the exact Word layout")
        case .crop: tr("Cut photos to a standard shape or trim away plain borders")
        case .removeBackground: tr("Cut the subject out of a photo")
        case .watermark: tr("Stamp text or a logo on photos and PDFs")
        case .blackWhite: tr("Turn photos and PDFs into black and white")
        case .iconSet: tr("Make Mac and Windows icon files from a picture")
        case .contactSheet: tr("Put many photos on one overview sheet")
        case .duplicates: tr("Find photos that are the same or look alike")
        case .recognizeText: tr("Read the text in photos and scanned PDFs into a text file")
        case .makeSearchable: tr("Add a hidden text layer to scanned PDFs so you can search and copy")
        case .pageNumbers: tr("Add page numbers to a PDF")
        case .password: tr("Protect a PDF with a password or remove its password")
        case .flatten: tr("Burn form fields and notes into the PDF so they can't be edited")
        case .stitch: tr("Put photos together into one long or wide image")
        case .cleanScan: tr("Straighten and brighten photos of documents")
        case .redact: tr("Black out names, numbers and other text for good")
        case .extractTables: tr("Save the tables in PDFs and photos as CSV files")
        case .videoToGIF: tr("Make an animated GIF from a video")
        }
    }
    var action: String {
        switch self {
        case .strip: "Remove Info"
        case .combine: "Create PDF"
        case .split: "Split"
        case .reorder: "Save"
        case .extractImages: "Extract"
        case .wordToPDF: "Create PDFs"
        case .watermark: "Add Watermark"
        case .blackWhite: "Convert"
        case .iconSet: "Make Icons"
        case .contactSheet: "Create Sheet"
        case .pageNumbers: "Add Numbers"
        case .password: "Apply"
        case .stitch: "Stitch"
        case .cleanScan: "Clean Up"
        case .extractTables: "Extract"
        case .videoToGIF: "Make GIF"
        default: rawValue
        }
    }
    func accepts(_ k: Kind) -> Bool {
        switch self {
        case .resize, .crop, .removeBackground, .iconSet, .contactSheet, .duplicates, .stitch, .cleanScan: k == .image
        case .split, .reorder, .extractImages, .pageNumbers, .password, .flatten: k == .pdf
        case .wordToPDF: k == .word
        case .videoToGIF: k == .video
        case .compress: k == .image || k == .pdf || k == .video
        case .rename: true
        default: k == .image || k == .pdf
        }
    }
    /// Tools where the PDF page selection matters
    var usesPages: Bool { self == .convert || self == .rotate || self == .split || self == .extractImages || self == .extractTables }
    var writesFiles: Bool { self != .rename && self != .duplicates }
}

struct Item: Identifiable {
    let id = UUID()
    var url: URL
    let kind: Kind
    var pageCount = 1
    var date = Date.distantPast
    var selected: Set<Int> = []      // PDF: 0-based pages; empty = all pages
    var parts: [[Int]] = []          // Split selected pages: sorted pages of each new PDF
    var partNames: [String] = []     // optional file name per part, "" = default name
    var status = tr("Ready")
    var done = false
    var failed = false
    var output: URL? = nil           // compressed copy, for comparing
    var results: [URL] = []          // files (or folders) the last successful run made, for dragging and Quick Look
    var order: [Int]? = nil          // Reorder: original 0-based pages in their new order; nil = unchanged

    var pages: [Int] { selected.isEmpty ? Array(0..<pageCount) : selected.sorted() }
    var pageSummary: String {
        selected.isEmpty ? tr("All %d pages", pageCount) : tr("%d of %d pages", selected.count, pageCount)
    }
    var partsSummary: String {
        let used = parts.reduce(0) { $0 + $1.count }
        return parts.isEmpty ? tr("No pages selected yet")
            : (parts.count == 1 ? tr("1 PDF") : tr("%d PDFs", parts.count)) + " · " + tr("%d of %d pages", used, pageCount)
    }
    var orderSummary: String {
        guard let order else { return tr("Original order") }
        return tr("New order: ") + order.prefix(8).map { String($0 + 1) }.joined(separator: ", ") + (order.count > 8 ? " …" : "")
    }
}

/// What a background job needs to know about a file
struct Job: Sendable {
    let id: UUID
    let url: URL
    let kind: Kind
    let pages: [Int]
    var parts: [[Int]] = []
    var partNames: [String] = []
    var outName: String? = nil      // Word to PDF: file name without extension
}

struct Outcome: Sendable {
    var message: String
    var files: [URL]
    var compareWith: URL? = nil
}

/// Files and results of one tool; every tool keeps its own
struct Workspace {
    var items: [Item] = []
    var summary: String? = nil
    var summaryFailed = false
    var lastOutputs: [URL] = []
}

@MainActor
final class Model: ObservableObject {
    @Published private var spaces: [Tool: Workspace] = [:]
    /// One shared file list for all presets, so the same files can be tried with different presets
    @Published private var presetSpace = Workspace()
    @Published var tool: Tool = .convert { didSet { presetID = nil } }
    @Published var presetID: UUID? = nil     // nil = a tool is shown
    @Published var savePresetTool: Tool? = nil   // set to open the "Save as Preset" sheet
    @Published var editingPresetID: UUID? = nil  // set to open the preset editor
    @Published var presets: [Preset] = [] {
        didSet { if persist { Preset.save(presets) } }
    }
    @Published var outputFolder: URL? = nil   // nil = next to the original
    @Published var busy = false
    @Published var focused: Item.ID? = nil   // PDF whose pages are shown below the list
    @Published var comparing: Item.ID? = nil

    /// The preset shown instead of a tool, if any
    var activePreset: Preset? { presetID.flatMap { id in presets.first { $0.id == id } } }
    private var space: Workspace {
        get { activePreset != nil ? presetSpace : spaces[tool] ?? Workspace() }
        set { if activePreset != nil { presetSpace = newValue } else { spaces[tool] = newValue } }
    }

    var items: [Item] {
        get { space.items }
        set { space.items = newValue }
    }
    var summary: String? {
        get { space.summary }
        set { space.summary = newValue; space.summaryFailed = false }
    }
    /// Set after `summary`: shows it as an error
    var summaryFailed: Bool {
        get { space.summaryFailed }
        set { space.summaryFailed = newValue }
    }
    var lastOutputs: [URL] {
        get { space.lastOutputs }
        set { space.lastOutputs = newValue }
    }

    /// All per-tool settings; saved to UserDefaults on every change
    @Published var settings = ToolSettings() {
        didSet {
            if persist, let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: "settings") }
            if oldValue.renameMode != settings.renameMode { forgetSmartNames() }
        }
    }
    /// Smart Rename: suggested file name (without extension) per file
    @Published var smartNames: [Item.ID: String] = [:]
    /// File shown by Quick Look (⌘Y), if any
    @Published var quickLook: URL? = nil
    @Published var showWatchFolders = false
    @Published var duplicates: [URL] = []
    @Published var pdfPassword = ""   // never stored
    @Published var lastRename: [(from: URL, to: URL)] = []

    /// false = scratch model (preset editor): doesn't read or write settings and presets
    let persist: Bool

    init(persist: Bool = true) {
        self.persist = persist
        guard persist else { return }
        if let saved = Preset.load() {
            presets = saved
        } else {
            presets = Preset.seeded()
            Preset.save(presets)   // observers don't run inside init
        }
        if let d = UserDefaults.standard.data(forKey: "settings"), let s = try? JSONDecoder().decode(ToolSettings.self, from: d) {
            settings = s
        }
    }

    /// Scratch model of the preset editor: show PDF-only options although there are no files
    var forcePDF = false
    var hasPDF: Bool { forcePDF || items.contains { $0.kind == .pdf } }
    var writesFiles: Bool { activePreset != nil || tool.writesFiles }
    var assignsParts: Bool { activePreset == nil && tool == .split && settings.splitMode == .extract }
    /// PDF whose page overview is shown: the clicked one, otherwise the first
    var pageItem: Item? {
        guard activePreset == nil, tool.usesPages || tool == .reorder else { return nil }
        let pdfs = eligible.filter { $0.kind == .pdf }
        return pdfs.first { $0.id == focused } ?? pdfs.first
    }
    var eligible: [Item] {
        if let p = activePreset { return items.filter { p.accepts($0.kind) } }
        return items.filter { tool.accepts($0.kind) }
    }
    var pending: [Item] { eligible.filter { !$0.done } }
    var canRun: Bool {
        if activePreset != nil { return !eligible.isEmpty }
        return switch tool {
        case .rename: settings.renameMode == .smart ? (smartMissing > 0 || renameCount > 0) : renameCount > 0
        case .stitch: eligible.count >= 2
        case .redact: !eligible.isEmpty && (!settings.redactTermList.isEmpty || settings.redactEmails || settings.redactIBANs || settings.redactPhones)
        case .password: !eligible.isEmpty && !pdfPassword.isEmpty
        case .watermark: !eligible.isEmpty && (settings.markKind == .logo ? settings.markLogo != nil : !settings.markText.trimmingCharacters(in: .whitespaces).isEmpty)
        case .duplicates: eligible.count >= 2
        default: !eligible.isEmpty
        }
    }
    /// Duplicates found by the last run that are still in the list
    var duplicatesInList: [URL] {
        let present = Set(items.map { $0.url.standardizedFileURL })
        return duplicates.filter { present.contains($0.standardizedFileURL) }
    }
    func clearList() { items.removeAll(); summary = nil; lastRename = []; duplicates = []; smartNames = [:] }

    /// Files of the last run plus the results kept on the rows, for Quick Look
    var previewURLs: [URL] {
        var seen = Set<URL>()
        return (lastOutputs + items.flatMap(\.results)).filter { seen.insert($0).inserted }
    }

    // MARK: Presets

    /// Shows the presets with these files and doesn't run anything: the current preset, otherwise the first
    func openPresets(_ urls: [URL]) {
        if activePreset == nil { presetID = presets.first?.id }
        add(urls)
    }

    /// Saves one tool with the given settings as a new preset, or as the last step of an existing one
    func savePreset(name: String, tool: Tool, settings: ToolSettings, addingTo id: UUID? = nil) {
        let step = PresetStep(tool: tool, settings: settings)
        if let id, let i = presets.firstIndex(where: { $0.id == id }) {
            presets[i].steps.append(step)
        } else {
            presets.append(Preset(name: name, steps: [step]))
        }
    }

    func updatePreset(_ p: Preset) {
        if let i = presets.firstIndex(where: { $0.id == p.id }) { presets[i] = p }
    }

    func duplicatePreset(_ id: UUID) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        var copy = presets[i]
        copy.id = UUID()
        copy.name += " " + tr("copy")
        copy.steps = copy.steps.map { var s = $0; s.id = UUID(); return s }
        presets.insert(copy, at: i + 1)
    }

    func deletePreset(_ id: UUID) {
        if presetID == id { presetID = nil }
        presets.removeAll { $0.id == id }
    }

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
        var existing = Set(items.map { $0.url.standardizedFileURL })
        for u in expanded where existing.insert(u.standardizedFileURL).inserted {
            guard let kind = Kind(url: u) else { continue }
            if kind == .pdf {
                if let doc = PDFDocument(url: u), (doc.pageCount > 0 || doc.isLocked) {
                    items.append(Item(url: u, kind: .pdf, pageCount: max(1, doc.pageCount), date: Self.date(of: u, kind: .pdf)))
                }
            } else {
                items.append(Item(url: u, kind: kind, date: Self.date(of: u, kind: kind)))
            }
        }
    }

    func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.allowedContentTypes = [.image, .pdf, .movie, .folder] + WordOps.extensions.compactMap { UTType(filenameExtension: $0) }
        if p.runModal() == .OK { add(p.urls) }
    }

    func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.prompt = tr("Choose")
        if p.runModal() == .OK { outputFolder = p.url }
    }

    func remove(_ id: Item.ID) { items.removeAll { $0.id == id }; smartNames[id] = nil }

    enum SortOrder { case name, date }
    func sort(_ order: SortOrder) {
        switch order {
        case .name: items.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        case .date: items.sort { $0.date < $1.date }
        }
    }

    func resetStatus() {
        for i in items.indices {
            items[i].status = tr("Ready"); items[i].done = false; items[i].failed = false; items[i].output = nil; items[i].results = []
        }
        summary = nil
        lastOutputs = []
        duplicates = []
    }

    func update(_ id: Item.ID, _ f: (inout Item) -> Void) {
        if let i = items.firstIndex(where: { $0.id == id }) { f(&items[i]) }
    }

    func pickLogo() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        if p.runModal() == .OK { settings.markLogo = p.url }
    }

    func showInFinder() { NSWorkspace.shared.activateFileViewerSelecting(lastOutputs) }

    // MARK: Running

    func run() {
        if let p = activePreset { runPreset(p); return }
        if pending.isEmpty && tool != .rename { resetStatus() }   // "… Again"
        summary = nil
        lastOutputs = []
        let folder = outputFolder
        switch tool {
        case .wordToPDF:
            guard WordOps.isInstalled else {
                summary = tr("Microsoft Word is needed for this"); summaryFailed = true
                return
            }
            let wasRunning = WordOps.isRunning
            WordOps.stuck = false
            let s = settings
            runEach({ job, progress in try Steps.perform(.wordToPDF, s, job, folder: folder, progress: progress) },
                    finally: { if !wasRunning { WordOps.quitIfIdle() } })
        case .contactSheet: makeContactSheet()
        case .stitch: stitch()
        case .duplicates: findDuplicates()
        case .combine: combine()
        case .rename:
            if settings.renameMode == .smart && smartMissing > 0 { suggestNames() } else { rename() }
        default:
            let s = settings, pw = pdfPassword, tool = tool
            runEach { job, progress in try Steps.perform(tool, s, job, folder: folder, password: pw, progress: progress) }
        }
    }

    private func runPreset(_ p: Preset) {
        if pending.isEmpty { resetStatus() }
        summary = nil
        lastOutputs = []
        let folder = outputFolder
        var quit = false
        if p.steps.contains(where: { $0.tool == .wordToPDF }), eligible.contains(where: { $0.kind == .word }) {
            guard WordOps.isInstalled else {
                summary = tr("Microsoft Word is needed for this"); summaryFailed = true
                return
            }
            quit = !WordOps.isRunning
            WordOps.stuck = false
        }
        let quitWord = quit
        runEach({ job, progress in try Steps.runPreset(p, job, folder: folder, progress: progress) },
                finally: { if quitWord { WordOps.quitIfIdle() } })
    }

    /// Runs `work` for every eligible file in the background, one after another
    private func runEach(_ work: @escaping @Sendable (Job, @escaping @Sendable (String) -> Void) throws -> Outcome,
                         finally: @escaping @Sendable () -> Void = {}) {
        let plain = activePreset == nil
        let reorder = plain && tool == .reorder
        let names = plain && tool == .wordToPDF ? wordNames() : [:]
        let jobs = pending.map {
            Job(id: $0.id, url: $0.url, kind: $0.kind,
                pages: reorder ? $0.order ?? Array(0..<$0.pageCount) : $0.pages, parts: $0.parts, partNames: $0.partNames,
                outName: names[$0.id])
        }
        guard !jobs.isEmpty else { return }
        busy = true
        Task.detached {
            for job in jobs {
                await MainActor.run { self.update(job.id) { $0.status = tr("Working…") } }
                let progress: @Sendable (String) -> Void = { msg in
                    Task { @MainActor in self.update(job.id) { if !$0.done && !$0.failed { $0.status = msg } } }
                }
                let result = Result { try work(job, progress) }
                await MainActor.run {
                    if case .success(let o) = result { self.lastOutputs += o.files }
                    self.update(job.id) {
                        switch result {
                        case .success(let o):
                            $0.status = "✓ " + o.message; $0.done = true; $0.output = o.compareWith; $0.results = o.files
                        case .failure(let e as Skipped):
                            $0.status = e.localizedDescription; $0.done = true
                        case .failure(let e):
                            $0.status = tr("Error: ") + e.localizedDescription; $0.failed = true
                        }
                    }
                }
            }
            finally()
            await MainActor.run {
                self.summarize(jobs.map(\.id))
                self.busy = false
            }
        }
    }

    /// Size of a file, or of everything inside a folder
    nonisolated private static func sizeOnDisk(_ u: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else { return fileSize(u) }
        let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil)
        var total: Int64 = 0
        while let f = e?.nextObject() as? URL { total += fileSize(f) }
        return total
    }

    /// "12 done, 1 skipped · 48 MB saved (−63 %)" for the files of the run that just ended
    private func summarize(_ ids: [Item.ID]) {
        let ran = items.filter { ids.contains($0.id) }
        let ok = ran.filter { $0.done && !$0.results.isEmpty }
        let skipped = ran.filter { $0.done && $0.results.isEmpty }.count
        let failed = ran.filter { $0.failed }.count
        var parts: [String] = []
        if !ok.isEmpty { parts.append(tr("%d done", ok.count)) }
        if skipped > 0 { parts.append(tr("%d skipped", skipped)) }
        if failed > 0 { parts.append(tr("%d failed", failed)) }
        guard !parts.isEmpty else { return }
        var text = parts.joined(separator: ", ")
        if !ok.isEmpty {
            let before = ok.reduce(Int64(0)) { $0 + Self.sizeOnDisk($1.url) }
            let after = ok.reduce(Int64(0)) { $0 + $1.results.reduce(Int64(0)) { $0 + Self.sizeOnDisk($1) } }
            // "Saved" only makes sense when the output is the same content, smaller (Compress, Resize, ...), not CSV or GIF
            let shrinkTools: [Tool] = [.compress, .resize, .strip, .convert]
            if after < before, before > 0, activePreset != nil || shrinkTools.contains(tool) {
                text += " · " + tr("%@ saved (−%d %%)", fmtSize(before - after), Int((Double(before - after) / Double(before) * 100).rounded()))
            } else if after > 0 {
                text += " · " + fmtSize(after)
            }
        }
        summary = text
        if ok.isEmpty && skipped == 0 { summaryFailed = true }
    }

    // MARK: Combine

    private func combine() {
        let parts = eligible
        guard !parts.isEmpty else { return }
        let name = settings.combinedName.trimmingCharacters(in: .whitespaces).isEmpty ? tr("Combined") : settings.combinedName
        let out = uniqueURL(outputFolder ?? parts[0].url.deletingLastPathComponent(), name, "pdf")
        let entries = parts.map { (url: $0.url, kind: $0.kind) }
        let pageSize = settings.pageSize, margin = settings.pageMargin
        for p in parts { update(p.id) { $0.status = tr("Waiting…"); $0.done = false; $0.failed = false } }
        busy = true
        Task.detached {
            let result = Result {
                try PDFOps.combine(entries, pageSize: pageSize, margin: margin, to: out) { n in
                    let id = parts[n - 1].id
                    Task { @MainActor in self.update(id) { $0.status = tr("Adding…") } }
                }
            }
            await MainActor.run {
                switch result {
                case .success(let pages):
                    for p in parts { self.update(p.id) { $0.status = "✓ " + tr("Added"); $0.done = true } }
                    self.summary = tr("Created “%@”: %d pages, %@", out.lastPathComponent, pages, fmtSize(fileSize(out)))
                    self.lastOutputs = [out]
                case .failure(let e):
                    for p in parts { self.update(p.id) { $0.status = tr("Ready") } }
                    self.summary = tr("Error: ") + e.localizedDescription; self.summaryFailed = true
                }
                self.busy = false
            }
        }
    }

    // MARK: Contact sheet

    private func makeContactSheet() {
        let parts = eligible
        guard !parts.isEmpty else { return }
        let trimmed = settings.sheetName.trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? tr("Contact Sheet") : trimmed
        let format = settings.sheetFormat
        let out = uniqueURL(outputFolder ?? parts[0].url.deletingLastPathComponent(), name, format == .pdf ? "pdf" : "jpg")
        let urls = parts.map { $0.url }
        let columns = settings.sheetColumns, names = settings.sheetNames
        for p in parts { update(p.id) { $0.status = tr("Waiting…"); $0.done = false; $0.failed = false } }
        busy = true
        Task.detached {
            let result = Result {
                try PhotoOps.contactSheet(urls, columns: columns, names: names, format: format, to: out) { n in
                    let id = parts[n - 1].id
                    Task { @MainActor in self.update(id) { $0.status = tr("Adding…") } }
                }
            }
            await MainActor.run {
                switch result {
                case .success(let pages):
                    for p in parts { self.update(p.id) { $0.status = "✓ " + tr("Added"); $0.done = true } }
                    self.summary = format == .pdf
                        ? tr("Created “%@”: %d pages, %@", out.lastPathComponent, pages, fmtSize(fileSize(out)))
                        : tr("Created “%@”, %@", out.lastPathComponent, fmtSize(fileSize(out)))
                    self.lastOutputs = [out]
                case .failure(let e):
                    for p in parts { self.update(p.id) { $0.status = tr("Ready") } }
                    self.summary = tr("Error: ") + e.localizedDescription; self.summaryFailed = true
                }
                self.busy = false
            }
        }
    }

    // MARK: Stitch

    private func stitch() {
        let parts = eligible
        guard parts.count >= 2 else { return }
        let trimmed = settings.stitchName.trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? tr("Stitched") : trimmed
        let format = settings.stitchFormat
        let out = uniqueURL(outputFolder ?? parts[0].url.deletingLastPathComponent(), name, format == .png ? "png" : "jpg")
        let urls = parts.map { $0.url }
        let direction = settings.stitchDirection, spacing = settings.stitchSpacing
        for p in parts { update(p.id) { $0.status = tr("Waiting…"); $0.done = false; $0.failed = false } }
        busy = true
        Task.detached {
            let result = Result {
                try Stitch.run(urls, direction: direction, spacing: spacing, format: format, to: out) { n in
                    let id = parts[n - 1].id
                    Task { @MainActor in self.update(id) { $0.status = tr("Adding…") } }
                }
            }
            await MainActor.run {
                switch result {
                case .success(let size):
                    for p in parts { self.update(p.id) { $0.status = "✓ " + tr("Added"); $0.done = true } }
                    self.summary = tr("Created “%@”: %d × %d px, %@", out.lastPathComponent, size.w, size.h, fmtSize(fileSize(out)))
                    self.lastOutputs = [out]
                case .failure(let e):
                    for p in parts { self.update(p.id) { $0.status = tr("Ready") } }
                    self.summary = tr("Error: ") + e.localizedDescription; self.summaryFailed = true
                }
                self.busy = false
            }
        }
    }

    // MARK: Find duplicates

    private func findDuplicates() {
        let parts = eligible
        guard parts.count >= 2 else { return }
        let urls = parts.map { $0.url }
        let mode = settings.duplicateMode
        duplicates = []
        for p in parts { update(p.id) { $0.status = tr("Waiting…"); $0.done = false; $0.failed = false } }
        busy = true
        Task.detached {
            let result = Result {
                try PhotoOps.findDuplicates(urls, mode: mode) { n in
                    let id = parts[n - 1].id
                    Task { @MainActor in self.update(id) { $0.status = tr("Checking…") } }
                }
            }
            await MainActor.run {
                switch result {
                case .success(let map):
                    let keepers = Set(map.values)
                    for (i, p) in parts.enumerated() {
                        self.update(p.id) {
                            if let k = map[i] {
                                let other = parts[k].url.lastPathComponent
                                $0.status = mode == .exact ? tr("Same as “%@”", other) : tr("Looks like “%@”", other)
                            } else {
                                $0.status = keepers.contains(i) ? "✓ " + tr("Kept") : tr("Unique")
                            }
                            $0.done = true
                        }
                    }
                    self.duplicates = map.keys.sorted().map { parts[$0].url }
                    self.summary = map.isEmpty ? tr("No duplicates found") : map.count == 1 ? tr("1 duplicate found") : tr("%d duplicates found", map.count)
                case .failure(let e):
                    for p in parts { self.update(p.id) { $0.status = tr("Ready") } }
                    self.summary = tr("Error: ") + e.localizedDescription; self.summaryFailed = true
                }
                self.busy = false
            }
        }
    }

    /// Moves the found duplicates to the Trash (recoverable) and takes them off the list
    func moveDuplicatesToTrash() {
        let urls = duplicatesInList
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { trashed, error in
            Task { @MainActor in
                let gone = Set(trashed.keys.map { $0.standardizedFileURL })
                self.items.removeAll { gone.contains($0.url.standardizedFileURL) }
                self.duplicates.removeAll { gone.contains($0.standardizedFileURL) }
                if let error, trashed.count < urls.count {
                    self.summary = tr("Error: ") + error.localizedDescription; self.summaryFailed = true
                } else {
                    self.summary = trashed.count == 1 ? tr("Moved 1 file to the Trash") : tr("Moved %d files to the Trash", trashed.count)
                }
            }
        }
    }

    // MARK: Import from iPhone

    private static let scanDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Saves scans and photos from Continuity Camera as files and adds them to the list
    func importScans(_ providers: [NSItemProvider]) {
        let dir = outputFolder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        for p in providers {
            let isPDF = p.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            guard let type = isPDF ? UTType.pdf : p.registeredTypeIdentifiers.compactMap({ UTType($0) }).first(where: { $0.conforms(to: .image) }) else { continue }
            p.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    let name = "Scan " + Self.scanDate.string(from: Date())
                    let url = uniqueURL(dir, name, type.preferredFilenameExtension ?? (isPDF ? "pdf" : "jpg"))
                    do {
                        try data.write(to: url)
                        self.add([url])
                    } catch {
                        self.summary = tr("Error: ") + error.localizedDescription; self.summaryFailed = true
                    }
                }
            }
        }
    }

    // MARK: Word to PDF

    /// PDF name (without .pdf) for every Word document, numbered in list order
    func wordNames() -> [Item.ID: String] {
        let docs = eligible
        let last = settings.wordStart + docs.count - 1
        let pattern = settings.wordPattern.trimmingCharacters(in: .whitespaces)
        var result: [Item.ID: String] = [:]
        for (n, it) in docs.enumerated() {
            let stem = it.url.deletingPathExtension().lastPathComponent
            switch settings.wordNaming {
            case .keep: result[it.id] = stem
            case .affix: result[it.id] = settings.wordPrefix + stem + settings.wordSuffix
            case .numbered: result[it.id] = pattern.isEmpty ? stem : Self.renamed(pattern, number: settings.wordStart + n, last: last)
            }
        }
        return result
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

    // MARK: Smart rename

    /// Files that still need a suggested name
    var smartMissing: Int { items.filter { smartNames[$0.id] == nil }.count }

    private func forgetSmartNames() {
        smartNames = [:]
        if var w = spaces[.rename] {
            for i in w.items.indices where !w.items[i].done { w.items[i].status = tr("Ready"); w.items[i].failed = false }
            spaces[.rename] = w
        }
    }

    /// Reads every file without a suggestion (in the background) and proposes a name; nothing is renamed yet
    private func suggestNames() {
        let todo = items.filter { smartNames[$0.id] == nil }.map { (id: $0.id, url: $0.url, kind: $0.kind, date: $0.date) }
        guard !todo.isEmpty else { return }
        summary = nil
        for t in todo { update(t.id) { $0.status = tr("Waiting…"); $0.done = false; $0.failed = false } }
        busy = true
        Task.detached {
            for t in todo {
                await MainActor.run { self.update(t.id) { $0.status = tr("Reading…") } }
                let result = Result { try SmartName.suggest(t.url, kind: t.kind, fallbackDate: t.date) }
                await MainActor.run {
                    switch result {
                    case .success(let stem):
                        self.smartNames[t.id] = stem
                        self.update(t.id) { $0.status = tr("Suggested") }
                    case .failure(let e):
                        self.update(t.id) { $0.status = tr("Error: ") + e.localizedDescription; $0.failed = true }
                    }
                }
            }
            await MainActor.run {
                let suggested = todo.filter { self.smartNames[$0.id] != nil }.count
                if suggested > 0 {
                    self.summary = suggested == 1 ? tr("1 name suggested. Check it, then click Rename.")
                        : tr("%d names suggested. Check them, then click Rename.", suggested)
                }
                self.busy = false
            }
        }
    }

    /// New file name for every file, in list order
    func renamePreview() -> [Item.ID: String] {
        if settings.renameMode == .smart {
            var used: [String: Int] = [:]
            var result: [Item.ID: String] = [:]
            for it in items {
                guard let stem = smartNames[it.id] else { continue }
                let ext = it.url.pathExtension
                let key = it.url.deletingLastPathComponent().path + "/" + stem.lowercased() + "." + ext.lowercased()
                let n = (used[key] ?? 0) + 1
                used[key] = n
                result[it.id] = stem + (n > 1 ? "-\(n)" : "") + (ext.isEmpty ? "" : "." + ext)
            }
            return result
        }
        let pattern = settings.renamePattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return [:] }
        let last = settings.renameStart + items.count - 1
        var result: [Item.ID: String] = [:]
        for (n, it) in items.enumerated() {
            let ext = it.url.pathExtension
            result[it.id] = Self.renamed(pattern, number: settings.renameStart + n, last: last) + (ext.isEmpty ? "" : "." + ext)
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
                update(m.id) { $0.status = tr("Error: ") + tr("“%@” already exists", m.to.lastPathComponent); $0.failed = true }
                summary = tr("Nothing renamed: a file with one of the new names already exists"); summaryFailed = true
                return
            }
            targets.insert(t)
        }
        do {
            try Self.moveAll(moves.map { ($0.from, $0.to) })
        } catch {
            summary = tr("Nothing renamed: ") + error.localizedDescription; summaryFailed = true
            return
        }
        for m in moves {
            update(m.id) { $0.url = m.to; $0.status = tr("✓ was “%@”", m.from.lastPathComponent); $0.done = true; $0.failed = false }
        }
        lastRename = moves.map { ($0.to, $0.from) }
        lastOutputs = moves.map { $0.to }
        summary = moves.count == 1 ? tr("Renamed 1 file") : tr("Renamed %d files", moves.count)
    }

    func undoRename() {
        let moves = lastRename
        do {
            try Self.moveAll(moves)
        } catch {
            summary = tr("Undo failed: ") + error.localizedDescription; summaryFailed = true
            return
        }
        for m in moves {
            if let i = items.firstIndex(where: { $0.url == m.from }) {
                items[i].url = m.to; items[i].status = tr("Ready"); items[i].done = false
            }
        }
        lastRename = []
        lastOutputs = []
        summary = tr("Original names restored")
    }
}
