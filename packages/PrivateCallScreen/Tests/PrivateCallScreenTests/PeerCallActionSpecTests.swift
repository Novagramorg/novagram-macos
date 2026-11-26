import XCTest
import TelegramCore
@testable import PrivateCallScreen

final class PeerCallActionSpecTests: XCTestCase {
    private func types(_ specs: [PeerCallActionSpec]) -> [PeerCallActionType] {
        return specs.map { $0.type }
    }

    private func spec(_ type: PeerCallActionType, in specs: [PeerCallActionSpec], file: StaticString = #filePath, line: UInt = #line) -> PeerCallActionSpec? {
        let found = specs.first(where: { $0.type == type })
        XCTAssertNotNil(found, "missing \(type)", file: file, line: line)
        return found
    }

    func testIncomingAudioRingingShowsMuteAcceptEnd() {
        let specs = peerCallActionSpecs(makeExternal(.ringing))
        XCTAssertEqual(types(specs), [.mute, .accept, .end])
        let accept = spec(.accept, in: specs)
        XCTAssertEqual(accept?.attract, true)
        XCTAssertEqual(accept?.enabled, true)
        XCTAssertEqual(spec(.mute, in: specs)?.enabled, true)
        XCTAssertEqual(spec(.mute, in: specs)?.active, false)
        XCTAssertEqual(spec(.end, in: specs)?.enabled, true)
    }

    func testIncomingVideoRingingHidesVideoAndScreencast() {
        let specs = peerCallActionSpecs(makeExternal(.ringing, videoState: .active(true)))
        XCTAssertEqual(types(specs), [.mute, .accept, .end])
    }

    func testOnlyAcceptAttracts() {
        let states: [ExternalPeerCallState.State] = [.waiting, .ringing, .requesting(ringing: true), .connecting, .active(startTime: 0, reception: 4, emoji: ""), .terminated(.ended(.busy))]
        for state in states {
            for spec in peerCallActionSpecs(makeExternal(state, videoState: .inactive(true))) {
                XCTAssertEqual(spec.attract, spec.type == .accept, "\(state) \(spec.type)")
                XCTAssertTrue(spec.interactive)
            }
        }
    }

    func testMuteReflectsStateWhileRinging() {
        let specs = peerCallActionSpecs(makeExternal(.ringing, isMuted: true))
        XCTAssertEqual(spec(.mute, in: specs)?.active, true)
        XCTAssertEqual(spec(.mute, in: specs)?.enabled, true)
    }

    func testMuteReflectsStateBeforeOutgoingCallStarts() {
        for state in [ExternalPeerCallState.State.waiting, .requesting(ringing: false), .requesting(ringing: true), .connecting] {
            let specs = peerCallActionSpecs(makeExternal(state, isMuted: true))
            XCTAssertEqual(spec(.mute, in: specs)?.active, true, "\(state)")
            XCTAssertEqual(spec(.mute, in: specs)?.enabled, true, "\(state)")
        }
    }

    func testMuteTogglesDuringActiveAndReconnecting() {
        for state in [ExternalPeerCallState.State.active(startTime: 0, reception: 4, emoji: "x"), .reconnecting(startTime: 0, reception: 1, emoji: "x")] {
            let unmuted = peerCallActionSpecs(makeExternal(state, isMuted: false))
            let muted = peerCallActionSpecs(makeExternal(state, isMuted: true))
            XCTAssertEqual(spec(.mute, in: unmuted)?.active, false, "\(state)")
            XCTAssertEqual(spec(.mute, in: muted)?.active, true, "\(state)")
            XCTAssertEqual(spec(.mute, in: muted)?.enabled, true, "\(state)")
        }
    }

    func testMuteDisabledAndInactiveOnceCallEnds() {
        let states: [ExternalPeerCallState.State] = [.terminating(nil), .terminating(.ended(.hungUp)), .terminated(nil), .terminated(.ended(.hungUp)), .terminated(.ended(.busy)), .terminated(.error(.disconnected))]
        for state in states {
            let specs = peerCallActionSpecs(makeExternal(state, isMuted: true))
            XCTAssertEqual(spec(.mute, in: specs)?.enabled, false, "\(state)")
            XCTAssertEqual(spec(.mute, in: specs)?.active, false, "\(state)")
        }
    }

