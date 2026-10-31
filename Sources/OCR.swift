import AppKit
import CoreText
import PDFKit
import Vision

enum OCR {
    typealias Line = (text: String, box: CGRect)

    /// Text lines with normalized boxes (origin bottom-left)
    static func recognize(_ img: CGImage) throws -> [Line] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        req.recognitionLanguages = ["de-DE", "en-US", "fr-FR"]
        do { try VNImageRequestHandler(cgImage: img, options: [:]).perform([req]) }
        catch { throw ConvError(tr("Text recognition failed")) }
        return (req.results ?? []).compactMap { o in
            guard let t = o.topCandidates(1).first, !t.string.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (t.string, o.boundingBox)
        }
    }

    static func hasText(_ page: PDFPage) -> Bool {
        (page.string ?? "").filter { !$0.isWhitespace }.count > 20
    }

    private static func wordCount(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

    // MARK: Text file

    static func text(_ src: URL, kind: Kind, folder: URL?, progress: (Int, Int) -> Void) throws -> (URL, words: Int) {
        var pages: [String] = []
        switch kind {
        case .pdf:
            let doc = try PDFOps.open(src)
            for i in 0..<doc.pageCount {
                progress(i + 1, doc.pageCount)
                guard let page = doc.page(at: i) else { continue }
                if hasText(page) { pages.append(page.string ?? ""); continue }
                guard let img = PDFOps.render(page, dpi: 300) else { throw ConvError(tr("Page %d can't be rendered", i + 1)) }
                pages.append(try recognize(img).map(\.text).joined(separator: "\n"))
            }
        default:
            progress(1, 1)
            pages = [try recognize(try ImageOps.upright(try ImageOps.source(src))).map(\.text).joined(separator: "\n")]
        }
        let text = pages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty else { throw Skipped(tr("No text found")) }
        let out = outputURL(for: src, suffix: nil, ext: "txt", folder: folder)
        do { try text.write(to: out, atomically: true, encoding: .utf8) } catch { throw ConvError(tr("Writing failed")) }
        return (out, wordCount(text))
    }

    // MARK: Searchable PDF

    /// Draws invisible text over each recognized line, stretched to the line's box
    private static func drawText(_ lines: [Line], in ctx: CGContext, size: CGSize) {
        ctx.saveGState()
        ctx.setTextDrawingMode(.invisible)
        for l in lines {
            let b = l.box, h = b.height * size.height, w = b.width * size.width
            guard h > 0, w > 0 else { continue }
            let font = CTFontCreateWithName("Helvetica" as CFString, h, nil)
            let attr = NSAttributedString(string: l.text, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(attr)
            let tw = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            guard tw > 0 else { continue }
            ctx.saveGState()
            ctx.translateBy(x: b.minX * size.width, y: b.minY * size.height + h * 0.2)
            ctx.scaleBy(x: w / tw, y: 1)
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    /// One-page PDF made by `content` (draws the visible part) plus the text layer
    static func layerPage(size: CGSize, lines: [Line], content: (CGContext) -> Void) throws -> PDFPage {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw ConvError(tr("PDF can't be created")) }
        ctx.beginPDFPage(nil)
        content(ctx)
        drawText(lines, in: ctx, size: size)
        ctx.endPDFPage()
        ctx.closePDF()
        guard let tmp = PDFDocument(data: data as Data), let p = tmp.page(at: 0) else { throw ConvError(tr("PDF can't be created")) }
        return p
    }

    static func makeSearchable(_ src: URL, kind: Kind, folder: URL?, progress: (Int, Int) -> Void) throws -> (URL, pages: Int) {
        let result = PDFDocument()
        var recognized = 0, found = 0
        switch kind {
        case .pdf:
            let doc = try PDFOps.open(src)
            for i in 0..<doc.pageCount {
                progress(i + 1, doc.pageCount)
                guard let page = doc.page(at: i) else { continue }
                if hasText(page) {
                    if let c = page.copy() as? PDFPage { result.insert(c, at: result.pageCount) }
                    continue
                }
                guard let img = PDFOps.render(page, dpi: 300) else { throw ConvError(tr("Page %d can't be rendered", i + 1)) }
                let lines = try recognize(img)
                recognized += 1
                found += lines.count
                if lines.isEmpty {
                    if let c = page.copy() as? PDFPage { result.insert(c, at: result.pageCount) }
                    continue
                }
                let b = page.bounds(for: .mediaBox)
                let size = page.rotation % 180 != 0 ? CGSize(width: b.height, height: b.width) : b.size
                result.insert(try layerPage(size: size, lines: lines) { page.draw(with: .mediaBox, to: $0) }, at: result.pageCount)
            }
            result.documentAttributes = doc.documentAttributes
        default:
            progress(1, 1)
            let s = try ImageOps.source(src)
            let (w, h) = ImageOps.displaySize(s)
            guard w > 0, h > 0 else { throw ConvError(tr("%@ can't be read", src.lastPathComponent)) }
            let long: CGFloat = 842
            let size = w > h ? CGSize(width: long, height: (long * CGFloat(h) / CGFloat(w)).rounded())
                             : CGSize(width: (long * CGFloat(w) / CGFloat(h)).rounded(), height: long)
            let lines = try recognize(try ImageOps.upright(s))
            recognized = 1
            found = lines.count
            if found > 0 {
                let img = try ImageOps.imageForPDF(s, maxEdge: Int((long * 300 / 72).rounded()))
                result.insert(try layerPage(size: size, lines: lines) {
                    $0.interpolationQuality = .high
                    $0.draw(img, in: CGRect(origin: .zero, size: size))
                }, at: 0)
            }
        }
        if recognized == 0 { throw Skipped(tr("Already searchable")) }
        if found == 0 { throw Skipped(tr("No text found")) }
        let out = outputURL(for: src, suffix: tr("searchable"), ext: "pdf", folder: folder)
        try PDFOps.save(result, to: out)
        return (out, recognized)
    }
}
