import Foundation

@MainActor
final class TajAIInsightStore: ObservableObject {
    enum State: Equatable {
        case idle, loading, success(String), failure(String)
    }

    @Published private(set) var states: [String: State] = [:]
    private let defaults: UserDefaults
    private let engine: any AnswerEngine

    init(defaults: UserDefaults = .standard, engine: any AnswerEngine = HybridAnswerEngine()) {
        self.defaults = defaults
        self.engine = engine
    }

    func state(for chapterID: String, language: String) -> State {
        states[stateKey(chapterID, language: language)] ?? .idle
    }

    func load(for chapter: TajMapCheckpoint, language: String) async {
        let stateKey = stateKey(chapter.id, language: language)
        let key = cacheKey(chapter.id, language: language)
        if let cached = defaults.string(forKey: key), !cached.isEmpty {
            states[stateKey] = .success(cached)
            return
        }
        states[stateKey] = .loading
        if let live = await liveInsight(for: chapter, language: language) {
            guard !Task.isCancelled else { return }
            defaults.set(live, forKey: key)
            states[stateKey] = .success(live)
            return
        }
        guard !Task.isCancelled else { return }
        guard !chapter.fallbackAIInformation.isEmpty else {
            states[stateKey] = .failure("No offline guide note is available for this chapter.")
            return
        }
        defaults.set(chapter.fallbackAIInformation, forKey: key)
        states[stateKey] = .success(chapter.fallbackAIInformation)
    }

    // Text-only /ask fast path (skipAudio) — falls back to the bundled note offline or without an app key.
    private func liveInsight(for chapter: TajMapCheckpoint, language: String) async -> String? {
        let question = "Share one fascinating, lesser-known insight about the \(chapter.name) chapter of the Taj Mahal in two sentences."
        let response = try? await engine.answer(
            text: question, audioBase64: nil,
            checkpointId: Self.backendCheckpointID(forChapter: chapter.id),
            monumentId: "taj_mahal", lang: language, skipAudio: true
        )
        guard let text = response?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func backendCheckpointID(forChapter id: String) -> String {
        backendCheckpointIDs[id] ?? "cp_great_gate"
    }

    private static let backendCheckpointIDs: [String: String] = [
        "start": "cp_great_gate",
        "great-gate": "cp_great_gate",
        "terrace": "cp_main_platform",
        "mughal-charbagh": "cp_river_view",
        "mosque": "cp_inlay_detail",
        "exit": "cp_great_gate"
    ]

    func retry(for chapter: TajMapCheckpoint, language: String) async {
        defaults.removeObject(forKey: cacheKey(chapter.id, language: language))
        await load(for: chapter, language: language)
    }

    private func stateKey(_ chapterID: String, language: String) -> String {
        "\(language).\(chapterID)"
    }

    private func cacheKey(_ chapterID: String, language: String) -> String {
        "taj.ai-insight.v2.\(language).\(chapterID)"
    }
}
