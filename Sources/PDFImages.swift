import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Pulls the pictures embedded in a PDF out as image files, at their original resolution.
/// JPEG and JPEG 2000 images are copied byte for byte; everything else is decoded and saved as PNG.
enum PDFImages {
    /// Images smaller than this on either side (icons, lines, bullets) are left out when `skipSmall` is on
    static let minSide = 50

    /// Writes into a new folder "name (images)"; returns the folder and how many images were saved
    static func extract(_ src: URL, pages: [Int], skipSmall: Bool, folder: URL?,
                        progress: (Int) -> Void) throws -> (folder: URL, count: Int) {
        let pdf = try PDFOps.open(src)
        guard let doc = pdf.documentRef else { throw ConvError("PDF can't be read") }
        let base = src.deletingPathExtension().lastPathComponent
        let digits = String(doc.numberOfPages).count
        var seen = Set<Int>()   // the same picture is often used on many pages
        var found: [(page: Int, stream: CGPDFStreamRef)] = []
        for (n, i) in pages.enumerated() {
            progress(n + 1)
            guard let page = doc.page(at: i + 1), let res = dict(page.dictionary, "Resources") else { continue }
            for s in images(in: res, seen: &seen) {
                if skipSmall, let d = CGPDFStreamGetDictionary(s),
                   min(int(d, "Width") ?? 0, int(d, "Height") ?? 0) < minSide { continue }
                found.append((i, s))
            }
        }
        guard !found.isEmpty else {
            throw Skipped(skipSmall ? "No pictures found (small ones skipped)" : "No pictures found")
        }

        let dir = uniqueURL(folder ?? src.deletingLastPathComponent(), "\(base) (images)", "")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var count = 0, perPage: [Int: Int] = [:]
        for f in found {
            perPage[f.page, default: 0] += 1
            let name = "page \(String(format: "%0\(digits)d", f.page + 1)) - \(perPage[f.page]!)"
            if (try? save(f.stream, dir: dir, name: name)) != nil { count += 1 }
        }
        guard count > 0 else {
            try? FileManager.default.removeItem(at: dir)
            throw ConvError("The pictures in this PDF can't be read")
        }
        return (dir, count)
    }

    // MARK: Finding images

    /// Image streams in a resource dictionary, including those inside form XObjects
    static func images(in resources: CGPDFDictionaryRef, seen: inout Set<Int>) -> [CGPDFStreamRef] {
        guard let xobjects = dict(resources, "XObject") else { return [] }
        var streams: [CGPDFStreamRef] = []
        CGPDFDictionaryApplyBlock(xobjects, { _, obj, _ in
            var s: CGPDFStreamRef?
            if CGPDFObjectGetValue(obj, .stream, &s), let s { streams.append(s) }
            return true
        }, nil)
        var result: [CGPDFStreamRef] = []
        for s in streams where seen.insert(unsafeBitCast(s, to: Int.self)).inserted {
            guard let d = CGPDFStreamGetDictionary(s) else { continue }
            switch name(d, "Subtype") {
            case "Image": result.append(s)
            case "Form": if let r = dict(d, "Resources") { result += images(in: r, seen: &seen) }
            default: break
            }
        }
        return result
    }

    // MARK: Saving

    static func save(_ stream: CGPDFStreamRef, dir: URL, name: String) throws {
        guard let d = CGPDFStreamGetDictionary(stream) else { throw ConvError("Unreadable image") }
        var fmt = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &fmt) else { throw ConvError("Unreadable image") }
        var smask: CGPDFStreamRef?
        let hasAlpha = CGPDFDictionaryGetStream(d, "SMask", &smask)

