import CoreLocation
import Foundation
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TelegramUtils
import Postbox
import InputDataUI
import AlertsUI
import Localization
import TGUIKit

final class BrowserLocationAction {
    private final class Request {
        private enum Phase {
            case permissions
            case prompt
            case saving
            case location
            case validating
            case finished
        }

        private let context: any AccountContextProtocol
        private let bot: Peer
        private weak var window: Window?
        private let canPresent: () -> Bool
        private let completion: ([String: Any], UserLocationRequestResult?) -> Void
        private let finished: (Request) -> Void
        private let disposable = MetaDisposable()
        private var phase = Phase.permissions
        private var cancelled = false

        init(context: any AccountContextProtocol, bot: Peer, window: Window, canPresent: @escaping () -> Bool, completion: @escaping ([String: Any], UserLocationRequestResult?) -> Void, finished: @escaping (Request) -> Void) {
            self.context = context
            self.bot = bot
            self.window = window
            self.canPresent = canPresent
            self.completion = completion
            self.finished = finished
        }

        func cancel() {
            self.cancelled = true
            self.phase = .finished
            self.disposable.dispose()
        }

        private func isCurrent(_ phase: Phase) -> Bool {
            guard self.phase == phase else {
                return false
            }
            guard self.canPresent(), self.window != nil else {
                self.cancel()
                self.finished(self)
                return false
            }
            return true
        }

        private func finish(_ data: [String: Any], error: UserLocationRequestResult? = nil) {
            guard self.phase != .finished else {
                return
            }
            self.phase = .finished
            self.disposable.dispose()
            self.finished(self)
            if !self.cancelled, self.canPresent(), self.window != nil {
                self.completion(data, error)
            }
        }

