import Foundation

final class PreviewSenderAttachmentEdits {
    private var attachments: [URL: UUID] = [:]
    private var current: UUID?
    private var isClosed = false

    func update(_ urls: [URL]) {
        guard !isClosed else { return }
        var updated: [URL: UUID] = [:]
        for url in urls {
            updated[url] = attachments[url] ?? updated[url] ?? UUID()
        }
        attachments = updated
    }

    func begin(for url: URL, urls: [URL]) -> PreviewSenderAttachmentEdit? {
        update(urls)
        guard !isClosed, let attachment = attachments[url] else { return nil }
        let current = UUID()
        self.current = current
        return PreviewSenderAttachmentEdit { [weak self] in
            guard let self, !self.isClosed else { return false }
            return self.current == current && self.attachments[url] == attachment
        }
    }

    func close() {
        isClosed = true
        current = nil
        attachments.removeAll()
    }
}

final class PreviewSenderAttachmentEdit {
    private enum Stage { case editing, committed, rendering, resolved }
    private var stage = Stage.editing
    private let isCurrent: () -> Bool

    init(isCurrent: @escaping () -> Bool) {
        self.isCurrent = isCurrent
    }

    var isActive: Bool {
        stage != .resolved && isCurrent()
    }

    func commit() -> Bool {
        guard stage == .editing, isCurrent() else { return false }
        stage = .committed
        return true
    }

    func startRendering() -> Bool {
        if stage == .editing {
            stage = .resolved
            return false
        }
        guard stage == .committed, isCurrent() else { return false }
        stage = .rendering
        return true
    }

    func apply() -> Bool {
        guard (stage == .editing || stage == .rendering), isCurrent() else { return false }
        stage = .resolved
        return true
    }

    func cancel() -> Bool {
        guard stage == .editing, isCurrent() else { return false }
        stage = .resolved
        return true
    }

    func discard() {
        stage = .resolved
    }
}
