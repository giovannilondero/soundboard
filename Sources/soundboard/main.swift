import AppKit
import Foundation

let usage = """
soundboard — keyboard soundboard that plays only through the MacBook speakers

USAGE
  soundboard run                      start the daemon (menu bar + hotkeys)
  soundboard play <key>               play a sound (via daemon, or directly if not running)
  soundboard stop                     stop playback
  soundboard reload                   reload config.json in the running daemon
  soundboard import <file> --key <k> [--name "Name"] [--max <sec>] [--fade <sec>] [--force]
                                      normalize a sound into the library and map it to Hyper+<k>
  soundboard map                      print the Bazecor key map and write MAP.md
  soundboard init                     create a default config.json
  soundboard install                  install + start the LaunchAgent (login autostart)
  soundboard uninstall                stop + remove the LaunchAgent
  soundboard doctor                   check devices, config, sounds
  soundboard devices                  list output devices
"""

func die(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write("error: \(msg)\n".data(using: .utf8)!)
    exit(code)
}

func option(_ name: String, in args: inout [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

func flag(_ name: String, in args: inout [String]) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func currentBinaryPath() -> String {
    let p = CommandLine.arguments[0]
    let url = URL(fileURLWithPath: p, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    return url.standardizedFileURL.resolvingSymlinksInPath().path
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print(usage); exit(0) }
args.removeFirst()

if let cfg = try? Config.load() { Log.fileURL = cfg.logFileURL }

switch command {
case "run":
    Daemon.run()

case "play":
    guard let key = args.first?.lowercased() else { die("usage: soundboard play <key>") }
    if IPC.daemonRunning {
        IPC.send("play", key: key)
    } else {
        let config = try Config.load()
        guard config.sounds[key] != nil else { die("no sound mapped to key \"\(key)\"") }
        guard let device = AudioDevices.find(named: config.outputDevice) else { die("output device \"\(config.outputDevice)\" not found") }
        let player = Player()
        let errs = player.preload(config)
        if let e = errs[key] { die(e) }
        AudioDevices.prepare(device, volume: config.volume)
        print("playing '\(key)' on \(device.name) @ \(Int(config.volume * 100))% (daemon not running, direct mode)")
        try player.playAndWait(key: key, on: device)
    }

case "stop":
    IPC.send("stop")

case "reload":
    if IPC.daemonRunning { IPC.send("reload"); print("reload sent") } else { print("daemon not running") }

case "quit":
    IPC.send("quit")

case "import":
    guard let file = args.first, !file.hasPrefix("--") else { die("usage: soundboard import <file> --key <k>") }
    args.removeFirst()
    guard let key = option("--key", in: &args) else { die("--key <k> is required") }
    var imp = Importer(source: URL(fileURLWithPath: (file as NSString).expandingTildeInPath), key: key)
    imp.name = option("--name", in: &args)
    imp.maxSeconds = option("--max", in: &args).flatMap(Double.init)
    imp.fadeSeconds = option("--fade", in: &args).flatMap(Double.init)
    imp.force = flag("--force", in: &args)
    if !args.isEmpty { die("unknown arguments: \(args.joined(separator: " "))") }
    let (config, entry) = try imp.run()
    print("imported → \(config.soundsDirURL.appendingPathComponent(entry.file).path)")
    print("Bazecor: key `\(KeyCodes.label(key))` → Hyper+\(KeyCodes.label(key)) → \(entry.displayName(key: key))")
    if IPC.daemonRunning { print("(daemon will pick it up automatically)") }

case "map":
    let config = try Config.load()
    let md = MapGenerator.markdown(config)
    print(md)
    try MapGenerator.write(config)
    print("written to \(Config.mapURL.path)")

case "init":
    if FileManager.default.fileExists(atPath: Config.url.path) { die("config already exists at \(Config.url.path)") }
    let cfg = Config()
    try cfg.save()
    try FileManager.default.createDirectory(at: cfg.soundsDirURL, withIntermediateDirectories: true)
    print("created \(Config.url.path)")

case "install":
    let bin = currentBinaryPath()
    try LaunchAgent.install(binary: bin)
    print("LaunchAgent installed and started: \(LaunchAgent.plistURL.path)\nbinary: \(bin)")

case "uninstall":
    try LaunchAgent.uninstall()
    print("LaunchAgent removed")

case "doctor":
    exit(Doctor.run() ? 0 : 1)

case "devices":
    let def = AudioDevices.defaultOutput()
    for d in AudioDevices.allOutputDevices() {
        print("\(d.id == def?.id ? "*" : " ") \(d.name)  [\(d.uid)]")
    }

case "-h", "--help", "help":
    print(usage)

default:
    die("unknown command \"\(command)\"\n\n\(usage)")
}
