import XCTest
import AppKit
import TGUIKit
import TelegramCore
import Postbox
@testable import ChatUI

final class ChatMediaStatusTransitionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func image(_ id: Int64) -> TelegramMediaImage {
        return TelegramMediaImage(imageId: MediaId(namespace: 0, id: id), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
    }

    func testOnlyKindChangesOfTheSameMediaAnimate() {
        let view = ChatMediaContentView(frame: NSMakeRect(0, 0, 100, 100))
        view.media = image(1)
        XCTAssertFalse(view.hasFetchStatusForCurrentMedia)

        view.fetchStatus = .Remote(progress: 0)
        XCTAssertFalse(view.statusChangeIsAnimatable)
        XCTAssertTrue(view.hasFetchStatusForCurrentMedia)

        view.fetchStatus = .Fetching(isActive: true, progress: 0.1)
        XCTAssertTrue(view.statusChangeIsAnimatable)

        view.fetchStatus = .Fetching(isActive: true, progress: 0.4)
        XCTAssertFalse(view.statusChangeIsAnimatable)

        view.fetchStatus = .Paused(progress: 0.4)
        XCTAssertFalse(view.statusChangeIsAnimatable)

        view.fetchStatus = .Remote(progress: 0)
        XCTAssertTrue(view.statusChangeIsAnimatable)

        view.fetchStatus = .Fetching(isActive: true, progress: 0.5)
        view.fetchStatus = .Local
        XCTAssertTrue(view.statusChangeIsAnimatable)
    }

    func testReusingTheViewForAnotherMediaDoesNotAnimate() {
        let view = ChatMediaContentView(frame: NSMakeRect(0, 0, 100, 100))
        view.media = image(1)
        view.fetchStatus = .Fetching(isActive: true, progress: 0.3)

        view.media = image(2)
        XCTAssertFalse(view.hasFetchStatusForCurrentMedia)
        view.fetchStatus = .Local
        XCTAssertFalse(view.statusChangeIsAnimatable)
        XCTAssertTrue(view.hasFetchStatusForCurrentMedia)

        view.fetchStatus = nil
        XCTAssertFalse(view.hasFetchStatusForCurrentMedia)
        view.fetchStatus = .Remote(progress: 0)
        XCTAssertFalse(view.statusChangeIsAnimatable)
    }
}
