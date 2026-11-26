import Foundation
import Cocoa
import TGUIKit

struct QrStudioGlassAppearance: Equatable {
    let tintColor: NSColor

    var isDark: Bool {
        return self.tintColor.lightness <= 0.8
    }

    var iconColor: NSColor {
        return self.isDark ? .white : .black
    }
}

enum QrStudioGlass {
    static func isDark(_ backdrop: QrStudioBackdrop) -> Bool {
        return self.appearance(for: backdrop).isDark
    }

    static func appearance(for backdrop: QrStudioBackdrop) -> QrStudioGlassAppearance {
        let background: QrStudioColor
        switch backdrop {
        case let .gift(gift):
            background = QrStudioColor.mix(gift.outer, gift.inner, 0.1)
        case let .theme(theme) where !theme.colors.isEmpty:
            let count = CGFloat(theme.colors.count)
            background = QrStudioColor(
                theme.colors.reduce(0) { $0 + $1.r } / count,
                theme.colors.reduce(0) { $0 + $1.g } / count,
                theme.colors.reduce(0) { $0 + $1.b } / count
            )
        default:
            background = backdrop.baseColor
        }
        let blend: CGFloat = background.nsColor.lightness > 0.8 ? 1 : 0
        func overlay(_ channel: CGFloat) -> CGFloat {
            let value = channel < 0.5 ? 2 * channel * blend : 1 - 2 * (1 - channel) * (1 - blend)
            return channel + (max(0, min(1, value)) - channel) * 0.25
        }
        return QrStudioGlassAppearance(tintColor: NSColor(srgbRed: overlay(background.r), green: overlay(background.g), blue: overlay(background.b), alpha: 1))
    }

    static func iconColor(isDark: Bool) -> NSColor {
        return isDark ? QrStudioColor(0.96, 0.96, 0.96).nsColor : QrStudioColor(0.1, 0.1, 0.1).nsColor
    }

    static func crossfade(_ view: NSView) {
        guard view.window != nil, let layer = view.layer else {
            return
        }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.45
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "qrStudioAppearance")
    }
}

final class QrStudioGlassButtonView: Control {
    var action: ((NSView) -> Void)?

    private var appliedAppearance: QrStudioGlassAppearance?
    private var appliedIcon: CGImage?
    private var appliedSize: CGSize?
    private var visuals = QrStudioStageStack<ImageButton>()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
        self.set(handler: { [weak self] control in
            self?.action?(control)
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(size: CGSize, appearance: QrStudioGlassAppearance, icon: CGImage?, reveal: QrStudioAppearanceReveal?, transition: ContainedViewLayoutTransition) {
        let sizeChanged = self.appliedSize != size
        self.appliedSize = size
        if sizeChanged, let top = self.visuals.layers.last {
            top.item.layer?.mask = nil
            top.item.layer?.removeAllAnimations()
            self.revealCompleted(id: top.id)
        }
        for visual in self.visuals.layers {
            visual.item.frame = CGRect(origin: .zero, size: size)
            visual.item.glassSize = size
        }

        if self.appliedAppearance != appearance {
            let hadAppearance = self.appliedAppearance != nil
            self.appliedAppearance = appearance
            self.appliedIcon = icon
            let visual = ImageButton(frame: CGRect(origin: .zero, size: size))
            visual.isEventLess = true
            visual.isAccessibilityDecorative = true
            visual.userInteractionEnabled = false
            visual.autohighlight = false
            visual.setGlassEffect(size: size, tintColor: appearance.tintColor, forceAppearance: .forceLight, interactive: false)
            self.updateIcon(visual, icon: icon, appearance: appearance)
            self.addSubview(visual)
            visual.layoutSubtreeIfNeeded()
            self.interactiveGlassView = visual
            let id = self.visuals.push(visual)

            guard hadAppearance, !sizeChanged, self.window != nil, let layer = visual.layer else {
                self.revealCompleted(id: id)
                return
            }
            if let reveal = reveal, let superview = self.superview {
                let frame = superview.convert(self.bounds, from: self)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                CATransaction.setCompletionBlock { [weak self, weak layer] in
                    layer?.mask = nil
                    self?.revealCompleted(id: id)
                }
                layer.mask = reveal.makeMask(frame: frame)
                CATransaction.commit()
            } else if transition.isAnimated {
                layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.45, completion: { [weak self] _ in
                    self?.revealCompleted(id: id)
                })
            } else {
                self.revealCompleted(id: id)
            }
        } else if self.appliedIcon !== icon, let visual = self.visuals.layers.last?.item {
            self.appliedIcon = icon
            self.updateIcon(visual, icon: icon, appearance: appearance)
        }
    }

    private func updateIcon(_ visual: ImageButton, icon: CGImage?, appearance: QrStudioGlassAppearance) {
        if let icon = icon, let tinted = qrStudioTinted(icon, color: appearance.iconColor) {
            visual.set(image: tinted, for: .Normal)
        } else {
            visual.removeImage(for: .Normal)
        }
    }

    private func revealCompleted(id: Int) {
        let removed = Set(self.visuals.revealCompleted(id: id))
        guard !removed.isEmpty else {
            return
        }
        let remaining = Set(self.visuals.layers.map { ObjectIdentifier($0.item) })
        for view in self.subviews where !remaining.contains(ObjectIdentifier(view)) {
            view.removeFromSuperview()
        }
    }
}
