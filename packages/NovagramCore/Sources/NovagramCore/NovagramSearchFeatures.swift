import Foundation
import SwiftSignalKit
import NovagramSearchKit

public enum NovagramSearchFeatures {
    public static let key = NovagramSearchSettings.Keys.searchFeatures

    public static var isEnabled: Bool {
        get {
            return NovagramSearchSettings.shared.isSearchFeaturesEnabled
        }
        set {
            NovagramSearchSettings.shared.isSearchFeaturesEnabled = newValue
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
