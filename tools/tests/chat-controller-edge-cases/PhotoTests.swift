import Foundation
import XCTest
import SwiftSignalKit

private enum PhotoCase {
    struct PeerId { var namespace = 0 }
    enum Namespaces { enum Peer { static let SecretChat = 1 } }
    struct Message { let id: Int }
    typealias EditedImageData = Int
    struct PixelDimensions { init(_ width: Int, _ height: Int) {} }
    struct Representation { let resource: Int }
    struct TelegramMediaImage: Equatable {
        let id: Int
        func representationForDisplayAtSize(_ size: PixelDimensions) -> Representation? { .init(resource: id) }
    }
    struct MediaResourceData { let path: String; let complete: Bool }
    typealias Media = TelegramMediaImage
    struct EditState {
        let message: Message
        var canEditMedia = true
        var editedData: EditedImageData?
        var media = TelegramMediaImage(id: 1)
        func withUpdatedEditedData(_ data: EditedImageData?) -> Self { var s = self; s.editedData = data; return s }
        func withUpdatedMedia(_ media: TelegramMediaImage) -> Self { var s = self; s.media = media; return s }
    }
    struct InterfaceState {
        var editState: EditState? = .init(message: .init(id: 1))
        func updatedEditState(_ f: (EditState?) -> EditState?) -> Self { var s = self; s.editState = f(editState); return s }
    }
    struct Presentation {
        var interfaceState = InterfaceState()
        func updatedInterfaceState(_ f: (InterfaceState) -> InterfaceState) -> Self { var s = self; s.interfaceState = f(interfaceState); return s }
    }
    final class Interaction {
        var interactionContext: Context!
        let editDisposable = MetaDisposable()
        var presentation = Presentation()
        var editEditingMessagePhoto: (TelegramMediaImage) -> Void = { _ in }
        var updateEditingMessageMedia: ([String]?, Bool) -> Void = { _, _ in }
        func update(_ f: (Presentation) -> Presentation) { presentation = f(presentation) }
    }
    final class MediaBox {
        var subscribers: [Int: [Subscriber<MediaResourceData, NoError>]] = [:]
        var canceled: [Int] = []
        var fetched: [Int] = []
        func resourceData(_ resource: Int) -> Signal<MediaResourceData, NoError> {
            Signal { subscriber in
                self.subscribers[resource, default: []].append(subscriber)
                return ActionDisposable { self.canceled.append(resource) }
            }
        }
        func emit(_ id: Int, complete: Bool) {
            for subscriber in subscribers[id] ?? [] {
                subscriber.putNext(.init(path: "/photo-\(id)", complete: complete))
            }
        }
    }
    final class Postbox { let mediaBox = MediaBox() }
    final class Account {
        let postbox = Postbox()
        var generated: [Subscriber<(TelegramMediaImage, Int), NoError>] = []
    }
    final class Window { var completion: (([String]?) -> Void)? }
    final class Context { let account = Account(); let window = Window() }
    struct MediaSenderContainer { let path: String; let isFile: Bool }
    enum Sender {
        static func generateMedia(for container: MediaSenderContainer, account: Account, isSecretRelated: Bool) -> Signal<(TelegramMediaImage, Int), NoError> {
            Signal { subscriber in account.generated.append(subscriber); return EmptyDisposable }
        }
    }
    static let kMediaImageExt = "jpg"
    static func link(path: String, ext: String) -> String? { path }
    static func filePanel(with exts: [String]?, allowMultiple: Bool, for window: Window, completion: @escaping ([String]?) -> Void) {
        window.completion = completion
    }
    struct MessageReference { init(_ message: Message) {} }
    enum AnyMediaReference { case message(message: MessageReference, media: TelegramMediaImage) }
    enum MediaResourceReference { case media(media: AnyMediaReference, resource: Int) }
    enum UserLocation { case peer(PeerId) }
    enum ContentType { case image }
    static func fetchedMediaResource(mediaBox: MediaBox, userLocation: UserLocation, userContentType: ContentType, reference: MediaResourceReference) -> Signal<Void, NoError> {
        Signal { _ in
            if case let .media(_, resource) = reference { mediaBox.fetched.append(resource) }
            return EmptyDisposable
        }
    }
    final class ChatNavigationHooks {
        static var shared = ChatNavigationHooks()
        var opened: [URL] = []
        var results: [Subscriber<(URL, EditedImageData?), NoError>] = []
        func editImage(_ context: Context, _ url: URL, _ data: EditedImageData?) -> Signal<(URL, EditedImageData?), NoError> {
            opened.append(url)
            return Signal { subscriber in self.results.append(subscriber); return EmptyDisposable }
        }
        func finish(_ index: Int = 0, changed: Bool = false) {
            results[index].putNext((changed ? URL(fileURLWithPath: "/edited") : opened[index], 42))
            results[index].putCompletion()
        }
    }
    struct DragItem { let title: String; let desc: String; let handler: () -> Void }
    struct DropStrings { let chatDropEditTitle = "Replace"; let chatDropEditDesc = "Replace" }
    static func strings() -> DropStrings { DropStrings() }
    struct Application { func activate(ignoringOtherApps: Bool) {} }
    static let NSApp = Application()
    static func putToTemp(image: Int) -> Signal<String, NoError> { .single("/image") }
    final class Harness {
        let context = Context()
        let chatInteraction = Interaction()
        let editCurrentMessagePhotoDisposable = MetaDisposable()
        let updateMediaDisposable = MetaDisposable()
        let updateChatLocationThreadDisposable = MetaDisposable()
        let loadSelectionMessagesDisposable = MetaDisposable()
        var editingSessionId = 0
        init() {
            self.chatInteraction.interactionContext = self.context
            let chatInteraction = self.chatInteraction
            let context = self.context
            let peerId = PeerId()
__PHOTO_SETUP__
__MEDIA_SETUP__
        }
        func fileDrop() -> DragItem {
            let list = ["/drop"]
            let peerId = PeerId()
            func build() -> [DragItem] {
__FILE_DROP__
                return []
            }
            return build()[0]
        }
        func imageDrop() -> DragItem {
            let image = 1
            let peerId = PeerId()
            func build() -> [DragItem] {
__IMAGE_DROP__
                return []
            }
            return build()[0]
        }
        func request(_ id: Int = 1) { chatInteraction.editEditingMessagePhoto(.init(id: id)) }
        func selectMessage(_ id: Int?) {
            let oldValue = chatInteraction.presentation
            chatInteraction.presentation.interfaceState.editState = id.map { .init(message: .init(id: $0)) }
            let value = chatInteraction.presentation
__EDIT_SESSION_UPDATE__
        }
        var state: EditState? { chatInteraction.presentation.interfaceState.editState }
        var box: MediaBox { context.account.postbox.mediaBox }
        func cleanup() {
__CLEANUP__
        }
        deinit { cleanup() }
    }
}

