import AppKit
import Foundation

/// The running soundboard: config, hotkeys, player, and menu bar item.
final class Daemon: NSObject, NSApplicationDelegate {
    private var config = Config()
    private let player = Player()
    private var watcher: ConfigWatcher?
    private var statusItem: NSStatusItem!
    private var volumeSlider: NSSlider!
    private var volumeLabel: NSTextField!
    private var hotkeyKeys: [UInt32: String] = [:]   // hotkey id → config key
    private let stopHotkeyID: UInt32 = 0xFFFF
    private var disabled = false
    private var errors: [String] = []
    private var volumeSaveWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        IPC.writePid()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = icon("speaker.wave.2")
        player.onPlayingChanged = { [weak self] _ in self?.updateIcon() }
        IPC.listen { [weak self] cmd, key in self?.handle(command: cmd, key: key) }
        reload()
        watcher = ConfigWatcher(url: Config.url) { [weak self] in
            Log.info("config.json changed, reloading")
            self?.reload()
        }
        Log.info("soundboard daemon started (pid \(ProcessInfo.processInfo.processIdentifier))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
        IPC.removePid()
    }

    // MARK: Reload

    func reload() {
        errors.removeAll()
        do {
            config = try Config.load()
        } catch {
            errors.append(error.localizedDescription)
            Log.error(error.localizedDescription)
            rebuildMenu()
            updateIcon()
            return
        }
        Log.fileURL = config.logFileURL

        let loadErrors = player.preload(config)
        for key in loadErrors.keys.sorted() { errors.append("[\(key)] \(loadErrors[key]!)") ; Log.error("sound '\(key)': \(loadErrors[key]!)") }

        registerHotkeys()

        if AudioDevices.find(named: config.outputDevice) == nil {
            errors.append("Output device \"\(config.outputDevice)\" not found")
        }
        rebuildMenu()
        updateIcon()
        Log.info("loaded \(config.sounds.count - loadErrors.count)/\(config.sounds.count) sounds")
    }

    private func registerHotkeys() {
        let hk = HotkeyManager.shared
        hk.unregisterAll()
        hotkeyKeys.removeAll()
        var nextID: UInt32 = 1
        for key in config.sortedKeys {
            guard let code = KeyCodes.code(for: key) else {
                errors.append("Unknown key name \"\(key)\" in config")
                continue
            }
            if hk.register(keyCode: code, id: nextID) {
                hotkeyKeys[nextID] = key
            } else {
                errors.append("Hotkey Hyper+\(KeyCodes.label(key)) refused by macOS (taken by another app?)")
            }
            nextID += 1
        }
        if let code = KeyCodes.code(for: config.stopKey) {
            if !hk.register(keyCode: code, id: stopHotkeyID) {
                errors.append("Stop hotkey Hyper+\(KeyCodes.label(config.stopKey)) refused by macOS")
            }
        } else {
            errors.append("Unknown stopKey \"\(config.stopKey)\"")
        }
        hk.handler = { [weak self] id in self?.hotkeyPressed(id) }
    }

    private func hotkeyPressed(_ id: UInt32) {
        if id == stopHotkeyID { stop(); return }
        guard !disabled, let key = hotkeyKeys[id] else { return }
        play(key)
    }

    // MARK: Actions

    func play(_ key: String) {
        guard let device = AudioDevices.find(named: config.outputDevice) else {
            setTransientError("Output device \"\(config.outputDevice)\" not found; sound not played")
            return
        }
        AudioDevices.prepare(device, volume: config.volume)
        do {
            try player.play(key: key, on: device)
            Log.info("play '\(key)' on \(device.name) @ \(Int(config.volume * 100))%")
        } catch {
            setTransientError("Play '\(key)' failed: \(error.localizedDescription)")
        }
    }

    func stop() { player.stop() }

    private func setTransientError(_ msg: String) {
        Log.error(msg)
        errors.removeAll { $0.hasPrefix("Output device") || $0.hasPrefix("Play ") }
        errors.insert(msg, at: 0)
        rebuildMenu()
        updateIcon()
    }

