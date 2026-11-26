import XCTest
import TelegramCore
@testable import TelegramCallsCore

final class CallTerminationTests: XCTestCase {
    private let callId = CallId(id: 1, accessHash: 2)

    func testNonTerminatedStatesHaveNoOutcome() {
        XCTAssertNil(callTerminationOutcome(.ringing))
        XCTAssertNil(callTerminationOutcome(.accepting))
        XCTAssertNil(callTerminationOutcome(.requesting(ringing: true)))
        XCTAssertNil(callTerminationOutcome(.dropping(reason: .ended(.hungUp))))
        XCTAssertNil(callTerminationOutcome(.switchedToConference(slug: "x")))
    }

    func testNormalHangUpWithoutRating() {
        XCTAssertEqual(callTerminationOutcome(.terminated(id: callId, reason: .ended(.hungUp), options: [])), CallTerminationOutcome(error: nil, ratingCallId: nil))
    }

    func testRatingRequested() {
        XCTAssertEqual(callTerminationOutcome(.terminated(id: callId, reason: .ended(.hungUp), options: [.reportRating])), CallTerminationOutcome(error: nil, ratingCallId: callId))
    }

    func testRatingNeedsCallId() {
        XCTAssertEqual(callTerminationOutcome(.terminated(id: nil, reason: .ended(.hungUp), options: [.reportRating])), CallTerminationOutcome(error: nil, ratingCallId: nil))
    }

    func testErrorsAreReported() {
        let errors: [CallSessionError] = [.generic, .privacyRestricted, .notSupportedByPeer(isVideo: true), .serverProvided(text: "text"), .disconnected]
        for error in errors {
            XCTAssertEqual(callTerminationOutcome(.terminated(id: callId, reason: .error(error), options: [])), CallTerminationOutcome(error: error, ratingCallId: nil), "\(error)")
        }
    }

    func testErrorAndRatingTogether() {
        XCTAssertEqual(callTerminationOutcome(.terminated(id: callId, reason: .error(.disconnected), options: [.reportRating])), CallTerminationOutcome(error: .disconnected, ratingCallId: callId))
    }

    func testEndedTypesAreNotErrors() {
        for type in [CallSessionEndedType.hungUp, .busy, .missed, .switchedToConference(slug: "x")] {
            XCTAssertNil(callTerminationOutcome(.terminated(id: callId, reason: .ended(type), options: []))?.error, "\(type)")
        }
    }
}
