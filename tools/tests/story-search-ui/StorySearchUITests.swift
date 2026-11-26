import Cocoa
import MapKit
import XCTest
import SwiftSignalKit

struct PeerId: Equatable, Hashable { let value: Int64; func toInt64() -> Int64 { value } }
struct Peer: Equatable { let id: PeerId; var referenceAvailable = true; func _asPeer() -> Peer { self } }
struct PeerReference: Equatable { let id: PeerId; init?(_ peer: Peer) { guard peer.referenceAvailable else { return nil }; id = peer.id } }
struct StoryId: Equatable { let peerId: PeerId; let id: Int32 }
struct Media: Equatable { func _asMedia() -> Any { 0 } }
class TelegramMediaFile {}
struct Story: Equatable { let id: Int32; let media = Media() }
enum StoryListContextState {
    struct Item: Equatable { let id: StoryId; let storyItem: Story; let peer: Peer? }
}
enum StoryListContext {
    struct State: Equatable {
        var items: [StoryListContextState.Item] = []
        var totalCount = 0
        var isLoading = false
        var hasCache = false
        var loadMoreToken: String? = ""
    }
}
final class Account {}
final class AnalyticsContext {
    func restricting(peerId: PeerId) -> AnalyticsContext { self }
    func beginPresentation() -> AnalyticsLifetime { AnalyticsLifetime() }
}
final class AnalyticsLifetime { func end() {} }
final class Analytics {
    static let shared = Analytics()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext() }
    func captureContext(engine: Account, peerId: PeerId, inherited: AnalyticsContext) -> AnalyticsContext { inherited }
}
protocol AccountContextProtocol: AnyObject { var account: Account { get }; var peerId: PeerId { get }; var myPeer: Peer? { get }; var window: Int { get } }
extension AccountContextProtocol { var engine: Account { account } }
final class Context: AccountContextProtocol {
    let account = Account(); let peerId = PeerId(value: 1); var myPeer: Peer? = Peer(id: .init(value: 1)); let window = 0
}
struct Venue { let latitude: Double; let longitude: Double }
struct MapVenue {}
enum Area { case venue(Int, Venue); case other }
final class SearchStoryListContext {
    enum Source { case hashtag(PeerId?, String); case mediaArea(Area) }
    var loads = 0
    let promise = ValuePromise<StoryListContext.State>(.init(), ignoreRepeated: true)
    var state: Signal<StoryListContext.State, NoError> { promise.get() }
    init(account: Account, source: Source) {}
    func loadMore() { loads += 1 }
}
struct StoryInitialIndex {}
struct Colors { let background = 0; let text = 0; let grayText = 0; let border = 0; let accent = 0; let underSelectedColor = 0 }
struct Icons { let modalClose = 0 }
struct TelegramPresentationTheme { let colors = Colors(); let icons = Icons(); let appearance = 0 }
let theme = TelegramPresentationTheme()
struct Strings {
    let storyLocationTitle = "location"; let storiesFoundListNotFound = "not found"; let unknownError = "error"
    let voiceOverCommonRetry = "retry"; let chatRichTextShowMore = "more"
    let locationPreviewOpenInMaps = "maps"; let inAppLinksConfirmOpenExternalOK = "ok"
    func storiesFoundListFromLocationOther(_ count: Int) -> String { "\(count) results" }
    func storySearchSubtitleOther(_ count: Int) -> String { "\(count) stories" }
}
func strings() -> Strings { .init() }
enum UserLocationResult { case success(CLLocation) }
enum UserLocationError: Error { case denied }
struct ReverseGeocodedPlacemark: Equatable { let city: String }
final class LocationProbe {
    var starts = 0; var cancellations = 0; var geocodes = 0; var geocodeCancellations = 0
    var location: Subscriber<UserLocationResult, UserLocationError>?
}
var locationProbe = LocationProbe()
func requestUserLocation() -> Signal<UserLocationResult, UserLocationError> {
    Signal { subscriber in
        let probe = locationProbe; probe.starts += 1; probe.location = subscriber
        return ActionDisposable { probe.cancellations += 1; probe.location = nil }
    }
}
func reverseGeocodeLocation(latitude: Double, longitude: Double) -> Signal<ReverseGeocodedPlacemark?, NoError> {
    Signal { _ in let probe = locationProbe; probe.geocodes += 1; return ActionDisposable { probe.geocodeCancellations += 1 } }
}
func deliverOnPrepareQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
struct InputDataIdentifier: Equatable { let value: String; init(_ value: String) { self.value = value } }
enum InputDataValue { case none }
struct InputDataEquatable { init<T>(_ value: T) {} }
struct InputDataEntry {
    let identifier: InputDataIdentifier; let item: (NSSize, AnyHashable) -> TableRowItem
    static func custom(sectionId: Int32, index: Int32, value: InputDataValue, identifier: InputDataIdentifier, equatable: InputDataEquatable, comparable: Int?, item: @escaping (NSSize, AnyHashable) -> TableRowItem) -> Self { .init(identifier: identifier, item: item) }
}
class TableRowItem {}
struct RowTheme { static func initialize(_ theme: TelegramPresentationTheme) -> Self { .init() } }
struct GeneralViewType {
    enum Position { case first, inner, last, single }
    let position: Position; let innerInset: NSEdgeInsets
    static let legacy = Self(position: .single, innerInset: NSEdgeInsets())
    static func modern(position: Position, insets: NSEdgeInsets) -> Self { .init(position: position, innerInset: insets) }
}
private final class MapRowItem: TableRowItem {
    let location: State.Location; let presentation: TelegramPresentationTheme
    init(_ size: NSSize, height: CGFloat, stableId: AnyHashable, context: any AccountContextProtocol, location: State.Location, userLocation: CLLocation?, geocodedPlacemark: ReverseGeocodedPlacemark?, userLocationError: UserLocationError?, presentation: TelegramPresentationTheme, viewType: GeneralViewType, action: @escaping () -> Void) { self.location = location; self.presentation = presentation }
}
final class SeparatorRowItem: TableRowItem { init(_ size: NSSize, _ id: AnyHashable, string: String, customTheme: RowTheme) {} }
final class SearchEmptyRowItem: TableRowItem {
    struct Action { let click: () -> Void; let title: String }
    var buttonAction: Action? { action }
    let isLoading: Bool; let text: String?; let action: Action?
    init(_ size: NSSize, stableId: AnyHashable, height: CGFloat?, isLoading: Bool, text: String?, customTheme: RowTheme, action: Action? = nil) { self.isLoading = isLoading; self.text = text; self.action = action }
}
final class GridRow: TableRowItem { let peerId: PeerId; let reference: PeerReference; let items: [StoryListContextState.Item]; init(_ peerId: PeerId, _ reference: PeerReference, _ items: [StoryListContextState.Item]) { self.peerId = peerId; self.reference = reference; self.items = items } }
final class StoriesHooks {
    static let shared = StoriesHooks()
    func showListStoryObserved(_ context: any AccountContextProtocol, _ list: SearchStoryListContext, _ peer: PeerId, _ index: StoryInitialIndex?, analyticsContext: AnalyticsContext) {}
    func makeStoryMonthRowItem(_ size: NSSize, _ id: AnyHashable, _ context: any AccountContextProtocol, _ standalone: Bool, _ peerId: PeerId, _ reference: PeerReference, _ items: [StoryListContextState.Item], _ selected: Int?, _ pinned: [Int32], _ columns: Int, _ type: GeneralViewType, _ open: @escaping (StoryInitialIndex?) -> Void, _ toggle: (Int) -> Void, _ menu: (Int) -> [Int], _ theme: TelegramPresentationTheme) -> TableRowItem { GridRow(peerId, reference, items) }
    enum Link { case external(link: String, Bool) }
    func executeInApp(_ link: Link) {}
}
struct TelegramThemeHooks { static let shared = Self(); enum Image { case iconStoryShare }; func image(_ image: Image) -> Int { 0 } }
extension Int { static var clear: Int { 0 }; func precomposed(_ color: Int) -> Int { self } }
func verifyAlert(for window: Int, information: String, ok: String, successHandler: @escaping (Bool) -> Void, presentation: TelegramPresentationTheme) {}
struct InputDataSignalValue { let entries: [InputDataEntry] }
struct ModalHeaderData {
    init(image: Int, handler: @escaping () -> Void) {}
    init(title: String, subtitle: String) {}
}
struct ModalTheme { let text: Int; let grayText: Int; let background: Int; let border: Int; let activeBorder: Int }
final class Table {
    struct Position { enum Direction { case bottom, top }; let direction: Direction }
    var scroll: ((Position) -> Void)?
    func setScrollHandler(_ f: @escaping (Position) -> Void) { scroll = f }
}
final class InputDataController {
    var analyticsContext: AnalyticsContext?
    enum Screen { case storiesSearchResults }
    var analyticsScreen: Screen?
    var onDeinit: (() -> Void)?; var contextObject: Any?
    var getBackgroundColor: (() -> Int)?
    var leftModalHeader: ModalHeaderData?; var rightModalHeader: ModalHeaderData?; var centerModalHeader: ModalHeaderData?
    var didLoad: ((InputDataController, Int) -> Void)?; var afterTransaction: ((InputDataController) -> Void)?
    let tableView = Table(); var values: [InputDataSignalValue] = []; var disposable: Disposable?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) { disposable = dataSignal.start(next: { [weak self] in self?.values.append($0) }) }
    deinit { onDeinit?(); disposable?.dispose() }
}
final class InputDataModalController {
    var analyticsContext: AnalyticsContext?
    let controller: InputDataController; var getModalTheme: (() -> ModalTheme)?
    init(_ controller: InputDataController, modalInteractions: Int?, size: NSSize, presentation: TelegramPresentationTheme) { self.controller = controller }
    func close() {}; func updateLocalizationAndTheme(theme: TelegramPresentationTheme) {}
}
extension Array { func chunks(_ n: Int) -> [[Element]] { stride(from: 0, to: count, by: n).map { Array(self[$0..<Swift.min($0 + n, count)]) } } }
__ARGUMENTS__
__STATE__
__ENTRIES__
__SOURCE__
__CONTROLLER__

