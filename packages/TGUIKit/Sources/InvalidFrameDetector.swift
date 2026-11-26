import AppKit
import ObjectiveC

#if DEBUG

private let maxAllowedExtent: CGFloat = 1_000_000
private var didInstallInvalidFrameDetector = false

private func isInvalid(_ x: CGFloat) -> Bool {
    return !x.isFinite || abs(x) > maxAllowedExtent
}

private func report(_ label: String, view: NSView, value: Any) {
    print("⚠️ Invalid \(label) on \(type(of: view)): \(value)")
    print(Thread.callStackSymbols.prefix(20).joined(separator: "\n"))
    //assertionFailure("Invalid \(label): \(value)")
}

@objc extension NSView {
    @objc dynamic func tg_swizzled_setFrame(_ frame: NSRect) {
        if isInvalid(frame.origin.x) || isInvalid(frame.origin.y) || isInvalid(frame.size.width) || isInvalid(frame.size.height) {
            report("frame", view: self, value: frame)
        }
        let sanitized = NSRect(
            x: frame.origin.x.isFinite ? frame.origin.x : 0,
            y: frame.origin.y.isFinite ? frame.origin.y : 0,
            width: max(0, frame.size.width.isFinite ? frame.size.width : 0),
            height: max(0, frame.size.height.isFinite ? frame.size.height : 0)
        )
        self.tg_swizzled_setFrame(sanitized)
    }

    @objc dynamic func tg_swizzled_setFrameSize(_ size: NSSize) {
        if isInvalid(size.width) || isInvalid(size.height) {
            report("frame size", view: self, value: size)
        }
        let sanitized = NSSize(
            width: max(0, size.width.isFinite ? size.width : 0),
            height: max(0, size.height.isFinite ? size.height : 0)
        )
        self.tg_swizzled_setFrameSize(sanitized)
    }

    @objc dynamic func tg_swizzled_setFrameOrigin(_ origin: NSPoint) {
        if isInvalid(origin.x) || isInvalid(origin.y) {
            report("frame origin", view: self, value: origin)
        }
        let sanitized = NSPoint(
            x: origin.x.isFinite ? origin.x : 0,
            y: origin.y.isFinite ? origin.y : 0
        )
        self.tg_swizzled_setFrameOrigin(sanitized)
    }
}

private func swizzle(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
    guard let originalMethod = class_getInstanceMethod(cls, original),
          let replacementMethod = class_getInstanceMethod(cls, replacement) else {
        return
    }
    method_exchangeImplementations(originalMethod, replacementMethod)
}

public func installInvalidFrameDetector() {
    guard !didInstallInvalidFrameDetector else { return }
    didInstallInvalidFrameDetector = true

    swizzle(NSView.self, #selector(setter: NSView.frame), #selector(NSView.tg_swizzled_setFrame(_:)))
    swizzle(NSView.self, #selector(NSView.setFrameSize(_:)), #selector(NSView.tg_swizzled_setFrameSize(_:)))
    swizzle(NSView.self, #selector(NSView.setFrameOrigin(_:)), #selector(NSView.tg_swizzled_setFrameOrigin(_:)))
}

#else

public func installInvalidFrameDetector() {
    // no-op in release builds
}

#endif
