import Foundation
import Cocoa

public func inputTextViewSize(_ inputView: UITextView, width: CGFloat) -> (NSSize, CGFloat) {
    let w = width
    let height = inputView.height(for: w)
    return (NSMakeSize(w, min(max(height, inputView.min_height), inputView.max_height)), height)
}
