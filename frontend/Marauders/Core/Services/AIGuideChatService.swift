import Foundation

struct AIGuideContext: Equatable {
    let monumentID: String
    let monumentName: String
    let checkpointID: String
    let checkpointName: String
    let language: String
}

@MainActor
final class AIGuideChatService: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Role: Equatable { case user, guide }

        let id: UUID
        let role: Role
        let text: String

        init(id: UUID = UUID(), role: Role, text: String) {
            self.id = id
            self.role = role
            self.text = text
        }
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let engine: any AnswerEngine
    private var activeRequestID: UUID?

    init(engine: any AnswerEngine = HybridAnswerEngine()) {
        self.engine = engine
    }

    func send(_ question: String, context: AIGuideContext) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isLoading else { return }

        messages.append(Message(role: .user, text: question))
        errorMessage = nil
        isLoading = true
        let requestID = UUID()
        activeRequestID = requestID
        defer {
            if activeRequestID == requestID {
                activeRequestID = nil
                isLoading = false
            }
        }

        do {
            try Task.checkCancellation()
            let response = try await engine.answer(
                text: question,
                audioBase64: nil,
                checkpointId: context.checkpointID,
                monumentId: context.monumentID,
                lang: context.language,
                skipAudio: true
            )
            try Task.checkCancellation()
            guard activeRequestID == requestID else { return }
            messages.append(Message(role: .guide, text: response.text))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeRequestID == requestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        activeRequestID = nil
        isLoading = false
    }
}
