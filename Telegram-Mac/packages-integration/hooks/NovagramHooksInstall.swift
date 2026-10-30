import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import NovagramCore
import PrivateCallScreen
import CallsUI
import InAppSettings
import SwiftSignalKit
import NovagramJobSearch
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
        novagramJobSearchClear(accountRecordId: accountId)
    }
    hooks.openRecentActions = { context, peer in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(ChannelEventLogController(context, peer: EnginePeer(peer)))
    }
    hooks.openJobSearch = { context, savedSearchId in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(NovagramJobSearchController(context: context, savedSearchId: savedSearchId))
    }
    hooks.jobSearchUnseenCount = { context in
        return NovagramJobAlertMonitor.shared.unseenCount(account: NovagramJobSearchEngine.account(context))
    }
    hooks.handleNotificationClick = { userInfo in
        return NovagramJobAlertMonitor.shared.handleNotificationClick(userInfo)
    }
    NovagramHooks.install(hooks)
    if let directory = ApiEnvironment.containerURL?.appendingPathComponent("novagram-archive", isDirectory: true) {
        NovagramMessageArchive.shared.configure(directory: directory)
    }
    installNovagramJobSearchHooks()
    installNovagramSettingsHooks()
    installNovagramAdsHooks()
    installNovagramCallRecordHooks()
    installNovagramCallExtrasHooks()
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
        combineLatest(NovagramCallRecording.shared.recordingSignal, NovagramDeveloperFlags.callRecordingSignal) |> map { isRecording, _ in isRecording }
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

private func installNovagramJobSearchHooks() {
    var hooks = NovagramJobSearchHooks()
    hooks.openMessage = { context, message in
        guard let context = context as? AccountContext else {
            return
        }
        #if DEBUG
        Logger.shared.log("NovagramJobSearch", "open post \(message.id)")
        #endif
        context.engine.messages.ensureMessagesAreLocallyAvailable(messages: [EngineMessage(message)])
        navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(message.id.peerId), focusTarget: .init(messageId: message.id))
    }
    hooks.openPeer = { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId))
    }
    NovagramJobSearchHooks.install(hooks)
}

func novagramJobSearchDidStart(context: AccountContext) {
    NovagramJobAlertMonitor.shared.start(context: context)
}

func novagramMessageArchiveDidStart(context: AccountContext) {
    NovagramMessageArchive.shared.removeOrphans(sharedContext: context.sharedContext)
    NovagramMessageArchive.shared.migrateLegacyIfNeeded(sharedContext: context.sharedContext, currentAccount: context.account)
}

func novagramJobSearchDidStop(context: AccountContext) {
    NovagramJobAlertMonitor.shared.stop(context: context)
}

func novagramJobSearchClear(accountRecordId: AccountRecordId) {
    NovagramJobSearchData.clear(accountRecordId: accountRecordId.int64)
    NovagramMessageArchive.shared.clear(accountRecordId: accountRecordId.int64)
    NovagramJobAlertMonitor.shared.clearUnseen(accountRecordId: accountRecordId.int64)
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
