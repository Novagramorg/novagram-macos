import Foundation
import XCTest

extension Array { mutating func move(at oldIndex: Int, to newIndex: Int) { insert(remove(at: oldIndex),at: newIndex) } }
struct Folder: Equatable { let id: Int }
enum Collection: Equatable {
    case all, collection(Folder), add
    var stableId: AnyHashable { switch self { case .all: return -1; case let .collection(folder): return folder.id; case .add: return Int.max } }
}
struct State { var editable = true; func access(_ id: Int) -> Bool { editable } }
struct Context { let peerId = 10 }
final class Arguments {
    let context = Context()
    var currentState: State? = .init()
    var calls: [(Int,Int)] = []
    func state() -> State? { currentState }
    func resort(_ from: Int, _ to: Int) { calls.append((from,to)) }
}
__DIFF__
class TableRowItem { let stableId: AnyHashable; init(_ id: AnyHashable = 0) { self.stableId = id } }
final class CollectionRowItem: TableRowItem {
    struct Item: Comparable, Identifiable { let value: Collection; let index: Int; let selected: Bool
        static func < (lhs: Item, rhs: Item) -> Bool { lhs.index < rhs.index }
        var stableId: AnyHashable { value.stableId }
        func makeItem(_ size: CGSize, arguments: Arguments) -> TableRowItem { TableRowItem(stableId) }
    }
    let items: [Item]
    let arguments: Arguments?
    var context: Int? = 10
    init(_ values: [Collection], arguments: Arguments?, selected: Int = -1) { self.items = values.enumerated().map { .init(value: $0.element,index: $0.offset,selected: $0.element.stableId == AnyHashable(selected)) }; self.arguments = arguments }
}
final class ResortController {
    let resortRange: NSRange
    let complete: (Int,Int) -> Void
    init(resortRange: NSRange, start: (Int)->Void, resort: (Int)->Void, complete: @escaping (Int,Int)->Void) { self.resortRange = resortRange; self.complete = complete }
}
typealias TableView = Table
final class Table {
    enum Animation { case none, effectFade }
    func beginTableUpdates() {}
    func endTableUpdates() {}
    func remove(at index: Int, animation: Animation) { rows.remove(at: index) }
    func insert(item: TableRowItem, at index: Int, animation: Animation) -> Bool { rows.insert(item.stableId,at: index); return true }
    func replace(item: TableRowItem, at index: Int, animated: Bool) { rows[index] = item.stableId }
    var rows: [AnyHashable] = []
    var resortController: ResortController?
    var animations: [Bool] = []
    var resets = 0
    func removeAll() { rows = []; resets += 1 }
    func drag(_ from: Int, _ to: Int) { let controller = resortController; rows.move(at: from,to: to); controller?.complete(from,to) }
}
func applyMergedRows(_ tableView: Table, current: inout [CollectionRowItem.Item], items: [CollectionRowItem.Item], animated: Bool, makeItem: (CollectionRowItem.Item) -> TableRowItem) {
    XCTAssertEqual(tableView.rows,current.map(\.stableId),"Diff input must match the rows already moved by TableView")
    tableView.animations.append(animated)
    _applyMergedRows(tableView,current: &current,items: items,animated: animated,makeItem: makeItem)
}
__APPLY__
class BaseView {
    var item: TableRowItem?
    let bounds = CGRect.zero
    func set(item: TableRowItem, animated: Bool) { self.item = item }
}
final class AlbumView: BaseView {
    var ignoreNextAnimation = false
    let tableView = Table()
    var items: [CollectionRowItem.Item] = []
    __SET__
}
final class StoryAlbumDragTests: XCTestCase {
    func values(_ ids: [Int], add: Bool = true) -> [Collection] { [.all] + ids.map { .collection(.init(id: $0)) } + (add ? [.add] : []) }
    func prepare(_ ids: [Int] = [7,8,9], add: Bool = true, editable: Bool = true) -> (AlbumView,Arguments) {
        let view = AlbumView(); let args = Arguments(); args.currentState?.editable = editable
        view.set(item: CollectionRowItem(values(ids,add: add),arguments: args),animated: false); return (view,args)
    }
    func testRangeExcludesAllAndAdd() {
        let (view,_) = prepare(); XCTAssertEqual(view.tableView.resortController?.resortRange,NSRange(location: 1,length: 3))
    }
    func testRangeIncludesLastAlbumWhenAddTabAbsent() {
        let (view,_) = prepare(add: false); XCTAssertEqual(view.tableView.resortController?.resortRange,NSRange(location: 1,length: 3))
    }
    func testReadonlyAlbumsCannotBeDragged() { let (view,_) = prepare(editable: false); XCTAssertNil(view.tableView.resortController) }
    func testMissingStateCannotEnableDragging() {
        let (view,args) = prepare(); args.currentState = nil; view.set(item: CollectionRowItem(values([7,8]),arguments: args),animated: true); XCTAssertNil(view.tableView.resortController)
    }
    func testZeroOrOneAlbumDisablesDragging() { for ids: [Int] in [[],[7]] { let (view,_) = prepare(ids); XCTAssertNil(view.tableView.resortController) } }
    func testForwardDropUsesIdentitiesAndRestoresConfirmedOrder() {
        let (view,args) = prepare(); let original = view.tableView.rows; view.tableView.drag(1,3)
        XCTAssertEqual(args.calls.map { [$0.0,$0.1] },[[7,9]]); XCTAssertEqual(view.tableView.rows,original); XCTAssertEqual(view.items.map(\.stableId),original)
    }
    func testBackwardDropUsesIdentitiesAndRestoresConfirmedOrder() {
        let (view,args) = prepare(); let original = view.tableView.rows; view.tableView.drag(3,1)
        XCTAssertEqual(args.calls.map { [$0.0,$0.1] },[[9,7]]); XCTAssertEqual(view.tableView.rows,original)
    }
    func testNoOpDropDoesNotSendMutation() {
        let (view,args) = prepare(); view.tableView.drag(2,2); XCTAssertTrue(args.calls.isEmpty)
    }
    func testInvalidDropDoesNotSendMutation() {
        let (view,args) = prepare(); view.tableView.resortController?.complete(-1,200); XCTAssertTrue(args.calls.isEmpty); XCTAssertEqual(view.tableView.rows,view.items.map(\.stableId))
    }
    func testControlDropDoesNotSendMutation() {
        let (view,args) = prepare(); let original = view.tableView.rows; view.tableView.drag(0,1); XCTAssertTrue(args.calls.isEmpty); XCTAssertEqual(view.tableView.rows,original)
    }
    func testStaleDragAfterListChangeRestoresLatestRows() {
        let (view,args) = prepare([7,8]); let old = view.tableView.resortController
        view.set(item: CollectionRowItem(values([9,7,8]),arguments: args),animated: true); let expected = view.tableView.rows
        view.tableView.rows.move(at: 1,to: 2); old?.complete(1,2)
        XCTAssertTrue(args.calls.isEmpty); XCTAssertEqual(view.tableView.rows,expected)
    }
    func testAcceptedOrderCanBeAppliedWithoutDoubleMoving() {
        let (view,args) = prepare(); view.tableView.drag(1,3)
        view.set(item: CollectionRowItem(values([8,9,7]),arguments: args),animated: true)
        XCTAssertEqual(view.tableView.rows,values([8,9,7]).map(\.stableId))
    }
    func testDragDoesNotDisableAllLaterAnimations() {
        let (view,args) = prepare(); view.tableView.drag(1,3)
        view.set(item: CollectionRowItem(values([8,9,7]),arguments: args),animated: true)
        view.set(item: CollectionRowItem(values([8,9,7]),arguments: args,selected: 9),animated: true)
        XCTAssertEqual(view.tableView.animations.last,true)
    }
    func testRetainedDragCallbackDoesNotRetainView() {
        var view: AlbumView?; let args = Arguments(); view = AlbumView(); view!.set(item: CollectionRowItem(values([7,8]),arguments: args),animated: false)
        weak var weakView = view; let controller = view!.tableView.resortController; view = nil; XCTAssertNil(weakView); controller?.complete(1,2); XCTAssertTrue(args.calls.isEmpty)
    }
}
