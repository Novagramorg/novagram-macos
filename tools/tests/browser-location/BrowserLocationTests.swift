import Foundation
import CoreLocation
import SwiftSignalKit
import XCTest

typealias PeerId = Int
final class Peer { let id: Int; let displayTitle: String; init(_ id: Int) { self.id = id; displayTitle = "bot \(id)" } }
__PERMISSIONS__
protocol AccountContextProtocol: AnyObject { var store: Store { get } }
final class Context: AccountContextProtocol { let store = Store(); let window = Window() }
final class Pending<T> {
    let subscriber: Subscriber<T, NoError>
    var cancelled = false
    var onDispose: (() -> Void)?
    init(_ subscriber: Subscriber<T, NoError>) { self.subscriber = subscriber }
    func send(_ value: T) { subscriber.putNext(value) }
    func complete() { subscriber.putCompletion() }
    func dispose() { cancelled = true; onDispose?() }
}
final class Store {
    var values: [PeerId: WebAppPermissionsState] = [:]
    var reads: [(PeerId, Pending<WebAppPermissionsState?>)] = []
    var writes: [(PeerId, (WebAppPermissionsState?) -> WebAppPermissionsState?, Pending<Never>)] = []
    var autoRead = true; var autoWrite = true
    func read(_ id: PeerId) -> Signal<WebAppPermissionsState?, NoError> {
        Signal { subscriber in
            let p = Pending(subscriber); self.reads.append((id, p))
            if self.autoRead { p.send(self.values[id]); p.complete() }
            return ActionDisposable { p.dispose() }
        }
    }
    func write(_ id: PeerId, _ update: @escaping (WebAppPermissionsState?) -> WebAppPermissionsState?) -> Signal<Never, NoError> {
        Signal { subscriber in
            let p = Pending(subscriber); self.writes.append((id, update, p))
            if self.autoWrite { self.values[id] = update(self.values[id]); p.complete() }
            return ActionDisposable { p.dispose() }
        }
    }
    func commitLast() { let (id, update, pending) = writes.last!; if !pending.cancelled { values[id] = update(values[id]); pending.complete() } }
}
func webAppPermissionsState(context: any AccountContextProtocol, peerId: PeerId) -> Signal<WebAppPermissionsState?, NoError> { context.store.read(peerId) }
func updateWebAppPermissionsStateInteractively(context: any AccountContextProtocol, peerId: PeerId, _ f: @escaping (WebAppPermissionsState?) -> WebAppPermissionsState?) -> Signal<Never, NoError> { context.store.write(peerId, f) }
func deliverOnMainQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
enum UserLocationRequestResult { case success(CLLocation), restricted, notDetermined, denied, wifiRequired, disabled }
final class Locator {
    var requests: [Pending<UserLocationRequestResult>] = []
    var synchronous: UserLocationRequestResult?
    var onSubscribe: (() -> Void)?
    func signal() -> Signal<UserLocationRequestResult, NoError> {
        Signal { subscriber in
            let pending = Pending(subscriber); self.requests.append(pending); self.onSubscribe?()
            if let result = self.synchronous { pending.send(result); pending.complete() }
            return ActionDisposable { pending.dispose() }
        }
    }
}
final class FeatureNavigationHooks { static var shared = FeatureNavigationHooks(); var locator = Locator(); func requestUserLocation() -> Signal<UserLocationRequestResult, NoError> { locator.signal() } }
final class Prompt { let allow: () -> Void; let deny: () -> Void; init(_ allow: @escaping () -> Void, _ deny: @escaping () -> Void) { self.allow = allow; self.deny = deny } }
final class Window { func makeKeyAndOrderFront(_ value: Any?) {}
    var prompts: [Prompt] = []; var texts: [String] = []; func removeObserver(for object: AnyObject) {} }
