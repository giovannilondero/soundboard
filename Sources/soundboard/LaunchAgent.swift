import Foundation

enum LaunchAgent {
    static let label = "com.giovanni.soundboard"
    static var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var domain: String { "gui/\(getuid())" }

    static func install(binary: String) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binary, "run"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardOutPath": Config.dir.appendingPathComponent("launchagent.log").path,
            "StandardErrorPath": Config.dir.appendingPathComponent("launchagent.log").path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try? launchctl(["bootout", "\(domain)/\(label)"])
        try data.write(to: plistURL)
        try launchctl(["bootstrap", domain, plistURL.path])
    }

    static func uninstall() throws {
        _ = try? launchctl(["bootout", "\(domain)/\(label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static var isLoaded: Bool {
        (try? launchctl(["print", "\(domain)/\(label)"])) != nil
    }

    @discardableResult
    static func launchctl(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else { throw SoundboardError("launchctl \(args.joined(separator: " ")) failed: \(out)") }
        return out
    }
}
