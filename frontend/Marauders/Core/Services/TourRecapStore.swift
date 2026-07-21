import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct TourRecap: Equatable {
    struct Question: Equatable, Identifiable {
        let id = UUID()
        let prompt: String
        let choices: [String]
        let answerIndex: Int
    }

    let journal: String
    let questions: [Question]
    let generatedOnDevice: Bool
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedRecap {
    @Guide(description: "A warm two-sentence journal entry about the visit, written to the visitor.")
    var journal: String
    @Guide(description: "Exactly three quiz questions about the visited chapters.")
    var questions: [GeneratedQuestion]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedQuestion {
    @Guide(description: "The quiz question.")
    var prompt: String
    @Guide(description: "Exactly four short answer choices.")
    var choices: [String]
    @Guide(description: "Zero-based index of the correct choice.")
    var answerIndex: Int
}
#endif

// End-of-tour recap: a journal paragraph plus a short quiz built from the chapters
// the visitor actually completed. Generated on-device via Foundation Models guided
// generation when available; otherwise assembled deterministically from the bundled
// chapter facts so the recap always works offline on any device.
@MainActor
final class TourRecapStore: ObservableObject {
    enum State: Equatable {
        case idle, generating, ready(TourRecap), failed(String)
    }

    @Published private(set) var state: State = .idle

    func generate(completedChapters: [TajMapCheckpoint], monumentName: String) {
        guard !completedChapters.isEmpty else {
            state = .failed("Complete a chapter first, then come back for your recap.")
            return
        }
        state = .generating
        Task {
            if let recap = await onDeviceRecap(chapters: completedChapters, monumentName: monumentName), recap.questions.count >= 1 {
                state = .ready(recap)
            } else {
                state = .ready(Self.fallbackRecap(chapters: completedChapters, monumentName: monumentName))
            }
        }
    }

    private func onDeviceRecap(chapters: [TajMapCheckpoint], monumentName: String) async -> TourRecap? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), FoundationModelsAnswerEngine.isUsable else { return nil }
        let facts = chapters.map { "- \($0.name): \($0.verifiedInformation) \($0.interestingFact)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
        You create a short recap of a visit to \(monumentName). Ground every question strictly in these notes:
        \(facts)
        Each question must have exactly four choices and exactly one correct answer at the given index.
        """)
        guard let response = try? await session.respond(
            to: "Write the visitor's journal entry and a three-question quiz.",
            generating: GeneratedRecap.self
        ) else { return nil }
        let questions = response.content.questions.compactMap { question -> TourRecap.Question? in
            guard question.choices.count >= 2, question.choices.indices.contains(question.answerIndex) else { return nil }
            return TourRecap.Question(prompt: question.prompt, choices: question.choices, answerIndex: question.answerIndex)
        }
        guard !questions.isEmpty else { return nil }
        return TourRecap(journal: response.content.journal, questions: questions, generatedOnDevice: true)
        #else
        return nil
        #endif
    }

    static func fallbackRecap(chapters: [TajMapCheckpoint], monumentName: String) -> TourRecap {
        let names = chapters.map(\.name).joined(separator: ", ")
        let journal = "Today you walked \(monumentName) chapter by chapter — \(names). Every story you unlocked is saved offline, ready to revisit anytime."
        let questions = chapters.prefix(3).enumerated().map { index, chapter -> TourRecap.Question in
            var choices = chapters.map(\.name)
            if choices.count < 4 {
                choices.append(contentsOf: ["The Moonlight Garden", "The Agra Fort", "The Yamuna Ghats"])
            }
            choices = Array(choices.prefix(4))
            let answer = chapter.name
            if !choices.contains(answer) { choices[0] = answer }
            choices.shuffle()
            _ = index
            return TourRecap.Question(
                prompt: "Which chapter does this describe? \"\(chapter.interestingFact)\"",
                choices: choices,
                answerIndex: choices.firstIndex(of: answer) ?? 0
            )
        }
        return TourRecap(journal: journal, questions: Array(questions), generatedOnDevice: false)
    }
}
