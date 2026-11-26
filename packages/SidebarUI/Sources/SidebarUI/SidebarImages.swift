import Cocoa
import TGUIKit
import TelegramTheme
import GeneralRows

extension ChatListFilterVisibilityItem {
    public convenience init(_ initialSize: NSSize, stableId: AnyHashable, sidebar: Bool, viewType: GeneralViewType, source: Source = .folders, toggle: @escaping (Bool) -> Void) {
        self.init(initialSize, images: sidebarImage, stableId: stableId, sidebar: sidebar, viewType: viewType, source: source, toggle: toggle)
    }
}

public func sidebarImage(_ image: SidebarImage) -> NSImage {
    switch image {
    case .iconSharedFolder: return TelegramThemeHooks.shared.image(.iconSharedFolder)
    case .tabsselectTopGray: return TelegramThemeHooks.shared.image(.tabsselectTopGray)
    case .tabsselectTopSystemcol: return TelegramThemeHooks.shared.image(.tabsselectTopSystemcol)
    case .tabsselectLeftGray: return TelegramThemeHooks.shared.image(.tabsselectLeftGray)
    case .tabsselectLeftSystemcol: return TelegramThemeHooks.shared.image(.tabsselectLeftSystemcol)
    case .iconForumTabs: return TelegramThemeHooks.shared.image(.iconForumTabs)
    case .iconForumList: return TelegramThemeHooks.shared.image(.iconForumList)
    }
}
