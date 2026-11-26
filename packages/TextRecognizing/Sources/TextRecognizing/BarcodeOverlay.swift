import Foundation
import Cocoa
import TGUIKit

@available(macOS 10.15, *)
final class BarcodeOverlay {

    final class Area : Control {
        let outline = CAShapeLayer()

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            outline.fillColor = NSColor.systemBlue.withAlphaComponent(0.14).cgColor
            outline.strokeColor = NSColor.systemBlue.cgColor
            outline.lineWidth = 3
            outline.lineJoin = .round
            outline.shadowColor = NSColor.black.cgColor
            outline.shadowOpacity = 0.35
            outline.shadowRadius = 4
            outline.shadowOffset = .zero
            outline.opacity = 0
            self.layer?.addSublayer(outline)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class Chip : Control {
        private let textView = TextView()
        private let iconView = ImageView()

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            addSubview(iconView)
            addSubview(textView)
            iconView.isAccessibilityDecorative = true

            if #available(macOS 11.0, *), let icon = NSImage(systemSymbolName: "qrcode", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold)) {
                iconView.image = icon.precomposed(.white)
                iconView.setFrameSize(icon.size)
            } else {
                iconView.isHidden = true
            }

            self.layer?.cornerRadius = Chip.height / 2
            self.layer?.borderWidth = 1
            self.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            self.set(background: NSColor(white: 0.08, alpha: 0.72), for: .Normal)
            self.set(background: NSColor(white: 0.16, alpha: 0.85), for: .Hover)
            self.set(background: NSColor(white: 0.22, alpha: 0.9), for: .Highlight)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        static let height: CGFloat = 28

        override func hitTest(_ point: NSPoint) -> NSView? {
            if isHidden {
                return nil
            }
            return NSPointInRect(point, frame) ? self : nil
        }

        func update(text: String, maxWidth: CGFloat) {
            let iconWidth = iconView.isHidden ? 0 : iconView.frame.width + 6
            let layout = TextViewLayout(.initialize(string: text, color: NSColor.white, font: .medium(13)), maximumNumberOfLines: 1, truncationType: .middle)
            layout.measure(width: max(20, maxWidth - 24 - iconWidth))
            textView.update(layout)
            setAccessibilityLabel(text)
            setFrameSize(NSMakeSize(12 + iconWidth + layout.layoutSize.width + 12, Chip.height))
            needsLayout = true
        }

        override func layout() {
            super.layout()
            if iconView.isHidden {
                textView.centerY(x: 12)
            } else {
                iconView.centerY(x: 12)
                textView.centerY(x: iconView.frame.maxX + 6)
            }
        }
    }

    let barcode: TextRecognizing.Result.Barcode
    let area = Area(frame: .zero)
    let chip = Chip(frame: .zero)
    private var isHighlighted: Bool = false
    private(set) var isRevealed: Bool = false
    
    static let proximity: CGFloat = 32

    init(barcode: TextRecognizing.Result.Barcode, superview: NSView, action: @escaping (TextRecognizing.Result.Barcode) -> Void, menu: @escaping (TextRecognizing.Result.Barcode) -> ContextMenu?) {
        self.barcode = barcode

        superview.addSubview(area)
        superview.addSubview(chip)
        chip.isHidden = true
        chip.layer?.opacity = 0

        for control in [area, chip] as [Control] {
            control.set(cursor: NSCursor.pointingHand, for: .Hover)
            control.set(cursor: NSCursor.pointingHand, for: .Highlight)
            control.set(handler: { _ in
                action(barcode)
            }, for: .Click)
            control.set(handler: { [weak self] _ in
                self?.updateHighlight()
            }, for: .Hover)
            control.set(handler: { [weak self] _ in
                self?.updateHighlight()
            }, for: .Normal)
            control.set(handler: { [weak self] _ in
                self?.updateHighlight()
            }, for: .Highlight)
            control.contextMenu = {
                return menu(barcode)
            }
        }
    }

    static func displayText(_ barcode: TextRecognizing.Result.Barcode) -> String {
        if let link = barcode.link {
            var text = link
            if let scheme = URL(string: link)?.scheme?.lowercased(), ["http", "https"].contains(scheme), text.lowercased().hasPrefix(scheme + "://") {
                text = String(text.dropFirst(scheme.count + 3))
            }
            if text.hasSuffix("/") {
                text.removeLast()
            }
            return text
        }
        let firstLine = barcode.payload.components(separatedBy: .newlines).first(where: { !$0.isEmpty })
        return firstLine ?? barcode.payload
    }

