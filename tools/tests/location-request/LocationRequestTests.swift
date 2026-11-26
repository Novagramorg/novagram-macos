import Foundation
import CoreLocation
import SwiftSignalKit
import XCTest

final class Queue {
    static let main = Queue()
    private let lock = NSLock()
    private var tasks: [() -> Void] = []
    var executing = false
    static func mainQueue() -> Queue { main }
    func async(_ f: @escaping () -> Void) { lock.lock(); tasks.append(f); lock.unlock() }
    func drain() {
        while true {
            lock.lock(); let task = tasks.isEmpty ? nil : tasks.removeFirst(); lock.unlock()
            guard let task else { break }
            executing = true; task(); executing = false
        }
    }
}
protocol CLLocationManagerDelegate: AnyObject {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
}
extension CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { locationManager(manager, didChangeAuthorization: manager.authorizationStatus) }
}
final class CLLocationManager: NSObject {
    final class Weak { weak var value: CLLocationManager?; init(_ value: CLLocationManager) { self.value = value } }
    static var known: [Weak] = []
    static var servicesEnabled = true
    static var status: CLAuthorizationStatus = .authorizedAlways
    static var instances: [CLLocationManager] = []
    static var created = 0
    static var offQueueOperations = 0
    static var onRequest: ((CLLocationManager) -> Void)?
    static var onAuthorization: ((CLLocationManager) -> Void)?
    static var onDelegate: ((CLLocationManager) -> Void)?
    static var onStop: ((CLLocationManager) -> Void)?
    weak var delegate: CLLocationManagerDelegate? {
        didSet {
            if !Queue.main.executing { Self.offQueueOperations += 1 }
            if delegate != nil {
                if !Self.instances.contains(where: { $0 === self }) { Self.instances.append(self) }
                Self.onDelegate?(self)
            }
        }
    }
    var desiredAccuracy: Double = 0
    var authorizationStatus: CLAuthorizationStatus { Self.status }
    var starts = 0; var stops = 0; var prompts = 0; var oneShots = 0
    override init() { super.init(); Self.created += 1; if !Queue.main.executing { Self.offQueueOperations += 1 }; Self.instances.append(self); Self.known.append(Weak(self)) }
    static func locationServicesEnabled() -> Bool { servicesEnabled }
    static func authorizationStatus() -> CLAuthorizationStatus { status }
    func startUpdatingLocation() { starts += 1; Self.onRequest?(self) }
    func requestLocation() { oneShots += 1; Self.onRequest?(self) }
    func stopUpdatingLocation() { stops += 1; if !Queue.main.executing { Self.offQueueOperations += 1 }; Self.onStop?(self) }
    func requestWhenInUseAuthorization() { prompts += 1; Self.onAuthorization?(self) }
    func locations(_ values: [CLLocation]) { delegate?.locationManager(self, didUpdateLocations: values) }
    func fail(_ code: CLError.Code) { delegate?.locationManager(self, didFailWithError: CLError(code)) }
    func authorize(_ status: CLAuthorizationStatus, modern: Bool = false) { Self.status = status; if modern { delegate?.locationManagerDidChangeAuthorization(self) } else { delegate?.locationManager(self, didChangeAuthorization: status) } }
}
__SOURCE__

final class Sink {
    var results: [UserLocationResult] = []; var errors: [UserLocationError] = []; var completions = 0
    var onNext: (() -> Void)?
    func subscribe(_ signal: Signal<UserLocationResult, UserLocationError> = requestUserLocation()) -> Disposable {
        signal.start(next: { self.results.append($0); self.onNext?() }, error: { self.errors.append($0) }, completed: { self.completions += 1 })
    }
}

