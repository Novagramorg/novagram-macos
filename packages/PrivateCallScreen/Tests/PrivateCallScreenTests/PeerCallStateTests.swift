import XCTest
import TelegramCore
import Localization
@testable import PrivateCallScreen

final class PeerCallStateTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestStrings.loaded
    }

    func testEnglishStringsLoaded() {
        XCTAssertTrue(TestStrings.loaded)
        XCTAssertNotEqual(L10n.callStatusBusy, "Call.StatusBusy")
        XCTAssertNotEqual(L10n.callStatusBusy, L10n.callStatusEnded)
    }

    func testDefaultStateHasNoWarnings() {
        let state = PeerCallState()
        XCTAssertEqual(state.externalState.remoteBatteryLevel, .normal)
        XCTAssertEqual(state.externalState.remoteAudioState, .active)
        XCTAssertFalse(state.externalState.isMuted)
        XCTAssertTrue(peerCallStatusTooltipFlags(state).isEmpty)
        XCTAssertEqual(peerCallMicroTooltips(state), [])
        XCTAssertEqual(state.secretKeyViewState, .concealed)
    }

    func testStatusTexts() {
        let cases: [(ExternalPeerCallState.State, String)] = [
            (.waiting, L10n.callStatusConnecting),
            (.connecting, L10n.callStatusConnecting),
            (.requesting(ringing: false), L10n.callStatusRequesting),
            (.requesting(ringing: true), L10n.callStatusRinging),
            (.terminating(nil), L10n.callStatusEnded),
            (.terminated(nil), L10n.callStatusEnded),
            (.terminated(.ended(.busy)), L10n.callStatusBusy),
            (.terminating(.ended(.busy)), L10n.callStatusBusy),
            (.terminated(.ended(.hungUp)), L10n.callStatusEnded),
            (.terminated(.ended(.missed)), L10n.callStatusEnded),
            (.terminated(.ended(.switchedToConference)), L10n.callStatusSwitchingToConference),
            (.terminated(.error(.generic)), L10n.callStatusFailed),
            (.terminated(.error(.disconnected)), L10n.callStatusFailed),
            (.terminated(.error(.privacyRestricted)), L10n.callStatusFailed),
            (.ringing, L10n.callStatusCalling),
        ]
        for (callState, text) in cases {
            XCTAssertEqual(makeState(makeExternal(callState)).status, .text(text, nil), "\(callState)")
        }
    }

    func testActiveStatusIsTimerWithReception() {
        let state = makeState(makeExternal(.active(startTime: 100, reception: 3, emoji: "")))
        XCTAssertEqual(state.status, .timer(100, 3))
        XCTAssertTrue(state.status.hasTimer)
    }

    func testReconnectingStatusKeepsReception() {
        let state = makeState(makeExternal(.reconnecting(startTime: 100, reception: 1, emoji: "")))
        XCTAssertEqual(state.status, .text(L10n.callStatusConnecting, 1))
        XCTAssertFalse(state.status.hasTimer)
    }

    func testRemovableAlwaysShowsEnded() {
        let states: [ExternalPeerCallState.State] = [.ringing, .connecting, .active(startTime: 0, reception: 4, emoji: ""), .terminated(.ended(.busy))]
        for callState in states {
            XCTAssertEqual(makeState(makeExternal(callState, canBeRemoved: true)).status, .text(L10n.callStatusEnded, nil), "\(callState)")
        }
    }

    func testRingingShowsAccountUsernameFirst() {
        let account = makeUser(id: 2, firstName: "Bob", username: "bobby")
        let status = makeState(makeExternal(.ringing), accountPeer: account).status
        XCTAssertEqual(status, .text(L10n.callStatusCallingAccount("bobby"), nil))
        guard case let .text(text, _) = status else {
            return XCTFail()
        }
        XCTAssertTrue(text.contains("bobby"), text)
    }

    func testRingingFallsBackToAccountFirstName() {
        let account = makeUser(id: 2, firstName: "Bob")
        let status = makeState(makeExternal(.ringing), accountPeer: account).status
        guard case let .text(text, _) = status else {
            return XCTFail()
        }
        XCTAssertTrue(text.contains("Bob"), text)
    }

    func testRingingConferenceTexts() {
        let account = makeUser(id: 2, firstName: "Bob", username: "bobby")
        XCTAssertEqual(makeState(makeExternal(.ringing, conferenceReference: conferenceMessageId), accountPeer: account).status, .text(L10n.callStatusGroupCallAccount("bobby"), nil))
        XCTAssertEqual(makeState(makeExternal(.ringing, conferenceReference: conferenceMessageId)).status, .text(L10n.callStatusGroupCall, nil))
    }

    func testIsActive() {
        let active: [ExternalPeerCallState.State] = [.requesting(ringing: false), .requesting(ringing: true), .connecting, .active(startTime: 0, reception: nil, emoji: ""), .reconnecting(startTime: 0, reception: nil, emoji: "")]
        let inactive: [ExternalPeerCallState.State] = [.waiting, .ringing, .terminating(nil), .terminated(nil)]
        for callState in active {
            XCTAssertTrue(makeState(makeExternal(callState)).isActive, "\(callState)")
            XCTAssertFalse(makeState(makeExternal(callState, canBeRemoved: true)).isActive, "\(callState)")
        }
        for callState in inactive {
            XCTAssertFalse(makeState(makeExternal(callState)).isActive, "\(callState)")
        }
    }

    func testReceptionAndSecretKey() {
        XCTAssertEqual(makeState(makeExternal(.active(startTime: 0, reception: 2, emoji: "🐱🐶🐭🐹"))).reception, 2)
        XCTAssertEqual(makeState(makeExternal(.active(startTime: 0, reception: 2, emoji: "🐱🐶🐭🐹"))).secretKey, "🐱🐶🐭🐹")
        XCTAssertEqual(makeState(makeExternal(.reconnecting(startTime: 0, reception: 0, emoji: "🐱"))).reception, 0)
        XCTAssertEqual(makeState(makeExternal(.reconnecting(startTime: 0, reception: 0, emoji: "🐱"))).secretKey, "🐱")
        for callState in [ExternalPeerCallState.State.waiting, .ringing, .connecting, .requesting(ringing: true), .terminated(nil)] {
            XCTAssertNil(makeState(makeExternal(callState)).reception, "\(callState)")
            XCTAssertNil(makeState(makeExternal(callState)).secretKey, "\(callState)")
        }
    }

    func testSeconds() {
        XCTAssertEqual(makeState(makeExternal(.active(startTime: startedSecondsAgo(10.5), reception: 4, emoji: ""))).seconds, 10)
        XCTAssertEqual(makeState(makeExternal(.reconnecting(startTime: startedSecondsAgo(3.2), reception: 4, emoji: ""))).seconds, 3)
        XCTAssertEqual(makeState(makeExternal(.connecting)).seconds, 0)
        XCTAssertEqual(makeState(makeExternal(.ringing)).seconds, 0)
    }

    func testStateIndex() {
        XCTAssertEqual(makeState(makeExternal(.waiting)).stateIndex, 0)
        XCTAssertEqual(makeState(makeExternal(.ringing)).stateIndex, 0)
        XCTAssertEqual(makeState(makeExternal(.requesting(ringing: true))).stateIndex, 0)
        XCTAssertEqual(makeState(makeExternal(.connecting)).stateIndex, 1)
        XCTAssertEqual(makeState(makeExternal(.active(startTime: startedSecondsAgo(10), reception: 4, emoji: ""))).stateIndex, 1)
        XCTAssertEqual(makeState(makeExternal(.active(startTime: startedSecondsAgo(10), reception: nil, emoji: ""))).stateIndex, 1)
        XCTAssertEqual(makeState(makeExternal(.active(startTime: startedSecondsAgo(10), reception: 1, emoji: ""))).stateIndex, 2)
        XCTAssertEqual(makeState(makeExternal(.active(startTime: startedSecondsAgo(1), reception: 1, emoji: ""))).stateIndex, 1)
        XCTAssertEqual(makeState(makeExternal(.reconnecting(startTime: 0, reception: 4, emoji: ""))).stateIndex, 2)
        XCTAssertEqual(makeState(makeExternal(.terminating(nil))).stateIndex, 0)
        XCTAssertEqual(makeState(makeExternal(.terminated(nil))).stateIndex, 0)
        XCTAssertEqual(makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), conferenceReference: conferenceMessageId)).stateIndex, 3)
    }

    func testTitles() {
        let state = makeState(makeExternal(.ringing), peer: makeUser(firstName: "Anna", lastName: "Smith"))
        XCTAssertEqual(state.title, "Anna Smith")
        XCTAssertEqual(state.compactTitle, "Anna")
        let lastOnly = makeState(makeExternal(.ringing), peer: makeUser(firstName: nil, lastName: "Smith"))
        XCTAssertEqual(lastOnly.title, "Smith")
        XCTAssertEqual(lastOnly.compactTitle, "Smith")
        let none = makeState(makeExternal(.ringing))
        XCTAssertNil(none.title)
        XCTAssertEqual(none.compactTitle, "")
    }

    func testSecretKeyViewStateToggle() {
        XCTAssertEqual(PeerCallState.SecretKeyViewState.concealed.rev, .revealed)
        XCTAssertEqual(PeerCallState.SecretKeyViewState.revealed.rev, .concealed)
    }

    func testRecall() {
        XCTAssertTrue(PeerCallSessionTerminationReason.ended(.busy).recall)
        XCTAssertTrue(PeerCallSessionTerminationReason.error(.disconnected).recall)
        XCTAssertFalse(PeerCallSessionTerminationReason.ended(.hungUp).recall)
        XCTAssertFalse(PeerCallSessionTerminationReason.ended(.missed).recall)
        XCTAssertFalse(PeerCallSessionTerminationReason.ended(.switchedToConference).recall)
        XCTAssertFalse(PeerCallSessionTerminationReason.error(.generic).recall)
        XCTAssertFalse(PeerCallSessionTerminationReason.error(.privacyRestricted).recall)
        XCTAssertFalse(PeerCallSessionTerminationReason.error(.notSupportedByPeer(isVideo: true)).recall)
        XCTAssertFalse(PeerCallSessionTerminationReason.error(.serverProvided(text: "")).recall)
    }
}

