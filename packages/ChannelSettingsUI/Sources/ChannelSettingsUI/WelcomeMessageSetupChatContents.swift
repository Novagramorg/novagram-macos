import Foundation
import TelegramCore
import Postbox
import Cocoa
import TGUIKit
import SwiftSignalKit
import Localization
import TelegramContext
import AlertsUI
import ChatModeTypes
import ChatUI

final class WelcomeMessageSetupChatContents: ChatCustomContentsProtocol {
    private final class Impl {
        let queue: Queue
        let context: any AccountContextProtocol
        let peerId: PeerId
        let messageLimit: Int

        private(set) var currentHistoryView: MessageHistoryView?
        let historyViewStream = ValuePipe<(MessageHistoryView, ViewUpdateType)>()
        private var observedMessageCount = 0
        private var reservedMessageCount = 0
        private var hasObservedHistory = false

        private var historyViewDisposable: Disposable?
        private var refreshDisposable: Disposable?

        init(queue: Queue, context: any AccountContextProtocol, peerId: PeerId, messageLimit: Int) {
            self.queue = queue
            self.context = context
            self.peerId = peerId
            self.messageLimit = messageLimit

            self.historyViewDisposable = (context.account.viewTracker.welcomeMessagesViewForLocation(peerId: peerId)
            |> deliverOn(queue)).startStrict(next: { [weak self] view, update, _ in
                guard let self else {
                    return
                }
                let updatedCount = view.entries.count
                if self.hasObservedHistory, updatedCount > self.observedMessageCount {
                    self.reservedMessageCount = max(0, self.reservedMessageCount - (updatedCount - self.observedMessageCount))
                }
                self.hasObservedHistory = true
                self.observedMessageCount = updatedCount
                self.currentHistoryView = view
                self.historyViewStream.putNext((view, update))
            })

            self.refreshDisposable = context.engine.messages.refreshWelcomeMessages(peerId: peerId).start()
        }

        deinit {
            self.historyViewDisposable?.dispose()
            self.refreshDisposable?.dispose()
        }

        func enqueueMessages(messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
            let availableCount = max(0, self.messageLimit - self.observedMessageCount - self.reservedMessageCount)
            let acceptedMessages = Array(messages.prefix(availableCount))
            let rejectedCount = messages.count - acceptedMessages.count
            self.reservedMessageCount += acceptedMessages.count

            if rejectedCount != 0 {
                Queue.mainQueue().async {
                    alert(for: self.context.window, info: strings().welcomeMessageLimitReached(self.messageLimit))
                }
            }

            guard !acceptedMessages.isEmpty else {
                return .single(Array(repeating: nil, count: messages.count))
            }

            return TelegramCore.enqueueWelcomeMessages(account: self.context.account, peerId: self.peerId, messages: acceptedMessages)
            |> deliverOn(self.queue)
            |> map { ids in
                self.reservedMessageCount = max(0, self.reservedMessageCount - ids.filter { $0 == nil }.count)
                return ids + Array(repeating: nil, count: rejectedCount)
            }
        }

        func deleteMessages(ids: [EngineMessage.Id]) {
            let _ = (self.context.engine.messages.deleteMessagesInteractively(messageIds: ids, type: .forEveryone)
            |> then(self.context.engine.messages.refreshWelcomeMessages(peerId: self.peerId))).startStandalone()
        }

        func messagesAtIds(_ ids: [MessageId], album: Bool) -> Signal<[Message], NoError> {
            let messages = self.currentHistoryView?.entries.map(\.message) ?? []
            var filtered = messages.filter { ids.contains($0.id) }

            if album {
                let groupingKeys = Set(filtered.compactMap(\.groupingKey))
                let filteredIds = Set(filtered.map(\.id))
                filtered.append(contentsOf: messages.filter {
                    guard let groupingKey = $0.groupingKey else {
                        return false
                    }
                    return groupingKeys.contains(groupingKey) && !filteredIds.contains($0.id)
                })
            }
            return .single(filtered)
        }
    }

    let kind: ChatCustomContentsKind = .welcomeMessages
    let messageLimit: Int?

    private let queue: Queue
    private let impl: QueueLocalObject<Impl>

    var historyView: Signal<(MessageHistoryView, ViewUpdateType), NoError> {
        return self.impl.signalWith { impl, subscriber in
            if let currentHistoryView = impl.currentHistoryView {
                subscriber.putNext((currentHistoryView, .Initial))
            }
            return impl.historyViewStream.signal().start(next: subscriber.putNext)
        }
    }

    init(context: any AccountContextProtocol, peerId: PeerId) {
        let messageLimit = max(0, Int(context.appConfiguration.getGeneralValue("ephemeral_welcome_messages_max", orElse: 5)))
        self.messageLimit = messageLimit

        let queue = Queue()
        self.queue = queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return Impl(queue: queue, context: context, peerId: peerId, messageLimit: messageLimit)
        })
    }

    func enqueueMessages(messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
        return self.impl.signalWith { impl, subscriber in
            return impl.enqueueMessages(messages: messages).start(next: { ids in
                subscriber.putNext(ids)
                subscriber.putCompletion()
            })
        }
    }

    func deleteMessages(ids: [EngineMessage.Id]) {
        self.impl.with { impl in
            impl.deleteMessages(ids: ids)
        }
    }

    func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool) {
    }

    func messagesAtIds(_ ids: [MessageId], album: Bool) -> Signal<[Message], NoError> {
        return self.impl.signalWith { impl, subscriber in
            return impl.messagesAtIds(ids, album: album).start(next: { messages in
                subscriber.putNext(messages)
                subscriber.putCompletion()
            })
        }
    }

    func hashtagSearchUpdate(query: String) {
    }

    var hashtagSearchResultsUpdate: ((SearchMessagesResult, SearchMessagesState)) -> Void = { _ in }

    func loadMore() {
    }
}

public func WelcomeMessageController<Context: AccountContextProtocol>(context: Context, peerId: PeerId) -> ViewController {
    let contents = WelcomeMessageSetupChatContents(context: context, peerId: peerId)
    return ChatAdditionController(context: context, chatLocation: .peer(peerId), mode: .customChatContents(contents: contents))
}