private final class MapMock {
    var annotations: [MKAnnotation] = []; var appearance = 0; var additions = 0; var removals = 0
    func addAnnotation(_ value: MKAnnotation) { additions += 1; annotations.append(value) }
    func removeAnnotations(_ values: [MKAnnotation]) { removals += values.count; annotations.removeAll { value in values.contains { ($0 as AnyObject) === (value as AnyObject) } } }
}
private class BaseMapView { func set(item: TableRowItem, animated: Bool = false) {} }
private final class VenueMock { func update(item: MapRowItem, animated: Bool) {} }
private final class MapView: BaseMapView {
    let mapView = MapMock(); let venueView = VenueMock(); var focusCount = 0
    func layout() {}; func focusVenue() { focusCount += 1 }
    __MAP_SET__
}
class MediaCell {}
class MediaVideoCell: MediaCell {}
class MediaPhotoCell: MediaCell {}
enum ImageCorner { case Corner(CGFloat) }
struct ImageCorners { let topLeft: ImageCorner; let topRight: ImageCorner; let bottomLeft: ImageCorner; let bottomRight: ImageCorner }
extension CGFloat { static let cornerRadius: CGFloat = 10 }
extension CGPoint { func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint { .init(x: x + dx, y: y + dy) } }
struct StoryCellLayoutItem {
    let item: StoryListContextState.Item; let peerReference: PeerReference; let peerId: PeerId; let frame: CGRect
    init(item: StoryListContextState.Item, peerReference: PeerReference, peerId: PeerId, frame: CGRect, viewType: MediaCell.Type, corners: ImageCorners, context: any AccountContextProtocol, isPinned: Bool) { self.item = item; self.peerReference = peerReference; self.peerId = peerId; self.frame = frame }
}
class BaseGrid { func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool { true } }
final class StoryMonthRowItem: BaseGrid {
    let context: any AccountContextProtocol = Context()
    let peerId: PeerId; let peerReference: PeerReference; let items: [StoryListContextState.Item]
    let viewType = GeneralViewType.modern(position: .inner, insets: NSEdgeInsets())
    let rowCountValue = 3; let blockWidth: CGFloat = 300; let pinnedIds: [Int32] = []
    var layoutItems: [StoryCellLayoutItem] = []; var itemSize = CGSize.zero; var postsSize = CGSize.zero; var contentHeight: CGFloat = 0
    init(_ items: [StoryListContextState.Item], fallback: PeerId) { self.items = items; self.peerId = fallback; self.peerReference = PeerReference(Peer(id: fallback))! }
    static func rowCount(blockWidth: CGFloat, rowCount: Int, viewType: GeneralViewType) -> (Int, CGFloat) { (rowCount, blockWidth / CGFloat(rowCount)) }
    __GRID_SIZE__
}

