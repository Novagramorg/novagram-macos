import Foundation
import SwiftSignalKit
import TGUIKit
import TelegramCore

final class ChatBirthdaySaveAction {
    private let disposable = MetaDisposable()
    private var operationId: UUID?
    private var cancelled: (() -> Void)?
    private(set) var isActive = true
    var isPending: Bool { self.operationId != nil }

    func setActive(_ active: Bool) {
        self.isActive = active
        if !active {
            self.reset()
        }
    }

    func reset() {
        self.operationId = nil
        let cancelled = self.cancelled
        self.cancelled = nil
        self.disposable.set(nil)
        cancelled?()
    }

    func perform(signal: Signal<Never, UpdateBirthdayError>, window: Window, canPresent: @escaping () -> Bool, started: () -> Void = {}, cancelled: @escaping () -> Void = {}, failed: @escaping (UpdateBirthdayError) -> Void, completed: @escaping () -> Void) {
        guard self.isActive, !self.isPending, canPresent(), self.isActive, !self.isPending else { return }
        let operationId = UUID()
        self.operationId = operationId
        self.cancelled = cancelled
        let pending = MetaDisposable()
        self.disposable.set(pending)
        started()
        guard self.isActive, self.operationId == operationId else { return }
        let finish: (UpdateBirthdayError?) -> Void = { [weak self] error in
            guard let self, self.isActive, self.operationId == operationId else { return }
            defer {
                if self.operationId == operationId {
                    self.operationId = nil
                    self.cancelled = nil
                }
            }
            self.disposable.set(nil)
            guard self.isActive, self.operationId == operationId else { return }
            guard canPresent(), self.isActive, self.operationId == operationId else {
                if self.operationId == operationId { self.reset() }
                return
            }
            self.cancelled = nil
            if let error { failed(error) } else { completed() }
        }
        pending.set(showModalProgress(signal: signal |> deliverOnMainQueue |> afterDisposed { [weak self] in
            Queue.mainQueue().justDispatch { [weak self] in
                guard let self, self.operationId == operationId else { return }
                self.reset()
            }
        }, for: window, shouldPresent: canPresent).start(error: { finish($0) }, completed: { finish(nil) }))
    }

    deinit {
        self.disposable.dispose()
    }
}
