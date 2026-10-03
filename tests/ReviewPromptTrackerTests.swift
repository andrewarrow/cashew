import Foundation

// Run: swiftc cashew/Models/ReviewPromptTracker.swift tests/ReviewPromptTrackerTests.swift -o /tmp/cashew-review-tests && /tmp/cashew-review-tests
@main
enum ReviewPromptTrackerTests {
    static func main() {
        testFirstLaunchAndPersistence()
        testSessionCounting()
        testInstallAgeThreshold()
        testOpenAndActionThresholds()
        testRequestCooldownAndVersion()
        testIneligibleRequestDoesNotConsumeOpportunity()
        testInvalidSavedDate()
        print("All review prompt tracker tests passed")
    }

    private static func testFirstLaunchAndPersistence() {
        withTracker { defaults, clock, tracker in
            let firstLaunch = clock.date
            expect(tracker.firstLaunchDate == firstLaunch, "first launch is recorded")
            expect(tracker.appOpenCount == 0 && tracker.completedActionCount == 0, "initialization isn't usage")
            tracker.recordAppOpen()
            tracker.recordCompletedAction()
            clock.advance(days: 1)

            let reloaded = ReviewPromptTracker(defaults: defaults, now: { clock.date })
            expect(reloaded.firstLaunchDate == firstLaunch, "relaunch or update preserves first launch")
            expect(reloaded.appOpenCount == 1 && reloaded.completedActionCount == 1, "usage survives relaunch")
            reloaded.recordAppOpen()
            expect(reloaded.appOpenCount == 2, "a later cold launch counts as a visit")
        }
    }

    private static func testSessionCounting() {
        withTracker { defaults, clock, tracker in
            tracker.recordAppOpen()
            tracker.recordAppOpen()
            clock.date.addTimeInterval(60 * 60)
            tracker.recordAppOpen()
            expect(tracker.appOpenCount == 1, "system dialogs don't count as additional visits, even after a long session")

            tracker.recordAppBackground()
            tracker.recordAppOpen()
            expect(tracker.appOpenCount == 2, "foregrounding after a separated visit counts")
            tracker.recordAppBackground()
            clock.date.addTimeInterval(ReviewPromptTracker.Policy.sessionInterval - 1)
            tracker.recordAppOpen()
            expect(tracker.appOpenCount == 2, "quick background and foreground don't inflate visits")

            let reloaded = ReviewPromptTracker(defaults: defaults, now: { clock.date })
            reloaded.recordAppOpen()
            expect(reloaded.appOpenCount == 2, "quick relaunch doesn't inflate visits")
            reloaded.recordAppBackground()
            clock.date.addTimeInterval(1)
            reloaded.recordAppOpen()
            expect(reloaded.appOpenCount == 3, "exact session interval is eligible")
        }
    }

    private static func testInstallAgeThreshold() {
        withTracker { _, clock, tracker in
            recordVisits(5, tracker: tracker, clock: clock)
            recordActions(3, tracker: tracker)
            clock.date = tracker.firstLaunchDate.addingTimeInterval(ReviewPromptTracker.Policy.minimumInstallAge - 1)
            expect(!tracker.shouldRequestReview(version: "1.0"), "never prompt before seven days")
            clock.date.addTimeInterval(1)
            expect(tracker.shouldRequestReview(version: "1.0"), "exact install age is eligible")
            clock.date = tracker.firstLaunchDate.addingTimeInterval(-1)
            expect(!tracker.shouldRequestReview(version: "1.0"), "clock moving backward doesn't bypass install age")
        }
    }

    private static func testOpenAndActionThresholds() {
        withTracker { _, clock, tracker in
            recordVisits(4, tracker: tracker, clock: clock)
            clock.advance(days: 7)
            recordActions(2, tracker: tracker)
            expect(!tracker.shouldRequestReview(version: "1.0"), "age alone isn't enough")
            tracker.recordAppBackground()
            tracker.recordAppOpen()
            expect(!tracker.shouldRequestReview(version: "1.0"), "five visits still require three completed actions")
            tracker.recordCompletedAction()
            expect(tracker.shouldRequestReview(version: "1.0"), "all three thresholds allow a request")
        }
        withTracker { _, clock, tracker in
            recordVisits(4, tracker: tracker, clock: clock)
            recordActions(3, tracker: tracker)
            clock.advance(days: 7)
            expect(!tracker.shouldRequestReview(version: "1.0"), "completed actions can't bypass the visit threshold")
        }
    }

    private static func testRequestCooldownAndVersion() {
        withTracker { defaults, clock, tracker in
            recordVisits(5, tracker: tracker, clock: clock)
            recordActions(3, tracker: tracker)
            clock.advance(days: 7)
            expect(tracker.recordReviewRequest(version: "1.0"), "eligible request is recorded")
            expect(!tracker.recordReviewRequest(version: "1.0"), "duplicate requests are suppressed")
            expect(!tracker.shouldRequestReview(version: "1.1"), "updating doesn't bypass cooldown")
            let requestDate = clock.date
            let reloaded = ReviewPromptTracker(defaults: defaults, now: { clock.date })
            expect(!reloaded.shouldRequestReview(version: "1.0"), "request history survives relaunch")

            clock.date = requestDate.addingTimeInterval(ReviewPromptTracker.Policy.requestCooldown - 1)
            expect(!reloaded.shouldRequestReview(version: "1.1"), "cooldown applies until its exact boundary")
            clock.date.addTimeInterval(1)
            expect(!reloaded.shouldRequestReview(version: "1.0"), "the same version isn't requested again after cooldown")
            expect(reloaded.recordReviewRequest(version: "1.1"), "a new version can request after 120 days")
            expect(!tracker.shouldRequestReview(version: "1.1"), "all trackers observe the recorded request")
        }
    }

    private static func testIneligibleRequestDoesNotConsumeOpportunity() {
        withTracker { _, clock, tracker in
            expect(!tracker.recordReviewRequest(version: "1.0"), "ineligible request is rejected")
            recordVisits(5, tracker: tracker, clock: clock)
            recordActions(3, tracker: tracker)
            clock.advance(days: 7)
            expect(!tracker.recordReviewRequest(version: ""), "missing version can't consume a request")
            expect(tracker.recordReviewRequest(version: "1.0"), "a rejected request doesn't start cooldown")
        }
    }

    private static func testInvalidSavedDate() {
        withTracker { defaults, clock, _ in
            defaults.set("invalid", forKey: "ReviewPrompt.firstLaunchDate")
            let reloaded = ReviewPromptTracker(defaults: defaults, now: { clock.date })
            expect(reloaded.firstLaunchDate == clock.date, "invalid saved date is repaired")
            expect(!reloaded.shouldRequestReview(version: "1.0"), "repair doesn't prompt prematurely")
        }
    }

    private static func recordVisits(_ count: Int, tracker: ReviewPromptTracker, clock: Clock) {
        for _ in 0..<count {
            tracker.recordAppBackground()
            tracker.recordAppOpen()
            clock.date.addTimeInterval(ReviewPromptTracker.Policy.sessionInterval)
        }
    }

    private static func recordActions(_ count: Int, tracker: ReviewPromptTracker) {
        for _ in 0..<count { tracker.recordCompletedAction() }
    }

    private static func withTracker(_ test: (UserDefaults, Clock, ReviewPromptTracker) -> Void) {
        let suiteName = "ReviewPromptTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = Clock()
        test(defaults, clock, ReviewPromptTracker(defaults: defaults, now: { clock.date }))
    }

    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_700_000_000)

        func advance(days: Double) {
            date.addTimeInterval(days * 24 * 60 * 60)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
