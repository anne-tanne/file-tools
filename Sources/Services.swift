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
        handle(pboard, error) { $0.serviceRun(.wordToPDF, $1) }
    }
    @objc func runPreset(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        handle(pboard, error) { $0.openPresets($1) }
    }
}
