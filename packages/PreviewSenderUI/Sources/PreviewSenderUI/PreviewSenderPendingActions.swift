import Foundation

final class PreviewSenderPendingActions {
    final class Token {
        private let validate: () -> Bool
        private var consumed = false

        fileprivate init(validate: @escaping () -> Bool) {
            self.validate = validate
        }

        var isCurrent: Bool {
            !consumed && validate()
        }

        func take() -> Bool {
            guard !consumed else { return false }
            consumed = true
            return validate()
        }
    }

    private var revision = UUID()
    private(set) var isClosed = false

    func invalidate() {
        revision = UUID()
    }

    func close() {
        isClosed = true
        invalidate()
    }

    func capture() -> () -> Bool {
        let token = captureToken()
        return { token.take() }
    }

    func captureToken() -> Token {
        invalidate()
        let revision = self.revision
        return Token { [weak self] in
            guard let self, !self.isClosed else { return false }
            return self.revision == revision
        }
    }
}
