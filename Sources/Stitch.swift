import AppKit
import ImageIO
import UniformTypeIdentifiers

enum StitchDirection: String, CaseIterable, Identifiable, Codable, Sendable, Titled {
    case vertical = "Top to bottom", horizontal = "Side by side"
    var id: String { rawValue }
}

enum StitchFormat: String, CaseIterable, Identifiable, Codable, Sendable, Titled {
    case png = "PNG", jpg = "JPG"
    var id: String { rawValue }
}

enum Stitch {
    private static let maxSide = 30_000.0

    /// Puts photos together in list order. Returns the pixel size.
    static func run(_ srcs: [URL], direction: StitchDirection, spacing: Int, format: StitchFormat, to out: URL,
                    progress: (Int) -> Void) throws -> (w: Int, h: Int) {
        guard srcs.count >= 2 else { throw ConvError(tr("Choose at least 2 photos")) }
        let vertical = direction == .vertical
        let gap = Double(max(0, spacing))

        // Sizes first (no pixels loaded), so the layout is known before decoding
        var sizes: [(w: Double, h: Double)] = []
        for u in srcs {
            let (w, h) = ImageOps.displaySize(try ImageOps.source(u))
            guard w > 0, h > 0 else { throw ConvError(tr("%@ can't be read", u.lastPathComponent)) }
            sizes.append((Double(w), Double(h)))
        }
        // Scale to the smallest width (vertical) or height (horizontal), never up
        let common = vertical ? sizes.map(\.w).min()! : sizes.map(\.h).min()!
        var scaled = sizes.map { vertical ? ($0.h * common / $0.w) : ($0.w * common / $0.h) }
        var total = scaled.reduce(0, +) + gap * Double(srcs.count - 1)
        var cross = common
        var shrink = 1.0
        if total > maxSide {
            shrink = maxSide / total
            total *= shrink
            cross = (cross * shrink).rounded()
            scaled = scaled.map { $0 * shrink }
        }
        let g = gap * shrink
        let W = Int((vertical ? cross : total).rounded()), H = Int((vertical ? total : cross).rounded())
        guard W > 0, H > 0, let c = ImageOps.context(W, H) else { throw ConvError(tr("Not enough memory")) }
        c.interpolationQuality = .high
        if format == .jpg {
            c.setFillColor(.white)
            c.fill(CGRect(x: 0, y: 0, width: W, height: H))
        }

        var pos = 0.0
        for (i, u) in srcs.enumerated() {
            progress(i + 1)
            let img = try ImageOps.upright(try ImageOps.source(u))
            let rect = vertical
                ? CGRect(x: 0, y: Double(H) - pos - scaled[i], width: cross, height: scaled[i])
                : CGRect(x: pos, y: 0, width: scaled[i], height: cross)
            c.draw(img, in: rect.integral)
            pos += scaled[i] + g
        }
        guard let result = c.makeImage() else { throw ConvError(tr("Writing failed")) }
        switch format {
        case .png:
            try ImageOps.write(out, type: UTType.png.identifier as CFString) { CGImageDestinationAddImage($0, result, nil) }
        case .jpg:
            try ImageOps.write(out, type: UTType.jpeg.identifier as CFString) {
                CGImageDestinationAddImage($0, result, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            }
        }
        return (W, H)
    }
}
