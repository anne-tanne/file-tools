# Image Converter

Small native macOS app (SwiftUI, no Xcode project) for converting, compressing and editing photos and PDFs.
Installed as `~/Applications/Image Converter.app`. Interface language: English.

## Build & install

```bash
./build.sh                       # compiles Sources/*.swift into "Image Converter.app" in this folder
pkill ImageConverter; rm -rf ~/Applications/"Image Converter.app"; mv "Image Converter.app" ~/Applications/ && open ~/Applications/"Image Converter.app"
```

`build.sh` runs `swiftc -O -parse-as-library Sources/*.swift`, writes Info.plist, copies `AppIcon.icns`, ad-hoc signs.
`icon.swift` is a standalone script that draws `icon_1024.png` (used to make `AppIcon.icns` via iconutil); it is not part of the app build.

## Structure

| File | Contents |
|---|---|
| `Sources/App.swift` | Entry point |
| `Sources/Formats.swift` | Enums (OutFormat, Level + target-size ladders, ResizeMode, StripMode, PageSize, SplitMode), file naming helpers, page range parsing |
| `Sources/ImageOps.swift` | ImageIO: convert, compress, resize, rotate, strip metadata, image prep for PDFs |
| `Sources/PDFOps.swift` | PDFKit/Quartz: pages to images, compress (custom QuartzFilter), split, rotate, strip info, combine |
| `Sources/Compressor.swift` | Level or target-size compression, keeps the smallest result |
| `Sources/Model.swift` | `Tool` enum, `Item`, `Model` (state, per-tool settings, background runner, combine, rename + undo) |
| `Sources/Views.swift` | Sidebar + tool view, file list, settings per tool, bottom bar |
| `Sources/Sheets.swift` | Page picker, before/after compare view |

Engine files (Formats, ImageOps, PDFOps, Compressor) don't import SwiftUI and can be compiled into a test harness on their own.

## Tools

Convert (JPG/PNG/HEIC/AVIF/TIFF, PDF pages → images), Compress (level or target size, compare view), Resize,
Rotate, Remove Info, Rename (in place, with undo), Combine to PDF, Split PDF.

## Behaviour rules

- Never overwrite: outputs are new files like `name (compressed).jpg`, `uniqueURL` adds ` (1)` etc. Only Rename changes files in place; it refuses if a target name exists and moves via temp names so swaps work.
- Keep photo metadata (EXIF, GPS, orientation) unless the tool is about removing it.
- Compression keeps a result only if it saves ≥ 5 %; otherwise reports "Already small, original kept" (`Skipped` error = neutral grey status, `ConvError` = red).

## Gotchas (learned the hard way)

- macOS can read WebP but not write it; AVIF is offered instead.
- `kCGImageDestinationImageMaxPixelSize` drops GPS and date: scale via `CGImageSourceCreateThumbnailAtIndex` and write `metadata(s)` yourself (`ImageOps.reencode`).
- AVIF doesn't keep the orientation tag: bake rotation into pixels before writing AVIF.
- Lossless metadata stripping: `CGImageDestinationCopyImageSource` with `kCGImageDestinationMetadata` + `MergeMetadata: false`. `kCGImageDestinationOrientation` can't be combined with metadata, so put orientation into the metadata. Without explicit metadata, *all* metadata incl. orientation is dropped.
- PDF compression: write with option `"QuartzFilter"` and a generated `.qfilter` (keys like the system "Reduce File Size" filter, `ImageResolution` = dpi). Text and vectors stay intact.
- Images drawn into a PDF context stay compact only if the CGImage comes from JPEG data (passthrough); decoded images get stored raw.
- In Views, the file list has `layoutPriority(1)`. Don't put `fixedSize`/`minHeight` frames on the settings block: AppKit-backed controls report bad ideal heights and the layout overflows.

## Testing without clicking

- Engine: compile `Sources/{Formats,ImageOps,PDFOps,Compressor}.swift` plus a `main.swift` harness with `swiftc` and run it against test files.
- Model/UI: compile all Sources except `App.swift` with a harness that creates `Model()`, adds files, sets `m.tool`, calls `m.run()` and spins the RunLoop until `!m.busy`.
- Screenshots: host `ContentView(model:)` in an off-screen `NSWindow` and use `cacheDisplay(in:to:)` (`screencapture` has no permission here). The sidebar renders blank this way because of vibrancy.
