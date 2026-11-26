import Cocoa
import TGUIKit
import Postbox
import TelegramCore

enum ChatVoiceSendFlightMotion {
    static let duration: Double = 0.3
    static let fadeDuration: Double = 0.06
    static let handOverTimeout: Double = 1.0
    static let horizontalControlPoints: (Float, Float, Float, Float) = (0.23, 1.0, 0.32, 1.0)
    static let verticalControlPoints: (Float, Float, Float, Float) = (0.19919472913616398, 0.010644531250000006, 0.27920937042459737, 0.91025390625)

    static func blobScale(targetWidth: CGFloat, centreDiameter: CGFloat) -> CGFloat {
        return targetWidth / centreDiameter
    }

    static func buttonScale(sourceWidth: CGFloat, targetWidth: CGFloat) -> CGFloat {
        return sourceWidth / targetWidth
    }

    static func scaleTransform(_ scale: CGFloat, size: NSSize) -> CATransform3D {
        return CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1.0), CATransform3DMakeTranslation(size.width * 0.5 * (1.0 - scale), size.height * 0.5 * (1.0 - scale), 0.0))
    }

    static func timingFunction(_ controlPoints: (Float, Float, Float, Float)) -> CAMediaTimingFunction {
        return CAMediaTimingFunction(controlPoints: controlPoints.0, controlPoints.1, controlPoints.2, controlPoints.3)
    }
}

func flightAnimation(keyPath: String, from: Any, to: Any, duration: Double, timingFunction: CAMediaTimingFunction, additive: Bool, removeOnCompletion: Bool = true, completion: (() -> Void)? = nil) -> CABasicAnimation {
    let animation = CABasicAnimation(keyPath: keyPath)
    animation.fromValue = from
    animation.toValue = to
    animation.duration = duration
    animation.timingFunction = timingFunction
    animation.isAdditive = additive
    animation.fillMode = .both
    animation.isRemovedOnCompletion = removeOnCompletion
    if let completion {
        animation.delegate = CALayerAnimationDelegate(completion: { _ in
            completion()
        })
    }
    return animation
}

final class ChatVoiceSendFlight {
    private final class Pending {
        let id: Int
        let overlay: ChatRecorderOverlayView
        let knownStableIds: Set<AnyHashable>

        init(id: Int, overlay: ChatRecorderOverlayView, knownStableIds: Set<AnyHashable>) {
            self.id = id
            self.overlay = overlay
            self.knownStableIds = knownStableIds
        }
    }

    private weak var tableView: TableView?
    private var pending: Pending?
    private var nextId: Int = 0
    private var flyingViews: [NSView] = []

    init(tableView: TableView) {
        self.tableView = tableView
    }

    deinit {
        self.pending?.overlay.removeFromSuperview()
        for view in self.flyingViews {
            view.removeFromSuperview()
        }
    }

    private var reduceMotion: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func launch(overlay: ChatRecorderOverlayView) -> Bool {
        guard !self.reduceMotion, let tableView = self.tableView, let window = tableView.window, overlay.window === window, overlay.superview != nil else {
            return false
        }
        self.cancel()

        var knownStableIds = Set<AnyHashable>()
        tableView.enumerateItems(with: { item in
            if let item = item as? ChatVoiceRowItem, let message = item.message, !message.flags.contains(.Incoming), message.flags.contains(.Unsent) {
                knownStableIds.insert(item.stableId)
            }
            return true
        })

        self.nextId += 1
        let id = self.nextId
        self.pending = Pending(id: id, overlay: overlay, knownStableIds: knownStableIds)
        delay(ChatVoiceSendFlightMotion.handOverTimeout, closure: { [weak self] in
            if let pending = self?.pending, pending.id == id {
                self?.cancel()
            }
        })
        return true
    }

