import Cocoa
import TGUIKit

public protocol ScreenCaptureInAppLink {
    var link: String { get }
}

public struct ScreenCaptureUIHooks {
    public let groupCallWindowBackground: () -> NSColor
    public let groupCallGrayStatusColor: () -> NSColor
    public let groupCallTitleColor: () -> NSColor
    public let groupCallAccent: () -> NSColor
    public let groupCallSecondary: () -> NSColor

    public init(groupCallWindowBackground: @escaping () -> NSColor,
                groupCallGrayStatusColor: @escaping () -> NSColor,
                groupCallTitleColor: @escaping () -> NSColor,
                groupCallAccent: @escaping () -> NSColor,
                groupCallSecondary: @escaping () -> NSColor) {
        self.groupCallWindowBackground = groupCallWindowBackground
        self.groupCallGrayStatusColor = groupCallGrayStatusColor
        self.groupCallTitleColor = groupCallTitleColor
        self.groupCallAccent = groupCallAccent
        self.groupCallSecondary = groupCallSecondary
    }

    private static var _shared: ScreenCaptureUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ScreenCaptureUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ScreenCaptureUIHooks.install must be called before the screen capture picker is used")
        return .placeholder
    }

    public static func install(_ hooks: ScreenCaptureUIHooks) {
        assert(Thread.isMainThread, "ScreenCaptureUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ScreenCaptureUIHooks(groupCallWindowBackground: {
        NSColor.black
    }, groupCallGrayStatusColor: {
        NSColor.gray
    }, groupCallTitleColor: {
        NSColor.white
    }, groupCallAccent: {
        NSColor.blue
    }, groupCallSecondary: {
        NSColor.gray
    })
}
