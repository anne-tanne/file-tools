import SwiftUI

struct ContentView: View {
    @StateObject var m: Model

    @MainActor init(model: Model? = nil) { _m = StateObject(wrappedValue: model ?? Model()) }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { Optional(m.tool) }, set: { if let t = $0 { m.tool = t } })) {
                Section("Convert & Compress") { toolRows([.convert, .compress, .resize]) }
                Section("Edit") { toolRows([.rotate, .strip, .rename]) }
                Section("PDF") { toolRows([.combine, .split]) }
            }
            .disabled(m.busy)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            ToolView()
        }
        .environmentObject(m)
        .frame(minWidth: 880, minHeight: 580)
        .sheet(item: Binding(get: { m.items.first { $0.id == m.editing } }, set: { m.editing = $0?.id })) { it in
            PagePicker(url: it.url, pageCount: it.pageCount, selected: it.selected) { sel in
                m.update(it.id) { $0.selected = sel; $0.done = false; $0.failed = false; $0.status = "Ready" }
            }
        }
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
        let preview = m.tool == .rename ? m.renamePreview() : [:]
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.tool.rawValue).font(.title2.bold())
                Text(m.tool.subtitle).foregroundStyle(.secondary)
            }

            dropZone(preview)
                .layoutPriority(1)   // the list gets the free space, settings only what they need

            VStack(alignment: .leading, spacing: 6) { settings }

            if m.tool.writesFiles {
                HStack {
                    Text("Save to:")
                    Text(m.outputFolder?.path ?? "same folder as original")
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if m.outputFolder != nil { Button("Reset") { m.outputFolder = nil } }
                    Button("Choose Folder…") { m.pickFolder() }
                }
            }

            if let s = m.summary {
                Label(s, systemImage: s.hasPrefix("Error") || s.hasPrefix("Nothing") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(s.hasPrefix("Error") || s.hasPrefix("Nothing") ? Color.red : Color.green)
            }

            bottomBar
        }
        .padding(20)
        .navigationTitle("Image Converter")
    }

    // MARK: File list

    func dropZone(_ preview: [Item.ID: String]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7]))
                .foregroundStyle(targeted ? Color.accentColor : .secondary.opacity(0.5))
                .background(RoundedRectangle(cornerRadius: 14).fill(targeted ? Color.accentColor.opacity(0.08) : .clear))
            if m.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: m.tool.icon).font(.system(size: 36)).foregroundStyle(.secondary)
                    Text(dropHint).font(.headline)
                    Button("Choose Files…") { m.pickFiles() }
                }
            } else {
                List {
                    ForEach(m.items) { it in row(it, preview: preview) }
                        .onMove { m.items.move(fromOffsets: $0, toOffset: $1) }
                }
                .scrollContentBackground(.hidden)
                .padding(6)
            }
        }
        .frame(minHeight: 220)
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
        case .split: "Drop PDFs here"
        default: "Drop photos, PDFs or folders here"
        }
    }

    @ViewBuilder func row(_ it: Item, preview: [Item.ID: String]) -> some View {
        let usable = m.tool.accepts(it.kind)
        HStack(spacing: 8) {
            Image(systemName: it.done && usable ? "checkmark.circle.fill" : it.failed ? "xmark.octagon.fill" : it.kind == .pdf ? "doc.richtext" : "photo")
                .foregroundStyle(it.done && usable ? .green : it.failed ? .red : .secondary)
                .frame(width: 18)
            Text(it.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            if usable && it.kind == .pdf && m.tool.usesPages {
                Button { m.editing = it.id } label: {
                    Label("Select Pages…", systemImage: "square.grid.2x2").font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small).disabled(m.busy)
                Text(it.pageSummary).font(.caption).foregroundStyle(.secondary)
            }
            if m.tool == .rename, !it.done, let new = preview[it.id], new != it.url.lastPathComponent {
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Text(new).foregroundStyle(Color.accentColor).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(usable ? it.status : "Not used by this tool")
                .foregroundStyle(it.failed ? Color.red : .secondary).font(.caption).lineLimit(1)
            if m.tool == .compress, it.output != nil {
                Button("Compare") { m.comparing = it.id }.controlSize(.small)
            }
            Button { m.remove(it.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(m.busy)
        }
        .opacity(usable ? 1 : 0.45)
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
                    Slider(value: $m.quality, in: 0.3...1.0).frame(width: 100)
                    Text("\(Int(m.quality * 100)) %").monospacedDigit().frame(width: 40, alignment: .trailing)
                } else {
                    Text(m.format.hint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if m.hasPDF {
                    Picker("PDF pages at", selection: $m.dpi) {
                        Text("72 dpi (screen)").tag(72)
                        Text("150 dpi").tag(150)
                        Text("300 dpi (print)").tag(300)
                    }
                    .fixedSize()
                }
            }
        case .compress:
            HStack(spacing: 14) {
                Picker("", selection: $m.compressBy) {
                    ForEach(CompressBy.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Divider().frame(height: 18)
                if m.compressBy == .level {
                    Picker("", selection: $m.level) {
                        ForEach(Level.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                } else {
                    Text("Smaller than")
                    TextField("", value: $m.targetMB, format: .number).frame(width: 56).multilineTextAlignment(.trailing)
                    Text("MB")
                }
                Spacer()
            }
            Text(m.compressBy == .level ? m.level.hint : "Tries gentle settings first and only goes further when needed")
                .font(.caption).foregroundStyle(.secondary)
        case .resize:
            HStack(spacing: 10) {
                Picker("", selection: $m.resizeMode) {
                    ForEach(ResizeMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().fixedSize()
                .onChange(of: m.resizeMode) { _, new in
                    if new == .percent { m.resizeValue = 50 } else if m.resizeValue <= 100 { m.resizeValue = 2000 }
                }
                TextField("", value: $m.resizeValue, format: .number).frame(width: 70).multilineTextAlignment(.trailing)
                Text(m.resizeMode == .percent ? "%" : "pixels")
                Text("Only makes photos smaller. Format and photo info are kept.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        case .rotate:
            HStack(spacing: 14) {
                Picker("", selection: $m.rotation) {
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
                Picker("", selection: $m.stripMode) {
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
                TextField("Photo ###", text: $m.renamePattern).frame(width: 200)
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
                TextField("Combined", text: $m.combinedName).frame(width: 180)
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
                Picker("", selection: $m.splitMode) {
                    ForEach(SplitMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if m.splitMode == .chunks {
                    Stepper("\(m.chunkSize) pages each", value: $m.chunkSize, in: 1...999)
                }
                Spacer()
            }
            Text("Use Select Pages… to choose which pages are used (all if none selected).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Bottom bar

    var bottomBar: some View {
        HStack {
            if !m.items.isEmpty {
                Button("Add…") { m.pickFiles() }
                Button("Clear List") { m.items.removeAll(); m.summary = nil; m.lastRename = [] }.disabled(m.busy)
                if m.items.count > 1 {
                    Menu("Sort") {
                        Button("By Name") { m.sort(.name) }
                        Button("By Date Taken") { m.sort(.date) }
                        Divider()
                        Button("Reverse Order") { m.items.reverse() }
                    }
                    .fixedSize().disabled(m.busy)
                }
            }
            Spacer()
            if !m.lastOutputs.isEmpty && !m.busy {
                Button("Show in Finder") { m.showInFinder() }
            }
            if m.busy { ProgressView().controlSize(.small) }
            Button(actionTitle) { m.run() }
                .keyboardShortcut(.defaultAction)
                .disabled(m.busy || actionDisabled)
        }
    }

    var actionTitle: String {
        switch m.tool {
        case .combine: return "Create PDF"
        case .rename: return "Rename (\(m.renameCount))"
        default:
            let n = m.pending.count
            return n == 0 && !m.eligible.isEmpty ? "\(m.tool.action) Again" : "\(m.tool.action) (\(n))"
        }
    }

    var actionDisabled: Bool {
        switch m.tool {
        case .rename: m.renameCount == 0
        default: m.eligible.isEmpty
        }
    }
}
