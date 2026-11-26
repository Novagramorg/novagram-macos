import Foundation
import SwiftSignalKit

final class EditAccountAvatarAcquisition: Disposable {
    private final class Selection<Value> {
        let canPresent: () -> Bool
        let selected: (Value) -> Void

        init(canPresent: @escaping () -> Bool, selected: @escaping (Value) -> Void) {
            self.canPresent = canPresent
            self.selected = selected
        }
    }

    private var selection: AnyObject?
    private var operationId: UUID?
    private var presentationId = UUID()
    private var isActive = true
    private var isDisposed = false

    func setActive(_ active: Bool) {
        self.isActive = active
        if !active {
            self.presentationId = UUID()
            self.reset()
        }
    }

    func presentationCheck(_ predicate: @escaping () -> Bool) -> () -> Bool {
        let presentationId = self.presentationId
        return { [weak self] in
            guard let self, self.isActive, !self.isDisposed, self.presentationId == presentationId else { return false }
            return predicate() && self.isActive && !self.isDisposed && self.presentationId == presentationId
        }
    }

    private func reset() {
        self.operationId = nil
        self.selection = nil
    }

    func start<Value>(canPresent: @escaping () -> Bool, selected: @escaping (Value) -> Void) -> ((Value) -> Void)? {
        guard self.isActive, !self.isDisposed else { return nil }
        let operationId = UUID()
        self.operationId = operationId
        self.selection = nil
        guard self.isActive, !self.isDisposed, self.operationId == operationId else { return nil }
        guard canPresent(), self.isActive, !self.isDisposed, self.operationId == operationId else {
            if self.operationId == operationId { self.reset() }
            return nil
        }
        self.selection = Selection(canPresent: canPresent, selected: selected)
        return { [weak self] value in
            guard let self, self.isActive, !self.isDisposed, self.operationId == operationId, let selection = self.selection as? Selection<Value> else { return }
            let canPresent = selection.canPresent()
            guard self.isActive, !self.isDisposed, self.operationId == operationId else { return }
            self.reset()
            if canPresent {
                selection.selected(value)
            }
        }
    }

    func dispose() {
        self.isDisposed = true
        self.reset()
    }
}
