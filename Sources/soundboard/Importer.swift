import Foundation

/// Normalizes a sound with ffmpeg (two-pass loudnorm), trims silence, writes 48 kHz stereo WAV into the sounds folder,
/// and registers it in config.json.
struct Importer {
    var source: URL
    var key: String
    var name: String?
    var maxSeconds: Double?
    var fadeSeconds: Double?
    var force = false
    var targetLUFS: Double = -16
    var truePeak: Double = -1

    static let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? "ffmpeg"

    func run() throws -> (Config, SoundEntry) {
        var config = try Config.load()
        let key = self.key.lowercased()
        guard KeyCodes.code(for: key) != nil else { throw SoundboardError("unknown key name \"\(key)\"") }
        if let existing = config.sounds[key], !force {
            throw SoundboardError("key \"\(key)\" already maps to \(existing.file); use --force to replace")
        }
        guard FileManager.default.fileExists(atPath: source.path) else { throw SoundboardError("file not found: \(source.path)") }

        let base = slug(name ?? source.deletingPathExtension().lastPathComponent)
        let destDir = config.soundsDirURL
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = destDir.appendingPathComponent("\(base).wav")

        // Pass 1: measure
        let pre = preFilters()
        let measureOut = try ffmpeg(["-hide_banner", "-nostats", "-i", source.path, "-af",
                                     (pre + ["loudnorm=I=\(targetLUFS):TP=\(truePeak):LRA=11:print_format=json"]).joined(separator: ","),
                                     "-f", "null", "-"])
        let m = try parseLoudnorm(measureOut)

        // Pass 2: normalize with measured values, then fade/resample
        var filters = pre + ["loudnorm=I=\(targetLUFS):TP=\(truePeak):LRA=11" +
                             ":measured_I=\(m["input_i"]!):measured_TP=\(m["input_tp"]!):measured_LRA=\(m["input_lra"]!)" +
                             ":measured_thresh=\(m["input_thresh"]!):offset=\(m["target_offset"]!):linear=true"]
        if let fade = fadeSeconds, fade > 0 {
            filters.append("areverse,afade=t=in:st=0:d=\(fade),areverse")
        }
        filters.append("aresample=48000")
        _ = try ffmpeg(["-hide_banner", "-nostats", "-y", "-i", source.path, "-af", filters.joined(separator: ","),
                        "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", dest.path])

        let entry = SoundEntry(file: dest.lastPathComponent, name: name ?? prettify(base), gain: nil)
        config.sounds[key] = entry
        try config.save()
        return (config, entry)
    }

    private func preFilters() -> [String] {
        var f: [String] = []
        if let max = maxSeconds, max > 0 { f.append("atrim=0:\(max)") }
        // Trim leading and trailing silence (below -50 dB).
        f.append("silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05")
        f.append("areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1,areverse")
        return f
    }

    private func parseLoudnorm(_ output: String) throws -> [String: String] {
        guard let start = output.range(of: "{", options: .backwards), let end = output.range(of: "}", options: .backwards),
              start.lowerBound < end.lowerBound else { throw SoundboardError("cannot parse loudnorm output:\n\(output)") }
        let json = String(output[start.lowerBound...end.lowerBound])
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw SoundboardError("cannot parse loudnorm JSON:\n\(json)")
        }
        for k in ["input_i", "input_tp", "input_lra", "input_thresh", "target_offset"] where dict[k] == nil {
            throw SoundboardError("loudnorm output missing \(k)")
        }
        return dict
    }

    @discardableResult
    private func ffmpeg(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Importer.ffmpeg)
        p.arguments = args
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else { throw SoundboardError("ffmpeg failed (\(p.terminationStatus)):\n\(out)") }
        return out
    }

    private func slug(_ s: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        var out = ""
        for ch in s.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
            if allowed.contains(ch) { out.append(ch) } else if ch == " " { out.append("-") }
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "sound" : trimmed
    }

    private func prettify(_ slug: String) -> String {
        slug.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
