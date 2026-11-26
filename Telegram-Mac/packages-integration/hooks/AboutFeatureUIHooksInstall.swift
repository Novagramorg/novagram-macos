import Cocoa
import AboutFeatureUI

extension inAppLink: AboutFeatureInAppLinkValue {
    var aboutFeatureInAppLink: AboutFeatureInAppLink {
        return mapAboutFeatureInAppLink(self)
    }
}

private func mapAboutFeatureInAppLink(_ link: inAppLink) -> AboutFeatureInAppLink {
    switch link {
    case let .callback(contents, handler):
        return .callback(contents, handler)
    default:
        return .other
    }
}
