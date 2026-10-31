import SwiftUI

@main
struct FileToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = Model.shared

    var body: some Scene {
        Window("File Tools", id: "main") { ContentView(model: model) }
            .windowResizability(.contentMinSize)
            .windowToolbarStyle(.unified)
            .commands {
                SidebarCommands()
                ToolCommands()
                ImportFromDevicesCommands()
            }
    }
}

/// Menu bar entries for everything the window offers, so each action has a menu item and a shortcut
struct ToolCommands: Commands {
    @FocusedObject var m: Model?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Files…") { m?.pickFiles() }
                .keyboardShortcut("o")
                .disabled(m == nil || m?.busy == true)
            Button("Choose Output Folder…") { m?.pickFolder() }
                .disabled(m == nil || m?.writesFiles != true)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Show in Finder") { m?.showInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(m?.lastOutputs.isEmpty ?? true)
            Button("Quick Look") { m?.quickLook = m?.previewURLs.first }
                .keyboardShortcut("y")
                .disabled(m?.previewURLs.isEmpty ?? true)
        }
        CommandMenu("Tool") {
            ForEach(Array(Tool.allCases.enumerated()), id: \.element) { n, t in
                // ⌘1 to ⌘9 for the first nine tools
                Button { m?.tool = t } label: { Label(t.rawValue, systemImage: t.icon) }
                    .keyboardShortcut(n < 9 ? KeyboardShortcut(KeyEquivalent(Character(String(n + 1)))) : nil)
                    .disabled(m == nil || m?.busy == true)
            }
            Divider()
            Button("Save as Preset…") { if let m { m.savePresetTool = m.tool } }
                .disabled(m == nil || m?.busy == true || m?.activePreset != nil || m?.tool.isChainable != true)
            Button("Watch Folders…") { m?.showWatchFolders = true }
                .disabled(m == nil)
            Divider()
            Button(m.map { $0.activePreset != nil ? "Run Preset" : $0.tool.action } ?? "Start") { m?.run() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(m == nil || m?.busy == true || m?.canRun != true)
        }
    }
}