        // Already a normal image file: copy it unchanged (no quality loss)
        if !hasAlpha && (fmt == .jpegEncoded || fmt == .JPEG2000) {
            try (data as Data).write(to: uniqueURL(dir, name, fmt == .jpegEncoded ? "jpg" : "jp2"))
            return
        }
        guard var img = image(d, data: data, format: fmt) else { throw ConvError("Unreadable image") }
        if hasAlpha, let smask, let md = CGPDFStreamGetDictionary(smask) {
            var mf = CGPDFDataFormat.raw
            if let mdata = CGPDFStreamCopyData(smask, &mf), let mask = image(md, data: mdata, format: mf),
               let masked = applying(mask, to: img) { img = masked }
        } else if !pngCompatible(img), let rgb = redrawn(img) {
            img = rgb
        }
        let out = uniqueURL(dir, name, "png")
        try ImageOps.write(out, type: UTType.png.identifier as CFString) { CGImageDestinationAddImage($0, img, nil) }
    }

    /// Decodes an image XObject
    static func image(_ d: CGPDFDictionaryRef, data: CFData, format: CGPDFDataFormat) -> CGImage? {
        if format != .raw {
            guard let s = CGImageSourceCreateWithData(data, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(s, 0, nil)
        }
        guard let w = int(d, "Width"), let h = int(d, "Height"), w > 0, h > 0 else { return nil }
        var isMask: DarwinBoolean = false
        _ = CGPDFDictionaryGetBoolean(d, "ImageMask", &isMask)
        let space: CGColorSpace, components: Int, bpc: Int
        if isMask.boolValue {
            // Stencil: 0 = painted (black), 1 = background (white), unless Decode says otherwise
            space = CGColorSpaceCreateDeviceGray(); components = 1; bpc = 1
        } else {
            var obj: CGPDFObjectRef?
            guard CGPDFDictionaryGetObject(d, "ColorSpace", &obj), let obj, let cs = colorSpace(obj) else { return nil }
            (space, components) = cs
            bpc = int(d, "BitsPerComponent") ?? 8
        }
        let bytesPerRow = (w * components * bpc + 7) / 8
        guard [1, 2, 4, 8, 16].contains(bpc), CFDataGetLength(data) >= bytesPerRow * h,
              let provider = CGDataProvider(data: data) else { return nil }
        let decode = numbers(d, "Decode")
        return decode.withUnsafeBufferPointer { buf in
            CGImage(width: w, height: h, bitsPerComponent: bpc, bitsPerPixel: bpc * components, bytesPerRow: bytesPerRow,
                    space: space, bitmapInfo: bpc == 16 ? .byteOrder16Big : [], provider: provider,
                    decode: decode.isEmpty ? nil : buf.baseAddress, shouldInterpolate: false, intent: .defaultIntent)
        }
    }

    /// PDF colour space (name or array) → CGColorSpace and number of components per pixel
    static func colorSpace(_ obj: CGPDFObjectRef) -> (CGColorSpace, Int)? {
        var n: UnsafePointer<CChar>?
        if CGPDFObjectGetValue(obj, .name, &n), let n { return device(String(cString: n)) }
        var arr: CGPDFArrayRef?
        guard CGPDFObjectGetValue(obj, .array, &arr), let arr, CGPDFArrayGetName(arr, 0, &n), let n else { return nil }
        switch String(cString: n) {
        case "ICCBased":
            var s: CGPDFStreamRef?
            guard CGPDFArrayGetStream(arr, 1, &s), let s, let d = CGPDFStreamGetDictionary(s) else { return nil }
            let count = int(d, "N") ?? 3
            var f = CGPDFDataFormat.raw
            if let icc = CGPDFStreamCopyData(s, &f), let cs = CGColorSpace(iccData: icc), cs.numberOfComponents == count {
                return (cs, count)
            }
            return device(count == 1 ? "DeviceGray" : count == 4 ? "DeviceCMYK" : "DeviceRGB")
        case "Indexed", "I":
            var baseObj: CGPDFObjectRef?, hival: CGPDFInteger = 0
            guard CGPDFArrayGetObject(arr, 1, &baseObj), let baseObj, let (base, count) = colorSpace(baseObj),
                  CGPDFArrayGetInteger(arr, 2, &hival), (0...255).contains(hival) else { return nil }
            var table: Data?
            var str: CGPDFStringRef?, s: CGPDFStreamRef?
            if CGPDFArrayGetString(arr, 3, &str), let str, let p = CGPDFStringGetBytePtr(str) {
                table = Data(bytes: p, count: CGPDFStringGetLength(str))
            } else if CGPDFArrayGetStream(arr, 3, &s), let s {
                var f = CGPDFDataFormat.raw
                table = CGPDFStreamCopyData(s, &f) as Data?
            }
            guard let table, table.count >= (Int(hival) + 1) * count else { return nil }
            let cs = table.withUnsafeBytes {
                CGColorSpace(indexedBaseSpace: base, last: Int(hival), colorTable: $0.bindMemory(to: UInt8.self).baseAddress!)
            }
            return cs.map { ($0, 1) }
        case "CalRGB": return device("DeviceRGB")
        case "CalGray": return device("DeviceGray")
        default: return nil   // Lab, Separation, DeviceN: rare for pictures
        }
    }

    static func device(_ name: String) -> (CGColorSpace, Int)? {
        switch name {
        case "DeviceGray", "G", "CalGray": (CGColorSpaceCreateDeviceGray(), 1)
        case "DeviceRGB", "RGB", "CalRGB": (CGColorSpace(name: CGColorSpace.sRGB)!, 3)
        case "DeviceCMYK", "CMYK": (CGColorSpaceCreateDeviceCMYK(), 4)
        default: nil
        }
    }

    /// PNG holds grey and RGB (8/16 bit) only
    static func pngCompatible(_ img: CGImage) -> Bool {
        guard let m = img.colorSpace?.model, m == .rgb || m == .monochrome else { return false }
        return img.bitsPerComponent == 8 || img.bitsPerComponent == 16
    }

    static func redrawn(_ img: CGImage) -> CGImage? {
        let gray = img.colorSpace?.model == .monochrome
            || (img.colorSpace?.model == .indexed && img.colorSpace?.baseColorSpace?.model == .monochrome)
        let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: gray ? 0 : CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage()
    }

    /// Soft mask (greyscale, white = visible) → transparent PNG
    static func applying(_ mask: CGImage, to img: CGImage) -> CGImage? {
        guard let ctx = ImageOps.context(img.width, img.height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        let gray = mask.colorSpace?.model == .monochrome && mask.bitsPerComponent == 8 ? mask : redrawn(mask)
        guard let gray else { return nil }
        ctx.clip(to: rect, mask: gray)
        ctx.draw(img, in: rect)
        return ctx.makeImage()
    }

    // MARK: Dictionary helpers

    static func dict(_ d: CGPDFDictionaryRef?, _ key: String) -> CGPDFDictionaryRef? {
        var r: CGPDFDictionaryRef?
        guard let d, CGPDFDictionaryGetDictionary(d, key, &r) else { return nil }
        return r
    }

    static func name(_ d: CGPDFDictionaryRef, _ key: String) -> String? {
        var p: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(d, key, &p), let p else { return nil }
        return String(cString: p)
    }

    static func int(_ d: CGPDFDictionaryRef, _ key: String) -> Int? {
        var v: CGPDFInteger = 0
        return CGPDFDictionaryGetInteger(d, key, &v) ? Int(v) : nil
    }

    static func numbers(_ d: CGPDFDictionaryRef, _ key: String) -> [CGFloat] {
        var a: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(d, key, &a), let a else { return [] }
        return (0..<CGPDFArrayGetCount(a)).compactMap { i in
            var v: CGPDFReal = 0
            return CGPDFArrayGetNumber(a, i, &v) ? v : nil
        }
    }
}
