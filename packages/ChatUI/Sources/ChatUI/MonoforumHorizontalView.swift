import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Cocoa
import Localization
import TelegramTheme
import TelegramUtils
import GeneralRows
import InlineStickerLayer

public class MonoforumHorizontalView : View {
    private let segmentView: ScrollableSegmentView = ScrollableSegmentView(frame: NSZeroRect)
    private let toggleButton = ImageButton()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toggleButton.autohighlight = false
        toggleButton.animates = false
        toggleButton.scaleOnClick = true
        toggleButton.setAccessibilityLabel(strings().voiceOverChatSwitchTopicsView)
        addSubview(toggleButton)
        addSubview(segmentView)
        layout()

        updateLocalizationAndTheme(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)

        self.backgroundColor = .clear
        segmentView.backgroundColor = .clear
        segmentView.scrollView.background = .clear
        
        let segmentTheme = ScrollableSegmentTheme(background: .clear, border: .clear, selector: theme.colors.accent, inactiveText: theme.colors.text, activeText: theme.colors.accent, textFont: .normal(.title))
        
        segmentView.theme = segmentTheme

    }
    
    
    public func set(items: [MonoforumItem], selected: Int64?, chatInteraction: ChatInteraction, animated: Bool) {

        toggleButton.set(image: TelegramThemeHooks.shared.image(.iconMonoforumToggle).precomposed(theme.colors.text), for: .Normal)
        toggleButton.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
        toggleButton.setSingle(handler: { [weak chatInteraction] _ in
            chatInteraction?.toggleMonoforumState()
        }, for: .Click)

        let presentation = theme
        let context = chatInteraction.context
        let peerId = chatInteraction.peerId
        
        let segmentTheme = ScrollableSegmentTheme(background: .clear, border: .clear, selector: presentation.colors.accent, inactiveText: presentation.colors.text, activeText: presentation.colors.accent, textFont: .normal(.title))
        
        segmentView.theme = segmentTheme
        
        var index: Int = 0
        let insets = NSEdgeInsets(left: 10, right: 10, top: 3, bottom: 5)
        var _items:[ScrollableSegmentItem] = []
        
        
//        _items.append(.init(title: "", index: index, uniqueId: -1, selected: false, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: segmentTheme, equatable: nil))
//        index += 1
//        
//        _items.append(.init(title: "", index: index, uniqueId: -1, selected: false, insets: NSEdgeInsets(left: 15, right: 15), icon: NSImage(resource: .iconMonoforumToggle).precomposed(theme.colors.grayIcon), theme: segmentTheme, equatable: nil))
//        index += 1
        
             
        if let user = chatInteraction.presentation.mainPeer as? TelegramUser, let botInfo = user.botInfo, botInfo.flags.contains(.hasForum), botInfo.flags.contains(.forumManagedByUser) {
            _items.append(.init(
                title: strings().chatMonoforumNewChat,
                index: index,
                uniqueId: 0,
                selected: selected == nil || selected == Message.newTopicThreadId,
                insets: NSEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 10),
                icon: nil,
                theme: segmentTheme,
                equatable: .init(selected)
            ))
            index += 1
        } else {
            _items.append(.init(title: strings().chatMonoforumUIAllTab, index: index, uniqueId: 0, selected: selected == nil, insets: NSEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 10), icon: nil, theme: segmentTheme, equatable: .init(selected)))
            index += 1
        }
        
        let generateIcon:(MonoforumItem)->CGImage? = { tab in
            let icon: CGImage?
            if let item = tab.item, let unreadCount = item.readCounters?.count, unreadCount > 0 {
                
                
                let unreadCount = Int(unreadCount)
                
                let textColor: NSColor
                textColor = .white

                
                let attributedString = NSAttributedString.initialize(string: "\(unreadCount.prettyNumber)", color: textColor, font: .medium(.short))
                let textLayout = TextNode.layoutText(maybeNode: nil,  attributedString, nil, 1, .start, NSMakeSize(CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude), nil, false, .center)
                var size = NSMakeSize(textLayout.0.size.width + 8, textLayout.0.size.height + 5)
                size = NSMakeSize(max(size.height,size.width), size.height)
                let badge = generateImage(size, rotatedContext: { size, ctx in
                    let rect = NSMakeRect(0, 0, size.width, size.height)
                    ctx.clear(rect)
                    
                    // Outer background
                    ctx.setFillColor(theme.colors.background.cgColor)
                    let outerPath = CGMutablePath()
                    outerPath.addRoundedRect(in: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2)
                    outerPath.closeSubpath()
                    ctx.addPath(outerPath)
                    ctx.fillPath()
                    
                    // Inner fill
                    let insetRect = rect.insetBy(dx: 1, dy: 1)
                    ctx.setFillColor(item.isMuted ? theme.colors.grayIcon.cgColor : theme.colors.accentIcon.cgColor)
                    let innerPath = CGMutablePath()
                    innerPath.addRoundedRect(in: insetRect, cornerWidth: insetRect.height / 2, cornerHeight: insetRect.height / 2)
                    innerPath.closeSubpath()
                    ctx.addPath(innerPath)
                    ctx.fillPath()

                    // Text
                    let focus = rect.focus(textLayout.0.size)
                    textLayout.1.draw(
                        focus.offsetBy(dx: 0, dy: -1),
                        in: ctx,
                        backingScaleFactor: System.backingScale,
                        backgroundColor: .white
                    )
                })!

                icon = badge
            } else if tab.item?.chatListIndex.pinningIndex != nil || tab.item?.threadData?.isClosed == true {
                let pinned = TelegramThemeHooks.shared.image(.iconMonoforumPin).precomposed(theme.colors.background, flipVertical: true)
                
                var icons: [CGImage] = []
                if tab.item?.chatListIndex.pinningIndex != nil {
                    icons.append(pinned)
                }
                let spacing: CGFloat = 1
                let paddingHorizontal: CGFloat = 4
                let paddingVertical: CGFloat = 2

                let iconHeight = icons.map { $0.backingSize.height }.max() ?? 0
                let iconWidths = icons.map { $0.backingSize.width }
                let totalWidth = iconWidths.reduce(0, +) + CGFloat(max(0, icons.count - 1)) * spacing

                let badgeSize = NSSize(width: totalWidth + paddingHorizontal * 2,
                                       height: iconHeight + paddingVertical * 2 + 2)

                let badge = generateImage(badgeSize, rotatedContext: { size, ctx in
                    let rect = NSMakeRect(0, 0, size.width, size.height)
                    ctx.clear(rect)

                    // Outer background
                    ctx.setFillColor(theme.colors.background.cgColor)
                    let outerPath = CGMutablePath()
                    outerPath.addRoundedRect(in: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2)
                    outerPath.closeSubpath()
                    ctx.addPath(outerPath)
                    ctx.fillPath()

                    // Inner fill
                    let insetRect = rect.insetBy(dx: 1, dy: 1)
                    ctx.setFillColor(theme.colors.badgeMuted.cgColor)
                    let innerPath = CGMutablePath()
                    innerPath.addRoundedRect(in: insetRect, cornerWidth: insetRect.height / 2, cornerHeight: insetRect.height / 2)
                    innerPath.closeSubpath()
                    ctx.addPath(innerPath)
                    ctx.fillPath()

                    // Draw icons
                    var x = paddingHorizontal
                    for (index, icon) in icons.enumerated() {
                        let y = (size.height - icon.backingSize.height) / 2
                        ctx.draw(icon, in: NSRect(x: x, y: y, width: icon.backingSize.width, height: icon.backingSize.height))
                        x += icon.backingSize.width
                        if index < icons.count - 1 {
                            x += spacing
                        }
                    }
                })!

                icon = badge
            } else {
                icon = nil
            }
            return icon
        }

        struct Tuple : Equatable {
            let item: MonoforumItem
            let selected: Bool
        }
        
        for tab in items {
            let title: String = tab.title
            let selected = selected == tab.uniqueId
            
            let tuple = Tuple(item: tab, selected: selected)
            
            let icon = generateIcon(tab)
           
            _items.append(ScrollableSegmentItem(title: title, index: index, uniqueId: tab.uniqueId, selected: selected, insets: insets, icon: icon, theme: segmentTheme, equatable: .init(tuple), customTextView: {
                
                let attr = NSMutableAttributedString()
                attr.append(string: "\(clown_space)" + title, color: selected ? segmentTheme.activeText : segmentTheme.inactiveText, font: segmentTheme.textFont)
                
                switch tab.mediaItem(selected: selected) {
                case let .topic(fileId):
                    if fileId == 0, let info = tab.item?.threadData?.info {
                        let file = ChatInterfaceHooks.shared.makeTopicIconFile(info.title, info.iconColor, tab.uniqueId == 1)
                        attr.insertEmbedded(.embeddedAnimated(file, playPolicy: .framesCount(1)), for: clown)
                    } else {
                        attr.insertEmbedded(.embeddedAnimated(fileId, playPolicy: .framesCount(1)), for: clown)
                    }
                case let .avatar(peer):
                    attr.insertEmbedded(.embeddedAvatar(peer), for: clown)
                default:
                    break
                }
                
                

                let layout = TextViewLayout(attr)
                layout.measure(width: .greatestFiniteMagnitude)

                let textView = InteractiveTextView()
                textView.userInteractionEnabled = false
                textView.textView.isSelectable = false
                textView.set(text: layout, context: context)
                
                return textView
            }))
            index += 1
        }
        
        _items.append(.init(title: "", index: index, uniqueId: -3, selected: false, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: segmentTheme, equatable: nil))
        index += 1
        
        segmentView.updateItems(_items, animated: animated)
        
        segmentView.menuItems = { [weak chatInteraction] item in
            guard let chatInteraction else {
                return .single([])
            }
            
            if item.uniqueId >= 1 {
                return chatInteraction.monoforumMenuItems(items[item.index - 1])
            } else {
                return .single([])
            }
        }
        
        var sortRange: NSRange = NSMakeRange(NSNotFound, 1)
        
        var pinned: [Int64] = []
        let offsetIndex = 3
        
        for (i, item) in items.enumerated() {
            if let _ = item.pinnedIndex {
                pinned.append(item.uniqueId)
                if sortRange.location == NSNotFound {
                    sortRange.location = i + offsetIndex
                } else {
                    sortRange.length += 1
                }
            }
        }
        
        segmentView.resortRange = sortRange
        segmentView.resortHandler = { fromIndex, toIndex in
            pinned.move(at: fromIndex - offsetIndex, to: toIndex - offsetIndex)
            _ = context.engine.peers.setForumChannelPinnedTopics(id: peerId, threadIds: pinned).start()
        }
        
        segmentView.didChangeSelectedItem = { [weak chatInteraction] item in
            if item.uniqueId == 0 || item.uniqueId > 0 {
                chatInteraction?.updateChatLocationThread(item.uniqueId == 0 ? nil : item.uniqueId)
            } else if item.uniqueId == -1 {
                chatInteraction?.toggleMonoforumState()
            }
        }
        
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: toggleButton, frame: NSMakeRect(0, 0, 40, size.height))
        segmentView.frame = NSMakeRect(40, 0, size.width - 40, size.height)
    }
}
