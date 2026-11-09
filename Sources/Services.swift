import SwiftUI

extension Model {
    /// The one model shared by the window and the Finder services
    static let shared = Model()

    /// Finder quick action: shows the tool with exactly these files and runs it with the saved settings.
    /// While a run is going, the files are only added.
    func serviceRun(_ tool: Tool, _ urls: [URL]) {
        if busy { add(urls); return }
        self.tool = tool
        clearList(undo: nil)
        add(urls)
        run()
    }

    /// Finder quick action for Word documents: a Serienbrief first asks for one PDF per letter or one for all,
    /// and how the letters are named (both kept as the window's settings)
    func serviceWordToPDF(_ urls: [URL]) {
        if busy { add(urls); return }
        tool = .wordToPDF
        clearList(undo: nil)
        add(urls)
        if !settings.wordCombine, let merge = mergeItems.first?.merge {
            guard askMerge(merge) else { return }
        }
        run()
    }

    /// false when cancelled
    private func askMerge(_ merge: WordOps.MergeInfo) -> Bool {
        let alert = NSAlert()
        alert.messageText = tr("Create PDFs from the mail merge")
        alert.informativeText = merge.fields.isEmpty
            ? tr("Fields in braces are filled in for each letter. Left empty, the letters are numbered.")
            : tr("Fields in braces are filled in for each letter. Left empty, the letters are numbered.") + "\n\n"
                + tr("Fields in this letter: %@", merge.fields.map { "{\($0)}" }.joined(separator: " "))
        alert.addButton(withTitle: tr("Create PDFs"))
        alert.addButton(withTitle: tr("Cancel"))
        let mode = NSPopUpButton(frame: .zero, pullsDown: false)
        mode.addItems(withTitles: MergeOutput.allCases.map(\.title))
        mode.selectItem(at: MergeOutput.allCases.firstIndex(of: settings.wordMerge) ?? 0)
        mode.isHidden = merge.wholeList
        let saved = settings.wordMergeName.trimmingCharacters(in: .whitespaces)
        let field = NSTextField(string: saved.isEmpty ? merge.nameExample : saved)
        field.placeholderString = tr("Letter")
        let label = NSTextField(labelWithString: tr("File names"))
        let docx = NSButton(checkboxWithTitle: tr("Also as Word documents"), target: nil, action: nil)
        docx.state = settings.wordMergeDocx ? .on : .off
        // Word documents only go with one PDF per letter
        let link = EnableWhenEach(mode: mode, box: docx)
        mode.target = link
        mode.action = #selector(EnableWhenEach.changed)
        link.changed()
        docx.isHidden = merge.wholeList
        let stack = NSStackView(views: [mode, docx, label, field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: docx)
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: stack.fittingSize.height)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = field
        let answer = withExtendedLifetime(link) { alert.runModal() }
        guard answer == .alertFirstButtonReturn else { return false }
        if !merge.wholeList {
            settings.wordMerge = MergeOutput.allCases[max(0, mode.indexOfSelectedItem)]
            settings.wordMergeDocx = docx.state == .on
        }
        var name = field.stringValue.trimmingCharacters(in: .whitespaces)
        if name.lowercased().hasSuffix(".pdf") { name = String(name.dropLast(4)) }
        settings.wordMergeName = name
        return true
    }

    /// Finder quick action on a folder (or loose files): one PDF from all PDFs and images in it, named in a dialog.
    /// A single folder gives a PDF next to it, so a second run doesn't pick it up.
    func serviceCombine(_ urls: [URL]) {
        if busy { add(urls); return }
        tool = .combine
        clearList(undo: nil)
        add(urls)
        guard !eligible.isEmpty else { return }
        var isDir: ObjCBool = false
        let folder = urls.count == 1 && FileManager.default.fileExists(atPath: urls[0].path, isDirectory: &isDir) && isDir.boolValue
            ? urls[0] : nil
        // The name set in the window as suggestion; unchanged, a folder suggests its own name
        let saved = settings.combinedName.trimmingCharacters(in: .whitespaces)
        let suggestion = withDate(saved.isEmpty || saved == tr("Combined") ? folder?.lastPathComponent ?? tr("Combined") : saved)
        guard let name = askName(suggestion) else { return }
        combineTarget = ((folder ?? eligible[0].url).deletingLastPathComponent(), name)
        run()
    }

    /// Name for the combined PDF, nil when cancelled
    private func askName(_ suggestion: String) -> String? {
        let alert = NSAlert()
        alert.messageText = tr("Combine into one PDF")
        alert.informativeText = tr("Name of the new PDF. yymmdd becomes today's date.")
        alert.addButton(withTitle: tr("Create PDF"))
        alert.addButton(withTitle: tr("Cancel"))
        let field = NSTextField(string: suggestion)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        var name = withDate(field.stringValue.trimmingCharacters(in: .whitespaces))
        if name.lowercased().hasSuffix(".pdf") { name = String(name.dropLast(4)) }
        return name.isEmpty ? suggestion : name
    }
}

/// Quick action dialog: the Word documents checkbox is only for one PDF per letter
private final class EnableWhenEach: NSObject {
    let mode: NSPopUpButton, box: NSButton
    init(mode: NSPopUpButton, box: NSButton) { self.mode = mode; self.box = box }
    @objc func changed() { box.isEnabled = MergeOutput.allCases[max(0, mode.indexOfSelectedItem)] == .each }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let provider = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
        FolderWatcher.shared.start()
    }

    /// Single-window utility: closing the window quits, so a quick action always starts with a fresh window
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Handlers for the NSServices entries in Info.plist (NSMessage = method name)
final class ServiceProvider: NSObject {
    private func handle(_ pboard: NSPasteboard, _ error: AutoreleasingUnsafeMutablePointer<NSString?>,
                        _ action: @escaping @MainActor (Model, [URL]) -> Void) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { error.pointee = "No files" as NSString; return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
                if let w = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    if w.isMiniaturized { w.deminiaturize(nil) }
                    w.makeKeyAndOrderFront(nil)
                }
                action(Model.shared, urls)
            }
        }
    }

    @objc func compress(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handle(pboard, error) { $0.serviceRun(.compress, $1) }
    }
    @objc func removeInfo(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handle(pboard, error) { $0.serviceRun(.strip, $1) }
    }
    @objc func watermark(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handle(pboard, error) { $0.serviceRun(.watermark, $1) }
    }
    @objc func makeSearchable(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handle(pboard, error) { $0.serviceRun(.makeSearchable, $1) }
    }
    @objc func recognizeText(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handle(pboard, error) { $0.serviceRun(.recognizeText, $1) }
    }
    @objc func wordToPDF(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handle(pboard, error) { $0.serviceWordToPDF($1) }
    }
    @objc func combine(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handle(pboard, error) { $0.serviceCombine($1) }
    }
    @objc func runPreset(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handle(pboard, error) { $0.openPresets($1) }
    }
}
