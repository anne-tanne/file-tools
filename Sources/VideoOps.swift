import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Video: compress (export presets) and turn a clip into an animated GIF
enum VideoOps {
    static let extensions: Set<String> = ["mov", "mp4", "m4v"]

    /// Presets for a level
    private static func preset(_ level: Level) -> String {
        switch level {
        case .high: AVAssetExportPresetHEVC1920x1080
        case .balanced: AVAssetExportPreset1280x720
        case .small: AVAssetExportPreset960x540
        }
    }

    /// Tried in order for a target size
    private static let ladder = [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1280x720,
                                 AVAssetExportPreset960x540, AVAssetExportPreset640x480]

    private final class SessionBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ s: AVAssetExportSession) { session = s }
    }

    private final class GenBox: @unchecked Sendable {
        let gen: AVAssetImageGenerator
        init(_ g: AVAssetImageGenerator) { gen = g }
    }

    private static func hasVideo(_ asset: AVAsset) throws -> Bool {
        let tracks = try waitFor { try await asset.loadTracks(withMediaType: .video) }
        return !tracks.isEmpty
    }

    /// Exports `asset` with one preset to `dest` (.mp4)
    private static func export(_ asset: AVAsset, preset: String, to dest: URL) throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConvError(tr("Could not compress this video"))
        }
        session.shouldOptimizeForNetworkUse = true
        let box = SessionBox(session)
        try? FileManager.default.removeItem(at: dest)
        do {
            try waitFor { try await box.session.export(to: dest, as: .mp4) }
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw ConvError(tr("Could not compress this video"))
        }
    }

    /// "name (compressed).mp4"
    static func compress(_ src: URL, level: Level, target: Int64?, folder: URL?, progress: (String) -> Void) throws -> URL {
        let before = fileSize(src)
        if let target, before <= target { throw Skipped(tr("Already under %@", fmtSize(target))) }
        let asset = AVURLAsset(url: src)
        guard try hasVideo(asset) else { throw ConvError(tr("No video track")) }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("FileTools-video-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var best: URL?
        var bestSize = Int64.max
        let presets = target == nil ? [preset(level)] : ladder
        for (i, p) in presets.enumerated() {
            progress(tr("Compressing video (%d of %d)", i + 1, presets.count))
            let tmp = tmpDir.appendingPathComponent("\(i).mp4")
            do { try export(asset, preset: p, to: tmp) } catch {
                if target == nil || (i == presets.count - 1 && best == nil) { throw error }
                continue
            }
            let size = fileSize(tmp)
            if size < bestSize { best = tmp; bestSize = size }
            if let target, size <= target { break }
        }
        guard let best else { throw ConvError(tr("Could not compress this video")) }
        guard bestSize < Int64(Double(before) * 0.95) else { throw Skipped(tr("Already small, original kept")) }
        let out = outputURL(for: src, suffix: "compressed", ext: "mp4", folder: folder)
        try FileManager.default.moveItem(at: best, to: out)
        return out
    }

    /// "name.gif"; returns the frame count. Only the first 60 seconds are used.
    static func toGIF(_ src: URL, width: Int, fps: Int, folder: URL?, progress: (Int, Int) -> Void) throws -> (URL, frames: Int) {
        let asset = AVURLAsset(url: src)
        guard try hasVideo(asset) else { throw ConvError(tr("No video track")) }
        let duration = try waitFor { try await asset.load(.duration) }.seconds
        guard duration.isFinite, duration > 0 else { throw ConvError(tr("No video track")) }
        let fps = max(1, fps)
        let length = min(duration, 60)
        let total = max(1, Int((length * Double(fps)).rounded(.down)))

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.maximumSize = CGSize(width: width, height: 0)

        // Never upscale: apply the maximum size only if the video is wider
        if let track = try waitFor({ try await asset.loadTracks(withMediaType: .video) }).first {
            let (size, t) = try waitFor { try await track.load(.naturalSize, .preferredTransform) }
            let shown = size.applying(t)
            if abs(shown.width) <= CGFloat(width) { gen.maximumSize = .zero }
        }

        let out = outputURL(for: src, suffix: nil, ext: "gif", folder: folder)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, total, nil) else {
            throw ConvError(tr("Could not create the GIF"))
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)]] as CFDictionary

        let box = GenBox(gen)
        var count = 0
        for n in 0..<total {
            progress(n + 1, total)
            let time = CMTime(seconds: Double(n) / Double(fps), preferredTimescale: 600)
            guard let img = try? waitFor({ try await box.gen.image(at: time).image }) else { continue }
            CGImageDestinationAddImage(dest, img, frameProps)
            count += 1
        }
        guard count > 0, CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out)
            throw ConvError(tr("Could not create the GIF"))
        }
        return (out, count)
    }
}
