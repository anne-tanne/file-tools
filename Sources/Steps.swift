import Foundation
import PDFKit

/// Per-file tool work, shared by the tool runner (and later by presets). No UI.
enum Steps {
    static func perform(_ tool: Tool, _ s: ToolSettings, _ job: Job, folder: URL?, password: String = "",
                        progress: @escaping @Sendable (String) -> Void) throws -> Outcome {
        switch tool {
        case .convert:
            if job.kind == .image {
                let out = try ImageOps.convert(job.url, to: s.format, quality: s.quality, folder: folder)
                return Outcome(message: out.lastPathComponent, files: [out])
            }
            let outs = try PDFOps.toImages(job.url, pages: job.pages, to: s.format, quality: s.quality, dpi: s.dpi, folder: folder) {
                progress(tr("Page %d of %d…", $0, job.pages.count))
            }
            return Outcome(message: outs.count == 1 ? outs[0].lastPathComponent : tr("%d images", outs.count), files: outs)
        case .compress:
            let target: Int64? = s.compressBy == .target ? Int64(max(0.05, s.targetMB) * 1_000_000) : nil
            let before = fileSize(job.url)
            let out = job.kind == .video
                ? try VideoOps.compress(job.url, level: s.level, target: target, folder: folder, progress: progress)
                : try Compressor.run(job.url, kind: job.kind, level: s.level, target: target, folder: folder, progress: progress)
            let after = fileSize(out)
            var msg = "\(fmtSize(before)) → \(fmtSize(after)) (−\(Int((Double(before - after) / Double(before) * 100).rounded())) %)"
            if let target, after > target { msg += tr(", smallest possible") }
            return Outcome(message: msg, files: [out], compareWith: job.kind == .video ? nil : out)
        case .resize:
            let (out, w, h) = try ImageOps.resize(job.url, mode: s.resizeMode, value: s.resizeValue, folder: folder)
            return Outcome(message: "\(w)×\(h)", files: [out])
        case .rotate:
            let out = job.kind == .image
                ? try ImageOps.rotate(job.url, degrees: s.rotation, folder: folder)
                : try PDFOps.rotate(job.url, pages: job.pages, degrees: s.rotation, folder: folder)
            return Outcome(message: out.lastPathComponent, files: [out])
        case .strip:
            let out = job.kind == .image
                ? try ImageOps.strip(job.url, mode: s.stripMode, folder: folder)
                : try PDFOps.stripInfo(job.url, folder: folder)
            return Outcome(message: out.lastPathComponent, files: [out])
        case .split:
            let outs = try PDFOps.split(job.url, pages: job.pages, mode: s.splitMode, chunk: s.chunkSize, parts: job.parts, names: job.partNames, folder: folder)
            return Outcome(message: outs.count == 1 ? outs[0].lastPathComponent : tr("%d PDFs", outs.count), files: outs)
        case .reorder:
            let out = try PDFOps.reorder(job.url, order: job.pages, folder: folder)
            return Outcome(message: out.lastPathComponent, files: [out])
        case .extractImages:
            let (dir, n) = try PDFImages.extract(job.url, pages: job.pages, skipSmall: s.skipSmallImages, folder: folder) {
                progress("Page \($0) of \(job.pages.count)…")
            }
            return Outcome(message: "\(n) image\(n == 1 ? "" : "s") in “\(dir.lastPathComponent)”", files: [dir])
        case .wordToPDF:
            progress(tr("Word is creating the PDF…"))
            let out = try WordOps.toPDF(job.url, name: job.outName ?? job.url.deletingPathExtension().lastPathComponent, folder: folder)
            let pages = PDFDocument(url: out)?.pageCount ?? 0
            return Outcome(message: out.lastPathComponent + " · " + (pages == 1 ? tr("1 page") : tr("%d pages", pages)), files: [out])
        case .crop:
            let (out, w, h) = try PhotoOps.crop(job.url, aspect: s.cropAspect, folder: folder)
            return Outcome(message: "\(w)×\(h)", files: [out])
        case .removeBackground:
            let out = try PhotoOps.removeBackground(job.url, fill: s.bgFill, cropToSubject: s.cropToSubject, folder: folder)
            return Outcome(message: out.lastPathComponent, files: [out])
        case .watermark:
            let mark = Watermark(text: s.markText, logo: s.markKind == .logo ? s.markLogo : nil, position: s.markPosition,
                                 opacity: s.markOpacity, size: s.markSize)
            let out = try PDFEdit.watermark(job.url, kind: job.kind, mark: mark, folder: folder)
            return Outcome(message: out.lastPathComponent, files: [out])
        case .blackWhite:
            let out = job.kind == .image
                ? try PhotoOps.blackAndWhite(job.url, folder: folder)
                : try PDFEdit.grayscale(job.url, folder: folder)
            return Outcome(message: out.lastPathComponent, files: [out])
        case .iconSet:
            let outs = try PhotoOps.iconSet(job.url, formats: s.iconFormats, folder: folder)
            return Outcome(message: outs.count == 1 ? outs[0].lastPathComponent : tr("%d icons", outs.count), files: outs)
        case .recognizeText:
            let (out, words) = try OCR.text(job.url, kind: job.kind, folder: folder) {
                if $1 > 1 { progress(tr("Page %d of %d…", $0, $1)) }
            }
            return Outcome(message: out.lastPathComponent + " · " + tr("%d words", words), files: [out])
        case .makeSearchable:
            let (out, pages) = try OCR.makeSearchable(job.url, kind: job.kind, folder: folder) {
                if $1 > 1 { progress(tr("Page %d of %d…", $0, $1)) }
            }
            return Outcome(message: out.lastPathComponent + (job.kind == .pdf ? " · " + tr("%d pages recognised", pages) : ""), files: [out])
        case .pageNumbers:
            let out = try PDFEdit.pageNumbers(job.url, style: s.numberStyle, position: s.numberPosition, start: s.numberStart, skipFirst: s.numberSkipFirst, folder: folder)
            return Outcome(message: out.lastPathComponent, files: [out])
        case .password:
            let out = try PDFEdit.password(job.url, mode: s.passwordMode, password: password, folder: folder)
            return Outcome(message: out.lastPathComponent, files: [out])
        case .flatten:
            let out = try PDFEdit.flatten(job.url, folder: folder)
            return Outcome(message: out.lastPathComponent, files: [out])
        case .cleanScan:
            let (out, found) = try DocScan.clean(job.url, color: s.scanColor, output: s.scanOutput, folder: folder)
            return Outcome(message: out.lastPathComponent + (found ? "" : " · " + tr("No page edges found, colours cleaned up")), files: [out])
        case .redact:
            let (out, matches, pages) = try Redact.run(job.url, kind: job.kind, terms: s.redactTermList, emails: s.redactEmails,
                                                       ibans: s.redactIBANs, phones: s.redactPhones, folder: folder) {
                if $1 > 1 { progress(tr("Page %d of %d…", $0, $1)) }
            }
            var msg = matches == 1 ? tr("1 match") : tr("%d matches", matches)
            if job.kind == .pdf { msg += " " + (pages == 1 ? tr("on 1 page") : tr("on %d pages", pages)) }
            return Outcome(message: msg, files: [out])
        case .extractTables:
            let (outs, tables) = try Tables.extract(job.url, kind: job.kind, pages: job.pages, separator: s.csvSeparator, folder: folder) {
                if $1 > 1 { progress(tr("Page %d of %d…", $0, $1)) }
            }
            return Outcome(message: tables == 1 ? tr("1 table") : tr("%d tables", tables), files: outs)
        case .videoToGIF:
            let (out, frames) = try VideoOps.toGIF(job.url, width: s.gifWidth, fps: s.gifFPS, folder: folder) {
                progress(tr("Frame %d of %d…", $0, $1))
            }
            return Outcome(message: out.lastPathComponent + " · " + tr("%d frames", frames), files: [out])
        case .combine, .rename, .contactSheet, .duplicates, .stitch:
            throw ConvError("Not a per-file tool")   // handled by Model on the whole list
        }
    }

