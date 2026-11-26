import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramContext

func chatDateMediaLocation(_ location: SearchMessagesLocation, tag: MessageTags) -> SearchMessagesLocation? {
    guard case let .peer(peerId, fromId, _, reactions, threadId, minDate, maxDate) = location else {
        return nil
    }
    return .peer(peerId: peerId, fromId: fromId, tags: tag, reactions: reactions, threadId: threadId, minDate: minDate, maxDate: maxDate)
}

final class ChatDateHeaderActions {
    private var lastJumpLocation: SearchMessagesLocation?
    private let actionDisposable = MetaDisposable()
    private var generation = 0

    deinit {
        actionDisposable.dispose()
    }

    func reset() {
        generation += 1
        lastJumpLocation = nil
        actionDisposable.set(nil)
    }

    func shouldShowMenu(location: SearchMessagesLocation, interaction: ChatInteraction) -> Bool {
        if lastJumpLocation == location {
            return true
        }
        guard case let .peer(_, _, _, _, _, minDate?, _) = location else {
            return false
        }
        lastJumpLocation = location
        actionDisposable.set(nil)
        interaction.jumpToDate(Date(timeIntervalSince1970: TimeInterval(minDate)))
        return false
    }

    private func isCurrent(_ location: SearchMessagesLocation, interaction: ChatInteraction, generation: Int) -> Bool {
        guard self.generation == generation, case let .peer(peerId, _, _, _, threadId, _, _) = location else {
            return false
        }
        return interaction.peerId == peerId && interaction.chatLocation.threadId == threadId
    }

    private func statusItem(_ title: String) -> ContextMenuItem {
        let item = ContextMenuItem(title)
        item.isEnabled = false
        return item
    }

    func makeMenu(location: SearchMessagesLocation, interaction: ChatInteraction) -> ContextMenu {
        let menu = ContextMenu()
        menu.items = [statusItem(strings().voiceOverCommonLoading)]
        let disposable = MetaDisposable()
        let generation = self.generation
        let categories: [(MessageTags, (Int) -> String)] = [
            (.photoOrVideo, { translate(key: "Chat.Date.PhotosAndVideos_other", [$0]) }),
            (.file, strings().sharedMediaFileCountOther),
            (.music, strings().sharedMediaMusicCountOther),
            (.voiceOrInstantVideo, strings().sharedMediaVoiceCountOther),
            (.gif, strings().sharedMediaGifCountOther),
            (.webPage, strings().sharedMediaLinkCountOther)
        ]
        menu.onShow = { [weak self, weak interaction] menu in
            guard let self, let interaction, self.isCurrent(location, interaction: interaction, generation: generation) else {
                return
            }
            let requests = categories.compactMap { tag, _ -> Signal<Int?, NoError>? in
                guard let location = chatDateMediaLocation(location, tag: tag) else { return nil }
                return chatDateMessageCount(context: interaction.interactionContext, location: location)
            }
            disposable.set((combineLatest(requests) |> deliverOnMainQueue).start(next: { [weak self, weak menu, weak interaction] counts in
                guard let self, let menu, let interaction, self.isCurrent(location, interaction: interaction, generation: generation) else {
                    return
                }
                var items: [ContextMenuItem] = []
                for (category, count) in zip(categories, counts) {
                    guard let count, count > 0 else { continue }
                    guard let categoryLocation = chatDateMediaLocation(location, tag: category.0) else { continue }
                    let title = category.1(Int(count))
                    let item = ContextMenuItem(title)
                    if category.0 == .photoOrVideo || category.0 == .gif {
                        item.handler = { [weak self, weak interaction] in
                            guard let self, let interaction, self.isCurrent(location, interaction: interaction, generation: generation) else { return }
                            self.openGallery(location: categoryLocation, interaction: interaction)
                        }
                    } else {
                        item.submenu = self.makeMessageMenu(location: categoryLocation, fallbackTitle: title, interaction: interaction)
                    }
                    items.append(item)
                }
                menu.items = items.isEmpty ? [self.statusItem(strings().requestJoinListSearchEmptyHeader)] : items
            }))
        }
        menu.onClose = {
            disposable.set(nil)
        }
        return menu
    }

    private func makeMessageMenu(location: SearchMessagesLocation, fallbackTitle: String, interaction: ChatInteraction) -> ContextMenu {
        let menu = ContextMenu()
        menu.items = [statusItem(strings().voiceOverCommonLoading)]
        let disposable = MetaDisposable()
        let generation = self.generation
        var state: SearchMessagesState?
        var loading = false
        var completed = false
        let load: () -> Void = { [weak self, weak menu, weak interaction] in
            guard let self, let menu, let interaction, !loading, !completed,
                  self.isCurrent(location, interaction: interaction, generation: generation) else { return }
            loading = true
            let previousState = state
            disposable.set((interaction.interactionContext.engine.messages.searchMessages(location: location, query: "", state: state, limit: 50)
            |> deliverOnMainQueue).start(next: { [weak self, weak menu, weak interaction] result, nextState in
                loading = false
                guard let self, let menu, let interaction, self.isCurrent(location, interaction: interaction, generation: generation),
                      case let .peer(_, _, _, _, _, minDate?, maxDate?) = location else { return }
                state = nextState
                completed = result.completed || previousState == nextState
                let messages = result.messages.filter { $0.timestamp >= minDate && $0.timestamp <= maxDate }
                menu.items = messages.map { message in
                    let file = message.media.compactMap { $0 as? TelegramMediaFile }.first
                    let title = file?.fileName ?? (message.text.isEmpty ? fallbackTitle : String(message.text.prefix(100)))
                    let time = DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp) - interaction.interactionContext.timeDifference), dateStyle: .none, timeStyle: .short)
                    return ContextMenuItem("\(time) · \(title)", handler: { [weak self, weak interaction] in
                        guard let self, let interaction, self.isCurrent(location, interaction: interaction, generation: generation) else { return }
                        interaction.focusMessageId(nil, .init(messageId: message.id, string: nil), .top(id: 0, innerId: nil, animated: true, focus: .init(focus: true), inset: 30))
                    })
                }
                if menu.items.isEmpty {
                    menu.items = [self.statusItem(strings().requestJoinListSearchEmptyHeader)]
                }
            }))
        }
        menu.onShow = { _ in load() }
        menu.loadMore = load
        menu.onClose = {
            disposable.set(nil)
            loading = false
        }
        return menu
    }

    private func openGallery(location: SearchMessagesLocation, interaction: ChatInteraction) {
        let generation = self.generation
        let signal = chatDateLoadMessages(context: interaction.interactionContext, location: location) |> deliverOnMainQueue
        actionDisposable.set(showModalProgress(signal: signal, for: interaction.interactionContext.window).start(next: { [weak self, weak interaction] messages in
            guard let self, let interaction, self.isCurrent(location, interaction: interaction, generation: generation) else { return }
            guard let messages = messages?.filter({ !$0.containsSecretMedia }), let first = messages.first else {
                interaction.showToaster(NSAttributedString(string: strings().requestJoinListSearchEmptyHeader))
                return
            }
            ChatNavigationHooks.shared.showChatGallery(interaction.interactionContext, first, nil, nil, .messages(messages), false, interaction.mode, interaction.chatLocation, interaction.contextHolder(), interaction.presentation.cachedData)
        }))
    }
}
