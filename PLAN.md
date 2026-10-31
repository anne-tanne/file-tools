# Plan: eight new features for File Tools

## 1. Goal and definition of done

Add to File Tools (see CLAUDE.md for architecture, conventions and gotchas, which every worker must read first):

1. **Run summary + results**: after each per-file run the bottom bar says e.g. "12 done, 1 skipped · 48 MB saved (−63 %)"; results can be dragged out of the list and previewed with Quick Look.
2. **Stitch Images**: new whole-list photo tool, puts photos together top-to-bottom or side by side into one image.
3. **Redact**: new tool for PDFs and photos, blacks out search terms (+ optional emails, IBANs, phone numbers) and really removes the text underneath.
4. **Extract Tables**: new tool for PDFs and photos, finds tables with Vision (macOS 26 `RecognizeDocumentsRequest`) and saves them as CSV.
5. **Video**: new file kind `.video` (mov, mp4, m4v). Compress accepts videos; new tool **Video to GIF**.
6. **Clean Up Scans**: new photo tool, finds the page in a photo of paper, straightens it, whitens it; saves JPG, PDF or searchable PDF.
7. **Watch Folders**: a folder + a preset; new files dropped into the folder are run through the preset automatically while the app is open.
8. **Smart Rename**: Rename gets a mode "From content": names like `261014-SwisscomInvoice.pdf` (yyMMdd-CamelCaseTitle), from Foundation Models when Apple Intelligence is on, otherwise from a heuristic.

Done = `./build.sh` succeeds with no errors, each engine passes its harness test, the Model harness runs each new tool, an off-screen screenshot of each new tool view looks right, and all new strings have German (Swiss: "ss", never "ß") and French entries in `L10n.swift`.

## 2. Decisions already made (don't revisit)

