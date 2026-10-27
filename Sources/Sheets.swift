import PDFKit
import SwiftUI

// MARK: - Page picker

/// Page overview shown below the file list; every change is passed on right away.
struct PagePicker: View {
    let url: URL
    let pageCount: Int
    @State var selected: Set<Int>
    let onChange: (Set<Int>) -> Void
    @State private var thumbs: [Int: NSImage] = [:]
    @State private var rangeText = ""
    @State private var rangeError = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Text(tr("%d of %d selected", selected.isEmpty ? pageCount : selected.count, pageCount)).foregroundStyle(.secondary)
            }
            HStack {
                TextField(tr("Pages, e.g. 1-3, 5, 8-"), text: $rangeText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyRange)
                    .foregroundStyle(rangeError ? .red : .primary)
                Button(tr("Apply"), action: applyRange)
                Divider().frame(height: 18)
                Button(tr("All")) { selected = Set(0..<pageCount); rangeText = "" }
                Button(tr("None")) { selected = []; rangeText = "" }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        let on = selected.contains(i)
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let t = thumbs[i] { Image(nsImage: t).resizable().scaledToFit() }
                                    else { Rectangle().fill(.quaternary) }
                                }
                                .frame(height: 150)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(on ? Color.accentColor : .secondary.opacity(0.3), lineWidth: on ? 3 : 1))
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundStyle(on ? Color.accentColor : .secondary)
                                    .background(Circle().fill(.background))
                                    .padding(6)
                            }
                            Text("\(i + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if on { selected.remove(i) } else { selected.insert(i) }; rangeText = rangeString(selected) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(tr("Page %d", i + 1))
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { if on { selected.remove(i) } else { selected.insert(i) }; rangeText = rangeString(selected) }
                        .task { await loadThumb(i) }
                    }
                }
                .padding(4)
            }
            Text(tr("No pages selected = all pages are used")).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { rangeText = rangeString(selected) }
        .onChange(of: selected) { _, s in onChange(s.count == pageCount ? [] : s) }
    }

    func applyRange() {
        if rangeText.trimmingCharacters(in: .whitespaces).isEmpty { selected = []; rangeError = false; return }
        if let r = parseRanges(rangeText, pageCount: pageCount) { selected = r; rangeError = false }
        else { rangeError = true; NSSound.beep() }
    }

    func loadThumb(_ i: Int) async {
        guard thumbs[i] == nil else { return }
        thumbs[i] = await pageThumbnail(url, i)
    }
}

func pageThumbnail(_ url: URL, _ i: Int) async -> NSImage? {
    await Task.detached { () -> NSImage? in
        guard let doc = PDFDocument(url: url), let page = doc.page(at: i) else { return nil }
        return withExtendedLifetime(doc) { page.thumbnail(of: NSSize(width: 240, height: 300), for: .mediaBox) }
    }.value
}

// MARK: - Assign pages to several PDFs (Split)

let partColors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .indigo, .brown, .mint, .yellow, .cyan]
func partColor(_ n: Int) -> Color { partColors[n % partColors.count] }

/// Click pages to put them into the new PDF; "New PDF" adds more, each shown in its own colour.
struct PartsPicker: View {
    let url: URL
    let pageCount: Int
    let onChange: ([[Int]], [String]) -> Void
    @State private var parts: [Set<Int>]
    @State private var names: [String]   // same length as parts; "" = default name
    @State private var active = 0
    @State private var lastClicked: Int? = nil
    @State private var thumbs: [Int: NSImage] = [:]
    @State private var rangeText = ""
    @State private var rangeError = false

    init(url: URL, pageCount: Int, parts: [[Int]], names: [String], onChange: @escaping ([[Int]], [String]) -> Void) {
        self.url = url
        self.pageCount = pageCount
        self.onChange = onChange
        _parts = State(initialValue: parts.isEmpty ? [[]] : parts.map(Set.init))
        _names = State(initialValue: parts.isEmpty ? [""] : parts.indices.map { $0 < names.count ? names[$0] : "" })
    }

