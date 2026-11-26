import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ChatUI
import InputTextView
import Localization
import ShortPeerRow
import TelegramUtils
import InputView
import InputDataUI



final class StoryPremRequiredInput : Control, StoryInput {
    func like(_ like: StoryReactionAction, resetIfNeeded: Bool) {
        
    }
    
    
    private let textView: TextView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isSelectable = false
        addSubview(textView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private var arguments: StoryArguments?
    
    func setArguments(_ arguments: StoryArguments?, groupId: PeerId?) {
        self.arguments = arguments
    }
    
    func update(_ story: StoryContentItem, animated: Bool) {
        let text = strings().storyInputPremiumRequiredState(story.peer?._asPeer().compactDisplayTitle ?? "")
        
        guard let context = self.arguments?.context else {
            return
        }
        
        let parsed = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes.init(body: MarkdownAttributeSet(font: .normal(.text), textColor: darkAppearance.colors.text), bold: MarkdownAttributeSet(font: .medium(.text), textColor: darkAppearance.colors.text), link: MarkdownAttributeSet(font: .medium(.text), textColor: darkAppearance.colors.link), linkAttribute: { link in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(link, { value in
                if value == "premium" {
                    FeatureNavigationHooks.shared.showPremiumBoarding(context, context.window, nil, false, darkAppearance)
                }
            }))
        })).detectBold(with: .medium(.text))
        
        let layout = TextViewLayout(parsed)
        layout.measure(width: frame.width)
        layout.interactions = LinkHooks.shared.globalLinkExecutor()
        self.textView.update(layout)
        
    }
    
    func updateState(_ state: StoryInteraction.State, animated: Bool) {
       
    }
    
    func updateInputText(_ state: ChatTextInputState, prevState: ChatTextInputState, animated: Bool) {
        
    }
    
    func updateInputState(animated: Bool) {
        guard let superview = self.superview else {
            return
        }
        updateInputSize(size: NSMakeSize(superview.frame.width, 30), animated: animated)
    }
    
    func installInputStateUpdate(_ f: ((StoryInputState) -> Void)?) {
        
    }
    
    
    func resetInputView() {
        
    }
    
    func updateInputContext(with result: ChatPresentationInputQueryResult?, context: InputContextHelper, animated: Bool) {
        
    }
    
    var isFirstResponder: Bool {
        return false
    }
    
    var text: UITextView? {
        return nil
    }
    
    var input: NSTextView? {
        return nil
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: textView, frame: textView.centerFrame())
    }
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
}