    func layout(in size: NSSize) {
        let corners = barcode.corners(viewSize: size)
        let bounds = barcode.bounds(viewSize: size)
        let inset: CGFloat = 8
        let expandedBounds = bounds.insetBy(dx: -inset, dy: -inset)
        let areaFrame = NSMakeRect(round(expandedBounds.minX), round(expandedBounds.minY), round(expandedBounds.maxX) - round(expandedBounds.minX), round(expandedBounds.maxY) - round(expandedBounds.minY))
        area.frame = areaFrame

        let center = NSMakePoint(bounds.midX, bounds.midY)
        let expanded = corners.map { point -> CGPoint in
            let dx = point.x - center.x
            let dy = point.y - center.y
            let length = max(1, sqrt(dx * dx + dy * dy))
            let offset = inset * 0.7
            return NSMakePoint(point.x + dx / length * offset * sqrt(2) - areaFrame.minX, point.y + dy / length * offset * sqrt(2) - areaFrame.minY)
        }
        let path = CGMutablePath()
        path.addLines(between: expanded)
        path.closeSubpath()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        area.outline.frame = areaFrame.size.bounds
        area.outline.path = path
        CATransaction.commit()

        let margin: CGFloat = 6
        let gap: CGFloat = 8 + floor(bounds.height * 0.1)
        chip.update(text: BarcodeOverlay.displayText(barcode), maxWidth: min(280, size.width - margin * 2))

        var y = bounds.minY - gap - Chip.height
        if y < margin {
            y = bounds.maxY + gap
            if y + Chip.height > size.height - margin {
                y = bounds.midY - Chip.height / 2
            }
        }
        let x = max(margin, min(size.width - chip.frame.width - margin, bounds.midX - chip.frame.width / 2))
        chip.setFrameOrigin(NSMakePoint(floor(x), floor(y)))
    }

    func contains(_ point: NSPoint) -> Bool {
        return NSPointInRect(point, area.frame) || (isRevealed && NSPointInRect(point, chip.frame))
    }
    
    func isNear(_ point: NSPoint) -> Bool {
        let proximity = BarcodeOverlay.proximity
        if NSPointInRect(point, area.frame.insetBy(dx: -proximity, dy: -proximity)) {
            return true
        }
        return isRevealed && NSPointInRect(point, chip.frame.insetBy(dx: -8, dy: -8))
    }
    
    func reveal(_ revealed: Bool, animated: Bool) {
        guard revealed != isRevealed else {
            return
        }
        isRevealed = revealed
        guard let layer = chip.layer else {
            return
        }
        let from = CGFloat(layer.presentation()?.opacity ?? layer.opacity)
        layer.opacity = revealed ? 1 : 0
        if revealed {
            chip.isHidden = false
            if animated {
                layer.animateAlpha(from: from, to: 1, duration: 0.15)
                if from == 0 {
                    layer.animateScaleSpring(from: 0.9, to: 1, duration: 0.3, bounce: false)
                }
            }
        } else if animated {
            layer.animateAlpha(from: from, to: 0, duration: 0.15, completion: { [weak self] _ in
                if self?.isRevealed == false {
                    self?.chip.isHidden = true
                }
            })
        } else {
            chip.isHidden = true
        }
    }
    
    func remove(animated: Bool) {
        if animated {
            performSubviewRemoval(area, animated: true)
            performSubviewRemoval(chip, animated: true)
        } else {
            area.removeFromSuperview()
            chip.removeFromSuperview()
        }
    }

    private func updateHighlight() {
        let highlighted = area.controlState != .Normal || chip.controlState != .Normal
        guard highlighted != isHighlighted else {
            return
        }
        isHighlighted = highlighted
        area.outline.removeAnimation(forKey: "pulse")
        let from = CGFloat(area.outline.presentation()?.opacity ?? area.outline.opacity)
        area.outline.opacity = highlighted ? 1 : 0
        area.outline.animateAlpha(from: from, to: highlighted ? 1 : 0, duration: 0.15)
    }
}