    /// File name used when the name field is left empty
    func defaultName(_ n: Int) -> String {
        let used = parts.filter { !$0.isEmpty }
        let k = parts[..<n].filter { !$0.isEmpty }.count
        return PDFOps.partName(url.deletingPathExtension().lastPathComponent, parts[n].sorted(), n: k, count: max(1, used.count))
    }

    /// Passes on the non-empty parts with their names
    func report() {
        let keep = parts.indices.filter { !parts[$0].isEmpty }
        onChange(keep.map { parts[$0].sorted() }, keep.map { names[$0] })
    }

    func part(of page: Int) -> Int? { parts.firstIndex { $0.contains(page) } }
    var assignedCount: Int { parts.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Text(tr("%d of %d pages selected", assignedCount, pageCount)).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(parts.indices, id: \.self) { n in chip(n) }
                    Button { parts.append([]); names.append(""); active = parts.count - 1; lastClicked = nil } label: {
                        Label(tr("New PDF"), systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                .padding(2)
            }
            HStack {
                TextField(tr("Pages for PDF %d, e.g. 1-3, 5", active + 1), text: $rangeText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyRange)
                    .foregroundStyle(rangeError ? .red : .primary)
                Button(tr("Add"), action: applyRange)
                Divider().frame(height: 18)
                Button(tr("All Remaining")) { assign(Set(0..<pageCount).filter { part(of: $0) == nil }) }
                    .disabled(assignedCount == pageCount)
                Button(tr("Clear All")) { parts = [[]]; names = [""]; active = 0; lastClicked = nil }
            }
            HStack {
                Text(tr("Name"))
                TextField(tr("File name for PDF %d", active + 1), text: $names[active],
                          prompt: Text(parts[active].isEmpty ? tr("Optional") : defaultName(active)))
                    .textFieldStyle(.roundedBorder).labelsHidden()
                Text(tr(".pdf")).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
                    ForEach(0..<pageCount, id: \.self) { i in tile(i) }
                }
                .padding(4)
            }
            Text(tr("Click pages to add them to the new PDF, shift-click for a range. Use New PDF to make several PDFs at once, each in its own colour."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: parts) { report() }
        .onChange(of: names) { report() }
    }

    func chip(_ n: Int) -> some View {
        let on = n == active
        return HStack(spacing: 6) {
            Circle().fill(partColor(n)).frame(width: 12, height: 12)
            Text(names[n].trimmingCharacters(in: .whitespaces).isEmpty ? "PDF \(n + 1)" : names[n])
                .fontWeight(on ? .semibold : .regular).lineLimit(1).truncationMode(.middle).frame(maxWidth: 180)
            Text("\(parts[n].count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if on && parts.count > 1 {
                Button { removePart(n) } label: { Label(tr("Remove PDF %d", n + 1), systemImage: "xmark.circle.fill") }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary).help(tr("Remove this PDF"))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(partColor(n).opacity(on ? 0.22 : 0.08)))
        .overlay(Capsule().stroke(on ? partColor(n) : .clear, lineWidth: 2))
        .contentShape(Capsule())
        .onTapGesture { active = n; lastClicked = nil; rangeText = "" }
    }

    func tile(_ i: Int) -> some View {
        let p = part(of: i)
        let color = p.map(partColor) ?? .secondary.opacity(0.3)
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let t = thumbs[i] { Image(nsImage: t).resizable().scaledToFit() }
                    else { Rectangle().fill(.quaternary) }
                }
                .frame(height: 150)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(p.map { partColor($0).opacity(0.12) } ?? .clear))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(color, lineWidth: p == nil ? 1 : 3))
                if let p {
                    Text("\(p + 1)").font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Circle().fill(partColor(p)))
                        .padding(6)
                }
            }
            Text("\(i + 1)").font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { click(i) }
        .task { if thumbs[i] == nil { thumbs[i] = await pageThumbnail(url, i) } }
    }

    func click(_ i: Int) {
        if NSEvent.modifierFlags.contains(.shift), let last = lastClicked {
            assign(Set(min(last, i)...max(last, i)))
        } else if parts[active].contains(i) {
            parts[active].remove(i)
        } else {
            assign([i])
        }
        lastClicked = i
    }

    /// Gives pages the active colour, taking them away from any other
    func assign(_ pages: Set<Int>) {
        for n in parts.indices where n != active { parts[n].subtract(pages) }
        parts[active].formUnion(pages)
    }

    func removePart(_ n: Int) {
        parts.remove(at: n)
        names.remove(at: n)
        active = min(n, parts.count - 1)
        lastClicked = nil
    }

    func applyRange() {
        guard !rangeText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let r = parseRanges(rangeText, pageCount: pageCount) { assign(r); rangeText = ""; rangeError = false }
        else { rangeError = true; NSSound.beep() }
    }
}

