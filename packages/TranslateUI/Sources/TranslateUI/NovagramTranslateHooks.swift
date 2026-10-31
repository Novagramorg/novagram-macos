import Foundation

// Set by the app (NovagramHooksInstall): a message translation finished with a result.
public enum NovagramTranslateHooks {
    public static var didTranslateMessage: () -> Void = {}
}
