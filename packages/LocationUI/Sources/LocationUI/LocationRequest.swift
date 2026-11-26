import Foundation
import CoreLocation
import SwiftSignalKit

public enum UserLocationResult: Equatable {
    case success(CLLocation)
}

public enum UserLocationError: Equatable {
    case restricted
    case notDetermined
    case denied
    case wifiRequired
    case disabled
}

private final class UserLocationRequest: NSObject, CLLocationManagerDelegate {
    private let isCancelled = Atomic(value: false)
    private var subscriber: Subscriber<UserLocationResult, UserLocationError>?
    private var manager: CLLocationManager?
    private var requestedAuthorization = false
    private var requestedLocation = false

    init(subscriber: Subscriber<UserLocationResult, UserLocationError>) {
        self.subscriber = subscriber
        super.init()
    }

    func start() {
        guard !self.isCancelled.with({ $0 }), self.subscriber != nil else {
            self.stop()
            return
        }
        guard CLLocationManager.locationServicesEnabled() else {
            self.fail(.disabled)
            return
        }
        let manager = CLLocationManager()
        self.manager = manager
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.delegate = self
        if #available(macOS 11.0, *) {
            self.locationManager(manager, didChangeAuthorization: manager.authorizationStatus)
        } else {
            self.locationManager(manager, didChangeAuthorization: CLLocationManager.authorizationStatus())
        }
    }

    func cancel() {
        self.isCancelled.swap(true)
        Queue.mainQueue().async {
            self.stop()
        }
    }

    private func stop() {
        self.subscriber = nil
        let manager = self.manager
        self.manager = nil
        manager?.delegate = nil
        manager?.stopUpdatingLocation()
    }

    private func fail(_ error: UserLocationError) {
        guard !self.isCancelled.with({ $0 }), let subscriber = self.subscriber else {
            return
        }
        self.stop()
        subscriber.putError(error)
    }

    @objc func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard self.manager === manager, !self.isCancelled.with({ $0 }), self.subscriber != nil else {
            return
        }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if !self.requestedLocation {
                self.requestedLocation = true
                if #available(macOS 10.14, *) {
                    manager.requestLocation()
                } else {
                    manager.startUpdatingLocation()
                }
            }
        case .denied:
            self.fail(.denied)
        case .restricted:
            self.fail(.restricted)
        case .notDetermined:
            if !self.requestedAuthorization {
                self.requestedAuthorization = true
                if #available(macOS 10.15, *) {
                    manager.requestWhenInUseAuthorization()
                } else if !self.requestedLocation {
                    self.requestedLocation = true
                    manager.startUpdatingLocation()
                }
            }
        @unknown default:
            self.fail(.denied)
        }
    }

    @available(macOS 11.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.locationManager(manager, didChangeAuthorization: manager.authorizationStatus)
    }

    @objc func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard self.manager === manager else {
            return
        }
        if let error = error as? CLError, error.code == .denied {
            self.fail(.denied)
        } else {
            self.fail(.wifiRequired)
        }
    }

    @objc func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard self.manager === manager, !self.isCancelled.with({ $0 }), let subscriber = self.subscriber else {
            return
        }
        guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy.isFinite && CLLocationCoordinate2DIsValid($0.coordinate) }) else {
            self.fail(.wifiRequired)
            return
        }
        self.stop()
        subscriber.putNext(.success(location))
        subscriber.putCompletion()
    }
}

public func requestUserLocation() -> Signal<UserLocationResult, UserLocationError> {
    return Signal { subscriber in
        let request = UserLocationRequest(subscriber: subscriber)
        Queue.mainQueue().async {
            request.start()
        }
        return ActionDisposable {
            request.cancel()
        }
    }
}
