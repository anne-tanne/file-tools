import AppKit
import ImageIO
import PDFKit
import Vision

/// Real redaction: matched text is painted over and removed from the file (pages with matches become a flat image
/// with a fresh invisible text layer read from the redacted image)
enum Redact {
    private static let dpi = 300

    private static let emailRE = regex(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#)
    private static let ibanRE = regex(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,3})?\b"#)
    private static let phoneREs = [
        regex(#"(?:\+|00)\d{1,3}[\s./-]?\(?\d{1,4}\)?(?:[\s./-]?\d{2,4}){2,4}"#),
        regex(#"\b0\d{2}[\s./-]?\d{3}[\s./-]?\d{2}[\s./-]?\d{2}\b"#),
    ]

    private static func regex(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }

    /// Ranges (UTF-16, merged when they overlap) of everything that should be blacked out in `text`
    private static func matches(in text: String, terms: [String], emails: Bool, ibans: Bool, phones: Bool) -> [NSRange] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var found: [NSRange] = []
        for t in terms {
            var from = 0
            while from < ns.length {
                let r = ns.range(of: t, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: from, length: ns.length - from))
                if r.location == NSNotFound || r.length == 0 { break }
                found.append(r)
                from = r.location + r.length
            }
        }
        var res: [NSRegularExpression] = []
        if emails { res.append(emailRE) }
        if ibans { res.append(ibanRE) }
        if phones { res += phoneREs }
        for re in res { found += re.matches(in: text, range: whole).map(\.range) }
        found.sort { $0.location < $1.location }
        var merged: [NSRange] = []
        for r in found {
            if let last = merged.last, r.location <= last.location + last.length {
                merged[merged.count - 1] = NSRange(location: last.location, length: max(last.length, r.location + r.length - last.location))
            } else { merged.append(r) }
        }
        return merged
    }

    // MARK: Finding boxes

    /// Text page: boxes in page space (1 pt padding) from the PDF's own text
    private static func textBoxes(_ page: PDFPage, ranges: [NSRange]) -> [CGRect] {
        var boxes: [CGRect] = []
        for r in ranges {
            for line in page.selection(for: r)?.selectionsByLine() ?? [] {
                let b = line.bounds(for: page)
                if b.width > 0, b.height > 0 { boxes.append(b.insetBy(dx: -1, dy: -1)) }
            }
        }
        return boxes
    }

    /// Scan / photo: runs OCR and returns (box count, boxes in pixel coordinates, origin bottom-left)
    private static func ocrBoxes(_ img: CGImage, terms: [String], emails: Bool, ibans: Bool, phones: Bool) throws -> (matches: Int, boxes: [CGRect]) {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        req.recognitionLanguages = ["de-DE", "en-US", "fr-FR"]
        do { try VNImageRequestHandler(cgImage: img, options: [:]).perform([req]) }
        catch { throw ConvError(tr("Text recognition failed")) }
        let w = CGFloat(img.width), h = CGFloat(img.height)
        var count = 0
        var boxes: [CGRect] = []
        for o in req.results ?? [] {
            guard let cand = o.topCandidates(1).first else { continue }
            let s = cand.string
            for r in matches(in: s, terms: terms, emails: emails, ibans: ibans, phones: phones) {
                guard let range = Range(r, in: s), let rect = try? cand.boundingBox(for: range) else { continue }
                let b = rect.boundingBox
                boxes.append(CGRect(x: b.minX * w, y: b.minY * h, width: b.width * w, height: b.height * h).insetBy(dx: -3, dy: -3))
                count += 1
            }
        }
        return (count, boxes)
    }

    // MARK: Painting

    private static func paint(_ img: CGImage, boxes: [CGRect]) throws -> CGImage {
        guard let ctx = ImageOps.context(img.width, img.height, like: img) else { throw ConvError(tr("Writing failed")) }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.setFillColor(.black)
        ctx.fill(boxes)
        guard let out = ctx.makeImage() else { throw ConvError(tr("Writing failed")) }
        return out
    }

    /// Page at 300 dpi with the boxes (page space) painted black after the page content
    private static func renderRedacted(_ page: PDFPage, number: Int, boxes: [CGRect]) throws -> CGImage {
        let box = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let scale = CGFloat(dpi) / 72
        let w = Int(((rotated ? box.height : box.width) * scale).rounded())
        let h = Int(((rotated ? box.width : box.height) * scale).rounded())
        guard w > 0, h > 0, let ctx = ImageOps.context(w, h) else { throw ConvError(tr("Page %d can't be rendered", number)) }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        ctx.concatenate(page.transform(for: .mediaBox))
        ctx.setFillColor(.black)
        ctx.fill(boxes)
        guard let img = ctx.makeImage() else { throw ConvError(tr("Page %d can't be rendered", number)) }
        return img
    }