    func testMuteDisabledWhenRemovable() {
        let specs = peerCallActionSpecs(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), isMuted: true, canBeRemoved: true))
        XCTAssertEqual(spec(.mute, in: specs)?.enabled, false)
        XCTAssertEqual(spec(.mute, in: specs)?.active, false)
    }

    func testAudioOnlyCallHasNoVideoButtons() {
        let specs = peerCallActionSpecs(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), videoState: .notAvailable))
        XCTAssertEqual(types(specs), [.mute, .end])
    }

    func testVideoButtonsOrderAndEnabledDuringActiveCall() {
        let specs = peerCallActionSpecs(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), videoState: .inactive(true)))
        XCTAssertEqual(types(specs), [.video, .screencast, .mute, .end])
        XCTAssertEqual(spec(.video, in: specs)?.enabled, true)
        XCTAssertEqual(spec(.screencast, in: specs)?.enabled, true)
        XCTAssertEqual(spec(.video, in: specs)?.active, false)
        XCTAssertEqual(spec(.screencast, in: specs)?.active, false)
    }

    func testVideoEnabledWhileReconnecting() {
        let specs = peerCallActionSpecs(makeExternal(.reconnecting(startTime: 0, reception: 0, emoji: ""), videoState: .inactive(true)))
        XCTAssertEqual(spec(.video, in: specs)?.enabled, true)
        XCTAssertEqual(spec(.screencast, in: specs)?.enabled, true)
    }

    func testVideoDisabledBeforeConnection() {
        for state in [ExternalPeerCallState.State.waiting, .requesting(ringing: true), .connecting] {
            let specs = peerCallActionSpecs(makeExternal(state, videoState: .active(true)))
            XCTAssertEqual(types(specs), [.video, .screencast, .mute, .end], "\(state)")
            XCTAssertEqual(spec(.video, in: specs)?.enabled, false, "\(state)")
            XCTAssertEqual(spec(.screencast, in: specs)?.enabled, false, "\(state)")
        }
    }

    func testCameraActive() {
        let specs = peerCallActionSpecs(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), videoState: .active(true), isScreenCapture: false))
        XCTAssertEqual(spec(.video, in: specs)?.active, true)
        XCTAssertEqual(spec(.screencast, in: specs)?.active, false)
    }

    func testScreencastActive() {
        let specs = peerCallActionSpecs(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), videoState: .active(true), isScreenCapture: true))
        XCTAssertEqual(spec(.video, in: specs)?.active, false)
        XCTAssertEqual(spec(.screencast, in: specs)?.active, true)
    }

    func testUnavailableOrPausedVideoIsNotActive() {
        for videoState in [ExternalPeerCallState.VideoState.active(false), .paused(true), .inactive(true), .inactive(false)] {
            let specs = peerCallActionSpecs(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), videoState: videoState))
            XCTAssertEqual(spec(.video, in: specs)?.active, false, "\(videoState)")
            XCTAssertEqual(spec(.screencast, in: specs)?.active, false, "\(videoState)")
        }
    }

    func testRedialAfterBusy() {
        let specs = peerCallActionSpecs(makeExternal(.terminated(.ended(.busy)), videoState: .inactive(true)))
        XCTAssertEqual(types(specs), [.mute, .redial, .end])
        XCTAssertEqual(spec(.redial, in: specs)?.enabled, true)
        XCTAssertEqual(spec(.redial, in: specs)?.attract, false)
        XCTAssertEqual(spec(.end, in: specs)?.enabled, true)
    }

    func testRedialAfterDisconnect() {
        let specs = peerCallActionSpecs(makeExternal(.terminated(.error(.disconnected))))
        XCTAssertEqual(types(specs), [.mute, .redial, .end])
    }

    func testNoRedialForOtherEndings() {
        let reasons: [PeerCallSessionTerminationReason?] = [nil, .ended(.hungUp), .ended(.missed), .ended(.switchedToConference), .error(.generic), .error(.privacyRestricted), .error(.notSupportedByPeer(isVideo: false)), .error(.serverProvided(text: "x"))]
        for reason in reasons {
            let specs = peerCallActionSpecs(makeExternal(.terminated(reason)))
            XCTAssertFalse(types(specs).contains(.redial), "\(String(describing: reason))")
        }
    }

    func testRedialNotOfferedWhileStillTerminating() {
        let specs = peerCallActionSpecs(makeExternal(.terminating(.ended(.busy))))
        XCTAssertFalse(types(specs).contains(.redial))
    }

    func testEndedVideoCallKeepsDisabledVideoButtons() {
        let specs = peerCallActionSpecs(makeExternal(.terminated(.ended(.hungUp)), videoState: .active(true)))
        XCTAssertEqual(types(specs), [.video, .screencast, .mute, .end])
        XCTAssertEqual(spec(.video, in: specs)?.enabled, false)
        XCTAssertEqual(spec(.screencast, in: specs)?.enabled, false)
    }

    func testEndDisabledOnlyWhenRemovable() {
        XCTAssertEqual(spec(.end, in: peerCallActionSpecs(makeExternal(.terminated(.ended(.hungUp)))))?.enabled, true)
        XCTAssertEqual(spec(.end, in: peerCallActionSpecs(makeExternal(.terminated(.ended(.hungUp)), canBeRemoved: true)))?.enabled, false)
        XCTAssertEqual(spec(.video, in: peerCallActionSpecs(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), videoState: .inactive(true), canBeRemoved: true)))?.enabled, false)
    }

    func testActionTypesAreUniqueInEveryState() {
        let states: [ExternalPeerCallState.State] = [.waiting, .ringing, .requesting(ringing: false), .requesting(ringing: true), .connecting, .active(startTime: 0, reception: nil, emoji: ""), .reconnecting(startTime: 0, reception: nil, emoji: ""), .terminating(nil), .terminated(nil), .terminated(.ended(.busy))]
        let videoStates: [ExternalPeerCallState.VideoState] = [.notAvailable, .inactive(true), .active(true), .paused(true)]
        for state in states {
            for videoState in videoStates {
                for isMuted in [false, true] {
                    for canBeRemoved in [false, true] {
                        let specs = peerCallActionSpecs(makeExternal(state, videoState: videoState, isMuted: isMuted, canBeRemoved: canBeRemoved))
                        XCTAssertEqual(Set(types(specs)).count, specs.count)
                        XCTAssertEqual(specs.last?.type, .end)
                        XCTAssertTrue(types(specs).contains(.mute))
                    }
                }
            }
        }
    }

    func testActionsSortedByStableIdMatchOrder() {
        let specs = peerCallActionSpecs(makeExternal(.active(startTime: 0, reception: 4, emoji: ""), videoState: .inactive(true)))
        let rawValues = specs.map { $0.type.rawValue }
        XCTAssertEqual(rawValues, rawValues.sorted())
        let ringing = peerCallActionSpecs(makeExternal(.ringing)).map { $0.type.rawValue }
        XCTAssertEqual(ringing, ringing.sorted())
        let redial = peerCallActionSpecs(makeExternal(.terminated(.ended(.busy)))).map { $0.type.rawValue }
        XCTAssertEqual(redial, redial.sorted())
    }
}
