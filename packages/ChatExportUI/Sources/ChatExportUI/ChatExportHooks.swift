import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public struct ChatExportHooks {
    public let loadHistoryPage: (any AccountContextProtocol, PeerId, MessageHistoryAnchorIndex, Int, Atomic<ChatLocationContextHolder?>, ChatLocationInput) -> Signal<MessageHistoryView, NoError>

    public init(loadHistoryPage: @escaping (any AccountContextProtocol, PeerId, MessageHistoryAnchorIndex, Int, Atomic<ChatLocationContextHolder?>, ChatLocationInput) -> Signal<MessageHistoryView, NoError>) {
        self.loadHistoryPage = loadHistoryPage
    }

    private static var _shared: ChatExportHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChatExportHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ChatExportHooks.install must be called before chat export is used")
        return .placeholder
    }

    public static func install(_ hooks: ChatExportHooks) {
        assert(Thread.isMainThread, "ChatExportHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ChatExportHooks(loadHistoryPage: { _, _, _, _, _, _ in .never() })
}
