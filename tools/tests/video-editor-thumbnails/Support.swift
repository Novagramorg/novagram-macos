import Cocoa
import XCTest
extension CGSize { func multipliedByScreenScale() -> CGSize { CGSize(width: width * 2, height: height * 2) } }
final class DrawingContext {
    let context: CGContext
    let bytesPerRow: Int
    var bytes: UnsafeMutableRawPointer { context.data! }
    init(size: CGSize, scale: CGFloat) {
        bytesPerRow = Int(size.width) * 4
        context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    }
    func withFlippedContext(_ draw: (CGContext) -> Void) { context.saveGState(); context.translateBy(x: 0, y: CGFloat(context.height)); context.scaleBy(x: 1, y: -1); draw(context); context.restoreGState() }
    func generateImage() -> CGImage? { context.makeImage() }
}
func testImage(_ width: Int = 80, height: Int = 40) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    return context.makeImage()!
}
let baseline = ProcessInfo.processInfo.environment["THUMB_BASELINE"] == "1"
