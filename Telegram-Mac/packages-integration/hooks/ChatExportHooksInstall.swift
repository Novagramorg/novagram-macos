import Cocoa
import Postbox
import TelegramCore
import SwiftSignalKit
import ChatExportUI

func installChatExportUIHooks() {
    ChatExportHooks.install(ChatExportHooks(loadHistoryPage: { context, peerId, anchor, count, holder, input in
        guard let context = context as? AccountContext else {
            return .never()
        }
        let location: ChatHistoryLocation = .Navigation(index: anchor, anchorIndex: anchor, count: count, side: .lower)
        return chatHistoryViewForLocation(location, context: context, chatLocation: .peer(peerId), fixedCombinedReadStates: nil, tag: nil, orderStatistics: [.combinedLocation], chatLocationContextHolder: holder, chatLocationInput: input)
        |> mapToSignal { update -> Signal<MessageHistoryView, NoError> in
            guard case let .HistoryView(view, _, _, _) = update else {
                return .never()
            }
            if view.isLoading {
                return .never()
            }
            return .single(view)
        }
    }))
}
