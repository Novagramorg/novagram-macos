import AppKit
import XCTest
import SwiftSignalKit

private var viewer: Gallery?
private var pipResumes = 0
func playPipIfNeeded() { pipResumes += 1 }
final class Analytics {
    static let shared = Analytics()
    let screens = Screens()
}
final class Screens {
    func hideStandalone(owner: AnyObject) {}
}
final class Background {
    func _change(opacity: CGFloat, animated: Bool) {}
}
final class Controls { func animateOut() {} }
final class Window {
    var visible = true
    func orderOut(_ sender: Any?) { visible = false }
}
final class Delegate {
    var finished = 0
    func contentInteractionView(for id: AnyHashable, animateIn: Bool) -> NSView? { nil }
    func interactionControllerDidFinishAnimation(interactive: Bool, for id: AnyHashable) { finished += 1 }
    func addAccesoryOnCopiedView(for id: AnyHashable, view: NSView) {}
}
final class AnalyticsOrigin {
    var active = false
    func restrict(messages: [Int]) {}
    func begin() { active = true }
    func end() { active = false }
}
struct GalleryEntry { var message: Int? }
struct GalleryItem { var entry: GalleryEntry }
final class Pager {
    var selectedItem: GalleryItem?
    var completions: [(Bool, AnyHashable?) -> Void] = []
    func animateOut(to: @escaping (AnyHashable) -> NSView?, completion: @escaping (Bool, AnyHashable?) -> Void, addAccesoryOnCopiedView: @escaping (AnyHashable?, NSView) -> Void, addVideoTimebase: @escaping (AnyHashable, NSView) -> Void) {
        completions.append(completion)
    }
    func finish() {
        let pending = completions
        completions.removeAll()
        pending.forEach { $0(true, "photo") }
    }
}
final class Gallery {
    __GENERATION__
    let disposable = MetaDisposable()
    let readyDispose = MetaDisposable()
    var didSetReady = true
    let backgroundView = Background()
    let controls = Controls()
    let window = Window()
    let pager = Pager()
    let analyticsOrigin = AnalyticsOrigin()
    let delegate: Delegate? = Delegate()
    var firstStableId: AnyHashable?
    var exclusionRemoved = 0
    func removeCaptureExclusion() { exclusionRemoved += 1 }
    __SHOW__
    __CLOSE__
    deinit { disposable.dispose(); readyDispose.dispose() }
}

final class GalleryCloseTests: XCTestCase {
    override func tearDown() {
        viewer = nil
        pipResumes = 0
        super.tearDown()
    }

    func testAnimatedCloseFinishesCurrentPresentation() {
        let gallery = Gallery()
        gallery.show()
        gallery.close(true)
        XCTAssertTrue(gallery.analyticsOrigin.active)
        XCTAssertTrue(viewer === gallery)
        XCTAssertTrue(gallery.window.visible)
        gallery.pager.finish()
        XCTAssertNil(viewer)
        XCTAssertFalse(gallery.analyticsOrigin.active)
        XCTAssertFalse(gallery.window.visible)
        XCTAssertEqual(pipResumes, 1)
        XCTAssertEqual(gallery.delegate?.finished, 1)
    }

    func testLateCompletionDoesNotReleaseNewViewer() {
        let old = Gallery()
        old.show()
        old.close(true)
        old.close(false)
        let new = Gallery()
        new.show()
        old.pager.finish()
        XCTAssertTrue(viewer === new)
        XCTAssertTrue(new.window.visible)
        XCTAssertEqual(pipResumes, 1)
    }

    func testLateCompletionAfterOldViewerDeinitDoesNotReleaseNewViewer() {
        var old: Gallery? = Gallery()
        weak var weakOld = old
        old?.show()
        old?.close(true)
        old?.close(false)
        let pager = old!.pager
        old = nil
        XCTAssertNil(weakOld)
        let new = Gallery()
        new.show()
        pager.finish()
        XCTAssertTrue(viewer === new)
        XCTAssertEqual(pipResumes, 1)
    }

    func testPipReopeningSameViewerIgnoresOldCompletion() {
        let gallery = Gallery()
        gallery.show()
        gallery.close(true)
        gallery.close(false)
        gallery.show()
        gallery.window.visible = true
        gallery.pager.finish()
        XCTAssertTrue(viewer === gallery)
        XCTAssertTrue(gallery.window.visible)
        XCTAssertEqual(pipResumes, 1)
    }

    func testRepeatedCloseOnlyResumesPipOnce() {
        let gallery = Gallery()
        gallery.show()
        gallery.close(false)
        gallery.close(false)
        XCTAssertEqual(pipResumes, 1)
    }

    func testOldViewerImmediateClosePreservesCurrentViewer() {
        let old = Gallery()
        old.show()
        old.close(false)
        let new = Gallery()
        new.show()
        old.close(false)
        XCTAssertTrue(viewer === new)
        XCTAssertEqual(pipResumes, 1)
    }
}