    /// JPEG-encodes and decodes again, so the PDF context embeds the JPEG data instead of raw pixels
    private static func jpegBacked(_ img: CGImage) throws -> CGImage {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw ConvError(tr("Writing failed")) }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest),
              let s = CGImageSourceCreateWithData(data as CFData, nil),
              let out = CGImageSourceCreateImageAtIndex(s, 0, nil) else { throw ConvError(tr("Writing failed")) }
        return out
    }

    // MARK: Run

    static func run(_ src: URL, kind: Kind, terms: [String], emails: Bool, ibans: Bool, phones: Bool, folder: URL?,
                    progress: (Int, Int) -> Void) throws -> (URL, matches: Int, pages: Int) {
        let terms = terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !terms.isEmpty || emails || ibans || phones else { throw Skipped(tr("No matches found")) }
        var total = 0, changed = 0

        switch kind {
        case .pdf:
            let doc = try PDFOps.open(src)
            let result = PDFDocument()
            for i in 0..<doc.pageCount {
                progress(i + 1, doc.pageCount)
                guard let page = doc.page(at: i) else { continue }
                var redacted: CGImage?
                var n = 0
                if OCR.hasText(page) {
                    let ranges = matches(in: page.string ?? "", terms: terms, emails: emails, ibans: ibans, phones: phones)
                    let boxes = textBoxes(page, ranges: ranges)
                    if !boxes.isEmpty {
                        n = ranges.count
                        redacted = try renderRedacted(page, number: i + 1, boxes: boxes)
                    }
                } else if let img = PDFOps.render(page, dpi: dpi) {
                    let (count, boxes) = try ocrBoxes(img, terms: terms, emails: emails, ibans: ibans, phones: phones)
                    if !boxes.isEmpty {
                        n = count
                        redacted = try paint(img, boxes: boxes)
                    }
                }
                guard var flat = redacted else {
                    if let c = page.copy() as? PDFPage { result.insert(c, at: result.pageCount) }
                    continue
                }
                // Safety net: whatever the PDF's own text missed (ligatures, odd encodings) is still visible, so read the
                // flattened page again and cover anything that still matches
                let (_, missed) = try ocrBoxes(flat, terms: terms, emails: emails, ibans: ibans, phones: phones)
                if !missed.isEmpty { flat = try paint(flat, boxes: missed) }
                total += n
                changed += 1
                let b = page.bounds(for: .mediaBox)
                let size = page.rotation % 180 != 0 ? CGSize(width: b.height, height: b.width) : b.size
                let img = try jpegBacked(flat)
                let lines = (try? OCR.recognize(img)) ?? []
                result.insert(try OCR.layerPage(size: size, lines: lines) {
                    $0.interpolationQuality = .high
                    $0.draw(img, in: CGRect(origin: .zero, size: size))
                }, at: result.pageCount)
            }
            if total == 0 { throw Skipped(tr("No matches found")) }
            // Title, author, keywords etc. that contain a match are left out
            result.documentAttributes = (doc.documentAttributes ?? [:]).filter { _, value in
                guard let s = value as? String else { return true }
                return matches(in: s, terms: terms, emails: emails, ibans: ibans, phones: phones).isEmpty
            }
            let out = outputURL(for: src, suffix: tr("redacted"), ext: "pdf", folder: folder)
            try PDFOps.save(result, to: out)
            return (out, total, changed)
        default:
            progress(1, 1)
            let s = try ImageOps.source(src)
            let img = try ImageOps.upright(s)
            let (count, boxes) = try ocrBoxes(img, terms: terms, emails: emails, ibans: ibans, phones: phones)
            if boxes.isEmpty { throw Skipped(tr("No matches found")) }
            let painted = try paint(img, boxes: boxes)
            let (type, ext) = ImageOps.outputType(s)
            let out = outputURL(for: src, suffix: tr("redacted"), ext: ext, folder: folder)
            var p = ImageOps.uprightMetadata(s)
            p[kCGImageDestinationLossyCompressionQuality] = 0.92
            try ImageOps.write(out, type: type) { CGImageDestinationAddImage($0, painted, p as CFDictionary) }
            return (out, count, 1)
        }
    }
}
