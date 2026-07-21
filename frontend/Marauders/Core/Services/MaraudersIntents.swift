import AppIntents

// Siri / Shortcuts / Spotlight surface. Progress reads the same persisted store the
// map uses, so the answer is correct without launching the UI.

struct ContinueTourIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue My Tour"
    static let description = IntentDescription("Opens Marauders to continue your monument tour.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct TourProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Tour Progress"
    static let description = IntentDescription("Tells you how many Taj Mahal chapters you have completed.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TajTourProgressStore()
        let completed = store.completedChapterCount
        let total = store.totalChapterCount
        let dialog: IntentDialog
        if completed == 0 {
            dialog = "You haven't started the Taj Mahal journey yet. Six chapters of secrets are waiting."
        } else if store.isComplete {
            dialog = "All \(total) chapters complete — you're a true Marauder. Your gift card is unlocked."
        } else {
            dialog = "You've completed \(completed) of \(total) Taj Mahal chapters. Next up: \(store.chapters.first { $0.order == completed }?.name ?? "the next chapter")."
        }
        return .result(dialog: dialog)
    }
}

struct MaraudersShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueTourIntent(),
            phrases: [
                "Continue my \(.applicationName) tour",
                "Resume my tour in \(.applicationName)"
            ],
            shortTitle: "Continue Tour",
            systemImageName: "building.columns.fill"
        )
        AppShortcut(
            intent: TourProgressIntent(),
            phrases: [
                "How is my \(.applicationName) tour going",
                "How many secrets have I found in \(.applicationName)"
            ],
            shortTitle: "Tour Progress",
            systemImageName: "checkmark.seal.fill"
        )
    }
}
