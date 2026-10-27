import SwiftUI

struct ContentView: View {
    @StateObject var m: Model
    @AppStorage(L10n.defaultsKey) private var language = L10n.lang.rawValue

    @MainActor init(model: Model? = nil) { _m = StateObject(wrappedValue: model ?? Model()) }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { Optional(m.tool) }, set: { if let t = $0 { m.tool = t } })) {
                ForEach(Tool.groups, id: \.title) { g in
                    Section(tr(g.title)) { toolRows(g.tools) }
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
        .sheet(item: Binding(get: { m.items.first { $0.id == m.comparing && $0.output != nil } }, set: { m.comparing = $0?.id })) { it in
            CompareView(original: it.url, compressed: it.output!, isPDF: it.kind == .pdf) {
                try? FileManager.default.trashItem(at: it.output!, resultingItemURL: nil)
                m.lastOutputs.removeAll { $0 == it.output }
                m.update(it.id) { $0.output = nil; $0.outputs = []; $0.done = false; $0.status = tr("Compressed copy moved to Trash") }
            }
        }
    }

    func toolRows(_ tools: [Tool]) -> some View {
        ForEach(tools) { t in Label(t.title, systemImage: t.icon).tag(t) }
    }
}

struct ToolView: View {
    @EnvironmentObject var m: Model
    @Environment(\.undoManager) private var undo
    @State private var targeted = false

