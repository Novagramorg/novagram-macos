import Foundation
import AppKit
import XCTest
import TelegramCore
import Postbox
import Localization
@testable import PrivateCallScreen

enum TestStrings {
    static let loaded: Bool = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Telegram-Mac/en.lproj/Localizable.strings")
        guard let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            return false
        }
        let entries = dict.map { LocalizationEntry.string(key: $0.key, value: $0.value) }
        let localization = TelegramCore.Localization(version: 0, entries: entries)
        let component = LocalizationComponent(languageCode: "en", localizedName: "English", localization: localization, customPluralizationCode: nil)
        applyUILocalization(LocalizationSettings(primaryComponent: component, secondaryComponent: nil))
        return true
    }()
}

func makeUser(id: Int64 = 1, firstName: String?, lastName: String? = nil, username: String? = nil) -> EnginePeer {
    return .user(TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: firstName, lastName: lastName, username: username, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
}

func makeExternal(
    _ state: ExternalPeerCallState.State,
    videoState: ExternalPeerCallState.VideoState = .notAvailable,
    remoteVideoState: ExternalPeerCallState.RemoteVideoState = .inactive,
    isMuted: Bool = false,
    remoteAudioState: ExternalPeerCallState.RemoteAudioState = .active,
    remoteBatteryLevel: ExternalPeerCallState.RemoteBatteryLevel = .normal,
    isScreenCapture: Bool = false,
    canBeRemoved: Bool = false,
    conferenceReference: MessageId? = nil
) -> ExternalPeerCallState {
    return ExternalPeerCallState(state: state, videoState: videoState, remoteVideoState: remoteVideoState, isMuted: isMuted, isOutgoingVideoPaused: false, remoteAspectRatio: 1.0, remoteAudioState: remoteAudioState, remoteBatteryLevel: remoteBatteryLevel, isScreenCapture: isScreenCapture, canBeRemoved: canBeRemoved, participants: [], conferenceReference: conferenceReference, supportsConferenceCalls: true)
}

func makeState(_ external: ExternalPeerCallState, peer: EnginePeer? = nil, accountPeer: EnginePeer? = nil) -> PeerCallState {
    var state = PeerCallState()
    state.externalState = external
    state.peer = peer
    state.accountPeer = accountPeer
    return state
}

func startedSecondsAgo(_ seconds: Double) -> Double {
    return CFAbsoluteTimeGetCurrent() - seconds
}

let conferenceMessageId = MessageId(peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(9)), namespace: Namespaces.Message.Cloud, id: 42)

enum TestTheme {
    static let prepared: Void = {
        _ = NSApplication.shared
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand"] where NSImage(named: name) == nil {
            let image = NSImage(size: NSSize(width: 10, height: 10))
            image.lockFocus()
            NSColor.gray.setFill()
            NSRect(x: 0, y: 0, width: 10, height: 10).fill()
            image.unlockFocus()
            image.setName(name)
        }
    }()
}