    /// Runs a preset's steps on one file in a temp folder and moves the final file next to the original (or into `folder`).
    /// Steps that don't apply to the current file are passed over; a `Skipped` step passes the file on unchanged.
    static func runPreset(_ p: Preset, _ job: Job, folder: URL?,
                          progress: @escaping @Sendable (String) -> Void) throws -> Outcome {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("FileTools-preset-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        var current = job.url
        var kind = job.kind
        var changed = false
        for (i, step) in p.steps.enumerated() {
            guard step.applies(to: kind) else { continue }
            progress(tr("Step %d of %d: %@", i + 1, p.steps.count, step.tool.title))
            let pages = kind == .pdf ? Array(0..<max(1, PDFDocument(url: current)?.pageCount ?? 1)) : [0]
            let stepJob = Job(id: job.id, url: current, kind: kind, pages: pages)
            do {
                let o = try perform(step.tool, step.settings, stepJob, folder: tmp, progress: progress)
                guard let out = o.files.first else { continue }
                current = out
                changed = true
            } catch is Skipped {
                continue
            }
            if step.tool == .recognizeText { break }   // the text file is the end of the recipe
            kind = Kind(url: current) ?? .image
        }
        guard changed else { throw Skipped(tr("Nothing to do for this file")) }
        let dest = uniqueURL(folder ?? job.url.deletingLastPathComponent(),
                             job.url.deletingPathExtension().lastPathComponent + " (\(p.name))", current.pathExtension)
        try fm.moveItem(at: current, to: dest)
        return Outcome(message: dest.lastPathComponent, files: [dest])
    }
}
