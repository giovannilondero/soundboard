import Foundation

enum Doctor {
    static func run() -> Bool {
        var ok = true
        func pass(_ s: String) { print("  ✓ \(s)") }
        func fail(_ s: String) { print("  ✗ \(s)"); ok = false }
        func warn(_ s: String) { print("  ! \(s)") }

        print("Config")
        var config: Config?
        do {
            config = try Config.load()
            pass("config.json parsed (\(config!.sounds.count) sounds)")
        } catch { fail(error.localizedDescription) }

        print("Audio devices")
        let devices = AudioDevices.allOutputDevices()
        for d in devices { print("    - \(d.name)  [\(d.uid)]") }
        if let cfg = config {
            if let dev = AudioDevices.find(named: cfg.outputDevice) {
                pass("target device \"\(dev.name)\" present")
                if let v = AudioDevices.volume(of: dev.id) { print("    volume \(Int(v * 100))%, muted: \(AudioDevices.isMuted(dev.id).map { "\($0)" } ?? "n/a")") }
            } else {
                fail("target device \"\(cfg.outputDevice)\" NOT found")
            }
            if let def = AudioDevices.defaultOutput() {
                if def.name == cfg.outputDevice {
                    warn("system default output is also \"\(def.name)\" — connect headphones to test isolation")
                } else {
                    pass("system default output is \"\(def.name)\" (other apps go there, soundboard goes to \"\(cfg.outputDevice)\")")
                }
            }
        }

        if let cfg = config {
            print("Sounds")
            if !FileManager.default.fileExists(atPath: cfg.soundsDirURL.path) { fail("sounds folder missing: \(cfg.soundsDirURL.path)") }
            for key in cfg.sortedKeys {
                let e = cfg.sounds[key]!
                let url = cfg.soundURL(e)
                if KeyCodes.code(for: key) == nil { fail("[\(key)] unknown key name") }
                if FileManager.default.fileExists(atPath: url.path) {
                    do { _ = try Player.load(url); pass("[\(KeyCodes.label(key))] \(e.displayName(key: key)) → \(url.lastPathComponent)") }
                    catch { fail("[\(key)] \(url.lastPathComponent): \(error.localizedDescription)") }
                } else { fail("[\(key)] file missing: \(url.path)") }
            }
            if KeyCodes.code(for: cfg.stopKey) == nil { fail("stopKey \"\(cfg.stopKey)\" unknown") } else { pass("stop key Hyper+\(KeyCodes.label(cfg.stopKey))") }
        }

        print("Tools")
        if FileManager.default.isExecutableFile(atPath: Importer.ffmpeg) { pass("ffmpeg at \(Importer.ffmpeg)") } else { warn("ffmpeg not found (needed only by `import`)") }

        print("Daemon")
        if let pid = IPC.daemonPid() { pass("daemon running (pid \(pid))") } else { warn("daemon not running (start with `soundboard run` or `soundboard install`)") }
        if LaunchAgent.isInstalled { pass("LaunchAgent installed (\(LaunchAgent.isLoaded ? "loaded" : "not loaded"))") } else { warn("LaunchAgent not installed") }

        print(ok ? "\nAll good." : "\nProblems found.")
        return ok
    }
}
