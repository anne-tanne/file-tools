import CoreGraphics
import Foundation
import PDFKit
import Vision

enum CSVSeparator: String, CaseIterable, Identifiable, Codable, Sendable, Titled {
    case semicolon = "Semicolon", comma = "Comma"
    var id: String { rawValue }
    var char: String { self == .semicolon ? ";" : "," }
}

/// Finds tables with Vision's document recognition (macOS 26) and saves them as CSV for Excel
enum Tables {
    typealias Grid = [[String]]

    /// One table → "name (table).csv"; several → a new folder "name (tables)" with "Page 3, table 1.csv" (photos: "Table 1.csv").
    /// Returns the file (or the folder) and the number of tables found.
    static func extract(_ src: URL, kind: Kind, pages: [Int], separator: CSVSeparator, folder: URL?,
                        progress: (Int, Int) -> Void) throws -> (files: [URL], tables: Int) {
        var found: [(page: Int?, grid: Grid)] = []
        if kind == .pdf {
            let pdf = try PDFOps.open(src)
            for (n, i) in pages.enumerated() {
                progress(n + 1, pages.count)
                guard let page = pdf.page(at: i) else { continue }
                guard let img = PDFOps.render(page, dpi: 300) else { throw ConvError(tr("Page %d can't be rendered", i + 1)) }
                found += try grids(in: img).map { (i + 1, $0) }
            }
        } else {
            progress(1, 1)
            found = try grids(in: try ImageOps.upright(try ImageOps.source(src))).map { (nil, $0) }
        }
        guard !found.isEmpty else { throw Skipped(tr("No tables found")) }

        do {
            if found.count == 1 {
                let out = outputURL(for: src, suffix: "table", ext: "csv", folder: folder)
                try csv(found[0].grid, separator: separator).write(to: out)
                return ([out], 1)
            }
            let base = src.deletingPathExtension().lastPathComponent
            let dir = uniqueURL(folder ?? src.deletingLastPathComponent(), "\(base) (tables)", "")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var perPage: [Int: Int] = [:]
            for t in found {
                let key = t.page ?? 0
                perPage[key, default: 0] += 1
                let n = perPage[key]!
                let name = t.page.map { tr("Page %d, table %d", $0, n) } ?? tr("Table %d", n)
                try csv(t.grid, separator: separator).write(to: uniqueURL(dir, name, "csv"))
            }
            return ([dir], found.count)
        } catch { throw ConvError(tr("Writing failed")) }
    }

    // MARK: Recognition

    /// Every table on one image as a rectangular grid of cell texts
    static func grids(in img: CGImage) throws -> [Grid] {
        let result: [DocumentObservation]
        do { result = try waitFor { try await RecognizeDocumentsRequest().perform(on: img) } }
        catch { throw ConvError(tr("Table recognition failed")) }
        return result.flatMap { $0.document.tables }.map(grid).filter { !$0.isEmpty && !$0[0].isEmpty }
    }

    /// A cell spanning several rows or columns puts its text in the first field; the others stay empty
    private static func grid(_ table: DocumentObservation.Container.Table) -> Grid {
        let cells = table.rows.flatMap { $0 }
        let rows = (cells.map(\.rowRange.upperBound).max() ?? -1) + 1
        let cols = (cells.map(\.columnRange.upperBound).max() ?? -1) + 1
        var g = Grid(repeating: Array(repeating: "", count: cols), count: rows)
        for c in cells {
            let r = c.rowRange.lowerBound, k = c.columnRange.lowerBound
            guard r >= 0, k >= 0, r < rows, k < cols else { continue }
            g[r][k] = c.content.text.transcript
        }
        return g
    }

    // MARK: CSV

    /// UTF-8 with BOM and CRLF line ends, so Excel opens it directly
    static func csv(_ grid: Grid, separator: CSVSeparator) -> Data {
        let sep = separator.char
        func field(_ s: String) -> String {
            let t = s.components(separatedBy: .newlines).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            guard t.contains(sep) || t.contains("\"") else { return t }
            return "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let text = grid.map { $0.map(field).joined(separator: sep) }.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }
}
