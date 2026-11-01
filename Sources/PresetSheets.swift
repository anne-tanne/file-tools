import SwiftUI

// MARK: - Save as preset

/// Saves the current tool and its settings as a new preset or as a step of an existing one
struct SavePresetSheet: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    let tool: Tool
    @State private var name: String
    @State private var target: UUID? = nil   // nil = new preset

    init(tool: Tool) {
        self.tool = tool
        _name = State(initialValue: tool.title)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(tr("Save as Preset"), systemImage: "star").font(.headline)
            Text(tr("A preset runs several steps one after another on every file. This one starts with “%@” and its current settings.", tool.title))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker(tr("Save as"), selection: $target) {
                Text(tr("New preset")).tag(UUID?.none)
                if !m.presets.isEmpty {
                    Divider()
                    ForEach(m.presets) { p in Text(tr("Add as step to “%@”", p.name)).tag(Optional(p.id)) }
                }
            }
            .pickerStyle(.menu)
            if target == nil {
                TextField(tr("Name"), text: $name, prompt: Text(tr("Preset name")))
            }
            HStack {
                Spacer()
                Button(tr("Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("Save")) {
                    m.savePreset(name: trimmed, tool: tool, settings: m.settings, addingTo: target)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(target == nil && trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

// MARK: - Edit preset

/// Name, steps and the settings of the selected step. Changes only apply on Save.
struct EditPresetSheet: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Preset
    @State private var selection: PresetStep.ID?
    @State private var confirmDelete = false
    /// Holds the selected step's settings so the normal settings editor can be reused; never saves anything itself
    @StateObject private var scratch: Model

    init(preset: Preset) {
        _draft = State(initialValue: preset)
        _selection = State(initialValue: preset.steps.first?.id)
        let model = Model(persist: false)
        model.forcePDF = true
        if let first = preset.steps.first { model.settings = first.settings }
        _scratch = StateObject(wrappedValue: model)
    }

    private var selectedIndex: Int? { draft.steps.firstIndex { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(tr("Name"), text: $draft.name, prompt: Text(tr("Preset name")))
                .font(.title3)

            HStack {
                Text(tr("Steps, in this order")).font(.headline)
                Spacer()
                Menu {
                    ForEach(Tool.chainable) { t in
                        Button { add(t) } label: { Label(t.title, systemImage: t.icon) }
                            .disabled(t == .recognizeText && draft.steps.contains { $0.tool == .recognizeText })
                    }
                } label: {
                    Label(tr("Add Step"), systemImage: "plus")
                }
                .fixedSize()
            }

            List(selection: $selection) {
                ForEach(Array(draft.steps.enumerated()), id: \.element.id) { n, step in
                    HStack(spacing: 8) {
                        Text("\(n + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
                        Label(step.tool.title, systemImage: step.tool.icon)
                        Text(step.settings.summary(for: step.tool)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button { remove(step.id) } label: { Label(tr("Delete Step"), systemImage: "minus.circle.fill") }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                            .help(tr("Delete this step"))
                    }
                    .tag(step.id)
                }
                .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1); keepTextLast() }
            }
            .frame(minHeight: 110, idealHeight: 130, maxHeight: 150)
            .overlay {
                if draft.steps.isEmpty {
                    ContentUnavailableView(tr("No Steps"), systemImage: "list.number", description: Text(tr("Add a step to get started.")))
                }
            }

            if let i = selectedIndex {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Label(draft.steps[i].tool.title, systemImage: draft.steps[i].tool.icon).font(.headline)
                    ToolSettingsView(tool: draft.steps[i].tool)
                        .environmentObject(scratch)
                        .id(draft.steps[i].id)
                }
            }

            Spacer(minLength: 0)
            Divider()
            HStack {
                Button(tr("Delete Preset…"), role: .destructive) { confirmDelete = true }
                    .confirmationDialog(tr("Delete this preset?"), isPresented: $confirmDelete) {
                        Button(tr("Delete “%@”", draft.name), role: .destructive) { m.deletePreset(draft.id); dismiss() }
                    } message: {
                        Text(tr("The preset is removed. Your files are not touched."))
                    }
                Spacer()
                Button(tr("Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("Save")) { m.updatePreset(draft); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.steps.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 700, idealWidth: 700, minHeight: 480, idealHeight: 520)
        .onChange(of: selection) { _, _ in
            if let i = selectedIndex { scratch.settings = draft.steps[i].settings }
        }
        .onChange(of: scratch.settings) { _, new in
            if let i = selectedIndex, draft.steps[i].settings != new { draft.steps[i].settings = new }
        }
    }

    private func add(_ tool: Tool) {
        let step = PresetStep(tool: tool, settings: m.settings)
        draft.steps.append(step)
        keepTextLast()
        selection = step.id
    }

    private func remove(_ id: PresetStep.ID) {
        draft.steps.removeAll { $0.id == id }
        if selection == id { selection = draft.steps.first?.id }
    }

    /// Recognize Text writes a text file, so nothing can follow it
    private func keepTextLast() {
        if let i = draft.steps.firstIndex(where: { $0.tool == .recognizeText }), i != draft.steps.count - 1 {
            draft.steps.append(draft.steps.remove(at: i))
        }
    }
}
