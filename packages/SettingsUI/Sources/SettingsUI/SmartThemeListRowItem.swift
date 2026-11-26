import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramTheme
import GeneralRows
import Localization



public class SmartThemeListRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let theme: TelegramPresentationTheme
    fileprivate let list: [SmartThemeCachedData]
    fileprivate let togglePalette: (InstallThemeSource)->Void
    fileprivate let animatedEmojiStickers: [String: StickerPackItem]
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, theme: TelegramPresentationTheme, list: [SmartThemeCachedData], animatedEmojiStickers: [String: StickerPackItem], viewType: GeneralViewType, togglePalette: @escaping(InstallThemeSource)->Void) {
        self.context = context
        self.theme = theme
        self.list = list
        self.animatedEmojiStickers = animatedEmojiStickers
        self.togglePalette = togglePalette
        super.init(initialSize, height: 90 + viewType.innerInset.top + viewType.innerInset.bottom, stableId: stableId, viewType: viewType)
    }
    
    public override func viewClass() -> AnyClass {
        return SmartThemeListRowView.self
    }
    
    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonTheme
    }
}


private final class SmartThemeListRowView : GeneralContainableRowView {
    private let tableView = HorizontalTableView(frame: NSZeroRect)
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(self.tableView)
        
    }
    
    
    override func updateColors() {
        guard let item = item as? SmartThemeListRowItem else {
            return
        }
        self.containerView.backgroundColor = item.theme.colors.background
        self.borderView.backgroundColor = item.theme.colors.border.cgColor
        self.backgroundColor = item.viewType.rowBackground
    }
    
    override var backdorColor: NSColor {
        guard let item = item as? SmartThemeListRowItem else {
            return theme.colors.background
        }
        return item.theme.colors.background
    }
    
    override func layout() {
        super.layout()
        guard let item = item as? SmartThemeListRowItem else {
            return
        }
        
        let innerInset = item.viewType.innerInset
        self.borderView.frame = NSMakeRect(innerInset.left, self.containerView.frame.height - .borderSize, self.containerView.frame.width - innerInset.left - innerInset.right, .borderSize)
        
        self.tableView.frame = NSMakeRect(0, innerInset.top, self.containerView.frame.width, self.containerView.frame.height - innerInset.bottom - innerInset.top)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        
        let previous: SmartThemeListRowItem? = self.item as? SmartThemeListRowItem
        super.set(item: item, animated: animated)
        
        guard let item = item as? SmartThemeListRowItem else {
            return
        }
        
        self.tableView.getBackgroundColor = {
            item.theme.colors.background
        }
        
        
        tableView.needUpdateVisibleAfterScroll = true
        
        self.layout()
        
        
        let reloadAnimated = animated && previous?.list.count != item.list.count
//
        tableView.beginTableUpdates()
        tableView.removeAll(animation: reloadAnimated ? .effectFade : .none)
        _ = tableView.addItem(item: GeneralRowItem(.zero, height: 10), animation: reloadAnimated ? .effectFade : .none)
        
        var scrollItem:AppearanceSmartThemePreviewRow? = nil
        
        
        for (_, smartTheme) in item.list.enumerated() {
            let data = smartTheme.data
            let selected: Bool = item.theme.colors.accent == data.appTheme.colors.accent && item.theme.wallpaper.wallpaper == data.appTheme.wallpaper.wallpaper
            let smartItem: AppearanceSmartThemePreviewRow
            switch smartTheme.source {
            case let .cloud(theme):
                smartItem = SettingsHooks.shared.makeSmartThemePreviewRow(tableView.frame.size, item.context, theme.id, item.theme.bubbled, item.animatedEmojiStickers, AppearanceThemeTuple(chatTheme: .emoticon(data.emoticon), image: data.previewIcon, theme: data.appTheme, index: 0), selected, { [weak item] _ in
                    item?.togglePalette(.cloud(theme, InstallCloudThemeCachedData(palette: data.appTheme.colors, wallpaper: data.appTheme.wallpaper.wallpaper, cloudWallpaper: data.appTheme.wallpaper.associated?.cloud)))
                })
            case let .local(palette):
                smartItem = SettingsHooks.shared.makeSmartThemePreviewRow(tableView.frame.size, item.context, arc4random(), item.theme.bubbled, item.animatedEmojiStickers, AppearanceThemeTuple(chatTheme: .emoticon(data.emoticon), image: data.previewIcon, theme: data.appTheme, index: 0), selected, { [weak item] _ in
                    item?.togglePalette(.local(palette))
                })
            }
            _ = tableView.addItem(item: smartItem)
            
            if selected && scrollItem == nil {
                scrollItem = smartItem
            }
        }

        _ = tableView.addItem(item: GeneralRowItem(.zero, height: 10), animation: reloadAnimated ? .effectFade : .none)
        tableView.endTableUpdates()
        
        if let item = scrollItem {
            self.tableView.scroll(to: .center(id: item.stableId, innerId: nil, animated: reloadAnimated, focus: .init(focus: false), inset: 0), toVisible: true)
        }
    }
}
