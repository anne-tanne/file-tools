import Foundation

/// Every per-tool setting in one value: saved as JSON, and the unit presets will be made of.
/// Not in here: the PDF password (never stored), output folder, rename undo, found duplicates.
struct ToolSettings: Codable, Sendable, Equatable {
    var format: OutFormat = .jpg
    var quality: Double = 0.9
    var dpi: Int = 150
    var compressBy: CompressBy = .level
    var level: Level = .balanced
    var targetMB: Double = 2
    var resizeMode: ResizeMode = .longest
    var resizeValue: Int = 2000
    var rotation: Int = 90
    var stripMode: StripMode = .all
    var pageSize: PageSize = .a4
    var pageMargin: Bool = true
    var combinedName: String = tr("Combined")
    var splitMode: SplitMode = .extract
    var chunkSize: Int = 5
    var skipSmallImages: Bool = true
    var wordNaming: WordNaming = .keep
    var wordPrefix: String = ""
    var wordSuffix: String = ""
    var wordPattern: String = tr("Document ###")
    var wordStart: Int = 1
    var renamePattern: String = tr("Photo ###")
    var renameStart: Int = 1
    var cropAspect: CropAspect = .square
    var bgFill: BackgroundFill = .transparent
    var cropToSubject: Bool = false
    var markKind: MarkKind = .text
    var markText: String = "© " + NSFullUserName()
    var markLogo: URL? = nil
    var markPosition: MarkPosition = .bottomRight
    var markOpacity: Double = 0.5
    var markSize: Double = 0.25
    var iconFormats: IconFormats = .both
    var sheetColumns: Int = 4
    var sheetNames: Bool = true
    var sheetFormat: SheetFormat = .pdf
    var sheetName: String = tr("Contact Sheet")
    var duplicateMode: DuplicateMode = .similar
    var numberStyle: NumberStyle = .plain
    var numberPosition: NumberPosition = .bottomCenter
    var numberStart: Int = 1
    var numberSkipFirst: Bool = false
    var passwordMode: PasswordMode = .add
    var stitchDirection: StitchDirection = .vertical
    var stitchSpacing: Int = 0
    var stitchFormat: StitchFormat = .png
    var stitchName: String = tr("Stitched")
    var scanColor: ScanColor = .color
    var scanOutput: ScanOutput = .pdf
    var redactTerms: String = ""
    var redactEmails: Bool = false
    var redactIBANs: Bool = false
    var redactPhones: Bool = false
    var csvSeparator: CSVSeparator = .semicolon
    var gifWidth: Int = 480
    var gifFPS: Int = 10
    var renameMode: RenameMode = .numbered

    init() {}

    /// Missing or unreadable fields fall back to their defaults, so old saved settings survive new fields
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let x = try? c.decodeIfPresent(T.self, forKey: key) { value = x }
        }
        get(.format, &format)
        get(.quality, &quality)
        get(.dpi, &dpi)
        get(.compressBy, &compressBy)
        get(.level, &level)
        get(.targetMB, &targetMB)
        get(.resizeMode, &resizeMode)
        get(.resizeValue, &resizeValue)
        get(.rotation, &rotation)
        get(.stripMode, &stripMode)
        get(.pageSize, &pageSize)
        get(.pageMargin, &pageMargin)
        get(.combinedName, &combinedName)
        get(.splitMode, &splitMode)
        get(.chunkSize, &chunkSize)
        get(.skipSmallImages, &skipSmallImages)
        get(.wordNaming, &wordNaming)
        get(.wordPrefix, &wordPrefix)
        get(.wordSuffix, &wordSuffix)
        get(.wordPattern, &wordPattern)
        get(.wordStart, &wordStart)
        get(.renamePattern, &renamePattern)
        get(.renameStart, &renameStart)
        get(.cropAspect, &cropAspect)
        get(.bgFill, &bgFill)
        get(.cropToSubject, &cropToSubject)
        get(.markKind, &markKind)
        get(.markText, &markText)
        get(.markLogo, &markLogo)
        get(.markPosition, &markPosition)
        get(.markOpacity, &markOpacity)
        get(.markSize, &markSize)
        get(.iconFormats, &iconFormats)
        get(.sheetColumns, &sheetColumns)
        get(.sheetNames, &sheetNames)
        get(.sheetFormat, &sheetFormat)
        get(.sheetName, &sheetName)
        get(.duplicateMode, &duplicateMode)
        get(.numberStyle, &numberStyle)
        get(.numberPosition, &numberPosition)
        get(.numberStart, &numberStart)
        get(.numberSkipFirst, &numberSkipFirst)
        get(.passwordMode, &passwordMode)
        get(.stitchDirection, &stitchDirection)
        get(.stitchSpacing, &stitchSpacing)
        get(.stitchFormat, &stitchFormat)
        get(.stitchName, &stitchName)
        get(.scanColor, &scanColor)
        get(.scanOutput, &scanOutput)
        get(.redactTerms, &redactTerms)
        get(.redactEmails, &redactEmails)
        get(.redactIBANs, &redactIBANs)
        get(.redactPhones, &redactPhones)
        get(.csvSeparator, &csvSeparator)
        get(.gifWidth, &gifWidth)
        get(.gifFPS, &gifFPS)
        get(.renameMode, &renameMode)
    }
}

