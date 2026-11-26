import AppKit
import XCTest

struct Pixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8, _ alpha: UInt8 = 255) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    static let clear = Pixel(0, 0, 0, 0)
    static let black = Pixel(0, 0, 0)
    static let white = Pixel(255, 255, 255)
}

enum PixelFormat: CaseIterable {
    case rgba, argb, bgra, abgr, straightRGBA, straightARGB, straightBGRA, straightABGR
    var alpha: CGImageAlphaInfo {
        switch self {
        case .rgba, .abgr: return .premultipliedLast
        case .argb, .bgra: return .premultipliedFirst
        case .straightRGBA, .straightABGR: return .last
        case .straightARGB, .straightBGRA: return .first
        }
    }
    var order: CGBitmapInfo {
        switch self {
        case .bgra, .abgr, .straightBGRA, .straightABGR: return .byteOrder32Little
        default: return .byteOrder32Big
        }
    }
    var premultiplied: Bool { alpha == .premultipliedFirst || alpha == .premultipliedLast }
    func bytes(_ pixel: Pixel) -> [UInt8] {
        let r = premultiplied ? UInt8(Int(pixel.red) * Int(pixel.alpha) / 255) : pixel.red
        let g = premultiplied ? UInt8(Int(pixel.green) * Int(pixel.alpha) / 255) : pixel.green
        let b = premultiplied ? UInt8(Int(pixel.blue) * Int(pixel.alpha) / 255) : pixel.blue
        switch self {
        case .rgba, .straightRGBA: return [r, g, b, pixel.alpha]
        case .argb, .straightARGB: return [pixel.alpha, r, g, b]
        case .bgra, .straightBGRA: return [b, g, r, pixel.alpha]
        case .abgr, .straightABGR: return [pixel.alpha, b, g, r]
        }
    }
}

func fixture(width: Int, height: Int, format: PixelFormat = .bgra, padded: Bool = true, space: CGColorSpace = CGColorSpaceCreateDeviceRGB(), pixel: (Int, Int) -> Pixel) throws -> CGImage {
    let rowBytes = width * 4 + (padded ? 28 : 0)
    var data = Data(repeating: 73, count: rowBytes * height)
    for y in 0..<height {
        for x in 0..<width {
            data.replaceSubrange((y * rowBytes + x * 4)..<(y * rowBytes + x * 4 + 4), with: format.bytes(pixel(x, y)))
        }
    }
    let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
    return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: space, bitmapInfo: CGBitmapInfo(rawValue: format.order.rawValue | format.alpha.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
}