// MARK: - Before / after

/// Original and compressed version on top of each other; drag the divider to compare.
struct CompareView: View {
    let original: URL
    let compressed: URL
    let isPDF: Bool
    let onDiscard: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var page = 0
    @State private var pageCount = 1
    @State private var split: CGFloat = 0.5
    @State private var zoom: CGFloat = 1
    @State private var before: NSImage?
    @State private var after: NSImage?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(tr("Original · %@", fmtSize(fileSize(original))), systemImage: "arrow.left")
                Spacer()
                Text(tr("Drag to compare")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Label(tr("Compressed · %@", fmtSize(fileSize(compressed))), systemImage: "arrow.right")
                    .labelStyle(TrailingIcon())
            }
            .font(.headline)

            GeometryReader { geo in
                if let before, let after {
                    let fit = min(geo.size.width / before.size.width, geo.size.height / before.size.height)
                    let size = CGSize(width: before.size.width * fit * zoom, height: before.size.height * fit * zoom)
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            Image(nsImage: after).resizable().interpolation(.high)
                            Image(nsImage: before).resizable().interpolation(.high)
                                .mask(alignment: .leading) { Rectangle().frame(width: size.width * split) }
                            Rectangle().fill(.white).frame(width: 2)
                                .shadow(color: .black.opacity(0.6), radius: 2)
                                .offset(x: size.width * split - 1)
                        }
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged {
                            split = min(1, max(0, $0.location.x / size.width))
                        })
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                if isPDF && pageCount > 1 {
                    Stepper(tr("Page %d of %d", page + 1, pageCount), value: $page, in: 0...(pageCount - 1))
                }
                Picker(tr("Zoom"), selection: $zoom) {
                    Text(tr("Fit")).tag(CGFloat(1))
                    Text(tr("2×")).tag(CGFloat(2))
                    Text(tr("4×")).tag(CGFloat(4))
                }
                .pickerStyle(.segmented).fixedSize()
                Spacer()
                Button(tr("Move Compressed Copy to Trash"), role: .destructive) { onDiscard(); dismiss() }
                Button(tr("Keep")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 640)
        .task(id: page) { await load() }
    }

    func load() async {
        let original = original, compressed = compressed, isPDF = isPDF, page = page
        let (b, a, count) = await Task.detached { () -> (NSImage?, NSImage?, Int) in
            if isPDF {
                func render(_ u: URL) -> (NSImage?, Int) {
                    guard let doc = PDFDocument(url: u), let p = doc.page(at: page), let img = PDFOps.render(p, dpi: 200) else { return (nil, 0) }
                    return (NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)), doc.pageCount)
                }
                let (b, n) = render(original)
                return (b, render(compressed).0, n)
            }
            return (NSImage(contentsOf: original), NSImage(contentsOf: compressed), 1)
        }.value
        before = b
        after = a
        pageCount = max(1, count)
    }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack { configuration.title; configuration.icon }
    }
}
