import Cocoa
import TGUIKit
import TelegramContext
import TelegramUtils
import SwiftSignalKit
import Localization

@available(macOS 10.15, *)
final class WalletGramTooltipPresenter {
    private let context: any AccountContextProtocol
    private let noticeDisposable = MetaDisposable()
    private weak var cardView: WalletCardView?
    private var address = ""
    private var isVisible = false
    private var isPending = false
    private var didPresent = false
    private var tooltip: WalletGramTooltipView?
    private var dismissTimer: Foundation.Timer?
    private var eventMonitor: Any?

    init(context: any AccountContextProtocol) {
        self.context = context
    }

    private var presentationLimit: Int32 {
        return 3 + Int32(abs(self.context.peerId.id._internalGetInt64Value()) % 3)
    }

    func update(cardView: WalletCardView, address: String) {
        self.cardView = cardView
        if self.address != address {
            self.address = address
            self.isPending = false
            self.didPresent = false
            self.noticeDisposable.set(nil)
            dismiss(animated: false)
        }
        if let tooltip {
            if let overlayParent = cardView.superview, tooltip.superview === overlayParent {
                tooltip.position(relativeTo: cardView)
            } else {
                dismiss(animated: false)
            }
        }
        maybePresent()
    }

    func setVisible(_ value: Bool) {
        isVisible = value
        if value {
            maybePresent()
        } else {
            dismiss(animated: false)
        }
    }

    private func maybePresent() {
        guard isVisible, !address.isEmpty, !isPending, !didPresent,
              let cardView, cardView.window != nil,
              !cardView.gramIconFrame.isEmpty,
              cardView.visibleRect.contains(cardView.gramIconFrame) else {
            return
        }
        let walletAddress = address
        isPending = true
        noticeDisposable.set((ApplicationSpecificNotice.getWalletGramTooltip(accountManager: context.sharedContext.accountManager)
        |> deliverOnMainQueue).start(next: { [weak self, weak cardView] count in
            guard let self, self.address == walletAddress else { return }
            self.isPending = false
            guard !self.didPresent else { return }
            if count >= self.presentationLimit {
                self.didPresent = true
                return
            }
            guard self.isVisible, let cardView, cardView.window != nil, let overlayParent = cardView.superview,
                  !cardView.gramIconFrame.isEmpty,
                  cardView.visibleRect.contains(cardView.gramIconFrame) else { return }
            self.didPresent = true
            let tooltip = WalletGramTooltipView(frame: .zero)
            overlayParent.addSubview(tooltip, positioned: .above, relativeTo: cardView)
            tooltip.position(relativeTo: cardView)
            self.tooltip = tooltip
            tooltip.animateIn()
            self.dismissTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false, block: { [weak self] _ in
                self?.dismiss(animated: true)
            })
            self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self, weak cardView] event in
                if event.window === cardView?.window {
                    self?.dismiss(animated: true)
                }
                return event
            }
            _ = ApplicationSpecificNotice.incrementWalletGramTooltip(accountManager: self.context.sharedContext.accountManager).startStandalone()
        }))
    }

    private func dismiss(animated: Bool) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let tooltip {
            self.tooltip = nil
            if animated {
                tooltip.animateOut()
            } else {
                DispatchQueue.main.async {
                    tooltip.removeFromSuperview()
                }
            }
        }
    }

    deinit {
        noticeDisposable.dispose()
        dismissTimer?.invalidate()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        tooltip?.removeFromSuperview()
    }
}

