import AudioToolbox
import CoreAudio
import Observation

/// Volumen de la salida de audio por defecto mediante CoreAudio. Lectura y
/// escritura sin permisos; sigue los cambios de dispositivo.
@MainActor
@Observable
final class AudioService: ServiceLifecycle {
    /// `nil` si no hay dispositivo de salida.
    private(set) var volume: AudioVolume?

    @ObservationIgnored private var device = AudioDeviceID(kAudioObjectUnknown)
    @ObservationIgnored private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?

    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard defaultDeviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.bindToDefaultDevice() }
        }
        AudioObjectAddPropertyListenerBlock(Self.system, &Self.defaultOutputAddress, .main, listener)
        defaultDeviceListener = listener
        bindToDefaultDevice()
    }

    func stop() {
        if let defaultDeviceListener {
            AudioObjectRemovePropertyListenerBlock(Self.system, &Self.defaultOutputAddress, .main, defaultDeviceListener)
        }
        defaultDeviceListener = nil
        unbindDevice()
        volume = nil
    }

    func setLevel(_ level: Double) {
        guard volume?.isAdjustable == true else { return }
        var value = Float32(min(max(level, 0), 1))
        let status = AudioObjectSetPropertyData(device, &Self.volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if status != noErr { Log.system.error("Fallo al ajustar el volumen: \(status)") }
        refresh()
    }

    func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(device, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        if status != noErr { Log.system.error("Fallo al silenciar: \(status)") }
        refresh()
    }

    private func bindToDefaultDevice() {
        unbindDevice()
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(Self.system, &Self.defaultOutputAddress, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else {
            volume = nil
            return
        }
        device = id
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        AudioObjectAddPropertyListenerBlock(id, &Self.volumeAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(id, &Self.muteAddress, .main, listener)
        deviceListener = listener
        refresh()
    }

    private func unbindDevice() {
        if let deviceListener, device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, deviceListener)
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, deviceListener)
        }
        deviceListener = nil
        device = AudioDeviceID(kAudioObjectUnknown)
    }

    private func refresh() {
        guard device != kAudioObjectUnknown else {
            volume = nil
            return
        }
        var level = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let hasLevel = AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &level) == noErr

        var settable = DarwinBoolean(false)
        let isSettable = hasLevel
            && AudioObjectIsPropertySettable(device, &Self.volumeAddress, &settable) == noErr
            && settable.boolValue

        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        let hasMute = AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &muted) == noErr

        volume = AudioVolume(level: Double(level), isMuted: hasMute && muted != 0, isAdjustable: isSettable)
    }
}
