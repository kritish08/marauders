import Foundation
import Speech

// On-device speech-to-text for the offline voice rescue path: when the /ask backend is
// unreachable, the recorded question is transcribed locally, answered by the on-device
// model, and spoken with system TTS — the full voice loop with zero network.
enum OfflineVoicePipeline {
    static func recognizerLocale(for lang: String) -> Locale {
        switch lang {
        case "hi": Locale(identifier: "hi-IN")
        case "fr": Locale(identifier: "fr-FR")
        case "es": Locale(identifier: "es-ES")
        default: Locale(identifier: "en-IN")
        }
    }

    static func transcribe(url: URL, lang: String) async -> String? {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { return nil }
        guard let recognizer = SFSpeechRecognizer(locale: recognizerLocale(for: lang)) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        return await withCheckedContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    finished = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
