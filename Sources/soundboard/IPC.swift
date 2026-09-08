import Foundation

/// CLI → daemon messaging through DistributedNotificationCenter.
enum IPC {
    static let name = Notification.Name("com.giovanni.soundboard.command")

    static func send(_ command: String, key: String? = nil) {
        var info: [String: String] = ["command": command]
        if let key { info["key"] = key }
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
        // distnoted delivers asynchronously; give it a beat before the process exits.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    static func listen(_ handler: @escaping (String, String?) -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { n in
            guard let cmd = n.userInfo?["command"] as? String else { return }
            handler(cmd, n.userInfo?["key"] as? String)
        }
    }

    // MARK: Daemon liveness via pid file

    static func writePid() {
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(to: Config.pidURL, atomically: true, encoding: .utf8)
    }

    static func removePid() { try? FileManager.default.removeItem(at: Config.pidURL) }

    static func daemonPid() -> pid_t? {
        guard let s = try? String(contentsOf: Config.pidURL, encoding: .utf8), let pid = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return kill(pid, 0) == 0 ? pid : nil
    }

    static var daemonRunning: Bool { daemonPid() != nil }
}
