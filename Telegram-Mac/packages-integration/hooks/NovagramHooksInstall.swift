import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import NovagramCore
import PrivateCallScreen
import CallsUI
import InAppSettings
import SwiftSignalKit
import NovagramSuperSearch
import TranslateUI
import ApiCredentials

func installNovagramHooks() {
    var hooks = NovagramHooks()
    hooks.presentEditedHistory = { context, peerId, messageId, currentText in
        guard let context = context as? AccountContext else {
            return
        }
        let controller = NovagramEditedHistoryController(context: context, peerId: peerId, messageId: messageId, currentText: currentText)
        context.bindings.rootNavigation().push(controller)
    }
    hooks.openChat = { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId))
    }
    hooks.accountWillLogOut = { accountId in
        NovagramAnalyticsManager.shared.accountWillLogOut(accountId: accountId)
        novagramSearchDataClear(accountRecordId: accountId)
    }
    hooks.openRecentActions = { context, peer in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(ChannelEventLogController(context, peer: EnginePeer(peer)))
    }
    hooks.openSuperSearch = { context in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(NovagramSuperSearchController(context: context))
    }
    NovagramHooks.install(hooks)
    if let directory = ApiEnvironment.containerURL?.appendingPathComponent("novagram-archive", isDirectory: true) {
        NovagramMessageArchive.shared.configure(directory: directory)
    }
    installNovagramSuperSearchHooks()
    installNovagramSettingsHooks()
    installNovagramAdsHooks()
    installNovagramCallRecordHooks()
    installNovagramCallExtrasHooks()
    NovagramTranslateHooks.didTranslateMessage = {
        NovagramReviewPrompt.record(.translateMessage)
    }
}

private func installNovagramCallRecordHooks() {
    var hooks = NovagramCallRecordHooks()
    hooks.isAvailable = {
        NovagramCallRecordingSettings.isEnabled
    }
    hooks.isRecording = {
        NovagramCallRecording.shared.isRecording
    }
    hooks.recordingSignal = {
        combineLatest(NovagramCallRecording.shared.recordingSignal, NovagramCallRecordingSettings.enabledSignal) |> map { isRecording, _ in isRecording }
    }
    hooks.title = { isRecording in
        NovagramL10n.current.callRecording_action(isRecording)
    }
    hooks.toggle = { request in
        NovagramCallRecording.shared.toggle(window: request.window, engine: request.engine, peerId: request.peerId, hasVideo: request.hasVideo, callId: request.callId)
    }
    hooks.autoStart = { request in
        NovagramCallRecording.shared.autoStart(window: request.window, engine: request.engine, peerId: request.peerId, hasVideo: request.hasVideo, callId: request.callId)
    }
    hooks.callDidUpdate = { window, state in
        NovagramCallRecording.shared.callDidUpdate(window: window, callId: state.callId, isEnded: state.isEnded, isMuted: state.isMuted)
    }
    NovagramCallRecordHooks.install(hooks)
    NovagramCallRecording.shared.micDeviceId = {
        guard let accountManager = appDelegate?.sharedApplicationContextValue?.sharedContext.accountManager else {
            return .single(nil)
        }
        return voiceCallSettings(accountManager) |> take(1) |> map { $0.audioInputDeviceId }
    }
}

private func installNovagramSuperSearchHooks() {
    var hooks = NovagramSuperSearchHooks()
    hooks.openMessage = { context, message in
        guard let context = context as? AccountContext else {
            return
        }
        #if DEBUG
        Logger.shared.log("NovagramSuperSearch", "open message \(message.id)")
        #endif
        context.engine.messages.ensureMessagesAreLocallyAvailable(messages: [EngineMessage(message)])
        novagramSuperSearchOpen(context: context, peerId: message.id.peerId, messageId: message.id)
    }
    hooks.openMessageId = { context, messageId in
        guard let context = context as? AccountContext else {
            return
        }
        novagramSuperSearchOpen(context: context, peerId: messageId.peerId, messageId: messageId)
    }
    hooks.openPeer = { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        novagramSuperSearchOpen(context: context, peerId: peerId, messageId: nil)
    }
    NovagramSuperSearchHooks.install(hooks)
}

// A locked chat asks for its PIN first, as when it is opened from the chat list.
private func novagramSuperSearchOpen(context: AccountContext, peerId: PeerId, messageId: MessageId?) {
    let reopen = { novagramSuperSearchOpen(context: context, peerId: peerId, messageId: messageId) }
    if NovagramChatPincode.requiresUnlock(peerId: peerId, window: context.window, reopen: reopen) {
        return
    }
    navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId), focusTarget: ChatFocusTarget(messageId: messageId))
}

func novagramMessageArchiveDidStart(context: AccountContext) {
    NovagramMessageArchive.shared.removeOrphans(sharedContext: context.sharedContext)
    NovagramMessageArchive.shared.migrateLegacyIfNeeded(sharedContext: context.sharedContext, currentAccount: context.account)
}

private let novagramReviewPromptDisposable = MetaDisposable()

// The rating prompt's natural break: the chat list shows with no chat open (the empty right pane in the dual
// layout, the chat list after closing a chat in the single layout).
func novagramReviewPromptDidStart(context: AccountContext) {
    guard !context.isSupport else {
        return
    }
    NovagramReviewPrompt.accountDidStart(accountId: context.account.id.int64)
    var noChatOpen = false
    novagramReviewPromptDisposable.set((context.globalPeerHandler.get() |> deliverOnMainQueue).start(next: { [weak context] location in
        noChatOpen = location == nil
        guard noChatOpen, let context else {
            return
        }
        NovagramReviewPrompt.chatListDidAppear(window: context.window, isBusy: { [weak context] in
            guard let context else {
                return true
            }
            return !noChatOpen || novagramReviewPromptIsBusy(context)
        })
    }))
}

// A call, a recording, the passcode lock, the open secret vault or any sheet (the chat lock PIN sheet too).
private func novagramReviewPromptIsBusy(_ context: AccountContext) -> Bool {
    let isLocked = appDelegate?.sharedApplicationContextValue?.notificationManager.isLocked ?? true
    return isLocked
        || context.sharedContext.hasActiveCall
        || NovagramCallRecording.shared.isRecording
        || NovagramHiddenChatsManager.shared.isRevealed
        || hasModals(context.window)
}

func novagramSearchDataClear(accountRecordId: AccountRecordId) {
    NovagramSuperSearchData.clear(accountRecordId: accountRecordId.int64)
    NovagramMessageArchive.shared.clear(accountRecordId: accountRecordId.int64)
}

private func installNovagramCallExtrasHooks() {
    var hooks = NovagramCallExtrasHooks()
    hooks.showDeviceMenu = { view, event in
        guard let sharedContext = appDelegate?.sharedApplicationContextValue?.sharedContext else {
            return
        }
        let l10n = NovagramL10n.current
        novagramPresentCallDeviceMenu(sharedContext: sharedContext, view: view, event: event, strings: NovagramCallDeviceMenuStrings(microphone: l10n.callDevices_microphone, speaker: l10n.callDevices_speaker, systemDefault: l10n.callDevices_default))
    }
    hooks.isWeakNetworkBannerEnabled = {
        true
    }
    hooks.weakConnectionText = {
        NovagramL10n.current.callWeakNetwork_text
    }
    hooks.turnOffVideoText = {
        NovagramL10n.current.callWeakNetwork_turnOffVideo
    }
    NovagramCallExtrasHooks.install(hooks)
}
