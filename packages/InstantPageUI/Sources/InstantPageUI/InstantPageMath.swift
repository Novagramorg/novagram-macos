import Cocoa
import TelegramTheme
import TelegramUtils
import TelegramContext

public enum InstantPageMathMode {
    case inline
    case block
}

public struct InstantPageMathRenderResult {
    public let image: NSImage
    public let size: CGSize
    public let width: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
    public init(image: NSImage, size: CGSize, width: CGFloat, ascent: CGFloat, descent: CGFloat) {
        self.image = image
        self.size = size
        self.width = width
        self.ascent = ascent
        self.descent = descent
    }
}

public final class InstantPageMathAttachment: NSObject {
    public let latex: String
    public let fontSize: CGFloat
    public let textColor: NSColor
    public let mode: InstantPageMathMode
    public let rendered: InstantPageMathRenderResult

    public init(latex: String, fontSize: CGFloat, textColor: NSColor, mode: InstantPageMathMode, rendered: InstantPageMathRenderResult) {
        self.latex = latex
        self.fontSize = fontSize
        self.textColor = textColor
        self.mode = mode
        self.rendered = rendered
    }

    public func isEqual(to other: InstantPageMathAttachment) -> Bool {
        return self.latex == other.latex
            && self.fontSize == other.fontSize
            && self.mode == other.mode
            && self.textColor.isEqual(other.textColor)
            && self.rendered.size == other.rendered.size
            && self.rendered.ascent == other.rendered.ascent
            && self.rendered.descent == other.rendered.descent
    }
}

public func instantPageMathAttachment(latex: String, fontSize: CGFloat, textColor: NSColor, mode: InstantPageMathMode) -> InstantPageMathAttachment? {
    return makeInstantPageMathAttachment(latex: latex, fontSize: fontSize, textColor: textColor, mode: mode, authoring: false)
}

public func instantPageMathAttachmentForAuthoring(latex: String, fontSize: CGFloat, textColor: NSColor, mode: InstantPageMathMode) -> InstantPageMathAttachment? {
    return makeInstantPageMathAttachment(latex: latex, fontSize: fontSize, textColor: textColor, mode: mode, authoring: true)
}

private func makeInstantPageMathAttachment(latex: String, fontSize: CGFloat, textColor: NSColor, mode: InstantPageMathMode, authoring: Bool) -> InstantPageMathAttachment? {
    let multiplier: CGFloat = 1.12
    let effectiveFontSize = fontSize * multiplier
    guard let rendered = InstantPageRenderHooks.shared.renderMath(latex, effectiveFontSize, textColor, mode, authoring) else {
        return nil
    }
    return InstantPageMathAttachment(latex: latex, fontSize: effectiveFontSize, textColor: textColor, mode: mode, rendered: rendered)
}
