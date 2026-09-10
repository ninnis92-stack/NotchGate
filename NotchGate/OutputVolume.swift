import AppKit
import CoreAudio
import Foundation

@Observable
@MainActor
final class OutputVolume {
    static let shared = OutputVolume()

    var level: Double = 0.6
    var isMuted = false

    var symbol: String {
        if isMuted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var deviceID: AudioDeviceID = 0
    var onHardwareChange: (() -> Void)?

    private var started = false
    private var scrubbing = false
    private var timer: Timer?
    private var lastAnnouncedLevel: Double?
    private var lastAnnouncedMute: Bool?

    private let kAudioHardwareServiceDeviceProperty_VirtualMainVolume = AudioObjectPropertySelector(0x766D766C) // 'vmvl'

    func start() {
        guard !started else { return }
        started = true
        refreshDevice()
        listen()
        read()
        let timer = Timer(timeInterval: 0.35, repeats: true) { _ in
            Task { @MainActor in
                OutputVolume.shared.readFromHardware()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func setLevel(_ value: Double) {
        scrubbing = true
        let clamped = min(max(value, 0), 1)
        level = clamped
        if clamped > 0.001 { isMuted = false }
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.scrubbing = false
        }
    }

    func toggleMute() {
        isMuted.toggle()
        apply()
    }

    private func apply() {
        refreshDevice()
        writeMute(isMuted)
        if !isMuted {
            writeVolume(Float(level))
        }
        writeSystemVolumeScript()
    }

    private func refreshDevice() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        deviceID = status == noErr ? device : 0
    }

    func readFromHardware() {
        read()
    }

    private func read() {
        if scrubbing { return }
        refreshDevice()
        guard deviceID != 0 else { return }
        if let mute = readMute() {
            isMuted = mute
        }
        if let volume = readVolume() {
            level = Double(volume)
        }
        let changed = lastAnnouncedLevel.map { abs($0 - level) > 0.008 } ?? false
            || lastAnnouncedMute.map { $0 != isMuted } ?? false
        lastAnnouncedLevel = level
        lastAnnouncedMute = isMuted
        if changed {
            onHardwareChange?()
        }
    }

    private func readVolume() -> Float? {
        if let value = scalar(selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, element: kAudioObjectPropertyElementMain) {
            return value
        }
        var values: [Float] = []
        for channel: UInt32 in 1...8 {
            if let value = scalar(selector: kAudioDevicePropertyVolumeScalar, element: channel) {
                values.append(value)
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    private func writeVolume(_ value: Float) {
        if setScalar(selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, element: kAudioObjectPropertyElementMain, value: value) {
            return
        }
        if setScalar(selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain, value: value) {
            return
        }
        var wroteChannel = false
        for channel: UInt32 in 1...2 {
            if setScalar(selector: kAudioDevicePropertyVolumeScalar, element: channel, value: value) {
                wroteChannel = true
            }
        }
        if wroteChannel { return }
        for channel: UInt32 in 3...8 {
            setScalar(selector: kAudioDevicePropertyVolumeScalar, element: channel, value: value)
        }
    }

    private func writeSystemVolumeScript() {
        let percent = Int((min(max(level, 0), 1) * 100).rounded())
        let muted = isMuted || percent == 0 ? "true" : "false"
        var error: NSDictionary?
        NSAppleScript(source: "set volume output volume \(percent) output muted \(muted)")?
            .executeAndReturnError(&error)
    }

    private func readMute() -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return status == noErr ? muted != 0 : nil
    }

    private func writeMute(_ muted: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
    }

    private func scalar(selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    @discardableResult
    private func setScalar(selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement, value: Float) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var writable: DarwinBoolean = false
        AudioObjectIsPropertySettable(deviceID, &address, &writable)
        guard writable.boolValue else { return false }
        var next = value
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float>.size),
            &next
        )
        return status == noErr
    }

    private func listen() {
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            .main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.read()
            }
        }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &volumeAddress,
            .main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.read()
            }
        }
    }
}