final class PeerCallTooltipTests: XCTestCase {
    func testOwnMicroOffOnlyWhileActive() {
        let active = makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), isMuted: true), peer: makeUser(firstName: "Anna"))
        XCTAssertEqual(peerCallMicroTooltips(active), [.yourMicroOff])
        for callState in [ExternalPeerCallState.State.connecting, .requesting(ringing: true), .reconnecting(startTime: 0, reception: 1, emoji: "")] {
            XCTAssertEqual(peerCallMicroTooltips(makeState(makeExternal(callState, isMuted: true))), [.yourMicroOff], "\(callState)")
        }
        for callState in [ExternalPeerCallState.State.ringing, .waiting, .terminating(nil), .terminated(.ended(.hungUp))] {
            XCTAssertEqual(peerCallMicroTooltips(makeState(makeExternal(callState, isMuted: true))), [], "\(callState)")
        }
        XCTAssertEqual(peerCallMicroTooltips(makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), isMuted: true, canBeRemoved: true))), [])
    }

    func testRemoteMicroOffUsesCompactName() {
        let state = makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), remoteAudioState: .muted), peer: makeUser(firstName: "Anna", lastName: "Smith"))
        XCTAssertEqual(peerCallMicroTooltips(state), [.microOff("Anna")])
    }

    func testBothMicroTooltipsInOrder() {
        let state = makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), isMuted: true, remoteAudioState: .muted), peer: makeUser(firstName: "Anna"))
        XCTAssertEqual(peerCallMicroTooltips(state), [.yourMicroOff, .microOff("Anna")])
    }

    func testUnmutingClearsTooltip() {
        let muted = makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), isMuted: true))
        var unmuted = muted
        unmuted.externalState.isMuted = false
        XCTAssertEqual(peerCallMicroTooltips(muted), [.yourMicroOff])
        XCTAssertEqual(peerCallMicroTooltips(unmuted), [])
    }

    func testLowSignalNeedsWeakReceptionAfterGracePeriod() {
        XCTAssertTrue(peerCallStatusTooltipFlags(makeState(makeExternal(.active(startTime: startedSecondsAgo(10), reception: 1, emoji: "")))).lowSignal)
        XCTAssertTrue(peerCallStatusTooltipFlags(makeState(makeExternal(.active(startTime: startedSecondsAgo(10), reception: 0, emoji: "")))).lowSignal)
        XCTAssertTrue(peerCallStatusTooltipFlags(makeState(makeExternal(.reconnecting(startTime: startedSecondsAgo(10), reception: 1, emoji: "")))).lowSignal)
        XCTAssertFalse(peerCallStatusTooltipFlags(makeState(makeExternal(.active(startTime: startedSecondsAgo(2), reception: 1, emoji: "")))).lowSignal)
        XCTAssertFalse(peerCallStatusTooltipFlags(makeState(makeExternal(.active(startTime: startedSecondsAgo(10), reception: 2, emoji: "")))).lowSignal)
        XCTAssertFalse(peerCallStatusTooltipFlags(makeState(makeExternal(.active(startTime: startedSecondsAgo(10), reception: nil, emoji: "")))).lowSignal)
        XCTAssertFalse(peerCallStatusTooltipFlags(makeState(makeExternal(.active(startTime: startedSecondsAgo(10), reception: 1, emoji: ""), canBeRemoved: true))).lowSignal)
    }

    func testLowBatteryOnlyWhileConnected() {
        XCTAssertTrue(peerCallStatusTooltipFlags(makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), remoteBatteryLevel: .low))).lowBattery)
        XCTAssertTrue(peerCallStatusTooltipFlags(makeState(makeExternal(.reconnecting(startTime: 0, reception: 4, emoji: ""), remoteBatteryLevel: .low))).lowBattery)
        for callState in [ExternalPeerCallState.State.waiting, .ringing, .requesting(ringing: true), .connecting, .terminating(nil), .terminated(nil)] {
            XCTAssertFalse(peerCallStatusTooltipFlags(makeState(makeExternal(callState, remoteBatteryLevel: .low))).lowBattery, "\(callState)")
        }
        XCTAssertFalse(peerCallStatusTooltipFlags(makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), remoteBatteryLevel: .low, canBeRemoved: true))).lowBattery)
        XCTAssertFalse(peerCallStatusTooltipFlags(makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), remoteBatteryLevel: .normal))).lowBattery)
    }

    func testFlagsIsEmpty() {
        XCTAssertTrue(PeerCallStatusTooltipFlags(lowSignal: false, lowBattery: false).isEmpty)
        XCTAssertFalse(PeerCallStatusTooltipFlags(lowSignal: true, lowBattery: false).isEmpty)
        XCTAssertFalse(PeerCallStatusTooltipFlags(lowSignal: false, lowBattery: true).isEmpty)
    }
}

