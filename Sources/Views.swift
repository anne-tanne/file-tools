import QuickLook
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable { case tool(Tool), favorite(Tool), preset(UUID) }

struct ContentView: View {
    @StateObject var m: Model
    @State private var deleting: Preset?
    /// The current tool was picked in Favorites, so that row is highlighted instead of its twin below
    @State private var pickedFavorite = false

    @MainActor init(model: Model? = nil) { _m = StateObject(wrappedValue: model ?? Model()) }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                if !favorites.isEmpty {
                    section("Favorites", "favorites") {
                        ForEach(favorites) { t in toolLabel(t).tag(SidebarItem.favorite(t)) }
                    }
                }
                section("Convert & Compress", "convert") { toolRows([.convert, .compress, .resize, .videoToGIF]) }
                section("Photos", "photos") { toolRows([.crop, .removeBackground, .watermark, .blackWhite, .iconSet, .contactSheet, .stitch, .cleanScan, .duplicates]) }
                section("Edit", "edit") { toolRows([.rotate, .strip, .rename, .recognizeText]) }
                section("PDF", "pdf") { toolRows([.wordToPDF, .combine, .split, .reorder, .extractImages, .makeSearchable, .pageNumbers, .password, .flatten, .redact, .extractTables]) }
                if !m.presets.isEmpty {
                    section("Presets", "presets") {
                        ForEach(m.presets) { p in
                            Label(p.name, systemImage: "star").tag(SidebarItem.preset(p.id))
                                .contextMenu {
                                    Button("Edit…") { m.editingPresetID = p.id }
                                    Button("Duplicate") { m.duplicatePreset(p.id) }
                                    Button("Watch Folders…") { m.showWatchFolders = true }
                                    Divider()
                                    Button("Delete…", role: .destructive) { deleting = p }
                                }
                        }
                    }
                }
            }
            .disabled(m.busy)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            ToolView()
        }
        .environmentObject(m)
        .focusedSceneObject(m)
        .frame(minWidth: 880, minHeight: 580)
        .importsItemProviders([.image, .pdf]) { m.importScans($0); return true }
        .sheet(item: $m.savePresetTool) { SavePresetSheet(tool: $0).environmentObject(m) }
        .sheet(item: Binding(get: { m.editingPresetID.flatMap { id in m.presets.first { $0.id == id } } },
                             set: { m.editingPresetID = $0?.id })) { EditPresetSheet(preset: $0).environmentObject(m) }
        .confirmationDialog("Delete this preset?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { p in
            Button("Delete “\(p.name)”", role: .destructive) { m.deletePreset(p.id) }
        } message: { _ in
            Text("The preset is removed. Your files are not touched.")
        }
        .sheet(isPresented: $m.showWatchFolders) { WatchFoldersSheet().environmentObject(m) }
        .sheet(item: Binding(get: { m.items.first { $0.id == m.comparing && $0.output != nil } }, set: { m.comparing = $0?.id })) { it in
            CompareView(original: it.url, compressed: it.output!, isPDF: it.kind == .pdf) {
                try? FileManager.default.removeItem(at: it.output!)
                m.lastOutputs.removeAll { $0 == it.output }
                m.update(it.id) { $0.output = nil; $0.results = []; $0.done = false; $0.status = "Compressed copy deleted" }
            }
        }
    }

    /// Sidebar sections the user folded away, remembered across launches
    @AppStorage("collapsedSections") private var collapsed = ""

    func expanded(_ key: String) -> Binding<Bool> {
        Binding(get: { !collapsed.split(separator: "|").contains(Substring(key)) }, set: { open in
            var keys = Set(collapsed.split(separator: "|").map(String.init))
            if open { keys.remove(key) } else { keys.insert(key) }
            collapsed = keys.sorted().joined(separator: "|")
        })
    }

    /// Collapsible sidebar section whose whole header toggles it, not only the small chevron
    func section<C: View>(_ title: LocalizedStringKey, _ key: String, @ViewBuilder _ content: () -> C) -> some View {
        let open = expanded(key)
        return Section(isExpanded: open) { content() } header: {
            Text(title).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .onTapGesture { withAnimation { open.wrappedValue.toggle() } }
        }
    }

    var selection: Binding<SidebarItem?> {
        Binding(get: {
            if let p = m.activePreset { return .preset(p.id) }
            return pickedFavorite && favorites.contains(m.tool) ? .favorite(m.tool) : .tool(m.tool)
        }, set: {
            switch $0 {
            case .tool(let t): pickedFavorite = false; m.tool = t
            case .favorite(let t): pickedFavorite = true; m.tool = t
            case .preset(let id): m.presetID = id
            case nil: break
            }
        })
    }

    /// Favourite tools in the order they were added, remembered across launches
    @AppStorage("favoriteTools") private var favoriteKeys = ""

    var favorites: [Tool] { favoriteKeys.split(separator: "|").compactMap { Tool(rawValue: String($0)) } }

    func toggleFavorite(_ t: Tool) {
        var list = favorites
        if let i = list.firstIndex(of: t) { list.remove(at: i) } else { list.append(t) }
        favoriteKeys = list.map(\.rawValue).joined(separator: "|")
    }

    func toolLabel(_ t: Tool) -> some View {
        Label(t.rawValue, systemImage: t.icon)
            .contextMenu {
                Button(favorites.contains(t) ? "Remove from Favorites" : "Add to Favorites") { toggleFavorite(t) }
            }
    }

    func toolRows(_ tools: [Tool]) -> some View {
        ForEach(tools) { t in toolLabel(t).tag(SidebarItem.tool(t)) }
    }
}