@available(macOS 10.15, *)
private final class WalletGramTooltipView: View {
    private let textView = TextView()
    private let gradient = CAGradientLayer()
    private let arrowGradient = CAGradientLayer()
    private let shape = CAShapeLayer()
    private var arrowTip = NSPoint.zero

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
        layer?.masksToBounds = false
        layer?.zPosition = 1
        _anchorPoint = NSPoint(x: 0.5, y: 0.5)
        gradient.colors = [NSColor(rgb: 0x47bafe).cgColor, NSColor(rgb: 0x44b5ff).cgColor]
        gradient.startPoint = .zero
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.cornerRadius = 14
        gradient.cornerCurve = .continuous
        gradient.masksToBounds = true
        layer?.addSublayer(gradient)
        arrowGradient.colors = gradient.colors
        arrowGradient.startPoint = gradient.startPoint
        arrowGradient.endPoint = gradient.endPoint
        arrowGradient.mask = shape
        layer?.addSublayer(arrowGradient)
        textView.isEventLess = true
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.disableBackgroundDrawing = true
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func position(relativeTo cardView: WalletCardView) {
        guard let overlayParent = superview else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let text = strings().walletGramTooltipDigitalCurrency
        let layout = TextViewLayout(.initialize(string: text, color: .white, font: .medium(11)), alignment: .left)
        layout.measure(width: max(1, cardView.bounds.width - 20 - 22))
        textView.update(layout)
        let bodyHeight = layout.layoutSize.height + 12
        let width = layout.layoutSize.width + 22
        let cardFrame = overlayParent.convert(cardView.bounds, from: cardView)
        let source = overlayParent.convert(cardView.gramIconFrame, from: cardView).offsetBy(dx: 0, dy: 4)
        let x = max(cardFrame.minX + 10, min(source.midX - width / 2, cardFrame.maxX - 10 - width))
        let tooltipFrame = NSRect(x: x, y: source.minY - 10 - bodyHeight, width: width, height: bodyHeight)
        if frame != tooltipFrame {
            frame = tooltipFrame
        }
        updateLayer()
        let arrowX = floor(source.midX - 9) - x
        arrowTip = NSPoint(x: arrowX + 9, y: bodyHeight + 7)
        textView.setFrameOrigin(NSPoint(x: 11, y: 6))
        gradient.frame = NSRect(x: 0, y: 0, width: width, height: bodyHeight)
        arrowGradient.frame = NSRect(x: 0, y: bodyHeight, width: width, height: 7)
        shape.frame = arrowGradient.bounds
        let path = CGMutablePath()
        let scale: CGFloat = 0.333333 * 0.62
        let origin = NSPoint(x: arrowX, y: 0)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }
        path.move(to: point(85.882251, 0))
        path.addCurve(to: point(68.9116882, 7.02834833), control1: point(79.5170552, 0), control2: point(73.4125613, 2.52817247))
        path.addLine(to: point(51.4264069, 24.5109211))
        path.addCurve(to: point(34.4558441, 24.5109211), control1: point(46.7401154, 29.1964866), control2: point(39.1421356, 29.1964866))
        path.addLine(to: point(16.9705627, 7.02834833))
        path.addCurve(to: point(0, 0), control1: point(12.4696897, 2.52817247), control2: point(6.36519576, 0))
        path.closeSubpath()
        shape.path = path
    }

    private var arrowOffset: NSPoint {
        NSPoint(x: arrowTip.x - bounds.width / 2, y: arrowTip.y - bounds.height / 2)
    }

    func animateIn() {
        layer?.animateSpring(from: NSNumber(value: 0.01), to: NSNumber(value: 1.0), keyPath: "transform.scale", duration: 0.4, damping: 105)
        layer?.animateSpring(from: NSValue(point: arrowOffset), to: NSValue(point: .zero), keyPath: "position", duration: 0.4, damping: 105, additive: true)
        layer?.animateAlpha(from: 0, to: 1, duration: 0.2, timingFunction: .easeInEaseOut)
    }

    func animateOut() {
        layer?.animateScale(from: 1, to: 0.01, duration: 0.2, removeOnCompletion: false)
        layer?.animatePosition(from: .zero, to: arrowOffset, duration: 0.2, timingFunction: .easeInEaseOut, removeOnCompletion: false, additive: true)
        layer?.animateAlpha(from: 1, to: 0, duration: 0.2, timingFunction: .easeInEaseOut, removeOnCompletion: false, completion: { [weak self] _ in
            self?.removeFromSuperview()
        })
    }
}
