import AppKit
import TGUIKit
import XCTest
@testable import SearchViews

final class StatusViewTests: XCTestCase {
    func setupView() -> (NSWindow, PanelSearchStatusView) {
        initializeSearchViewLab()
        System.updateScaleFactor(2)
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 350, 448), styleMask: [.borderless], backing: .buffered, defer: false)
        let view = PanelSearchStatusView(frame: NSMakeRect(0, 0, 350, 448))
        window.contentView = view
        return (window, view)
    }
    func update(_ view: PanelSearchStatusView, _ status: PanelSearchPresentation, reduceMotion: Bool = false, make: @escaping () -> View? = { View(frame: NSMakeRect(0, 0, 120, 120)) }) {
        view.update(status: status, kind: .stickers, title: "No Results Found", detail: "There were no results for “peppafe”.\nTry a new search.", loadingLabel: "Loading", backgroundColor: .white, textColor: .black, detailColor: .gray, reduceMotion: reduceMotion, makeAnimation: make)
        view.layoutSubtreeIfNeeded()
    }
    func testLoadingUsesOneGradientAndNoDuck() {
        let (window, view) = setupView()
        var animations = 0
        update(view, .loading, make: { animations += 1; return View() })
        XCTAssertEqual(animations, 0)
        let gradients = view.layer!.sublayers!.compactMap { $0 as? CAGradientLayer }
        XCTAssertEqual(gradients.count, 1)
        XCTAssertNotNil(gradients[0].animation(forKey: "searchShimmer"))
        XCTAssertNotNil((gradients[0].mask as? CAShapeLayer)?.path)
        XCTAssertNil(view.hitTest(NSPoint(x: 30, y: 30)))
        withExtendedLifetime(window) {}
    }
    func testEmptyCreatesDuckOnlyOnceAndStopsShimmer() {
        let (window, view) = setupView()
        var animations = 0
        update(view, .loading)
        for _ in 0..<10 { update(view, .empty, make: { animations += 1; return View() }) }
        XCTAssertEqual(animations, 1)
        XCTAssertEqual(view.subviews.count, 3)
        XCTAssertNil(view.layer!.sublayers!.compactMap { $0 as? CAGradientLayer }.first!.animation(forKey: "searchShimmer"))
        withExtendedLifetime(window) {}
    }
    func testHiddenReleasesDuckAndStopsShimmer() {
        let (window, view) = setupView()
        update(view, .empty)
        update(view, .hidden)
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(view.subviews.count, 2)
        update(view, .loading)
        view.removeFromSuperview()
        window.contentView = nil
        XCTAssertNil(view.layer!.sublayers!.compactMap { $0 as? CAGradientLayer }.first!.animation(forKey: "searchShimmer"))
    }
    func testReducedMotionKeepsStaticPlaceholders() {
        let (window, view) = setupView()
        update(view, .loading, reduceMotion: true)
        let gradient = view.layer!.sublayers!.compactMap { $0 as? CAGradientLayer }.first!
        XCTAssertFalse(gradient.isHidden)
        XCTAssertNil(gradient.animation(forKey: "searchShimmer"))
        withExtendedLifetime(window) {}
    }
    func testEmptyLayoutFitsCompactPanel() {
        let (window, view) = setupView()
        view.frame.size = NSMakeSize(280, 200)
        update(view, .empty)
        for child in view.subviews {
            XCTAssertTrue(view.bounds.contains(child.frame), "\(child.frame)")
        }
        withExtendedLifetime(window) {}
    }
    func testLoadingAccessibilityLabel() {
        let (window, view) = setupView()
        update(view, .loading)
        XCTAssertEqual(view.accessibilityLabel(), "Loading")
        update(view, .empty)
        XCTAssertTrue(view.accessibilityLabel()!.contains("No Results Found"))
        withExtendedLifetime(window) {}
    }
}
