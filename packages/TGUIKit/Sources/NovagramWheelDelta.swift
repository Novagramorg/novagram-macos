import Cocoa

extension HorizontalScrollView {
    func novagramWheelDeltaY(_ event: NSEvent) -> CGFloat {
        return event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * horizontalLineScroll
    }
}
