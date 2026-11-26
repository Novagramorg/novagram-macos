import Cocoa
import TGUIKit
import CallsUI

func installScreenCaptureUIHooks() {
    ScreenCaptureUIHooks.install(ScreenCaptureUIHooks(groupCallWindowBackground: {
        return GroupCallTheme.windowBackground
    }, groupCallGrayStatusColor: {
        return GroupCallTheme.grayStatusColor
    }, groupCallTitleColor: {
        return GroupCallTheme.titleColor
    }, groupCallAccent: {
        return GroupCallTheme.accent
    }, groupCallSecondary: {
        return GroupCallTheme.secondary
    }))
}

extension inAppLink: ScreenCaptureInAppLink {}
