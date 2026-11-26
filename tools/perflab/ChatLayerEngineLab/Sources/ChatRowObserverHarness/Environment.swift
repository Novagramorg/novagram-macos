import Cocoa
import TGUIKit

class TableRowItem: NSObject {}

final class ChatRowItem: TableRowItem {
    struct Presentation { var bubbled = true }
    struct Message { var id: Int }
    let chatInteraction: ChatInteraction
    let stableId: Int
    let message: Message?
    var presentation = Presentation()

    init(_ interaction: ChatInteraction, id: Int) {
        chatInteraction = interaction
        stableId = id
        message = Message(id: id)
    }
}

struct ChatPresentationInterfaceState {
    struct Selection: Equatable { var selectedIds: Set<Int> }
    var selectionState: Selection?
}

final class ChatInteraction: InterfaceObserver {
    var presentation = ChatPresentationInterfaceState()
    func select(_ ids: Set<Int>?) {
        let old = presentation
        presentation.selectionState = ids.map { .init(selectedIds: $0) }
        notifyObservers(value: presentation, oldValue: old, animated: false)
    }
}

final class FocusView: NSView { var stableId = 0 }
final class StatusView {
    func set(item: ChatRowItem, animated: Bool) {}
}
final class SelectionView {
    var selected = false
    func set(selected: Bool, animated: Bool) { self.selected = selected }
}

class RowEnvironment: NSView, Notifable {
    var item: TableRowItem?
    let contentView = NSView()
    let rightView = StatusView()
    let selectingView: SelectionView? = SelectionView()
    var animatedView: FocusView?
    var onRender: (() -> Void)?
    var onSuperBind: (() -> Void)?
    var onFill: (() -> Void)?
    var receivedIds: [Int] = []
    var layoutCount = 0

    func set(item: TableRowItem, animated: Bool = false) {
        self.item = item
        onSuperBind?()
    }
    func isEqual(to other: Notifable) -> Bool {
        return self === other
    }
    func notify(with value: Any, oldValue: Any, animated: Bool) {}
    func invalidateFrameCache() {}
    func updateBackground(animated: Bool, item: TableRowItem?, clean: Bool) {}
    func renderLayoutType(_ item: ChatRowItem, animated: Bool) { onRender?() }
    func updateSelectingState(_ animated: Bool = false, selectingMode: Bool, item: ChatRowItem?, needUpdateColors: Bool) {
        if needUpdateColors, let item { receivedIds.append(item.stableId) }
    }
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) { layoutCount += 1 }
    func updateColors() {}
    func fillTopicLink(_ item: ChatRowItem, animated: Bool) { onFill?() }
    func fillReply(_ item: ChatRowItem, animated: Bool) {}
    func fillName(_ item: ChatRowItem, animated: Bool) {}
    func fillForward(_ item: ChatRowItem, animated: Bool) {}
    func fillForwardHeader(_ item: ChatRowItem, animated: Bool) {}
    func fillForwardLine(_ item: ChatRowItem, animated: Bool) {}
    func fillPhoto(_ item: ChatRowItem, animated: Bool) {}
    func fillStatus(_ item: ChatRowItem, animated: Bool) {}
    func fillPsaButton(_ item: ChatRowItem, animated: Bool) {}
    func fillShareView(_ item: ChatRowItem, animated: Bool) {}
    func fillReactions(_ item: ChatRowItem, animated: Bool) {}
    func fillReplyMarkup(_ item: ChatRowItem, animated: Bool) {}
    func fillCaption(_ item: ChatRowItem, animated: Bool) {}
    func fillFactCheck(_ item: ChatRowItem, animated: Bool) {}
    func fillChannelComments(_ item: ChatRowItem, animated: Bool) {}
    func updateRightHosting(_ item: ChatRowItem) {}
}

enum ChatMergeProbe {
    static func noteBind(previous: TableRowItem?, next: TableRowItem) {}
}