struct Strings {
    let webAppLocationPermissionAllow = "allow", webAppLocationPermissionDecline = "decline", webAppLocationPermissionDeniedError = "denied", webAppLocationPermissionWifiError = "wifi", webAppLocationPermissionDisabledError = "disabled"
    func webAppLocationPermissionText(_ a: String, _ b: String) -> String { a + b }
    func webAppLocationPermissionSucceed(_ a: String) -> String { a }
}
func strings() -> Strings { .init() }
func verifyAlert(for window: Window, information: String, ok: String, cancel: String, successHandler: @escaping (Bool) -> Void, cancelHandler: @escaping () -> Void) { window.prompts.append(Prompt({ successHandler(true) }, cancelHandler)) }
func showModalText(for window: Window, text: String) { window.texts.append(text) }
struct JSON {
    let data: [String: Any]
    init?(dictionary: [String: Any]) { guard JSONSerialization.isValidJSONObject(dictionary) else { return nil }; data = dictionary }
    var string: String? { (try? JSONSerialization.data(withJSONObject: data)).flatMap { String(data: $0, encoding: .utf8) } }
}
var testTimestamp: Double = 100
func CACurrentMediaTime() -> Double { testTimestamp }
final class BrowserHooks {
    static let shared = BrowserHooks(); var opened: [PeerId] = []
    func openPeerInfo(_ context: any AccountContextProtocol, _ id: PeerId) { opened.append(id) }
}
final class Queue { static let main = Queue(); static func mainQueue() -> Queue { main }; func after(_ delay: Double, _ action: @escaping () -> Void) { action() } }
__SOURCE__
class BaseController { func viewWillDisappear(_ animated: Bool) {}; func viewWillAppear(_ animated: Bool) {} }
final class Resettable { func reset() {} }
final class Controller: BaseController {
    var lastTouchTimestamp: Double?
    let context = Context(); var bot: Peer? = Peer(10); var window: Window? = Window()
    let locationAction = BrowserLocationAction(); var acceptsLocationRequests = true
    let emojiPermissionAction = Resettable()
    let emojiStatusAction = Resettable()
    let preparedShareAction = Resettable(); let apperanceDisposable = MetaDisposable()
    var events: [(String, [String: Any])] = []
    func sendEvent(name: String, data: String?) { guard let data = data?.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }; events.append((name, object)) }
    func cancelPendingInvoices() {}
    __METHODS__
}

