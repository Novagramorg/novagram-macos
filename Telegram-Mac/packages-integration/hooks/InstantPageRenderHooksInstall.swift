import Cocoa
import SwiftMath
import InstantPageUI

func installInstantPageRenderHooks() {
    InstantPageRenderHooks.install(InstantPageRenderHooks(renderMath: { latex, fontSize, textColor, mode, authoring in
        let renderMode: MTMathUILabelMode
        switch mode {
        case .inline:
            renderMode = .text
        case .block:
            renderMode = .display
        }
        let rendered = authoring ? MTMathRenderer.renderForAuthoring(latex: latex, fontSize: fontSize, textColor: textColor, mode: renderMode) : MTMathRenderer.render(latex: latex, fontSize: fontSize, textColor: textColor, mode: renderMode)
        guard let rendered else {
            return nil
        }
        return InstantPageMathRenderResult(image: rendered.image, size: rendered.size, width: rendered.width, ascent: rendered.ascent, descent: rendered.descent)
    }, detectLinks: { attributedString in
        attributedString.detectLinks(type: [.Links], context: nil, openInfo: { _, _, _, _ in }, hashtag: nil, command: nil, applyProxy: nil, dotInMention: false)
    }))
}
