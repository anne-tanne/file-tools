import Foundation

enum Compressor {
    /// Compresses into "name (compressed).ext". With a target size, tries gentle settings first and
    /// only gets stronger as needed; keeps the smallest result if the target can't be reached.
    static func run(_ src: URL, kind: Kind, level: Level, target: Int64?, folder: URL?,
                    progress: (String) -> Void) throws -> URL {
        let before = fileSize(src)
        let ext = kind == .pdf ? "pdf" : (ImageOps.outputType(try ImageOps.source(src)).ext ?? src.pathExtension)

        let steps: Int
        let attempt: (Int, URL) throws -> Void
        if let target {
            guard before > target else { throw Skipped("Already under \(fmtSize(target))") }
            if kind == .pdf {
                steps = Level.pdfLadder.count
                attempt = { i, u in try PDFOps.compress(src, dpi: Level.pdfLadder[i].dpi, quality: Level.pdfLadder[i].quality, to: u) }
            } else {
                steps = Level.imageLadder.count
                attempt = { i, u in try ImageOps.compress(src, quality: Level.imageLadder[i].quality, maxEdge: Level.imageLadder[i].edge, to: u) }
            }
        } else {
            steps = 1
            if kind == .pdf {
                attempt = { _, u in try PDFOps.compress(src, dpi: level.pdfDPI, quality: level.quality, to: u) }
            } else {
                attempt = { _, u in try ImageOps.compress(src, quality: level.quality, maxEdge: level.maxEdge, to: u) }
            }
        }

        let fm = FileManager.default
        var best: (url: URL, size: Int64)? = nil
        do {
            for i in 0..<steps {
                if steps > 1 { progress("Trying step \(i + 1) of \(steps)…") }
                let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                try attempt(i, tmp)
                let size = fileSize(tmp)
                if let b = best, b.size <= size {
                    try? fm.removeItem(at: tmp)
                } else {
                    if let b = best { try? fm.removeItem(at: b.url) }
                    best = (tmp, size)
                }
                if let target, size <= target { break }
            }
        } catch {
            if let b = best { try? fm.removeItem(at: b.url) }
            throw error
        }
        guard let b = best, Double(b.size) <= Double(before) * 0.95 else {
            if let b = best { try? fm.removeItem(at: b.url) }
            throw Skipped("Already small, original kept")
        }
        let out = outputURL(for: src, suffix: "compressed", ext: ext, folder: folder)
        try fm.moveItem(at: b.url, to: out)
        return out
    }
}