struct ToolView: View {
    @EnvironmentObject var m: Model
    @State private var targeted = false

    var body: some View {
        stack
            .padding(20)
            .navigationTitle(m.activePreset?.name ?? m.tool.title)
            .navigationSubtitle(m.activePreset.map { tr("Preset · ") + ($0.steps.count == 1 ? tr("1 step") : tr("%d steps", $0.steps.count)) } ?? m.tool.subtitle)
            .toolbar { toolbar }
            .quickLookPreview($m.quickLook, in: m.previewURLs)
    }

    @ViewBuilder var stack: some View {
        let preview = m.tool == .rename ? m.renamePreview() : m.tool == .wordToPDF ? m.wordNames().mapValues { $0 + ".pdf" } : [:]
        VStack(alignment: .leading, spacing: 14) {
            if let it = m.pageItem {
                // List shrinks to what it needs, the page overview gets the free space
                dropZone(preview)
                    .frame(height: min(CGFloat(m.items.count) * 30 + 16, 150))
                pagePanel(it)
                    .layoutPriority(1)
            } else {
                dropZone(preview)
                    .frame(minHeight: 220)
                    .layoutPriority(1)   // the list gets the free space, settings only what they need
            }

            if let p = m.activePreset {
                presetSteps(p)
            } else {
                ToolSettingsView(tool: m.tool)
            }

            if m.writesFiles {
                HStack {
                    Label("Save to", systemImage: "folder").labelStyle(.titleAndIcon)
                    Text(m.outputFolder?.path ?? "Same folder as original")
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if m.outputFolder != nil { Button("Use Original Folder") { m.outputFolder = nil } }
                    Button("Choose Folder…") { m.pickFolder() }
                }
            }

            Divider()

            bottomBar
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { m.pickFiles() } label: { Label("Add Files", systemImage: "plus") }
                .help("Add photos, PDFs or folders (⌘O)")
                .disabled(m.busy)
            Menu {
                Button("By Name") { m.sort(.name) }
                Button("By Date Taken") { m.sort(.date) }
                Divider()
                Button("Reverse Order") { m.items.reverse() }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort the list")
            .disabled(m.busy || m.items.count < 2)
            Button { m.clearList() } label: { Label("Clear List", systemImage: "trash") }
                .help("Remove all files from the list. The files themselves are not touched.")
                .disabled(m.busy || m.items.isEmpty)
        }
        if m.activePreset == nil && m.tool.isChainable {
            ToolbarItem(placement: .primaryAction) {
                Button { m.savePresetTool = m.tool } label: { Label("Save as Preset…", systemImage: "star.square.on.square") }
                    .help("Save this tool and its settings as a preset")
                    .disabled(m.busy)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { m.quickLook = m.previewURLs.first } label: { Label("Quick Look", systemImage: "eye") }
                .help("Preview the new files (⌘Y)")
                .disabled(m.busy || m.previewURLs.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { m.showInFinder() } label: { Label("Show in Finder", systemImage: "finder") }
                .help("Show the new files in Finder (⇧⌘R)")
                .disabled(m.busy || m.lastOutputs.isEmpty)
        }
    }

    // MARK: File list

    func dropZone(_ preview: [Item.ID: String]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            if m.items.isEmpty {
                shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
                ContentUnavailableView {
                    Label(dropHint, systemImage: m.activePreset != nil ? "star" : m.tool.icon)
                } actions: {
                    Button("Choose Files…") { m.pickFiles() }
                }
            } else {
                shape.fill(.fill.quinary)
                shape.strokeBorder(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: targeted ? 2 : 1)
                List(selection: Binding(get: { m.pageItem?.id ?? m.focused }, set: { m.focused = $0 })) {
                    ForEach(m.items) { it in row(it, preview: preview).tag(it.id) }
                        .onMove { m.items.move(fromOffsets: $0, toOffset: $1) }
                }
                .scrollContentBackground(.hidden)
                .padding(6)
            }
        }
        .background(targeted ? AnyShapeStyle(Color.accentColor.opacity(0.08)) : AnyShapeStyle(.clear), in: shape)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in m.add([url]) } }
                }
            }
            return true
        }
    }

    var dropHint: String {
        if m.activePreset != nil { return "Drop photos, PDFs or folders here" }
        return switch m.tool {
        case .resize, .crop, .removeBackground, .iconSet, .contactSheet, .duplicates, .stitch, .cleanScan: "Drop photos or folders here"
        case .videoToGIF: "Drop videos here"
        case .compress: "Drop photos, PDFs, videos or folders here"
        case .split, .reorder, .extractImages, .pageNumbers, .password, .flatten: "Drop PDFs here"
        case .wordToPDF: "Drop Word documents or folders here"
        default: "Drop photos, PDFs or folders here"
        }
    }

    func rowIcon(_ it: Item, usable: Bool) -> String {
        if it.done && usable { return "checkmark.circle.fill" }
        if it.failed { return "xmark.octagon.fill" }
        switch it.kind {
        case .pdf: return "doc.richtext"
        case .word: return "doc.text"
        case .video: return "film"
        case .image: return "photo"
        }
    }

    @ViewBuilder func row(_ it: Item, preview: [Item.ID: String]) -> some View {
        let preset = m.activePreset
        let usable = preset?.accepts(it.kind) ?? m.tool.accepts(it.kind)
        HStack(spacing: 8) {
            Image(systemName: rowIcon(it, usable: usable))
                .foregroundStyle(it.done && usable ? .green : it.failed ? .red : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(it.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            if usable && it.kind == .pdf && m.assignsParts {
                HStack(spacing: 3) {
                    ForEach(it.parts.indices, id: \.self) { Circle().fill(partColor($0)).frame(width: 8, height: 8) }
                }
                Text(it.partsSummary).font(.caption).foregroundStyle(.secondary)
            } else if usable && it.kind == .pdf && preset == nil && m.tool.usesPages {
                Text(it.pageSummary).font(.caption).foregroundStyle(.secondary)
            } else if usable && preset == nil && m.tool == .reorder {
                Text(it.orderSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if preset == nil, m.tool == .rename || m.tool == .wordToPDF, usable, !it.done, let new = preview[it.id], new != it.url.lastPathComponent {
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Text(new).foregroundStyle(Color.accentColor).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(usable ? it.status : "Not used by this tool")
                .foregroundStyle(it.failed ? Color.red : .secondary).font(.caption).lineLimit(1)
            if preset == nil, m.tool == .compress, it.output != nil {
                Button("Compare") { m.comparing = it.id }.controlSize(.small)
            }
            if usable, it.done, let first = it.results.first {
                Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                    .onDrag { NSItemProvider(contentsOf: first) ?? NSItemProvider(object: first as NSURL) }
                    .help("Drag the result to another app or folder")
                    .accessibilityLabel("Drag the result to another app or folder")
            }
            Button { m.remove(it.id) } label: { Label("Remove from List", systemImage: "xmark.circle.fill") }
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Remove from list").disabled(m.busy)
        }
        .opacity(usable ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([it.url]) }
            if it.done, !it.results.isEmpty {
                Button("Quick Look Result") { m.quickLook = it.results.first }
                Button("Show Result in Finder") { NSWorkspace.shared.activateFileViewerSelecting(it.results) }
            }
            Divider()
            Button("Remove from List") { m.remove(it.id) }.disabled(m.busy)
        }
    }

    // MARK: Page overview

    /// Pages of the selected PDF, right in the window; changes apply immediately
    @ViewBuilder func pagePanel(_ it: Item) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Group {
            if m.tool == .reorder {
                PageArranger(url: it.url, pageCount: it.pageCount, order: it.order ?? Array(0..<it.pageCount)) { order in
                    m.update(it.id) {
                        $0.order = order == Array(0..<it.pageCount) ? nil : order
                        $0.done = false; $0.failed = false; $0.status = "Ready"
                    }
                }
            } else if m.assignsParts {
                PartsPicker(url: it.url, pageCount: it.pageCount, parts: it.parts, names: it.partNames) { parts, names in
                    m.update(it.id) { $0.parts = parts; $0.partNames = names; $0.done = false; $0.failed = false; $0.status = "Ready" }
                }
            } else {
                PagePicker(url: it.url, pageCount: it.pageCount, selected: it.selected) { sel in
                    m.update(it.id) { $0.selected = sel; $0.done = false; $0.failed = false; $0.status = "Ready" }
                }
            }
        }
        .id("\(it.id)-\(m.tool.rawValue)-\(m.assignsParts)")   // fresh state per PDF and tool
        .disabled(m.busy)
        .padding(14)
        .frame(minHeight: 260)
        .background(.fill.quinary, in: shape)
        .overlay(shape.strokeBorder(.separator))
    }

    // MARK: Preset

    func presetSteps(_ p: Preset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Steps, in this order").font(.headline)
                Spacer()
                Button { m.editingPresetID = p.id } label: { Label("Edit Preset…", systemImage: "slider.horizontal.3") }
                    .disabled(m.busy)
            }
            ForEach(Array(p.steps.enumerated()), id: \.element.id) { n, step in
                HStack(spacing: 8) {
                    Text("\(n + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
                    Label(step.tool.title, systemImage: step.tool.icon)
                    Text(step.settings.summary(for: step.tool)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    Spacer()
                }
            }
        }
    }

    // MARK: Bottom bar

    var bottomBar: some View {
        HStack(spacing: 12) {
            if let s = m.summary {
                let bad = m.summaryFailed || s.hasPrefix("Error") || s.hasPrefix("Nothing")
                Label(s, systemImage: bad ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(bad ? .red : .secondary)
                    .lineLimit(2)
            } else if !m.items.isEmpty {
                Text("\(m.items.count) file\(m.items.count == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
            Spacer()
            if m.busy { ProgressView().controlSize(.small) }
            Button(actionTitle) { m.run() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(m.busy || !m.canRun)
        }
    }

    var actionTitle: String {
        if m.activePreset != nil {
            let n = m.pending.count
            return n == 0 && !m.eligible.isEmpty ? "Run Preset Again" : "Run Preset (\(n))"
        }
        switch m.tool {
        case .combine: return "Create PDF"
        case .rename:
            return m.settings.renameMode == .smart && m.smartMissing > 0 ? "Suggest Names (\(m.smartMissing))" : "Rename (\(m.renameCount))"
        case .contactSheet: return "Create Sheet"
        case .stitch: return "Stitch"
        case .password:
            let n = m.pending.count
            let verb = m.settings.passwordMode == .add ? "Protect" : "Unlock"
            return n == 0 && !m.eligible.isEmpty ? "\(verb) Again" : "\(verb) (\(n))"
        default:
            let n = m.pending.count
            return n == 0 && !m.eligible.isEmpty ? "\(m.tool.action) Again" : "\(m.tool.action) (\(n))"
        }
    }
}

// MARK: - Settings per tool

/// The settings editor of one tool, bound to `m.settings`. Also used inside the preset editor with a scratch model.
struct ToolSettingsView: View {
    @EnvironmentObject var m: Model
    let tool: Tool
    @State private var confirmTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { settings }
    }

    @ViewBuilder var settings: some View {
        switch tool {
        case .convert:
            HStack(spacing: 14) {
                Picker("Format", selection: $m.settings.format) {
                    ForEach(OutFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
                if m.settings.format.isLossy {
                    Text("Quality")
                    Slider(value: $m.settings.quality, in: 0.3...1.0) { Text("Quality") }.labelsHidden().frame(width: 100)
                    Text("\(Int(m.settings.quality * 100)) %").monospacedDigit().frame(width: 40, alignment: .trailing)
                } else {
                    Text(m.settings.format.hint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if m.hasPDF {   // own line: next to format + quality it overflows the minimum window width
                Picker("PDF pages at", selection: $m.settings.dpi) {
                    Text("72 dpi (screen)").tag(72)
                    Text("150 dpi").tag(150)
                    Text("300 dpi (print)").tag(300)
                }
                .fixedSize()
            }
        case .compress:
            HStack(spacing: 14) {
                Picker("Compress by", selection: $m.settings.compressBy) {
                    ForEach(CompressBy.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Divider().frame(height: 18)
                if m.settings.compressBy == .level {
                    Picker("Level", selection: $m.settings.level) {
                        ForEach(Level.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                } else {
                    Text("Smaller than")
                    TextField("Maximum size in MB", value: $m.settings.targetMB, format: .number).labelsHidden().frame(width: 56).multilineTextAlignment(.trailing)
                    Text("MB")
                }
                Spacer()
            }
            Text(m.settings.compressBy == .level ? m.settings.level.hint : "Tries gentle settings first and only goes further when needed")
                .font(.caption).foregroundStyle(.secondary)
        case .resize:
            HStack(spacing: 10) {
                Picker("Resize by", selection: $m.settings.resizeMode) {
                    ForEach(ResizeMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().fixedSize()
                .onChange(of: m.settings.resizeMode) { _, new in
                    if new == .percent { m.settings.resizeValue = 50 } else if m.settings.resizeValue <= 100 { m.settings.resizeValue = 2000 }
                }
                TextField("Size", value: $m.settings.resizeValue, format: .number).labelsHidden().frame(width: 70).multilineTextAlignment(.trailing)
                Text(m.settings.resizeMode == .percent ? "%" : "pixels")
                Text("Only makes photos smaller. Format and photo info are kept.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        case .rotate:
            HStack(spacing: 14) {
                Picker("Rotation", selection: $m.settings.rotation) {
                    Label("90° right", systemImage: "rotate.right").tag(90)
                    Label("180°", systemImage: "arrow.uturn.down").tag(180)
                    Label("90° left", systemImage: "rotate.left").tag(270)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Text(m.hasPDF ? "For PDFs, only the selected pages are turned (all if none selected)" : "")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        case .strip:
            HStack(spacing: 14) {
                Picker("Remove", selection: $m.settings.stripMode) {
                    ForEach(StripMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Text(m.settings.stripMode == .all
                     ? "Removes camera, date and location. The image itself stays exactly the same."
                     : "Removes only where the photo was taken. The image itself stays exactly the same.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if m.hasPDF {
                Text("For PDFs, removes author, title and other document info.").font(.caption).foregroundStyle(.secondary)
            }
        case .rename:
            HStack(spacing: 10) {
                Picker("Names", selection: $m.settings.renameMode) {
                    ForEach(RenameMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                if !m.lastRename.isEmpty {
                    Button("Undo Rename") { m.undoRename() }.disabled(m.busy)
                }
            }
            if m.settings.renameMode == .numbered {
                HStack(spacing: 10) {
                    Text("New name")
                    TextField("New name", text: $m.settings.renamePattern, prompt: Text("Photo ###")).labelsHidden().frame(width: 200)
                    Stepper("starting at \(m.settings.renameStart)", value: $m.settings.renameStart, in: 0...99999)
                    Spacer()
                }
                Text("# is replaced by the number (### → 001). Files are renamed in place, in list order. Drag to reorder or use Sort.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Names like 261014-SwisscomInvoice.pdf, from each file's date and content. Click Suggest Names, check them, then Rename.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .combine:
            HStack(spacing: 10) {
                Text("Name")
                TextField("Name", text: $m.settings.combinedName, prompt: Text("Combined")).labelsHidden().frame(width: 180)
                Text(".pdf").foregroundStyle(.secondary)
                Divider().frame(height: 18)
                Picker("Photo pages", selection: $m.settings.pageSize) {
                    ForEach(PageSize.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                Toggle("Margin", isOn: $m.settings.pageMargin)
                Spacer()
            }
            Text("Files are added in list order. Drag to reorder or use Sort. PDF pages are added unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        case .split:
            HStack(spacing: 14) {
                Picker("Split mode", selection: $m.settings.splitMode) {
                    ForEach(SplitMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if m.settings.splitMode == .chunks {
                    Stepper("\(m.settings.chunkSize) pages each", value: $m.settings.chunkSize, in: 1...999)
                }
                Spacer()
            }
            Text(splitHint).font(.caption).foregroundStyle(.secondary)
        case .reorder:
            Text("Drag the pages above into the order you want. Click another PDF in the list to arrange its pages. The PDF is saved as a new file.")
                .font(.caption).foregroundStyle(.secondary)
        case .wordToPDF:
            HStack(spacing: 10) {
                Picker("PDF names", selection: $m.settings.wordNaming) {
                    ForEach(WordNaming.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                switch m.settings.wordNaming {
                case .keep:
                    EmptyView()
                case .affix:
                    TextField("Text before", text: $m.settings.wordPrefix, prompt: Text("Before")).labelsHidden().frame(width: 110)
                    Text("name").foregroundStyle(.secondary)
                    TextField("Text after", text: $m.settings.wordSuffix, prompt: Text("After")).labelsHidden().frame(width: 110)
                case .numbered:
                    TextField("New name", text: $m.settings.wordPattern, prompt: Text("Document ###")).labelsHidden().frame(width: 180)
                    Stepper("starting at \(m.settings.wordStart)", value: $m.settings.wordStart, in: 0...99999)
                }
                Spacer()
            }
            Text(wordHint).font(.caption).foregroundStyle(.secondary)
        case .crop:
            HStack(spacing: 14) {
                Picker("Shape", selection: $m.settings.cropAspect) {
                    ForEach(CropAspect.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            Text(m.settings.cropAspect == .trim
                 ? "Cuts away plain borders of one colour around the picture."
                 : "Cuts from the centre. The shape follows the photo: wide photos stay wide, tall photos stay tall.")
                .font(.caption).foregroundStyle(.secondary)
        case .removeBackground:
            HStack(spacing: 14) {
                Picker("Background", selection: $m.settings.bgFill) {
                    ForEach(BackgroundFill.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Toggle("Crop to subject", isOn: $m.settings.cropToSubject)
                Spacer()
            }
            Text(m.settings.bgFill == .transparent ? "Saved as PNG with a transparent background." : "Saved as JPG on a white background.")
                .font(.caption).foregroundStyle(.secondary)
        case .watermark:
            HStack(spacing: 10) {
                Picker("Mark", selection: $m.settings.markKind) {
                    ForEach(MarkKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if m.settings.markKind == .text {
                    TextField("Watermark text", text: $m.settings.markText, prompt: Text("Text")).labelsHidden().frame(width: 200)
                } else {
                    Button("Choose Logo…") { m.pickLogo() }
                    Text(m.settings.markLogo?.lastPathComponent ?? "No logo chosen")
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 160, alignment: .leading)
                }
                Picker("Position", selection: $m.settings.markPosition) {
                    ForEach(MarkPosition.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                Spacer()
            }
            HStack(spacing: 10) {
                Text("Opacity")
                Slider(value: $m.settings.markOpacity, in: 0.1...1.0) { Text("Opacity") }.labelsHidden().frame(width: 100)
                Text("\(Int(m.settings.markOpacity * 100)) %").monospacedDigit().frame(width: 40, alignment: .trailing)
                Text("Size")
                Slider(value: $m.settings.markSize, in: 0.1...0.8) { Text("Size") }.labelsHidden().frame(width: 100)
                Text("\(Int(m.settings.markSize * 100)) %").monospacedDigit().frame(width: 40, alignment: .trailing)
                Spacer()
            }
            Text("Size is the width of the mark compared to the photo or page. Photo info is kept.")
                .font(.caption).foregroundStyle(.secondary)
        case .blackWhite:
            Text("Photos keep their format and photo info. PDFs are made grey, text and vectors stay sharp.")
                .font(.caption).foregroundStyle(.secondary)
        case .iconSet:
            HStack(spacing: 14) {
                Picker("Icon formats", selection: $m.settings.iconFormats) {
                    ForEach(IconFormats.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            Text("Pictures that aren't square get transparent edges. Use a square picture of at least 1024 px for the best result.")
                .font(.caption).foregroundStyle(.secondary)
        case .contactSheet:
            HStack(spacing: 10) {
                Text("Name")
                TextField("Name", text: $m.settings.sheetName, prompt: Text("Contact Sheet")).labelsHidden().frame(width: 150)
                Text(m.settings.sheetFormat == .pdf ? ".pdf" : ".jpg").foregroundStyle(.secondary)
                Picker("Format", selection: $m.settings.sheetFormat) {
                    ForEach(SheetFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Stepper("\(m.settings.sheetColumns) columns", value: $m.settings.sheetColumns, in: 2...10)
                Toggle("File names", isOn: $m.settings.sheetNames)
                Spacer()
            }
            Text("All photos go on one sheet in list order. Drag to reorder or use Sort.")
                .font(.caption).foregroundStyle(.secondary)
        case .duplicates:
            HStack(spacing: 14) {
                Picker("Compare", selection: $m.settings.duplicateMode) {
                    ForEach(DuplicateMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                if !m.duplicatesInList.isEmpty {
                    Button("Move Duplicates to Trash (\(m.duplicatesInList.count))") { confirmTrash = true }
                        .disabled(m.busy)
                        .confirmationDialog("Move \(m.duplicatesInList.count) duplicates to the Trash?", isPresented: $confirmTrash) {
                            Button("Move to Trash", role: .destructive) { m.moveDuplicatesToTrash() }
                        } message: {
                            Text("The best copy of each photo is kept. You can put the others back from the Trash.")
                        }
                }
            }
            Text(m.settings.duplicateMode == .similar
                 ? "Finds the same photo even when it was resized, saved again or turned. Nothing is deleted until you confirm."
                 : "Finds files with exactly the same content. Nothing is deleted until you confirm.")
                .font(.caption).foregroundStyle(.secondary)
        case .recognizeText:
            Text("Reads German, English and French. Saves a .txt file next to each photo or PDF. PDF pages that already have text are copied as they are.")
                .font(.caption).foregroundStyle(.secondary)
        case .makeSearchable:
            Text("Adds an invisible text layer to scanned pages so you can search and copy. The pages look the same. Pages that already have text stay unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        case .pageNumbers:
            HStack(spacing: 14) {
                Picker("Style", selection: $m.settings.numberStyle) {
                    ForEach(NumberStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Picker("Position", selection: $m.settings.numberPosition) {
                    ForEach(NumberPosition.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                Spacer()
            }
            HStack(spacing: 14) {
                Stepper("Start at \(m.settings.numberStart)", value: $m.settings.numberStart, in: 0...9999)
                Toggle("Skip first page", isOn: $m.settings.numberSkipFirst)
                Spacer()
            }
            Text("Links and form fields in the PDF are not kept. Text and images stay sharp.")
                .font(.caption).foregroundStyle(.secondary)
        case .password:
            HStack(spacing: 10) {
                Picker("Mode", selection: $m.settings.passwordMode) {
                    ForEach(PasswordMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                SecureField("Password", text: $m.pdfPassword, prompt: Text("Password")).labelsHidden().frame(width: 200)
                Spacer()
            }
            Text(m.settings.passwordMode == .add
                 ? "The PDF is saved as a new file that needs the password to open. Don't forget it: it can't be recovered."
                 : "Enter the current password. The PDF is saved as a new file without a password.")
                .font(.caption).foregroundStyle(.secondary)
        case .flatten:
            Text("Form fields, notes and stamps become part of the page, so they can no longer be edited. PDFs without any are skipped.")
                .font(.caption).foregroundStyle(.secondary)
        case .stitch:
            HStack(spacing: 10) {
                Text("Name")
                TextField("Name", text: $m.settings.stitchName, prompt: Text("Stitched")).labelsHidden().frame(width: 150)
                Text(m.settings.stitchFormat == .png ? ".png" : ".jpg").foregroundStyle(.secondary)
                Picker("Format", selection: $m.settings.stitchFormat) {
                    ForEach(StitchFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            HStack(spacing: 14) {
                Picker("Direction", selection: $m.settings.stitchDirection) {
                    ForEach(StitchDirection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Stepper("Gap \(m.settings.stitchSpacing) px", value: $m.settings.stitchSpacing, in: 0...500, step: 10)
                Spacer()
            }
            Text("Photos are put together in list order. Drag to reorder or use Sort. They are scaled to the same width (or height), never enlarged.")
                .font(.caption).foregroundStyle(.secondary)
        case .cleanScan:
            HStack(spacing: 10) {
                Picker("Colours", selection: $m.settings.scanColor) {
                    ForEach(ScanColor.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            HStack(spacing: 10) {
                Text("Save as")
                Picker("Save as", selection: $m.settings.scanOutput) {
                    ForEach(ScanOutput.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            Text("Finds the page in the photo, straightens it and makes the paper white. If no page edges are found, only the colours are cleaned up.")
                .font(.caption).foregroundStyle(.secondary)
        case .redact:
            TextField("Words to black out", text: $m.settings.redactTerms, prompt: Text("Names or words, separated by commas"))
                .labelsHidden()
            HStack(spacing: 14) {
                Toggle("Email addresses", isOn: $m.settings.redactEmails)
                Toggle("IBANs", isOn: $m.settings.redactIBANs)
                Toggle("Phone numbers", isOn: $m.settings.redactPhones)
                Spacer()
            }
            Text("Matching text is covered and removed for good. Pages with matches become images with a hidden text layer.")
                .font(.caption).foregroundStyle(.secondary)
        case .extractTables:
            HStack(spacing: 10) {
                Picker("Separator", selection: $m.settings.csvSeparator) {
                    ForEach(CSVSeparator.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            Text("Each table becomes a CSV file that opens in Excel. For PDFs, only the selected pages are searched (all if none selected).")
                .font(.caption).foregroundStyle(.secondary)
        case .videoToGIF:
            HStack(spacing: 14) {
                Picker("Width", selection: $m.settings.gifWidth) {
                    Text("320 px").tag(320)
                    Text("480 px").tag(480)
                    Text("640 px").tag(640)
                }
                .fixedSize()
                Picker("Frame rate", selection: $m.settings.gifFPS) {
                    Text("10 fps").tag(10)
                    Text("15 fps").tag(15)
                }
                .fixedSize()
                Spacer()
            }
            Text("Only the first 60 seconds are used. The GIF loops forever and is never wider than the video.")
                .font(.caption).foregroundStyle(.secondary)
        case .extractImages:
            Toggle("Skip small images (icons, lines, logos under \(PDFImages.minSide) px)", isOn: $m.settings.skipSmallImages)
            Text("Pictures are saved at their original resolution into a new folder. JPEGs are copied unchanged, others are saved as PNG.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var wordHint: String {
        m.settings.wordNaming == .numbered
            ? "# is replaced by the number (### → 001), in list order. Drag to reorder or use Sort."
            : "Microsoft Word makes the PDFs, so they look exactly like the document in Word. Documents you have open in Word stay open."
    }

    var splitHint: String {
        switch m.settings.splitMode {
        case .extract: "Makes a new PDF from the pages you click above. Add more PDFs to split into several at once."
        case .each: "Makes one PDF per page. The page selection above limits which pages (all if none selected)."
        case .chunks: "Cuts the PDF into parts of \(m.settings.chunkSize) pages. The page selection above limits which pages (all if none selected)."
        }
    }
}
