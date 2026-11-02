import AVFoundation
import Observation
import CoreAudio
import OSLog

@MainActor
@Observable
final class AudioRoutingModel {
    private(set) var inputDevices: [AudioDevice] = []
    private(set) var outputDevices: [AudioDevice] = []
    private(set) var isRunning = false

    var selectedInputDevice: AudioDeviceID = kAudioObjectUnknown {
        didSet { if oldValue != selectedInputDevice { selectionChanged() } }
    }
    var selectedOutputDevice: AudioDeviceID = kAudioObjectUnknown {
        didSet { if oldValue != selectedOutputDevice { selectionChanged() } }
    }

    var selectedInputName: String { inputDevices.first { $0.id == selectedInputDevice }?.name ?? "" }
    var selectedOutputName: String { outputDevices.first { $0.id == selectedOutputDevice }?.name ?? "" }

    private let catalog = AudioDeviceCatalog()
    private let passthrough = AudioPassthrough()
    private let logger = Logger(subsystem: "cyffon.macos-audio-penetrator", category: "AudioRouting")
    @ObservationIgnored private var routingTask: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var isRefreshing = false

    init() {
        refreshDevices()
        do {
            try catalog.startMonitoring { [weak self] in self?.refreshDevices() }
        } catch {
            report(error.localizedDescription)
        }
    }

    func toggle() {
        isRunning.toggle()
        updateRouting()
    }

    func stop() {
        isRunning = false
        updateRouting()
    }

    private func selectionChanged() {
        if isRunning && !isRefreshing { updateRouting() }
    }

    private func refreshDevices() {
        do {
            try catalog.refresh()
            isRefreshing = true
            inputDevices = catalog.inputDevices
            outputDevices = catalog.outputDevices
            // 接続解除されたデバイスを選択したままにせず、現在のDefaultに戻す。
            if !inputDevices.contains(where: { $0.id == selectedInputDevice }) {
                selectedInputDevice = kAudioObjectUnknown
            }
            if !outputDevices.contains(where: { $0.id == selectedOutputDevice }) {
                selectedOutputDevice = kAudioObjectUnknown
            }
            isRefreshing = false
            if isRunning { updateRouting() }
        } catch {
            stop()
            report(error.localizedDescription)
        }
    }

    private func updateRouting() {
        let previousTask = routingTask
        previousTask?.cancel()
        revision = UUID()
        let currentRevision = revision

        routingTask = Task { [weak self] in
            // 前の起動処理が完了してから停止し、連打や切り替えによる処理の逆転を防ぐ。
            await previousTask?.value
            guard let self, !Task.isCancelled else { return }
            await passthrough.stop()
            guard !Task.isCancelled, isRunning else { return }

            let authorized = await microphoneAccess()
            // 許可ダイアログの表示中に停止した場合は、許可後も起動しない。
            guard !Task.isCancelled else { return }
            guard authorized else {
                isRunning = false
                report("マイクへのアクセスが許可されていません。システム設定の「プライバシーとセキュリティ」→「マイク」を確認してください。")
                return
            }

            do {
                let input = try catalog.resolve(selectedInputDevice, for: .input)
                let output = try catalog.resolve(selectedOutputDevice, for: .output)
                try await passthrough.start(
                    inputUID: catalog.deviceUID(for: input),
                    outputUID: catalog.deviceUID(for: output)
                ) { [weak self] message in
                    Task { @MainActor [weak self] in
                        // 切り替え前のセッションから届いた通知は現在の状態に反映しない。
                        guard let self, self.revision == currentRevision else { return }
                        self.stop()
                        if let message { self.report(message) }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                isRunning = false
                report(error.localizedDescription)
            }
        }
    }

    private func microphoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func report(_ message: String) {
        // 既存のUIは変えず、失敗時は停止状態に戻してコンソールに理由を残す。
        logger.error("\(message, privacy: .public)")
    }
}
