@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AudioNarrationController: NSObject, ObservableObject {
    enum State: Equatable { case idle, speaking, pausing, paused }

    @Published private(set) var state: State = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var estimatedDuration: TimeInterval = 0
    @Published var speechRate: Float {
        didSet { defaults.set(speechRate, forKey: rateKey) }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let defaults: UserDefaults
    private let rateKey = "taj.narration-rate.v1"
    private var activeUtterance: AVSpeechUtterance?
    private var text = ""
    private var language = "en-IN"
    private var chapterID = ""
    private var startedAt: Date?
    private var utteranceStartUTF16Offset = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let number = defaults.object(forKey: rateKey) as? NSNumber {
            speechRate = min(max(number.floatValue, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        } else {
            speechRate = AVSpeechUtteranceDefaultSpeechRate
        }
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { state == .speaking || state == .pausing }

    var playbackSpeed: Float {
        speechRate / AVSpeechUtteranceDefaultSpeechRate
    }

    func play(text: String, languageCode: String, chapterID: String) {
        if self.chapterID == chapterID, state == .paused {
            resume()
            return
        }
        start(text: text, languageCode: languageCode, chapterID: chapterID)
    }

    func pause() {
        guard state == .speaking, synthesizer.pauseSpeaking(at: .word) else { return }
        state = .pausing
    }

    func resume() {
        guard state == .paused else { return }
        _ = synthesizer.continueSpeaking()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        activeUtterance = nil
        startedAt = nil
        state = .idle
        progress = 0
        elapsed = 0
    }

    func restart() {
        guard !text.isEmpty else { return }
        start(text: text, languageCode: language, chapterID: chapterID)
    }

    func seek(to position: Double) {
        guard !text.isEmpty else { return }
        let clampedPosition = min(max(position, 0), 0.999)
        let utf16Offset = Int(Double(text.utf16.count) * clampedPosition)
        let composedRange = (text as NSString).rangeOfComposedCharacterSequence(at: utf16Offset)
        var startIndex = String.Index(utf16Offset: composedRange.location, in: text)
        while startIndex > text.startIndex, !text[text.index(before: startIndex)].isWhitespace {
            startIndex = text.index(before: startIndex)
        }
        speak(from: startIndex)
    }

    func setPlaybackSpeed(_ multiplier: Float) {
        let position = progress
        let shouldRemainPaused = state == .paused || state == .pausing
        speechRate = min(
            max(AVSpeechUtteranceDefaultSpeechRate * multiplier, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
        estimatedDuration = duration(for: text)
        if state != .idle {
            seek(to: position)
            if shouldRemainPaused, synthesizer.pauseSpeaking(at: .immediate) {
                state = .pausing
            }
        }
    }

    private func start(text: String, languageCode: String, chapterID: String) {
        synthesizer.stopSpeaking(at: .immediate)
        self.text = text
        language = locale(for: languageCode)
        self.chapterID = chapterID
        progress = 0
        elapsed = 0
        estimatedDuration = duration(for: text)
        speak(from: text.startIndex)
    }

    private func speak(from startIndex: String.Index) {
        synthesizer.stopSpeaking(at: .immediate)
        let spokenText = String(text[startIndex...])
        utteranceStartUTF16Offset = text.utf16.distance(from: text.utf16.startIndex, to: startIndex.samePosition(in: text.utf16)!)
        progress = text.isEmpty ? 0 : Double(utteranceStartUTF16Offset) / Double(text.utf16.count)
        elapsed = progress * estimatedDuration

        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = speechRate
        utterance.pitchMultiplier = 0.96
        utterance.prefersAssistiveTechnologySettings = true
        utterance.postUtteranceDelay = 0.15
        activeUtterance = utterance
        startedAt = Date()
        state = .speaking
        synthesizer.speak(utterance)
    }

    private func duration(for text: String) -> TimeInterval {
        max(Double(text.split(whereSeparator: \.isWhitespace).count) / wordsPerSecond, 1)
    }

    private var wordsPerSecond: Double {
        let normalized = Double(speechRate / AVSpeechUtteranceDefaultSpeechRate)
        return max(2.1 * normalized, 0.8)
    }

    private func locale(for code: String) -> String {
        switch code { case "hi": "hi-IN"; case "fr": "fr-FR"; case "es": "es-ES"; default: "en-IN" }
    }

    private func updateElapsed() {
        elapsed = min(progress * estimatedDuration, estimatedDuration)
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        progress = 1
        updateElapsed()
        state = .idle
        activeUtterance = nil
        startedAt = nil
    }
}

extension AudioNarrationController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.updateElapsed()
            self.state = .paused
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.startedAt = Date().addingTimeInterval(-self.elapsed)
            self.state = .speaking
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.startedAt = nil
            self.state = .idle
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance, !self.text.isEmpty else { return }
            let spokenOffset = self.utteranceStartUTF16Offset + characterRange.location + characterRange.length
            self.progress = min(Double(spokenOffset) / Double(self.text.utf16.count), 1)
            self.updateElapsed()
        }
    }
}
