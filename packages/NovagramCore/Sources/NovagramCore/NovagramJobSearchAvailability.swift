import Foundation
import SwiftSignalKit

public enum NovagramJobSearchAvailability {
    public static let key = "novagram_search_features"

    public static var isEnabled: Bool {
        guard let defaults = UserDefaults(suiteName: "pro_messager"), defaults.object(forKey: key) != nil else {
            return true
        }
        return defaults.bool(forKey: key)
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
