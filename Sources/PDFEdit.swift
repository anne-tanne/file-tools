import AppKit
import ImageIO
import PDFKit
import Quartz

/// Stamping and page-level PDF tools (page numbers, watermark, password, flatten, grayscale)
enum PDFEdit {
    // MARK: Helpers

    /// Redraws every page into a new PDF (rotation baked in, vectors and text stay vectors) and calls
    /// `stamp(context, page rect, page index)` to draw on top.
    private static func redraw(_ doc: PDFDocument, stamp: (CGContext, CGRect, Int) -> Void) throws -> PDFDocument {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ConvError(tr("PDF can't be created")) }
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let swap = page.rotation % 180 != 0
            let rect = CGRect(x: 0, y: 0, width: swap ? box.height : box.width, height: swap ? box.width : box.height)
            var r = rect
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: Data(bytes: &r, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            page.draw(with: .mediaBox, to: ctx)
            ctx.saveGState()
            stamp(ctx, rect, i)
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        guard let result = PDFDocument(data: data as Data), result.pageCount > 0 else { throw ConvError(tr("PDF can't be created")) }
        if let attrs = doc.documentAttributes { result.documentAttributes = attrs }
        return result
    }

    private static func line(_ text: String, font: String, size: CGFloat, color: CGColor) -> (line: CTLine, width: CGFloat, ascent: CGFloat, descent: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let l = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var a: CGFloat = 0, d: CGFloat = 0
        let w = CTLineGetTypographicBounds(l, &a, &d, nil)
        return (l, CGFloat(w), a, d)
    }

