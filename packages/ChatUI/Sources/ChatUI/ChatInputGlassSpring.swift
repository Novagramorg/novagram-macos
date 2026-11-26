import Cocoa

enum ChatInputGlassSpring {
    static func animate(_ changes: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 1.35, 0.5, 1.0)
            context.allowsImplicitAnimation = true
            changes()
        }
    }
}
