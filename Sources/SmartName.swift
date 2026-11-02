import AppKit
import FoundationModels
import PDFKit
import Vision

/// Suggests a file name like "261014-SwisscomInvoice" (yyMMdd-TitleInCamelCase) from a file's content.
/// Sender and document type from the text (or scene labels for photos), date from the text or the file.
enum SmartName {
    /// Apple Intelligence is on and its model is ready. Otherwise names come from the heuristic only.
    static var usesAppleIntelligence: Bool { SystemLanguageModel.default.availability == .available }

    /// File name stem without extension, e.g. "261014-SwisscomInvoice". `fallbackDate` = photo date or file creation date.
    static func suggest(_ url: URL, kind: Kind, fallbackDate: Date) throws -> String {
        var text = String(try content(url, kind: kind).prefix(1500))
        var description = ""
        if text.filter(\.isLetter).count < 20 {
            if kind == .image { description = try labels(url).joined(separator: ", ") }
            text = ""
        }
        // Apple Intelligence when on (falls back to the heuristic on any model error)
        let guess = usesAppleIntelligence && !(text.isEmpty && description.isEmpty)
            ? try? modelGuess(text: text, description: description) : nil
        let date = guess?.date ?? firstDate(in: text) ?? fallbackDate
        let title = guess?.title ?? heuristicTitle(text: text, description: description)
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

    // MARK: Apple Intelligence

    /// Answer shape for the model: {date, sender, type}. Built by hand because the @Generable macro needs Xcode.
    private static let schema: GenerationSchema? = try? GenerationSchema(root: DynamicGenerationSchema(name: "Guess", properties: [
        .init(name: "date", description: "The document's own date (invoice date, letter date, meeting date) as YYYY-MM-DD, or an empty string",
              schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "sender", description: "Who wrote or sent it (company, organisation or person), copied exactly from the file, or an empty string",
              schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "type", description: "What kind of document it is, in 1 or 2 words (invoice, receipt, minutes, letter, contract, …)",
              schema: DynamicGenerationSchema(type: String.self)),
    ]), dependencies: [])

    /// Date and title from the on-device model. The small model makes things up, so its answer only counts
    /// where the file backs it: the date must be one of the file's dates, the sender's words must be in the file.
    /// nil parts: use the heuristic for that part.
    private static func modelGuess(text: String, description: String) throws -> (date: Date?, title: String?) {
        let language = switch L10n.lang { case .en: "English"; case .de: "German (Swiss spelling, ss instead of ß)"; case .fr: "French" }
        let instructions = """
            You help name files. Read the content of one file and say when it was written, who sent it and what kind \
            of document it is. Write the kind of document in \(language). Copy names exactly as written, never translate them.
            """
        let prompt = text.isEmpty ? "A photo showing: \(description)" : "Text of the file:\n\(text)"
        guard let schema else { throw ConvError("No schema") }
        let guess = try waitFor {
            let c = try await LanguageModelSession(instructions: instructions).respond(to: prompt, schema: schema).content
            return (date: try c.value(String.self, forProperty: "date"), sender: try c.value(String.self, forProperty: "sender"),
                    type: try c.value(String.self, forProperty: "type"))
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let date = f.date(from: guess.date.trimmingCharacters(in: .whitespaces)).flatMap { d in
            allDates(in: text).contains { Calendar.current.isDate($0, inSameDayAs: d) } ? d : nil
        }
        let source = (text + " " + description).lowercased()
        let senderText = guess.sender.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        let sender = Array(words(senderText).filter { !legalForms.contains($0.lowercased()) && !honorifics.contains($0.lowercased()) }.prefix(3))
        guard !sender.isEmpty, sender.allSatisfy({ source.contains($0.lowercased()) }) else { return (date, nil) }
        var title = sender
        if let type = documentType(guess.type, source: source), !sender.contains(where: { $0.lowercased() == type.lowercased() }) {
            title.append(type)
        }
        return (date, title.joined(separator: " "))
    }

    /// The model's document type, only if the file backs it: a known type (as the interface language's word)
    /// whose keyword is in the file, or words that are themselves in the file
    private static func documentType(_ guess: String, source: String) -> String? {
        let w = words(guess).prefix(2)
        guard !w.isEmpty else { return nil }
        if let i = w.lazy.compactMap({ typeKeywords[$0.lowercased()] ?? typeAliases[$0.lowercased()] }).first {
            guard typeKeywords.contains(where: { $0.value == i && source.contains($0.key) }) else { return nil }
            return typeWord(i)
        }
        return w.allSatisfy { source.contains($0.lowercased()) } ? w.joined(separator: " ") : nil
    }

    private static let honorifics: Set<String> = ["dr", "med", "prof", "herr", "frau", "mr", "mrs", "ms", "mme", "monsieur", "madame"]

    /// Words of at least 2 letters, without numbers (dates, amounts)
    private static func words(_ s: String) -> [String] {
        s.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init).filter { $0.filter(\.isLetter).count >= 2 }
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
        "protokoll": 7, "procès-verbal": 7,
        "letter": 8, "lettre": 8,
    ]
    /// More words the model uses for a type; too common in running text to be keywords themselves
    private static let typeAliases: [String: Int] = ["minutes": 7, "brief": 8]
    /// Output words per type: en, de, fr
    private static let typeWords: [(en: String, de: String, fr: String)] = [
        ("Invoice", "Rechnung", "Facture"), ("Receipt", "Quittung", "Reçu"), ("Contract", "Vertrag", "Contrat"),
        ("Offer", "Offerte", "Offre"), ("Reminder", "Mahnung", "Rappel"), ("Statement", "Kontoauszug", "Relevé"),
        ("Certificate", "Bestätigung", "Attestation"), ("Minutes", "Protokoll", "ProcèsVerbal"), ("Letter", "Brief", "Lettre"),
    ]

    private static func typeWord(_ i: Int) -> String {
        let t = typeWords[i]
        return switch L10n.lang { case .en: t.en; case .de: t.de; case .fr: t.fr }
    }

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
            let word = typeWord(i)
            let lower = title.lowercased()
            let present = lower.contains(word.lowercased())
                || typeKeywords.contains { $0.value == i && lower.contains($0.key) }
            if !present { title += " " + word }
        }
        return title
    }

    private static func firstDate(in text: String) -> Date? { allDates(in: text).first }

    /// Dates found in the text (year 1990…next year), in text order
    private static func allDates(in text: String) -> [Date] {
        guard !text.isEmpty, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        return det.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.date).filter(inRange)
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
