import Foundation
import XCTest
import SwiftSignalKit

private enum SelectionCase {
    struct Message { let id: Int; var canDelete = true; var canForward = true }
    struct Selection: Equatable { let selectedIds: Set<Int> }
    struct Presentation {
        var selectionState: Selection?
        var basicActions = (false, false)
        let chatLocation = 0
        func withUpdatedBasicActions(_ actions: (Bool, Bool)) -> Self { var s = self; s.basicActions = actions; return s }
    }
    enum Mode { case history, customChatContents(Postbox) }
    final class Interaction {
        var presentation = Presentation()
        func update(_ f: (Presentation) -> Presentation) { presentation = f(presentation) }
    }
    final class Postbox {
        var subscribers: [Int: Subscriber<[Message], NoError>] = [:]
        var canceled: [Int] = []
        func messagesAtIds(_ ids: [Int], album: Bool = false) -> Signal<[Message], NoError> {
            Signal { subscriber in
                self.subscribers[ids[0]] = subscriber
                return ActionDisposable { self.canceled.append(ids[0]) }
            }
        }
        func complete(_ id: Int, canDelete: Bool = true, canForward: Bool = true) {
            subscribers[id]?.putNext([.init(id: id, canDelete: canDelete, canForward: canForward)])
            subscribers[id]?.putCompletion()
        }
    }
    final class Account { let postbox = Postbox() }
    final class Context { let account = Account(); var isFrozen = false }
    static func canDeleteMessage(_ message: Message, account: Account, chatLocation: Int, mode: Mode) -> Bool { message.canDelete }
    static func canForwardMessage(_ message: Message, chatInteraction: Interaction) -> Bool { message.canForward }
    final class Harness {
        let context = Context()
        let chatInteraction = Interaction()
        let loadSelectionMessagesDisposable = MetaDisposable()
        let updateChatLocationThreadDisposable = MetaDisposable()
        let editCurrentMessagePhotoDisposable = MetaDisposable()
        let updateMediaDisposable = MetaDisposable()
        func select(_ id: Int?) {
            let oldValue = chatInteraction.presentation
            chatInteraction.presentation.selectionState = id.map { .init(selectedIds: [$0]) }
            let value = chatInteraction.presentation
            let mode = Mode.history
            let context = self.context
__SELECTION_UPDATE__
        }
        func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        deinit {
__CLEANUP__
        }
    }
}

final class SelectionTests: XCTestCase {
    func testCanceledSelectionCannotEnableActionsFromLateLookup() {
        let h = SelectionCase.Harness()
        h.select(1)
        h.select(nil)
        h.drain()
        h.context.account.postbox.complete(1)
        XCTAssertFalse(h.chatInteraction.presentation.basicActions.0)
        XCTAssertFalse(h.chatInteraction.presentation.basicActions.1)
        XCTAssertTrue(h.context.account.postbox.canceled.contains(1))
    }
    func testDeferredClearCannotDisableNewSelection() {
        let h = SelectionCase.Harness()
        h.select(1)
        h.select(nil)
        h.select(2)
        h.context.account.postbox.complete(2)
        h.drain()
        XCTAssertTrue(h.chatInteraction.presentation.basicActions.0)
        XCTAssertTrue(h.chatInteraction.presentation.basicActions.1)
    }
    func testPreviousSelectionCannotReplaceNewPermissions() {
        let h = SelectionCase.Harness()
        h.select(1)
        h.select(2)
        h.context.account.postbox.complete(2, canDelete: false, canForward: false)
        h.context.account.postbox.complete(1)
        XCTAssertFalse(h.chatInteraction.presentation.basicActions.0)
        XCTAssertFalse(h.chatInteraction.presentation.basicActions.1)
    }
    func testFrozenAccountKeepsActionsDisabled() {
        let h = SelectionCase.Harness()
        h.context.isFrozen = true
        h.select(1)
        h.context.account.postbox.complete(1)
        XCTAssertFalse(h.chatInteraction.presentation.basicActions.0)
        XCTAssertFalse(h.chatInteraction.presentation.basicActions.1)
    }
    func testNormalSelectionLoadsPermissionsAndClearsOnExit() {
        let h = SelectionCase.Harness()
        h.select(1)
        h.context.account.postbox.complete(1, canForward: false)
        XCTAssertTrue(h.chatInteraction.presentation.basicActions.0)
        XCTAssertFalse(h.chatInteraction.presentation.basicActions.1)
        h.select(nil)
        h.drain()
        XCTAssertFalse(h.chatInteraction.presentation.basicActions.0)
    }
}
