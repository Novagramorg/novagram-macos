import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import ChatHistoryModel
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils



public class ChatCommentsHeaderItem : TableStickItem {
    
    private let entry:ChatHistoryEntry
    fileprivate let chatInteraction:ChatInteraction?
    public let isBubbled: Bool
    public let layout:TextViewLayout
    public let presentation: TelegramPresentationTheme
    public init(_ initialSize:NSSize, _ entry:ChatHistoryEntry, interaction: ChatInteraction, theme: TelegramPresentationTheme) {
        self.entry = entry
        self.isBubbled = entry.renderType == .bubble
        self.chatInteraction = interaction
        self.presentation = theme
        
        let text: String
        switch entry {
        case let .commentsHeader(empty, _, _):
            if interaction.mode.isTopicMode {
                if empty {
                    text = strings().chatTopicHeaderEmpty
                } else {
                    text = strings().chatTopicHeaderFull
                }
            } else {
                if empty {
                    text = strings().chatCommentsHeaderEmpty
                } else {
                    text = strings().chatCommentsHeaderFull
                }
            }
            
        default:
            text = ""
        }
        
        self.layout = TextViewLayout(.initialize(string: text, color: theme.chatServiceItemTextColor, font: .medium(theme.fontSize)), maximumNumberOfLines: 1, truncationType: .end, alignment: .center)
        
        
        super.init(initialSize)
    }
    
    public var shouldBlurService: Bool {
        if TelegramUtilsHooks.shared.isLite(.blur) {
            return false
        }
        return presentation.shouldBlurService
    }
    
    public override var canBeAnchor: Bool {
        return false
    }
    
    public required init(_ initialSize: NSSize) {
        entry = .commentsHeader(true, MessageIndex.absoluteLowerBound(), .list)
        self.isBubbled = false
        self.layout = TextViewLayout(NSAttributedString())
        self.chatInteraction = nil
        self.presentation = theme
        super.init(initialSize)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        layout.measure(width: width - 40)
        return success
    }
    
    public override var stableId: AnyHashable {
        return entry.stableId
    }
    
    public override var height: CGFloat {
        return 30
    }
    
    public override func viewClass() -> AnyClass {
        return ChatCommentsHeaderView.self
    }
    
    
}

public class ChatCommentsHeaderView : TableRowView {
    private let textView:TextView
    private let containerView: Control = Control()
    public required init(frame frameRect: NSRect) {
        self.textView = TextView()
        self.textView.isSelectable = false
        self.containerView.wantsLayer = true
        self.containerView.isAccessibilityDecorative = true
        self.textView.disableBackgroundDrawing = true
        super.init(frame: frameRect)
        addSubview(textView)
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    
    public override func updateColors() {
        super.updateColors()
        guard let item = item as? ChatCommentsHeaderItem else {
            return
        }
        if item.shouldBlurService {
            textView.blurBackground = theme.blurServiceColor
            textView.backgroundColor = .clear
        } else {
            textView.backgroundColor = theme.chatServiceItemColor
            textView.blurBackground = nil
        }
    }
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
    }
    
    public override func layout() {
        super.layout()
        textView.center()
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        if let item = item as? ChatCommentsHeaderItem {
            textView.update(item.layout)
            textView.setFrameSize(item.layout.layoutSize.width + 16, item.layout.layoutSize.height + 6)
            textView.layer?.cornerRadius = textView.frame.height / 2
            self.needsLayout = true
        }
        super.set(item: item, animated:animated)
    }
}
