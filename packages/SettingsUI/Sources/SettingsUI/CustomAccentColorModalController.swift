import Cocoa
import TGUIKit
import TelegramCore
import ColorPalette
import Postbox
import SwiftSignalKit
import InAppSettings
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import FoundationUtils
import TelegramMediaUtils
import TelegramLinks
import ThemeSettings
import ChatHistoryModel
import FilePanels
import WallpaperUI

private final class CustomAccentColorView : View {
    private let tableView: TableView = TableView(frame: NSZeroRect, isFlipped: false)
    public weak var controller: ModalViewController?
    public let colorPicker = WallpaperColorPickerContainerView(frame: NSZeroRect)
    private let context: any AccountContextProtocol
    private let backgroundView = BackgroundView(frame: .zero)
    fileprivate let segmentControl = CatalinaStyledSegmentController(frame: NSMakeRect(0, 0, 290, 30))
    private let segmentContainer = View()

    public required init(frame frameRect: NSRect, theme: TelegramPresentationTheme, context: any AccountContextProtocol) {
        self.context = context
        super.init(frame: frameRect)
        self.addSubview(backgroundView)
        self.addSubview(tableView)
        self.addSubview(colorPicker)
        colorPicker.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        colorPicker.colorPicker.color = theme.colors.accent
        
       
        
        tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            guard let `self` = self else {
                return
            }
            self.tableView.enumerateVisibleViews(with: { view in
                if let view = view as? AppearanceChatPreviewRowView {
                    view.updateBackground(animated: false, item: view.item)
                }
            })
        }))
        
        if theme.bubbled {
            backgroundView.backgroundMode = theme.backgroundMode
        } else {
            backgroundView.backgroundMode = .color(color: theme.colors.chatBackground)
        }
        
        segmentContainer.backgroundColor = theme.colors.background
        
        segmentContainer.addSubview(segmentControl.view)
        self.addSubview(segmentContainer)
        
        

    }
    
    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let contentHeight = frame.height - (controller?.modalInteractions?.height ?? 0)

        transition.updateFrame(view: backgroundView, frame: NSMakeRect(0, 50, frame.width, contentHeight - 160))
        backgroundView.updateLayout(size: NSMakeSize(frame.width, contentHeight - 160), transition: transition)

        transition.updateFrame(view: tableView, frame: NSMakeRect(0, 50, frame.width, contentHeight - 160 - 50))

        transition.updateFrame(view: colorPicker, frame: NSMakeRect(0, contentHeight - 160, frame.width, 160))
        colorPicker.updateLayout(size: NSMakeSize(frame.width, 160), transition: transition)
        
        transition.updateFrame(view: segmentContainer, frame: NSMakeRect(0, 0, frame.width, 50))
        transition.updateFrame(view: segmentControl.view, frame: segmentControl.view.centerFrame())

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    fileprivate func addTableItems(_ context: any AccountContextProtocol, theme: TelegramPresentationTheme) {
        
        segmentContainer.backgroundColor = theme.colors.background
        segmentContainer.borderColor = theme.colors.border
        segmentContainer.border = [.Bottom]
        segmentControl.theme = CatalinaSegmentTheme(backgroundColor: theme.colors.listBackground, foregroundColor: theme.colors.background, activeTextColor: theme.colors.text, inactiveTextColor: theme.colors.listGrayText)

        
        tableView.removeAll()
        self.tableView.getBackgroundColor = {
            .clear
        }
        _ = tableView.addItem(item: GeneralRowItem(frame.size, height: 10, stableId: arc4random(), backgroundColor: .clear))

        
        let chatInteraction = SettingsHooks.shared.makeChatPreviewContext(context, PeerId(0), false)
        
        chatInteraction.getGradientOffsetRect = { [weak self] in
            guard let `self` = self else {
                return .zero
            }
            let offset = self.tableView.scrollPosition().current.rect.origin
            return CGRect(origin: offset, size: self.tableView.frame.size)
        }
        
        let fromUser1 = TelegramUser(id: PeerId(1), accessHash: nil, firstName: strings().appearanceSettingsChatPreviewUserName1, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        
        let fromUser2 = TelegramUser(id: PeerId(2), accessHash: nil, firstName: strings().appearanceSettingsChatPreviewUserName2, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        
        
        
        let firstMessage = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 1), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: 60 * 18 + 60*60*18, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser1, text: strings().appearanceSettingsChatPreview1, attributes: [], media: [], peers:SimpleDictionary([fromUser2.id : fromUser2, fromUser1.id : fromUser1]) , associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        
        let firstEntry: ChatHistoryEntry = .MessageEntry(firstMessage, MessageIndex(firstMessage), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
        
        
        let timestamp1: Int32 = 60 * 20 + 60 * 60 * 18

        let secondMessage = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 0), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: timestamp1, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser2, text: strings().appearanceSettingsChatPreview2, attributes: [ReplyMessageAttribute(messageId: firstMessage.id, threadMessageId: nil, quote: nil, isQuote: false, innerSubject: nil)], media: [], peers:SimpleDictionary([fromUser2.id : fromUser2, fromUser1.id : fromUser1]) , associatedMessages: SimpleDictionary([firstMessage.id : firstMessage]), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        
        let secondEntry: ChatHistoryEntry = .MessageEntry(secondMessage, MessageIndex(secondMessage), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
        
        let timestamp2: Int32 = 60 * 22 + 60 * 60 * 18
        
        let thridMessage = Message(stableId: 2, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 1), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: timestamp2, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser1, text: strings().appearanceSettingsChatPreview3, attributes: [], media: [], peers:SimpleDictionary([fromUser2.id : fromUser2, fromUser1.id : fromUser1]) , associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        
        let thridEntry: ChatHistoryEntry = .MessageEntry(thridMessage, MessageIndex(thridMessage), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
        
        
        let item1 = SettingsHooks.shared.makeChatPreviewItem(frame.size, chatInteraction, firstEntry, theme)
        let item2 = SettingsHooks.shared.makeChatPreviewItem(frame.size, chatInteraction, secondEntry, theme)
        let item3 = SettingsHooks.shared.makeChatPreviewItem(frame.size, chatInteraction, thridEntry, theme)
        
        let items = [item1, item2, item3]
        for item in items {
            _ = item.makeSize(frame.width, oldWidth: 0)
            _ = self.tableView.addItem(item: item)
        }

    }
    
    public func updateMode(_ mode: WallpaperColorSelectMode, newTheme: TelegramPresentationTheme) {
        self.colorPicker.colorPicker.needsLayout = true
        self.addTableItems(self.context, theme: newTheme)
        self.tableView.updateLocalizationAndTheme(theme: newTheme)
        self.controller?.updateLocalizationAndTheme(theme: newTheme)
        self.colorPicker.updateLocalizationAndTheme(theme: newTheme)
        self.updateLocalizationAndTheme(theme: newTheme)
        self.colorPicker.updateMode(mode, animated: true)

    }
    
}


public class CustomAccentColorModalController: ModalViewController {

    public override var defaultBarTitle: String {
        return localizedString("Telegram.CustomAccentColorModalController")
    }

    public enum SelectMode {
        case accent
        case messages
    }
    
    private var selectMode: SelectMode = .accent
    
    private let context: any AccountContextProtocol
    private let updateColor: (PaletteAccentColor)->Void
    public init(context: any AccountContextProtocol, updateColor: @escaping(PaletteAccentColor)->Void) {
        self.context = context
        self.updateColor = updateColor
        super.init(frame: NSMakeRect(0, 0, 350, 380))
        self.bar = .init(height: 0)
    }
    private var currentTheme: TelegramPresentationTheme = theme
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        currentTheme = theme as! TelegramPresentationTheme
        self.modal?.updateLocalizationAndTheme(theme: theme)
    }
    private func updateSelectMode(_ selectMode: SelectMode, animated: Bool) {
        self.selectMode = selectMode
        switch selectMode {
        case .accent:
            self.genericView.colorPicker.updateMode(.single(currentTheme.colors.accent), animated: animated)
        case .messages:
            self.genericView.colorPicker.updateMode(.gradient(currentTheme.colors.bubbleBackground_outgoing, 0, nil), animated: animated)
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        genericView.controller = self
        
        genericView.addTableItems(self.context, theme: theme)
        
        self.genericView.segmentControl.add(segment: CatalinaSegmentedItem(title: strings().appearanceThemeAccent, handler: { [weak self] in
            self?.updateSelectMode(.accent, animated: true)
        }))
        if theme.bubbled && System.supportsTransparentFontDrawing {
            self.genericView.segmentControl.add(segment: CatalinaSegmentedItem(title: strings().appearanceThemeAccentMessages, handler: { [weak self] in
                self?.updateSelectMode(.messages, animated: true)
            }))
        }

        
        genericView.colorPicker.updateMode(.single(theme.colors.accent), animated: false)
        
        genericView.colorPicker.modeDidUpdate = { [weak self] mode in
            guard let `self` = self else {return}
            var newTheme = self.currentTheme
            switch mode {
            case let .single(color):
                let accent = PaletteAccentColor(color, newTheme.colors.bubbleBackground_outgoing)
                let colors = newTheme.colors.withoutAccentColor().withAccentColor(accent, disableTint: false)
                newTheme = newTheme.withUpdatedColors(colors)

            case let .gradient(colors, _, _):
                let accent = PaletteAccentColor(newTheme.colors.accent, colors)
                let colors = newTheme.colors.withoutAccentColor().withAccentColor(accent, disableTint: false)
                newTheme = newTheme.withUpdatedColors(colors)
            }
            self.currentTheme = newTheme
            self.genericView.updateMode(mode, newTheme: newTheme)
        }
        
        readyOnce()
    }
    
    
    
    private func saveAccent() {
        self.updateColor(PaletteAccentColor(currentTheme.colors.accent, currentTheme.colors.bubbleBackground_outgoing))
        
        delay(0.1, closure: { [weak self] in
           self?.close()
        })
    }
    
    public override var modalInteractions: ModalInteractions? {
        return ModalInteractions(acceptTitle: strings().modalSet, accept: { [weak self] in
            self?.saveAccent()
        }, height: 50, customTheme: { [weak self] in
            return self?.modalTheme ?? .init()
        })
    }
    
    public override var modalTheme: ModalViewController.Theme {
        return .init(text: currentTheme.colors.text, grayText: currentTheme.colors.grayText, background: currentTheme.colors.background, border: currentTheme.colors.border, accent: currentTheme.colors.accent, grayForeground: currentTheme.colors.grayForeground)
    }
    
    public override var dynamicSize: Bool {
        return true
    }
    
    public override func initializer() -> NSView {
        return CustomAccentColorView(frame: NSMakeRect(_frameRect.minX, _frameRect.minY, _frameRect.width, _frameRect.height - bar.height), theme: currentTheme, context: self.context)
    }
    
    public override func measure(size: NSSize) {
        self.modal?.resize(with: NSMakeSize(350, 380), animated: false)
    }
    
    private var genericView:CustomAccentColorView {
        return self.view as! CustomAccentColorView
    }
    public override func viewClass() -> AnyClass {
        return CustomAccentColorView.self
    }
    
    public override var handleAllEvents: Bool {
        return false
    }
    
    public override func firstResponder() -> NSResponder? {
        return genericView.colorPicker.colorEditor.textView.inputView
    }
}
