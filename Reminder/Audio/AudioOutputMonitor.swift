import AudioToolbox
import CoreAudio
import Observation

/// 今の音声出力先がミュート (または音量 0) かを監視する。
/// OS からの変更通知でだけ読み直し、定期的には見に行かない
@MainActor
@Observable
final class AudioOutputMonitor {
    enum Status: Equatable {
        case audible
        case muted
        case volumeZero
        /// 出力先によってはミュートも音量も取れない
        case unknown

        /// 通知の音が聞こえない状態か
        var isSilent: Bool { self == .muted || self == .volumeZero }
    }

    private(set) var status: Status = .unknown

    @ObservationIgnored private var device = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        // 出力先の切り替え (イヤホンの接続など) を監視する
        AudioObjectAddPropertyListenerBlock(Self.systemObject, &Self.defaultOutputAddress, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.switchToDefaultDevice() }
        }
        switchToDefaultDevice()
    }

    /// ミュートを外す。音量は変えない
    func unmute() {
        guard status == .muted else { return }
        var value: UInt32 = 0
        AudioObjectSetPropertyData(device, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        updateStatus()
    }

    private func switchToDefaultDevice() {
        if let deviceListener {
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, deviceListener)
            AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, deviceListener)
        }

        var newDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(Self.systemObject, &Self.defaultOutputAddress, 0, nil, &size, &newDevice)
        device = newDevice

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateStatus() }
        }
        AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(device, &Self.volumeAddress, .main, listener)
        deviceListener = listener

        updateStatus()
    }

    private func updateStatus() {
        let isMuted: UInt32? = read(&Self.muteAddress)
        let volume: Float32? = read(&Self.volumeAddress)

        status = if isMuted.map({ $0 != 0 }) == true {
            .muted
        } else if let volume, volume <= 0.001 {
            .volumeZero
        } else if isMuted == nil, volume == nil {
            .unknown
        } else {
            .audible
        }
    }

    private func read<Value>(_ address: inout AudioObjectPropertyAddress) -> Value? {
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<Value>.size)
        let pointer = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }
}
