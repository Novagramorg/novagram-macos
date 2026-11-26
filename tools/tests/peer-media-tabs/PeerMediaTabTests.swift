import XCTest
import SwiftSignalKit

enum PeerMediaCollectionMode: Equatable { case photos, files, links }
final class ViewController {
    let ready = Promise<Bool>()
}
struct GenericView { var mainTable = 0 }
final class MediaController {
    var mode: PeerMediaCollectionMode? = .photos
    let modeValue = ValuePromise<PeerMediaCollectionMode?>(.photos, ignoreRepeated: true)
    let toggleDisposable = MetaDisposable()
    let genericView = GenericView()
    var currentMainTableView: ((Int, Bool, Bool) -> Void)?
    let controllers: [PeerMediaCollectionMode: ViewController] = [.photos: ViewController(), .files: ViewController(), .links: ViewController()]
    var applied: [PeerMediaCollectionMode] = []

    func controller(for mode: PeerMediaCollectionMode) -> ViewController { controllers[mode]! }
    func applyReadyController(mode: PeerMediaCollectionMode, animated: Bool) {
        self.mode = mode
        applied.append(mode)
    }
    func select(_ mode: PeerMediaCollectionMode) { toggle(with: mode, animated: true) }
    __TOGGLE__
    deinit { toggleDisposable.dispose() }
}

final class PeerMediaTabTests: XCTestCase {
    func testReturningToVisibleTabCancelsPendingSelection() {
        let media = MediaController()
        media.select(.files)
        media.select(.photos)
        media.controller(for: .files).ready.set(.single(true))
        XCTAssertEqual(media.mode, .photos)
        XCTAssertEqual(media.applied, [])
    }

    func testNewestPendingSelectionWins() {
        let media = MediaController()
        media.select(.files)
        media.select(.links)
        media.controller(for: .files).ready.set(.single(true))
        XCTAssertEqual(media.applied, [])
        media.controller(for: .links).ready.set(.single(true))
        XCTAssertEqual(media.applied, [.links])
    }

    func testReadySelectionAppliesImmediatelyAndOnlyOnce() {
        let media = MediaController()
        media.controller(for: .files).ready.set(.single(true))
        media.select(.files)
        media.select(.files)
        XCTAssertEqual(media.applied, [.files])
    }

    func testReselectVisibleTabRetainsTableCallback() {
        let media = MediaController()
        var calls = 0
        media.currentMainTableView = { _, animated, changed in
            XCTAssertTrue(animated)
            XCTAssertFalse(changed)
            calls += 1
        }
        media.select(.photos)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(media.applied, [])
    }

    func testControllerIsReleasedWhileTabIsLoading() {
        var media: MediaController? = MediaController()
        weak var weakMedia = media
        let files = media!.controller(for: .files)
        media?.select(.files)
        media = nil
        XCTAssertNil(weakMedia)
        files.ready.set(.single(true))
    }
}