    /// Draws the mark (text or logo) at the given position inside `rect`
    private static func drawMark(_ ctx: CGContext, _ rect: CGRect, mark: Watermark, logo: CGImage?, color: CGColor, shadow: Bool) {
        let W = rect.width, H = rect.height
        let target = CGFloat(mark.size) * W
        // Mark drawn centred on the origin, `mw` × `mh` points
        var mw = target, mh = target
        var drawOne: () -> Void = {}
        if let logo {
            mh = target * CGFloat(logo.height) / CGFloat(logo.width)
            drawOne = { ctx.draw(logo, in: CGRect(x: -mw / 2, y: -mh / 2, width: mw, height: mh)) }
        } else {
            let probe = line(mark.text, font: "Helvetica-Bold", size: 100, color: color)
            guard probe.width > 0 else { return }
            let k = target / probe.width
            mh = (probe.ascent + probe.descent) * k
            drawOne = {
                ctx.saveGState()
                ctx.scaleBy(x: k, y: k)
                ctx.textPosition = CGPoint(x: -probe.width / 2, y: -(probe.ascent + probe.descent) / 2 + probe.descent)
                CTLineDraw(probe.line, ctx)
                ctx.restoreGState()
            }
        }
        ctx.setAlpha(CGFloat(mark.opacity))
        if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -max(1, W * 0.002)), blur: max(2, W * 0.006), color: CGColor(gray: 0, alpha: 0.6)) }
        switch mark.position {
        case .bottomRight:
            let m = 0.03 * W
            ctx.translateBy(x: rect.maxX - m - mw / 2, y: rect.minY + m + mh / 2)
            drawOne()
        case .center:
            ctx.translateBy(x: rect.midX, y: rect.midY)
            drawOne()
        case .diagonal:
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: atan(H / W))
            drawOne()
        case .tiled:
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: -.pi / 6)
            let stepX = mw + target * 0.5, stepY = mh + target * 0.5
            let reach = hypot(W, H) / 2 + mw
            var row = 0
            var y = -reach
            while y <= reach {
                var x = -reach + (row % 2 == 0 ? 0 : stepX / 2)
                while x <= reach {
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: y)
                    drawOne()
                    ctx.restoreGState()
                    x += stepX
                }
                y += stepY
                row += 1
            }
        }
    }

    // MARK: Page numbers

    static func pageNumbers(_ src: URL, style: NumberStyle, position: NumberPosition, start: Int, skipFirst: Bool, folder: URL?) throws -> URL {
        let doc = try PDFOps.open(src)
        let total = doc.pageCount + start - 1
        let grey = CGColor(gray: 0.3, alpha: 1)
        let result = try redraw(doc) { ctx, rect, i in
            if skipFirst && i == 0 { return }
            let n = start + i
            let text: String = switch style {
            case .plain: "\(n)"
            case .ofTotal: tr("%d of %d", n, total)
            case .slash: "\(n) / \(total)"
            }
            let l = line(text, font: "Helvetica", size: 10, color: grey)
            let x: CGFloat, y: CGFloat
            switch position {
            case .bottomCenter: x = rect.midX - l.width / 2; y = 24
            case .bottomRight: x = rect.maxX - 24 - l.width; y = 24
            case .topRight: x = rect.maxX - 24 - l.width; y = rect.maxY - 24 - l.ascent
            }
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(l.line, ctx)
        }
        let out = outputURL(for: src, suffix: tr("numbered"), ext: "pdf", folder: folder)
        try PDFOps.save(result, to: out)
        return out
    }

    // MARK: Watermark

    static func watermark(_ src: URL, kind: Kind, mark: Watermark, folder: URL?) throws -> URL {
        var logo: CGImage?
        if let u = mark.logo { logo = try ImageOps.upright(ImageOps.source(u)) }
        else if mark.text.trimmingCharacters(in: .whitespaces).isEmpty { throw ConvError(tr("Enter a text or choose a logo first")) }
        if kind == .pdf {
            let doc = try PDFOps.open(src)
            let result = try redraw(doc) { ctx, rect, _ in
                drawMark(ctx, rect, mark: mark, logo: logo, color: CGColor(gray: 0.5, alpha: 1), shadow: false)
            }
            let out = outputURL(for: src, suffix: tr("watermarked"), ext: "pdf", folder: folder)
            try PDFOps.save(result, to: out)
            return out
        }
        let s = try ImageOps.source(src)
        let img = try ImageOps.upright(s)
        let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        guard let ctx = ImageOps.context(img.width, img.height, like: img) else { throw ConvError(tr("Not enough memory")) }
        ctx.draw(img, in: rect)
        drawMark(ctx, rect, mark: mark, logo: logo, color: .white, shadow: logo == nil)
        guard let marked = ctx.makeImage() else { throw ConvError(tr("Writing failed")) }
        var p = ImageOps.uprightMetadata(s)
        p[kCGImageDestinationLossyCompressionQuality] = 0.92
        let (type, ext) = ImageOps.outputType(s)
        let out = outputURL(for: src, suffix: tr("watermarked"), ext: ext, folder: folder)
        try ImageOps.write(out, type: type) { CGImageDestinationAddImage($0, marked, p as CFDictionary) }
        return out
    }

    // MARK: Password

    static func password(_ src: URL, mode: PasswordMode, password: String, folder: URL?) throws -> URL {
        guard !password.isEmpty else { throw ConvError(tr("Enter a password first")) }
        guard let doc = PDFDocument(url: src) else { throw ConvError(tr("PDF can't be read")) }
        switch mode {
        case .add:
            if doc.isEncrypted { throw ConvError(tr("Already password protected")) }
            let out = outputURL(for: src, suffix: tr("protected"), ext: "pdf", folder: folder)
            try PDFOps.save(doc, to: out, options: [.userPasswordOption: password, .ownerPasswordOption: password])
            return out
        case .remove:
            if !doc.isEncrypted { throw Skipped(tr("Has no password")) }
            if doc.isLocked, !doc.unlock(withPassword: password) { throw ConvError(tr("Wrong password")) }
            let plain = PDFDocument()
            for i in 0..<doc.pageCount {
                if let p = doc.page(at: i)?.copy() as? PDFPage { plain.insert(p, at: plain.pageCount) }
            }
            if let attrs = doc.documentAttributes { plain.documentAttributes = attrs }
            let out = outputURL(for: src, suffix: tr("unlocked"), ext: "pdf", folder: folder)
            try PDFOps.save(plain, to: out)
            return out
        }
    }

    // MARK: Flatten

    static func flatten(_ src: URL, folder: URL?) throws -> URL {
        let doc = try PDFOps.open(src)
        guard (0..<doc.pageCount).contains(where: { !(doc.page(at: $0)?.annotations.isEmpty ?? true) }) else {
            throw Skipped(tr("Nothing to flatten"))
        }
        let out = outputURL(for: src, suffix: tr("flattened"), ext: "pdf", folder: folder)
        try PDFOps.save(doc, to: out, options: [.burnInAnnotationsOption: true])
        return out
    }

    // MARK: Black & white

    static func grayscale(_ src: URL, folder: URL?) throws -> URL {
        let doc = try PDFOps.open(src)
        var filter = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Gray Tone.qfilter"))
        if filter == nil {
            let data: [String: Any] = [
                "Domains": ["Applications": true, "Printing": true],
                "FilterType": 1,
                "Name": "File Tools Gray",
                "FilterData": ["ColorSettings": ["ColorConversion": "Convert", "DeviceGray": true]],
            ]
            let qf = FileManager.default.temporaryDirectory.appendingPathComponent("filetools-gray.qfilter")
            if (data as NSDictionary).write(to: qf, atomically: true) { filter = QuartzFilter(url: qf) }
        }
        guard let filter else { throw ConvError(tr("Compression filter unavailable")) }
        let out = outputURL(for: src, suffix: tr("black & white"), ext: "pdf", folder: folder)
        try PDFOps.save(doc, to: out, options: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter])
        return out
    }
}