final class LocationRequestTests: XCTestCase {
    let modern = __MODERN__
    override func setUp() {
        Queue.main.drain()
        onMain {
            for manager in CLLocationManager.known.compactMap({ $0.value }) {
                manager.delegate = nil; manager.starts = 0; manager.stops = 0; manager.prompts = 0; manager.oneShots = 0
            }
        }
        CLLocationManager.known.removeAll { $0.value == nil }
        CLLocationManager.instances.removeAll(); CLLocationManager.created = 0; CLLocationManager.offQueueOperations = 0
        CLLocationManager.status = .authorizedAlways; CLLocationManager.servicesEnabled = true
        CLLocationManager.onRequest = nil; CLLocationManager.onAuthorization = nil; CLLocationManager.onDelegate = nil; CLLocationManager.onStop = nil
    }
    override func tearDown() {
        CLLocationManager.onRequest = nil; CLLocationManager.onAuthorization = nil; CLLocationManager.onDelegate = nil; CLLocationManager.onStop = nil
        Queue.main.drain(); CLLocationManager.instances.removeAll()
    }
    func location(_ latitude: Double = 1, accuracy: Double = 20) -> CLLocation { .init(coordinate: .init(latitude: latitude, longitude: 2), altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: Date(timeIntervalSince1970: 100)) }
    func onMain(_ f: @escaping () -> Void) { Queue.main.async(f); Queue.main.drain() }
    var latest: CLLocationManager { CLLocationManager.instances.last! }
    func testCancellationSuppressesCallbackBeforeMainCleanup() {
        let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let manager = latest; let delegate = manager.delegate
        d.dispose()
        Queue.main.executing = true
        delegate?.locationManager(manager, didChangeAuthorization: .authorizedAlways)
        delegate?.locationManager(manager, didUpdateLocations: [location()])
        Queue.main.executing = false
        XCTAssertTrue(sink.results.isEmpty); Queue.main.drain(); XCTAssertNil(manager.delegate)
    }
    func testForeignManagerCallbacksCannotFinishRequest() {
        let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let manager = latest; let delegate = manager.delegate
        onMain {
            let foreign = CLLocationManager()
            delegate?.locationManager(foreign, didFailWithError: CLError(.denied))
            delegate?.locationManager(foreign, didUpdateLocations: [self.location()])
        }
        XCTAssertTrue(sink.errors.isEmpty); XCTAssertTrue(sink.results.isEmpty)
        onMain { manager.locations([self.location()]) }; XCTAssertEqual(sink.results.count, 1); d.dispose()
    }
    func testUnavailableFixTerminatesOneShot() {
        let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let manager = latest
        onMain { manager.fail(.locationUnknown) }; XCTAssertEqual(sink.errors, [.wifiRequired]); XCTAssertNil(manager.delegate); d.dispose()
    }
    func testZeroCoordinateAndAccuracyAreValid() {
        let value = CLLocation(coordinate: .init(latitude: 0, longitude: 0), altitude: 0, horizontalAccuracy: 0, verticalAccuracy: -1, timestamp: Date())
        let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); onMain { self.latest.locations([value]) }; XCTAssertEqual(sink.results, [.success(value)]); XCTAssertEqual(sink.completions, 1); d.dispose()
    }
    func testTakeOneDisposesWithoutDoubleCompletion() {
        let sink = Sink(); let d = sink.subscribe(requestUserLocation() |> take(1)); Queue.main.drain(); let manager = latest
        onMain { manager.locations([self.location()]) }; XCTAssertEqual(sink.results.count, 1); XCTAssertEqual(sink.completions, 1); XCTAssertEqual(manager.stops, 1); d.dispose()
    }
    func testSubscriberCanCancelDuringNext() {
        let sink = Sink(); let d = sink.subscribe(); sink.onNext = { d.dispose() }; Queue.main.drain(); let manager = latest
        onMain { manager.locations([self.location()]) }; XCTAssertEqual(sink.results.count, 1); XCTAssertEqual(sink.completions, 0); XCTAssertEqual(manager.stops, 1)
    }
    func testStoppingIgnoresReentrantDelegateFailure() {
        let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let manager = latest; let delegate = manager.delegate
        CLLocationManager.onStop = { delegate?.locationManager($0, didFailWithError: CLError(.denied)) }
        onMain { manager.locations([self.location()]) }; XCTAssertEqual(sink.results.count, 1); XCTAssertEqual(sink.completions, 1); XCTAssertTrue(sink.errors.isEmpty); d.dispose()
    }
    func testColdSignalDoesNotStartServices() { let signal = requestUserLocation(); XCTAssertEqual(CLLocationManager.created, 0); withExtendedLifetime(signal) {} }
    func testCancellationBeforeQueuedStartDoesNotPromptOrCreateManager() { let sink = Sink(); CLLocationManager.status = .notDetermined; let d = sink.subscribe(); d.dispose(); Queue.main.drain(); XCTAssertEqual(CLLocationManager.created, 0); XCTAssertTrue(sink.results.isEmpty); XCTAssertTrue(sink.errors.isEmpty) }
    func testConcurrentSubscriptionsUseIndependentManagers() {
        let a = Sink(), b = Sink(); let da = a.subscribe(), db = b.subscribe(); Queue.main.drain()
        XCTAssertEqual(CLLocationManager.instances.count, 2)
        let first = CLLocationManager.instances.first!, last = latest
        let firstLocation = location(1), secondLocation = location(2)
        onMain { first.locations([firstLocation]); last.locations([secondLocation]) }
        XCTAssertEqual(a.results, [.success(firstLocation)]); XCTAssertEqual(b.results, [.success(secondLocation)]); XCTAssertEqual(a.completions, 1); XCTAssertEqual(b.completions, 1)
        da.dispose(); db.dispose()
    }
    func testCancellingOlderRequestDoesNotStopNewRequest() {
        let a = Sink(), b = Sink(); let da = a.subscribe(); Queue.main.drain(); let old = latest
        let db = b.subscribe(); Queue.main.drain(); let current = latest
        da.dispose(); Queue.main.drain(); XCTAssertEqual(old.stops, 1); XCTAssertNotNil(current.delegate); XCTAssertEqual(current.stops, 0)
        onMain { current.locations([self.location()]) }; XCTAssertEqual(b.results.count, 1); XCTAssertTrue(a.results.isEmpty); db.dispose()
    }
    func testDisposalFromBackgroundOnlyTouchesManagerOnMainQueue() {
        let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let manager = latest
        DispatchQueue.global().sync { d.dispose() }
        XCTAssertEqual(manager.stops, 0); Queue.main.drain(); XCTAssertEqual(manager.stops, 1); XCTAssertEqual(CLLocationManager.offQueueOperations, 0)
    }
    func testSubscriptionFromBackgroundCreatesManagerOnMainQueue() {
        let sink = Sink(); var d: Disposable?
        DispatchQueue.global().sync { d = sink.subscribe() }
        XCTAssertEqual(CLLocationManager.created, 0); Queue.main.drain(); XCTAssertEqual(CLLocationManager.created, 1); XCTAssertEqual(CLLocationManager.offQueueOperations, 0); d?.dispose()
    }
    func testSuccessStopsBeforeCallbackAndCompletesOnce() {
        let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let manager = latest
        sink.onNext = { XCTAssertNil(manager.delegate); XCTAssertEqual(manager.stops, 1) }
        onMain { manager.locations([self.location()]); manager.locations([self.location(3)]) }
        XCTAssertEqual(sink.results.count, 1); XCTAssertEqual(sink.completions, 1); XCTAssertTrue(sink.errors.isEmpty); d.dispose(); Queue.main.drain(); XCTAssertEqual(manager.stops, 1)
    }
    func testErrorsStopAndDetachManager() {
        let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let manager = latest
        onMain { manager.fail(.network) }; XCTAssertEqual(sink.errors, [.wifiRequired]); XCTAssertNil(manager.delegate); XCTAssertEqual(manager.stops, 1); d.dispose()
    }
    func testDeniedErrorKeepsPermissionMeaning() { let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); onMain { self.latest.fail(.denied) }; XCTAssertEqual(sink.errors, [.denied]); d.dispose() }
    func testDisabledServicesFailWithoutStarting() { CLLocationManager.servicesEnabled = false; let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); XCTAssertEqual(sink.errors, [.disabled]); XCTAssertEqual(CLLocationManager.created, 0); d.dispose() }
    func testDeniedAuthorizationStopsWithoutRequest() { CLLocationManager.status = .denied; let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); XCTAssertEqual(sink.errors, [.denied]); XCTAssertEqual(latest.oneShots + latest.starts, 0); XCTAssertNil(latest.delegate); d.dispose() }
    func testRestrictedAuthorizationKeepsMeaning() { CLLocationManager.status = .restricted; let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); XCTAssertEqual(sink.errors, [.restricted]); XCTAssertNil(latest.delegate); d.dispose() }
    func testAuthorizationPromptsOnceAndStartsOnce() {
        CLLocationManager.status = .notDetermined; let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let manager = latest
        onMain { manager.authorize(.notDetermined); manager.authorize(.authorizedAlways); manager.authorize(.authorizedAlways, modern: true) }
        XCTAssertEqual(manager.prompts, modern ? 1 : 0); XCTAssertEqual(manager.oneShots, modern ? 1 : 0); XCTAssertEqual(manager.starts, modern ? 0 : 1); d.dispose()
    }
    func testCancelledPermissionRequestIgnoresQueuedDelegateCallbacks() {
        CLLocationManager.status = .notDetermined; let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let manager = latest; let delegate = manager.delegate
        d.dispose(); onMain { delegate?.locationManager(manager, didChangeAuthorization: .authorizedAlways); delegate?.locationManager(manager, didUpdateLocations: [self.location()]) }
        XCTAssertEqual(manager.starts + manager.oneShots, modern ? 0 : 1); XCTAssertTrue(sink.results.isEmpty); XCTAssertNil(manager.delegate)
    }
    func testCancelDuringDelegateAssignmentDoesNotStartServices() {
        let sink = Sink(); let d = sink.subscribe(); CLLocationManager.onDelegate = { _ in d.dispose() }; Queue.main.drain()
        XCTAssertEqual(latest.starts + latest.oneShots, 0); XCTAssertNil(latest.delegate); XCTAssertTrue(sink.results.isEmpty)
    }
    func testSynchronousSuccessDuringStartIsDeliveredAndReleased() {
        CLLocationManager.onRequest = { $0.locations([self.location()]) }; let sink = Sink(); let d = sink.subscribe(); Queue.main.drain()
        XCTAssertEqual(sink.results.count, 1); XCTAssertEqual(sink.completions, 1); XCTAssertNil(latest.delegate); d.dispose()
    }
    func testSynchronousPermissionGrantStartsOnce() {
        CLLocationManager.status = .notDetermined; CLLocationManager.onAuthorization = { $0.authorize(.authorizedAlways, modern: true) }
        let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); XCTAssertEqual(latest.prompts, modern ? 1 : 0); XCTAssertEqual(latest.oneShots, modern ? 1 : 0); XCTAssertEqual(latest.starts, modern ? 0 : 1); d.dispose()
    }
    func testSuccessCanStartNewRequestWithoutOldCleanupStoppingIt() {
        let a = Sink(), b = Sink(); var second: Disposable?; a.onNext = { second = b.subscribe() }
        let first = a.subscribe(); Queue.main.drain(); let old = latest; onMain { old.locations([self.location()]) }; let new = latest
        first.dispose(); Queue.main.drain(); XCTAssertNotNil(new.delegate); XCTAssertEqual(new.stops, 0); onMain { new.locations([self.location(3)]) }; XCTAssertEqual(b.results.count, 1); second?.dispose()
    }
    func testLastValidLocationWins() { let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let values = [location(1), location(2), location(3, accuracy: -1)]; onMain { self.latest.locations(values) }; XCTAssertEqual(sink.results, [.success(values[1])]); d.dispose() }
    func testInvalidAccuracyFailsWithoutExposingCoordinates() { let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); onMain { self.latest.locations([self.location(1, accuracy: -1)]) }; XCTAssertTrue(sink.results.isEmpty); XCTAssertEqual(sink.errors, [.wifiRequired]); d.dispose() }
    func testInvalidCoordinateFailsWithoutExposingCoordinates() { let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); onMain { self.latest.locations([self.location(100)]) }; XCTAssertTrue(sink.results.isEmpty); XCTAssertEqual(sink.errors, [.wifiRequired]); d.dispose() }
    func testEmptyOneShotResultFinishesWithError() { let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); onMain { self.latest.locations([]) }; XCTAssertEqual(sink.errors, [.wifiRequired]); XCTAssertNil(latest.delegate); d.dispose() }
    func testRetainedOldDelegateCannotDeliverAfterCompletion() { let sink = Sink(); let d = sink.subscribe(); Queue.main.drain(); let manager = latest, delegate = manager.delegate; onMain { manager.locations([self.location()]); delegate?.locationManager(manager, didFailWithError: CLError(.denied)); delegate?.locationManager(manager, didUpdateLocations: [self.location(4)]) }; XCTAssertEqual(sink.results.count, 1); XCTAssertTrue(sink.errors.isEmpty); XCTAssertEqual(sink.completions, 1); d.dispose() }
    func testCancellationReleasesManagerAndSubscriberCaptures() {
        var sink: Sink? = Sink(); weak var weakSink = sink; let d = sink!.subscribe(); Queue.main.drain(); weak var manager = CLLocationManager.instances.last
        sink = nil; d.dispose(); CLLocationManager.instances.removeAll(); Queue.main.drain(); XCTAssertNil(manager); XCTAssertNil(weakSink)
    }
    func testCompletionReleasesManagerAndSubscriberCaptures() {
        var sink: Sink? = Sink(); weak var weakSink = sink; let d = sink!.subscribe(); Queue.main.drain(); weak var manager = CLLocationManager.instances.last
        onMain { self.latest.locations([self.location()]) }; sink = nil; CLLocationManager.instances.removeAll(); Queue.main.drain(); XCTAssertNil(manager); XCTAssertNil(weakSink); withExtendedLifetime(d) {}
    }
}
