import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

enum AudioDeviceDirection {
    case input, output

    var scope: AudioObjectPropertyScope {
        self == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
    }

    var defaultSelector: AudioObjectPropertySelector {
        self == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
    }
}

enum AudioDeviceError: LocalizedError {
    case coreAudio(String, OSStatus)
    case unavailable

    var errorDescription: String? {
        switch self {
        case let .coreAudio(operation, status):
            return "\(operation)に失敗しました (Core Audio: \(status))。"
        case .unavailable:
            return "利用可能な音声デバイスがありません。"
        }
    }
}

@MainActor
final class AudioDeviceCatalog {
    private(set) var inputDevices: [AudioDevice] = []
    private(set) var outputDevices: [AudioDevice] = []
    private var observation: AudioDeviceObservation?
    private let system = AudioObjectID(kAudioObjectSystemObject)

    func refresh() throws {
        var address = propertyAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size))
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        if !ids.isEmpty {
            try ids.withUnsafeMutableBytes {
                try check(AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!))
            }
            ids = Array(ids.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size))
        }

        let inputs = try devices(ids, direction: .input)
        let outputs = try devices(ids, direction: .output)
        inputDevices = inputs
        outputDevices = outputs
    }

    /// ID 0 は「Default」を表す。起動時に解決することで、macOS の現在の設定を使用する。
    func resolve(_ id: AudioDeviceID, for direction: AudioDeviceDirection) throws -> AudioDeviceID {
        let resolved = id == kAudioObjectUnknown ? try defaultDevice(direction) : id
        guard resolved != kAudioObjectUnknown, try hasChannels(resolved, direction: direction) else {
            throw AudioDeviceError.unavailable
        }
        return resolved
    }

    func deviceUID(for id: AudioDeviceID) throws -> String {
        try stringProperty(kAudioDevicePropertyDeviceUID, of: id)
    }

    func startMonitoring(onChange: @escaping @MainActor @Sendable () -> Void) throws {
        stopMonitoring()
        observation = try AudioDeviceObservation(onChange: onChange)
    }

    func stopMonitoring() {
        observation = nil
    }

    private func devices(_ ids: [AudioDeviceID], direction: AudioDeviceDirection) throws -> [AudioDevice] {
        let actual = try ids.filter { try hasChannels($0, direction: direction) }
            .map { AudioDevice(id: $0, name: try deviceName($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let defaultID = try defaultDevice(direction)
        let defaultName = try defaultID == kAudioObjectUnknown ? "利用可能なデバイスなし" : deviceName(defaultID)
        return [AudioDevice(id: kAudioObjectUnknown, name: "Default (\(defaultName))")] + actual
    }

    private func defaultDevice(_ direction: AudioDeviceDirection) throws -> AudioDeviceID {
        var address = propertyAddress(direction.defaultSelector)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id))
        return id
    }

    private func deviceName(_ id: AudioDeviceID) throws -> String {
        try stringProperty(kAudioObjectPropertyName, of: id)
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) throws -> String {
        var address = propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value))
        // Core Audio の CFString プロパティは呼び出し側に所有権が渡される。
        guard let value else { throw AudioDeviceError.unavailable }
        return value.takeRetainedValue() as String
    }

    private func hasChannels(_ id: AudioDeviceID, direction: AudioDeviceDirection) throws -> Bool {
        var address = propertyAddress(kAudioDevicePropertyStreamConfiguration, scope: direction.scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size))
        guard size >= MemoryLayout<AudioBufferList>.size else { return false }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage))
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw AudioDeviceError.coreAudio("音声デバイスの取得", status) }
    }
}

/// 監視の登録と解除を対にして、画面が閉じられた場合にもリスナーを解放する。
private nonisolated final class AudioDeviceObservation {
    private let listener: AudioObjectPropertyListenerBlock
    private var addresses: [AudioObjectPropertyAddress] = []
    private let system = AudioObjectID(kAudioObjectSystemObject)

    init(onChange: @escaping @MainActor @Sendable () -> Void) throws {
        listener = { _, _ in Task { @MainActor in onChange() } }
        do {
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
                             kAudioHardwarePropertyDefaultOutputDevice] {
                var address = AudioObjectPropertyAddress(
                    mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                let status = AudioObjectAddPropertyListenerBlock(system, &address, .main, listener)
                guard status == noErr else { throw AudioDeviceError.coreAudio("音声デバイスの監視", status) }
                addresses.append(address)
            }
        } catch {
            removeListeners()
            throw error
        }
    }

    deinit {
        removeListeners()
    }

    private func removeListeners() {
        for var address in addresses {
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, listener)
        }
        addresses.removeAll()
    }
}
