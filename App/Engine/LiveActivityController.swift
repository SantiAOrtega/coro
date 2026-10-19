import ActivityKit
import CoroKit
import Foundation

/// Owns the single lyrics Live Activity. iOS mirrors it to CarPlay (iOS 26+).
@MainActor
final class LiveActivityController {
    typealias State = LyricsActivityAttributes.ContentState

    private var activity: Activity<LyricsActivityAttributes>?
    private var pending: State?
    private var isUpdating = false

    var isRunning: Bool { activity != nil }

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Must be called while the app is in the foreground.
    func start(sourceName: String, state: State) throws {
        endAllStale()
        let content = ActivityContent(state: state, staleDate: nil)
        activity = try Activity.request(
            attributes: LyricsActivityAttributes(sourceName: sourceName),
            content: content,
            pushType: nil
        )
    }

    /// Coalesces bursts: only the latest state is sent once the previous update finishes.
    func update(_ state: State) {
        guard activity != nil else { return }
        pending = state
        guard !isUpdating else { return }
        isUpdating = true
        Task { @MainActor in
            while let next = self.pending, let activity = self.activity {
                self.pending = nil
                await activity.update(ActivityContent(state: next, staleDate: Date().addingTimeInterval(120)))
            }
            self.isUpdating = false
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        pending = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Clean up activities left behind by a previous run (crash, force-quit).
    func endAllStale() {
        for stale in Activity<LyricsActivityAttributes>.activities where stale.id != activity?.id {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
