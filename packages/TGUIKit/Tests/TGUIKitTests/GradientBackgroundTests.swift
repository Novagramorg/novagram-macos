import XCTest
import AppKit
@testable import TGUIKit

final class GradientBackgroundTests: XCTestCase {

    // The visible gradient lives on contentView.image (the non-dimmed image); the dimmed image only ever
    // fed CloneViews, which are never created. Verify the gradient still renders after both non-animated
    // layout paths now that the dimmed image is generated lazily instead of eagerly.

    func testSizeUpdatePathRendersGradient() {
        let view = AnimatedGradientBackgroundView(colors: [.red, .blue, .green, .yellow])
        view.updateLayout(size: CGSize(width: 300, height: 400), transition: .immediate)
        XCTAssertNotNil(view.contentView.image, "size-update path should render the gradient")
    }

    func testColorInvalidationPathRendersGradient() {
        let view = AnimatedGradientBackgroundView(colors: [.red, .blue, .green, .yellow])
        view.updateLayout(size: CGSize(width: 300, height: 400), transition: .immediate)
        view.updateColors(colors: [.yellow, .purple, .orange, .cyan])
        XCTAssertNotNil(view.contentView.image, "color-invalidation path should re-render the gradient")
    }
}
