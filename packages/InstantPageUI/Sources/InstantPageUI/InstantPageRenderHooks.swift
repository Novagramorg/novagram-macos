import Cocoa

public struct InstantPageRenderHooks {
    public let renderMath: (String, CGFloat, NSColor, InstantPageMathMode, Bool) -> InstantPageMathRenderResult?
    public let detectLinks: (NSMutableAttributedString) -> Void

    public init(renderMath: @escaping (String, CGFloat, NSColor, InstantPageMathMode, Bool) -> InstantPageMathRenderResult?,
                detectLinks: @escaping (NSMutableAttributedString) -> Void) {
        self.renderMath = renderMath
        self.detectLinks = detectLinks
    }

    private static var value: InstantPageRenderHooks?
    public static var shared: InstantPageRenderHooks {
        guard let value = value else {
            preconditionFailure("InstantPageRenderHooks not installed")
        }
        return value
    }
    public static func install(_ hooks: InstantPageRenderHooks) {
        self.value = hooks
    }
}
