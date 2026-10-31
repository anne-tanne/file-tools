import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import Vision

enum ScanColor: String, CaseIterable, Identifiable, Codable, Sendable, Titled {
    case color = "Colour", gray = "Greyscale", bw = "Black & White"
    var id: String { rawValue }
}

enum ScanOutput: String, CaseIterable, Identifiable, Codable, Sendable, Titled {
    case jpg = "JPG", pdf = "PDF", searchable = "Searchable PDF"
    var id: String { rawValue }
}

enum DocScan {
    private static let ciContext = CIContext()
    private static let maxEdge: CGFloat = 4000

    /// Corners of the page in pixels (origin lower left, like CIImage)
    private struct Quad { var tl, tr, br, bl: CGPoint }

    /// Finds the page: document segmentation first, then rectangle detection
    private static func findPage(_ img: CGImage) -> Quad? {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        func quad(_ o: VNRectangleObservation) -> Quad {
            func p(_ n: CGPoint) -> CGPoint { CGPoint(x: n.x * w, y: n.y * h) }
            // Pulled in 1 % towards the centre so a dark page edge doesn't end up in the result
            let q = [p(o.topLeft), p(o.topRight), p(o.bottomRight), p(o.bottomLeft)]
            let c = CGPoint(x: q.map(\.x).reduce(0, +) / 4, y: q.map(\.y).reduce(0, +) / 4)
            let i = q.map { CGPoint(x: $0.x + (c.x - $0.x) * 0.01, y: $0.y + (c.y - $0.y) * 0.01) }
            return Quad(tl: i[0], tr: i[1], br: i[2], bl: i[3])
        }
        let handler = VNImageRequestHandler(cgImage: img)
        let seg = VNDetectDocumentSegmentationRequest()
        if (try? handler.perform([seg])) != nil, let o = seg.results?.first, o.confidence >= 0.5 { return quad(o) }
        let rect = VNDetectRectanglesRequest()
        rect.minimumConfidence = 0.5
        rect.minimumAspectRatio = 0.3
        rect.minimumSize = 0.2
        rect.maximumObservations = 1
        rect.quadratureTolerance = 30
        if (try? handler.perform([rect])) != nil, let o = rect.results?.first, o.confidence >= 0.5 { return quad(o) }
        return nil
    }

    /// Straightens the page (when found) and cleans up the colours
    private static func process(_ img: CGImage, color: ScanColor) throws -> (CGImage, found: Bool) {
        var ci = CIImage(cgImage: img)
        let page = findPage(img)
        if let q = page {
            let f = CIFilter.perspectiveCorrection()
            f.inputImage = ci
            f.topLeft = q.tl; f.topRight = q.tr; f.bottomRight = q.br; f.bottomLeft = q.bl
            if let out = f.outputImage, out.extent.width >= 1, out.extent.height >= 1 { ci = out }
        }
        // Long edge at most 4000 px
        let k = maxEdge / max(ci.extent.width, ci.extent.height)
        if k < 1 {
            ci = ci.transformed(by: CGAffineTransform(scaleX: k, y: k))
        }
        let enhancer = CIFilter.documentEnhancer()
        enhancer.inputImage = ci
        enhancer.amount = 10
        ci = enhancer.outputImage ?? ci
        if color != .color {
            let g = CIFilter.colorControls()
            g.inputImage = ci
            g.saturation = 0
            ci = g.outputImage ?? ci
        }
        if color == .bw {
            let t = CIFilter.colorThresholdOtsu()
            t.inputImage = ci
            ci = t.outputImage ?? ci
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let rect = ci.extent.integral
        guard let out = ciContext.createCGImage(ci, from: rect, format: .RGBA8, colorSpace: space) else {
            throw ConvError(tr("Writing failed"))
        }
        return (out, page != nil)
    }

    /// JPEG-encoded and decoded again, so a PDF stores it as JPEG data
    private static func jpegBacked(_ file: URL) throws -> CGImage {
        guard let s = CGImageSourceCreateWithURL(file as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(s, 0, nil) else {
            throw ConvError(tr("File can't be read"))
        }
        return img
    }

    private static func writePDF(jpeg: URL, to out: URL) throws {
        let img = try jpegBacked(jpeg)
        let w = 595.0, h = (w * Double(img.height) / Double(img.width)).rounded()
        var box = CGRect(x: 0, y: 0, width: w, height: h)
        guard let c = CGContext(out as CFURL, mediaBox: &box, nil) else { throw ConvError(tr("Can't write to destination")) }
        c.beginPDFPage(nil)
        c.draw(img, in: box)
        c.endPDFPage()
        c.closePDF()
    }

    /// "name (clean).jpg/.pdf"; foundPage = false when no page edges were found and only the colours were cleaned up
    static func clean(_ src: URL, color: ScanColor, output: ScanOutput, folder: URL?) throws -> (URL, foundPage: Bool) {
        let s = try ImageOps.source(src)
        let (img, found) = try process(try ImageOps.upright(s), color: color)
        var p = ImageOps.uprightMetadata(s)
        p[kCGImageDestinationLossyCompressionQuality] = 0.9
        let jpeg = UTType.jpeg.identifier as CFString
        let suffix = tr("clean")

        if output == .jpg {
            let out = outputURL(for: src, suffix: suffix, ext: "jpg", folder: folder)
            try ImageOps.write(out, type: jpeg) { CGImageDestinationAddImage($0, img, p as CFDictionary) }
            return (out, found)
        }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("FileTools-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let tmp = tmpDir.appendingPathComponent(src.deletingPathExtension().lastPathComponent + ".jpg")
        try ImageOps.write(tmp, type: jpeg) { CGImageDestinationAddImage($0, img, p as CFDictionary) }
        let out = outputURL(for: src, suffix: suffix, ext: "pdf", folder: folder)

        if output == .searchable {
            do {
                let (made, _) = try OCR.makeSearchable(tmp, kind: .image, folder: tmpDir) { _, _ in }
                try FileManager.default.moveItem(at: made, to: out)
                return (out, found)
            } catch is Skipped {
                // No text found: plain PDF below
            }
        }
        do { try writePDF(jpeg: tmp, to: out) } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        return (out, found)
    }
}
