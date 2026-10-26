import AppKit
import ImageIO
import PDFKit
import Quartz

enum PDFOps {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let d = PDFDocument(url: url) else { throw ConvError(tr("PDF can't be read")) }
        if d.isLocked { throw ConvError(tr("PDF is password protected")) }
        return d
    }

    static func save(_ doc: PDFDocument, to out: URL, options: [PDFDocumentWriteOption: Any] = [:]) throws {
        guard doc.write(to: out, withOptions: options) else {
            try? FileManager.default.removeItem(at: out)
            throw ConvError(tr("Writing failed"))
        }
    }

    /// New document with copies of the given pages
    static func extract(_ doc: PDFDocument, _ pages: [Int]) -> PDFDocument {
        let n = PDFDocument()
        for i in pages {
            if let p = doc.page(at: i)?.copy() as? PDFPage { n.insert(p, at: n.pageCount) }
        }
        return n
    }

    // MARK: Pages to images

    static func render(_ page: PDFPage, dpi: Int) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let scale = CGFloat(dpi) / 72
        let w = Int(((rotated ? box.height : box.width) * scale).rounded())
        let h = Int(((rotated ? box.width : box.height) * scale).rounded())
        guard w > 0, h > 0, let ctx = ImageOps.context(w, h) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)   // applies page rotation
        return ctx.makeImage()
    }

    static func toImages(_ src: URL, pages: [Int], to fmt: OutFormat, quality: Double, dpi: Int, folder: URL?,
                         progress: (Int) -> Void) throws -> [URL] {
        let doc = try open(src)
        let dir = folder ?? src.deletingLastPathComponent()
        let base = src.deletingPathExtension().lastPathComponent
        let digits = String(doc.pageCount).count
        var outs: [URL] = []
        for (n, i) in pages.enumerated() {
            progress(n + 1)
            guard let page = doc.page(at: i), let img = render(page, dpi: dpi) else {
                throw ConvError(tr("Page %d can't be rendered", i + 1))
            }
            let name = doc.pageCount == 1 ? base : "\(base) - \(tr("page")) \(String(format: "%0\(digits)d", i + 1))"
            let out = uniqueURL(dir, name, fmt.ext)
            var p: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
            if fmt.isLossy { p[kCGImageDestinationLossyCompressionQuality] = quality }
            try ImageOps.write(out, type: fmt.utType.identifier as CFString) { CGImageDestinationAddImage($0, img, p as CFDictionary) }
            outs.append(out)
        }
        return outs
    }

    // MARK: Compress

    /// Recompresses the images inside the PDF; text and vector graphics stay untouched.
    static func compress(_ src: URL, dpi: Int, quality: Double, to out: URL) throws {
        let doc = try open(src)
        let filterData: [String: Any] = [
            "Domains": ["Applications": true, "Printing": true],
            "FilterType": 1,
            "Name": "File Tools",
            "FilterData": ["ColorSettings": ["ImageSettings": [
                "Compression Quality": quality,
                "ImageCompression": "ImageJPEGCompress",
                "ImageScaleSettings": ["ImageResolution": dpi, "ImageScaleInterpolate": true,
                                       "ImageSizeMax": 20000, "ImageSizeMin": 0],
            ]]],
        ]
        let qf = FileManager.default.temporaryDirectory
            .appendingPathComponent("filetools-\(dpi)-\(Int(quality * 100)).qfilter")
        guard (filterData as NSDictionary).write(to: qf, atomically: true), let filter = QuartzFilter(url: qf) else {
            throw ConvError(tr("Compression filter unavailable"))
        }
        try save(doc, to: out, options: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter])
    }

    // MARK: Split

    /// Default file name (without extension) of part n of `count` in `.extract` mode
    static func partName(_ base: String, _ part: [Int], n: Int, count: Int) -> String {
        let pages = "(\(tr("pages")) \(rangeString(Set(part))))"
        return count == 1 ? "\(base) \(pages)" : "\(base) - \(tr("part")) \(n + 1) \(pages)"
    }

    /// parts: page groups for `.extract` mode, one PDF each (chosen in the parts picker);
    /// names: optional file names for those PDFs, empty = default name
    static func split(_ src: URL, pages: [Int], mode: SplitMode, chunk: Int, parts: [[Int]] = [], names: [String] = [],
                      folder: URL?) throws -> [URL] {
        let doc = try open(src)
        let base = src.deletingPathExtension().lastPathComponent
        let dir = folder ?? src.deletingLastPathComponent()
        let digits = String(doc.pageCount).count
        func pad(_ i: Int) -> String { String(format: "%0\(digits)d", i + 1) }
        let groups: [(name: String, pages: [Int])]
        switch mode {
        case .extract:
            guard !parts.isEmpty else { throw ConvError(tr("No pages selected yet: click pages in the overview first")) }
            groups = parts.enumerated().map { n, part in
                var name = n < names.count ? names[n].trimmingCharacters(in: .whitespaces) : ""
                if name.lowercased().hasSuffix(".pdf") { name = String(name.dropLast(4)).trimmingCharacters(in: .whitespaces) }
                return (name.isEmpty ? partName(base, part, n: n, count: parts.count) : name, part)
            }
        case .each:
            groups = pages.map { ("\(base) - \(tr("page")) \(pad($0))", [$0]) }
        case .chunks:
            let size = max(1, chunk)
            groups = stride(from: 0, to: pages.count, by: size).enumerated().map { n, start in
                let part = Array(pages[start..<min(start + size, pages.count)])
                return ("\(base) - \(tr("part")) \(n + 1) (\(tr("pages")) \(rangeString(Set(part))))", part)
            }
        }
        return try groups.map { g in
            let out = uniqueURL(dir, g.name, "pdf")
            try save(extract(doc, g.pages), to: out)
            return out
        }
    }

    // MARK: Rotate

    /// degrees: 90 = clockwise, 180, 270 = counter-clockwise
    static func rotate(_ src: URL, pages: [Int], degrees: Int, folder: URL?) throws -> URL {
        let doc = try open(src)
        for i in pages {
            if let p = doc.page(at: i) { p.rotation = (p.rotation + degrees) % 360 }
        }
        let out = outputURL(for: src, suffix: tr("rotated"), ext: "pdf", folder: folder)
        try save(doc, to: out)
        return out
    }

    // MARK: Reorder

    /// order: original 0-based page indices in their new order. Pages are moved within the document,
    /// so bookmarks, links and document info stay intact.
    static func reorder(_ src: URL, order: [Int], folder: URL?) throws -> URL {
        let doc = try open(src)
        guard order.sorted() == Array(0..<doc.pageCount) else { throw ConvError(tr("Page order doesn't match the PDF")) }
        let pages = order.compactMap { doc.page(at: $0) }
        for (pos, page) in pages.enumerated() {
            let cur = doc.index(for: page)
            if cur != pos { doc.exchangePage(at: cur, withPageAt: pos) }
        }
        let out = outputURL(for: src, suffix: tr("reordered"), ext: "pdf", folder: folder)
        try save(doc, to: out)
        return out
    }

    // MARK: Remove info

    static func stripInfo(_ src: URL, folder: URL?) throws -> URL {
        let doc = try open(src)
        doc.documentAttributes = [:]
        let out = outputURL(for: src, suffix: tr("no info"), ext: "pdf", folder: folder)
        try save(doc, to: out)
        return out
    }

    // MARK: Combine

    static func combine(_ entries: [(url: URL, kind: Kind)], pageSize: PageSize, margin: Bool, to out: URL,
                        progress: (Int) -> Void) throws -> Int {
        let result = PDFDocument()
        for (n, e) in entries.enumerated() {
            progress(n + 1)
            do { try add(e) } catch {
                // Say which file stopped the whole PDF
                throw ConvError("\(e.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        func add(_ e: (url: URL, kind: Kind)) throws {
            switch e.kind {
            case .pdf:
                let doc = try open(e.url)
                for i in 0..<doc.pageCount {
                    if let p = doc.page(at: i)?.copy() as? PDFPage { result.insert(p, at: result.pageCount) }
                }
            case .image:
                result.insert(try imagePage(e.url, pageSize: pageSize, margin: margin), at: result.pageCount)
            case .word:
                break   // not accepted by Combine
            }
        }
        guard result.pageCount > 0 else { throw ConvError(tr("Nothing to combine")) }
        try save(result, to: out)
        return result.pageCount
    }

    /// One PDF page showing the image, fitted and centred
    static func imagePage(_ url: URL, pageSize: PageSize, margin: Bool) throws -> PDFPage {
        let s = try ImageOps.source(url)
        let (w, h) = ImageOps.displaySize(s)
        guard w > 0, h > 0 else { throw ConvError(tr("%@ can't be read", url.lastPathComponent)) }
        let landscape = w > h
        let inset: CGFloat = margin ? 28 : 0   // about 1 cm
        var page: CGSize
        switch pageSize {
        case .a4: page = landscape ? CGSize(width: 842, height: 595) : CGSize(width: 595, height: 842)
        case .letter: page = landscape ? CGSize(width: 792, height: 612) : CGSize(width: 612, height: 792)
        case .fit:
            let long: CGFloat = 842
            page = landscape ? CGSize(width: long, height: (long * CGFloat(h) / CGFloat(w)).rounded())
                             : CGSize(width: (long * CGFloat(w) / CGFloat(h)).rounded(), height: long)
            page.width += 2 * inset
            page.height += 2 * inset
        }
        let area = CGRect(origin: .zero, size: page).insetBy(dx: inset, dy: inset)
        let scale = min(area.width / CGFloat(w), area.height / CGFloat(h))
        let size = CGSize(width: CGFloat(w) * scale, height: CGFloat(h) * scale)
        let rect = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        // 300 dpi at the printed size is plenty
        let img = try ImageOps.imageForPDF(s, maxEdge: Int((max(size.width, size.height) * 300 / 72).rounded()))

        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: page)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw ConvError(tr("PDF can't be created")) }
        ctx.beginPDFPage(nil)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: rect)
        ctx.endPDFPage()
        ctx.closePDF()
        guard let tmp = PDFDocument(data: data as Data), let p = tmp.page(at: 0)?.copy() as? PDFPage else {
            throw ConvError(tr("PDF can't be created"))
        }
        return p
    }
}
