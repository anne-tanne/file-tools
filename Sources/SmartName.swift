import AppKit
import PDFKit
import Vision

/// Suggests a file name like "261014-SwisscomInvoice" (yyMMdd-TitleInCamelCase) from a file's content.
/// Sender and document type from the text (or scene labels for photos), date from the text or the file.
enum SmartName {
    /// File name stem without extension, e.g. "261014-SwisscomInvoice". `fallbackDate` = photo date or file creation date.
    static func suggest(_ url: URL, kind: Kind, fallbackDate: Date) throws -> String {
        var text = String(try content(url, kind: kind).prefix(1500))
        var description = ""
        if text.filter(\.isLetter).count < 20 {
            if kind == .image { description = try labels(url).joined(separator: ", ") }
            text = ""
        }
        let date = firstDate(in: text) ?? fallbackDate
        let title = heuristicTitle(text: text, description: description)
        var name = camelCase(title)
        if name.isEmpty { name = camelCase(url.deletingPathExtension().lastPathComponent) }
        if name.isEmpty { name = tr("Document") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyMMdd"
        return "\(f.string(from: date))-\(name)"
    }

    // MARK: Content

    private static func content(_ url: URL, kind: Kind) throws -> String {
        switch kind {
        case .pdf:
            let doc = try PDFOps.open(url)
            let pages = (0..<min(2, doc.pageCount)).compactMap { doc.page(at: $0) }
            if pages.contains(where: OCR.hasText) { return pages.compactMap(\.string).joined(separator: "\n") }
            guard let first = pages.first, let img = PDFOps.render(first, dpi: 200) else { return "" }
            return try ocrText(img)
        case .image:
            return try ocrText(try ImageOps.upright(try ImageOps.source(url)))
        case .video:
            return ""   // no text to read: the name comes from the date and the file name
        case .word:
            guard let a = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else {
                throw ConvError(tr("File can't be read"))
            }
            return a.string
        }
    }

    /// Recognised lines in reading order (top to bottom)
    private static func ocrText(_ img: CGImage) throws -> String {
        try OCR.recognize(img).sorted { $0.box.maxY > $1.box.maxY }.map(\.text).joined(separator: "\n")
    }

    /// Up to 3 scene labels with confidence > 0.3, as words ("outdoor_water" -> "outdoor water")
    private static func labels(_ url: URL) throws -> [String] {
        let img = try ImageOps.upright(try ImageOps.source(url))
        let req = VNClassifyImageRequest()
        do { try VNImageRequestHandler(cgImage: img, options: [:]).perform([req]) }
        catch { return [] }
        return (req.results ?? []).filter { $0.confidence > 0.3 }.prefix(3)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    // MARK: Heuristic

    private static let legalForms: Set<String> = ["ag", "gmbh", "sa", "sàrl", "sarl", "ltd", "inc", "llc", "kg"]

    /// Keyword (lowercase) -> index into `typeWords`; the earliest keyword in the text wins
    private static let typeKeywords: [String: Int] = [
        "rechnung": 0, "invoice": 0, "facture": 0,
        "quittung": 1, "beleg": 1, "receipt": 1, "quittance": 1, "reçu": 1,
        "vertrag": 2, "contract": 2, "contrat": 2,
        "offerte": 3, "angebot": 3, "offer": 3, "quote": 3, "offre": 3, "devis": 3,
        "mahnung": 4, "reminder": 4, "rappel": 4,
        "kontoauszug": 5, "statement": 5, "relevé": 5,
        "zeugnis": 6, "bestätigung": 6, "certificate": 6, "attestation": 6, "certificat": 6,
    ]
    /// Output words per type: en, de, fr
    private static let typeWords: [(en: String, de: String, fr: String)] = [
        ("Invoice", "Rechnung", "Facture"), ("Receipt", "Quittung", "Reçu"), ("Contract", "Vertrag", "Contrat"),
        ("Offer", "Offerte", "Offre"), ("Reminder", "Mahnung", "Rappel"), ("Statement", "Kontoauszug", "Relevé"),
        ("Certificate", "Bestätigung", "Attestation"),
    ]

    /// Sender (first line, without legal forms and bracketed parts, max 2 words) plus the document type
    private static func heuristicTitle(text: String, description: String) -> String {
        var title = ""
        for line in text.split(whereSeparator: \.isNewline) {
            let raw = line.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .filter { $0.filter(\.isLetter).count >= 2 }
            guard raw.count >= 2 else { continue }
            let cleaned = String(line).replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
            let words = cleaned.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .filter { $0.filter(\.isLetter).count >= 2 && !legalForms.contains($0.lowercased()) }
            title = (words.isEmpty ? raw : words).prefix(2).joined(separator: " ")
            break
        }
        if title.isEmpty { return description }
        // earliest document-type keyword (whole word, case-insensitive)
        let found = text.split(whereSeparator: { !$0.isLetter }).lazy
            .compactMap { typeKeywords[$0.lowercased()] }.first
        if let i = found {
            let t = typeWords[i]
            let word = switch L10n.lang { case .en: t.en; case .de: t.de; case .fr: t.fr }
            let lower = title.lowercased()
            let present = lower.contains(word.lowercased())
                || typeKeywords.contains { $0.value == i && lower.contains($0.key) }
            if !present { title += " " + word }
        }
        return title
    }

    private static func firstDate(in text: String) -> Date? {
        guard !text.isEmpty, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for m in det.matches(in: text, range: range) {
            if let d = m.date, inRange(d) { return d }
        }
        return nil
    }

    // MARK: Helpers

    private static func inRange(_ d: Date) -> Bool {
        let year = Calendar.current.component(.year, from: d)
        return year >= 1990 && year <= Calendar.current.component(.year, from: Date()) + 1
    }

    /// Words joined with a capital first letter each (rest kept), letters and digits only, at most 40 characters
    static func camelCase(_ s: String) -> String {
        let words = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let joined = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return String(joined.prefix(40))
    }
}
