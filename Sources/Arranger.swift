import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Page arranger

/// Thumbnails of all pages, shown below the file list; drag them into a new order. Changes apply right away.
struct PageArranger: View {
    let url: URL
    let pageCount: Int
    @State var order: [Int]          // original 0-based pages in their new order
    let onChange: ([Int]) -> Void
    @State private var thumbs: [Int: NSImage] = [:]
    @State private var dragging: Int? = nil

    var changed: Bool { order != Array(0..<pageCount) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Text(changed ? "Order changed" : "Original order").foregroundStyle(.secondary)
            }
            HStack {
                Button("Reverse") { withAnimation { order.reverse() } }
                Button("Reset") { withAnimation { order = Array(0..<pageCount) } }.disabled(!changed)
                Spacer()
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
                    ForEach(Array(order.enumerated()), id: \.element) { pos, page in
                        tile(page, at: pos)
                            .onDrag {
                                dragging = page
                                return NSItemProvider(object: String(page) as NSString)
                            }
                            .onDrop(of: [.text], delegate: MoveDrop(target: page, order: $order, dragging: $dragging))
                            .contextMenu {
                                Button("Move to Beginning") { move(page, to: 0) }.disabled(pos == 0)
                                Button("Move to End") { move(page, to: order.count) }.disabled(pos == order.count - 1)
                            }
                    }
                }
                .padding(4)
            }
            // Dropping between tiles or on empty space ends the drag cleanly
            .onDrop(of: [.text], isTargeted: nil) { _ in dragging = nil; return true }
            Text("Drag pages to move them. Right-click a page to move it to the beginning or end.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: order) { _, o in onChange(o) }
    }

    func tile(_ page: Int, at pos: Int) -> some View {
        VStack(spacing: 4) {
            Group {
                if let t = thumbs[page] { Image(nsImage: t).resizable().scaledToFit() }
                else { Rectangle().fill(.quaternary) }
            }
            .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.secondary.opacity(0.3), lineWidth: 1))
            HStack(spacing: 4) {
                Text("\(pos + 1)").font(.caption.bold())
                if page != pos {
                    Text("was \(page + 1)").font(.caption).foregroundStyle(Color.accentColor)
                }
            }
        }
        .opacity(dragging == page ? 0.35 : 1)
        .contentShape(Rectangle())
        .task { await loadThumb(page) }
    }

    func move(_ page: Int, to dest: Int) {
        guard let from = order.firstIndex(of: page) else { return }
        withAnimation { order.move(fromOffsets: [from], toOffset: dest) }
    }

    func loadThumb(_ i: Int) async {
        guard thumbs[i] == nil else { return }
        thumbs[i] = await pageThumbnail(url, i)
    }
}

/// Moves the dragged page live while it passes over other pages
private struct MoveDrop: DropDelegate {
    let target: Int
    @Binding var order: [Int]
    @Binding var dragging: Int?

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target,
              let from = order.firstIndex(of: d), let to = order.firstIndex(of: target) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            order.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
