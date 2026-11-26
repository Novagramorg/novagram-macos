import Foundation

public enum AboutFeatureInAppLink {
    case callback(String, (String) -> Void)
    case other
}

public protocol AboutFeatureInAppLinkValue {
    var aboutFeatureInAppLink: AboutFeatureInAppLink { get }
}