    private func handle(command: String, key: String?) {
        switch command {
        case "play": if let key { play(key.lowercased()) }
        case "stop": stop()
        case "reload": reload()
        case "quit": NSApp.terminate(nil)
        default: Log.error("unknown IPC command \(command)")
        }
    }

    // MARK: Menu

    private func icon(_ symbol: String) -> NSImage? {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Soundboard")
        img?.isTemplate = true
        return img
    }

    private func updateIcon() {
        let symbol: String
        if !errors.isEmpty { symbol = "exclamationmark.triangle" }
        else if disabled { symbol = "speaker.slash" }
        else if player.isPlaying { symbol = "speaker.wave.3" }
        else { symbol = "speaker.wave.2" }
        statusItem.button?.image = icon(symbol)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for e in errors {
            let item = NSMenuItem(title: "⚠︎ \(e)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if !errors.isEmpty { menu.addItem(.separator()) }

        // Volume slider
        let volItem = NSMenuItem()
        volItem.view = makeVolumeView()
        menu.addItem(volItem)
        menu.addItem(.separator())

        // Sounds
        if config.sounds.isEmpty {
            let item = NSMenuItem(title: "No sounds. Use: soundboard import <file> --key <k>", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for key in config.sortedKeys {
            let entry = config.sounds[key]!
            let item = NSMenuItem(title: "\(KeyCodes.label(key))\t\(entry.displayName(key: key))", action: #selector(menuPlay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let stopItem = NSMenuItem(title: "Stop", action: #selector(menuStop), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        let disableItem = NSMenuItem(title: "Disable hotkeys", action: #selector(menuToggleDisabled), keyEquivalent: "")
        disableItem.target = self
        disableItem.state = disabled ? .on : .off
        menu.addItem(disableItem)
        menu.addItem(.separator())

        for (title, sel) in [("Open config.json", #selector(menuOpenConfig)),
                             ("Open sounds folder", #selector(menuOpenSounds)),
                             ("Reload config", #selector(menuReload)),
                             ("Bazecor map (MAP.md)", #selector(menuMap))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Soundboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func makeVolumeView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        let title = NSTextField(labelWithString: "Speaker volume")
        title.font = .menuFont(ofSize: 13)
        title.frame = NSRect(x: 14, y: 24, width: 150, height: 17)
        view.addSubview(title)

        volumeLabel = NSTextField(labelWithString: "\(Int(config.volume * 100))%")
        volumeLabel.font = .menuFont(ofSize: 13)
        volumeLabel.alignment = .right
        volumeLabel.frame = NSRect(x: 176, y: 24, width: 50, height: 17)
        view.addSubview(volumeLabel)

        volumeSlider = NSSlider(value: Double(config.volume), minValue: 0, maxValue: 1, target: self, action: #selector(volumeChanged(_:)))
        volumeSlider.frame = NSRect(x: 14, y: 2, width: 212, height: 20)
        volumeSlider.isContinuous = true
        view.addSubview(volumeSlider)
        return view
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        config.volume = Float(sender.doubleValue)
        volumeLabel.stringValue = "\(Int(config.volume * 100))%"
        if let device = AudioDevices.find(named: config.outputDevice) {
            AudioDevices.prepare(device, volume: config.volume)
        }
        volumeSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do { try self.config.save() } catch { Log.error("cannot save volume: \(error.localizedDescription)") }
        }
        volumeSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    @objc private func menuPlay(_ sender: NSMenuItem) { if let key = sender.representedObject as? String { play(key) } }
    @objc private func menuStop() { stop() }
    @objc private func menuToggleDisabled() { disabled.toggle(); rebuildMenu(); updateIcon() }
    @objc private func menuOpenConfig() { NSWorkspace.shared.open(Config.url) }
    @objc private func menuOpenSounds() { NSWorkspace.shared.open(config.soundsDirURL) }
    @objc private func menuReload() { reload() }
    @objc private func menuMap() {
        do {
            try MapGenerator.write(config)
            NSWorkspace.shared.open(Config.mapURL)
        } catch { setTransientError("Cannot write MAP.md: \(error.localizedDescription)") }
    }

    // MARK: Entry point

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let daemon = Daemon()
        app.delegate = daemon
        signal(SIGTERM) { _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
        app.run()
        exit(0)
    }
}
