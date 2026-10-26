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
    static let script = """
    on findIndex(p)
        tell application "Microsoft Word"
            repeat with i from 1 to (count of documents)
                if (posix full name of document i) is p then return i
            end repeat
        end tell
        return 0
    end findIndex

    on run argv
        set src to item 1 of argv
        set dst to item 2 of argv
        tell application "Microsoft Word" to open (POSIX file src) read only true add to recent files false
        set i to 0
        repeat 40 times
            set i to my findIndex(src)
            if i > 0 then exit repeat
            delay 0.25
        end repeat
        if i = 0 then error "NOT_OPENED"
        try
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

    static func toPDF(_ src: URL, name: String, folder: URL?) throws -> URL {
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

        let (ok, output) = runScript([copy.path, tmp.path], timeout: 180)
        guard ok, FileManager.default.fileExists(atPath: tmp.path) else {
            if output == "TIMEOUT" || output.contains("NOT_OPENED") || output.contains("-1712") { stuck = true }
            throw ConvError(message(for: output))
        }
        let out = uniqueURL(folder ?? src.deletingLastPathComponent(), name, "pdf")
        do { try FileManager.default.moveItem(at: tmp, to: out) } catch { throw ConvError(tr("Can't write to destination")) }
        return out
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