    func cancel() {
        guard let pending = self.pending else {
            return
        }
        self.pending = nil
        let overlay = pending.overlay
        overlay.blobView.stopAnimating()
        guard let layer = overlay.layer, overlay.window != nil else {
            overlay.removeFromSuperview()
            return
        }
        self.flyingViews.append(overlay)
        layer.animateScaleSpring(from: 1.0, to: 0.1, duration: 0.3, removeOnCompletion: false, bounce: false, completion: { [weak self, weak overlay] _ in
            overlay?.removeFromSuperview()
            self?.flyingViews.removeAll(where: { $0 === overlay })
        })
        layer.animateAlpha(from: 1, to: 0, duration: 0.18, timingFunction: .spring, removeOnCompletion: false)
    }

    func tableDidUpdate() {
        guard let pending = self.pending, let tableView = self.tableView else {
            return
        }
        var target: ChatVoiceContentView?
        tableView.enumerateVisibleViews(with: { view in
            guard target == nil, let view = view as? ChatMediaView, let item = view.item as? ChatVoiceRowItem, let message = item.message, !message.flags.contains(.Incoming), message.flags.contains(.Unsent), !pending.knownStableIds.contains(item.stableId), let content = view.contentNode as? ChatVoiceContentView else {
                return
            }
            target = content
        })
        guard let target else {
            return
        }
        self.pending = nil
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.timingFunction = nil
        NSAnimationContext.current.allowsImplicitAnimation = false
        if !self.start(overlay: pending.overlay, target: target, tableView: tableView) {
            self.pending = pending
            self.cancel()
        }
        NSAnimationContext.endGrouping()
    }