    var body: some View {
        let preview = m.tool == .rename ? m.renamePreview() : m.tool == .wordToPDF && !m.wordCombine ? m.wordPDFNames().mapValues { $0 + ".pdf" } : [:]
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

            VStack(alignment: .leading, spacing: 6) { settings }

            if m.tool.writesFiles {
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
        .padding(20)
        .navigationTitle(m.tool.title)
        .navigationSubtitle(m.tool.subtitle)
        .toolbar { toolbar }
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
    }

    // MARK: File list

    func dropZone(_ preview: [Item.ID: String]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            if m.items.isEmpty {
                shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator))
                ContentUnavailableView {
                    Label(dropHint, systemImage: m.tool.icon)
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
        switch m.tool {
        case .resize: tr("Drop photos or folders here")
        case .split, .reorder, .extractImages: tr("Drop PDFs here")
        case .wordToPDF: tr("Drop Word documents or folders here")
        default: tr("Drop photos, PDFs or folders here")
        }
    }

    @ViewBuilder func row(_ it: Item, preview: [Item.ID: String]) -> some View {
        let usable = m.tool.accepts(it.kind)
        HStack(spacing: 8) {
            Image(systemName: it.done && usable ? "checkmark.circle.fill" : it.failed ? "xmark.octagon.fill" : it.kind == .pdf ? "doc.richtext" : it.kind == .word ? "doc.text" : "photo")
                .foregroundStyle(it.done && usable ? .green : it.failed ? .red : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
                .modifier(DragOut(file: usable && it.outputs.count == 1 ? it.outputs[0] : nil))
            Text(it.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            if usable && it.kind == .pdf && m.assignsParts {
                HStack(spacing: 3) {
                    ForEach(it.parts.indices, id: \.self) { Circle().fill(partColor($0)).frame(width: 8, height: 8) }
                }
                Text(it.partsSummary).font(.caption).foregroundStyle(.secondary)
            } else if usable && it.kind == .pdf && m.tool.usesPages {
                Text(it.pageSummary).font(.caption).foregroundStyle(.secondary)
            } else if usable && m.tool == .reorder {
                Text(it.orderSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if m.tool == .rename || m.tool == .wordToPDF, usable, !it.done, let new = preview[it.id], new != it.url.lastPathComponent {
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Text(new).foregroundStyle(Color.accentColor).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(usable ? it.status : tr("Not used by this tool"))
                .foregroundStyle(it.failed ? Color.red : .secondary).font(.caption).lineLimit(1)
            if m.tool == .compress, it.output != nil {
                Button(tr("Compare")) { m.comparing = it.id }.controlSize(.small)
            }
            Button { m.remove(it.id, undo: undo) } label: { Label(tr("Remove from List"), systemImage: "xmark.circle.fill") }
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                .help(tr("Remove from list")).disabled(m.busy)
        }
        .opacity(usable ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .contextMenu {
            if usable && !it.outputs.isEmpty {
                Button(tr(it.outputs.count == 1 ? "Show New File in Finder" : "Show New Files in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting(it.outputs)
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

    // MARK: Settings per tool

    @ViewBuilder var settings: some View {
        switch m.tool {
        case .convert:
            HStack(spacing: 14) {
                Picker(tr("Format"), selection: $m.format) {
                    ForEach(OutFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
                if m.format.isLossy {
                    Text(tr("Quality"))
                    Slider(value: $m.quality, in: 0.3...1.0) { Text(tr("Quality")) }.labelsHidden().frame(width: 100)
                    Text("\(Int(m.quality * 100)) %").monospacedDigit().frame(width: 40, alignment: .trailing)
                } else {
                    Text(m.format.hint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if m.hasPDF {   // own line: next to format + quality it overflows the minimum window width
                Picker(tr("PDF pages at"), selection: $m.dpi) {
                    Text(tr("72 dpi (screen)")).tag(72)
                    Text(tr("150 dpi")).tag(150)
                    Text(tr("300 dpi (print)")).tag(300)
                }
                .fixedSize()
            }
        case .compress:
            HStack(spacing: 14) {
                Picker(tr("Compress by"), selection: $m.compressBy) {
                    ForEach(CompressBy.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Divider().frame(height: 18)
                if m.compressBy == .level {
                    Picker(tr("Level"), selection: $m.level) {
                        ForEach(Level.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                } else {
                    Text(tr("Smaller than"))
                    TextField(tr("Maximum size in MB"), value: $m.targetMB, format: .number).labelsHidden().frame(width: 56).multilineTextAlignment(.trailing)
                    Text(tr("MB"))
                }
                Spacer()
            }
            Text(m.compressBy == .level ? m.level.hint : tr("Tries gentle settings first and only goes further when needed"))
                .font(.caption).foregroundStyle(.secondary)
        case .resize:
            HStack(spacing: 10) {
                Picker(tr("Resize by"), selection: $m.resizeMode) {
                    ForEach(ResizeMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                .onChange(of: m.resizeMode) { _, new in
                    if new == .percent { m.resizeValue = 50 } else if m.resizeValue <= 100 { m.resizeValue = 2000 }
                }
                TextField(tr("Size"), value: $m.resizeValue, format: .number).labelsHidden().frame(width: 70).multilineTextAlignment(.trailing)
                Text(m.resizeMode == .percent ? "%" : tr("pixels"))
                Text(tr("Only makes photos smaller. Format and photo info are kept.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        case .rotate:
            HStack(spacing: 14) {
                Picker(tr("Rotation"), selection: $m.rotation) {
                    Label(tr("90° right"), systemImage: "rotate.right").tag(90)
                    Label(tr("180°"), systemImage: "arrow.uturn.down").tag(180)
                    Label(tr("90° left"), systemImage: "rotate.left").tag(270)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Text(m.hasPDF ? tr("For PDFs, only the selected pages are turned (all if none selected)") : "")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        case .strip:
            HStack(spacing: 14) {
                Picker(tr("Remove"), selection: $m.stripMode) {
                    ForEach(StripMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Text(tr(m.stripMode == .all
                     ? "Removes camera, date and location. The image itself stays exactly the same."
                     : "Removes only where the photo was taken. The image itself stays exactly the same."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if m.hasPDF {
                Text(tr("For PDFs, removes author, title and other document info.")).font(.caption).foregroundStyle(.secondary)
            }
        case .rename:
            NameRuleEditor(rule: $m.renameRule, modes: [.add, .numbered], example: m.items.first?.url, placeholder: tr("Photo ###")) {
                if !m.lastRename.isEmpty {
                    Button(tr("Undo Rename")) { m.undoRename() }.disabled(m.busy)
                }
            }
            Text(tr("Files are renamed in place. The arrow in the list shows the new name."))
                .font(.caption).foregroundStyle(.secondary)
        case .combine:
            HStack(spacing: 10) {
                Text(tr("Name"))
                TextField(tr("Name"), text: $m.combinedName, prompt: Text(tr("Combined"))).labelsHidden().frame(width: 180)
                Text(tr(".pdf")).foregroundStyle(.secondary)
                Divider().frame(height: 18)
                Picker(tr("Photo pages"), selection: $m.pageSize) {
                    ForEach(PageSize.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Toggle(tr("Margin"), isOn: $m.pageMargin)
                Spacer()
            }
            Text(tr("Files are added in list order. Drag to reorder or use Sort. PDF pages are added unchanged."))
                .font(.caption).foregroundStyle(.secondary)
        case .split:
            HStack(spacing: 14) {
                Picker(tr("Split mode"), selection: $m.splitMode) {
                    ForEach(SplitMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if m.splitMode == .chunks {
                    Stepper(tr("%d pages each", m.chunkSize), value: $m.chunkSize, in: 1...999)
                }
                Spacer()
            }
            Text(splitHint).font(.caption).foregroundStyle(.secondary)
        case .reorder:
            Text(tr("Drag the pages above into the order you want. Click another PDF in the list to arrange its pages. The PDF is saved as a new file."))
                .font(.caption).foregroundStyle(.secondary)
        case .wordToPDF:
            HStack(spacing: 14) {
                Toggle(tr("Combine into one PDF"), isOn: $m.wordCombine)
                Toggle(tr("Compress"), isOn: $m.wordCompress)
                if m.wordCompress {
                    Picker(tr("Level"), selection: $m.wordLevel) {
                        ForEach(Level.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Spacer()
            }
            HStack(spacing: 14) {
                Toggle(tr("Without tracked changes and comments"), isOn: $m.wordFinal)
                    .help(tr("Accepts all tracked changes and removes comments in the copy Word works on. The Word document itself stays unchanged."))
                Toggle(tr("Update fields and table of contents"), isOn: $m.wordUpdateFields)
                    .help(tr("Updates page numbers, cross-references and tables of contents before the PDF is made, as Word does before printing."))
                Spacer()
            }
            if m.wordCombine {
                HStack(spacing: 10) {
                    Text(tr("Name"))
                    TextField(tr("Name"), text: $m.wordCombinedName, prompt: Text(tr("Combined"))).labelsHidden().frame(width: 180)
                    Text(tr(".pdf")).foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                NameRuleEditor(rule: $m.wordRule, modes: NameMode.allCases, example: m.eligible.first?.url, placeholder: tr("Document ###"), outExt: ".pdf") {}
            }
            if m.wordCombine || m.wordRule.mode == .keep {
                Text(wordHint).font(.caption).foregroundStyle(.secondary)
            }
        case .extractImages:
            Toggle(tr("Skip small images (icons, lines, logos under %d px)", PDFImages.minSide), isOn: $m.skipSmallImages)
            Text(tr("Pictures are saved at their original resolution into a new folder. JPEGs are copied unchanged, others are saved as PNG."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var wordHint: String {
        m.wordCombine
            ? tr("Documents are added in list order, each with a bookmark. Drag to reorder or use Sort.")
            : tr("The PDFs get the names of the Word documents. Microsoft Word makes them, so they look exactly like the document in Word.")
    }

    var splitHint: String {
        switch m.splitMode {
        case .extract: tr("Makes a new PDF from the pages you click above. Add more PDFs to split into several at once.")
        case .each: tr("Makes one PDF per page. The page selection above limits which pages (all if none selected).")
        case .chunks: tr("Cuts the PDF into parts of %d pages. The page selection above limits which pages (all if none selected).", m.chunkSize)
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
        switch m.tool {
        case .combine: return tr("Create PDF")
        case .wordToPDF where m.wordCombine: return m.pending.isEmpty && !m.eligible.isEmpty ? tr("%@ Again", tr("Create PDF")) : tr("Create PDF")
        case .rename: return "\(tr("Rename")) (\(m.renameCount))"
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
    let example: URL?          // first file in the list, for the example in the hint
    let placeholder: String
    var outExt: String? = nil  // extension of the new files if it differs from the example's
    @ViewBuilder var extra: Extra

    var body: some View {
        Picker(tr("Name"), selection: $rule.mode) {
            ForEach(modes) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
        HStack(spacing: 8) {
            switch rule.mode {
            case .keep:
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
