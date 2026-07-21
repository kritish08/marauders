import Foundation

protocol AnswerEngine {
    func answer(
        text: String?, audioBase64: String?,
        checkpointId: String, monumentId: String, lang: String, skipAudio: Bool
    ) async throws -> AskResponse
}

extension AnswerEngine {
    func answer(
        text: String?, audioBase64: String?,
        checkpointId: String, monumentId: String, lang: String
    ) async throws -> AskResponse {
        try await answer(
            text: text, audioBase64: audioBase64,
            checkpointId: checkpointId, monumentId: monumentId, lang: lang, skipAudio: false
        )
    }
}

struct AskResponse: Codable {
    let question: String
    let text: String
    let audioBase64: String
}

private struct AskRequest: Encodable {
    let monumentId: String
    let checkpointId: String
    let lang: String
    let text: String?
    let audioBase64: String?
    let skipAudio: Bool
}

struct AzureAnswerEngine: AnswerEngine {
    enum EngineError: LocalizedError {
        case missingAppKey
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingAppKey: "Live questions are not configured on this build. Add MARAUDERS_APP_KEY locally."
            case .invalidResponse: "The guide returned an unreadable response. Please try again."
            case .server(let message): message
            }
        }
    }

    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func answer(
        text: String?, audioBase64: String?,
        checkpointId: String, monumentId: String, lang: String, skipAudio: Bool
    ) async throws -> AskResponse {
        guard !API.appKey.isEmpty else { throw EngineError.missingAppKey }
        var request = URLRequest(url: API.base.appendingPathComponent("ask"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(API.appKey, forHTTPHeaderField: "X-App-Key")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(AskRequest(
            monumentId: monumentId, checkpointId: checkpointId, lang: lang,
            text: text, audioBase64: audioBase64, skipAudio: skipAudio
        ))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw EngineError.server("The live guide is unavailable (\(http.statusCode)). Please retry.")
        }
        return try JSONDecoder().decode(AskResponse.self, from: data)
    }

    func health() async -> Bool {
        do {
            let (_, response) = try await session.data(from: API.base.appendingPathComponent("health"))
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
}

#if canImport(FoundationModels)
import FoundationModels
#endif

// On-device answers via Apple's Foundation Models framework (iOS 26+, A17 Pro-class
// hardware). Text-only: callers that need spoken audio go through AzureAnswerEngine.
struct FoundationModelsAnswerEngine: AnswerEngine {
    static var isUsable: Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return false }
        return SystemLanguageModel.default.availability == .available
        #else
        return false
        #endif
    }

    func answer(
        text: String?, audioBase64: String?,
        checkpointId: String, monumentId: String, lang: String, skipAudio: Bool
    ) async throws -> AskResponse {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), SystemLanguageModel.default.availability == .available else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "On-device answers need Apple Intelligence (iOS 26, iPhone 15 Pro or later)."])
        }
        guard let question = text?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "On-device answers support text questions only."])
        }
        let session = LanguageModelSession(instructions: Self.instructions(monumentId: monumentId, checkpointId: checkpointId, lang: lang))
        let response = try await session.respond(to: question)
        return AskResponse(question: question, text: response.content, audioBase64: "")
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }

    private static func instructions(monumentId: String, checkpointId: String, lang: String) -> String {
        let languageName = Locale(identifier: "en").localizedString(forLanguageCode: lang) ?? "English"
        var lines = [
            "You are Marauders, an expert local tour guide.",
            "The visitor is at the site \"\(monumentId)\", near checkpoint \"\(checkpointId)\".",
            "Answer in \(languageName). Keep answers to two or three vivid, factual sentences.",
            "If the question is unrelated to the site or travel, gently steer back to the tour."
        ]
        if monumentId == "taj_mahal" {
            lines.append("Grounding notes you may draw on:")
            for chapter in TajMapCheckpoint.chapters {
                lines.append("- \(chapter.name): \(chapter.verifiedInformation) \(chapter.interestingFact)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// On-device first for text questions, Azure /ask otherwise or on any failure.
struct HybridAnswerEngine: AnswerEngine {
    let onDevice = FoundationModelsAnswerEngine()
    let remote = AzureAnswerEngine()

    func answer(
        text: String?, audioBase64: String?,
        checkpointId: String, monumentId: String, lang: String, skipAudio: Bool
    ) async throws -> AskResponse {
        if skipAudio, text != nil, FoundationModelsAnswerEngine.isUsable {
            if let response = try? await onDevice.answer(
                text: text, audioBase64: audioBase64,
                checkpointId: checkpointId, monumentId: monumentId, lang: lang, skipAudio: true
            ) {
                return response
            }
        }
        return try await remote.answer(
            text: text, audioBase64: audioBase64,
            checkpointId: checkpointId, monumentId: monumentId, lang: lang, skipAudio: skipAudio
        )
    }
}