final class TextButton {
    enum State { case Normal, Click }
    struct Font { enum Size { case text }; static func normal(_ size: Size) -> Self { .init() } }
    final class Layer { var cornerRadius: CGFloat = 0 }
    var layer: Layer? = Layer(); var autoSizeToFit = true; var scaleOnClick = false
    var removed = false; var handler: ((Int) -> Void)?
    func set(font: Font, for state: State) {}
    func set(color: Int, for state: State) {}
    func set(background: Int, for state: State) {}
    func set(text: String, for state: State) {}
    func set(handler: @escaping (Int) -> Void, for state: State) { self.handler = handler }
    func sizeToFit(_ first: NSSize, _ second: NSSize, thatFit: Bool) {}
    func removeAllHandlers() { handler = nil }
    func removeFromSuperview() { removed = true }
}
final class EmptyActionView {
    var action: TextButton?; let frame = CGRect(x: 0, y: 0, width: 350, height: 160)
    func addSubview(_ button: TextButton) {}
    func update(_ item: SearchEmptyRowItem) {
        __EMPTY_ACTION__
    }
}

final class StorySearchUITests: XCTestCase {
    var loads = 0
    override func setUp() { locationProbe = LocationProbe(); loads = 0 }
    func item(_ id: Int32, peer: Int64 = 2, valid: Bool = true) -> StoryListContextState.Item { .init(id: .init(peerId: .init(value: peer), id: id), storyItem: .init(id: id), peer: .init(id: .init(value: peer), referenceAvailable: valid)) }
    private func rows(_ list: StoryListContext.State, context: Context = Context()) -> [TableRowItem] {
        let arguments = Arguments(context: context, presentaiton: theme, openStory: { _ in }, loadMore: { self.loads += 1 })
        return entries(State(listState: list), arguments: arguments).map { $0.item(.init(width: 350, height: 300), $0.identifier.value) }
    }
    private func screen(_ source: SearchStoryListContext.Source = .hashtag(nil, "tag"), list: SearchStoryListContext? = nil) -> InputDataModalController { StoryFoundListController(context: Context(), source: source, presentation: theme, existingsContext: list) }
    func testReusedEmptyRowRemovesStaleAction() {
        let view = EmptyActionView()
        view.update(SearchEmptyRowItem(.zero, stableId: 1, height: 160, isLoading: false, text: "error", customTheme: .initialize(theme), action: .init(click: { self.loads += 1 }, title: "retry")))
        let oldButton = view.action
        view.update(SearchEmptyRowItem(.zero, stableId: 1, height: 160, isLoading: true, text: "", customTheme: .initialize(theme)))
        XCTAssertNil(view.action); XCTAssertTrue(oldButton?.removed == true)
        oldButton?.handler?(0); XCTAssertEqual(loads, 0)
    }
    func testReusedEmptyRowReplacesCallback() {
        let view = EmptyActionView()
        view.update(SearchEmptyRowItem(.zero, stableId: 1, height: 160, isLoading: false, text: "error", customTheme: .initialize(theme), action: .init(click: { self.loads += 1 }, title: "retry")))
        view.update(SearchEmptyRowItem(.zero, stableId: 1, height: 160, isLoading: false, text: "", customTheme: .initialize(theme), action: .init(click: { self.loads += 10 }, title: "more")))
        view.action?.handler?(0); XCTAssertEqual(loads, 10)
    }
    func testHashtagDoesNotRequestLocation() { let modal = screen(); XCTAssertEqual(locationProbe.starts, 0); XCTAssertEqual(locationProbe.geocodes, 0); withExtendedLifetime(modal) {} }
    func testVenueRequestsLocationAndDisposesOnRelease() { var modal: InputDataModalController? = screen(.mediaArea(.venue(0, .init(latitude: 1, longitude: 2)))); XCTAssertEqual(locationProbe.starts, 1); XCTAssertEqual(locationProbe.geocodes, 1); weak var controller = modal?.controller; modal = nil; XCTAssertNil(controller); XCTAssertEqual(locationProbe.cancellations, 1); XCTAssertEqual(locationProbe.geocodeCancellations, 1) }
    func testOtherAreaDoesNotRequestLocation() { let modal = screen(.mediaArea(.other)); XCTAssertEqual(locationProbe.starts, 0); withExtendedLifetime(modal) {} }
    func testInitialFailureOffersRetry() { let empty = rows(.init()).first as? SearchEmptyRowItem; XCTAssertEqual(empty?.text, "error"); XCTAssertEqual(empty?.action?.title, "retry"); empty?.action?.click(); XCTAssertEqual(loads, 1) }
    func testExhaustedEmptyIsNotAnError() { let empty = rows(.init(hasCache: true, loadMoreToken: nil)).first as? SearchEmptyRowItem; XCTAssertEqual(empty?.text, "not found"); XCTAssertNil(empty?.action) }
    func testLoadingDoesNotOfferRetry() { let empty = rows(.init(isLoading: true)).first as? SearchEmptyRowItem; XCTAssertEqual(empty?.isLoading, true); XCTAssertNil(empty?.action) }
    func testEmptyPageWithMoreCanContinue() { let empty = rows(.init(totalCount: 9, hasCache: true, loadMoreToken: "next")).first as? SearchEmptyRowItem; XCTAssertEqual(empty?.action?.title, "more"); empty?.action?.click(); XCTAssertEqual(loads, 1) }
    func testLoadedItemsIgnoreStaleZeroCount() { let output = rows(.init(items: [item(1)], hasCache: true, loadMoreToken: nil)); XCTAssertEqual(output.compactMap { $0 as? GridRow }.count, 1); XCTAssertFalse(output.contains { $0 is SearchEmptyRowItem }) }
    func testSearchUsesResultPeerNotAccount() { let row = rows(.init(items: [item(1)], totalCount: 1, hasCache: true, loadMoreToken: nil)).first as? GridRow; XCTAssertEqual(row?.peerId, .init(value: 2)); XCTAssertEqual(row?.reference.id, .init(value: 2)) }
    func testMissingAccountPeerDoesNotBlockResults() { let context = Context(); context.myPeer = nil; XCTAssertEqual(rows(.init(items: [item(1)], totalCount: 1, hasCache: true, loadMoreToken: nil), context: context).compactMap { $0 as? GridRow }.count, 1) }
    func testMalformedPeersCannotProduceWrongReferences() { let bad = StoryListContextState.Item(id: .init(peerId: .init(value: 3), id: 1), storyItem: .init(id: 1), peer: .init(id: .init(value: 2))); let output = rows(.init(items: [bad, item(2, valid: false)], totalCount: 2, hasCache: true, loadMoreToken: nil)); XCTAssertFalse(output.contains { $0 is GridRow }); XCTAssertEqual((output.first as? SearchEmptyRowItem)?.text, "not found") }
    func testPartialResultsKeepPaginationControl() { let output = rows(.init(items: [item(1)], totalCount: 5, hasCache: true, loadMoreToken: "next")); XCTAssertEqual(output.count, 2); XCTAssertEqual((output.last as? SearchEmptyRowItem)?.action?.title, "more") }
    func testResultLoadingKeepsGrid() { let output = rows(.init(items: [item(1)], totalCount: 5, isLoading: true, hasCache: true)); XCTAssertTrue(output.first is GridRow); XCTAssertEqual((output.last as? SearchEmptyRowItem)?.isLoading, true) }
    func testGridPreservesMixedPeerIdentity() { let grid = StoryMonthRowItem([item(1, peer: 2), item(1, peer: 3)], fallback: .init(value: 1)); _ = grid.makeSize(300); XCTAssertEqual(grid.layoutItems.map { $0.peerId.value }, [2, 3]); XCTAssertEqual(grid.layoutItems.map { $0.peerReference.id.value }, [2, 3]) }
    func testGridFallsBackForProfileItemWithoutPeer() { let value = StoryListContextState.Item(id: .init(peerId: .init(value: 2), id: 1), storyItem: .init(id: 1), peer: nil); let grid = StoryMonthRowItem([value], fallback: .init(value: 2)); _ = grid.makeSize(300); XCTAssertEqual(grid.layoutItems.first?.peerReference.id.value, 2) }
    private func mapItem(_ location: State.Location) -> MapRowItem { .init(.zero, height: 200, stableId: 0, context: Context(), location: location, userLocation: nil, geocodedPlacemark: nil, userLocationError: nil, presentation: theme, viewType: .legacy, action: {}) }
    func testMapUpdatesDoNotResetUserPanOrDuplicatePin() { let view = MapView(); let location = State.Location(coordinate: .init(latitude: 1, longitude: 2), venue: nil); view.set(item: mapItem(location)); view.set(item: mapItem(location)); XCTAssertEqual(view.focusCount, 1); XCTAssertEqual(view.mapView.additions, 1) }
    func testMapReuseReplacesOldVenue() { let view = MapView(); view.set(item: mapItem(.init(coordinate: .init(latitude: 1, longitude: 2), venue: nil))); view.set(item: mapItem(.init(coordinate: .init(latitude: 3, longitude: 4), venue: nil))); XCTAssertEqual(view.mapView.annotations.count, 1); XCTAssertEqual(view.focusCount, 2); XCTAssertEqual(view.mapView.removals, 1) }
    func testModalOwnsContextAndReleasesIt() { var modal: InputDataModalController? = screen(); weak var list = modal?.controller.contextObject as? SearchStoryListContext; XCTAssertNotNil(list); modal?.controller.didLoad?(modal!.controller, 0); modal = nil; XCTAssertNil(list) }
    func testBorrowedContextSurvivesModalAndScrollLoadsIt() { let list = SearchStoryListContext(account: Account(), source: .hashtag(nil, "tag")); var modal: InputDataModalController? = screen(list: list); modal?.controller.didLoad?(modal!.controller, 0); let count = list.loads; modal?.controller.tableView.scroll?(.init(direction: .top)); XCTAssertEqual(list.loads, count); modal?.controller.tableView.scroll?(.init(direction: .bottom)); XCTAssertEqual(list.loads, count + 1); modal = nil; list.loadMore(); XCTAssertEqual(list.loads, count + 2) }
}
