import Foundation

struct LiquidGlassSurfaceReleasePolicy {
    var releasesWhenHidden: Bool
    private(set) var isInWindow: Bool = false

    init(releasesWhenHidden: Bool) {
        self.releasesWhenHidden = releasesWhenHidden
    }

    mutating func update(isInWindow: Bool) -> Bool {
        self.isInWindow = isInWindow
        return !isInWindow && self.releasesWhenHidden
    }

    var releasesNow: Bool {
        return self.releasesWhenHidden && !self.isInWindow
    }
}
