import QuickLook
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable { case tool(Tool), favorite(Tool), preset(UUID) }

struct ContentView: View {
    @StateObject var m: Model
    @State private var deleting: Preset?
    /// The current tool was picked in Favorites, so that row is highlighted instead of its twin below
    @State private var pickedFavorite = false
    @AppStorage(L10n.defaultsKey) private var language = L10n.lang.rawValue

    @MainActor init(model: Model? = nil) { _m = StateObject(wrappedValue: model ?? Model()) }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                if !favorites.isEmpty {
                    section(tr("Favorites"), "favorites") {
                        ForEach(favorites) { t in toolLabel(t).tag(SidebarItem.favorite(t)) }
                    }
                }
                ForEach(Tool.groups, id: \.key) { g in
                    section(tr(g.title), g.key) { toolRows(g.tools) }
                }
                if !m.presets.isEmpty {
                    section(tr("Presets"), "presets") {
                        ForEach(m.presets) { p in
                            Label(p.name, systemImage: "star").tag(SidebarItem.preset(p.id))
                                .contextMenu {
                                    Button(tr("Edit…")) { m.editingPresetID = p.id }
                                    Button(tr("Duplicate")) { m.duplicatePreset(p.id) }
                                    Button(tr("Watch Folders…")) { m.showWatchFolders = true }
                                    Divider()
                                    Button(tr("Delete…"), role: .destructive) { deleting = p }
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
        .id(language)   // rebuild every view in the new language; the model and its files stay
        .onChange(of: language) { old, _ in m.languageChanged(from: Lang(rawValue: old) ?? .en) }
        .environmentObject(m)
        .focusedSceneObject(m)
        .frame(minWidth: 880, minHeight: 580)
        .importsItemProviders([.image, .pdf]) { m.importScans($0); return true }
        .sheet(item: $m.savePresetTool) { SavePresetSheet(tool: $0).environmentObject(m) }
        .sheet(item: Binding(get: { m.editingPresetID.flatMap { id in m.presets.first { $0.id == id } } },
                             set: { m.editingPresetID = $0?.id })) { EditPresetSheet(preset: $0).environmentObject(m) }
        .confirmationDialog(tr("Delete this preset?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { p in
            Button(tr("Delete “%@”", p.name), role: .destructive) { m.deletePreset(p.id) }
        } message: { _ in
            Text(tr("The preset is removed. Your files are not touched."))
        }
        .sheet(isPresented: $m.showWatchFolders) { WatchFoldersSheet().environmentObject(m) }
        .sheet(item: Binding(get: { m.items.first { $0.id == m.comparing && $0.output != nil } }, set: { m.comparing = $0?.id })) { it in
            CompareView(original: it.url, compressed: it.output!, isPDF: it.kind == .pdf) {
                try? FileManager.default.trashItem(at: it.output!, resultingItemURL: nil)
                m.lastOutputs.removeAll { $0 == it.output }
                m.update(it.id) { $0.output = nil; $0.results = []; $0.done = false; $0.status = tr("Compressed copy moved to Trash") }
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
    func section<C: View>(_ title: String, _ key: String, @ViewBuilder _ content: () -> C) -> some View {
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
        Label(t.title, systemImage: t.icon)
            .contextMenu {
                Button(tr(favorites.contains(t) ? "Remove from Favorites" : "Add to Favorites")) { toggleFavorite(t) }
            }
    }

    func toolRows(_ tools: [Tool]) -> some View {
        ForEach(tools) { t in toolLabel(t).tag(SidebarItem.tool(t)) }
    }
}

struct ToolView: View {
    @EnvironmentObject var m: Model
    @Environment(\.undoManager) private var undo
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
        let preview = m.activePreset != nil ? [:] : m.tool == .rename ? m.renamePreview()
            : m.tool == .wordToPDF && !m.settings.wordCombine ? m.wordPDFNames().mapValues { $0 + ".pdf" } : [:]
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
                    Label(tr("Save to"), systemImage: "folder").labelStyle(.titleAndIcon)
                    Text(m.outputFolder?.path ?? tr("Same folder as original"))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if m.outputFolder != nil { Button(tr("Use Original Folder")) { m.outputFolder = nil } }
                    Button(tr("Choose Folder…")) { m.pickFolder() }
                }
            }

            Divider()

            bottomBar
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { m.pickFiles() } label: { Label(tr("Add Files"), systemImage: "plus") }
                .help(tr("Add photos, PDFs or folders (⌘O)"))
                .disabled(m.busy)
            Menu {
                Button(tr("By Name")) { m.sort(.name, undo: undo) }
                Button(tr("By Date Taken")) { m.sort(.date, undo: undo) }
                Divider()
                Button(tr("Reverse Order")) { m.sort(.reverse, undo: undo) }
            } label: {
                Label(tr("Sort"), systemImage: "arrow.up.arrow.down")
            }
            .help(tr("Sort the list"))
            .disabled(m.busy || m.items.count < 2)
            Button { m.clearList(undo: undo) } label: { Label(tr("Clear List"), systemImage: "xmark.circle") }
                .help(tr("Remove all files from the list. The files themselves are not touched."))
                .disabled(m.busy || m.items.isEmpty)
        }
        if m.activePreset == nil && m.tool.isChainable {
            ToolbarItem(placement: .primaryAction) {
                Button { m.savePresetTool = m.tool } label: { Label(tr("Save as Preset…"), systemImage: "star.square.on.square") }
                    .help(tr("Save this tool and its settings as a preset"))
                    .disabled(m.busy)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { m.quickLook = m.previewURLs.first } label: { Label(tr("Quick Look"), systemImage: "eye") }
                .help(tr("Preview the new files (⌘Y)"))
                .disabled(m.busy || m.previewURLs.isEmpty)
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
                    Button(tr("Choose Files…")) { m.pickFiles() }
                }
            } else {
                shape.fill(.fill.quinary)
                shape.strokeBorder(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: targeted ? 2 : 1)
                List(selection: Binding(get: { m.pageItem?.id ?? m.focused }, set: { m.focused = $0 })) {
                    ForEach(m.items) { it in row(it, preview: preview).tag(it.id) }
                        .onMove { from, to in m.changeItems(tr("Move"), undo: undo) { $0.move(fromOffsets: from, toOffset: to) } }
                }
                .onDeleteCommand { if !m.busy, let id = m.pageItem?.id ?? m.focused { m.remove(id, undo: undo) } }
                .animation(.default, value: m.items.map(\.id))
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
        if m.activePreset != nil { return tr("Drop photos, PDFs or folders here") }
        return switch m.tool {
        case .resize, .crop, .removeBackground, .iconSet, .contactSheet, .duplicates, .stitch, .cleanScan: tr("Drop photos or folders here")
        case .videoToGIF: tr("Drop videos here")
        case .compress: tr("Drop photos, PDFs, videos or folders here")
        case .split, .reorder, .extractImages, .pageNumbers, .password, .flatten: tr("Drop PDFs here")
        case .wordToPDF: tr("Drop Word documents or folders here")
        default: tr("Drop photos, PDFs or folders here")
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
            Text(usable ? it.status : tr("Not used by this tool"))
                .foregroundStyle(it.failed ? Color.red : .secondary).font(.caption).lineLimit(1)
            if preset == nil, m.tool == .compress, it.output != nil {
                Button(tr("Compare")) { m.comparing = it.id }.controlSize(.small)
            }
            if usable, it.done, let first = it.results.first {
                Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                    .modifier(DragOut(file: first))
                    .accessibilityLabel(tr("Drag the result to another app or folder"))
            }
            Button { m.remove(it.id, undo: undo) } label: { Label(tr("Remove from List"), systemImage: "xmark.circle.fill") }
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                .help(tr("Remove from list")).disabled(m.busy)
        }
        .opacity(usable ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .contextMenu {
            if usable && it.done && !it.results.isEmpty {
                Button(tr("Quick Look Result")) { m.quickLook = it.results.first }
                Button(tr(it.results.count == 1 ? "Show New File in Finder" : "Show New Files in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting(it.results)
                }
                Button(tr("Show Original in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([it.url]) }
            } else {
                Button(tr("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([it.url]) }
            }
            Divider()
            Button(tr("Remove from List")) { m.remove(it.id, undo: undo) }.disabled(m.busy)
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
                        $0.done = false; $0.failed = false; $0.status = tr("Ready")
                    }
                }
            } else if m.assignsParts {
                PartsPicker(url: it.url, pageCount: it.pageCount, parts: it.parts, names: it.partNames) { parts, names in
                    m.update(it.id) { $0.parts = parts; $0.partNames = names; $0.done = false; $0.failed = false; $0.status = tr("Ready") }
                }
            } else {
                PagePicker(url: it.url, pageCount: it.pageCount, selected: it.selected) { sel in
                    m.update(it.id) { $0.selected = sel; $0.done = false; $0.failed = false; $0.status = tr("Ready") }
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
                Text(tr("Steps, in this order")).font(.headline)
                Spacer()
                Button { m.editingPresetID = p.id } label: { Label(tr("Edit Preset…"), systemImage: "slider.horizontal.3") }
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
                let bad = m.summaryFailed
                Label(s, systemImage: bad ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(bad ? .red : .secondary)
                    .lineLimit(2)
            } else if !m.items.isEmpty {
                Text(m.items.count == 1 ? tr("1 file") : tr("%d files", m.items.count)).foregroundStyle(.secondary)
            }
            if !m.busy && !m.lastOutputs.isEmpty {   // only once there is something to show
                Button(tr("Show in Finder")) { m.showInFinder() }
                    .help(tr("Show the new files in Finder (⇧⌘R)"))
            }
            Spacer()
            if m.busy {
                ProgressView().controlSize(.small)
                if m.canStop || m.stopping {
                    Button(m.stopping ? tr("Stopping…") : tr("Stop")) { m.stop() }
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                        .help(tr("Stops after the file that is being worked on (Esc)"))
                        .disabled(m.stopping)
                }
            }
            Button(actionTitle) { m.run() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(m.busy || !m.canRun)
        }
        .animation(.default, value: m.summary)
        .animation(.default, value: m.busy)
    }

    var actionTitle: String {
        if m.activePreset != nil {
            let n = m.pending.count
            return n == 0 && !m.eligible.isEmpty ? tr("%@ Again", tr("Run Preset")) : "\(tr("Run Preset")) (\(n))"
        }
        switch m.tool {
        case .combine: return tr("Create PDF")
        case .wordToPDF where m.settings.wordCombine:
            return m.pending.isEmpty && !m.eligible.isEmpty ? tr("%@ Again", tr("Create PDF")) : tr("Create PDF")
        case .rename:
            return m.settings.renameMode == .smart && m.smartMissing > 0
                ? tr("Suggest Names (%d)", m.smartMissing) : "\(tr("Rename")) (\(m.renameCount))"
        case .contactSheet: return tr("Create Sheet")
        case .stitch: return tr("Stitch")
        case .password:
            let n = m.pending.count
            let verb = m.settings.passwordMode == .add ? tr("Protect") : tr("Unlock")
            return n == 0 && !m.eligible.isEmpty ? tr("%@ Again", verb) : "\(verb) (\(n))"
        default:
            let n = m.pending.count
            return n == 0 && !m.eligible.isEmpty ? tr("%@ Again", m.tool.action) : "\(m.tool.action) (\(n))"
        }
    }
}

/// Choice of how new names are made, with the fields for that choice and an example of the result
struct NameRuleEditor<Extra: View>: View {
    @Binding var rule: NameRule
    let modes: [NameMode]
    var smart: Binding<Bool>? = nil   // Rename only: a third choice, names read from each file's content
    let example: URL?          // first file in the list, for the example in the hint
    let placeholder: String
    var outExt: String? = nil  // extension of the new files if it differs from the example's
    @ViewBuilder var extra: Extra

    private var isSmart: Bool { smart?.wrappedValue == true }

    /// nil = from content
    private var choice: Binding<NameMode?> {
        Binding(get: { isSmart ? nil : rule.mode }, set: {
            if let mode = $0 { smart?.wrappedValue = false; rule.mode = mode } else { smart?.wrappedValue = true }
        })
    }

    var body: some View {
        Picker(tr("Name"), selection: choice) {
            ForEach(modes) { Text($0.title).tag(Optional($0)) }
            if smart != nil { Text(tr("From content")).tag(NameMode?.none) }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
        HStack(spacing: 8) {
            switch isSmart ? nil : rule.mode {
            case nil, .keep:
                EmptyView()
            case .add:
                TextField(tr("Text before the name"), text: $rule.before, prompt: Text(tr("Before"))).labelsHidden().frame(width: 130)
                Text(tr("+ name +")).foregroundStyle(.secondary)
                TextField(tr("Text after the name"), text: $rule.after, prompt: Text(tr("After"))).labelsHidden().frame(width: 130)
            case .numbered:
                Text(tr("New name"))
                TextField(tr("New name"), text: $rule.pattern, prompt: Text(placeholder)).labelsHidden().frame(width: 180)
                Stepper(tr("first number %d", rule.start), value: $rule.start, in: 0...99999)
            }
            Spacer()
            extra
        }
        ForEach(hint, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
    }

    /// One or two short lines (a long line gets cut off at the minimum window width)
    var hint: [String] {
        if isSmart {
            return [tr("Names like 261014-SwisscomInvoice.pdf, from each file's date and content. Click Suggest Names, check them, then Rename.")]
        }
        let stem = example?.deletingPathExtension().lastPathComponent ?? tr("Report")
        let ext = example.map { $0.pathExtension.isEmpty ? "" : "." + $0.pathExtension } ?? ""
        func name(_ i: Int) -> String { rule.apply(stem, index: i, count: 3) + (outExt ?? ext) }
        switch rule.mode {
        case .keep:
            return []
        case .add:
            return [tr("Adds text in front of and/or behind the current name: “%@” becomes “%@”.", stem + ext, name(0))]
        case .numbered:
            return [tr("Example: “%@”, “%@”, …", name(0), name(1)),
                    tr("The whole name is replaced. # marks where the number goes (### = 3 digits).")]
        }
    }
}

/// Lets a new file be dragged from the list to the Finder, Mail or another app
struct DragOut: ViewModifier {
    let file: URL?

    func body(content: Content) -> some View {
        if let file {
            content
                .onDrag { NSItemProvider(object: file as NSURL) } preview: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 48, height: 48)
                }
                .help(tr("Drag to put “%@” somewhere else", file.lastPathComponent))
        } else {
            content
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
                Picker(tr("Format"), selection: $m.settings.format) {
                    ForEach(OutFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
                if m.settings.format.isLossy {
                    Text(tr("Quality"))
                    Slider(value: $m.settings.quality, in: 0.3...1.0) { Text(tr("Quality")) }.labelsHidden().frame(width: 100)
                    Text("\(Int(m.settings.quality * 100)) %").monospacedDigit().frame(width: 40, alignment: .trailing)
                } else {
                    Text(m.settings.format.hint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if m.hasPDF {   // own line: next to format + quality it overflows the minimum window width
                Picker(tr("PDF pages at"), selection: $m.settings.dpi) {
                    Text(tr("72 dpi (screen)")).tag(72)
                    Text(tr("150 dpi")).tag(150)
                    Text(tr("300 dpi (print)")).tag(300)
                }
                .fixedSize()
            }
        case .compress:
            HStack(spacing: 14) {
                Picker(tr("Compress by"), selection: $m.settings.compressBy) {
                    ForEach(CompressBy.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Divider().frame(height: 18)
                if m.settings.compressBy == .level {
                    Picker(tr("Level"), selection: $m.settings.level) {
                        ForEach(Level.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                } else {
                    Text(tr("Smaller than"))
                    TextField(tr("Maximum size in MB"), value: $m.settings.targetMB, format: .number).labelsHidden().frame(width: 56).multilineTextAlignment(.trailing)
                    Text(tr("MB"))
                }
                Spacer()
            }
            Text(m.settings.compressBy == .level ? m.settings.level.hint : tr("Tries gentle settings first and only goes further when needed"))
                .font(.caption).foregroundStyle(.secondary)
        case .resize:
            HStack(spacing: 10) {
                Picker(tr("Resize by"), selection: $m.settings.resizeMode) {
                    ForEach(ResizeMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                .onChange(of: m.settings.resizeMode) { _, new in
                    if new == .percent { m.settings.resizeValue = 50 } else if m.settings.resizeValue <= 100 { m.settings.resizeValue = 2000 }
                }
                TextField(tr("Size"), value: $m.settings.resizeValue, format: .number).labelsHidden().frame(width: 70).multilineTextAlignment(.trailing)
                Text(m.settings.resizeMode == .percent ? "%" : tr("pixels"))
                Text(tr("Only makes photos smaller. Format and photo info are kept.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        case .rotate:
            HStack(spacing: 14) {
                Picker(tr("Rotation"), selection: $m.settings.rotation) {
                    Label(tr("90° right"), systemImage: "rotate.right").tag(90)
                    Label("180°", systemImage: "arrow.uturn.down").tag(180)
                    Label(tr("90° left"), systemImage: "rotate.left").tag(270)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Text(m.hasPDF ? tr("For PDFs, only the selected pages are turned (all if none selected)") : "")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        case .strip:
            HStack(spacing: 14) {
                Picker(tr("Remove"), selection: $m.settings.stripMode) {
                    ForEach(StripMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Text(m.settings.stripMode == .all
                     ? tr("Removes camera, date and location. The image itself stays exactly the same.")
                     : tr("Removes only where the photo was taken. The image itself stays exactly the same."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if m.hasPDF {
                Text(tr("For PDFs, removes author, title and other document info.")).font(.caption).foregroundStyle(.secondary)
            }
        case .rename:
            NameRuleEditor(rule: $m.settings.renameRule, modes: [.add, .numbered],
                           smart: Binding(get: { m.settings.renameMode == .smart }, set: { m.settings.renameMode = $0 ? .smart : .rule }),
                           example: m.items.first?.url, placeholder: tr("Photo ###")) {
                if !m.lastRename.isEmpty {
                    Button(tr("Undo Rename")) { m.undoRename() }.disabled(m.busy)
                }
            }
            Text(tr("Files are renamed in place. The arrow in the list shows the new name."))
                .font(.caption).foregroundStyle(.secondary)
        case .combine:
            HStack(spacing: 10) {
                Text(tr("Name"))
                TextField(tr("Name"), text: $m.settings.combinedName, prompt: Text(tr("Combined"))).labelsHidden().frame(width: 180)
                Text(tr(".pdf")).foregroundStyle(.secondary)
                Divider().frame(height: 18)
                Picker(tr("Photo pages"), selection: $m.settings.pageSize) {
                    ForEach(PageSize.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Toggle(tr("Margin"), isOn: $m.settings.pageMargin)
                Spacer()
            }
            Text(tr("Files are added in list order. Drag to reorder or use Sort. PDF pages are added unchanged."))
                .font(.caption).foregroundStyle(.secondary)
        case .split:
            HStack(spacing: 14) {
                Picker(tr("Split mode"), selection: $m.settings.splitMode) {
                    ForEach(SplitMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if m.settings.splitMode == .chunks {
                    Stepper(tr("%d pages each", m.settings.chunkSize), value: $m.settings.chunkSize, in: 1...999)
                }
                Spacer()
            }
            Text(splitHint).font(.caption).foregroundStyle(.secondary)
        case .reorder:
            Text(tr("Drag the pages above into the order you want. Click another PDF in the list to arrange its pages. The PDF is saved as a new file."))
                .font(.caption).foregroundStyle(.secondary)
        case .wordToPDF:
            // In a preset step (scratch model) every file becomes its own PDF under its own name
            let combine = m.persist && m.settings.wordCombine
            HStack(spacing: 14) {
                if m.persist { Toggle(tr("Combine into one PDF"), isOn: $m.settings.wordCombine) }
                Toggle(tr("Compress"), isOn: $m.settings.wordCompress)
                if m.settings.wordCompress {
                    Picker(tr("Level"), selection: $m.settings.wordLevel) {   // a menu: segments don't fit next to the toggles in German
                        ForEach(Level.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Spacer()
            }
            HStack(spacing: 14) {
                Toggle(tr("Without tracked changes and comments"), isOn: $m.settings.wordFinal)
                    .help(tr("Accepts all tracked changes and removes comments in the copy Word works on. The Word document itself stays unchanged."))
                Toggle(tr("Update fields and table of contents"), isOn: $m.settings.wordUpdateFields)
                    .help(tr("Updates page numbers, cross-references and tables of contents before the PDF is made, as Word does before printing."))
                Spacer()
            }
            if combine {
                HStack(spacing: 10) {
                    Text(tr("Name"))
                    TextField(tr("Name"), text: $m.settings.wordCombinedName, prompt: Text(tr("Combined"))).labelsHidden().frame(width: 180)
                    Text(tr(".pdf")).foregroundStyle(.secondary)
                    Spacer()
                }
            } else if m.persist {
                NameRuleEditor(rule: $m.settings.wordRule, modes: NameMode.allCases, example: m.eligible.first?.url,
                               placeholder: tr("Document ###"), outExt: ".pdf") {}
            }
            if combine || !m.persist || m.settings.wordRule.mode == .keep {
                Text(wordHint).font(.caption).foregroundStyle(.secondary)
            }
        case .crop:
            HStack(spacing: 14) {
                Picker(tr("Shape"), selection: $m.settings.cropAspect) {
                    ForEach(CropAspect.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            Text(m.settings.cropAspect == .trim
                 ? tr("Cuts away plain borders of one colour around the picture.")
                 : tr("Cuts from the centre. The shape follows the photo: wide photos stay wide, tall photos stay tall."))
                .font(.caption).foregroundStyle(.secondary)
        case .removeBackground:
            HStack(spacing: 14) {
                Picker(tr("Background"), selection: $m.settings.bgFill) {
                    ForEach(BackgroundFill.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Toggle(tr("Crop to subject"), isOn: $m.settings.cropToSubject)
                Spacer()
            }
            Text(m.settings.bgFill == .transparent ? tr("Saved as PNG with a transparent background.") : tr("Saved as JPG on a white background."))
                .font(.caption).foregroundStyle(.secondary)
        case .watermark:
            HStack(spacing: 10) {
                Picker(tr("Mark"), selection: $m.settings.markKind) {
                    ForEach(MarkKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if m.settings.markKind == .text {
                    TextField(tr("Watermark text"), text: $m.settings.markText, prompt: Text(tr("Text"))).labelsHidden().frame(width: 200)
                } else {
                    Button(tr("Choose Logo…")) { m.pickLogo() }
                    Text(m.settings.markLogo?.lastPathComponent ?? tr("No logo chosen"))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 160, alignment: .leading)
                }
                Picker(tr("Position"), selection: $m.settings.markPosition) {
                    ForEach(MarkPosition.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Spacer()
            }
            HStack(spacing: 10) {
                Text(tr("Opacity"))
                Slider(value: $m.settings.markOpacity, in: 0.1...1.0) { Text(tr("Opacity")) }.labelsHidden().frame(width: 100)
                Text("\(Int(m.settings.markOpacity * 100)) %").monospacedDigit().frame(width: 40, alignment: .trailing)
                Text(tr("Size"))
                Slider(value: $m.settings.markSize, in: 0.1...0.8) { Text(tr("Size")) }.labelsHidden().frame(width: 100)
                Text("\(Int(m.settings.markSize * 100)) %").monospacedDigit().frame(width: 40, alignment: .trailing)
                Spacer()
            }
            Text(tr("Size is the width of the mark compared to the photo or page. Photo info is kept."))
                .font(.caption).foregroundStyle(.secondary)
        case .blackWhite:
            Text(tr("Photos keep their format and photo info. PDFs are made grey, text and vectors stay sharp."))
                .font(.caption).foregroundStyle(.secondary)
        case .iconSet:
            HStack(spacing: 14) {
                Picker(tr("Icon formats"), selection: $m.settings.iconFormats) {
                    ForEach(IconFormats.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            Text(tr("Pictures that aren't square get transparent edges. Use a square picture of at least 1024 px for the best result."))
                .font(.caption).foregroundStyle(.secondary)
        case .contactSheet:
            HStack(spacing: 10) {
                Text(tr("Name"))
                TextField(tr("Name"), text: $m.settings.sheetName, prompt: Text(tr("Contact Sheet"))).labelsHidden().frame(width: 150)
                Text(m.settings.sheetFormat == .pdf ? ".pdf" : ".jpg").foregroundStyle(.secondary)
                Picker(tr("Format"), selection: $m.settings.sheetFormat) {
                    ForEach(SheetFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Stepper(tr("%d columns", m.settings.sheetColumns), value: $m.settings.sheetColumns, in: 2...10)
                Toggle(tr("File names"), isOn: $m.settings.sheetNames)
                Spacer()
            }
            Text(tr("All photos go on one sheet in list order. Drag to reorder or use Sort."))
                .font(.caption).foregroundStyle(.secondary)
        case .duplicates:
            HStack(spacing: 14) {
                Picker(tr("Compare"), selection: $m.settings.duplicateMode) {
                    ForEach(DuplicateMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                if !m.duplicatesInList.isEmpty {
                    Button("\(tr("Move Duplicates to Trash")) (\(m.duplicatesInList.count))") { confirmTrash = true }
                        .disabled(m.busy)
                        .confirmationDialog(m.duplicatesInList.count == 1 ? tr("Move 1 duplicate to the Trash?") : tr("Move %d duplicates to the Trash?", m.duplicatesInList.count), isPresented: $confirmTrash) {
                            Button(tr("Move to Trash"), role: .destructive) { m.moveDuplicatesToTrash() }
                        } message: {
                            Text(tr("The best copy of each photo is kept. You can put the others back from the Trash."))
                        }
                }
            }
            Text(m.settings.duplicateMode == .similar
                 ? tr("Finds the same photo even when it was resized, saved again or turned. Nothing is deleted until you confirm.")
                 : tr("Finds files with exactly the same content. Nothing is deleted until you confirm."))
                .font(.caption).foregroundStyle(.secondary)
        case .recognizeText:
            Text(tr("Reads German, English and French. Saves a .txt file next to each photo or PDF. PDF pages that already have text are copied as they are."))
                .font(.caption).foregroundStyle(.secondary)
        case .makeSearchable:
            Text(tr("Adds an invisible text layer to scanned pages so you can search and copy. The pages look the same. Pages that already have text stay unchanged."))
                .font(.caption).foregroundStyle(.secondary)
        case .pageNumbers:
            HStack(spacing: 14) {
                Picker(tr("Style"), selection: $m.settings.numberStyle) {
                    ForEach(NumberStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Picker(tr("Position"), selection: $m.settings.numberPosition) {
                    ForEach(NumberPosition.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Spacer()
            }
            HStack(spacing: 14) {
                Stepper(tr("Start at %d", m.settings.numberStart), value: $m.settings.numberStart, in: 0...9999)
                Toggle(tr("Skip first page"), isOn: $m.settings.numberSkipFirst)
                Spacer()
            }
            Text(tr("Links and form fields in the PDF are not kept. Text and images stay sharp."))
                .font(.caption).foregroundStyle(.secondary)
        case .password:
            HStack(spacing: 10) {
                Picker(tr("Mode"), selection: $m.settings.passwordMode) {
                    ForEach(PasswordMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                SecureField(tr("Password"), text: $m.pdfPassword, prompt: Text(tr("Password"))).labelsHidden().frame(width: 200)
                Spacer()
            }
            Text(m.settings.passwordMode == .add
                 ? tr("The PDF is saved as a new file that needs the password to open. Don't forget it: it can't be recovered.")
                 : tr("Enter the current password. The PDF is saved as a new file without a password."))
                .font(.caption).foregroundStyle(.secondary)
        case .flatten:
            Text(tr("Form fields, notes and stamps become part of the page, so they can no longer be edited. PDFs without any are skipped."))
                .font(.caption).foregroundStyle(.secondary)
        case .stitch:
            HStack(spacing: 10) {
                Text(tr("Name"))
                TextField(tr("Name"), text: $m.settings.stitchName, prompt: Text(tr("Stitched"))).labelsHidden().frame(width: 150)
                Text(m.settings.stitchFormat == .png ? ".png" : ".jpg").foregroundStyle(.secondary)
                Picker(tr("Format"), selection: $m.settings.stitchFormat) {
                    ForEach(StitchFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            HStack(spacing: 14) {
                Picker(tr("Direction"), selection: $m.settings.stitchDirection) {
                    ForEach(StitchDirection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Stepper(tr("Gap %d px", m.settings.stitchSpacing), value: $m.settings.stitchSpacing, in: 0...500, step: 10)
                Spacer()
            }
            Text(tr("Photos are put together in list order. Drag to reorder or use Sort. They are scaled to the same width (or height), never enlarged."))
                .font(.caption).foregroundStyle(.secondary)
        case .cleanScan:
            HStack(spacing: 10) {
                Picker(tr("Colours"), selection: $m.settings.scanColor) {
                    ForEach(ScanColor.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            HStack(spacing: 10) {
                Text(tr("Save as"))
                Picker(tr("Save as"), selection: $m.settings.scanOutput) {
                    ForEach(ScanOutput.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            Text(tr("Finds the page in the photo, straightens it and makes the paper white. If no page edges are found, only the colours are cleaned up."))
                .font(.caption).foregroundStyle(.secondary)
        case .redact:
            TextField(tr("Words to black out"), text: $m.settings.redactTerms, prompt: Text(tr("Names or words, separated by commas")))
                .labelsHidden()
            HStack(spacing: 14) {
                Toggle(tr("Email addresses"), isOn: $m.settings.redactEmails)
                Toggle(tr("IBANs"), isOn: $m.settings.redactIBANs)
                Toggle(tr("Phone numbers"), isOn: $m.settings.redactPhones)
                Spacer()
            }
            Text(tr("Matching text is covered and removed for good. Pages with matches become images with a hidden text layer."))
                .font(.caption).foregroundStyle(.secondary)
        case .extractTables:
            HStack(spacing: 10) {
                Picker(tr("Separator"), selection: $m.settings.csvSeparator) {
                    ForEach(CSVSeparator.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            Text(tr("Each table becomes a CSV file that opens in Excel. For PDFs, only the selected pages are searched (all if none selected)."))
                .font(.caption).foregroundStyle(.secondary)
        case .videoToGIF:
            HStack(spacing: 14) {
                Picker(tr("Width"), selection: $m.settings.gifWidth) {
                    Text(tr("320 px")).tag(320)
                    Text(tr("480 px")).tag(480)
                    Text(tr("640 px")).tag(640)
                }
                .fixedSize()
                Picker(tr("Frame rate"), selection: $m.settings.gifFPS) {
                    Text(tr("10 fps")).tag(10)
                    Text(tr("15 fps")).tag(15)
                }
                .fixedSize()
                Spacer()
            }
            Text(tr("Only the first 60 seconds are used. The GIF loops forever and is never wider than the video."))
                .font(.caption).foregroundStyle(.secondary)
        case .extractImages:
            Toggle(tr("Skip small images (icons, lines, logos under %d px)", PDFImages.minSide), isOn: $m.settings.skipSmallImages)
            Text(tr("Pictures are saved at their original resolution into a new folder. JPEGs are copied unchanged, others are saved as PNG."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var wordHint: String {
        m.persist && m.settings.wordCombine
            ? tr("Documents are added in list order, each with a bookmark. Drag to reorder or use Sort.")
            : tr("The PDFs get the names of the Word documents. Microsoft Word makes them, so they look exactly like the document in Word.")
    }

    var splitHint: String {
        switch m.settings.splitMode {
        case .extract: tr("Makes a new PDF from the pages you click above. Add more PDFs to split into several at once.")
        case .each: tr("Makes one PDF per page. The page selection above limits which pages (all if none selected).")
        case .chunks: tr("Cuts the PDF into parts of %d pages. The page selection above limits which pages (all if none selected).", m.settings.chunkSize)
        }
    }
}
