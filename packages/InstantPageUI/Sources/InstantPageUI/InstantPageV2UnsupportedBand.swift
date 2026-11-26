import Cocoa

public protocol InstantPageV2UnsupportedBandLayout: AnyObject {
    var size: NSSize { get }
    func measure(width: CGFloat)
    func pillRect(in rect: CGRect) -> CGRect
    func cleanTearRect(in rect: CGRect) -> CGRect
    func draw(in ctx: CGContext, rect: CGRect)
}

public protocol InstantPageV2UnsupportedBandStyle {
    func makeBandLayout(title: String, subtitle: String, action: String) -> any InstantPageV2UnsupportedBandLayout
}