    private func start(overlay: ChatRecorderOverlayView, target: ChatVoiceContentView, tableView: TableView) -> Bool {
        let progressView = target.progressView
        guard let host = overlay.superview, let contentView = progressView.superview, host.window === tableView.window else {
            return false
        }
        let blob = overlay.blobView
        let centreDiameter = blob.centreDiameter
        let targetRect = progressView.convert(progressView.bounds, to: host)
        let visibleRect = tableView.convert(tableView.bounds, to: host)
        guard centreDiameter > 0, targetRect.width > 0, visibleRect.contains(NSMakePoint(targetRect.midX, targetRect.midY)) else {
            return false
        }
        let sourceCentre = blob.convert(NSMakePoint(blob.bounds.midX, blob.bounds.midY), to: host)
        let sourceRect = NSMakeRect(sourceCentre.x - centreDiameter / 2, sourceCentre.y - centreDiameter / 2, centreDiameter, centreDiameter)

        let duration = ChatVoiceSendFlightMotion.duration
        let horizontalCurve = ChatVoiceSendFlightMotion.timingFunction(ChatVoiceSendFlightMotion.horizontalControlPoints)
        let verticalCurve = ChatVoiceSendFlightMotion.timingFunction(ChatVoiceSendFlightMotion.verticalControlPoints)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let subviews = contentView.subviews
        let nextSibling = subviews.firstIndex(where: { $0 === progressView }).flatMap { index in
            index + 1 < subviews.count ? subviews[index + 1] : nil
        }
        let originalFrame = progressView.frame
        let container = View(frame: targetRect)
        container.isEventLess = true
        container.backgroundColor = .clear
        container.layer?.masksToBounds = false
        container.layer?.allowsGroupOpacity = true
        host.addSubview(container)
        progressView.removeFromSuperview()
        progressView.setFrameOrigin(.zero)
        container.addSubview(progressView)
        self.flyingViews.append(container)

        if let layer = container.layer {
            let dx = sourceRect.midX - targetRect.midX
            let dy = sourceRect.midY - targetRect.midY
            layer.add(flightAnimation(keyPath: "position", from: NSValue(point: NSMakePoint(dx, 0)), to: NSValue(point: .zero), duration: duration, timingFunction: horizontalCurve, additive: true), forKey: "voiceFlightX")
            layer.add(flightAnimation(keyPath: "position", from: NSValue(point: NSMakePoint(0, dy)), to: NSValue(point: .zero), duration: duration, timingFunction: verticalCurve, additive: true, completion: { [weak self, weak container, weak contentView, weak progressView, weak nextSibling] in
                guard let container else {
                    return
                }
                if let progressView, let contentView {
                    progressView.removeFromSuperview()
                    progressView.frame = originalFrame
                    if let nextSibling, nextSibling.superview === contentView {
                        contentView.addSubview(progressView, positioned: .below, relativeTo: nextSibling)
                    } else {
                        contentView.addSubview(progressView)
                    }
                }
                container.removeFromSuperview()
                self?.flyingViews.removeAll(where: { $0 === container })
            }), forKey: "voiceFlightY")
            let fromScale = ChatVoiceSendFlightMotion.buttonScale(sourceWidth: sourceRect.width, targetWidth: targetRect.width)
            layer.add(flightAnimation(keyPath: "transform", from: NSValue(caTransform3D: ChatVoiceSendFlightMotion.scaleTransform(fromScale, size: targetRect.size)), to: NSValue(caTransform3D: CATransform3DIdentity), duration: duration, timingFunction: verticalCurve, additive: false), forKey: "voiceFlightScale")
            layer.add(flightAnimation(keyPath: "opacity", from: 0.0 as NSNumber, to: 1.0 as NSNumber, duration: ChatVoiceSendFlightMotion.fadeDuration, timingFunction: CAMediaTimingFunction(name: .easeInEaseOut), additive: false), forKey: "voiceFlightAlpha")
        }

        blob.stopAnimating()
        if let layer = overlay.layer {
            let size = overlay.frame.size
            let fromCenter = NSMakePoint(overlay.frame.midX, overlay.frame.midY)
            let toCenter = NSMakePoint(targetRect.midX, targetRect.midY)
            let toScale = ChatVoiceSendFlightMotion.blobScale(targetWidth: targetRect.width, centreDiameter: centreDiameter)
            overlay.setFrameOrigin(NSMakePoint(toCenter.x - size.width / 2, toCenter.y - size.height / 2))
            layer.transform = ChatVoiceSendFlightMotion.scaleTransform(toScale, size: size)
            layer.add(flightAnimation(keyPath: "position", from: NSValue(point: NSMakePoint(fromCenter.x - toCenter.x, 0)), to: NSValue(point: .zero), duration: duration, timingFunction: horizontalCurve, additive: true), forKey: "voiceFlightX")
            layer.add(flightAnimation(keyPath: "position", from: NSValue(point: NSMakePoint(0, fromCenter.y - toCenter.y)), to: NSValue(point: .zero), duration: duration, timingFunction: verticalCurve, additive: true), forKey: "voiceFlightY")
            layer.add(flightAnimation(keyPath: "transform", from: NSValue(caTransform3D: ChatVoiceSendFlightMotion.scaleTransform(1.0, size: size)), to: NSValue(caTransform3D: layer.transform), duration: duration, timingFunction: verticalCurve, additive: false), forKey: "voiceFlightScale")
            layer.allowsGroupOpacity = true
            layer.opacity = 0
            self.flyingViews.append(overlay)
            layer.add(flightAnimation(keyPath: "opacity", from: 1.0 as NSNumber, to: 0.0 as NSNumber, duration: min(ChatVoiceSendFlightMotion.fadeDuration, duration), timingFunction: CAMediaTimingFunction(name: .easeInEaseOut), additive: false, removeOnCompletion: false, completion: { [weak self, weak overlay] in
                overlay?.removeFromSuperview()
                self?.flyingViews.removeAll(where: { $0 === overlay })
            }), forKey: "voiceFlightAlpha")
        } else {
            overlay.removeFromSuperview()
        }

        target.waveformView.animateIn()

        CATransaction.commit()
        return true
    }
}
