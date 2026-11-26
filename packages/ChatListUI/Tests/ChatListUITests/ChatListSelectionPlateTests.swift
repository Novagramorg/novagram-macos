import XCTest
import AppKit
import TGUIKit
@testable import ChatListUI

final class ChatListSelectionPlateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let rowFrame = NSMakeRect(0, 0, 300, 70)
    private let plateFrame = NSMakeRect(3, 3, 294, 64)
    private let plateColor = NSColor(calibratedRed: 0.36, green: 0.47, blue: 0.86, alpha: 1)

    private func makeHost() -> View {
        let host = View(frame: rowFrame)
        host.backgroundColor = .white
        return host
    }

    private func addContent(to host: View) {
        let content = View(frame: host.bounds)
        host.addSubview(content)
        let avatar = View(frame: NSMakeRect(10, 10, 50, 50))
        avatar.backgroundColor = .systemGreen
        avatar.layer?.cornerRadius = 25
        host.addSubview(avatar)
    }

    private func legacyPlate(in host: View) -> View {
        let plate = View()
        plate.layer?.cornerRadius = 14
        plate.layer?.masksToBounds = true
        plate.backgroundColor = plateColor
        plate.frame = plateFrame
        host.addSubview(plate)
        return plate
    }

    private func currentPlate(in host: View) -> SimpleLayer {
        let plate = makeChatListSelectionPlateLayer()
        plate.isHidden = false
        plate.backgroundColor = plateColor.cgColor
        plate.frame = plateFrame
        host.layer?.addSublayer(plate)
        return plate
    }

    private func differingPixelsOutsideCorners(_ a: PixelBuffer, _ b: PixelBuffer, scale: Int = 2) -> Int {
        let corner = Int(ceil(14 * 1.6)) * scale
        let plate = NSRect(x: plateFrame.minX * CGFloat(scale), y: plateFrame.minY * CGFloat(scale), width: plateFrame.width * CGFloat(scale), height: plateFrame.height * CGFloat(scale))
        let corners = [
            NSRect(x: plate.minX - 2, y: plate.minY - 2, width: CGFloat(corner) + 2, height: CGFloat(corner) + 2),
            NSRect(x: plate.maxX - CGFloat(corner), y: plate.minY - 2, width: CGFloat(corner) + 2, height: CGFloat(corner) + 2),
            NSRect(x: plate.minX - 2, y: plate.maxY - CGFloat(corner), width: CGFloat(corner) + 2, height: CGFloat(corner) + 2),
            NSRect(x: plate.maxX - CGFloat(corner), y: plate.maxY - CGFloat(corner), width: CGFloat(corner) + 2, height: CGFloat(corner) + 2),
        ]
        var count = 0
        for y in 0 ..< a.height {
            for x in 0 ..< a.width where !corners.contains(where: { $0.contains(NSPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) }) {
                let index = (y * a.width + x) * 4
                if (0 ..< 4).contains(where: { abs(Int(a.bytes[index + $0]) - Int(b.bytes[index + $0])) > 2 }) {
                    count += 1
                }
            }
        }
        return count
    }

    func testPlateLayerRendersLikeThePlateView() {
        let legacyHost = makeHost()
        _ = legacyPlate(in: legacyHost)
        addContent(to: legacyHost)
        let currentHost = makeHost()
        _ = currentPlate(in: currentHost)
        addContent(to: currentHost)
        let empty = makeHost()
        addContent(to: empty)
        let old = ViewSnapshot.render(legacyHost)
        let new = ViewSnapshot.render(currentHost)
        XCTAssertGreaterThan(old.differingPixels(from: ViewSnapshot.render(empty)), 1000)
        XCTAssertEqual(differingPixelsOutsideCorners(old, new), 0)
    }

    func testPlateStaysBelowViewsAddedAfterIt() {
        let legacyHost = makeHost()
        _ = legacyPlate(in: legacyHost)
        addContent(to: legacyHost)
        let currentHost = makeHost()
        _ = currentPlate(in: currentHost)
        addContent(to: currentHost)
        _ = ViewSnapshot.render(currentHost)
        for host in [legacyHost, currentHost] {
            let late = View(frame: NSMakeRect(100, 20, 60, 30))
            late.backgroundColor = .systemOrange
            host.addSubview(late)
        }
        XCTAssertEqual(differingPixelsOutsideCorners(ViewSnapshot.render(legacyHost), ViewSnapshot.render(currentHost)), 0)
    }

    func testHiddenPlateDrawsNothing() {
        let currentHost = makeHost()
        let plate = currentPlate(in: currentHost)
        addContent(to: currentHost)
        plate.isHidden = true
        let empty = makeHost()
        addContent(to: empty)
        XCTAssertEqual(ViewSnapshot.render(currentHost).differingPixels(from: ViewSnapshot.render(empty)), 0)
    }

    private func basic(_ layer: CALayer?, _ key: String) -> CABasicAnimation? {
        return layer?.animation(forKey: key) as? CABasicAnimation
    }

    private func assertSameAnimation(_ legacy: CABasicAnimation?, _ current: CABasicAnimation?, _ key: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(legacy, key, file: file, line: line)
        XCTAssertEqual(legacy?.keyPath, current?.keyPath, key, file: file, line: line)
        XCTAssertEqual(legacy?.duration, current?.duration, key, file: file, line: line)
        XCTAssertEqual(legacy?.timingFunction, current?.timingFunction, key, file: file, line: line)
        XCTAssertEqual(legacy?.fromValue as? NSValue, current?.fromValue as? NSValue, key, file: file, line: line)
        XCTAssertEqual(legacy?.toValue as? NSValue, current?.toValue as? NSValue, key, file: file, line: line)
        XCTAssertEqual(legacy?.isRemovedOnCompletion, current?.isRemovedOnCompletion, key, file: file, line: line)
    }

    func testFrameChangeAnimatesLikeTheViewHelpers() {
        let targets = [NSMakeRect(3, 3, 294, 64), NSMakeRect(3, 3, 64, 64), NSMakeRect(8, 6, 64, 64), NSMakeRect(5, 4, 294, 64)]
        let legacyHost = makeHost()
        let legacy = legacyPlate(in: legacyHost)
        let currentHost = makeHost()
        let current = currentPlate(in: currentHost)
        for target in targets.dropFirst() {
            legacy.layer?.removeAllAnimations()
            current.removeAllAnimations()
            legacy._change(size: target.size, animated: true, duration: 0.2, timingFunction: .easeOut)
            legacy._change(pos: target.origin, animated: true, duration: 0.2, timingFunction: .easeOut)
            chatListAnimateLayerFrame(current, to: target)
            XCTAssertEqual(Set(legacy.layer?.animationKeys() ?? []), Set(current.animationKeys() ?? []), "\(target)")
            for key in legacy.layer?.animationKeys() ?? [] {
                assertSameAnimation(basic(legacy.layer, key), basic(current, key), "\(key) \(target)")
            }
            XCTAssertEqual(legacy.frame, target)
            XCTAssertEqual(current.frame, target)
        }
    }

    func testFactoryMatchesTheOldPlateViewLayer() {
        let plate = makeChatListSelectionPlateLayer()
        let view = View()
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        XCTAssertEqual(plate.cornerRadius, view.layer?.cornerRadius)
        XCTAssertEqual(plate.cornerCurve, view.layer?.cornerCurve)
        XCTAssertEqual(plate.masksToBounds, true)
        XCTAssertEqual(plate.anchorPoint, .zero)
        XCTAssertLessThan(plate.zPosition, 0)
        XCTAssertTrue(plate.isHidden)
    }

    func testUnchangedFrameAddsNoAnimation() {
        let currentHost = makeHost()
        let current = currentPlate(in: currentHost)
        chatListAnimateLayerFrame(current, to: plateFrame)
        XCTAssertNil(current.animationKeys())
        XCTAssertEqual(current.frame, plateFrame)
    }
}
