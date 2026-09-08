import CoreAudio
import AudioToolbox
import Foundation

struct OutputDevice {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

enum AudioDevices {
    private static func address(_ sel: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func getString(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = address(sel)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString? = nil
        let st = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard st == noErr, let v = value else { return nil }
        return v as String
    }

    static func allOutputDevices() -> [OutputDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var streamsAddr = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamsAddr, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return nil }
            guard let name = getString(id, kAudioObjectPropertyName),
                  let uid = getString(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return OutputDevice(id: id, name: name, uid: uid)
        }
    }

    static func find(named name: String) -> OutputDevice? {
        allOutputDevices().first { $0.name == name }
    }

    static func defaultOutput() -> OutputDevice? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        return allOutputDevices().first { $0.id == id }
    }

    // MARK: Volume / mute (device-level, independent from other devices)

    static func volume(of id: AudioDeviceID) -> Float? {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr else { return nil }
        return v
    }

    static func setVolume(_ id: AudioDeviceID, _ volume: Float) throws {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
        var v = Float32(max(0, min(1, volume)))
        let st = AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        if st != noErr { throw SoundboardError("cannot set volume on device \(id) (OSStatus \(st))") }
    }

    static func isMuted(_ id: AudioDeviceID) -> Bool? {
        var addr = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr else { return nil }
        return v != 0
    }

    static func setMuted(_ id: AudioDeviceID, _ muted: Bool) throws {
        var addr = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(id, &addr) else { return }
        var v: UInt32 = muted ? 1 : 0
        let st = AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        if st != noErr { throw SoundboardError("cannot set mute on device \(id) (OSStatus \(st))") }
    }

    /// Unmute and set volume, so a "full volume" play actually comes out.
    static func prepare(_ device: OutputDevice, volume: Float) {
        if isMuted(device.id) == true {
            do { try setMuted(device.id, false) } catch { Log.error(error.localizedDescription) }
        }
        if let cur = self.volume(of: device.id), abs(cur - volume) < 0.005 { return }
        do { try setVolume(device.id, volume) } catch { Log.error(error.localizedDescription) }
    }
}
