import ActivityKit
import Foundation

// Drives the lock-screen / Dynamic Island Live Activity for an in-progress tour.
// Updates are local-only (no push token) so the activity works fully offline.
@MainActor
final class TourLiveActivityController {
    private var activity: Activity<TourActivityAttributes>?

    func start(monumentName: String, state: TourActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        activity = try? Activity.request(
            attributes: TourActivityAttributes(monumentName: monumentName),
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    func update(_ state: TourActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let ending = activity else { return }
        activity = nil
        Task { await ending.end(nil, dismissalPolicy: .immediate) }
    }
}
