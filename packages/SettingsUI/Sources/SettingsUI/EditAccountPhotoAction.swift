import Foundation
import SwiftSignalKit

final class EditAccountPhotoAction: Disposable {
    private let disposable = MetaDisposable()
    private var operationId: UUID?
    private var isDisposed = false

    func start(_ start: (@escaping () -> Bool) -> Disposable) {
        guard !self.isDisposed else { return }
        let operationId = UUID()
        self.operationId = operationId
        let pending = MetaDisposable()
        self.disposable.set(pending)
        let isCurrent: () -> Bool = { [weak self] in
            guard let self else { return false }
            return !self.isDisposed && self.operationId == operationId
        }
        guard isCurrent() else { return }
        pending.set(start(isCurrent))
    }

    @discardableResult
    func cancel() -> Bool {
        self.operationId = nil
        self.disposable.set(nil)
        return self.operationId == nil
    }

    func dispose() {
        self.isDisposed = true
        self.cancel()
    }

    deinit {
        self.disposable.dispose()
    }
}
