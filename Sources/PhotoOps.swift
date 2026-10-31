import AppKit
import CoreImage
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Vision

enum PhotoOps {
    private static let ciContext = CIContext()

    private static func rgbSpace(_ img: CGImage) -> CGColorSpace {
        img.colorSpace?.model == .rgb ? img.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// Writes an edited (upright) photo with the source's metadata, in the same format when macOS can write it
    private static func writeUpright(_ img: CGImage, source s: CGImageSource, src: URL, suffix: String, folder: URL?) throws -> URL {
        let (type, ext) = ImageOps.outputType(s)
        let out = outputURL(for: src, suffix: tr(suffix), ext: ext, folder: folder)
        var p = ImageOps.uprightMetadata(s)
        p[kCGImageDestinationLossyCompressionQuality] = 0.92
        try ImageOps.write(out, type: type) { CGImageDestinationAddImage($0, img, p as CFDictionary) }
        return out
    }

    // MARK: Remove background

    static func removeBackground(_ src: URL, fill: BackgroundFill, cropToSubject: Bool, folder: URL?) throws -> URL {
        let s = try ImageOps.source(src)
        let img = try ImageOps.upright(s)
        let handler = VNImageRequestHandler(cgImage: img)
        let request = VNGenerateForegroundInstanceMaskRequest()
        do { try handler.perform([request]) } catch { throw ConvError(tr("No subject found")) }
        guard let result = request.results?.first, !result.allInstances.isEmpty else { throw ConvError(tr("No subject found")) }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: cropToSubject)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard var cut = ciContext.createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: rgbSpace(img)) else {
            throw ConvError(tr("Writing failed"))
        }
        var p = ImageOps.uprightMetadata(s)
        let type: CFString, ext: String
        if fill == .white {
            guard let c = ImageOps.context(cut.width, cut.height, like: cut) else { throw ConvError(tr("Not enough memory")) }
            let r = CGRect(x: 0, y: 0, width: cut.width, height: cut.height)
            c.setFillColor(.white)
            c.fill(r)
            c.draw(cut, in: r)
            guard let flat = c.makeImage() else { throw ConvError(tr("Writing failed")) }
            cut = flat
            (type, ext) = (UTType.jpeg.identifier as CFString, "jpg")
            p[kCGImageDestinationLossyCompressionQuality] = 0.92
        } else {
            (type, ext) = (UTType.png.identifier as CFString, "png")
        }
        let out = outputURL(for: src, suffix: tr("no background"), ext: ext, folder: folder)
        try ImageOps.write(out, type: type) { CGImageDestinationAddImage($0, cut, p as CFDictionary) }
        return out
    }

    // MARK: Crop

    static func crop(_ src: URL, aspect: CropAspect, folder: URL?) throws -> (URL, Int, Int) {
        let s = try ImageOps.source(src)
        let img = try ImageOps.upright(s)
        let w = img.width, h = img.height
        var rect = CGRect(x: 0, y: 0, width: w, height: h)
        if let r = aspect.ratio {
            // Ratio follows the photo's orientation: landscape stays wide, portrait stays tall
            let target = w >= h ? r : 1 / r
            let cur = Double(w) / Double(h)
            guard abs(cur / target - 1) >= 0.01 else { throw Skipped(tr("Already this shape")) }
            if cur > target {
                let nw = max(1, Int((Double(h) * target).rounded()))
                rect = CGRect(x: (w - nw) / 2, y: 0, width: nw, height: h)
            } else {
                let nh = max(1, Int((Double(w) / target).rounded()))
                rect = CGRect(x: 0, y: (h - nh) / 2, width: w, height: nh)
            }
        } else {
            guard let box = try borderFreeRect(img) else { throw Skipped(tr("No borders to trim")) }
            rect = box
        }
        guard let cropped = img.cropping(to: rect) else { throw ConvError(tr("Cropping failed")) }
        let out = try writeUpright(cropped, source: s, src: src, suffix: "cropped", folder: folder)
        return (out, cropped.width, cropped.height)
    }

    /// Bounding box of everything that differs from the top-left pixel by more than 24/255; nil if nothing to trim
    private static func borderFreeRect(_ img: CGImage) throws -> CGRect? {
        let w = img.width, h = img.height
        guard let c = ImageOps.context(w, h, like: img) else { throw ConvError(tr("Not enough memory")) }
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = c.data else { throw ConvError(tr("Not enough memory")) }
        let bpr = c.bytesPerRow
        let px = data.assumingMemoryBound(to: UInt8.self)
        // Row 0 of the buffer is the top of the image
        let b = (px[0], px[1], px[2], px[3])
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            let row = px + y * bpr
            for x in 0..<w {
                let q = row + x * 4
                if abs(Int(q[0]) - Int(b.0)) > 24 || abs(Int(q[1]) - Int(b.1)) > 24
                    || abs(Int(q[2]) - Int(b.2)) > 24 || abs(Int(q[3]) - Int(b.3)) > 24 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    maxY = y
                }
            }
        }
        guard maxX >= 0, !(minX == 0 && minY == 0 && maxX == w - 1 && maxY == h - 1) else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: Black & white

    static func blackAndWhite(_ src: URL, folder: URL?) throws -> URL {
        let s = try ImageOps.source(src)
        let (type, ext) = ImageOps.outputType(s)
        let orientation = ImageOps.properties(s)[kCGImagePropertyOrientation] as? Int ?? 1
        // AVIF doesn't keep the orientation tag, so bake it into the pixels there
        let bake = (type as String) == "public.avif" && orientation != 1
        let stored: CGImage
        if bake { stored = try ImageOps.upright(s) }
        else {
            guard let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { throw ConvError(tr("File can't be read")) }
            stored = i
        }
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else { throw ConvError(tr("Writing failed")) }
        filter.setValue(CIImage(cgImage: stored), forKey: kCIInputImageKey)
        guard let result = filter.outputImage,
              let gray = ciContext.createCGImage(result, from: CGRect(x: 0, y: 0, width: stored.width, height: stored.height),
                                                 format: .RGBA8, colorSpace: rgbSpace(stored)) else {
            throw ConvError(tr("Writing failed"))
        }
        var p = bake ? ImageOps.uprightMetadata(s) : ImageOps.metadata(s)
        p[kCGImageDestinationLossyCompressionQuality] = 0.92
        let out = outputURL(for: src, suffix: tr("black & white"), ext: ext, folder: folder)
        try ImageOps.write(out, type: type) { CGImageDestinationAddImage($0, gray, p as CFDictionary) }
        return out
    }

    // MARK: Icons

    static func iconSet(_ src: URL, formats: IconFormats, folder: URL?) throws -> [URL] {
        let s = try ImageOps.source(src)
        let img = try ImageOps.upright(s)
        let side = max(img.width, img.height)
        // Pad to a transparent square, centred
        guard let sq = ImageOps.context(side, side, like: img) else { throw ConvError(tr("Not enough memory")) }
        sq.draw(img, in: CGRect(x: (side - img.width) / 2, y: (side - img.height) / 2, width: img.width, height: img.height))
        guard let square = sq.makeImage() else { throw ConvError(tr("Writing failed")) }

        func scaled(_ n: Int) -> CGImage? {
            guard let c = ImageOps.context(n, n, like: square) else { return nil }
            c.interpolationQuality = .high
            c.draw(square, in: CGRect(x: 0, y: 0, width: n, height: n))
            return c.makeImage()
        }
        func make(_ ext: String, type: UTType, sizes: [Int]) throws -> URL {
            let out = uniqueURL(folder ?? src.deletingLastPathComponent(), src.deletingPathExtension().lastPathComponent, ext)
            // ImageIO's ICO writer takes at most 6 images: if it refuses the full list, drop 24
            var images = sizes.compactMap(scaled)
            var dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, images.count, nil)
            if dest == nil, sizes.contains(24) {
                images = sizes.filter { $0 != 24 }.compactMap(scaled)
                dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, images.count, nil)
            }
            guard !images.isEmpty, let d = dest else { throw ConvError(tr("Can't write to destination")) }
            for i in images { CGImageDestinationAddImage(d, i, nil) }
            guard CGImageDestinationFinalize(d) else {
                try? FileManager.default.removeItem(at: out)
                throw ConvError(tr("Writing failed"))
            }
            return out
        }
        var urls: [URL] = []
        if formats != .ico { urls.append(try make("icns", type: .icns, sizes: [16, 32, 64, 128, 256, 512, 1024])) }
        if formats != .icns { urls.append(try make("ico", type: .ico, sizes: [16, 24, 32, 48, 64, 128, 256])) }
        return urls
    }

    // MARK: Contact sheet

    static func contactSheet(_ srcs: [URL], columns: Int, names: Bool, format: SheetFormat, to out: URL,
                             progress: (Int) -> Void) throws -> Int {
        let cols = max(1, columns)
        let pageW = 595.0, pageH = 842.0, margin = 28.0, gap = 10.0
        let cell = ((pageW - 2 * margin - gap * Double(cols - 1)) / Double(cols)).rounded(.down)
        let cellH = cell + (names ? 14 : 0)
        let rowsPerPage = max(1, Int((pageH - 2 * margin + gap) / (cellH + gap)))
        let pageSize = cols * rowsPerPage
        let count = format == .jpg ? 1 : max(1, (srcs.count + pageSize - 1) / pageSize)
        let thumbEdge = Int(cell / 72 * 300)

        /// Draws one cell: thumbnail fitted in the square, caption below. (x, y) = lower left of the cell in points.
        func drawCell(_ c: CGContext, _ url: URL, x: Double, y: Double) {
            let top = y + cellH
            if let s = try? ImageOps.source(url), let img = try? ImageOps.imageForPDF(s, maxEdge: thumbEdge) {
                let k = min(cell / Double(img.width), cell / Double(img.height))
                let tw = Double(img.width) * k, th = Double(img.height) * k
                c.draw(img, in: CGRect(x: x + (cell - tw) / 2, y: top - cell + (cell - th) / 2, width: tw, height: th))
            }
            guard names else { return }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingMiddle
            style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Helvetica", size: 7) ?? NSFont.systemFont(ofSize: 7),
                .foregroundColor: NSColor(white: 0.4, alpha: 1), .paragraphStyle: style,
            ]
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
            (url.lastPathComponent as NSString).draw(in: CGRect(x: x, y: y, width: cell, height: 10), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
        }
        func position(_ i: Int, pageH: Double) -> (Double, Double) {
            let n = i % pageSize
            return (margin + Double(n % cols) * (cell + gap), pageH - margin - Double(n / cols + 1) * cellH - Double(n / cols) * gap)
        }

        if format == .pdf {
            var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
            guard let c = CGContext(out as CFURL, mediaBox: &box, nil) else { throw ConvError(tr("Can't write to destination")) }
            for (i, url) in srcs.enumerated() {
                progress(i + 1)
                if i % pageSize == 0 { if i > 0 { c.endPDFPage() }; c.beginPDFPage(nil) }
                let (x, y) = position(i, pageH: pageH)
                drawCell(c, url, x: x, y: y)
            }
            if srcs.isEmpty { c.beginPDFPage(nil) }
            c.endPDFPage()
            c.closePDF()
            return count
        }
        // JPG: one image 3000 px wide, same layout, as tall as the rows need
        let scale = 3000 / pageW
        let rows = max(1, (srcs.count + cols - 1) / cols)
        let h = 2 * margin + Double(rows) * cellH + Double(rows - 1) * gap
        guard let c = ImageOps.context(3000, Int((h * scale).rounded(.up))) else { throw ConvError(tr("Not enough memory")) }
        c.setFillColor(.white)
        c.fill(CGRect(x: 0, y: 0, width: c.width, height: c.height))
        c.scaleBy(x: scale, y: scale)
        let hPts = Double(c.height) / scale
        for (i, url) in srcs.enumerated() {
            progress(i + 1)
            let n = i, col = n % cols, row = n / cols
            drawCell(c, url, x: margin + Double(col) * (cell + gap), y: hPts - margin - Double(row + 1) * cellH - Double(row) * gap)
        }
        guard let img = c.makeImage() else { throw ConvError(tr("Writing failed")) }
        try ImageOps.write(out, type: UTType.jpeg.identifier as CFString) {
            CGImageDestinationAddImage($0, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        }
        return 1
    }

    // MARK: Duplicates

    /// Maps each duplicate's index to the index of the file to keep (most pixels, ties → earlier in the list)
    static func findDuplicates(_ srcs: [URL], mode: DuplicateMode, progress: (Int) -> Void) throws -> [Int: Int] {
        var parent = Array(0..<srcs.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        func union(_ a: Int, _ b: Int) { let (x, y) = (find(a), find(b)); if x != y { parent[max(x, y)] = min(x, y) } }

        switch mode {
        case .exact:
            var seen: [String: Int] = [:]
            for (i, url) in srcs.enumerated() {
                progress(i + 1)
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if let j = seen[hash] { union(j, i) } else { seen[hash] = i }
            }
        case .similar:
            var prints: [(Int, VNFeaturePrintObservation)] = []
            for (i, url) in srcs.enumerated() {
                progress(i + 1)
                guard let s = try? ImageOps.source(url), let (w, h) = Optional(ImageOps.displaySize(s)),
                      let img = CGImageSourceCreateThumbnailAtIndex(s, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceThumbnailMaxPixelSize: min(1024, max(w, h)),
                          kCGImageSourceCreateThumbnailWithTransform: true,
                      ] as CFDictionary) else { continue }
                let handler = VNImageRequestHandler(cgImage: img)
                let request = VNGenerateImageFeaturePrintRequest()
                if (try? handler.perform([request])) != nil, let obs = request.results?.first { prints.append((i, obs)) }
            }
            for a in 0..<prints.count {
                for b in (a + 1)..<max(a + 1, prints.count) {
                    var d: Float = 0
                    if (try? prints[a].1.computeDistance(&d, to: prints[b].1)) != nil, d < similarThreshold { union(prints[a].0, prints[b].0) }
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for i in 0..<srcs.count { groups[find(i), default: []].append(i) }
        var result: [Int: Int] = [:]
        for members in groups.values where members.count > 1 {
            let pixels = members.map { i -> Int in
                guard let s = try? ImageOps.source(srcs[i]) else { return 0 }
                let (w, h) = ImageOps.pixelSize(s)
                return w * h
            }
            var best = 0
            for k in 1..<members.count where pixels[k] > pixels[best] { best = k }
            for m in members where m != members[best] { result[m] = members[best] }
        }
        return result
    }

    /// Feature-print distance below which two photos count as the same picture
    static let similarThreshold: Float = 0.5
}
