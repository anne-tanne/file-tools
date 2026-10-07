# File Tools

Small native macOS app (SwiftUI, no Xcode project) for converting, compressing and editing photos and PDFs.
Installed as `~/Applications/File Tools.app`. Interface language: English.

## Build & install

```bash
./build.sh                       # compiles Sources/*.swift into "File Tools.app" in this folder
pkill FileTools; rm -rf ~/Applications/"File Tools.app"; mv "File Tools.app" ~/Applications/ && open ~/Applications/"File Tools.app"
```

`build.sh` runs `swiftc -O -parse-as-library Sources/*.swift`, writes Info.plist, compiles the icon with `xcrun actool`, ad-hoc signs.
Icon: `AppIcon.icon` is a layered Liquid Glass icon (Icon Composer format: `icon.json` with gradient fill + glass/shadow/translucency per group, layer PNGs in `Assets/`). `icon_layers.swift` redraws those PNGs (canvas = whole icon shape, no background, no shadows). `actool` turns it into `Assets.car` (needs Xcode; `CFBundleIconName` = AppIcon). `icon.swift` / `AppIcon.icns` are the old flat icon, used only as fallback when actool is missing. To check the result, render `NSWorkspace.shared.icon(forFile:)` with an absolute path.

## Structure

| File | Contents |
|---|---|
| `Sources/App.swift` | Entry point |
| `Sources/Formats.swift` | Enums (OutFormat, Level + target-size ladders, ResizeMode, StripMode, PageSize, SplitMode), file naming helpers, page range parsing |
| `Sources/ImageOps.swift` | ImageIO: convert, compress, resize, rotate, strip metadata, image prep for PDFs |
| `Sources/PDFOps.swift` | PDFKit/Quartz: pages to images, compress (custom QuartzFilter), split, rotate, strip info, combine |
| `Sources/PDFImages.swift` | Extract embedded pictures from a PDF (CGPDF XObject walk; JPEG/JPX copied as-is, others decoded to PNG) |
| `Sources/Compressor.swift` | Level or target-size compression, keeps the smallest result |
| `Sources/Model.swift` | `Tool` enum, `Item`, `Model` (state, per-tool settings, background runner, combine, rename + undo) |
| `Sources/Views.swift` | Sidebar + tool view, file list, settings per tool, bottom bar |
| `Sources/Sheets.swift` | Page picker, parts picker (Split: pages into one or more PDFs), before/after compare view |
| `Sources/Arranger.swift` | Page arranger (drag thumbnails to reorder PDF pages) |

Engine files (Formats, ImageOps, PDFOps, PDFImages, Compressor) don't import SwiftUI and can be compiled into a test harness on their own.

## Tools

Convert (JPG/PNG/HEIC/AVIF/TIFF, PDF pages → images), Compress (level or target size, compare view), Resize,
Rotate, Remove Info, Rename (in place, with undo), Combine to PDF, Split PDF, Reorder Pages, Extract Images.

## Behaviour rules

- Never overwrite: outputs are new files like `name (compressed).jpg`, `uniqueURL` adds ` (1)` etc. Only Rename changes files in place; it refuses if a target name exists and moves via temp names so swaps work.
- Keep photo metadata (EXIF, GPS, orientation) unless the tool is about removing it.
- Compression keeps a result only if it saves ≥ 5 %; otherwise reports "Already small, original kept" (`Skipped` error = neutral grey status, `ConvError` = red).

## UI conventions (macOS 26 HIG)

- Targets macOS 26 only (`LSMinimumSystemVersion` 26.0); Liquid Glass sidebar/toolbar come from the system, so no custom backgrounds on bars or controls.
- Tool name and subtitle go in the toolbar (`navigationTitle`/`navigationSubtitle`), not as a header in the content.
- List actions (Add, Sort, Clear, Show in Finder) are toolbar buttons with SF Symbols and `.help`; the run button is bottom right, `.borderedProminent`, `.large`, default action.
- Every action also has a menu bar item (`ToolCommands` in App.swift, via `focusedSceneObject`): ⌘O add, ⇧⌘R Show in Finder, ⌘1 to ⌘9 tools, ⌘↩ run.
- Empty states use `ContentUnavailableView`. Rounded shapes use `style: .continuous`; fills use `.fill.quinary` / `.separator`, not hard-coded colours.
- Every control has a real label (use `.labelsHidden()` to hide it), icon-only buttons use `Label` + `.labelStyle(.iconOnly)`, so VoiceOver reads them.

## Gotchas (learned the hard way)

- macOS can read WebP but not write it; AVIF is offered instead.
- `kCGImageDestinationImageMaxPixelSize` drops GPS and date: scale via `CGImageSourceCreateThumbnailAtIndex` and write `metadata(s)` yourself (`ImageOps.reencode`).
- AVIF doesn't keep the orientation tag: bake rotation into pixels before writing AVIF.
- Lossless metadata stripping: `CGImageDestinationCopyImageSource` with `kCGImageDestinationMetadata` + `MergeMetadata: false`. `kCGImageDestinationOrientation` can't be combined with metadata, so put orientation into the metadata. Without explicit metadata, *all* metadata incl. orientation is dropped.
- PDF compression: write with option `"QuartzFilter"` and a generated `.qfilter` (keys like the system "Reduce File Size" filter, `ImageResolution` = dpi). Text and vectors stay intact.
- Images drawn into a PDF context stay compact only if the CGImage comes from JPEG data (passthrough); decoded images get stored raw.
- Page overviews (picker, parts picker, arranger) are shown inline below the file list for the clicked PDF (`Model.pageItem`), not as sheets; they report every change right away. They're keyed with `.id(item + tool)` so their local state resets per PDF.
- In Views, the file list has `layoutPriority(1)` (the page overview gets it instead when shown). Don't put `fixedSize`/`minHeight` frames on the settings block: AppKit-backed controls report bad ideal heights and the layout overflows.

## Testing without clicking

- Engine: compile `Sources/{Formats,ImageOps,PDFOps,Compressor}.swift` plus a `main.swift` harness with `swiftc` and run it against test files.
- Model/UI: compile all Sources except `App.swift` with a harness that creates `Model()`, adds files, sets `m.tool`, calls `m.run()` and spins the RunLoop until `!m.busy`.
- Screenshots: host `ContentView(model:)` in an off-screen `NSWindow` and use `cacheDisplay(in:to:)` (`screencapture` has no permission here). The sidebar renders blank this way because of vibrancy.
