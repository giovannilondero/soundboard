import Foundation

struct SoundEntry: Codable, Equatable {
    var file: String
    var name: String?
    var gain: Float?

    func displayName(key: String) -> String {
        name ?? (file as NSString).deletingPathExtension
    }
}

struct Config: Codable {
    var outputDevice: String = "MacBook Pro Speakers"
    var volume: Float = 1.0
    var stopKey: String = "escape"
    var soundsDir: String = "~/Soundboard/sounds"
    var logFile: String? = "~/Soundboard/soundboard.log"
    var sounds: [String: SoundEntry] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outputDevice = try c.decodeIfPresent(String.self, forKey: .outputDevice) ?? outputDevice
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? volume
        stopKey = try c.decodeIfPresent(String.self, forKey: .stopKey) ?? stopKey
        soundsDir = try c.decodeIfPresent(String.self, forKey: .soundsDir) ?? soundsDir
        logFile = try c.decodeIfPresent(String.self, forKey: .logFile) ?? logFile
        sounds = try c.decodeIfPresent([String: SoundEntry].self, forKey: .sounds) ?? [:]
        // Normalize keys to lowercase so "A" and "a" are the same hotkey.
        sounds = Dictionary(uniqueKeysWithValues: sounds.map { ($0.key.lowercased(), $0.value) })
    }

    // MARK: Paths

    static let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Soundboard")
    static let url = dir.appendingPathComponent("config.json")
    static let mapURL = dir.appendingPathComponent("MAP.md")
    static let pidURL = dir.appendingPathComponent(".pid")

    static func expand(_ p: String) -> URL {
        URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
    }

    var soundsDirURL: URL { Config.expand(soundsDir) }
    var logFileURL: URL? { logFile.map(Config.expand) }

    func soundURL(_ e: SoundEntry) -> URL {
        e.file.hasPrefix("/") || e.file.hasPrefix("~")
            ? Config.expand(e.file)
            : soundsDirURL.appendingPathComponent(e.file)
    }

    // MARK: Load / save

    static func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SoundboardError("config not found at \(url.path) (run `soundboard init`)")
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            throw SoundboardError("config.json is invalid: \(error.localizedDescription)")
        }
    }

    func save() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true)
        try enc.encode(self).write(to: Config.url, options: .atomic)
    }

    /// Keys in display order: digits, letters, then everything else.
    var sortedKeys: [String] {
        func rank(_ k: String) -> (Int, String) {
            if k.count == 1, let ch = k.first {
                if ch.isNumber { return (0, k) }
                if ch.isLetter { return (1, k) }
                return (2, k)
            }
            return (3, k)
        }
        return sounds.keys.sorted { rank($0) < rank($1) }
    }
}
