import Cocoa
import TGUIKit
import Postbox
import TelegramCore

import SwiftSignalKit
import TelegramContext
import TelegramUtils
import ChatModeTypes
import ChatHistoryModel
import Localization
import MessageUtils



open class ChatSwitchInlineController<Context: AccountContextProtocol>: ChatController<Context> {
    open override var defaultBarTitle: String {
        return localizedString("Telegram.ChatSwitchInlineController")
    }
    private let fallbackId:PeerId
    private let fallbackMode: ChatMode
    public init(context:Context, peerId:PeerId, fallbackId:PeerId, fallbackMode: ChatMode, initialAction:ChatInitialAction? = nil) {
        self.fallbackId = fallbackId
        self.fallbackMode = fallbackMode
        super.init(context: context, chatLocation: .peer(peerId), initialAction: initialAction)
    }
    
    public override var removeAfterDisapper: Bool {
        return true
    }
    
    override open func backSettings() -> (String,CGImage?) {
        return (strings().navigationCancel,nil)
    }
    
    override func applyTransition(_ transition:TableUpdateTransition, initialData:ChatHistoryCombinedInitialData, isLoading: Bool, processedView: ChatHistoryView) {
        super.applyTransition(transition, initialData: initialData, isLoading: isLoading, processedView: processedView)
        
        if case let .none(interface) = transition.state, let _ = interface {
            for (_, item) in transition.inserted {
                if let item = item as? ChatRowItem, let message = item.message {
                    for attribute in message.attributes {
                        if let attribute = attribute as? ReplyMarkupMessageAttribute {
                            for row in attribute.rows {
                                for button in row.buttons {
                                    if case let .switchInline(samePeer: _, query: query, _) = button.action {
                                        let text = "@\(message.inlinePeer?.username ?? "") \(query)"
                                        let controller: ChatController<Context>
                                        switch self.fallbackMode {
                                        case .history, .pinned:
                                            controller = ChatController(context: context, chatLocation: .peer(fallbackId), initialAction: .inputText(text: .init(inputText: text), behavior: .automatic))
                                        case let .thread(mode):
                                            controller = ChatController(context: context, chatLocation: .peer(fallbackId), mode: .thread(mode: mode), initialAction: .inputText(text: .init(inputText: text), behavior: .automatic), chatLocationContextHolder: Atomic<ChatLocationContextHolder?>(value: nil))
                                        case .scheduled:
                                            controller = ChatScheduleController(context: context, chatLocation: .peer(fallbackId), initialAction: .inputText(text: .init(inputText: text), behavior: .automatic))
                                        case .customChatContents, .customLink, .preview:
                                            fatalError()
                                        }
                                        self.navigationController?.push(controller)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
}