final class PhotoTests: XCTestCase {
    override func setUp() { PhotoCase.ChatNavigationHooks.shared = .init() }
    func testDelayedFileDropCannotModifyAnotherEdit() {
        let h = PhotoCase.Harness()
        h.fileDrop().handler()
        h.selectMessage(2)
        h.context.account.generated[0].putNext((.init(id: 9), 0))
        XCTAssertEqual(h.state?.media.id, 1)
    }
    func testDelayedImageDropCannotModifyAnotherEdit() {
        let h = PhotoCase.Harness()
        h.imageDrop().handler()
        h.selectMessage(2)
        h.context.account.generated[0].putNext((.init(id: 9), 0))
        XCTAssertEqual(h.state?.media.id, 1)
    }
    func testDropTargetCannotBeUsedAfterReopeningSameMessage() {
        let h = PhotoCase.Harness()
        let drop = h.fileDrop()
        h.selectMessage(nil)
        h.selectMessage(1)
        drop.handler()
        XCTAssertTrue(h.context.account.generated.isEmpty)
    }
    func testDropReplacementCancelsPreviousConversion() {
        let h = PhotoCase.Harness()
        h.fileDrop().handler()
        h.imageDrop().handler()
        h.context.account.generated[1].putNext((.init(id: 8), 0))
        h.context.account.generated[0].putNext((.init(id: 9), 0))
        XCTAssertEqual(h.state?.media.id, 8)
    }
    func testDropCancelsPendingPhotoEditor() {
        let h = PhotoCase.Harness()
        h.request()
        h.fileDrop().handler()
        h.box.emit(1, complete: true)
        XCTAssertTrue(PhotoCase.ChatNavigationHooks.shared.opened.isEmpty)
    }
    func testSuccessfulImageDropStillReplacesMedia() {
        let h = PhotoCase.Harness()
        h.imageDrop().handler()
        h.context.account.generated[0].putNext((.init(id: 9), 0))
        XCTAssertEqual(h.state?.media.id, 9)
    }
    func testPartialImageDoesNotOpenEditor() {
        let h = PhotoCase.Harness()
        h.request()
        h.box.emit(1, complete: false)
        XCTAssertTrue(PhotoCase.ChatNavigationHooks.shared.opened.isEmpty)
    }
    func testDownloadOpensEditorOnlyOnceWhenComplete() {
        let h = PhotoCase.Harness()
        h.request()
        h.box.emit(1, complete: false)
        h.box.emit(1, complete: false)
        h.box.emit(1, complete: true)
        XCTAssertEqual(PhotoCase.ChatNavigationHooks.shared.opened.count, 1)
    }
    func testPhotoRequestStartsFetch() {
        let h = PhotoCase.Harness()
        h.request()
        XCTAssertEqual(h.box.fetched, [1])
    }
    func testNoEditorWhenEditWasCanceledDuringDownload() {
        let h = PhotoCase.Harness()
        h.request()
        h.selectMessage(nil)
        h.box.emit(1, complete: true)
        XCTAssertTrue(PhotoCase.ChatNavigationHooks.shared.opened.isEmpty)
    }
    func testDownloadCannotOpenEditorForAnotherMessage() {
        let h = PhotoCase.Harness()
        h.request()
        h.selectMessage(2)
        h.box.emit(1, complete: true)
        XCTAssertTrue(PhotoCase.ChatNavigationHooks.shared.opened.isEmpty)
    }
    func testEditorResultCannotModifyAnotherDraft() {
        let h = PhotoCase.Harness()
        h.request()
        h.box.emit(1, complete: true)
        h.selectMessage(2)
        PhotoCase.ChatNavigationHooks.shared.finish()
        XCTAssertNil(h.state?.editedData)
    }
    func testGeneratedPhotoCannotReplaceAnotherDraftMedia() {
        let h = PhotoCase.Harness()
        h.request()
        h.box.emit(1, complete: true)
        PhotoCase.ChatNavigationHooks.shared.finish(changed: true)
        h.selectMessage(2)
        h.context.account.generated[0].putNext((.init(id: 9), 0))
        XCTAssertEqual(h.state?.media.id, 1)
    }
    func testNewPhotoRequestCancelsPreviousDownload() {
        let h = PhotoCase.Harness()
        h.request(1)
        h.request(2)
        h.box.emit(2, complete: true)
        h.box.emit(1, complete: true)
        XCTAssertEqual(PhotoCase.ChatNavigationHooks.shared.opened, [URL(fileURLWithPath: "/photo-2")])
    }
    func testCleanupCancelsDownload() {
        let h = PhotoCase.Harness()
        h.request()
        h.cleanup()
        h.box.emit(1, complete: true)
        XCTAssertTrue(PhotoCase.ChatNavigationHooks.shared.opened.isEmpty)
        XCTAssertTrue(h.box.canceled.contains(1))
    }
    func testSuccessfulPhotoEditStillUpdatesDataAndMedia() {
        let h = PhotoCase.Harness()
        h.request()
        h.box.emit(1, complete: true)
        PhotoCase.ChatNavigationHooks.shared.finish(changed: true)
        h.context.account.generated[0].putNext((.init(id: 9), 0))
        XCTAssertEqual(h.state?.editedData, 42)
        XCTAssertEqual(h.state?.media.id, 9)
    }
    func testPhotoEditWithoutChangesKeepsOriginalMedia() {
        let h = PhotoCase.Harness()
        h.request(4)
        h.box.emit(4, complete: true)
        PhotoCase.ChatNavigationHooks.shared.finish()
        XCTAssertEqual(h.state?.editedData, 42)
        XCTAssertEqual(h.state?.media.id, 4)
        XCTAssertTrue(h.context.account.generated.isEmpty)
    }
    func testFilePanelResultCannotModifyDifferentMessage() {
        let h = PhotoCase.Harness()
        h.chatInteraction.updateEditingMessageMedia(nil, true)
        h.selectMessage(2)
        h.context.window.completion?(["/replacement"])
        XCTAssertTrue(h.context.account.generated.isEmpty)
    }
    func testGeneratedFileCannotModifyDifferentMessage() {
        let h = PhotoCase.Harness()
        h.chatInteraction.updateEditingMessageMedia(nil, true)
        h.context.window.completion?(["/replacement"])
        h.selectMessage(2)
        h.context.account.generated[0].putNext((.init(id: 9), 0))
        XCTAssertEqual(h.state?.media.id, 1)
    }
    func testSuccessfulFileReplacementStillWorks() {
        let h = PhotoCase.Harness()
        h.chatInteraction.updateEditingMessageMedia(nil, true)
        h.context.window.completion?(["/replacement"])
        h.context.account.generated[0].putNext((.init(id: 9), 0))
        XCTAssertEqual(h.state?.media.id, 9)
    }
    func testChoosingFileCancelsPendingPhotoEditor() {
        let h = PhotoCase.Harness()
        h.request()
        h.chatInteraction.updateEditingMessageMedia(nil, true)
        h.context.window.completion?(["/replacement"])
        h.box.emit(1, complete: true)
        XCTAssertTrue(PhotoCase.ChatNavigationHooks.shared.opened.isEmpty)
    }
    func testCanceledAndReopenedSameMessageIgnoresOldFilePanel() {
        let h = PhotoCase.Harness()
        h.chatInteraction.updateEditingMessageMedia(nil, true)
        h.selectMessage(nil)
        h.selectMessage(1)
        h.context.window.completion?(["/replacement"])
        XCTAssertTrue(h.context.account.generated.isEmpty)
    }
    func testCanceledAndReopenedSameMessageIgnoresOldPhotoDownload() {
        let h = PhotoCase.Harness()
        h.request()
        h.selectMessage(nil)
        h.selectMessage(1)
        h.box.emit(1, complete: true)
        XCTAssertTrue(PhotoCase.ChatNavigationHooks.shared.opened.isEmpty)
    }
    func testCanceledAndReopenedSameMessageIgnoresOldGeneratedMedia() {
        let h = PhotoCase.Harness()
        h.chatInteraction.updateEditingMessageMedia(nil, true)
        h.context.window.completion?(["/replacement"])
        h.selectMessage(nil)
        h.selectMessage(1)
        h.context.account.generated[0].putNext((.init(id: 9), 0))
        XCTAssertEqual(h.state?.media.id, 1)
    }
}
