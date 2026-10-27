import SwiftUI

struct ContentView: View {
    @StateObject var m: Model

    @MainActor init(model: Model? = nil) { _m = StateObject(wrappedValue: model ?? Model()) }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { Optional(m.tool) }, set: { if let t = $0 { m.tool = t } })) {
                Section("Convert & Compress") { toolRows([.convert, .compress, .resize]) }
                Section("Edit") { toolRows([.rotate, .strip, .rename]) }
                Section("PDF") { toolRows([.wordToPDF, .combine, .split, .reorder, .extractImages]) }
            }
            .disabled(m.busy)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            ToolView()
        }
        .environmentObject(m)
        .focusedSceneObject(m)
        .frame(minWidth: 880, minHeight: 580)
        .sheet(item: Binding(get: { m.items.first { $0.id == m.comparing && $0.output != nil } }, set: { m.comparing = $0?.id })) { it in
            CompareView(original: it.url, compressed: it.output!, isPDF: it.kind == .pdf) {
                try? FileManager.default.removeItem(at: it.output!)
                m.lastOutputs.removeAll { $0 == it.output }
                m.update(it.id) { $0.output = nil; $0.done = false; $0.status = "Compressed copy deleted" }
            }
        }
    }

    func toolRows(_ tools: [Tool]) -> some View {
        ForEach(tools) { t in Label(t.rawValue, systemImage: t.icon).tag(t) }
    }
}

struct ToolView: View {
    @EnvironmentObject var m: Model
    @State private var targeted = false

    var body: some View {
        let preview = m.tool == .rename ? m.renamePreview() : m.tool == .wordToPDF && !m.wordCombine ? m.wordNames().mapValues { $0 + ".pdf" } : [:]
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
        .padding(20)
        .navigationTitle(m.tool.rawValue)
        .navigationSubtitle(m.tool.subtitle)
        .toolbar { toolbar }
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
                    Label(dropHint, systemImage: m.tool.icon)
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
        switch m.tool {
        case .resize: "Drop photos or folders here"
        case .split, .reorder, .extractImages: "Drop PDFs here"
        case .wordToPDF: "Drop Word documents or folders here"
        default: "Drop photos, PDFs or folders here"
        }
    }

