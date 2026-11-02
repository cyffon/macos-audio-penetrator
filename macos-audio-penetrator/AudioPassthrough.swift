import AVFoundation

/// 起動・停止はブロックするため、UIから独立したactorでセッションを管理する。
actor AudioPassthrough {
    private var session: AVCaptureSession?
    private var observers: [NSObjectProtocol] = []

    func start(
        inputUID: String,
        outputUID: String,
        onStop: @escaping @Sendable (String?) -> Void
    ) throws {
        try Task.checkCancellation()
        stop()
        guard let device = AVCaptureDevice(uniqueID: inputUID), device.hasMediaType(.audio) else {
            throw AudioPassthroughError.inputUnavailable
        }

        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioPreviewOutput()
        output.outputDeviceUniqueID = outputUID
        output.volume = 1
        try configure(session, input: input, output: output)
        try Task.checkCancellation()

        self.session = session
        let sessionID = ObjectIdentifier(session)
        let stopNotifications = [
            AVCaptureSession.runtimeErrorNotification,
            AVCaptureSession.didStopRunningNotification,
            AVCaptureSession.wasInterruptedNotification
        ]
        observers = stopNotifications.map { name in
            NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] notification in
                let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                Task { await self?.sessionStopped(sessionID, message: message, onStop: onStop) }
            }
        }

        session.startRunning()
        guard session.isRunning else {
            stop()
            throw AudioPassthroughError.startFailed
        }
    }

    func stop() {
        // 通常の停止を障害通知として扱わないよう、先に監視を解除する。
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        session?.stopRunning()
        session = nil
    }

    private func configure(
        _ session: AVCaptureSession,
        input: AVCaptureDeviceInput,
        output: AVCaptureAudioPreviewOutput
    ) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else {
            throw AudioPassthroughError.configurationFailed
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            throw AudioPassthroughError.configurationFailed
        }
        // PreviewOutputに転送を任せ、PCMバッファのコピーや独自の音声処理を避ける。
        session.addOutput(output)
    }

    private func sessionStopped(
        _ sessionID: ObjectIdentifier,
        message: String?,
        onStop: @Sendable (String?) -> Void
    ) {
        guard let session, ObjectIdentifier(session) == sessionID else { return }
        stop()
        onStop(message)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        session?.stopRunning()
    }
}

private enum AudioPassthroughError: LocalizedError {
    case inputUnavailable
    case configurationFailed
    case startFailed

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            "選択した入力デバイスを使用できません。"
        case .configurationFailed:
            "選択したデバイスで音声転送を構成できません。"
        case .startFailed:
            "音声転送を起動できませんでした。デバイスとマイクのアクセス許可を確認してください。"
        }
    }
}