// MARK: - Presets

/// One step of a preset: a tool and the settings it runs with
struct PresetStep: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var tool: Tool
    var settings: ToolSettings

    /// Convert only handles photos in a recipe; PDFs pass over it
    func applies(to kind: Kind) -> Bool { tool.isChainable && tool.accepts(kind) && !(tool == .convert && kind == .pdf) }
}

/// A named recipe: steps run one after another on every file
struct Preset: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var name: String
    var steps: [PresetStep]

    /// A file kind is usable if any step applies to it
    func accepts(_ kind: Kind) -> Bool { steps.contains { $0.applies(to: kind) } }

    static func seeded() -> [Preset] {
        func step(_ tool: Tool, _ change: (inout ToolSettings) -> Void = { _ in }) -> PresetStep {
            var s = ToolSettings()
            change(&s)
            return PresetStep(tool: tool, settings: s)
        }
        return [
            Preset(name: tr("Web Upload"), steps: [
                step(.resize) { $0.resizeMode = .longest; $0.resizeValue = 1600 },
                step(.convert) { $0.format = .jpg; $0.quality = 0.85 },
                step(.compress) { $0.compressBy = .target; $0.targetMB = 0.5 },
            ]),
            Preset(name: tr("For Email"), steps: [step(.compress) { $0.compressBy = .level; $0.level = .small }]),
            Preset(name: tr("Share Safely"), steps: [step(.strip) { $0.stripMode = .all }]),
            Preset(name: tr("Searchable Scan"), steps: [
                step(.makeSearchable),
                step(.compress) { $0.compressBy = .level; $0.level = .balanced },
            ]),
        ]
    }

    static func load() -> [Preset]? {
        guard let d = UserDefaults.standard.data(forKey: "presets") else { return nil }
        return try? JSONDecoder().decode([Preset].self, from: d)
    }

    static func save(_ presets: [Preset]) {
        if let d = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(d, forKey: "presets") }
    }
}

extension Tool {
    /// Tools that can be a step of a preset: one output per file, no stored password, no whole-list work
    static let chainable: [Tool] = [.convert, .compress, .resize, .rotate, .strip, .crop, .removeBackground, .watermark,
                                    .blackWhite, .makeSearchable, .pageNumbers, .flatten, .wordToPDF, .recognizeText,
                                    .cleanScan, .redact]
    var isChainable: Bool { Self.chainable.contains(self) }
}

extension ToolSettings {
    /// Words to black out: `redactTerms` split on commas and line breaks
    var redactTermList: [String] {
        redactTerms.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// One line for the preset's step list
    func summary(for tool: Tool) -> String {
        switch tool {
        case .convert:
            return format.isLossy ? tr("%@, quality %d %%", format.rawValue, Int((quality * 100).rounded())) : format.rawValue
        case .compress:
            return compressBy == .level ? tr("Level: %@", level.title) : tr("Smaller than %@ MB", targetMB.formatted(.number.precision(.fractionLength(0...2))))
        case .resize:
            switch resizeMode {
            case .longest: return tr("Longest side %d px", resizeValue)
            case .width: return tr("Width %d px", resizeValue)
            case .height: return tr("Height %d px", resizeValue)
            case .percent: return tr("%d %% of the size", resizeValue)
            }
        case .rotate: return rotation == 180 ? tr("180°") : rotation == 90 ? tr("90° right") : tr("90° left")
        case .strip: return stripMode.title
        case .crop: return cropAspect.title
        case .removeBackground: return bgFill.title + (cropToSubject ? ", " + tr("crop to subject") : "")
        case .watermark: return markKind == .text ? "“\(markText)”" : (markLogo?.lastPathComponent ?? tr("No logo chosen"))
        case .blackWhite: return tr("Photos and PDFs")
        case .makeSearchable: return tr("Add a text layer to scans")
        case .pageNumbers: return numberStyle.title + ", " + numberPosition.title
        case .flatten: return tr("Burn in form fields and notes")
        case .wordToPDF: return tr("Word layout")
        case .recognizeText: return tr("Save the text as .txt")
        case .cleanScan: return scanColor.title + ", " + scanOutput.title
        case .redact:
            var parts: [String] = []
            let n = redactTermList.count
            if n > 0 { parts.append(n == 1 ? tr("1 word") : tr("%d words", n)) }
            if redactEmails { parts.append(tr("Email addresses")) }
            if redactIBANs { parts.append(tr("IBANs")) }
            if redactPhones { parts.append(tr("Phone numbers")) }
            return parts.isEmpty ? tr("Nothing to black out yet") : parts.joined(separator: ", ")
        default: return ""
        }
    }
}
