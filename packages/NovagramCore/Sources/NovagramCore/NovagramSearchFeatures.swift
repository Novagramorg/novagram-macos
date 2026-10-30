import Foundation
import SwiftSignalKit

public enum NovagramSearchFeatures {
    public static let key = "novagram_search_features"

    private static let suiteName = "pro_messager"

    public static var isEnabled: Bool {
        get {
            guard let defaults = UserDefaults(suiteName: suiteName), defaults.object(forKey: key) != nil else {
                return true
            }
            return defaults.bool(forKey: key)
        }
        set {
            UserDefaults(suiteName: suiteName)?.set(newValue, forKey: key)
        }
    }

    public static func signal() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            subscriber.putNext(isEnabled)
            let observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { _ in
                subscriber.putNext(isEnabled)
            })
            return ActionDisposable {
                NotificationCenter.default.removeObserver(observer)
            }
        } |> distinctUntilChanged
    }
}
