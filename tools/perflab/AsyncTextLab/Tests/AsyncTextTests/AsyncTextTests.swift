import Cocoa
import XCTest
@testable import TGUIKit
import AsyncTextHarness

private func threadCPU() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
    return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
}

private func processCPU() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6 + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
}

private var retainedImages: [NSImage] = []

final class AsyncTextTests: XCTestCase {
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.liquidGlass = false
        if retainedImages.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
                let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    NSColor.black.setFill()
                    rect.insetBy(dx: 4, dy: 4).fill()
                    return true
                }
                _ = image.setName(name)
                retainedImages.append(image)
            }
        }
    }

    private func render(_ window: AsyncTextWindow, async: Bool, count: Int, paragraphs: Int, wait: Double) -> [UInt8]? {
        let scale = window.window.backingScaleFactor
        System.updateScaleFactor(scale)
        let scene = AsyncTextScene(in: window.host, count: count, width: 600, paragraphs: paragraphs, async: async, scale: scale)
        CATransaction.flush()
        spinRunLoop(wait)
        let image = window.capture().map(rgba)
        scene.remove()
        CATransaction.flush()
        spinRunLoop(0.1)
        return image
    }

    func testAsyncDrawingIsNotPixelIdentical() throws {
        let spaces: [(String, NSColorSpace?)] = [("default", nil), ("sRGB", .sRGB), ("displayP3", .displayP3)]
        for (name, space) in spaces {
            let window = AsyncTextWindow(size: NSSize(width: 620, height: 900), colorSpace: space)
            defer { window.close() }
            spinRunLoop(0.3)
            let a = try XCTUnwrap(render(window, async: false, count: 6, paragraphs: 4, wait: 0.4))
            let b = try XCTUnwrap(render(window, async: true, count: 6, paragraphs: 4, wait: 0.4))
            let c = try XCTUnwrap(render(window, async: false, count: 6, paragraphs: 4, wait: 0.4))
            XCTAssertEqual(a, c, "sync path unstable in \(name)")
            XCTAssertTrue(a.contains { $0 < 200 }, "no text drawn in \(name)")
            let diff = zip(a, b).reduce(into: (0, 0)) { r, p in if p.0 != p.1 { r.0 += 1; r.1 = max(r.1, abs(Int(p.0) - Int(p.1))) } }
            print("ASYNC_PARITY space=\(name) bytes=\(a.count) differentBytes=\(diff.0) maxDelta=\(diff.1)")
            XCTAssertGreaterThan(diff.0, 0, "drawsAsynchronously became pixel-identical in \(name); revisit the parked async path")
        }
    }

    func testManualRasterMatchesSync() throws {
        guard ProcessInfo.processInfo.environment["ASYNC_TEXT_EXPLORE"] == "1" else { throw XCTSkip("exploratory, set ASYNC_TEXT_EXPLORE=1") }
        let spaces: [(String, NSColorSpace?)] = [("default", nil), ("sRGB", .sRGB), ("displayP3", .displayP3)]
        for (name, space) in spaces {
            let window = AsyncTextWindow(size: NSSize(width: 620, height: 900), colorSpace: space)
            defer { window.close() }
            spinRunLoop(0.3)
            let scale = window.window.backingScaleFactor
            let reference = try XCTUnwrap(render(window, async: false, count: 6, paragraphs: 4, wait: 0.4))
            let candidates: [(String, CGColorSpace?)] = [
                ("window", window.window.colorSpace?.cgColorSpace),
                ("screen", window.window.screen?.colorSpace?.cgColorSpace),
                ("sRGB", CGColorSpace(name: CGColorSpace.sRGB)),
                ("deviceRGB", CGColorSpaceCreateDeviceRGB()),
            ]
            for (csName, cs) in candidates {
                guard let cs else { continue }
                for flipped in [nil, true, false] as [Bool?] {
                    let scene = ManualTextScene(in: window.host, count: 6, width: 600, paragraphs: 4, scale: scale, colorSpace: cs, flipped: flipped, queue: DispatchQueue.global(qos: .userInitiated))
                    CATransaction.flush()
                    spinRunLoop(0.4)
                    let shot = try XCTUnwrap(window.capture().map(rgba))
                    scene.remove()
                    CATransaction.flush()
                    spinRunLoop(0.1)
                    let diff = zip(reference, shot).reduce(into: (0, 0)) { r, p in if p.0 != p.1 { r.0 += 1; r.1 = max(r.1, abs(Int(p.0) - Int(p.1))) } }
                    print("MANUAL_PARITY window=\(name) context=\(csName) flipped=\(flipped.map { "\($0)" } ?? "auto") differentBytes=\(diff.0) maxDelta=\(diff.1)")
                }
            }
        }
    }

    func testOwnRasterStaysWithinMeasuredGap() throws {
        for align in [false, true] {
        AsyncTextFixtures.alignFrames = align
        defer { AsyncTextFixtures.alignFrames = false }
        for (name, space) in [("default", nil), ("sRGB", NSColorSpace.sRGB), ("displayP3", NSColorSpace.displayP3)] as [(String, NSColorSpace?)] {
            let window = AsyncTextWindow(size: NSSize(width: 620, height: 900), colorSpace: space)
            defer { window.close() }
            spinRunLoop(0.3)
            let scale = window.window.backingScaleFactor
            for paragraphs in [1, 4] {
                let reference = try XCTUnwrap(render(window, async: false, count: 6, paragraphs: paragraphs, wait: 0.4))
                let again = try XCTUnwrap(render(window, async: false, count: 6, paragraphs: paragraphs, wait: 0.4))
                print("RULE_STABLE align=\(align) window=\(name) paragraphs=\(paragraphs) nativeRepeatDifferentBytes=\(zip(reference, again).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) })")
                let cs = try XCTUnwrap(ManualTextRaster.colorSpace(for: window.window))
                let rule = ManualTextRaster.format(for: window.window)
                for (format, gravity) in [(rule, CALayerContentsGravity.resize), (rule, .topLeft), (rule, .bottomLeft), (rule == .bgra8 ? .rgba16 : .bgra8, .bottomLeft)] {
                    let scene = ManualTextScene(in: window.host, count: 6, width: 600, paragraphs: paragraphs, scale: scale, colorSpace: cs, flipped: nil, queue: DispatchQueue.global(qos: .userInitiated), format: format, gravity: gravity)
                    CATransaction.flush()
                    spinRunLoop(0.4)
                    let shot = try XCTUnwrap(window.capture().map(rgba))
                    scene.remove()
                    CATransaction.flush()
                    spinRunLoop(0.1)
                    let diff = zip(reference, shot).reduce(into: (0, 0)) { r, p in if p.0 != p.1 { r.0 += 1; r.1 = max(r.1, abs(Int(p.0) - Int(p.1))) } }
                    let different = diff.0
                    print("RULE_PARITY align=\(align) window=\(name) paragraphs=\(paragraphs) format=\(format.rawValue) gravity=\(gravity.rawValue) rule=\(format == rule) differentBytes=\(different) maxDelta=\(diff.1)")
                    if gravity != .bottomLeft { continue }
                    if format == rule {
                        XCTAssertLessThanOrEqual(diff.1, rule == .rgba16 ? 3 : 2, "own raster beyond the measured glyph-compositing gap in \(name)")
                    } else {
                        XCTAssertGreaterThan(different, 0, "wrong format is indistinguishable in \(name)")
                    }
                }
            }
        }
        }
    }

    func testManualRasterFormats() throws {
        guard ProcessInfo.processInfo.environment["ASYNC_TEXT_EXPLORE"] == "1" else { throw XCTSkip("exploratory, set ASYNC_TEXT_EXPLORE=1") }
        let paragraphs = Int(ProcessInfo.processInfo.environment["FORMAT_PARAGRAPHS"] ?? "4") ?? 4
        AsyncTextFixtures.extraHeight = CGFloat(Double(ProcessInfo.processInfo.environment["FORMAT_EXTRA"] ?? "0") ?? 0)
        defer { AsyncTextFixtures.extraHeight = 0 }
        if let hex = ProcessInfo.processInfo.environment["FORMAT_COLOR"], let v = UInt32(hex, radix: 16) {
            AsyncTextFixtures.forcedColor = NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        }
        defer { AsyncTextFixtures.forcedColor = nil }
        for (name, space) in [("default", nil), ("sRGB", NSColorSpace.sRGB)] as [(String, NSColorSpace?)] {
            let window = AsyncTextWindow(size: NSSize(width: 620, height: 900), colorSpace: space)
            defer { window.close() }
            spinRunLoop(0.3)
            let scale = window.window.backingScaleFactor
            let reference = try XCTUnwrap(render(window, async: false, count: 6, paragraphs: paragraphs, wait: 0.4))
            let candidates: [(String, CGColorSpace?)] = [
                ("window", window.window.colorSpace?.cgColorSpace),
                ("extendedSRGB", CGColorSpace(name: CGColorSpace.extendedSRGB)),
                ("extendedLinearSRGB", CGColorSpace(name: CGColorSpace.extendedLinearSRGB)),
                ("displayP3", CGColorSpace(name: CGColorSpace.displayP3)),
                ("extendedDisplayP3", CGColorSpace(name: CGColorSpace.extendedDisplayP3)),
                ("sRGB", CGColorSpace(name: CGColorSpace.sRGB)),
            ]
            for (csName, cs) in candidates {
                guard let cs else { continue }
                for format in ManualTextRaster.Format.allCases {
                    let scene = ManualTextScene(in: window.host, count: 6, width: 600, paragraphs: paragraphs, scale: scale, colorSpace: cs, flipped: nil, queue: DispatchQueue.global(qos: .userInitiated), format: format)
                    CATransaction.flush()
                    spinRunLoop(0.4)
                    let shot = try XCTUnwrap(window.capture().map(rgba))
                    scene.remove()
                    CATransaction.flush()
                    spinRunLoop(0.1)
                    let diff = zip(reference, shot).reduce(into: (0, 0)) { r, p in if p.0 != p.1 { r.0 += 1; r.1 = max(r.1, abs(Int(p.0) - Int(p.1))) } }
                    print("FORMAT_PARITY window=\(name) context=\(csName) format=\(format.rawValue) differentBytes=\(diff.0) maxDelta=\(diff.1)")
                }
            }
        }
    }

    func testBackgroundDisplayParity() throws {
        let colors: [String?] = [nil, "0d0d12", "1a66e6", "808080"]
        for color in colors {
            if let hex = color, let v = UInt32(hex, radix: 16) {
                AsyncTextFixtures.forcedColor = NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
            } else {
                AsyncTextFixtures.forcedColor = nil
            }
            defer { AsyncTextFixtures.forcedColor = nil }
            for (name, space) in [("default", nil), ("sRGB", NSColorSpace.sRGB)] as [(String, NSColorSpace?)] {
                let window = AsyncTextWindow(size: NSSize(width: 620, height: 900), colorSpace: space)
                defer { window.close() }
                spinRunLoop(0.3)
                let scale = window.window.backingScaleFactor
                for paragraphs in [1, 4] {
                    let reference = try XCTUnwrap(render(window, async: false, count: 6, paragraphs: paragraphs, wait: 0.4))
                    let useRenderer = ProcessInfo.processInfo.environment["BG_RENDERER"] == "1"
                    for format in (useRenderer ? [CALayerContentsFormat(rawValue: "AutomaticAppKit")] : [nil, CALayerContentsFormat(rawValue: "AutomaticAppKit"), .RGBA8Uint, .RGBA16Float]) as [CALayerContentsFormat?] {
                        let scene = BackgroundDisplayScene(in: window.host, count: 6, width: 600, paragraphs: paragraphs, scale: scale, format: format, queue: DispatchQueue.global(qos: .userInitiated), colorSpace: useRenderer ? window.window.colorSpace?.cgColorSpace : nil)
                        CATransaction.flush()
                        spinRunLoop(0.4)
                        let shot = try XCTUnwrap(window.capture().map(rgba))
                        scene.remove()
                        CATransaction.flush()
                        spinRunLoop(0.1)
                        let diff = zip(reference, shot).reduce(into: (0, 0)) { r, p in if p.0 != p.1 { r.0 += 1; r.1 = max(r.1, abs(Int(p.0) - Int(p.1))) } }
                        print("BGDISPLAY color=\(color ?? "mixed") window=\(name) paragraphs=\(paragraphs) format=\(format?.rawValue ?? "default") contents=\(Set(scene.contentsTypes)) differentBytes=\(diff.0) maxDelta=\(diff.1)")
                        if !useRenderer, format?.rawValue == "AutomaticAppKit" {
                            if name == "sRGB" {
                                XCTAssertEqual(diff.0, 0, "detached CA display no longer exact in an sRGB window")
                            } else {
                                XCTAssertGreaterThan(diff.0, 0, "detached CA display became exact in a wide-gamut window; revisit the parked path")
                            }
                        }
                    }
                }
            }
        }
    }

    func testContextSettingsSweep() throws {
        guard ProcessInfo.processInfo.environment["ASYNC_TEXT_EXPLORE"] == "1" else { throw XCTSkip("exploratory, set ASYNC_TEXT_EXPLORE=1") }
        let hex = ProcessInfo.processInfo.environment["FORMAT_COLOR"] ?? "0d0d12"
        let v = UInt32(hex, radix: 16)!
        AsyncTextFixtures.forcedColor = NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
        defer { AsyncTextFixtures.forcedColor = nil; ManualTextRaster.prepare = nil }
        let settings: [(String, (CGContext) -> Void)] = [
            ("none", { _ in }),
            ("noQuant", { $0.setAllowsFontSubpixelQuantization(false); $0.setShouldSubpixelQuantizeFonts(false) }),
            ("quant", { $0.setAllowsFontSubpixelQuantization(true); $0.setShouldSubpixelQuantizeFonts(true) }),
            ("perceptual", { $0.setRenderingIntent(.perceptual) }),
            ("relative", { $0.setRenderingIntent(.relativeColorimetric) }),
            ("absolute", { $0.setRenderingIntent(.absoluteColorimetric) }),
            ("saturation", { $0.setRenderingIntent(.saturation) }),
            ("interpHigh", { $0.interpolationQuality = .high }),
            ("interpNone", { $0.interpolationQuality = .none }),
            ("flatness", { $0.setFlatness(0.1) }),
        ]
        for (name, space) in [("default", nil), ("sRGB", NSColorSpace.sRGB)] as [(String, NSColorSpace?)] {
            let window = AsyncTextWindow(size: NSSize(width: 620, height: 900), colorSpace: space)
            defer { window.close() }
            spinRunLoop(0.3)
            let scale = window.window.backingScaleFactor
            let reference = try XCTUnwrap(render(window, async: false, count: 6, paragraphs: 4, wait: 0.4))
            let cs = try XCTUnwrap(ManualTextRaster.colorSpace(for: window.window))
            for (settingName, setting) in settings {
                ManualTextRaster.prepare = setting
                let scene = ManualTextScene(in: window.host, count: 6, width: 600, paragraphs: 4, scale: scale, colorSpace: cs, flipped: nil, queue: DispatchQueue.global(qos: .userInitiated), format: ManualTextRaster.format(for: window.window))
                CATransaction.flush()
                spinRunLoop(0.4)
                let shot = try XCTUnwrap(window.capture().map(rgba))
                scene.remove()
                CATransaction.flush()
                spinRunLoop(0.1)
                let diff = zip(reference, shot).reduce(into: (0, 0)) { r, p in if p.0 != p.1 { r.0 += 1; r.1 = max(r.1, abs(Int(p.0) - Int(p.1))) } }
                print("SWEEP color=\(hex) window=\(name) setting=\(settingName) differentBytes=\(diff.0) maxDelta=\(diff.1)")
            }
        }
    }

    func testFillProbe() throws {
        for (name, space) in [("default", nil), ("sRGB", NSColorSpace.sRGB)] as [(String, NSColorSpace?)] {
            let window = AsyncTextWindow(size: NSSize(width: 140, height: 60), colorSpace: space)
            defer { window.close() }
            spinRunLoop(0.3)
            let scale = window.window.backingScaleFactor
            let native = FillProbeLayer()
            native.contentsScale = scale
            native.frame = CGRect(x: 0, y: 0, width: 110, height: 40)
            window.host.layer?.addSublayer(native)
            native.setNeedsDisplay()
            CATransaction.flush(); spinRunLoop(0.4)
            let a = try XCTUnwrap(window.capture().map(rgba))
            native.removeFromSuperlayer()
            let manual = SimpleLayer()
            manual.contentsScale = scale
            manual.frame = native.frame
            window.host.layer?.addSublayer(manual)
            let rule = ManualTextRaster.format(for: window.window)
            let cs = try XCTUnwrap(ManualTextRaster.colorSpace(for: window.window))
            let w = 220, h = 80
            let bpc = rule == .bgra8 ? 8 : 16
            let info: UInt32 = rule == .bgra8 ? CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: bpc, bytesPerRow: 0, space: cs, bitmapInfo: info))
            if manual.contentsAreFlipped() { ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1) }
            ctx.scaleBy(x: scale, y: scale)
            FillProbeLayer.draw(in: ctx)
            manual.contents = ctx.makeImage()
            CATransaction.flush(); spinRunLoop(0.4)
            let b = try XCTUnwrap(window.capture().map(rgba))
            manual.removeFromSuperlayer()
            let W = Int(window.window.frame.width * scale)
            for i in 0..<FillProbeLayer.colors.count {
                let cx = (i * 20 + 10) * Int(scale), cy1 = 10 * Int(scale), cy2 = 30 * Int(scale)
                func px(_ d: [UInt8], _ x: Int, _ y: Int) -> String { let o = (y * W + x) * 4; return "\(d[o]),\(d[o+1]),\(d[o+2])" }
                print("FILL window=\(name) color=\(i) solid native=\(px(a, cx, cy1)) manual=\(px(b, cx, cy1)) edge native=\(px(a, (i * 20 + 2) * Int(scale), cy2)) manual=\(px(b, (i * 20 + 2) * Int(scale), cy2))")
            }
            let fillDifferent = zip(a, b).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) }
            print("FILL window=\(name) differentBytes=\(fillDifferent)")
            XCTAssertEqual(fillDifferent, 0, "fills through the own raster differ in \(name)")
        }
    }

    func testProbeBackingContext() throws {
        guard ProcessInfo.processInfo.environment["ASYNC_TEXT_EXPLORE"] == "1" else { throw XCTSkip("exploratory, set ASYNC_TEXT_EXPLORE=1") }
        for (name, space) in [("default", nil), ("sRGB", NSColorSpace.sRGB), ("displayP3", NSColorSpace.displayP3)] as [(String, NSColorSpace?)] {
            let window = AsyncTextWindow(size: NSSize(width: 300, height: 200), colorSpace: space)
            defer { window.close() }
            spinRunLoop(0.2)
            let layer = ContextProbeLayer()
            layer.contentsScale = window.window.backingScaleFactor
            layer.frame = CGRect(x: 10, y: 10, width: 100.5, height: 40)
            window.host.layer?.addSublayer(layer)
            layer.setNeedsDisplay()
            CATransaction.flush()
            spinRunLoop(0.3)
            print("PROBE window=\(name) windowCS=\(window.window.colorSpace?.localizedName ?? "nil") screenCS=\(window.window.screen?.colorSpace?.localizedName ?? "nil") \(ContextProbeLayer.log.last ?? "none")")
            print("PROBE windowCGName=\(String(describing: window.window.colorSpace?.cgColorSpace?.name)) screenCGName=\(String(describing: window.window.screen?.colorSpace?.cgColorSpace?.name)) depth=\(window.window.depthLimit.rawValue) canP3=\(window.window.canRepresent(.p3)) screenCanP3=\(window.window.screen?.canRepresent(.p3) ?? false) wide=\(window.window.colorSpace?.cgColorSpace?.isWideGamutRGB ?? false)")
            layer.removeFromSuperlayer()
        }
    }

    func testMutationIsDetected() throws {
        let window = AsyncTextWindow(size: NSSize(width: 620, height: 900), colorSpace: nil)
        defer { window.close() }
        spinRunLoop(0.3)
        let a = try XCTUnwrap(render(window, async: false, count: 6, paragraphs: 4, wait: 0.4))
        let scale = window.window.backingScaleFactor
        let scene = AsyncTextScene(in: window.host, count: 6, width: 600, paragraphs: 4, async: true, scale: scale)
        scene.layers[3].frame.origin.x += 0.5
        CATransaction.flush()
        spinRunLoop(0.4)
        let b = try XCTUnwrap(window.capture().map(rgba))
        scene.remove()
        XCTAssertNotEqual(a, b)
    }

    func testFirstFrameHasContent() throws {
        let window = AsyncTextWindow(size: NSSize(width: 620, height: 900), colorSpace: nil)
        defer { window.close() }
        spinRunLoop(0.3)
        let scale = window.window.backingScaleFactor
        System.updateScaleFactor(scale)
        let reference = try XCTUnwrap(render(window, async: false, count: 6, paragraphs: 4, wait: 0.5))
        let blank = try XCTUnwrap(window.capture().map(rgba))
        for async in [false, true] {
            var firstMatch: [Double] = []
            var blankFrames = 0, partialFrames = 0
            for _ in 0..<8 {
                let scene = AsyncTextScene(in: window.host, count: 6, width: 600, paragraphs: 4, async: async, scale: scale)
                let start = CACurrentMediaTime()
                CATransaction.flush()
                var matched: Double?
                var sawNonFinal = false
                while CACurrentMediaTime() - start < 0.25 {
                    guard let shot = window.capture().map(rgba) else { break }
                    if shot == reference {
                        matched = CACurrentMediaTime() - start
                        break
                    }
                    if shot == blank { blankFrames += 1 } else { partialFrames += 1 }
                    sawNonFinal = true
                }
                _ = sawNonFinal
                firstMatch.append((matched ?? 1) * 1000)
                scene.remove()
                CATransaction.flush()
                spinRunLoop(0.1)
            }
            print("ASYNC_FIRST_FRAME async=\(async) msToFinal=\(firstMatch.map { String(format: "%.1f", $0) }) blankCaptures=\(blankFrames) partialCaptures=\(partialFrames)")
        }
    }

    func testMainThreadCommitCost() throws {
        guard ProcessInfo.processInfo.environment["ASYNC_TEXT_BENCH"] == "1" else { throw XCTSkip("set ASYNC_TEXT_BENCH=1") }
        let window = AsyncTextWindow(size: NSSize(width: 620, height: 1400), colorSpace: nil)
        defer { window.close() }
        spinRunLoop(0.3)
        let scale = window.window.backingScaleFactor
        System.updateScaleFactor(scale)
        let cs = try XCTUnwrap(window.window.colorSpace?.cgColorSpace)
        let queue = DispatchQueue(label: "raster", qos: .userInitiated, attributes: .concurrent)
        for paragraphs in [1, 4, 12] {
            for mode in ["native", "manual16", "manual8", "native", "manual16", "manual8"] {
                var mainMs: [Double] = []
                var bindMs: [Double] = []
                var procMs: [Double] = []
                for _ in 0..<30 {
                    let p0 = processCPU()
                    let b0 = threadCPU()
                    let remove: () -> Void
                    switch mode {
                    case "native":
                        let scene = AsyncTextScene(in: window.host, count: 8, width: 600, paragraphs: paragraphs, async: false, scale: scale)
                        remove = scene.remove
                    default:
                        let scene = ManualTextScene(in: window.host, count: 8, width: 600, paragraphs: paragraphs, scale: scale, colorSpace: cs, flipped: nil, queue: queue, format: mode == "manual16" ? .rgba16 : .bgra8)
                        remove = scene.remove
                    }
                    let t0 = threadCPU()
                    CATransaction.flush()
                    let t1 = threadCPU()
                    spinRunLoop(0.05)
                    let p1 = processCPU()
                    bindMs.append((t0 - b0) * 1000)
                    mainMs.append((t1 - t0) * 1000)
                    procMs.append((p1 - p0) * 1000)
                    remove()
                    CATransaction.flush()
                    spinRunLoop(0.02)
                }
                mainMs.sort(); procMs.sort(); bindMs.sort()
                print("ASYNC_BENCH paragraphs=\(paragraphs) mode=\(mode) bindMainMedianMs=\(String(format: "%.3f", bindMs[15])) commitMainMedianMs=\(String(format: "%.3f", mainMs[15])) commitMainP90Ms=\(String(format: "%.3f", mainMs[27])) processMedianMs=\(String(format: "%.3f", procMs[15]))")
            }
        }
    }
}
