import AVFoundation
import Foundation

/// Plays preloaded PCM buffers on one specific output device, never the system default.
final class Player {
    /// Common format every sound is converted to at preload time.
    static let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var boundDeviceID: AudioDeviceID?
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var generation = 0
    private var configObserver: NSObjectProtocol?

    private(set) var isPlaying = false { didSet { if oldValue != isPlaying { onPlayingChanged?(isPlaying) } } }
    var onPlayingChanged: ((Bool) -> Void)?

    init() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] _ in
            Log.info("audio engine configuration changed; will rebuild on next play")
            self?.tearDownEngine()
        }
    }

    // MARK: Preload

    /// Loads and converts every sound. Returns per-key error messages for the ones that failed.
    func preload(_ config: Config) -> [String: String] {
        var errors: [String: String] = [:]
        var loaded: [String: AVAudioPCMBuffer] = [:]
        for (key, entry) in config.sounds {
            let url = config.soundURL(entry)
            do {
                let buf = try Player.load(url)
                if let gain = entry.gain, gain != 1 { Player.apply(gain: gain, to: buf) }
                loaded[key] = buf
            } catch {
                errors[key] = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        buffers = loaded
        return errors
    }

    static func load(_ url: URL) throws -> AVAudioPCMBuffer {
        guard FileManager.default.fileExists(atPath: url.path) else { throw SoundboardError("file not found") }
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SoundboardError("cannot allocate buffer")
        }
        try file.read(into: inBuf)

        if inFormat == format { return inBuf }

        guard let converter = AVAudioConverter(from: inFormat, to: format) else {
            throw SoundboardError("unsupported format \(inFormat)")
        }
        let ratio = format.sampleRate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outCapacity) else {
            throw SoundboardError("cannot allocate buffer")
        }
        var consumed = false
        var convError: NSError?
        let status = converter.convert(to: outBuf, error: &convError) { _, outStatus in
            if consumed { outStatus.pointee = .endOfStream; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return inBuf
        }
        if status == .error { throw convError ?? SoundboardError("conversion failed") }
        return outBuf
    }

    static func apply(gain: Float, to buf: AVAudioPCMBuffer) {
        guard let ch = buf.floatChannelData else { return }
        let n = Int(buf.frameLength)
        for c in 0..<Int(buf.format.channelCount) {
            for i in 0..<n { ch[c][i] *= gain }
        }
    }

    // MARK: Engine

    private func tearDownEngine() {
        node?.stop()
        engine?.stop()
        engine = nil
        node = nil
        boundDeviceID = nil
        isPlaying = false
    }

    private func ensureEngine(for device: OutputDevice) throws -> AVAudioPlayerNode {
        if let node, let engine, boundDeviceID == device.id, engine.outputNode.audioUnit != nil {
            return node
        }
        tearDownEngine()

        let engine = AVAudioEngine()
        guard let au = engine.outputNode.audioUnit else { throw SoundboardError("no output audio unit") }
        var devID = device.id
        let st = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                      &devID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard st == noErr else { throw SoundboardError("cannot bind engine to \(device.name) (OSStatus \(st))") }

        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: Player.format)
        engine.prepare()

        self.engine = engine
        self.node = node
        self.boundDeviceID = device.id
        return node
    }

    // MARK: Play / stop

    func play(key: String, on device: OutputDevice) throws {
        guard let buf = buffers[key] else { throw SoundboardError("no sound loaded for key '\(key)'") }
        let node = try ensureEngine(for: device)
        guard let engine else { return }

        node.stop()
        generation += 1
        let gen = generation
        node.scheduleBuffer(buf, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.isPlaying = false
            }
        }
        if !engine.isRunning { try engine.start() }
        node.play()
        isPlaying = true
    }

    func stop() {
        generation += 1
        node?.stop()
        isPlaying = false
    }

    /// One-shot blocking play, used by the CLI when the daemon is not running.
    func playAndWait(key: String, on device: OutputDevice) throws {
        var done = false
        onPlayingChanged = { playing in if !playing { done = true } }
        try play(key: key, on: device)
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        // Give the hardware a moment to flush the tail.
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }
}
