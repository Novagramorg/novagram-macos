import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import NovagramCore
import PrivateCallScreen

func installNovagramHooks() {
    var hooks = NovagramHooks()
    hooks.presentEditedHistory = { context, peerId, messageId, currentText in
        guard let context = context as? AccountContext else {
            return
        }
        let controller = NovagramEditedHistoryController(context: context, peerId: peerId, messageId: messageId, currentText: currentText)
        context.bindings.rootNavigation().push(controller)
    }
    hooks.accountWillLogOut = { accountId in
        NovagramAnalyticsManager.shared.accountWillLogOut(accountId: accountId)
    }
    hooks.openRecentActions = { context, peer in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(ChannelEventLogController(context, peer: EnginePeer(peer)))
    }
    NovagramHooks.install(hooks)
    installNovagramSettingsHooks()
    installNovagramAdsHooks()
    installNovagramCallRecordHooks()
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
        NovagramCallRecording.shared.recordingSignal
    }
    hooks.title = { isRecording in
        NovagramL10n.current.callRecording_action(isRecording)
    }
    hooks.toggle = { request in
        NovagramCallRecording.shared.toggle(window: request.window, engine: request.engine, peerId: request.peerId, hasVideo: request.hasVideo)
    }
    hooks.callDidUpdate = { window, state in
        NovagramCallRecording.shared.callDidUpdate(window: window, isEnded: state.isEnded, isMuted: state.isMuted)
    }
    NovagramCallRecordHooks.install(hooks)
}
