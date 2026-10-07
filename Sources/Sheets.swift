import PDFKit
import SwiftUI

// MARK: - Page picker

struct PagePicker: View {
    let url: URL
    let pageCount: Int
    @State var selected: Set<Int>
    let onDone: (Set<Int>) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var thumbs: [Int: NSImage] = [:]
    @State private var rangeText = ""
    @State private var rangeError = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Text("\(selected.isEmpty ? pageCount : selected.count) of \(pageCount) selected").foregroundStyle(.secondary)
            }
            HStack {
                TextField("Pages, e.g. 1-3, 5, 8-", text: $rangeText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyRange)
                    .foregroundStyle(rangeError ? .red : .primary)
                Button("Apply", action: applyRange)
                Divider().frame(height: 18)
                Button("All") { selected = Set(0..<pageCount); rangeText = "" }
                Button("None") { selected = []; rangeText = "" }
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
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Color.accentColor : .secondary.opacity(0.3), lineWidth: on ? 3 : 1))
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundStyle(on ? Color.accentColor : .secondary)
                                    .background(Circle().fill(.background))
                                    .padding(6)
                            }
                            Text("\(i + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if on { selected.remove(i) } else { selected.insert(i) }; rangeText = rangeString(selected) }
                        .task { await loadThumb(i) }
                    }
                }
                .padding(4)
            }
            HStack {
                Text("No pages selected = all pages are converted").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") {
                    onDone(selected.count == pageCount ? [] : selected)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 560)
        .onAppear { rangeText = rangeString(selected) }
    }

    func applyRange() {
        if rangeText.trimmingCharacters(in: .whitespaces).isEmpty { selected = []; rangeError = false; return }
        if let r = parseRanges(rangeText, pageCount: pageCount) { selected = r; rangeError = false }
        else { rangeError = true; NSSound.beep() }
    }

    func loadThumb(_ i: Int) async {
        guard thumbs[i] == nil else { return }
        let url = url
        let img = await Task.detached { () -> NSImage? in
            guard let page = PDFDocument(url: url)?.page(at: i) else { return nil }
            return page.thumbnail(of: NSSize(width: 240, height: 300), for: .mediaBox)
        }.value
        thumbs[i] = img
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
                Label("Original · \(fmtSize(fileSize(original)))", systemImage: "arrow.left")
                Spacer()
                Text("Drag to compare").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Label("Compressed · \(fmtSize(fileSize(compressed)))", systemImage: "arrow.right")
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
            .background(Color.black.opacity(0.05))

            HStack {
                if isPDF && pageCount > 1 {
                    Stepper("Page \(page + 1) of \(pageCount)", value: $page, in: 0...(pageCount - 1))
                }
                Picker("Zoom", selection: $zoom) {
                    Text("Fit").tag(CGFloat(1))
                    Text("2×").tag(CGFloat(2))
                    Text("4×").tag(CGFloat(4))
                }
                .pickerStyle(.segmented).fixedSize()
                Spacer()
                Button("Delete Compressed Copy", role: .destructive) { onDiscard(); dismiss() }
                Button("Keep") { dismiss() }.keyboardShortcut(.defaultAction)
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
