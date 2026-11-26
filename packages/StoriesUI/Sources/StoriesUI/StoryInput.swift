import Cocoa
import TGUIKit
import TGModernGrowingTextView
import SwiftSignalKit
import Postbox
import TelegramCore
import ColorPalette
import InputView
import TelegramMedia
import TelegramMediaResources
import FoundationUtils
import ChatUI
import InputTextView
import ShortPeerRow
import TelegramTheme
import TelegramUtils

protocol StoryInput {
    func setArguments(_ arguments: StoryArguments?, groupId: PeerId?) -> Void
    func updateState(_ state: StoryInteraction.State, animated: Bool) -> Void
    func updateInputText(_ state: ChatTextInputState, prevState: ChatTextInputState, animated: Bool) -> Void
    func updateInputState(animated: Bool)
    func installInputStateUpdate(_ f: ((StoryInputState)->Void)?) -> Void
    func resetInputView()
    func updateInputContext(with result:ChatPresentationInputQueryResult?, context: InputContextHelper, animated:Bool)
    func like(_ like: StoryReactionAction, resetIfNeeded: Bool)

    func update(_ story: StoryContentItem, animated: Bool)
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition)
    
    var isFirstResponder: Bool { get }
    var text: UITextView? { get }
    var input: NSTextView? { get }
}

extension StoryInput where Self: NSView {
    func updateInputSize(size: NSSize, animated: Bool) {
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        guard let superview = superview, let window = self.window else {
            return
        }
        
        let wSize = NSMakeSize(window.frame.width - 100, superview.frame.height - 110)
        let aspect = StoryLayoutView.size.aspectFitted(wSize)

        transition.updateFrame(view: self, frame: CGRect(origin: CGPoint(x: floorToScreenPixels(backingScaleFactor,  (superview.frame.width - size.width) / 2), y: aspect.height + 10 - size.height + 30), size: size))
        self.updateLayout(size: size, transition: transition)
    }
    
    func applyStoryInput(_ arguments: StoryArguments?, groupId: PeerId?, textView: UITextView) {
        let color = NSColor(rgb: 0xffffff)
        var colors: PeerNameColors.Colors = .init(main: color)
        if let arguments = arguments, let nameColor = arguments.context.myPeer?.namePeerColor {
            let peerColors = arguments.context.peerNameColors.get(nameColor)
            if peerColors.secondary != nil && peerColors.tertiary != nil {
                colors = .init(main: color, secondary: color.withAlphaComponent(0.2), tertiary: color.withAlphaComponent(0.2))
            } else if peerColors.secondary != nil {
                colors = .init(main: color, secondary: color.withAlphaComponent(0.2), tertiary: nil)
            }
        }
        textView.context = arguments?.context
        textView.inputTheme = .init(quote: .init(foreground: colors, icon: TelegramThemeHooks.shared.image(.iconQuote), collapse: TelegramThemeHooks.shared.image(.iconQuoteCollapse), expand: TelegramThemeHooks.shared.image(.iconQuoteExpand)), indicatorColor: darkAppearance.inputTheme.indicatorColor, backgroundColor: darkAppearance.inputTheme.backgroundColor, selectingColor: darkAppearance.inputTheme.selectingColor, textColor: darkAppearance.inputTheme.textColor, accentColor: darkAppearance.inputTheme.accentColor, grayTextColor: darkAppearance.inputTheme.grayTextColor, fontSize: darkAppearance.inputTheme.fontSize)
        self.updateInputState(animated: true)
        
        if let input = arguments?.interaction.presentation.findInput(groupId) {
            textView.set(input)
        }
        if let arguments = arguments {
            self.updateState(arguments.interaction.presentation, animated: false)
        }
        self.layer?.masksToBounds = false
    }
}
