import Foundation

/// Address lists for Serienbriefe, read by File Tools itself and handed to Word as a table in a Word document.
/// Word opens Excel lists only after asking twice (its Excel converter, then the sheet) and CSV lists only after
/// asking for the text encoding, every time; a table in a Word document it opens without asking.
enum MergeList {
    /// Header row first, then one row per letter; empty rows are left out
    static func read(_ url: URL, sheet: String?) throws -> [[String]] {
        var rows: [[String]]
        switch url.pathExtension.lowercased() {
        case "xlsx", "xlsm": rows = try readXLSX(url, sheet: sheet)
        case "csv", "txt": rows = try readCSV(url)
        default: throw ConvError(tr("File Tools can read address lists in Excel (.xlsx) or CSV. Save “%@” in one of these formats and connect it to the letter again.", url.lastPathComponent))
        }
        rows = rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }.filter { $0.contains { !$0.isEmpty } }
        guard var header = rows.first else { return [] }
        let width = rows.map(\.count).max() ?? 0
        rows = rows.map { $0 + Array(repeating: "", count: width - $0.count) }
        // Word needs a name for every column, each one different
        header = header + Array(repeating: "", count: width - header.count)
        var seen: Set<String> = []
        for i in header.indices {
            var name = header[i].isEmpty ? "Field\(i + 1)" : header[i]
            var n = 2
            while !seen.insert(name.lowercased()).inserted { name = "\(header[i])\(n)"; n += 1 }
            header[i] = name
        }
        rows[0] = header
        return rows
    }

    /// The rows as a table in a minimal Word document at `out`
    static func writeTable(_ rows: [[String]], to out: URL) throws {
        let fm = FileManager.default
        let dir = out.deletingLastPathComponent().appendingPathComponent("list-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        func cell(_ s: String) -> String {
            let runs = s.components(separatedBy: .newlines).map { "<w:t xml:space=\"preserve\">\(xmlEscape($0))</w:t>" }
            return "<w:tc><w:p><w:r>" + runs.joined(separator: "<w:br/>") + "</w:r></w:p></w:tc>"
        }
        let table = rows.map { "<w:tr>" + $0.map(cell).joined() + "</w:tr>" }.joined()
        let files = [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
            """,
            "word/document.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:tbl>\(table)</w:tbl><w:p/></w:body></w:document>
            """,
        ]
        for (path, text) in files {
            let u = dir.appendingPathComponent(path)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        guard Zip.run("/usr/bin/zip", ["-q", "-X", "-r", out.path] + files.keys.sorted(), in: dir).status == 0 else {
            throw ConvError(tr("File can't be read"))
        }
    }

    // MARK: Excel

    /// The sheet the letter names (Windows Word stores it in the query), otherwise the first one
    private static func readXLSX(_ url: URL, sheet: String?) throws -> [[String]] {
        let unreadable = ConvError(tr("Word couldn't read the address list “%@”.", url.lastPathComponent))
        guard let workbook = Zip.text(url, "xl/workbook.xml"), let rels = Zip.text(url, "xl/_rels/workbook.xml.rels") else { throw unreadable }
        let sheets = XMLRows.elements("sheet", in: workbook)
        guard let chosen = sheets.first(where: { $0["name"] == sheet }) ?? sheets.first,
              let rid = chosen["r:id"],
              let target = XMLRows.elements("Relationship", in: rels).first(where: { $0["Id"] == rid })?["Target"] else { throw unreadable }
        let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
        guard let xml = Zip.text(url, path) else { throw unreadable }
        let shared = Zip.text(url, "xl/sharedStrings.xml").map(XMLRows.sharedStrings) ?? []
        let dateStyles = Zip.text(url, "xl/styles.xml").map(XMLRows.dateStyles) ?? []
        return XMLRows.sheet(xml, shared: shared, dateStyles: dateStyles)
    }

    // MARK: CSV

    private static func readCSV(_ url: URL) throws -> [[String]] {
        guard let data = try? Data(contentsOf: url) else { throw ConvError(tr("File can't be read")) }
        // UTF-8 (with or without BOM), otherwise what Excel for Windows and old Macs write
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .macOSRoman) else { throw ConvError(tr("File can't be read")) }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let firstLine = text.prefix { !$0.isNewline }
        let sep: Character = [";", "\t", ","].max { a, b in firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count } ?? ";"
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars.removeFirst() } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty {
                quoted = true
            } else if c == sep {
                row.append(field); field = ""
            } else if c.isNewline {   // "\r\n" is one Character
                row.append(field); rows.append(row); row = []; field = ""
            } else { field.append(c) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Reading files inside zip packages (.docx, .xlsx) with the system's unzip and zip
enum Zip {
    static func text(_ zip: URL, _ entry: String) -> String? {
        let r = run("/usr/bin/unzip", ["-p", zip.path, entry])
        guard r.status == 0, !r.data.isEmpty else { return nil }
        return String(data: r.data, encoding: .utf8)
    }

    static func run(_ exe: String, _ args: [String], in dir: URL? = nil) -> (status: Int32, data: Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let dir { p.currentDirectoryURL = dir }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, Data()) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, data)
    }
}

