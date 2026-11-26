import Cocoa
import TGUIKit

public struct DateSelectorHooks {
    public let showPremiumBoarding: (Window) -> Void

    public init(showPremiumBoarding: @escaping (Window) -> Void) {
        self.showPremiumBoarding = showPremiumBoarding
    }

    public static var shared: DateSelectorHooks = DateSelectorHooks(showPremiumBoarding: { _ in })
}

public func installDateSelectorHooks(_ hooks: DateSelectorHooks) {
    DateSelectorHooks.shared = hooks
}
