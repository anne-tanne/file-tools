import AppKit

/// Word documents to PDF by driving Microsoft Word (same result as File > Save As > PDF, so the layout stays exact)
enum WordOps {
    static let bundleID = "com.microsoft.Word"
    static let extensions: Set = ["doc", "docx", "docm", "dot", "dotx", "rtf", "odt"]

    static var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// Word is sandboxed: it saves into its own temp folder without asking for file access, we move the PDF from there
    static var wordTemp: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/tmp", isDirectory: true)
    }

    // Word works on a copy inside its own container: opening a file elsewhere by script makes the sandboxed Word
    // show a blocking "Grant File Access" dialog, and the user's original is never opened (or already open) this way.
    // The copy is found by its path, never via "active document" (that can be another file the user has open), and
    // documents are addressed by index: Word rejects "close" on references kept in a variable (-1708).
    // "every document" errors when none is open, so documents are counted and walked by index.
    private static let findIndex = """
    on findIndex(p)
        tell application "Microsoft Word"
            repeat with i from 1 to (count of documents)
                if (posix full name of document i) is p then return i
            end repeat
        end tell
        return 0
    end findIndex

    on openCopy(src, waitSeconds)
        with timeout of (waitSeconds + 10) seconds
            tell application "Microsoft Word" to open (POSIX file src) read only true add to recent files false
        end timeout
        set i to 0
        repeat (waitSeconds * 4) times
            set i to my findIndex(src)
            if i > 0 then return i
            delay 0.25
        end repeat
        error "NOT_OPENED"
    end openCopy

    on tidy(i, clean, refresh)
        tell application "Microsoft Word"
            if clean then
                try
                    accept all revisions document i
                end try
                try
                    delete all comments document i
                end try
            end if
            if refresh then
                -- otherwise updated fields show up as tracked changes
                try
                    set track revisions of document i to false
                end try
                -- fields that ask for input or point to other files would open a dialog or fail
                set skip to {field ask, field fill in, field include, field include picture, field include text, field link}
                repeat with k from 1 to (count of fields of document i)
                    try
                        if field type of field k of document i is not in skip then update field (field k of document i)
                    end try
                end repeat
                -- last, so the page numbers match the final text
                repeat with k from 1 to (count of tables of contents of document i)
                    try
                        update (table of contents k of document i)
                    end try
                end repeat
            end if
        end tell
    end tidy

    """

    static let script = findIndex + """
    on run argv
        set src to item 1 of argv
        set dst to item 2 of argv
        set clean to (item 3 of argv) is "1"
        set refresh to (item 4 of argv) is "1"
        set i to my openCopy(src, 10)
        try
            my tidy(i, clean, refresh)
            tell application "Microsoft Word" to save as document i file name dst file format format PDF
        on error e
            set i to my findIndex(src)
            if i > 0 then tell application "Microsoft Word" to close document i saving no
            error e
        end try
        set i to my findIndex(src)
        if i > 0 then tell application "Microsoft Word" to close document i saving no
        return "OK"
    end run
    """

    /// Set when Word stops responding, so the rest of the batch doesn't wait for it file by file (jobs run one at a time)
    nonisolated(unsafe) static var stuck = false

    struct Options: Sendable {
        var final = true          // accept tracked changes and drop comments, so no markup ends up in the PDF
        var updateFields = true   // fields and tables of contents, as Word would before printing
    }

    /// Saves the document as a PDF at `out` (Word only ever changes its own copy)
    static func toPDF(_ src: URL, options: Options, to out: URL) throws {
        guard isInstalled else { throw ConvError(tr("Microsoft Word is needed for this")) }
        guard !stuck else { throw ConvError(tr("Not converted: Word wasn't responding")) }
        let fm = FileManager.default
        let work = wordTemp.appendingPathComponent("FileTools-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        let copy = work.appendingPathComponent(src.lastPathComponent)   // same name, so Word's FILENAME fields still match
        let tmp = work.appendingPathComponent("out.pdf")
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: copy)
        } catch { throw ConvError(tr("File can't be read")) }

        let (ok, output) = runScript([copy.path, tmp.path, options.final ? "1" : "0", options.updateFields ? "1" : "0"], timeout: 300)
        guard ok, FileManager.default.fileExists(atPath: tmp.path) else {
            if output == "TIMEOUT" || output.contains("NOT_OPENED") || output.contains("-1712") { stuck = true }
            throw ConvError(message(for: output))
        }
        do { try FileManager.default.moveItem(at: tmp, to: out) } catch { throw ConvError(tr("Can't write to destination")) }
    }

    // MARK: Serienbriefe (mail merge)

    /// A Serienbrief main document: Word fills it in from an address list, one letter per row
    struct MergeInfo: Sendable {
        var fields: [String]     // merge fields used in the letter, in order, for naming the PDFs
        var list: String?        // path of the address list as stored in the letter
        var sheet: String?       // Excel sheet, when the letter names one (Windows Word does)
        var type: String         // Word's main document type: formLetters, mailingLabels, envelopes, catalog, …
        var filtered: Bool       // recipients filtered or unticked in Word
        var wholeList: Bool { type == "mailingLabels" || type == "catalog" }   // all rows on shared pages, not one letter each

        /// Suggested file names: "{Nachname} {Vorname}" when the letter has these fields, otherwise its first two
        var nameExample: String {
            let pick = ["Nachname", "Vorname"].allSatisfy(fields.contains) ? ["Nachname", "Vorname"] : Array(fields.prefix(2))
            return pick.map { "{\($0)}" }.joined(separator: " ")
        }
    }

    /// One merged letter: its PDF, its Word document if asked for, and its row of the address list (by column name)
    struct Letter: Sendable {
        var url: URL
        var docx: URL?
        var values: [String: String]
    }

    /// Only .docx-type files are looked into (zip with XML); old .doc letters are converted as they are
    static func mergeInfo(_ url: URL) -> MergeInfo? {
        guard ["docx", "docm", "dotx", "dotm"].contains(url.pathExtension.lowercased()),
              let settings = Zip.text(url, "word/settings.xml"),
              let merge = firstMatch(#"(<w:mailMerge>.*?</w:mailMerge>)"#, in: settings) else { return nil }
        let type = firstMatch(#"<w:mainDocumentType w:val="([^"]+)""#, in: merge) ?? "formLetters"
        guard type != "notAMergeDocument" else { return nil }
        let query = xmlUnescape(firstMatch(#"<w:query w:val="([^"]*)""#, in: merge) ?? "")
        var list: String? = nil
        let rels = Zip.text(url, "word/_rels/settings.xml.rels")
        if let rels, let target = firstMatch(#"Type="[^"]*/mailMergeSource"[^>]*Target="([^"]+)""#, in: rels)
                ?? firstMatch(#"Target="([^"]+)"[^>]*Type="[^"]*/mailMergeSource""#, in: rels) {
            list = listPath(target)
        }
        // Field codes become plain text once the XML tags are gone ("MERGEFIELD Vorname \* MERGEFORMAT")
        var fields: [String] = []
        if let doc = Zip.text(url, "word/document.xml") {
            let text = doc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let re = try! NSRegularExpression(pattern: #"MERGEFIELD\s+(?:"([^"]+)"|([^\s\\"]+))"#)
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
                if let r = Range(r, in: text) {
                    let f = xmlUnescape(String(text[r]))
                    if !fields.contains(f) { fields.append(f) }
                }
            }
        }
        // Unticked recipients (Windows Word): a part listing every row with active = 0 or 1
        var unticked = false
        if let rels, let id = firstMatch(#"<w:recipientData r:id="([^"]+)""#, in: merge),
           let target = firstMatch(#"Id="\#(id)"[^>]*Target="([^"]+)""#, in: rels) ?? firstMatch(#"Target="([^"]+)"[^>]*Id="\#(id)""#, in: rels),
           let data = Zip.text(url, "word/" + target) {
            unticked = data.range(of: #"<w:active w:val="(0|false)""#, options: .regularExpression) != nil
        }
        return MergeInfo(fields: fields, list: list, sheet: firstMatch(#"FROM\s+`([^`]+)\$`"#, in: query), type: type,
                         filtered: unticked || query.range(of: #"\sWHERE\s"#, options: [.regularExpression, .caseInsensitive]) != nil)
    }

    // Word works on a copy of the letter without its own link to the list ("open" attaches File Tools' table to it).
    // Merged letters go to a new document (Word names it "Serienbriefe1" etc.), found as the one that wasn't there before.
    private static let mergeScript = findIndex + """
    on run argv
        set mode to item 1 of argv
        set src to item 2 of argv
        if mode is "open" then
            set i to my openCopy(src, 10)
            set docKind to item 4 of argv
            tell application "Microsoft Word"
                open data source data merge of document i name (item 3 of argv)
                set dm to data merge of document i
                if docKind is "labels" then
                    set main document type of dm to document type mailing labels
                else if docKind is "envelopes" then
                    set main document type of dm to document type envelopes
                else if docKind is "catalog" then
                    set main document type of dm to document type catalog
                end if
                set ds to data source of dm
                if (count of data merge field names of ds) is 0 then error "NO_LIST"
                set active record of ds to last data record
                return (active record of ds) as text
            end tell
        else if mode is "merge" then
            set i to my findIndex(src)
            if i = 0 then error "NOT_OPENED"
            tell application "Microsoft Word"
                set known to {}
                repeat with k from 1 to (count of documents)
                    set end of known to name of document k
                end repeat
                set dm to data merge of document i
                set destination of dm to send to new document
                set first record of data source of dm to (item 3 of argv) as integer
                set last record of data source of dm to (item 4 of argv) as integer
                execute data merge dm pause false
                set j to 0
                repeat with k from 1 to (count of documents)
                    if name of document k is not in known then set j to k
                end repeat
            end tell
            if j = 0 then error "NOT_MERGED"
            try
                my tidy(j, (item 6 of argv) is "1", (item 7 of argv) is "1")
                tell application "Microsoft Word" to save as document j file name (item 5 of argv) file format format PDF
                if (item 8 of argv) is not "" then
                    tell application "Microsoft Word" to save as document j file name (item 8 of argv) file format format document
                end if
            on error e
                tell application "Microsoft Word" to close document j saving no
                error e
            end try
            tell application "Microsoft Word" to close document j saving no
            return "OK"
        else
            set i to my findIndex(src)
            if i > 0 then tell application "Microsoft Word" to close document i saving no
            return "OK"
        end if
    end run
    """

    /// Word merges the letters one at a time into PDFs inside `work`, one per row of the address list (empty rows
    /// are left out); `progress(0, 0)` while Word opens the letter. Everything that would stop Word with a question
    /// (list missing, Excel or CSV list) is dealt with before Word opens anything.
    /// `wordFiles`: each letter also as a Word document (letters merged one at a time only)
    static func mergeLetters(_ src: URL, options: Options, wordFiles: Bool = false, work: URL,
                             progress: @Sendable (Int, Int) -> Void) throws -> [Letter] {
        guard isInstalled else { throw ConvError(tr("Microsoft Word is needed for this")) }
        guard !stuck else { throw ConvError(tr("Not converted: Word wasn't responding")) }
        guard let info = mergeInfo(src) else { throw ConvError(tr("This is not a mail merge document")) }
        guard let stored = info.list else { throw ConvError(tr("No address list is connected to this mail merge document")) }
        guard !info.filtered else {
            throw ConvError(tr("Recipients are filtered or unticked in this letter. File Tools can't apply that yet: remove the filter in Word (Sendungen › Empfängerliste bearbeiten) or make a list with only these recipients."))
        }
        let fm = FileManager.default
        let name = stored.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? stored
        // Not where the letter says (a letter from someone else): the same file next to the letter
        let nextTo = src.deletingLastPathComponent().appendingPathComponent(name).path
        guard let list = [stored, nextTo].first(where: { fm.fileExists(atPath: $0) }) else {
            throw ConvError(tr("The address list “%@” wasn't found. Put it in the same folder as the letter.", name))
        }
        let table = try MergeList.read(URL(fileURLWithPath: list), sheet: info.sheet)
        guard table.count > 1 else { throw ConvError(tr("The address list “%@” has no entries.", name)) }

        let copyDir = wordTemp.appendingPathComponent("FileTools-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: copyDir) }
        let copy = copyDir.appendingPathComponent(src.lastPathComponent)
        let listCopy = copyDir.appendingPathComponent("Liste.docx")
        do {
            try fm.createDirectory(at: copyDir, withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: copy)
            try unlink(copy)
            try MergeList.writeTable(table, to: listCopy)
        } catch { throw ConvError(tr("File can't be read")) }

        progress(0, 0)
        let kind = ["mailingLabels": "labels", "envelopes": "envelopes", "catalog": "catalog"][info.type] ?? "letters"
        let (opened, output) = runOSA(mergeScript, ["open", copy.path, listCopy.path, kind], timeout: 120)
        defer { _ = runOSA(mergeScript, ["close", copy.path], timeout: 30) }
        guard opened else {
            if output == "TIMEOUT" || output.contains("-1712") { stuck = true }
            if output.contains("NO_LIST") { throw ConvError(tr("Word couldn't read the address list “%@”.", name)) }
            throw ConvError(message(for: output))
        }
        let rows = Array(table.dropFirst())
        guard Int(output) == rows.count else { throw ConvError(tr("Word couldn't read the address list “%@”.", name)) }
        let header = table[0]

        // Labels and directories: the whole list at once
        let batches = info.wholeList ? [(1, rows.count, [String]())] : rows.enumerated().map { ($0 + 1, $0 + 1, $1) }
        var letters: [Letter] = []
        for (n, b) in batches.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            progress(n + 1, batches.count)
            let pdf = work.appendingPathComponent("letter-\(n + 1).pdf")
            let tmp = copyDir.appendingPathComponent("\(n + 1).pdf")
            let docx = wordFiles && !info.wholeList ? work.appendingPathComponent("letter-\(n + 1).docx") : nil
            let tmpDocx = docx.map { _ in copyDir.appendingPathComponent("\(n + 1).docx") }
            let (ok, out) = runOSA(mergeScript, ["merge", copy.path, String(b.0), String(b.1), tmp.path,
                                                 options.final ? "1" : "0", options.updateFields ? "1" : "0", tmpDocx?.path ?? ""],
                                   timeout: 180)
            guard ok, fm.fileExists(atPath: tmp.path), tmpDocx.map({ fm.fileExists(atPath: $0.path) }) ?? true else {
                if out == "TIMEOUT" || out.contains("-1712") { stuck = true }
                throw ConvError(message(for: out))
            }
            do {
                try fm.moveItem(at: tmp, to: pdf)
                if let docx, let tmpDocx { try fm.moveItem(at: tmpDocx, to: docx) }
            } catch { throw ConvError(tr("Can't write to destination")) }
            letters.append(Letter(url: pdf, docx: docx, values: Dictionary(zip(header, b.2), uniquingKeysWith: { a, _ in a })))
        }
        return letters
    }

    /// Takes the letter's own link to its address list out of the copy, so Word doesn't try to open the list itself
    private static func unlink(_ docx: URL) throws {
        let fm = FileManager.default
        let patch = docx.deletingLastPathComponent().appendingPathComponent("patch", isDirectory: true)
        defer { try? fm.removeItem(at: patch) }
        guard var xml = Zip.text(docx, "word/settings.xml") else { throw ConvError(tr("File can't be read")) }
        xml = xml.replacingOccurrences(of: #"<w:mailMerge>.*?</w:mailMerge>"#, with: "", options: .regularExpression)
        let out = patch.appendingPathComponent("word/settings.xml")
        try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try xml.write(to: out, atomically: true, encoding: .utf8)
        guard Zip.run("/usr/bin/zip", ["-q", docx.path, "word/settings.xml"], in: patch).status == 0 else { throw ConvError(tr("File can't be read")) }
        _ = Zip.run("/usr/bin/zip", ["-q", "-d", docx.path, "word/_rels/settings.xml.rels"])
    }

    /// "file:////Users/as/Adressen.xlsx" → "/Users/as/Adressen.xlsx"; Windows paths stay as they are (only the name is used)
    private static func listPath(_ target: String) -> String {
        var s = xmlUnescape(target)
        if s.lowercased().hasPrefix("file:") { s = String(s.dropFirst(5)) }
        s = s.removingPercentEncoding ?? s
        if s.hasPrefix("/") { s = "/" + s.drop(while: { $0 == "/" }) }
        return s
    }

    private static func firstMatch(_ pattern: String, in s: String) -> String? {
        let re = try! NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    private static func xmlUnescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Quits Word if it has no documents open (used when Word was only started for the conversion)
    static func quitIfIdle() {
        _ = runOSA("""
        tell application "Microsoft Word"
            if (count of documents) is 0 then quit saving no
        end tell
        """, [], timeout: 30)
    }

    private static func runScript(_ args: [String], timeout: TimeInterval) -> (Bool, String) {
        runOSA(script, args, timeout: timeout)
    }

    /// Runs AppleScript through osascript (NSAppleScript isn't safe off the main thread); returns success and stdout/stderr
    private static func runOSA(_ source: String, _ args: [String], timeout: TimeInterval) -> (Bool, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return (false, error.localizedDescription) }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return (false, "TIMEOUT")
        }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (p.terminationStatus == 0, out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func message(for output: String) -> String {
        if output == "TIMEOUT" || output.contains("-1712") {
            return tr("Word didn't respond. Is the file password protected, or is a dialog open in Word?")
        }
        if output.contains("NOT_OPENED") {
            return tr("Word didn't open the file. Is a dialog open in Word?")
        }
        if output.contains("-1743") {
            return tr("Not allowed to control Word: turn on File Tools › Microsoft Word in System Settings › Privacy & Security › Automation")
        }
        // osascript: "…: execution error: Word got an error: … (-1708)"
        let detail = output.components(separatedBy: "execution error: ").last ?? output
        return tr("Word: ") + detail
    }
}
