import Cocoa

/// Marker for views that consume horizontal scroll/swipe gestures locally so
/// global window-level swipe handlers (navigation back, chat reply-swipe) must
/// bail when the cursor is over a region the view is actively scrolling.
public protocol HorizontalScrollConsuming: AnyObject {
    func consumesHorizontalScroll(atWindowPoint windowPoint: NSPoint) -> Bool
}

public extension NSView {
    /// Walks self and its superview chain looking for the nearest
    /// `HorizontalScrollConsuming` that claims `windowPoint` (in window coords).
    func enclosingHorizontalScrollConsumer(atWindowPoint windowPoint: NSPoint) -> HorizontalScrollConsuming? {
        var view: NSView? = self
        while let v = view {
            if let consumer = v as? HorizontalScrollConsuming,
               consumer.consumesHorizontalScroll(atWindowPoint: windowPoint) {
                return consumer
            }
            view = v.superview
        }
        return nil
    }
}

//
