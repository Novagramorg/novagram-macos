import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import Postbox

import TelegramCore
import CallsUI
import Localization
import TelegramCallsCore
import TelegramTheme
import TelegramUtils
import Strings
import InAppSettings





public class GroupCallNavigationHeaderView: CallHeaderBasicView {




    private let audioLevelDisposable = MetaDisposable()

    public var context: GroupCallContext? {
        get {
            return self.header?.contextObject as? GroupCallContext
        }
    }

    public override func toggleMute() {
        self.context?.call.toggleIsMuted()
    }

    public override func showInfoWindow() {
        self.context?.present()
    }

    public override func hangUp() {
        self.context?.leave()
    }

    public override var blueColor: NSColor {
        return NSColor(rgb: 0x0078ff)
    }
    public override var grayColor: NSColor {
        return NSColor(rgb: 0x33c659)
    }

    public override func hide(_ animated: Bool) {
        super.hide(true)
        audioLevelDisposable.set(nil)
    }

    public override func update(with contextObject: Any) {
        super.update(with: contextObject)

        let context = contextObject as! GroupCallContext

        backgroundView.isFlat = context.call.sharedContext.isLite(.blur)

        let peerId = context.call.peerId

        let data = context.call.summaryState
        |> filter { $0 != nil }
        |> map { $0! }
        |> map { summary -> GroupCallPanelData in
            return GroupCallPanelData(
                peerId: peerId,
                isChannel: summary.callState.isChannel,
                info: summary.info,
                topParticipants: summary.topParticipants,
                participantCount: summary.participantCount,
                activeSpeakers: summary.activeSpeakers,
                groupCall: nil
            )
        }

        let signal = Signal<Peer?, NoError>.single(context.call.peer)

        var isReady = false
        disposable.set(combineLatest(queue: .mainQueue(), context.call.state, context.call.isMuted, data, signal, appearanceSignal, context.call.members).start(next: { [weak self] state, isMuted, data, peer, _, members in
            guard let self else {
                return
            }
            let title: String
            if let custom = state.title, !custom.isEmpty {
                title = custom
            } else {
                title = peer?.displayTitle ?? strings().callGroupCall
            }
            let model = GroupCallHeaderModel(title: title, state: state, isMuted: isMuted, data: data, members: members, theme: theme)
            if model != self.currentModel {
                self.currentModel = model
                self.apply(model)
            }
            if !isReady {
                isReady = true
                self.ready.set(.single(true))
            }
        }))

        hideDisposable.set((context.call.canBeRemoved |> deliverOnMainQueue).start(next: { [weak self] value in
            if value {
                self?.hide(true)
            }
        }))
        let isVisible = context.window.window.takeOcclusionState |> map { $0.contains(.visible) }
        let isConnected = context.call.state |> map { state -> Bool in
            if case .connected = state.networkState {
                return true
            }
            return false
        } |> distinctUntilChanged
        let effectiveLevel = combineLatest(isVisible, .single([]) |> then(context.call.audioLevels), isConnected)
        |> map { isVisible, audioLevels, isConnected -> Float in
            guard isVisible, isConnected, !audioLevels.isEmpty else {
                return 0
            }
            let level = audioLevels.reduce(0, { $0 + $1.2 }) / Float(audioLevels.count)
            return (level * 50).rounded() / 50
        }
        |> distinctUntilChanged
        self.audioLevelDisposable.set((effectiveLevel |> deliverOnMainQueue).start(next: { [weak self] level in
            self?.backgroundView.audioLevel = level
        }))
    }

    deinit {
        audioLevelDisposable.dispose()
    }


    private var currentModel: GroupCallHeaderModel?

    private func apply(_ model: GroupCallHeaderModel) {
        setInfo(model.title)
        self.status = model.status
        self.backgroundView.speaking = (model.speaking.0, model.speaking.1, model.speaking.2)
        setMicroIcon(model.isMuted ? theme.icons.callInlineMuted : theme.icons.callInlineUnmuted, isMuted: model.isMuted)
        needsLayout = true
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func getEndText() -> String {
        return strings().voiceChatTitleEnd
    }
    
    public override init(_ header: NavigationHeader) {
        super.init(header)
    }

}

private struct GroupCallHeaderModel: Equatable {
    let title: String
    let status: CallControllerStatusValue
    let speaking: (Bool, Bool, Bool)
    let isMuted: Bool
    let theme: ObjectIdentifier

    init(title: String, state: PresentationGroupCallState, isMuted: Bool, data: GroupCallPanelData, members: PresentationGroupCallMembers?, theme: TelegramPresentationTheme) {
        self.title = title
        self.isMuted = isMuted
        self.theme = ObjectIdentifier(theme)
        let isConnected: Bool
        switch state.networkState {
        case .connecting:
            if let scheduleTimestamp = state.scheduleTimestamp {
                self.status = .startsIn(Int(scheduleTimestamp))
                isConnected = true
            } else {
                self.status = .text(strings().voiceChatStatusConnecting, nil)
                isConnected = false
            }
        case .connected:
            if let first = data.topParticipants.first(where: { value in
                if let peer = value.peer {
                    return members?.speakingParticipants.contains(peer.id) ?? false
                } else {
                    return false
                }
            }) {
                self.status = .text(first.peer!._asPeer().compactDisplayTitle.prefixWithDots(12), nil)
            } else if state.isStream, data.participantCount == 0 {
                self.status = .text(strings().voiceChatStatusStream.lowercased(), nil)
            } else {
                self.status = .text(strings().voiceChatStatusMembersOther(data.participantCount), nil)
            }
            isConnected = true
        }
        if state.scheduleTimestamp != nil {
            self.speaking = (true, true, false)
        } else {
            self.speaking = (isConnected && !isMuted, isConnected, state.muteState?.canUnmute ?? true)
        }
    }

    static func ==(lhs: GroupCallHeaderModel, rhs: GroupCallHeaderModel) -> Bool {
        return lhs.title == rhs.title && lhs.status == rhs.status && lhs.speaking == rhs.speaking && lhs.isMuted == rhs.isMuted && lhs.theme == rhs.theme
    }
}
