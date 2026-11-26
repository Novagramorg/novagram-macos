import Cocoa
import TGUIKit

private let walletPeerBalanceHeaderGap: CGFloat = 28
private let walletPeerBalanceInset: CGFloat = 20
private let walletPeerBalanceCardWidth: CGFloat = 360
private let walletPeerBalanceButtonGap: CGFloat = 12
private let walletPeerBalanceButtonHeight: CGFloat = 40
private let walletCardReferenceSize = CGSize(width: 360, height: 228)
private let walletClassicAccent = NSColor.systemBlue
private var theme: PresentationTheme { return presentation }
private struct TestStrings {
    let peerInfoHeadItemSendMoney = "Send Money"
    let walletPeerBalanceControllerPublicBalanceNotice = "Your balance is public"
    func walletPeerBalanceControllerPeerBalanceNotice(_ name: String, _ balance: String) -> String { "\(name): \(balance)" }
}
private func formatGramsText(_ value: Int64, maxDecimalPositions: Int) -> String { String(value) }
private func walletMeasureBalanced(_ layout: TextViewLayout, width: CGFloat) { layout.measure(width: width) }
private var walletPeerBalanceCardHeight: CGFloat { ceil(walletPeerBalanceCardWidth * walletCardReferenceSize.height / walletCardReferenceSize.width) }
private func strings() -> TestStrings { return TestStrings() }
private final class WalletCardView: View {}
__VIEW__

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
System.updateScaleFactor(2)
System.liquidGlass = false
private var retainedImages: [NSImage] = []
for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.black.setFill()
        rect.fill()
        return true
    }
    image.setName(name)
    retainedImages.append(image)
}
private let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
private let host = View(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
window.contentView = host
private let source = View(frame: CGRect(x: 80, y: 100, width: 110, height: 32))
source.backgroundColor = .blue
source.layer?.masksToBounds = false
private let sourceContent = View(frame: source.bounds.insetBy(dx: 8, dy: 4))
source.addSubview(sourceContent)
private let sourceFrame = source.frame
private let sourceContentTransform = CATransform3DMakeTranslation(2, 1, 0)
sourceContent.layer?.transform = sourceContentTransform
private func verifyRestoredSource() {
    precondition(!source.isHidden, "The pill stays visible")
    precondition(source.frame == sourceFrame, "The pill frame stays fixed")
    precondition(source.layer?.masksToBounds == false, "Restore the original clipping")
    precondition(CATransform3DEqualToTransform(sourceContent.layer!.transform, sourceContentTransform), "Restore the label transform")
}
host.addSubview(source)
private func makeView() -> WalletPeerBalanceView {
    let view = WalletPeerBalanceView(frame: host.bounds)
    view.transitionSource = WalletPeerBalanceSource(view: source)
    precondition(view.transitionSource != nil, "Capture a source without showing a window")
    host.addSubview(view)
    view.animateIn()
    return view
}
private func waitFor(_ completed: () -> Bool) {
    let deadline = Date().addingTimeInterval(2)
    while !completed() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(completed(), "Transition completion must run")
}
private let motion = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
private let cancelled = makeView()
if motion {
    precondition(!source.isHidden, "Keep the pill background visible during flight")
    precondition(source.layer?.masksToBounds == true, "Clip the rising label inside the pill")
    cancelled.transitionSource?.update(progress: 0.3, dismissing: false)
    precondition(sourceContent.layer!.transform.m42 == sourceContentTransform.m42 - source.bounds.height, "Only the label slides up by the pill height")
    precondition(source.frame == sourceFrame, "Do not resize the pill")
    precondition(CATransform3DIsIdentity(source.layer!.transform), "Do not transform the pill background")
}
cancelled.cancelTransition()
verifyRestoredSource()
cancelled.removeFromSuperview()
private let detached = makeView()
detached.removeFromSuperview()
verifyRestoredSource()
private let closing = makeView()
private var completed = false
closing.animateOut { completed = true }
precondition(!closing.sendButton.userInteractionEnabled, "Closing disables sending")
waitFor { completed }
verifyRestoredSource()
closing.removeFromSuperview()
private let disappearingSource = makeView()
source.removeFromSuperview()
completed = false
disappearingSource.animateOut { completed = true }
waitFor { completed }
verifyRestoredSource()
disappearingSource.removeFromSuperview()
print("Passed offscreen wallet lifecycle: fixed pill, sliding label, cancellation, detach, interrupted opening, and missing-source dismissal")
