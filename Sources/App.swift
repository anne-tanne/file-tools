import SwiftUI

@main
struct FileToolsApp: App {
    var body: some Scene {
        WindowGroup("File Tools") { ContentView() }
            .windowResizability(.contentMinSize)
            .windowToolbarStyle(.unified)
            .commands {
                SidebarCommands()
                ToolCommands()
            }
        Settings { SettingsView() }
    }
}

struct SettingsView: View {
    @AppStorage(L10n.defaultsKey) private var language = L10n.lang.rawValue   // redraws on change

    var body: some View {
        Form {
            Picker(tr("Language"), selection: Binding(get: { L10n.lang }, set: { L10n.set($0) })) {
                ForEach(Lang.allCases) { Text($0.name).tag($0) }
            }
            Text(tr("Menus that come from macOS switch language after the app is restarted."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Menu bar entries for everything the window offers, so each action has a menu item and a shortcut
struct ToolCommands: Commands {
    @FocusedObject var m: Model?
    @AppStorage(L10n.defaultsKey) private var language = L10n.lang.rawValue   // redraws on change

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(tr("Add Files…")) { m?.pickFiles() }
                .keyboardShortcut("o")
                .disabled(m == nil || m?.busy == true)
            Button(tr("Choose Output Folder…")) { m?.pickFolder() }
                .disabled(m == nil || m?.tool.writesFiles != true)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button(tr("Show in Finder")) { m?.showInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(m?.lastOutputs.isEmpty ?? true)
            ShareLink(items: m?.lastOutputs ?? []) { Text(tr("Share")) }
                .disabled(m == nil || m?.busy == true || m?.lastOutputs.isEmpty != false)
        }
        CommandMenu(tr("Tool")) {
            // Same groups and order as the sidebar; ⌘1 to ⌘9 for the first nine tools
            ForEach(Tool.groups, id: \.title) { g in
                ForEach(g.tools) { t in
                    let n = Tool.allCases.firstIndex(of: t)!
                    Button { m?.tool = t } label: { Label(t.title, systemImage: t.icon) }
                        .keyboardShortcut(n < 9 ? KeyboardShortcut(KeyEquivalent(Character(String(n + 1)))) : nil)
                        .disabled(m == nil || m?.busy == true)
                }
                Divider()
            }
            Button(m.map { $0.tool.action } ?? tr("Start")) { m?.run() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(m == nil || m?.busy == true || m?.canRun != true)
            Button(tr("Stop")) { m?.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(m?.canStop != true)
        }
    }
}
