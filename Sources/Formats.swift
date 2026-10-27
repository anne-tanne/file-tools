import Foundation
import UniformTypeIdentifiers

/// Shown in red next to the file
struct ConvError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Not an error: nothing needed doing (shown in grey)
struct Skipped: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Enums whose raw value is English UI text
protocol Titled: RawRepresentable<String> {}
extension Titled { var title: String { tr(rawValue) } }

enum Kind: Sendable { case image, pdf, word }

enum OutFormat: String, CaseIterable, Identifiable, Sendable {
    case jpg = "JPG", png = "PNG", heic = "HEIC", avif = "AVIF", tiff = "TIFF"
    var id: String { rawValue }
    var ext: String { rawValue.lowercased() }
    var utType: UTType {
        switch self {
        case .jpg: .jpeg
        case .png: .png
        case .heic: .heic
        case .avif: UTType("public.avif") ?? .jpeg
        case .tiff: .tiff
        }
    }
    var isLossy: Bool { self == .jpg || self == .heic || self == .avif }
    var hint: String {
        switch self {
        case .jpg: tr("Works everywhere")
        case .png: tr("Lossless, keeps transparency")
        case .heic: tr("Small files, best on Apple devices")
        case .avif: tr("Smallest files, for the web")
        case .tiff: tr("Lossless, for print and archiving")
        }
    }
}

enum Level: String, CaseIterable, Identifiable, Sendable, Titled {
    case high = "High quality", balanced = "Balanced", small = "Smallest"
    var id: String { rawValue }
    /// JPEG quality used for photos and for images inside PDFs
    var quality: Double { switch self { case .high: 0.85; case .balanced: 0.8; case .small: 0.7 } }
    /// Resolution images inside PDFs are reduced to
    var pdfDPI: Int { switch self { case .high: 300; case .balanced: 200; case .small: 150 } }
    /// Longest edge for photos in pixels (nil = keep size)
    var maxEdge: Int? { switch self { case .high: nil; case .balanced: 4000; case .small: 2500 } }
    var hint: String {
        switch self {
        case .high: tr("Barely visible difference, good for printing")
        case .balanced: tr("Looks the same on screen, much smaller")
        case .small: tr("For email and web, still sharp on screen")
        }
    }

    /// Steps tried one after another when aiming for a target size, gentlest first
    static let pdfLadder: [(dpi: Int, quality: Double)] = [
        (300, 0.85), (200, 0.8), (150, 0.75), (150, 0.6), (120, 0.6), (96, 0.5), (72, 0.45),
    ]
    static let imageLadder: [(quality: Double, edge: Int?)] = [
        (0.85, nil), (0.75, nil), (0.65, nil), (0.75, 4000), (0.65, 3200), (0.65, 2600),
        (0.6, 2000), (0.6, 1600), (0.55, 1280), (0.5, 1000), (0.5, 800),
    ]
}

enum CompressBy: String, CaseIterable, Identifiable, Titled { case level = "Quality level", target = "Target size"; var id: String { rawValue } }

enum ResizeMode: String, CaseIterable, Identifiable, Sendable, Titled {
    case longest = "Longest side", width = "Width", height = "Height", percent = "Percentage"
    var id: String { rawValue }
}

enum StripMode: String, CaseIterable, Identifiable, Sendable, Titled {
    case all = "Everything", location = "Location only"
    var id: String { rawValue }
}

enum PageSize: String, CaseIterable, Identifiable, Sendable, Titled {
    case a4 = "A4", letter = "US Letter", fit = "Same as image"
    var id: String { rawValue }
}

enum NameMode: String, CaseIterable, Identifiable, Sendable, Titled {
    case keep = "Keep name", add = "Add text", numbered = "New name + number"
    var id: String { rawValue }
}

/// How new file names are made (Rename, Word to PDF); works on the name without extension
struct NameRule: Sendable {
    var mode: NameMode
    var before = "", after = ""          // Add text
    var pattern: String                  // New name + number: "Photo ###"
    var start = 1

    /// New name for the file at `index` (0-based, list order) of `count` files
    func apply(_ stem: String, index: Int, count: Int) -> String {
        let name: String
        switch mode {
        case .keep: name = stem
        case .add: name = before + stem + after
        case .numbered:
            let p = pattern.trimmingCharacters(in: .whitespaces)
            name = p.isEmpty ? stem : Self.numbered(p, number: start + index, last: start + count - 1)
        }
        let clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? stem : clean
    }

    /// "Photo ###" + 7 → "Photo 007"; without # the number is appended
    static func numbered(_ pattern: String, number: Int, last: Int) -> String {
        if let r = pattern.range(of: "#+", options: .regularExpression) {
            let width = pattern.distance(from: r.lowerBound, to: r.upperBound)
            return pattern.replacingCharacters(in: r, with: String(format: "%0\(width)d", number))
        }
        return pattern + " " + String(format: "%0\(max(2, String(last).count))d", number)
    }
}

enum SplitMode: String, CaseIterable, Identifiable, Sendable, Titled {
    case extract = "Selected pages", each = "Each page separately", chunks = "Every few pages"
    var id: String { rawValue }
}

// MARK: - Files

func uniqueURL(_ dir: URL, _ base: String, _ ext: String) -> URL {
    let base = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    func make(_ name: String) -> URL {
        ext.isEmpty ? dir.appendingPathComponent(name) : dir.appendingPathComponent(name).appendingPathExtension(ext)
    }
    var out = make(base)
    var n = 1
    while FileManager.default.fileExists(atPath: out.path) {
        out = make("\(base) (\(n))")
        n += 1
    }
    return out
}

/// "photo.jpg" + "rotated" → "photo (rotated).jpg", never overwriting anything
func outputURL(for src: URL, suffix: String?, ext: String? = nil, folder: URL?) -> URL {
    let base = src.deletingPathExtension().lastPathComponent + (suffix.map { " (\($0))" } ?? "")
    return uniqueURL(folder ?? src.deletingLastPathComponent(), base, ext ?? src.pathExtension)
}

/// Makes Finder show the extension (Word can save its PDFs with "Hide extension" set)
func showExtension(_ u: URL) {
    var u = u
    var values = URLResourceValues()
    values.hasHiddenExtension = false
    try? u.setResourceValues(values)
}

func fileSize(_ u: URL) -> Int64 {
    ((try? FileManager.default.attributesOfItem(atPath: u.path)[.size]) as? NSNumber)?.int64Value ?? 0
}

func fmtSize(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

// MARK: - Page ranges

/// Parses "1-3, 5, 8-" into 0-based page indexes.
func parseRanges(_ s: String, pageCount: Int) -> Set<Int>? {
    var result = Set<Int>()
    for part in s.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
        let ends = part.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if ends.count == 1, let n = Int(ends[0]), (1...pageCount).contains(n) {
            result.insert(n - 1)
        } else if ends.count == 2 {
            let a = ends[0].isEmpty ? 1 : Int(ends[0]), b = ends[1].isEmpty ? pageCount : Int(ends[1])
            guard let a, let b, a >= 1, b <= pageCount, a <= b else { return nil }
            result.formUnion((a - 1)...(b - 1))
        } else { return nil }
    }
    return result
}

func rangeString(_ pages: Set<Int>) -> String {
    var parts: [String] = []
    var sorted = pages.sorted()[...]
    while let start = sorted.first {
        var end = start
        sorted = sorted.dropFirst()
        while sorted.first == end + 1 { end += 1; sorted = sorted.dropFirst() }
        parts.append(start == end ? "\(start + 1)" : "\(start + 1)-\(end + 1)")
    }
    return parts.joined(separator: ", ")
}
