import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageOps {
    static let writableTypes = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    static func source(_ url: URL) throws -> CGImageSource {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(s) > 0 else {
            throw ConvError(tr("File can't be read"))
        }
        return s
    }

    static func properties(_ s: CGImageSource) -> [CFString: Any] {
        CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] ?? [:]
    }

    /// Pixel size as stored in the file (before the orientation tag is applied)
    static func pixelSize(_ s: CGImageSource) -> (w: Int, h: Int) {
        let p = properties(s)
        return (p[kCGImagePropertyPixelWidth] as? Int ?? 0, p[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    /// Pixel size as the image is displayed
    static func displaySize(_ s: CGImageSource) -> (w: Int, h: Int) {
        let (w, h) = pixelSize(s)
        let o = properties(s)[kCGImagePropertyOrientation] as? Int ?? 1
        return o >= 5 ? (h, w) : (w, h)
    }

    static func hasAlpha(_ s: CGImageSource) -> Bool { properties(s)[kCGImagePropertyHasAlpha] as? Bool ?? false }

    /// Same format as the source if macOS can write it (ext nil = keep extension), otherwise JPG or PNG
    static func outputType(_ s: CGImageSource) -> (type: CFString, ext: String?) {
        if let t = CGImageSourceGetType(s), writableTypes.contains(t as String) { return (t, nil) }
        return hasAlpha(s) ? (UTType.png.identifier as CFString, "png") : (UTType.jpeg.identifier as CFString, "jpg")
    }

    /// Source metadata (EXIF, GPS, orientation…) without size info, for writing a new image
    static func metadata(_ s: CGImageSource) -> [CFString: Any] {
        var p = properties(s)
        for k in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyFileSize,
                  kCGImagePropertyHasAlpha, kCGImagePropertyDepth] { p[k] = nil }
        if var exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            p[kCGImagePropertyExifDictionary] = exif
        }
        return p
    }

    static func write(_ out: URL, type: CFString, _ add: (CGImageDestination) -> Void) throws {
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil) else {
            throw ConvError(tr("Can't write to destination"))
        }
        add(d)
        guard CGImageDestinationFinalize(d) else {
            try? FileManager.default.removeItem(at: out)
            throw ConvError(tr("Writing failed"))
        }
    }

    /// Re-encodes image 0 of the source, keeping its metadata
    static func reencode(_ s: CGImageSource, to out: URL, type: CFString, quality: Double?, maxEdge: Int? = nil) throws {
        var p: [CFString: Any] = [:]
        if let quality { p[kCGImageDestinationLossyCompressionQuality] = quality }
        guard let maxEdge else {
            try write(out, type: type) { CGImageDestinationAddImageFromSource($0, s, 0, p as CFDictionary) }
            return
        }
        // ImageIO's built-in downscaling drops location and date, so scale first and copy the metadata ourselves
        guard let img = CGImageSourceCreateThumbnailAtIndex(s, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ] as CFDictionary) else { throw ConvError(tr("File can't be read")) }
        p.merge(metadata(s)) { mine, _ in mine }
        try write(out, type: type) { CGImageDestinationAddImage($0, img, p as CFDictionary) }
    }

    /// Full-size image with the orientation tag applied to the pixels
    static func upright(_ s: CGImageSource) throws -> CGImage {
        let (w, h) = displaySize(s)
        guard let img = CGImageSourceCreateThumbnailAtIndex(s, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary) else { throw ConvError(tr("File can't be read")) }
        return img
    }

    /// Metadata for pixels that are already upright
    static func uprightMetadata(_ s: CGImageSource) -> [CFString: Any] {
        var p = metadata(s)
        p[kCGImagePropertyOrientation] = 1
        if var tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            p[kCGImagePropertyTIFFDictionary] = tiff
        }
        return p
    }

    static func context(_ w: Int, _ h: Int, like img: CGImage? = nil) -> CGContext? {
        let space = (img?.colorSpace?.model == .rgb ? img?.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    // MARK: Convert

    static func convert(_ src: URL, to fmt: OutFormat, quality: Double, folder: URL?) throws -> URL {
        let s = try source(src)
        let out = outputURL(for: src, suffix: nil, ext: fmt.ext, folder: folder)
        let type = fmt.utType.identifier as CFString
        let q = fmt.isLossy ? quality : nil
        let orientation = properties(s)[kCGImagePropertyOrientation] as? Int ?? 1
        if fmt == .avif && orientation != 1 {
            // AVIF files don't keep the rotation tag, so turn the pixels upright instead
            let img = try upright(s)
            var p = uprightMetadata(s)
            p[kCGImageDestinationLossyCompressionQuality] = quality
            try write(out, type: type) { CGImageDestinationAddImage($0, img, p as CFDictionary) }
        } else if fmt == .jpg && hasAlpha(s) {
            // JPG has no transparency: put the image on white instead of black
            guard let img = CGImageSourceCreateImageAtIndex(s, 0, nil), let c = context(img.width, img.height, like: img) else {
                throw ConvError(tr("File can't be read"))
            }
            let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
            c.setFillColor(.white)
            c.fill(r)
            c.draw(img, in: r)
            guard let flat = c.makeImage() else { throw ConvError(tr("File can't be read")) }
            var p = metadata(s)
            p[kCGImageDestinationLossyCompressionQuality] = quality
            try write(out, type: type) { CGImageDestinationAddImage($0, flat, p as CFDictionary) }
        } else {
            try reencode(s, to: out, type: type, quality: q)
        }
        return out
    }

    // MARK: Compress

    static func compress(_ src: URL, quality: Double, maxEdge: Int?, to out: URL) throws {
        let s = try source(src)
        let (w, h) = pixelSize(s)
        // Only downscale photos that are actually larger than the limit
        let edge = maxEdge.flatMap { max(w, h) > $0 ? $0 : nil }
        try reencode(s, to: out, type: outputType(s).type, quality: quality, maxEdge: edge)
    }

    // MARK: Resize

    static func resize(_ src: URL, mode: ResizeMode, value: Int, folder: URL?) throws -> (URL, Int, Int) {
        let s = try source(src)
        let (w, h) = displaySize(s)
        guard w > 0, h > 0, value > 0 else { throw ConvError(tr("Invalid size")) }
        let scale: Double = switch mode {
        case .longest: Double(value) / Double(max(w, h))
        case .width: Double(value) / Double(w)
        case .height: Double(value) / Double(h)
        case .percent: Double(value) / 100
        }
        guard scale < 1 else { throw Skipped(tr("Already %d×%d, left as is", w, h)) }
        let nw = max(1, Int((Double(w) * scale).rounded())), nh = max(1, Int((Double(h) * scale).rounded()))
        let (type, ext) = outputType(s)
        let out = outputURL(for: src, suffix: "\(nw)×\(nh)", ext: ext, folder: folder)
        try reencode(s, to: out, type: type, quality: 0.9, maxEdge: max(nw, nh))
        return (out, nw, nh)
    }

    // MARK: Rotate

    /// degrees: 90 = clockwise, 180, 270 = counter-clockwise
    static func rotate(_ src: URL, degrees: Int, folder: URL?) throws -> URL {
        let s = try source(src)
        let upright = try upright(s)
        let iw = upright.width, ih = upright.height
        let (nw, nh) = degrees == 180 ? (iw, ih) : (ih, iw)
        guard let c = context(nw, nh, like: upright) else { throw ConvError(tr("Not enough memory")) }
        switch degrees {
        case 90: c.translateBy(x: 0, y: CGFloat(nh)); c.rotate(by: -.pi / 2)
        case 180: c.translateBy(x: CGFloat(nw), y: CGFloat(nh)); c.rotate(by: .pi)
        default: c.translateBy(x: CGFloat(nw), y: 0); c.rotate(by: .pi / 2)
        }
        c.draw(upright, in: CGRect(x: 0, y: 0, width: iw, height: ih))
        guard let rotated = c.makeImage() else { throw ConvError(tr("Rotating failed")) }

        var p = uprightMetadata(s)
        p[kCGImageDestinationLossyCompressionQuality] = 0.92
        let (type, ext) = outputType(s)
        let out = outputURL(for: src, suffix: tr("rotated"), ext: ext, folder: folder)
        try write(out, type: type) { CGImageDestinationAddImage($0, rotated, p as CFDictionary) }
        return out
    }

    // MARK: Remove info

    /// Copies the image data unchanged (no quality loss) and only replaces the metadata.
    static func strip(_ src: URL, mode: StripMode, folder: URL?) throws -> URL {
        let s = try source(src)
        guard let type = CGImageSourceGetType(s), writableTypes.contains(type as String) else {
            throw ConvError(tr("macOS can't save this format, convert it first"))
        }
        let meta: CGMutableImageMetadata
        switch mode {
        case .all:
            meta = CGImageMetadataCreateMutable()
            // Keep the rotation, otherwise the photo would show sideways
            if let o = properties(s)[kCGImagePropertyOrientation] {
                CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary,
                                                             kCGImagePropertyOrientation, o as CFTypeRef)
            }
        case .location:
            guard properties(s)[kCGImagePropertyGPSDictionary] != nil else { throw Skipped(tr("No location stored")) }
            guard let existing = CGImageSourceCopyMetadataAtIndex(s, 0, nil),
                  let copy = CGImageMetadataCreateMutableCopy(existing) else { throw Skipped(tr("No location stored")) }
            var paths: [String] = []
            CGImageMetadataEnumerateTagsUsingBlock(copy, nil, nil) { path, tag in
                if let name = CGImageMetadataTagCopyName(tag) as String?, name.hasPrefix("GPS") { paths.append(path as String) }
                return true
            }
            for p in paths { CGImageMetadataRemoveTagWithPath(copy, nil, p as CFString) }
            meta = copy
        }
        let out = outputURL(for: src, suffix: tr(mode == .all ? "no info" : "no location"), folder: folder)
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil) else {
            throw ConvError(tr("Can't write to destination"))
        }
        let opts: [CFString: Any] = [
            kCGImageDestinationMetadata: meta,
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeGPS: true,
            kCGImageMetadataShouldExcludeXMP: mode == .all,
        ]
        var err: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(d, s, opts as CFDictionary, &err) else {
            try? FileManager.default.removeItem(at: out)
            throw ConvError(err?.takeRetainedValue().localizedDescription ?? tr("Writing failed"))
        }
        // HEICs written by ImageIO keep their XMP block (with the date) through the lossless copy,
        // so if anything is left, save the pixels again with only the orientation
        if mode == .all, hasPersonalInfo(out) {
            var p: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
            p[kCGImagePropertyOrientation] = properties(s)[kCGImagePropertyOrientation]
            guard let img = CGImageSourceCreateImageAtIndex(s, 0, nil) else { throw ConvError(tr("File can't be read")) }
            try write(out, type: type) { CGImageDestinationAddImage($0, img, p as CFDictionary) }
        }
        return out
    }

    /// True if the file still has metadata beyond what describes the pixels themselves
    static func hasPersonalInfo(_ url: URL) -> Bool {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let meta = CGImageSourceCopyMetadataAtIndex(s, 0, nil) else { return false }
        let harmless: Set = ["Orientation", "TileWidth", "TileLength", "ColorSpace", "PixelXDimension", "PixelYDimension",
                             "hasXMP", "ResolutionUnit", "XResolution", "YResolution"]
        var found = false
        CGImageMetadataEnumerateTagsUsingBlock(meta, nil, [kCGImageMetadataEnumerateRecursively: true] as CFDictionary) { _, tag in
            if let name = CGImageMetadataTagCopyName(tag) as String?, !harmless.contains(name) { found = true; return false }
            return true
        }
        return found
    }

    // MARK: For PDFs

    /// Image ready to be placed in a PDF: upright, at most maxEdge pixels, and JPEG-backed for
    /// photos so the PDF stores it compactly. Untouched JPEGs are passed through as they are.
    static func imageForPDF(_ s: CGImageSource, maxEdge: Int) throws -> CGImage {
        let p = properties(s)
        let orientation = p[kCGImagePropertyOrientation] as? Int ?? 1
        let (w, h) = pixelSize(s)
        let type = CGImageSourceGetType(s) as String?
        if type == UTType.jpeg.identifier, orientation == 1, max(w, h) <= maxEdge,
           let img = CGImageSourceCreateImageAtIndex(s, 0, nil) { return img }
        guard let img = CGImageSourceCreateThumbnailAtIndex(s, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxEdge, max(w, h)),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary) else { throw ConvError(tr("Image can't be read")) }
        // Graphics and screenshots stay lossless
        if hasAlpha(s) || type == UTType.png.identifier || type == UTType.tiff.identifier { return img }
        let data = NSMutableData()
        guard let d = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return img }
        CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(d), let js = CGImageSourceCreateWithData(data, nil),
              let jpeg = CGImageSourceCreateImageAtIndex(js, 0, nil) else { return img }
        return jpeg
    }
}
