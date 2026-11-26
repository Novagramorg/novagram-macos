import Foundation
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TelegramUtils
import Postbox
import AlertsUI
import Localization
import TGUIKit

final class BrowserEmojiPermissionAction {
    private final class Request {
        private enum Phase {
            case permissions
            case prompt
            case saving
            case granting
            case finished
        }

        private let context: any AccountContextProtocol
        private let bot: Peer
        private weak var window: Window?
        private let canPresent: () -> Bool
        private let completion: (String) -> Void
        private let finished: (Request) -> Void
        private let disposable = MetaDisposable()
        private var dismissPrompt: (() -> Void)?
        private var phase = Phase.permissions
        private var cancelled = false

        init(context: any AccountContextProtocol, bot: Peer, window: Window, canPresent: @escaping () -> Bool, completion: @escaping (String) -> Void, finished: @escaping (Request) -> Void) {
            self.context = context
            self.bot = bot
            self.window = window
            self.canPresent = canPresent
            self.completion = completion
            self.finished = finished
        }

        func cancel() {
            self.cancelled = true
            self.phase = .finished
            self.disposable.dispose()
            let dismiss = self.dismissPrompt
            self.dismissPrompt = nil
            dismiss?()
        }

        private func isCurrent(_ phase: Phase) -> Bool {
            guard self.phase == phase else {
                return false
            }
            guard self.canPresent(), self.window != nil else {
                self.cancel()
                self.finished(self)
                return false
            }
            return !self.cancelled && self.phase == phase
        }

        private func finish(_ status: String, newlyAllowed: Bool = false, openPremium: Bool = false) {
            guard self.phase != .finished else {
                return
            }
            self.phase = .finished
            defer { self.finished(self) }
            self.disposable.dispose()
            let dismiss = self.dismissPrompt
            self.dismissPrompt = nil
            dismiss?()
            guard !self.cancelled, self.canPresent(), let window = self.window else {
                return
            }
            if newlyAllowed {
                showModalText(for: window, text: strings().webappEmojiStatusAllowed(self.bot.displayTitle))
            } else if openPremium {
                BrowserHooks.shared.openPremiumBoarding(self.context, window)
            }
            guard !self.cancelled, self.canPresent() else {
                return
            }
            self.completion(status)
        }

        func start() {
            guard self.isCurrent(.permissions) else {
                return
            }
            let botId = self.bot.id
            let accountId = self.context.account.peerId
            let accountPeer = self.context.myPeer
            let pending = MetaDisposable()
            self.disposable.set(pending)
            var received = false
            pending.set((self.context.account.postbox.transaction { transaction -> (Bool, Peer?) in
                let allowed = (transaction.getPeerCachedData(peerId: botId) as? CachedUserData)?.flags.contains(.botCanManageEmojiStatus) == true
                return (allowed, transaction.getPeer(accountId) ?? accountPeer)
            } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] allowed, accountPeer in
                received = true
                guard let self, self.isCurrent(.permissions) else {
                    return
                }
                if allowed {
                    self.finish("allowed")
                } else if let accountPeer {
                    self.askPermission(accountPeer: accountPeer)
                } else {
                    self.finish("cancelled")
                }
            }, completed: { [weak self] in
                guard !received, let self, self.isCurrent(.permissions) else {
                    return
                }
                self.finish("cancelled")
            }))
        }

        private func askPermission(accountPeer: Peer) {
            guard self.isCurrent(.permissions), let window = self.window else {
                return
            }
            self.phase = .prompt
            let context = self.context
            let data = ModalAlertData(title: nil, info: strings().webappEmojiStatusRequested(self.bot.displayTitle, self.bot.displayTitle), description: nil, ok: strings().webappEmojiStatusRequestedAllow, options: [], mode: .confirm(text: strings().webappEmojiStatusRequestedDecline, isThird: false), header: .init(id: "header", value: { initialSize, stableId, presentation in
                BotEmojiStatusPermissionRowItem(initialSize, stableId: stableId, peer: .init(accountPeer), context: context)
            }))
            let dismiss = showDismissableModalAlert(for: window, data: data, completion: { [weak self] _ in
                self?.choose(true)
            }, cancel: { [weak self] in
                self?.choose(false)
            }, onDeinit: { [weak self] in
                Queue.mainQueue().justDispatch { [weak self] in
                    guard let self, self.isCurrent(.prompt) else {
                        return
                    }
                    self.finish("cancelled")
                }
            })
            if self.phase == .prompt && !self.cancelled {
                self.dismissPrompt = dismiss
            } else {
                dismiss()
            }
        }

        private func choose(_ allowed: Bool) {
            guard self.isCurrent(.prompt) else {
                return
            }
            if allowed && !self.context.isPremium {
                self.finish("cancelled", openPremium: true)
                return
            }
            self.phase = .saving
            let pending = MetaDisposable()
            self.disposable.set(pending)
            guard self.isCurrent(.saving) else {
                return
            }
            pending.set((updateWebAppPermissionsStateInteractively(context: self.context, peerId: self.bot.id) { current in
                WebAppPermissionsState(location: current?.location, emojiStatus: .init(isRequested: true))
            } |> deliverOnMainQueue).start(completed: { [weak self] in
                guard let self, self.isCurrent(.saving) else {
                    return
                }
                if allowed {
                    self.grant()
                } else {
                    self.finish("cancelled")
                }
            }))
        }

        private func grant() {
            self.phase = .granting
            let pending = MetaDisposable()
            self.disposable.set(pending)
            guard self.isCurrent(.granting) else {
                return
            }
            pending.set((self.context.engine.peers.toggleBotEmojiStatusAccess(peerId: self.bot.id, enabled: true)
            |> deliverOnMainQueue).start(error: { [weak self] _ in
                guard let self, self.isCurrent(.granting) else {
                    return
                }
                self.finish("cancelled")
            }, completed: { [weak self] in
                guard let self, self.isCurrent(.granting) else {
                    return
                }
                self.finish("allowed", newlyAllowed: true)
            }))
        }

        deinit {
            self.disposable.dispose()
            self.dismissPrompt?()
        }
    }

    private var request: Request?

    func open(context: any AccountContextProtocol, bot: Peer, window: Window, canPresent: @escaping () -> Bool, completion: @escaping (String) -> Void) {
        guard self.request == nil, canPresent() else {
            return
        }
        let request = Request(context: context, bot: bot, window: window, canPresent: canPresent, completion: completion, finished: { [weak self] request in
            if self?.request === request {
                self?.request = nil
            }
        })
        self.request = request
        request.start()
    }

    func reset() {
        let request = self.request
        self.request = nil
        request?.cancel()
    }

    deinit {
        self.request?.cancel()
    }
}
