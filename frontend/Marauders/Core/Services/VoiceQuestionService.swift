@preconcurrency import AVFoundation
import Foundation

@MainActor
final class VoiceQuestionService: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private struct QuestionContext {
        let checkpointID: String
        let monumentID: String
        let language: String
    }

    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case thinking
        case speaking
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var answerText: String?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var synthesizer: AVSpeechSynthesizer?
    private var questionContext: QuestionContext?
    private var questionURL: URL?
    private var answerURL: URL?
    private var workTask: Task<Void, Never>?
    private let engine: any AnswerEngine

    var suppressesTourAudio: Bool {
        switch state {
        case .requestingPermission, .recording, .thinking, .speaking: true
        case .idle, .failed: false
        }
    }

    init(engine: any AnswerEngine = HybridAnswerEngine()) {
        self.engine = engine
        super.init()
    }

    func toggleRecording(checkpointID: String, monumentID: String, language: String) {
        switch state {
        case .idle, .failed:
            questionContext = QuestionContext(checkpointID: checkpointID, monumentID: monumentID, language: language)
            state = .requestingPermission
            workTask?.cancel()
            workTask = Task { await startRecording() }
        case .recording:
            stopAndAsk()
        case .requestingPermission, .thinking, .speaking:
            break
        }
    }

    func retry(checkpointID: String, monumentID: String, language: String) {
        state = .idle
        toggleRecording(checkpointID: checkpointID, monumentID: monumentID, language: language)
    }

    func cancel() {
        workTask?.cancel()
        workTask = nil
        if let url = recorder?.url { try? FileManager.default.removeItem(at: url) }
        if let questionURL { try? FileManager.default.removeItem(at: questionURL) }
        questionURL = nil
        recorder?.stop()
        recorder = nil
        player?.stop()
        player = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        if let answerURL { try? FileManager.default.removeItem(at: answerURL) }
        answerURL = nil
        questionContext = nil
        answerText = nil
        state = .idle
        cleanupAudioSession()
    }

    private func startRecording() async {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard !Task.isCancelled else { return }
        guard allowed else {
            questionContext = nil
            state = .failed("Microphone access is required to ask the guide a question.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("question-\(UUID().uuidString).m4a")
            questionURL = url
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            guard recorder?.record() == true else {
                recorder = nil
                questionContext = nil
                state = .failed("The microphone could not start. Please try again.")
                cleanupAudioSession()
                return
            }
            state = .recording
            answerText = nil
        } catch {
            questionContext = nil
            state = .failed("The microphone could not start. Please try again.")
            cleanupAudioSession()
        }
    }

    private func stopAndAsk() {
        guard let recorder, let context = questionContext else { return }
        recorder.stop()
        let url = recorder.url
        questionURL = url
        self.recorder = nil
        state = .thinking
        workTask?.cancel()
        workTask = Task {
            do {
                let audio = try Data(contentsOf: url).base64EncodedString()
                let response = try await engine.answer(
                    text: nil, audioBase64: audio,
                    checkpointId: context.checkpointID,
                    monumentId: context.monumentID,
                    lang: context.language
                )
                guard !Task.isCancelled else { return }
                answerText = response.text
                try play(base64: response.audioBase64)
            } catch {
                guard !Task.isCancelled else { return }
                if await rescueOffline(recordingURL: url, context: context) { return }
                questionContext = nil
                state = .failed(error.localizedDescription)
                cleanupAudioSession()
            }
            try? FileManager.default.removeItem(at: url)
            questionURL = nil
            workTask = nil
        }
    }

    // Fully offline voice loop: on-device STT -> on-device model -> system TTS.
    // Only attempted when the network path already failed and Apple Intelligence is usable.
    private func rescueOffline(recordingURL: URL, context: QuestionContext) async -> Bool {
        guard FoundationModelsAnswerEngine.isUsable else { return false }
        guard let transcript = await OfflineVoicePipeline.transcribe(url: recordingURL, lang: context.language),
              !transcript.isEmpty, !Task.isCancelled else { return false }
        guard let response = try? await FoundationModelsAnswerEngine().answer(
            text: transcript, audioBase64: nil,
            checkpointId: context.checkpointID, monumentId: context.monumentID,
            lang: context.language, skipAudio: true
        ), !Task.isCancelled else { return false }
        answerText = response.text
        speak(response.text, lang: context.language)
        return true
    }

    private func speak(_ text: String, lang: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: OfflineVoicePipeline.recognizerLocale(for: lang).identifier)
            ?? AVSpeechSynthesisVoice(language: "en-GB")
        let next = AVSpeechSynthesizer()
        next.delegate = self
        synthesizer = next
        next.speak(utterance)
        state = .speaking
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.synthesizer === synthesizer else { return }
            self.synthesizer = nil
            self.questionContext = nil
            self.cleanupAudioSession()
            self.state = .idle
        }
    }

    private func play(base64: String) throws {
        guard let data = Data(base64Encoded: base64) else { throw CocoaError(.fileReadCorruptFile) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("answer-\(UUID().uuidString).mp3")
        try data.write(to: url, options: .atomic)
        answerURL = url
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        guard player?.play() == true else {
            player = nil
            try? FileManager.default.removeItem(at: url)
            answerURL = nil
            throw CocoaError(.fileReadUnknown)
        }
        state = .speaking
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            if let answerURL = self.answerURL { try? FileManager.default.removeItem(at: answerURL) }
            self.answerURL = nil
            self.questionContext = nil
            self.cleanupAudioSession()
            self.state = .idle
        }
    }

    private func cleanupAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
