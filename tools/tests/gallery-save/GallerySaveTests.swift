import XCTest
import SwiftSignalKit

enum MediaResourceStatus { case Local, Remote }
struct Message {
    var adAttribute: Int?
    var protected = false
    func isCopyProtected(cachedData: Int?) -> Bool { protected }
}
struct Entry {
    var message: Message?
    var isProtected = false
}
class MGalleryItem {
    var entry = Entry()
    var realStatus: Signal<MediaResourceStatus, NoError> = .single(.Local)
    let path = Promise<String>()
}
final class MGalleryPhotoItem: MGalleryItem {}
final class MGalleryPeerPhotoItem: MGalleryItem {}
final class MGalleryExternalVideoItem: MGalleryItem {}
final class Pager { var selectedItem: MGalleryItem? }
final class Window { var alerts: [String] = [] }
struct Strings {
    let galleryWaitDownloadPhoto = "photo"
    let galleryWaitDownloadVideo = "video"
}
func strings() -> Strings { Strings() }
func alert(for window: Window, info: String) { window.alerts.append(info) }
final class Gallery {
    let pager = Pager()
    let window = Window()
    let operationDisposable = MetaDisposable()
    var cachedPeerData: Int?
    var saved: [String] = []
    __SAVE__
    deinit { operationDisposable.dispose() }
}

final class GallerySaveTests: XCTestCase {
    func testImmediateLocalStatusWithDelayedPath() {
        XCTAssertTrue(Thread.isMainThread)
        let gallery = Gallery()
        let item = MGalleryPhotoItem()
        gallery.pager.selectedItem = item
        gallery.saveAs()
        XCTAssertEqual(gallery.saved, [])
        item.path.set(.single("/ready/photo.jpg"))
        XCTAssertEqual(gallery.saved, ["/ready/photo.jpg"])
    }

    func testImmediatePathSavesOnlyOnce() {
        let gallery = Gallery()
        let item = MGalleryPhotoItem()
        gallery.pager.selectedItem = item
        item.path.set(.single("/ready/photo.jpg"))
        gallery.saveAs()
        item.path.set(.single("/late/photo.jpg"))
        XCTAssertEqual(gallery.saved, ["/ready/photo.jpg"])
    }

    func testDelayedStatusAndDelayedPath() {
        let gallery = Gallery()
        let item = MGalleryPhotoItem()
        let status = Promise<MediaResourceStatus>()
        item.realStatus = status.get()
        gallery.pager.selectedItem = item
        gallery.saveAs()
        status.set(.single(.Local))
        item.path.set(.single("/ready/photo.jpg"))
        XCTAssertEqual(gallery.saved, ["/ready/photo.jpg"])
    }

    func testNewestSaveCancelsPreviousPathWait() {
        let gallery = Gallery()
        let first = MGalleryPhotoItem()
        let second = MGalleryPhotoItem()
        gallery.pager.selectedItem = first
        gallery.saveAs()
        gallery.pager.selectedItem = second
        gallery.saveAs()
        first.path.set(.single("/first.jpg"))
        second.path.set(.single("/second.jpg"))
        XCTAssertEqual(gallery.saved, ["/second.jpg"])
    }

    func testRemoteMediaShowsMatchingAlertWithoutSaving() {
        for item in [MGalleryPhotoItem(), MGalleryItem()] {
            let gallery = Gallery()
            gallery.pager.selectedItem = item
            item.realStatus = .single(.Remote)
            item.path.set(.single("/stale.jpg"))
            gallery.saveAs()
            XCTAssertEqual(gallery.saved, [])
            XCTAssertEqual(gallery.window.alerts, [item is MGalleryPhotoItem ? "photo" : "video"])
        }
    }

    func testProtectedAndAdvertisingMediaNeverSave() {
        let protected = MGalleryPhotoItem()
        protected.entry.isProtected = true
        let protectedMessage = MGalleryPhotoItem()
        protectedMessage.entry.message = Message(protected: true)
        let ad = MGalleryPhotoItem()
        ad.entry.message = Message(adAttribute: 1)
        for item in [protected, protectedMessage, ad, MGalleryExternalVideoItem()] {
            let gallery = Gallery()
            gallery.pager.selectedItem = item
            item.path.set(.single("/must-not-save.jpg"))
            gallery.saveAs()
            XCTAssertEqual(gallery.saved, [])
            XCTAssertEqual(gallery.window.alerts, [])
        }
    }

    func testPendingSaveDoesNotRetainGallery() {
        var gallery: Gallery? = Gallery()
        weak var weakGallery = gallery
        let item = MGalleryPhotoItem()
        gallery?.pager.selectedItem = item
        gallery?.saveAs()
        gallery = nil
        XCTAssertNil(weakGallery)
        item.path.set(.single("/late.jpg"))
    }

    func testCancellingPendingSavePreventsOutput() {
        let gallery = Gallery()
        let item = MGalleryPhotoItem()
        gallery.pager.selectedItem = item
        gallery.saveAs()
        gallery.operationDisposable.set(nil)
        item.path.set(.single("/cancelled.jpg"))
        XCTAssertEqual(gallery.saved, [])
    }
}