final class BrowserLocationTests: XCTestCase {
    override func setUp() { FeatureNavigationHooks.shared = FeatureNavigationHooks(); BrowserHooks.shared.opened = []; testTimestamp = 100 }
    var locator: Locator { FeatureNavigationHooks.shared.locator }
    func allowed(_ controller: Controller) { controller.context.store.values[10] = .init(location: .init(isRequested: true, isAllowed: true), emojiStatus: .init(isRequested: true)) }
    func coordinate(_ latitude: Double = 1, horizontal: Double = 10, vertical: Double = -1, altitude: Double = 0, course: Double = -1, speed: Double = -1) -> CLLocation { .init(coordinate: .init(latitude: latitude, longitude: 2), altitude: altitude, horizontalAccuracy: horizontal, verticalAccuracy: vertical, course: course, speed: speed, timestamp: Date()) }
    func result(_ controller: Controller) -> [String: Any]? { controller.events.last?.1 }
    func testNavigationClearsSettingsGesture() { let c = Controller(); c.lastTouchTimestamp = 100; c.cancelPendingPageActions(); c.openLocationSettings(); XCTAssertTrue(BrowserHooks.shared.opened.isEmpty) }
    func testReappearingPageCannotReuseOldGesture() { let c = Controller(); c.lastTouchTimestamp = 100; c.viewWillDisappear(false); c.viewWillAppear(false); c.openLocationSettings(); XCTAssertTrue(BrowserHooks.shared.opened.isEmpty) }
    func testSettingsRequiresRecentInteraction() { let c = Controller(); c.openLocationSettings(); XCTAssertTrue(BrowserHooks.shared.opened.isEmpty); c.lastTouchTimestamp = 89; c.openLocationSettings(); XCTAssertTrue(BrowserHooks.shared.opened.isEmpty) }
    func testSettingsConsumesInteractionOnce() { let c = Controller(); c.lastTouchTimestamp = 95; c.openLocationSettings(); c.openLocationSettings(); XCTAssertEqual(BrowserHooks.shared.opened, [10]); XCTAssertNil(c.lastTouchTimestamp) }
    func testSettingsRejectsHiddenPageAndFutureTimestamp() { let c = Controller(); c.lastTouchTimestamp = 101; c.openLocationSettings(); XCTAssertTrue(BrowserHooks.shared.opened.isEmpty); c.lastTouchTimestamp = 100; c.viewWillDisappear(false); c.openLocationSettings(); XCTAssertTrue(BrowserHooks.shared.opened.isEmpty) }
    func testSettingsUsesCurrentBot() { let c = Controller(); c.lastTouchTimestamp = 100; c.bot = Peer(20); c.openLocationSettings(); XCTAssertEqual(BrowserHooks.shared.opened, [20]) }
    func testSettingsAcceptsTenSecondBoundary() { let c = Controller(); c.lastTouchTimestamp = 90; c.openLocationSettings(); XCTAssertEqual(BrowserHooks.shared.opened, [10]) }
    func testResetDuringFinalReadDisposalSuppressesDelivery() {
        let c = Controller(); allowed(c); c.requestLocation(); c.context.store.autoRead = false
        locator.requests.last?.send(.success(coordinate()))
        let pending = c.context.store.reads.last!.1
        pending.onDispose = { c.cancelPendingPageActions() }
        pending.send(c.context.store.values[10]); XCTAssertTrue(c.events.isEmpty)
        pending.onDispose = nil
    }
    func testResetDuringPermissionReadDisposalDoesNotAcquireLocation() {
        let c = Controller(); allowed(c); c.context.store.autoRead = false; c.requestLocation()
        let pending = c.context.store.reads.last!.1; pending.onDispose = { c.cancelPendingPageActions() }
        pending.send(c.context.store.values[10]); XCTAssertTrue(locator.requests.isEmpty)
        pending.onDispose = nil
    }
    func testResetDoesNotCancelReentrantNewCheck() {
        let c = Controller(); allowed(c); c.requestLocation(); c.context.store.autoRead = false
        let location = locator.requests.last!; location.onDispose = { c.checkLocation() }
        c.cancelPendingPageActions(); location.onDispose = nil
        let check = c.context.store.reads.last!.1; XCTAssertFalse(check.cancelled)
        check.send(c.context.store.values[10]); XCTAssertEqual(c.events.last?.0, "location_checked")
    }
    func testUnknownPermissionDoesNotAcquireLocationBeforeConsent() { let c = Controller(); c.requestLocation(); XCTAssertEqual(c.window?.prompts.count, 1); XCTAssertTrue(locator.requests.isEmpty) }
    func testPreviouslyDeniedPermissionDoesNotAcquireOrPrompt() { let c = Controller(); c.context.store.values[10] = .init(location: .init(isRequested: true, isAllowed: false), emojiStatus: nil); c.requestLocation(); XCTAssertTrue(locator.requests.isEmpty); XCTAssertTrue(c.window!.prompts.isEmpty); XCTAssertEqual(result(c)?["available"] as? Bool, false) }
    func testAllowedResultUsesCapturedBotAndValidPayload() { let c = Controller(); allowed(c); c.requestLocation(); locator.requests.last?.send(.success(coordinate())); XCTAssertEqual(c.events.count, 1); XCTAssertEqual(result(c)?["available"] as? Bool, true); XCTAssertEqual(result(c)?["latitude"] as? Double, 1); XCTAssertEqual(c.context.store.reads.map { $0.0 }, [10, 10]) }
    func testPermissionWriteCompletesBeforeAcquisition() { let c = Controller(); c.context.store.autoWrite = false; c.requestLocation(); c.window?.prompts.first?.allow(); XCTAssertTrue(locator.requests.isEmpty); XCTAssertTrue(c.window!.texts.isEmpty); c.context.store.commitLast(); XCTAssertEqual(locator.requests.count, 1); XCTAssertEqual(c.window?.texts.count, 1) }
    func testPermissionGrantPreservesEmojiState() { let c = Controller(); c.context.store.values[10] = .init(location: nil, emojiStatus: .init(isRequested: true)); c.requestLocation(); c.window?.prompts.first?.allow(); XCTAssertEqual(c.context.store.values[10]?.emojiStatus?.isRequested, true); XCTAssertEqual(c.context.store.values[10]?.location?.isAllowed, true); XCTAssertEqual(locator.requests.count, 1) }
    func testDeclinePreservesEmojiAndAnswersWithoutLocation() { let c = Controller(); c.context.store.values[10] = .init(location: nil, emojiStatus: .init(isRequested: true)); c.requestLocation(); c.window?.prompts.first?.deny(); XCTAssertTrue(locator.requests.isEmpty); XCTAssertEqual(c.context.store.values[10]?.emojiStatus?.isRequested, true); XCTAssertEqual(c.context.store.values[10]?.location?.isAllowed, false); XCTAssertEqual(result(c)?["available"] as? Bool, false) }
    func testRepeatedRequestsDoNotDuplicatePromptsOrAcquisition() { let c = Controller(); c.requestLocation(); c.requestLocation(); XCTAssertEqual(c.window?.prompts.count, 1); c.window?.prompts.first?.allow(); c.requestLocation(); XCTAssertEqual(locator.requests.count, 1) }
    func testRepeatedPromptCallbacksCannotOverwriteDecision() { let c = Controller(); c.requestLocation(); let prompt = c.window!.prompts[0]; prompt.allow(); prompt.deny(); prompt.allow(); XCTAssertEqual(c.context.store.writes.count, 1); XCTAssertEqual(c.context.store.values[10]?.location?.isAllowed, true) }
    func testAllLocationFailuresAnswerUnavailable() { for failure in [UserLocationRequestResult.denied, .restricted, .wifiRequired, .disabled, .notDetermined] { let c = Controller(); allowed(c); c.requestLocation(); locator.requests.last?.send(failure); XCTAssertEqual(result(c)?["available"] as? Bool, false); XCTAssertEqual(c.events.count, 1); XCTAssertEqual(c.window?.texts.count, 1) } }
    func testEmptyLocationSignalAnswersUnavailableAndAllowsRetry() { let c = Controller(); allowed(c); c.requestLocation(); locator.requests.last?.complete(); XCTAssertEqual(result(c)?["available"] as? Bool, false); c.requestLocation(); XCTAssertEqual(locator.requests.count, 2) }
    func testEmptyPermissionReadAnswersUnavailable() { let c = Controller(); c.context.store.autoRead = false; c.requestLocation(); c.context.store.reads.last?.1.complete(); XCTAssertEqual(result(c)?["available"] as? Bool, false); XCTAssertTrue(locator.requests.isEmpty) }
    func testPageResetCancelsReadAndSuppressesDelivery() { let c = Controller(); c.context.store.autoRead = false; c.requestLocation(); let pending = c.context.store.reads[0].1; c.cancelPendingPageActions(); XCTAssertTrue(pending.cancelled); pending.send(nil); XCTAssertTrue(c.window!.prompts.isEmpty); XCTAssertTrue(c.events.isEmpty) }
    func testPageResetCancelsAcquisitionAndOldResult() { let c = Controller(); allowed(c); c.requestLocation(); let pending = locator.requests[0]; c.cancelPendingPageActions(); XCTAssertTrue(pending.cancelled); pending.send(.success(coordinate())); XCTAssertTrue(c.events.isEmpty) }
    func testOldPromptAfterResetCannotPersistPermission() { let c = Controller(); c.requestLocation(); let prompt = c.window!.prompts[0]; c.cancelPendingPageActions(); prompt.allow(); prompt.deny(); XCTAssertTrue(c.context.store.writes.isEmpty); XCTAssertTrue(locator.requests.isEmpty); XCTAssertTrue(c.events.isEmpty) }
    func testResetDuringSaveCancelsContinuation() { let c = Controller(); c.context.store.autoWrite = false; c.requestLocation(); c.window?.prompts.first?.allow(); let pending = c.context.store.writes[0].2; c.cancelPendingPageActions(); XCTAssertTrue(pending.cancelled); pending.complete(); XCTAssertTrue(locator.requests.isEmpty) }
    func testDisappearStopsAndReappearAcceptsNewRequest() { let c = Controller(); allowed(c); c.requestLocation(); let pending = locator.requests[0]; c.viewWillDisappear(false); XCTAssertTrue(pending.cancelled); c.requestLocation(); XCTAssertEqual(locator.requests.count, 1); c.viewWillAppear(false); c.requestLocation(); XCTAssertEqual(locator.requests.count, 2) }
    func testChangedBotCannotReceiveOldLocation() { let c = Controller(); allowed(c); c.requestLocation(); c.bot = Peer(20); locator.requests.last?.send(.success(coordinate())); XCTAssertTrue(c.events.isEmpty); c.requestLocation(); XCTAssertEqual(c.context.store.reads.last?.0, 20) }
    func testChangedWindowCannotReceiveOldLocation() { let c = Controller(); allowed(c); c.requestLocation(); c.window = Window(); locator.requests.last?.send(.success(coordinate())); XCTAssertTrue(c.events.isEmpty) }
    func testPermissionRevokedDuringAcquisitionSuppressesCoordinates() { let c = Controller(); allowed(c); c.requestLocation(); c.context.store.values[10] = .init(location: .init(isRequested: true, isAllowed: false), emojiStatus: nil); locator.requests.last?.send(.success(coordinate())); XCTAssertEqual(result(c)?["available"] as? Bool, false); XCTAssertNil(result(c)?["latitude"]) }
    func testResetDuringFinalValidationSuppressesResult() { let c = Controller(); allowed(c); c.requestLocation(); c.context.store.autoRead = false; locator.requests.last?.send(.success(coordinate())); let pending = c.context.store.reads.last!.1; c.cancelPendingPageActions(); XCTAssertTrue(pending.cancelled); pending.send(.init(location: .init(isRequested: true, isAllowed: true), emojiStatus: nil)); XCTAssertTrue(c.events.isEmpty) }
    func testMissingBotOrWindowAnswersUnavailable() { let c = Controller(); c.bot = nil; c.requestLocation(); XCTAssertEqual(result(c)?["available"] as? Bool, false); c.bot = Peer(10); c.window = nil; c.requestLocation(); XCTAssertEqual(c.events.count, 2); XCTAssertTrue(locator.requests.isEmpty) }
    func testSynchronousLocationCompletionDoesNotCancelNextRequest() { let c = Controller(); allowed(c); locator.synchronous = .success(coordinate()); c.requestLocation(); c.requestLocation(); XCTAssertEqual(c.events.count, 2); XCTAssertEqual(locator.requests.count, 2) }
    func testCancelDuringSubscribeOwnsReturnedDisposable() { let c = Controller(); allowed(c); locator.onSubscribe = { c.cancelPendingPageActions() }; c.requestLocation(); XCTAssertEqual(locator.requests.count, 1); XCTAssertTrue(locator.requests[0].cancelled); XCTAssertTrue(c.events.isEmpty); locator.onSubscribe = nil }
    func testControllerReleasesWhileLocationIsPending() { var c: Controller? = Controller(); allowed(c!); c!.requestLocation(); weak var weakController = c; c = nil; XCTAssertNil(weakController); XCTAssertTrue(locator.requests[0].cancelled) }
    func testControllerReleasesWithRetainedConsentPrompt() { var c: Controller? = Controller(); c!.requestLocation(); let window = c!.window!; weak var weakController = c; c = nil; XCTAssertNil(weakController); window.prompts.first?.allow(); XCTAssertTrue(locator.requests.isEmpty) }
    func testCheckNeverRequestsCoordinatesOrConsent() { let c = Controller(); allowed(c); c.checkLocation(); XCTAssertEqual(c.events.last?.0, "location_checked"); XCTAssertEqual(result(c)?["access_requested"] as? Bool, true); XCTAssertEqual(result(c)?["access_granted"] as? Bool, true); XCTAssertTrue(locator.requests.isEmpty); XCTAssertTrue(c.window!.prompts.isEmpty) }
    func testCheckAbsentPermissionOmitsGrantedField() { let c = Controller(); c.checkLocation(); XCTAssertEqual(result(c)?["access_requested"] as? Bool, false); XCTAssertNil(result(c)?["access_granted"]) }
    func testCheckResetCancelsAndSuppressesOldState() { let c = Controller(); c.context.store.autoRead = false; c.checkLocation(); let pending = c.context.store.reads.last!.1; c.cancelPendingPageActions(); XCTAssertTrue(pending.cancelled); pending.send(nil); XCTAssertTrue(c.events.isEmpty) }
    func testEmptyCheckStillAnswers() { let c = Controller(); c.context.store.autoRead = false; c.checkLocation(); c.context.store.reads.last?.1.complete(); XCTAssertEqual(c.events.count, 1); XCTAssertEqual(result(c)?["access_requested"] as? Bool, false) }
    func testUnknownSensorValuesBecomeJSONNull() { let data = BrowserLocationAction.locationData(coordinate()); for field in ["altitude", "course", "speed", "vertical_accuracy", "course_accuracy", "speed_accuracy"] { XCTAssertTrue(data[field] is NSNull, field) }; XCTAssertTrue(JSONSerialization.isValidJSONObject(data)) }
    func testNegativeAltitudeAndZeroSpeedRemainValid() { let data = BrowserLocationAction.locationData(coordinate(vertical: 10, altitude: -20, course: 0, speed: 0)); XCTAssertEqual(data["altitude"] as? Double, -20); XCTAssertEqual(data["course"] as? Double, 0); XCTAssertEqual(data["speed"] as? Double, 0) }
    func testInvalidCoordinatesCannotProduceAvailablePayload() { for value in [coordinate(100), coordinate(horizontal: -1), coordinate(horizontal: .infinity)] { let data = BrowserLocationAction.locationData(value); XCTAssertEqual(data["available"] as? Bool, false); XCTAssertNil(data["latitude"]); XCTAssertTrue(JSONSerialization.isValidJSONObject(data)) } }
}