final class PeerCallStateApplyTests: XCTestCase {
    func testRevealedKeyStaysWhileKeyExists() {
        var state = makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: "🐱")))
        state.secretKeyViewState = .revealed
        let updated = peerCallState(state, applying: makeExternal(.reconnecting(startTime: 0, reception: 1, emoji: "🐱")), actions: [])
        XCTAssertEqual(updated.secretKeyViewState, .revealed)
    }

    func testRevealedKeyConcealedWhenCallEnds() {
        var state = makeState(makeExternal(.active(startTime: 0, reception: 4, emoji: "🐱")))
        state.secretKeyViewState = .revealed
        for callState in [ExternalPeerCallState.State.terminating(nil), .terminated(.ended(.hungUp)), .connecting] {
            let updated = peerCallState(state, applying: makeExternal(callState), actions: [])
            XCTAssertEqual(updated.secretKeyViewState, .concealed, "\(callState)")
        }
    }

    func testApplyKeepsLocalUiState() {
        var state = makeState(makeExternal(.ringing), peer: makeUser(firstName: "Anna"))
        state.smallVideo = .incoming
        state.mouseInside = false
        state.statusTooltip = "tip"
        let action = makeAction(type: .end, text: "", resource: .icDecline, action: {})
        let updated = peerCallState(state, applying: makeExternal(.connecting, isMuted: true), actions: [action])
        XCTAssertEqual(updated.smallVideo, .incoming)
        XCTAssertFalse(updated.mouseInside)
        XCTAssertEqual(updated.statusTooltip, "tip")
        XCTAssertEqual(updated.peer?.id, state.peer?.id)
        XCTAssertEqual(updated.externalState.state, .connecting)
        XCTAssertTrue(updated.externalState.isMuted)
        XCTAssertEqual(updated.actions.map { $0.stableId }, [.end])
    }

    func testStateIndexAlwaysHasFallbackColors() {
        let states: [ExternalPeerCallState.State] = [.waiting, .ringing, .requesting(ringing: true), .connecting, .active(startTime: 0, reception: 0, emoji: ""), .active(startTime: startedSecondsAgo(10), reception: 1, emoji: ""), .reconnecting(startTime: 0, reception: 0, emoji: ""), .terminating(nil), .terminated(nil)]
        for callState in states {
            for conference in [nil, conferenceMessageId] {
                let index = makeState(makeExternal(callState, conferenceReference: conference)).stateIndex
                XCTAssertTrue(colorSets_fallback.indices.contains(index), "\(callState) \(index)")
                XCTAssertEqual(colorSets_fallback[index].count, 4)
            }
        }
    }
}