- **Location only** in Remove Info already keeps the date and drops GPS: nothing to do.
- **Reorder Pages** cannot delete or insert pages today. Not part of this plan.
- New `Tool` cases are **appended at the end** of the enum, so the ⌘1–⌘9 shortcuts don't move: `stitch = "Stitch Images", cleanScan = "Clean Up Scans", redact = "Redact", extractTables = "Extract Tables", videoToGIF = "Video to GIF"`.
- Sidebar: Convert & Compress gets Video to GIF; Photos gets Stitch Images and Clean Up Scans; PDF gets Redact and Extract Tables.
- Engines go into **new files** so they can be written in parallel: `VideoOps.swift`, `Redact.swift`, `Tables.swift`, `DocScan.swift`, `Stitch.swift`, `SmartName.swift`, `WatchFolders.swift`. Each new engine file defines its own small enums (Titled, Codable, Sendable, CaseIterable, Identifiable, raw value = English UI text) instead of putting them in Formats.swift.
- Async APIs (Vision's new Swift API, AVFoundation export, Foundation Models) are called through `waitFor { ... }` (already in Formats.swift). Engine code runs on a background thread.
- `OCR.recognize(_:)`, `OCR.hasText(_:)` and `OCR.layerPage(size:lines:content:)` are already internal (not private) so other engines can reuse them.
- Redact really removes text: a page with matches is rendered to an image at 300 dpi, black boxes are painted, and the page is replaced by that image (JPEG, decoded from JPEG data so it stays compact) with a new invisible OCR text layer read from the *redacted* image. Pages without matches are copied unchanged.
- Extract Tables writes UTF-8 CSV with a BOM and CRLF line ends (opens in Excel). Separator setting, default **semicolon** (Swiss/German/French Excel).
- Video compression uses `AVAssetExportSession` presets, output `.mp4`. Levels: High = `AVAssetExportPresetHEVC1920x1080`, Balanced = `AVAssetExportPreset1280x720`, Smallest = `AVAssetExportPreset960x540`. Target size: try `[HEVC1920x1080, 1280x720, 960x540, 640x480]` in order, stop at the first one ≤ target, keep the smallest. Same rules as photos: ≥ 5 % saving or `Skipped("Already small, original kept")`; `Skipped("Already under %@")` when the source is already under the target. Never `fileLengthLimit` (it cuts the video off).
- Video to GIF: only the first 60 seconds; width setting (320 / 480 / 640 px, never upscaled), frame rate setting (10 / 15 fps); loops forever.
- Clean Up Scans: `VNDetectDocumentSegmentationRequest`, falling back to `VNDetectRectanglesRequest`; `CIPerspectiveCorrection`; then colour mode: Colour = `CIDocumentEnhancer`, Greyscale = enhancer + saturation 0, Black & White = greyscale + `CIColorThresholdOtsu`. If no page is found, the whole photo is only enhanced and the message says so.
- Watch Folders: results go into a subfolder named `tr("Processed")` inside the watched folder (not recursive, so results don't trigger again). Files already in the folder when watching starts are ignored. Only works while the app is open (window closing still quits the app). Settings saved in UserDefaults `watchFolders`.
- Smart Rename name format: `yyMMdd-TitleInCamelCase` + original extension, e.g. `261014-SwisscomInvoice.pdf`. Title is 2–4 words in the **app interface language** (`L10n.lang`), no spaces, letters and digits only (umlauts allowed), at most 40 characters. Date = date the document was issued if found, else the photo date / file creation date (`Model.date(of:kind:)`). Duplicate names in one batch get `-2`, `-3`.
- Apple Intelligence is **off on the developer's Mac**. Smart Rename must work without it (heuristic) and use Foundation Models when `SystemLanguageModel.default.availability == .available`.

## 3. Steps

### Phase 1: engines (all parallel, new files only)

Shared constraints for every Phase 1 step:
- Create only the files named in the step (plus a harness in the scratch dir given in the brief). Do not edit any existing file in `Sources/`. If an existing file seems to need a change, stop and report it.
- Match the style of `PhotoOps.swift` / `PDFEdit.swift`: `enum Name { static func ... }`, short `///` doc comments, `tr("...")` around every user-visible string, `ConvError` for failures (red), `Skipped` for "nothing to do" (grey), `outputURL(for:suffix:ext:folder:)` for every output (never overwrite).
- No SwiftUI imports in engine files (except WatchFolders.swift, which holds a sheet view).
- Check: compile the new file with its dependencies and a `main.swift` harness using `swiftc -parse-as-library`, run it against generated test files, report what was produced.
- Report: files created, public signatures, every new English `tr()` string, what you tested and how, what you assumed.

#### 1a. VideoOps.swift (mid tier)
```swift
enum VideoOps {
    static let extensions: Set<String> = ["mov", "mp4", "m4v"]
    /// "name (compressed).mp4"
    static func compress(_ src: URL, level: Level, target: Int64?, folder: URL?, progress: (String) -> Void) throws -> URL
    /// "name.gif"; returns the frame count
    static func toGIF(_ src: URL, width: Int, fps: Int, folder: URL?, progress: (Int, Int) -> Void) throws -> (URL, frames: Int)
}
```
Details in section 2. GIF: `AVAssetImageGenerator` (`appliesPreferredTrackTransform = true`, zero tolerance, `maximumSize` from width), ImageIO GIF destination, `kCGImagePropertyGIFLoopCount = 0`, `kCGImagePropertyGIFDelayTime = 1/fps`. Progress: frame n of total. Throw `ConvError(tr("No video track"))` for files without video. Test: generate a 5 s 1920×1080 movie with `AVAssetWriter` in the harness, compress it at every level and with a 1 MB target, make a GIF; check sizes and that the GIF has the expected frame count.
Deps: Formats.swift (Level, outputURL, fileSize, fmtSize, waitFor), L10n.swift.

#### 1b. Redact.swift (mid tier)
```swift
enum Redact {
    /// "name (redacted).pdf" or same image format; matches = boxes painted, pages = pages changed (1 for photos)
    static func run(_ src: URL, kind: Kind, terms: [String], emails: Bool, ibans: Bool, phones: Bool, folder: URL?,
                    progress: (Int, Int) -> Void) throws -> (URL, matches: Int, pages: Int)
}
```
- Matching: terms are case- and diacritic-insensitive literals (empty ones ignored). Regexes (case-insensitive): email `[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}`; IBAN `\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]){11,30}\b`; phone `(?:\+|00)\d{1,3}[\s./-]?\(?\d{1,4}\)?(?:[\s./-]?\d{2,4}){2,4}` and Swiss national `\b0\d{2}[\s./-]?\d{3}[\s./-]?\d{2}[\s./-]?\d{2}\b`.
- PDF page with text (`OCR.hasText`): find ranges in `page.string`, `page.selection(for: NSRange)` → `selectionsByLine()` → `bounds(for: page)` (page space), pad by 1 pt. Render the page like `PDFOps.render(_:dpi:)` at 300 dpi but paint the boxes in the same context after `page.draw(with: .mediaBox, to:)`, with `page.transform(for: .mediaBox)` applied, so rotation is handled.
- PDF page without text (scan): render at 300 dpi, run your own `VNRecognizeTextRequest` (same settings as `OCR.recognize`), find matches in each `topCandidates(1).first!.string`, `boundingBox(for: Range)` → pixel boxes, paint them.
- Rebuild changed pages: JPEG-encode the redacted image (quality 0.85), decode it again (CGImageSource from that data, so the PDF keeps JPEG data), `OCR.recognize` the redacted image, `OCR.layerPage(size: page size in points incl. rotation, lines:)` drawing the image. Copy other pages with `page.copy()`. Keep `documentAttributes`.
- Photos: upright image (`ImageOps.upright`), OCR as above, paint boxes, write in the same format with `ImageOps.uprightMetadata` (see `PhotoOps.writeUpright`, which is private: write the equivalent).
- No matches → `Skipped(tr("No matches found"))`. Locked PDFs are refused by `PDFOps.open`.
- Test: create a text PDF with CoreText containing a name, an email, an IBAN (`CH93 0076 2011 6238 5295 7`) and a phone number; a 2-page PDF where only page 2 matches; an image of text (render the PDF page to PNG). After redaction, `PDFDocument.string` of the output must no longer contain any matched string, page 1 must be unchanged (still real text), and the output must stay reasonably small.
Deps: Formats, L10n, ImageOps, PDFOps, OCR.

#### 1c. Tables.swift (mid tier)
```swift
enum CSVSeparator: String, CaseIterable, Identifiable, Codable, Sendable, Titled { case semicolon = "Semicolon", comma = "Comma" }
enum Tables {
    /// One table → "name (table).csv"; several → folder "name (tables)" with "Page 3, table 1.csv" (photos: "Table 1.csv").
    /// Returns [file] or [folder] and the number of tables.
    static func extract(_ src: URL, kind: Kind, pages: [Int], separator: CSVSeparator, folder: URL?,
                        progress: (Int, Int) -> Void) throws -> (files: [URL], tables: Int)
}
```
- Vision Swift API: `RecognizeDocumentsRequest().perform(on: CGImage)` via `waitFor`; `observation.document.tables`; `table.rows: [[Cell]]`; text in the cell's content transcript. Read the SDK's `Vision.swiftmodule/arm64e-apple-macos.swiftinterface` for the exact names, and handle cells that span several columns/rows (put the text in the first column of the span, empty fields for the rest) so columns stay aligned.
- PDF pages rendered with `PDFOps.render(page, dpi: 300)`; photos via `ImageOps.upright`.
- CSV: UTF-8 with BOM, CRLF, quote fields containing the separator, a quote or a newline (double the quotes); trim cell whitespace, newlines inside a cell become spaces.
- No tables → `Skipped(tr("No tables found"))`.
- Test: draw a PDF with a 4×3 grid table with ruled lines plus a paragraph; draw a second one with two tables on two pages; check the CSV content.
Deps: Formats, L10n, ImageOps, PDFOps.

#### 1d. DocScan.swift and Stitch.swift (mid tier)
```swift
enum ScanColor: String, ... Titled { case color = "Colour", gray = "Greyscale", bw = "Black & White" }
enum ScanOutput: String, ... Titled { case jpg = "JPG", pdf = "PDF", searchable = "Searchable PDF" }
enum DocScan {
    /// "name (clean).jpg/.pdf"; foundPage = false when no page edges were found and only the colours were cleaned up
    static func clean(_ src: URL, color: ScanColor, output: ScanOutput, folder: URL?) throws -> (URL, foundPage: Bool)
}
enum StitchDirection: String, ... Titled { case vertical = "Top to bottom", horizontal = "Side by side" }
enum StitchFormat: String, ... Titled { case png = "PNG", jpg = "JPG" }
enum Stitch {
    /// Puts photos together in list order. Returns the pixel size.
    static func run(_ srcs: [URL], direction: StitchDirection, spacing: Int, format: StitchFormat, to out: URL,
                    progress: (Int) -> Void) throws -> (w: Int, h: Int)
}
```
- DocScan: see section 2. Keep confidence ≥ 0.5 for the detected quad; output long edge at most 4000 px. JPG: quality 0.9, keep metadata minus orientation (pixels are already upright). PDF: page width 595 pt, height by aspect, image drawn from JPEG data (passthrough). Searchable: write the cleaned JPG to a temp folder, call `OCR.makeSearchable(tmp, kind: .image, folder: tmpDir) { _, _ in }`, move the result to the final `outputURL(... suffix: tr("clean"), ext: "pdf")`; if that throws `Skipped` (no text) fall back to the plain PDF. Clean up temp files.
- Stitch: upright every photo; vertical scales all to the smallest width, horizontal to the smallest height (never upscale); `spacing` px gaps, white for JPG, transparent for PNG; if the long side would exceed 30 000 px, scale everything down to fit. Progress = photo n (1-based). JPG quality 0.9. Throw `ConvError` if fewer than 2 photos.
- Test DocScan: draw a white "paper" quad with text, rotated and in perspective, on a dark background (CGContext), save as JPG; check the result is upright, roughly paper-shaped and bright; try all outputs. Test Stitch with 3 photos of different sizes in both directions.
Deps: Formats, L10n, ImageOps, PDFOps, OCR.

#### 1e. SmartName.swift (mid tier; escalate the prompt wording to high tier only if results are bad)
```swift
enum SmartName {
    static var usesAppleIntelligence: Bool   // SystemLanguageModel.default.availability == .available
    /// File name stem without extension, e.g. "261014-SwisscomInvoice". `fallbackDate` = photo date or file creation date.
    static func suggest(_ url: URL, kind: Kind, fallbackDate: Date) throws -> String
}
```
- Text: PDF → `page.string` of the first 2 pages; if no page has text (`OCR.hasText`) OCR the first page rendered at 200 dpi. Photo → `OCR.recognize(ImageOps.upright(...))`. Word → `NSAttributedString(url:options:documentAttributes:)`.string. Use the first 1500 characters.
- If the text has fewer than 20 letters (e.g. a photo of a landscape): `VNClassifyImageRequest`, up to 3 labels with confidence > 0.3, as the content description.
- Foundation Models when available: `@Generable struct Guess { @Guide(...) var date: String /* YYYY-MM-DD or empty */; @Guide(...) var title: String /* 2–4 words: sender/subject and document type, in <interface language> */ }`, `LanguageModelSession(instructions:)`, `respond(to:generating:)` through `waitFor`. Validate the date (must parse, year 1990…next year); otherwise use the fallback date.
- Heuristic (no Apple Intelligence or model error): date = first date `NSDataDetector` finds in the text (year 1990…next year), else fallback; title = the first line with at least 2 words of ≥ 2 letters, first 4 words; for photos the labels (Vision label identifiers have underscores: make them words).
- Title → CamelCase: split on anything that isn't a letter or digit, capitalise the first letter of each word, keep the rest, join, max 40 characters. Empty title → CamelCase of the original stem.
- Test: a PDF with "Swisscom (Schweiz) AG … Rechnung … 14.10.2026", a photo of text, a photo without text (draw shapes), a .docx made with `NSAttributedString` → `.docx` writer. Print the names. Confirm it compiles and runs the heuristic path here (Apple Intelligence is off).
Deps: Formats, L10n, ImageOps, PDFOps, OCR.

#### 1f. WatchFolders.swift (mid tier)
```swift
struct WatchFolder: Codable, Identifiable, Equatable { var id = UUID(); var url: URL; var presetID: UUID; var enabled = true }
@MainActor final class FolderWatcher: ObservableObject {
    static let shared = FolderWatcher()
    @Published var folders: [WatchFolder]          // saved to UserDefaults "watchFolders" on change
    @Published var status: [WatchFolder.ID: String] // last activity per folder, e.g. "✓ Scan.pdf", "Error: …"
    func start()                                   // called once at launch; (re)starts sources for enabled folders
    func addFolder()                               // NSOpenPanel for a folder, first preset preselected
}
struct WatchFoldersSheet: View                     // table-like list + "Add Folder…" + "Done"
```
- Presets come from `Model.shared.presets` (Services.swift); a folder whose preset no longer exists shows "Preset was deleted" and is skipped.
- `DispatchSource.makeFileSystemObjectSource(fileDescriptor: open(path, O_EVTONLY), eventMask: .write)` per enabled folder; on event wait 1 s (debounce), list top-level non-hidden regular files, skip names starting with `~$` or `.`, extensions `download`, `crdownload`, `part`; process only files not in the folder's `known` set (filled with the folder's contents when watching starts). A file is ready when its size is the same in two checks 1 s apart.
- Kind: `Model.imageExtensions` → `.image`, `pdf` → `.pdf`, `WordOps.extensions` → `.word`; anything else is ignored (Phase 2 adds video). Skip files the preset doesn't accept (`preset.accepts(kind)`).
- Run on one serial background queue: `Steps.runPreset(preset, Job(id: UUID(), url:, kind:, pages: all pages), folder: <folder>/Processed, progress: { _ in })`; create the subfolder when needed; add every handled file to `known` whether it worked or not. Update `status` on the main actor.
- Sheet rows: folder name (path in `.help`), preset `Picker` (labelsHidden), `Toggle` enabled (labelsHidden, label "Watch"), status caption, remove button (`Label` + `.labelStyle(.iconOnly)`). Empty state `ContentUnavailableView("No Watched Folders", systemImage: "folder.badge.gearshape", ...)`. Caption: "Works while File Tools is open. Results go into a “Processed” folder inside the watched folder. Files already in the folder are left alone." Follow UI conventions in CLAUDE.md.
- Test: harness compiles all Sources except App.swift, creates a temp folder, adds a WatchFolder with the seeded "Share Safely" preset (strip info) via `FolderWatcher.shared`, copies a JPG in, spins the RunLoop ~6 s, checks `Processed/<name> (Share Safely).jpg` exists and that the pre-existing file was not processed.
Deps: everything except App.swift (read-only use).

### Phase 2: integration (after all of Phase 1; one worker, mid tier, sequential)

Files: Formats.swift, Model.swift, Settings.swift, Steps.swift, Views.swift, App.swift, Services.swift, L10n.swift, CLAUDE.md, build.sh (only if needed). Don't change engine logic from Phase 1; report problems instead.

1. **Kind.video**: add `case video` to `Kind`. Add `extension Kind { init?(url:) }` (or a static helper in Model) used by `Model.add`, `Steps.runPreset` (replace `current.pathExtension == "pdf" ? .pdf : .image`) and `FolderWatcher`. `Model.add` accepts `VideoOps.extensions`; `pickFiles` allows `.movie`; drop hint and row icon (`film`) handle video. Audit every `switch` on / comparison with `Kind`.
2. **Tool cases** (section 2 names, appended). Icons — verify each exists with `NSImage(systemSymbolName:accessibilityDescription:)` in the harness: stitch `rectangle.split.1x2`, cleanScan `doc.viewfinder`, redact `rectangle.inset.filled`, extractTables `tablecells`, videoToGIF `film.stack`. Subtitles: "Put photos together into one long or wide image", "Straighten and brighten photos of documents", "Black out names, numbers and other text for good", "Save the tables in PDFs and photos as CSV files", "Make an animated GIF from a video". Actions: "Stitch", "Clean Up", "Redact", "Extract", "Make GIF". `accepts`: stitch/cleanScan image; redact/extractTables image+pdf; videoToGIF video; compress image+pdf+video; rename all; **default becomes `k == .image || k == .pdf`**. `usesPages` adds extractTables. `chainable` adds cleanScan and redact.
3. **ToolSettings** (with `init(from:)` lines): `stitchDirection = .vertical`, `stitchSpacing = 0`, `stitchFormat = .png`, `stitchName = tr("Stitched")`, `scanColor = .color`, `scanOutput = .pdf`, `redactTerms = ""`, `redactEmails = false`, `redactIBANs = false`, `redactPhones = false`, `csvSeparator = .semicolon`, `gifWidth = 480`, `gifFPS = 10`, `renameMode: RenameMode = .numbered` (new enum in Formats.swift: `numbered = "Numbered", smart = "From content"`). `summary(for:)` for cleanScan (`scanColor.title + ", " + scanOutput.title`) and redact (terms count + enabled patterns).
4. **Steps.perform**: compress → `VideoOps.compress` for `.video` (no `compareWith`); cleanScan, redact (terms = `redactTerms` split on commas and newlines), extractTables, videoToGIF. Messages: e.g. "3 matches on 2 pages", "2 tables", "%d frames", "No page edges found, colours cleaned up".
5. **Stitch** in Model: whole-list like `makeContactSheet` (name + extension from format, `uniqueURL`), summary "Created “%@”: %d × %d px, %@".
6. **Smart Rename** in Model: `@Published var smartNames: [Item.ID: String]` (stems). `renamePreview()` in smart mode returns `smartNames[id] + "." + ext`, numbering duplicates `-2`, `-3`. Run in smart mode: if some items lack a suggestion, run `suggestNames()` (background, per-row status "Reading…", then "Suggested"), otherwise `rename()` as today. Clear an item's suggestion when the mode changes or the list is cleared; undo works as today. Action title: "Suggest Names (n)" / "Rename (n)".
7. **Run summary**: `Item.results: [URL]` (set from `Outcome.files` on success, cleared in `resetStatus`). At the end of `runEach`, set `summary`: "%d done" + ", %d skipped" + ", %d failed", then " · " + either "%@ saved (−%d %%)" when total output size < total input size of the succeeded files, or the total output size. Folders count by their contents' size. If all failed, `summaryFailed = true`.
8. **Views**:
   - Settings UI for the five tools and Rename's mode picker (smart mode hint: "Names like 261014-SwisscomInvoice.pdf, from the date and content of each file. Click Suggest Names first, check them, then Rename." plus, when `!SmartName.usesAppleIntelligence`, "Turn on Apple Intelligence in System Settings for better names.").
   - Redact UI: `TextField` for terms (prompt "Names or words, separated by commas"), Toggles "Email addresses", "IBANs", "Phone numbers"; hint "Matching text is covered and removed for good. Pages with matches become images with a new hidden text layer; other pages stay unchanged." `canRun` for redact needs a term or a toggle.
   - Rows: for an item with `results`, a small draggable icon (`doc.on.doc`, `.onDrag { NSItemProvider(contentsOf: it.results[0])! }`, `.help("Drag the result to another app or folder")`, accessible label); context menu "Quick Look Result" and "Show Result in Finder".
   - Quick Look: `.quickLookPreview($previewURL, in: m.lastOutputs)`; toolbar button `Label("Quick Look", systemImage: "eye")` with `.help("Preview the new files (⌘Y)")`, disabled when no outputs; menu item in ToolCommands with ⌘Y (needs a `@Published var quickLook: URL?` on Model so the menu can open it).
   - Watch Folders: `@Published var showWatchFolders = false` on Model; "Watch Folders…" item in the Tool menu and in the presets' context menu; sheet in ContentView. `AppDelegate.applicationDidFinishLaunching` calls `FolderWatcher.shared.start()`.
9. **L10n**: every new English `tr()` string and SwiftUI string literal from Phase 1 and 2 gets `(German Swiss, French)` (grep the new files and diffs).
10. **CLAUDE.md**: structure table rows for the new files, tools list, and new gotchas reported by Phase 1 workers.

Check: `./build.sh`; Model harness (all Sources except App.swift) runs each new tool on test files from Phase 1 and prints item statuses and summaries; off-screen screenshots (see CLAUDE.md "Testing without clicking") of each new tool view with files in the list, Rename in smart mode, and the Watch Folders sheet.

### Phase 3: review and install (coordinator)
Read the whole diff, build, run the harnesses, check screenshots, install per CLAUDE.md, run `pbs -update`.

## 4. Dependencies

- 1a–1f are independent: run in parallel.
- Phase 2 needs all of Phase 1.
- Phase 3 needs Phase 2.

## 5. Open questions

None blocking. Later, maybe: Reorder Pages with delete/insert; Watch Folders while the window is closed (keep running, Open at Login).
