import Cocoa
import XCTest
import TGUIKit
import TelegramContext
import CandidateBindingHarness
import NativeBindingHarness

private protocol ProfileBindingDriver: AnyObject {
    func bind(_ index: Int)
}

extension NativeBindingHarness.BenchmarkDriver: ProfileBindingDriver {}
extension CandidateBindingHarness.BenchmarkDriver: ProfileBindingDriver {}

private final class ProfileWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var backingScaleFactor: CGFloat { 2 }
}

private final class ProfileScrollHost {
    let window = ProfileWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
    let scroll: NSScrollView
    let document: View
    init(_ root: NSView) {
        let size = CGSize(width: root.frame.width, height: 160)
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        scroll = NSScrollView(frame: CGRect(origin: .zero, size: size))
        document = View(frame: CGRect(x: 0, y: 0, width: size.width, height: root.frame.height + 1200))
        window.contentView = scroll
        scroll.documentView = document
        scroll.contentView.postsBoundsChangedNotifications = false
        document.addSubview(root)
    }
    func move(to y: CGFloat) {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
}

final class ProfileTests: XCTestCase {
    private func sampleVisibility(root: NSView, role: String, caption: Bool) {
        let host = ProfileScrollHost(root)
        for index in 0..<40 { host.move(to: index % 2 == 0 ? 0 : 190) }
        FileHandle.standardOutput.write(Data("INLINE_EMOJI_PROFILE_READY role=\(role) caption=\(caption) blocks=12 phase=visibility diagnostic_only=true\n".utf8))
        var operations = 0
        let deadline = CACurrentMediaTime() + 18
        while CACurrentMediaTime() < deadline {
            autoreleasepool {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for index in 0..<100 { host.move(to: index % 2 == 0 ? 0 : 190) }
                operations += 100
                CATransaction.commit()
                CATransaction.flush()
            }
        }
        XCTAssertGreaterThan(operations, 0)
        FileHandle.standardOutput.write(Data("INLINE_EMOJI_PROFILE_COMPLETE role=\(role) operations=\(operations) diagnostic_only=true\n".utf8))
        withExtendedLifetime(host) {}
    }

    private func sample<D: ProfileBindingDriver>(_ driver: D, role: String, caption: Bool) {
        driver.bind(0)
        autoreleasepool {
            for _ in 0..<20 {
                driver.bind(1)
                driver.bind(0)
            }
            CATransaction.flush()
        }
        FileHandle.standardOutput.write(Data("INLINE_EMOJI_PROFILE_READY role=\(role) caption=\(caption) blocks=12 diagnostic_only=true\n".utf8))
        var operations = 0
        let deadline = CACurrentMediaTime() + 18
        withExtendedLifetime(driver) {
            while CACurrentMediaTime() < deadline {
                autoreleasepool {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    for index in 0..<100 {
                        driver.bind(index % 2)
                    }
                    operations += 100
                    CATransaction.commit()
                    CATransaction.flush()
                }
            }
        }
        XCTAssertGreaterThan(operations, 0)
        FileHandle.standardOutput.write(Data("INLINE_EMOJI_PROFILE_COMPLETE role=\(role) caption=\(caption) blocks=12 operations=\(operations) diagnostic_only=true\n".utf8))
    }

    func testSameBindingDiagnosticSampler() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["INLINE_EMOJI_PROFILE"] == "1" else {
            throw XCTSkip("Opt-in diagnostic stack sampling; operation counts are not benchmark results")
        }
        let role = environment["INLINE_EMOJI_ROLE"] ?? ""
        guard role == "native" || role == "layer" else {
            XCTFail("Set INLINE_EMOJI_ROLE to native or layer")
            return
        }
        TGUIKitTestBootstrap.install()
        System.updateScaleFactor(2)
        defer { System.updateScaleFactor(2) }
        let caption = environment["INLINE_EMOJI_CAPTION"] == "1"
        let account = Account()
        if role == "native" {
            let fixtures = NativeBindingHarness.BenchmarkFixtures(account: account, caption: caption, blocks: 12)
            let driver = NativeBindingHarness.BenchmarkDriver(fixtures: fixtures)
            driver.bind(0)
            XCTAssertTrue(driver.rendersNative)
            XCTAssertEqual(driver.media.count, fixtures.expectedMediaCount)
            if environment["INLINE_EMOJI_PROFILE_PHASE"] == "visibility" {
                sampleVisibility(root: driver.root, role: role, caption: caption)
                return
            }
            sample(driver, role: role, caption: caption)
            XCTAssertTrue(driver.rendersNative)
            XCTAssertEqual(driver.media.count, fixtures.expectedMediaCount)
        } else {
            let fixtures = CandidateBindingHarness.BenchmarkFixtures(account: account, caption: caption, blocks: 12)
            let driver = CandidateBindingHarness.BenchmarkDriver(fixtures: fixtures)
            driver.bind(0)
            XCTAssertTrue(driver.rendersLayers)
            XCTAssertEqual(driver.media.count, fixtures.expectedMediaCount)
            if environment["INLINE_EMOJI_PROFILE_PHASE"] == "visibility" {
                sampleVisibility(root: driver.root, role: role, caption: caption)
                return
            }
            sample(driver, role: role, caption: caption)
            XCTAssertTrue(driver.rendersLayers)
            XCTAssertEqual(driver.media.count, fixtures.expectedMediaCount)
        }
    }
}