/// The parts of the Excel file format an address list needs
private final class XMLRows: NSObject, XMLParserDelegate {
    /// Attributes of every element with this name
    static func elements(_ name: String, in xml: String) -> [[String: String]] {
        let p = XMLRows()
        p.onStart = { el, attrs in if el == name { p.found.append(attrs) } }
        p.parse(xml)
        return p.found
    }

    /// Every <si> entry's text (rich text runs joined, phonetic hints left out)
    static func sharedStrings(_ xml: String) -> [String] {
        let p = XMLRows()
        var result: [String] = [], current = "", inPhonetic = false
        p.onStart = { el, _ in if el == "si" { current = "" } else if el == "rPh" { inPhonetic = true } }
        p.onEnd = { el, text in
            switch el {
            case "t" where !inPhonetic: current += text
            case "rPh": inPhonetic = false
            case "si": result.append(current)
            default: break
            }
        }
        p.parse(xml)
        return result
    }

    /// Style indexes (the "s" of a cell) whose number format shows a date
    static func dateStyles(_ xml: String) -> Set<Int> {
        let p = XMLRows()
        var custom: [Int: String] = [:], styles: [Int] = [], inCellXfs = false
        p.onStart = { el, a in
            if el == "numFmt", let id = a["numFmtId"].flatMap(Int.init) { custom[id] = a["formatCode"] ?? "" }
            if el == "cellXfs" { inCellXfs = true }
            if el == "xf", inCellXfs { styles.append(a["numFmtId"].flatMap(Int.init) ?? 0) }
        }
        p.onEnd = { el, _ in if el == "cellXfs" { inCellXfs = false } }
        p.parse(xml)
        func isDate(_ id: Int) -> Bool {
            if (14...22).contains(id) || (45...47).contains(id) { return true }
            guard let code = custom[id] else { return false }
            // Without quoted text and [colors]: day, month or year letters make it a date
            let bare = code.replacingOccurrences(of: #""[^"]*"|\[[^\]]*\]"#, with: "", options: .regularExpression).lowercased()
            return bare.contains { "dmy".contains($0) } && !bare.contains("0")
        }
        return Set(styles.indices.filter { isDate(styles[$0]) })
    }

    /// Cell texts by row, placed by their column letters (empty cells are left out of the file)
    static func sheet(_ xml: String, shared: [String], dateStyles: Set<Int>) -> [[String]] {
        let p = XMLRows()
        var rows: [[String]] = [], row: [String] = []
        var col = 0, type = "", style = 0, value = "", inline = ""
        p.onStart = { el, a in
            switch el {
            case "row": row = []
            case "c":
                col = a["r"].map(columnIndex) ?? row.count
                type = a["t"] ?? ""; style = a["s"].flatMap(Int.init) ?? 0; value = ""; inline = ""
            default: break
            }
        }
        p.onEnd = { el, text in
            switch el {
            case "v": value = text
            case "t": inline += text
            case "c":
                let s: String
                switch type {
                case "s": s = Int(value).flatMap { $0 < shared.count ? shared[$0] : nil } ?? ""
                case "inlineStr": s = inline
                case "b": s = value == "1" ? "TRUE" : "FALSE"
                case "str", "e": s = value
                default: s = dateStyles.contains(style) ? date(value) : number(value)
                }
                if col >= row.count { row += Array(repeating: "", count: col - row.count + 1) }
                row[col] = s
            case "row": rows.append(row)
            default: break
            }
        }
        p.parse(xml)
        return rows
    }

    /// "AB12" → 27
    private static func columnIndex(_ ref: String) -> Int {
        ref.prefix { $0.isLetter }.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    /// Whole numbers without ".0" (postal codes, house numbers); others as Excel stored them
    private static func number(_ v: String) -> String {
        guard let d = Double(v), d == d.rounded(), abs(d) < 1e15 else { return v }
        return String(Int64(d))
    }

    /// Excel day number → "15.03.2026" (time of day left out)
    private static func date(_ v: String) -> String {
        guard let d = Double(v) else { return v }
        let base = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"), year: 1899, month: 12, day: 30).date!
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: base.addingTimeInterval(d.rounded(.down) * 86400))
    }

    private var onStart: (String, [String: String]) -> Void = { _, _ in }
    private var onEnd: (String, String) -> Void = { _, _ in }
    private var found: [[String: String]] = []
    private var text = ""

    private func parse(_ xml: String) {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        onStart(el, attributes)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        onEnd(el, text)
        text = ""
    }
}
