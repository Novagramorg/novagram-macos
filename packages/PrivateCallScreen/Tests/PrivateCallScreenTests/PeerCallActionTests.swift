import XCTest
import TelegramCore
import Localization
@testable import PrivateCallScreen

final class PeerCallActionTests: XCTestCase {
    private let allTypes: [PeerCallActionType] = [.video, .screencast, .mute, .accept, .redial, .end]

    func testActionImagesAreCachedPerType() {
        for type in allTypes {
            let first = makeAction(type: type, text: type.title, resource: type.resource, action: {})
            let second = makeAction(type: type, text: type.title, resource: type.resource, active: true, enabled: false, action: {})
            XCTAssertTrue(first.normal === second.normal, "\(type)")
            XCTAssertNotNil(first.activeImage, "\(type)")
            XCTAssertTrue(first.activeImage === second.activeImage, "\(type)")
        }
    }

    func testDifferentTypesUseDifferentImages() {
        let images = allTypes.map { makeAction(type: $0, text: "", resource: $0.resource, action: {}).normal }
        for i in 0 ..< images.count {
            for j in i + 1 ..< images.count {
                XCTAssertFalse(images[i] === images[j], "\(allTypes[i]) vs \(allTypes[j])")
            }
        }
    }

    func testActionImageIsCircleSized() {
        for type in allTypes {
            let action = makeAction(type: type, text: "", resource: type.resource, action: {})
            XCTAssertEqual(CGFloat(action.normal.width) / CGFloat(action.normal.height), 1, "\(type)")
            XCTAssertGreaterThanOrEqual(action.normal.width, 50, "\(type)")
        }
    }

    func testActiveImageUsedOnlyWhenActive() {
        let inactive = makeAction(type: .mute, text: "", resource: .icMute, active: false, action: {})
        let active = makeAction(type: .mute, text: "", resource: .icMute, active: true, action: {})
        XCTAssertTrue(inactive.image === inactive.normal)
        XCTAssertTrue(active.image === active.activeImage)
    }

    func testEqualityIgnoresClosureButTracksState() {
        let a = makeAction(type: .mute, text: "a", resource: .icMute, active: false, action: {})
        let b = makeAction(type: .mute, text: "b", resource: .icMute, active: false, action: {})
        let c = makeAction(type: .mute, text: "a", resource: .icMute, active: true, action: {})
        let d = makeAction(type: .mute, text: "a", resource: .icMute, enabled: false, action: {})
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }

    func testActionInvokesClosure() {
        var count = 0
        let action = makeAction(type: .end, text: "", resource: .icDecline, action: { count += 1 })
        action.action()
        XCTAssertEqual(count, 1)
    }

    func testTitlesAndResourcesMatchType() {
        _ = TestStrings.loaded
        XCTAssertEqual(PeerCallActionType.end.title, L10n.callEnd)
        XCTAssertEqual(PeerCallActionType.redial.title, L10n.callRecall)
        XCTAssertEqual(PeerCallActionType.accept.title, L10n.callAccept)
        XCTAssertEqual(PeerCallActionType.mute.title, L10n.callMute)
        XCTAssertEqual(PeerCallActionType.screencast.title, L10n.callScreen)
        XCTAssertEqual(PeerCallActionType.video.title, L10n.callVideo)
        XCTAssertEqual(Set(allTypes.map { $0.title }).count, allTypes.count)
    }
}
