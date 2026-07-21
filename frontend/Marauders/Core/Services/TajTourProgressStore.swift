import Foundation

@MainActor
final class TajTourProgressStore: ObservableObject {
    private struct Snapshot: Codable {
        let completedIDs: Set<String>
        let selectedID: String
    }

    @Published private(set) var completedIDs: Set<String>
    @Published private(set) var selectedChapterID: String

    private let defaults: UserDefaults
    private let key: String

    init(scopeID: String = "taj_mahal", defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "taj.tour-progress.v1.\(scopeID)"
        let validIDs = Set(TajMapCheckpoint.chapters.map(\.id))
        let decoded = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let persisted = decoded?.completedIDs.intersection(validIDs) ?? []

        var contiguous = Set<String>()
        for chapter in TajMapCheckpoint.chapters {
            guard persisted.contains(chapter.id) else { break }
            contiguous.insert(chapter.id)
        }
        completedIDs = contiguous

        let fallback = TajMapCheckpoint.chapters.first { !contiguous.contains($0.id) }?.id
            ?? TajMapCheckpoint.chapters.last?.id
            ?? ""
        if let selected = decoded?.selectedID,
           validIDs.contains(selected),
           let chapter = TajMapCheckpoint.chapters.first(where: { $0.id == selected }),
           chapter.order <= contiguous.count {
            selectedChapterID = selected
        } else {
            selectedChapterID = fallback
        }
    }

    var chapters: [TajMapCheckpoint] {
        TajMapCheckpoint.chapters.map { $0.withStatus(status(for: $0)) }
    }

    var selectedChapter: TajMapCheckpoint? {
        chapters.first { $0.id == selectedChapterID }
    }

    var completedChapterCount: Int { completedIDs.count }
    var totalChapterCount: Int { TajMapCheckpoint.chapters.count }
    var progress: Double { totalChapterCount == 0 ? 0 : min(Double(completedChapterCount) / Double(totalChapterCount), 1) }
    var isComplete: Bool { totalChapterCount > 0 && completedChapterCount == totalChapterCount }

    func status(for chapter: TajMapCheckpoint) -> CheckpointStatus {
        if completedIDs.contains(chapter.id) { return .completed }
        if chapter.id == selectedChapterID && chapter.order == completedChapterCount { return .active }
        if chapter.order == completedChapterCount { return .available }
        return chapter.order > completedChapterCount ? .locked : .upcoming
    }

    @discardableResult
    func select(_ chapterID: String) -> Bool {
        guard let chapter = TajMapCheckpoint.chapters.first(where: { $0.id == chapterID }),
              chapter.order <= completedChapterCount else { return false }
        selectedChapterID = chapterID
        persist()
        return true
    }

    var canCompleteSelectedChapter: Bool {
        guard let selectedChapter else { return false }
        return selectedChapter.order == completedChapterCount && !completedIDs.contains(selectedChapter.id)
    }

    @discardableResult
    func completeSelectedChapter() -> Bool {
        guard canCompleteSelectedChapter, let selectedChapter else { return false }
        completedIDs.insert(selectedChapter.id)
        persist()
        return true
    }

    private func persist() {
        let snapshot = Snapshot(completedIDs: completedIDs, selectedID: selectedChapterID)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
    }
}
