import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import NovagramCore
import PrivateCallScreen
import CallsUI
import InAppSettings
import SwiftSignalKit

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
        NovagramCallRecording.shared.recordingSignal
    }
    hooks.title = { isRecording in
        NovagramL10n.current.callRecording_action(isRecording)
    }
    hooks.toggle = { request in
        NovagramCallRecording.shared.toggle(window: request.window, engine: request.engine, peerId: request.peerId, hasVideo: request.hasVideo)
    }
    hooks.autoStart = { request in
        NovagramCallRecording.shared.autoStart(window: request.window, engine: request.engine, peerId: request.peerId, hasVideo: request.hasVideo)
    }
    hooks.callDidUpdate = { window, state in
        NovagramCallRecording.shared.callDidUpdate(window: window, isEnded: state.isEnded, isMuted: state.isMuted)
    }
    NovagramCallRecordHooks.install(hooks)
    NovagramCallRecording.shared.micDeviceId = {
        guard let accountManager = appDelegate?.sharedApplicationContextValue?.sharedContext.accountManager else {
            return .single(nil)
        }
        return voiceCallSettings(accountManager) |> take(1) |> map { $0.audioInputDeviceId }
    }
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
