#if canImport(AppKit)
import AppKit
import RichTextEditorCore
import SwiftMath

/// An inline math-formula attachment: renders the LaTeX to an image via SwiftMath and sits it on the text
/// baseline using the math ascent/descent. The same renderer the chat (`InstantPageMath`/`MTMathRenderer`)
/// uses, so editor formulas match the chat pixel-for-pixel. Unlike the animated custom-emoji attachment,
/// a formula is a STATIC image, so TextKit's fragment drawing renders it directly — no hosted view needed.
@available(macOS 12, *)
final class FormulaTextAttachment: NSTextAttachment {
    let latex: String
    private let imageSize: CGSize
    /// Distance from the image's bottom to the math baseline (so the attachment can sit on the text baseline).
    private let descent: CGFloat

    init?(latex: String, fontSize: CGFloat, color: NSColor) {
        guard !latex.isEmpty,
              let r = MTMathRenderer.render(latex: latex, fontSize: fontSize, textColor: color, mode: .text)
        else { return nil }
        self.latex = latex
        self.imageSize = r.size
        self.descent = r.descent
        super.init(data: nil, ofType: nil)
        self.image = r.image
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: NSTextLocation,
                                   textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        // Image height = ascent + descent; lowering the bottom by `descent` lands the math baseline on the text baseline.
        return CGRect(x: 0, y: -descent, width: imageSize.width, height: imageSize.height)
    }
}
#endif