    @ViewBuilder func row(_ it: Item, preview: [Item.ID: String]) -> some View {
        let usable = m.tool.accepts(it.kind)
        HStack(spacing: 8) {
            Image(systemName: it.done && usable ? "checkmark.circle.fill" : it.failed ? "xmark.octagon.fill" : it.kind == .pdf ? "doc.richtext" : it.kind == .word ? "doc.text" : "photo")
                .foregroundStyle(it.done && usable ? .green : it.failed ? .red : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
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
            Text(usable ? it.status : "Not used by this tool")
                .foregroundStyle(it.failed ? Color.red : .secondary).font(.caption).lineLimit(1)
            if m.tool == .compress, it.output != nil {
                Button("Compare") { m.comparing = it.id }.controlSize(.small)
            }
            Button { m.remove(it.id) } label: { Label("Remove from List", systemImage: "xmark.circle.fill") }
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Remove from list").disabled(m.busy)
        }
        .opacity(usable ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([it.url]) }
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

    // MARK: Settings per tool

    @ViewBuilder var settings: some View {
        switch m.tool {
        case .convert:
            HStack(spacing: 14) {
                Picker("Format", selection: $m.format) {
                    ForEach(OutFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
                if m.format.isLossy {
                    Text("Quality")
                    Slider(value: $m.quality, in: 0.3...1.0) { Text("Quality") }.labelsHidden().frame(width: 100)
                    Text("\(Int(m.quality * 100)) %").monospacedDigit().frame(width: 40, alignment: .trailing)
                } else {
                    Text(m.format.hint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if m.hasPDF {   // own line: next to format + quality it overflows the minimum window width
                Picker("PDF pages at", selection: $m.dpi) {
                    Text("72 dpi (screen)").tag(72)
                    Text("150 dpi").tag(150)
                    Text("300 dpi (print)").tag(300)
                }
                .fixedSize()
            }
        case .compress:
            HStack(spacing: 14) {
                Picker("Compress by", selection: $m.compressBy) {
                    ForEach(CompressBy.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Divider().frame(height: 18)
                if m.compressBy == .level {
                    Picker("Level", selection: $m.level) {
                        ForEach(Level.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                } else {
                    Text("Smaller than")
                    TextField("Maximum size in MB", value: $m.targetMB, format: .number).labelsHidden().frame(width: 56).multilineTextAlignment(.trailing)
                    Text("MB")
                }
                Spacer()
            }
            Text(m.compressBy == .level ? m.level.hint : "Tries gentle settings first and only goes further when needed")
                .font(.caption).foregroundStyle(.secondary)
        case .resize:
            HStack(spacing: 10) {
                Picker("Resize by", selection: $m.resizeMode) {
                    ForEach(ResizeMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().fixedSize()
                .onChange(of: m.resizeMode) { _, new in
                    if new == .percent { m.resizeValue = 50 } else if m.resizeValue <= 100 { m.resizeValue = 2000 }
                }
                TextField("Size", value: $m.resizeValue, format: .number).labelsHidden().frame(width: 70).multilineTextAlignment(.trailing)
                Text(m.resizeMode == .percent ? "%" : "pixels")
                Text("Only makes photos smaller. Format and photo info are kept.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        case .rotate:
            HStack(spacing: 14) {
                Picker("Rotation", selection: $m.rotation) {
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
                Picker("Remove", selection: $m.stripMode) {
                    ForEach(StripMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Text(m.stripMode == .all
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
                Text("New name")
                TextField("New name", text: $m.renamePattern, prompt: Text("Photo ###")).labelsHidden().frame(width: 200)
                Stepper("starting at \(m.renameStart)", value: $m.renameStart, in: 0...99999)
                Spacer()
                if !m.lastRename.isEmpty {
                    Button("Undo Rename") { m.undoRename() }.disabled(m.busy)
                }
            }
            Text("# is replaced by the number (### → 001). Files are renamed in place, in list order. Drag to reorder or use Sort.")
                .font(.caption).foregroundStyle(.secondary)
        case .combine:
            HStack(spacing: 10) {
                Text("Name")
                TextField("Name", text: $m.combinedName, prompt: Text("Combined")).labelsHidden().frame(width: 180)
                Text(".pdf").foregroundStyle(.secondary)
                Divider().frame(height: 18)
                Picker("Photo pages", selection: $m.pageSize) {
                    ForEach(PageSize.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                Toggle("Margin", isOn: $m.pageMargin)
                Spacer()
            }
            Text("Files are added in list order. Drag to reorder or use Sort. PDF pages are added unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        case .split:
            HStack(spacing: 14) {
                Picker("Split mode", selection: $m.splitMode) {
                    ForEach(SplitMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if m.splitMode == .chunks {
                    Stepper("\(m.chunkSize) pages each", value: $m.chunkSize, in: 1...999)
                }
                Spacer()
            }
            Text(splitHint).font(.caption).foregroundStyle(.secondary)
        case .reorder:
            Text("Drag the pages above into the order you want. Click another PDF in the list to arrange its pages. The PDF is saved as a new file.")
                .font(.caption).foregroundStyle(.secondary)
        case .wordToPDF:
            HStack(spacing: 14) {
                Toggle("Combine into one PDF", isOn: $m.wordCombine)
                Toggle("Compress", isOn: $m.wordCompress)
                if m.wordCompress {
                    Picker("Level", selection: $m.wordLevel) {
                        ForEach(Level.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Spacer()
            }
            HStack(spacing: 14) {
                Toggle("Without tracked changes and comments", isOn: $m.wordFinal)
                    .help("Accepts all tracked changes and removes comments in the copy Word works on. The Word document itself stays unchanged.")
                Toggle("Update fields and table of contents", isOn: $m.wordUpdateFields)
                    .help("Updates page numbers, cross-references and tables of contents before the PDF is made, as Word does before printing.")
                Spacer()
            }
            if m.wordCombine {
                HStack(spacing: 10) {
                    Text("Name")
                    TextField("Name", text: $m.wordCombinedName, prompt: Text("Combined")).labelsHidden().frame(width: 180)
                    Text(".pdf").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
            HStack(spacing: 10) {
                Picker("PDF names", selection: $m.wordNaming) {
                    ForEach(WordNaming.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                switch m.wordNaming {
                case .keep:
                    EmptyView()
                case .affix:
                    TextField("Text before", text: $m.wordPrefix, prompt: Text("Before")).labelsHidden().frame(width: 110)
                    Text("name").foregroundStyle(.secondary)
                    TextField("Text after", text: $m.wordSuffix, prompt: Text("After")).labelsHidden().frame(width: 110)
                case .numbered:
                    TextField("New name", text: $m.wordPattern, prompt: Text("Document ###")).labelsHidden().frame(width: 180)
                    Stepper("starting at \(m.wordStart)", value: $m.wordStart, in: 0...99999)
                }
                Spacer()
            }
            }
            Text(wordHint).font(.caption).foregroundStyle(.secondary)
        case .extractImages:
            Toggle("Skip small images (icons, lines, logos under \(PDFImages.minSide) px)", isOn: $m.skipSmallImages)
            Text("Pictures are saved at their original resolution into a new folder. JPEGs are copied unchanged, others are saved as PNG.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var wordHint: String {
        m.wordCombine
            ? "Documents are added in list order, each with a bookmark. Drag to reorder or use Sort."
            : m.wordNaming == .numbered
            ? "# is replaced by the number (### → 001), in list order. Drag to reorder or use Sort."
            : "Microsoft Word makes the PDFs, so they look exactly like the document in Word. Documents you have open in Word stay open."
    }

    var splitHint: String {
        switch m.splitMode {
        case .extract: "Makes a new PDF from the pages you click above. Add more PDFs to split into several at once."
        case .each: "Makes one PDF per page. The page selection above limits which pages (all if none selected)."
        case .chunks: "Cuts the PDF into parts of \(m.chunkSize) pages. The page selection above limits which pages (all if none selected)."
        }
    }

    // MARK: Bottom bar

    var bottomBar: some View {
        HStack(spacing: 12) {
            if let s = m.summary {
                let bad = s.hasPrefix("Error") || s.hasPrefix("Nothing")
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
        switch m.tool {
        case .combine: return "Create PDF"
        case .wordToPDF where m.wordCombine: return m.pending.isEmpty && !m.eligible.isEmpty ? "Create PDF Again" : "Create PDF"
        case .rename: return "Rename (\(m.renameCount))"
        default:
            let n = m.pending.count
            return n == 0 && !m.eligible.isEmpty ? "\(m.tool.action) Again" : "\(m.tool.action) (\(n))"
        }
    }
}
