import AppKit

open class BaseTextView: NSTextView {
    @objc open var allowsWritingToolsAffordance: Bool {
        return false
    }
}
