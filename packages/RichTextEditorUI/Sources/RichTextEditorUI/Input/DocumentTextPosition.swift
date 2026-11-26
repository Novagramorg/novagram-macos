#if canImport(AppKit)
import Foundation

/// Plain Int-offset position (was a UITextPosition subclass). Kept as a thin box so existing
/// call sites `DocumentTextPosition(x)` / `.offset` continue to work.
@available(macOS 12, *)
final class DocumentTextPosition: NSObject {
    let offset: Int
    init(_ offset: Int) { self.offset = offset }
}

/// Plain offset range (was a UITextRange subclass). `start`/`end`/`isEmpty` are plain computed
/// properties now (no `override`).
@available(macOS 12, *)
final class DocumentTextRange: NSObject {
    let from: DocumentTextPosition
    let to: DocumentTextPosition
    init(_ from: DocumentTextPosition, _ to: DocumentTextPosition) { self.from = from; self.to = to }
    var start: DocumentTextPosition { from.offset <= to.offset ? from : to }
    var end: DocumentTextPosition { from.offset <= to.offset ? to : from }
    var isEmpty: Bool { from.offset == to.offset }
}
#endif