        func start() {
            guard self.isCurrent(.permissions) else {
                return
            }
            let pending = MetaDisposable()
            self.disposable.set(pending)
            var received = false
            pending.set((webAppPermissionsState(context: self.context, peerId: self.bot.id)
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak self] state in
                received = true
                guard let self, self.isCurrent(.permissions) else {
                    return
                }
                if let permission = state?.location, permission.isRequested {
                    if permission.isAllowed {
                        self.locate()
                    } else {
                        self.finish(["available": false])
                    }
                } else {
                    self.askPermission()
                }
            }, completed: { [weak self] in
                guard !received, let self, self.isCurrent(.permissions) else {
                    return
                }
                self.finish(["available": false])
            }))
        }

        private func askPermission() {
            guard let window = self.window else {
                self.finish(["available": false])
                return
            }
            self.phase = .prompt
            verifyAlert(for: window, information: strings().webAppLocationPermissionText(self.bot.displayTitle, self.bot.displayTitle), ok: strings().webAppLocationPermissionAllow, cancel: strings().webAppLocationPermissionDecline, successHandler: { [weak self] _ in
                self?.savePermission(true)
            }, cancelHandler: { [weak self] in
                self?.savePermission(false)
            })
        }

        private func savePermission(_ allowed: Bool) {
            guard self.isCurrent(.prompt) else {
                return
            }
            self.phase = .saving
            let pending = MetaDisposable()
            self.disposable.set(pending)
            guard self.isCurrent(.saving) else {
                return
            }
            pending.set((updateWebAppPermissionsStateInteractively(context: self.context, peerId: self.bot.id) { current in
                WebAppPermissionsState(location: .init(isRequested: true, isAllowed: allowed), emojiStatus: current?.emojiStatus)
            } |> deliverOnMainQueue).start(completed: { [weak self] in
                guard let self, self.isCurrent(.saving) else {
                    return
                }
                if allowed {
                    if let window = self.window {
                        showModalText(for: window, text: strings().webAppLocationPermissionSucceed(self.bot.displayTitle))
                    }
                    guard self.isCurrent(.saving) else {
                        return
                    }
                    self.locate()
                } else {
                    self.finish(["available": false])
                }
            }))
        }

        private func locate() {
            self.phase = .location
            let pending = MetaDisposable()
            self.disposable.set(pending)
            var received = false
            guard self.isCurrent(.location) else {
                return
            }
            let signal = FeatureNavigationHooks.shared.requestUserLocation() |> take(1) |> deliverOnMainQueue
            guard self.isCurrent(.location) else {
                return
            }
            pending.set(signal.start(next: { [weak self] result in
                received = true
                guard let self, self.isCurrent(.location) else {
                    return
                }
                switch result {
                case let .success(location):
                    self.validatePermission(location)
                default:
                    self.finish(["available": false], error: result)
                }
            }, completed: { [weak self] in
                guard !received, let self, self.isCurrent(.location) else {
                    return
                }
                self.finish(["available": false])
            }))
        }

        private func validatePermission(_ location: CLLocation) {
            self.phase = .validating
            let pending = MetaDisposable()
            self.disposable.set(pending)
            guard self.isCurrent(.validating) else {
                return
            }
            var received = false
            pending.set((webAppPermissionsState(context: self.context, peerId: self.bot.id)
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak self] state in
                received = true
                guard let self, self.isCurrent(.validating) else {
                    return
                }
                if let permission = state?.location, permission.isRequested && permission.isAllowed {
                    self.finish(BrowserLocationAction.locationData(location))
                } else {
                    self.finish(["available": false])
                }
            }, completed: { [weak self] in
                guard !received, let self, self.isCurrent(.validating) else {
                    return
                }
                self.finish(["available": false])
            }))
        }

        deinit {
            self.disposable.dispose()
        }
    }

    private var request: Request?
    private var checkDisposable = MetaDisposable()
    private var checkId: UUID?

    func reset() {
        let request = self.request
        self.request = nil
        self.checkId = nil
        let checkDisposable = self.checkDisposable
        self.checkDisposable = MetaDisposable()
        request?.cancel()
        checkDisposable.dispose()
    }

    func check(context: any AccountContextProtocol, botId: PeerId, canPresent: @escaping () -> Bool, completion: @escaping ([String: Any]) -> Void) {
        let id = UUID()
        self.checkId = id
        let pending = MetaDisposable()
        self.checkDisposable.set(pending)
        guard self.checkId == id, canPresent() else {
            return
        }
        pending.set((webAppPermissionsState(context: context, peerId: botId)
        |> then(.single(nil))
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self, self.checkId == id, canPresent() else {
                return
            }
            self.checkId = nil
            var data: [String: Any] = ["available": true, "access_requested": state?.location?.isRequested ?? false]
            if let permission = state?.location, permission.isRequested {
                data["access_granted"] = permission.isAllowed
            }
            completion(data)
        }))
    }

    func open(context: any AccountContextProtocol, bot: Peer, window: Window, canPresent: @escaping () -> Bool, completion: @escaping ([String: Any], UserLocationRequestResult?) -> Void) {
        guard self.request == nil, canPresent() else {
            return
        }
        let request = Request(context: context, bot: bot, window: window, canPresent: canPresent, completion: completion, finished: { [weak self] request in
            if self?.request === request {
                self?.request = nil
            }
        })
        self.request = request
        request.start()
    }

    static func locationData(_ location: CLLocation) -> [String: Any] {
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0 else {
            return ["available": false]
        }
        func nonnegative(_ value: Double) -> Any {
            return value.isFinite && value >= 0 ? value as Any : NSNull()
        }
        var data: [String: Any] = [
            "available": true,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.verticalAccuracy.isFinite && location.verticalAccuracy >= 0 && location.altitude.isFinite ? location.altitude as Any : NSNull(),
            "course": location.course < 360 ? nonnegative(location.course) : NSNull(),
            "speed": nonnegative(location.speed),
            "horizontal_accuracy": nonnegative(location.horizontalAccuracy),
            "vertical_accuracy": nonnegative(location.verticalAccuracy)
        ]
        if #available(macOS 10.15.4, *) {
            data["course_accuracy"] = location.course >= 0 && location.course < 360 ? nonnegative(location.courseAccuracy) : NSNull()
        } else {
            data["course_accuracy"] = NSNull()
        }
        if #available(macOS 10.15, *) {
            data["speed_accuracy"] = location.speed.isFinite && location.speed >= 0 ? nonnegative(location.speedAccuracy) : NSNull()
        } else {
            data["speed_accuracy"] = NSNull()
        }
        return data
    }

    deinit {
        self.request?.cancel()
        self.checkDisposable.dispose()
    }
}
