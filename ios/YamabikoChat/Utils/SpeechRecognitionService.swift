import Foundation
import Combine
import Speech
import AVFoundation

enum SpeechRecognitionError: LocalizedError {
    case notAvailable
    case permissionDenied
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return L10n.text("音声認識はこのデバイスでは利用できません。")
        case .permissionDenied:
            return L10n.text("音声認識またはマイクの使用が許可されていません。設定から許可してください。")
        case .recognitionFailed(let message):
            return L10n.format("音声認識エラー: %@", message)
        }
    }
}

@MainActor
final class SpeechRecognitionService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var error: SpeechRecognitionError?

    var onTranscription: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var pendingStartTask: Task<Void, Never>?
    private var hasInstalledInputTap = false

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    func toggleRecording() {
        if isRecording || pendingStartTask != nil {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = .notAvailable
            DiagnosticsLogger.log(
                "Speech recognizer not available",
                category: .app,
                error: error
            )
            return
        }

        error = nil
        pendingStartTask?.cancel()

        pendingStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.pendingStartTask = nil
            }

            let micStatus = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard !Task.isCancelled else { return }
            guard micStatus else {
                self.error = .permissionDenied
                DiagnosticsLogger.log("Microphone permission denied", category: .app, error: self.error)
                return
            }

            let speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            guard !Task.isCancelled else { return }
            guard speechStatus == .authorized else {
                self.error = .permissionDenied
                DiagnosticsLogger.log("Speech recognition permission denied", category: .app, error: self.error)
                return
            }
            guard !Task.isCancelled else { return }

            self.beginRecognition(speechRecognizer: speechRecognizer)
        }
    }

    func stopRecording() {
        stopRecording(cancelPendingStart: true)
    }

    private func stopRecording(cancelPendingStart: Bool) {
        if cancelPendingStart {
            pendingStartTask?.cancel()
            pendingStartTask = nil
        }

        audioEngine.stop()
        if hasInstalledInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledInputTap = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }

    private func beginRecognition(speechRecognizer: SFSpeechRecognizer) {
        // Stop any existing session
        if audioEngine.isRunning {
            stopRecording(cancelPendingStart: false)
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = .recognitionFailed(error.localizedDescription)
            DiagnosticsLogger.log("Audio session setup failed", category: .app, error: error)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.onTranscription?(text)

                    if result.isFinal {
                        self.stopRecording()
                    }
                }

                if let error {
                    // Ignore cancellation errors from manual stop
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // Recognition cancelled – expected on manual stop
                        return
                    }
                    self.error = .recognitionFailed(error.localizedDescription)
                    DiagnosticsLogger.log("Speech recognition failed", category: .app, error: error)
                    self.stopRecording()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        hasInstalledInputTap = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            self.error = .recognitionFailed(error.localizedDescription)
            DiagnosticsLogger.log("Audio engine start failed", category: .app, error: error)
            stopRecording(cancelPendingStart: false)
        }
    }
}
