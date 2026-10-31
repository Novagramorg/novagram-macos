import AppKit
import Localization
import NovagramReviewPromptCore
import os.log

// App Store rating prompt (NovagramReviewPromptKit SDK, the same rules as iOS): every user, Apple's system prompt only.
public enum NovagramReviewPrompt {
    private static let center = ReviewPromptCenter()
    private static let log = OSLog(subsystem: "uz.fenixuz.app", category: "NovagramReviewPrompt")
    private static var loginScreenShown = false
    private static var startedAccountId: Int64?

    // Any thread.
    public static func record(_ feature: ReviewPromptFeature) {
        center.recordSuccess(feature)
        let newCount = center.state.newSuccessCount(for: feature)
        os_log("%{public}@", log: log, type: .default, "success \(feature.rawValue), new \(newCount)")
    }

    // Main thread.
    public static func loginScreenDidShow() {
        loginScreenShown = true
    }

    // Main thread, on every account start. After the login screen, another account than before means a login.
    public static func accountDidStart(accountId: Int64) {
        if loginScreenShown, accountId != startedAccountId {
            center.noteFreshStart()
            os_log("%{public}@", log: log, type: .default, "fresh start after login")
        }
        loginScreenShown = false
        startedAccountId = accountId
    }

    // Main thread, at a natural break: the chat list shows with no chat open.
    public static func chatListDidAppear(window: NSWindow?, isBusy: @escaping () -> Bool) {
        guard #available(macOS 10.15, *) else {
            return
        }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        MainActor.assumeIsolated {
            center.requestReviewIfAppropriate(appVersion: appVersion, in: window, isBusy: isBusy, completion: { result in
                os_log("%{public}@", log: log, type: .default, "request \(appVersion): \(result)")
            })
        }
    }

    public static var rateTitle: String {
        return ReviewPromptStrings(languageCode: appCurrentLanguage.languageCode).rateTitle
    }

    public static var rateFooter: String {
        return ReviewPromptStrings(languageCode: appCurrentLanguage.languageCode).footer
    }

    // The Settings row opens the App Store's write-review page, never the system prompt.
    public static func openWriteReview() {
        guard let url = ReviewPromptLinks.writeReviewURL() else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
