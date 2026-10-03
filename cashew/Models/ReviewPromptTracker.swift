import Foundation

/// Local usage history used to choose a good time for StoreKit's review request.
final class ReviewPromptTracker {
    enum Policy {
        static let minimumInstallAge: TimeInterval = 7 * 24 * 60 * 60
        static let minimumAppOpens = 5
        static let minimumCompletedActions = 3
        static let sessionInterval: TimeInterval = 30 * 60
        static let requestCooldown: TimeInterval = 120 * 24 * 60 * 60
    }

    private enum Key {
        static let firstLaunchDate = "ReviewPrompt.firstLaunchDate"
        static let appOpenCount = "ReviewPrompt.appOpenCount"
        static let lastCountedOpenDate = "ReviewPrompt.lastCountedOpenDate"
        static let completedActionCount = "ReviewPrompt.completedActionCount"
        static let lastRequestDate = "ReviewPrompt.lastRequestDate"
        static let lastRequestVersion = "ReviewPrompt.lastRequestVersion"
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private var isForeground = false
    let firstLaunchDate: Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        // The app cannot run at installation time; its first launch is our proxy.
        if let savedDate = defaults.object(forKey: Key.firstLaunchDate) as? Date {
            firstLaunchDate = savedDate
        } else {
            firstLaunchDate = now()
            defaults.set(firstLaunchDate, forKey: Key.firstLaunchDate)
        }
    }

    var appOpenCount: Int {
        defaults.integer(forKey: Key.appOpenCount)
    }

    var completedActionCount: Int {
        defaults.integer(forKey: Key.completedActionCount)
    }

    func recordAppOpen() {
        // Inactive -> active transitions (e.g. dismissing a system dialog) aren't visits.
        guard !isForeground else { return }
        isForeground = true
        let date = now()
        if let lastOpen = defaults.object(forKey: Key.lastCountedOpenDate) as? Date,
           date.timeIntervalSince(lastOpen) < Policy.sessionInterval {
            return
        }
        defaults.set(appOpenCount + 1, forKey: Key.appOpenCount)
        defaults.set(date, forKey: Key.lastCountedOpenDate)
    }

    func recordAppBackground() {
        isForeground = false
    }

    func recordCompletedAction() {
        defaults.set(completedActionCount + 1, forKey: Key.completedActionCount)
    }

    func shouldRequestReview(version: String) -> Bool {
        guard !version.isEmpty,
              appOpenCount >= Policy.minimumAppOpens,
              completedActionCount >= Policy.minimumCompletedActions,
              now().timeIntervalSince(firstLaunchDate) >= Policy.minimumInstallAge,
              defaults.string(forKey: Key.lastRequestVersion) != version else {
            return false
        }
        if let lastRequest = defaults.object(forKey: Key.lastRequestDate) as? Date,
           now().timeIntervalSince(lastRequest) < Policy.requestCooldown {
            return false
        }
        return true
    }

    /// StoreKit doesn't report whether it showed a prompt or whether someone reviewed.
    @discardableResult
    func recordReviewRequest(version: String) -> Bool {
        guard shouldRequestReview(version: version) else { return false }
        defaults.set(now(), forKey: Key.lastRequestDate)
        defaults.set(version, forKey: Key.lastRequestVersion)
        return true
    }
}
