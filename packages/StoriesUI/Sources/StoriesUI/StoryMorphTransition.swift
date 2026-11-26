import Cocoa
import TGUIKit
import AvatarUI

struct StoryMorphEndpoint {
    let shape: StoryMorphShape
    let view: NSView
    let snapshot: CGImage?

    static func resolve(_ control: NSView, in host: NSView) -> StoryMorphEndpoint? {
        guard let window = host.window, control.window === window, !control.isHiddenOrHasHiddenAncestor else {
            return nil
        }
        let view: NSView
        let snapshot: CGImage?
        if let control = control as? AvatarStoryControl {
            view = control.avatar
            snapshot = StoryMorphEndpoint.image(control.avatar.imageContents)
        } else if let control = control as? AvatarControl {
            view = control
            snapshot = StoryMorphEndpoint.image(control.imageContents)
        } else {
            view = control
            snapshot = nil
        }
        let bounds = view.bounds
        guard bounds.width >= 1, bounds.height >= 1 else {
            return nil
        }
        guard StoryMorphEndpoint.visibleFraction(of: view) >= 0.25 else {
            return nil
        }
        let rect = host.convert(bounds, from: view)
        guard rect.intersects(host.bounds) else {
            return nil
        }
        let scale = rect.width / bounds.width
        let cornerRadius: CGFloat
        if let snapshot = snapshot {
            cornerRadius = StoryMorphImageShape.cornerRadius(of: snapshot, displaySize: rect.size) ?? min(rect.width, rect.height) / 2
        } else {
            cornerRadius = (view.layer?.cornerRadius ?? 0) * scale
        }
        let shape = StoryMorphShape(rect: rect, cornerRadius: min(cornerRadius, min(rect.width, rect.height) / 2))
        guard shape.isValid else {
            return nil
        }
        return StoryMorphEndpoint(shape: shape, view: view, snapshot: snapshot)
    }

    static func visibleFraction(of view: NSView) -> CGFloat {
        guard let window = view.window, view.bounds.width > 0, view.bounds.height > 0 else {
            return 0
        }
        let full = view.convert(view.bounds, to: nil)
        var visible = full
        var ancestor = view.superview
        while let current = ancestor, !visible.isNull {
            if current is NSClipView || current.layer?.masksToBounds == true || current === window.contentView {
                visible = visible.intersection(current.convert(current.bounds, to: nil))
            }
            ancestor = current.superview
        }
        if visible.isNull || visible.isEmpty {
            return 0
        }
        return (visible.width * visible.height) / (full.width * full.height)
    }

    private static func image(_ contents: Any?) -> CGImage? {
        guard let contents = contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else {
            return nil
        }
        return (contents as! CGImage)
    }
}

final class StoryMorphHold {
    private struct Entry {
        weak var view: NSView?
        var count: Int
        var alpha: CGFloat
    }
    private static var entries: [ObjectIdentifier: Entry] = [:]

    private weak var view: NSView?
    private let key: ObjectIdentifier
    private var released = false

    static func originalAlpha(of view: NSView) -> CGFloat {
        return self.entries[ObjectIdentifier(view)]?.alpha ?? view.alphaValue
    }

    static func isHeld(_ view: NSView) -> Bool {
        return (self.entries[ObjectIdentifier(view)]?.count ?? 0) > 0
    }

    init(_ view: NSView) {
        self.view = view
        self.key = ObjectIdentifier(view)
        if var entry = StoryMorphHold.entries[self.key], entry.view === view {
            entry.count += 1
            StoryMorphHold.entries[self.key] = entry
        } else {
            StoryMorphHold.entries[self.key] = Entry(view: view, count: 1, alpha: view.alphaValue)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer?.removeAnimation(forKey: StoryMorphHold.fadeKey)
        view.alphaValue = 0
        CATransaction.commit()
    }

    static let fadeKey = "storyMorph.holdFade"

    func release(fadeDuration: Double = 0) {
        guard !self.released else {
            return
        }
        self.released = true
        guard var entry = StoryMorphHold.entries[self.key] else {
            return
        }
        guard entry.view === self.view else {
            if entry.view == nil {
                StoryMorphHold.entries[self.key] = nil
            }
            return
        }
        entry.count -= 1
        if entry.count > 0 {
            StoryMorphHold.entries[self.key] = entry
            return
        }
        StoryMorphHold.entries[self.key] = nil
        guard let view = self.view, entry.view === view else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.alphaValue = entry.alpha
        CATransaction.commit()
        if fadeDuration > 0, entry.alpha > 0, let layer = view.layer {
            storyMorphIsolatedAnimations(duration: fadeDuration) {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 0
                animation.toValue = Float(entry.alpha)
                animation.duration = fadeDuration
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
                animation.fillMode = .both
                layer.add(animation, forKey: StoryMorphHold.fadeKey)
            }
        }
    }

    deinit {
        if !self.released {
            let key = self.key
            let view = self.view
            if var entry = StoryMorphHold.entries[key], entry.view === view {
                entry.count -= 1
                if entry.count > 0 {
                    StoryMorphHold.entries[key] = entry
                } else {
                    StoryMorphHold.entries[key] = nil
                    if let view = view, entry.view === view {
                        view.alphaValue = entry.alpha
                    }
                }
            }
        }
    }
}

func storyMorphIsolatedAnimations(duration: Double, _ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setAnimationDuration(duration)
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
    body()
    CATransaction.commit()
}

final class StoryMorphContentView: View {
    var didAddSubviewHandler: (() -> Void)?

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        self.didAddSubviewHandler?()
    }
}

final class StoryMorphHostView: View {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

final class StoryMorphTransition {
    enum Phase: Equatable {
        case opening
        case open
        case closing
        case closed
    }

    static let animationKeys = ["storyMorph.position", "storyMorph.bounds", "storyMorph.cornerRadius", "storyMorph.opacity", "storyMorph.transform"]

    private static var active: [ObjectIdentifier: StoryMorphTransition] = [:]

    static var activeCount: Int {
        return self.active.count
    }

    #if DEBUG
    static var debugDidRun: ((StoryMorphTransition) -> Void)?
    #endif

    static var activeTransitions: [StoryMorphTransition] {
        return Array(self.active.values)
    }

    private(set) var phase: Phase
    let host: StoryMorphHostView
    let bubble: View
    let snapshotLayer: CALayer
    let snapshotHost: StoryMorphHostView
    let content: NSView
    private let contentSize: CGSize
    private let chrome: () -> [NSView]
    private let targetRadius: CGFloat
    private var restore: ((NSView) -> Void)?

    private(set) var timeline: StoryMorphTimeline?
    private var fades: StoryMorphFades
    private(set) var startTime: CFTimeInterval = 0
    private var generation: Int = 0
    private var hold: StoryMorphHold?
    private var fadedView: NSView?
    private weak var endpointView: NSView?
    private var completion: (() -> Void)?

    var onPhaseCompleted: ((Phase) -> Void)?

    private init(content: NSView, host: StoryMorphHostView, phase: Phase, targetRadius: CGFloat, chrome: @escaping () -> [NSView], restore: ((NSView) -> Void)?) {
        self.content = content
        self.contentSize = content.frame.size
        self.host = host
        self.phase = phase
        self.chrome = chrome
        self.restore = restore
        self.targetRadius = targetRadius
        self.bubble = View(frame: .zero)
        self.bubble.layer?.masksToBounds = true
        self.bubble.backgroundColor = .clear
        self.snapshotHost = StoryMorphHostView(frame: .zero)
        self.snapshotHost.backgroundColor = .clear
        self.snapshotHost.layer?.masksToBounds = false
        self.snapshotLayer = CALayer()
        self.snapshotLayer.anchorPoint = .zero
        self.snapshotLayer.contentsGravity = .resize
        self.snapshotLayer.masksToBounds = true
        self.snapshotLayer.disableActions()
        self.fades = .opening(hasSnapshot: false)
    }

    private static func makeHost(in window: NSWindow) -> StoryMorphHostView? {
        guard let contentView = window.contentView else {
            return nil
        }
        let host = StoryMorphHostView(frame: contentView.bounds)
        host.autoresizingMask = [.width, .height]
        host.backgroundColor = .clear
        host.layer?.masksToBounds = false
        contentView.addSubview(host)
        return host
    }

    static func open(content: NSView, from control: NSView, targetRadius: CGFloat, chrome: @escaping () -> [NSView], restore: @escaping (NSView) -> Void) -> StoryMorphTransition? {
        guard let window = content.window, let home = content.superview, content.frame.width >= 1, content.frame.height >= 1 else {
            return nil
        }
        guard let host = StoryMorphTransition.makeHost(in: window) else {
            return nil
        }
        guard let source = StoryMorphEndpoint.resolve(control, in: host) else {
            host.removeFromSuperview()
            return nil
        }
        let target = StoryMorphShape(rect: host.convert(content.frame, from: home), cornerRadius: targetRadius)
        guard target.isValid else {
            host.removeFromSuperview()
            return nil
        }
        let transition = StoryMorphTransition(content: content, host: host, phase: .opening, targetRadius: targetRadius, chrome: chrome, restore: restore)
        transition.adopt(content: content, rest: target.rect)
        transition.attach(endpoint: source)
        let hasSnapshot = source.snapshot != nil
        let sourceState = source.shape.state(openness: 0)
        let targetState = target.state(openness: 1)
        transition.provisional = (sourceState, StoryMorphFades.opening(hasSnapshot: hasSnapshot).values(openness: 0))
        let landing = StoryMorphTransition.active.values.first { $0.phase == .closing && $0.endpointView === source.view && !$0.isStartPending }
        transition.run(removeOnCompletion: true, prepare: { [weak landing] in
            if let landing = landing, landing.phase == .closing, !landing.isStartPending, let landingPlan = landing.timeline?.plan {
                let t = max(0, CACurrentMediaTime() - landing.startTime)
                let state = landingPlan.state(at: t)
                let velocity = landingPlan.velocity(at: t)
                let current = landing.fades.values(openness: state.openness)
                landing.finish()
                return (StoryMorphPlan(from: state, to: targetState, velocity: velocity, springs: .expand), .opening(hasSnapshot: hasSnapshot, startOpenness: state.openness, start: current))
            }
            return (StoryMorphPlan(from: sourceState, to: targetState, springs: .expand), .opening(hasSnapshot: hasSnapshot))
        })
        return transition
    }

    static func close(content: NSView, to control: NSView?, targetRadius: CGFloat, chrome: @escaping () -> [NSView], completion: @escaping () -> Void) -> StoryMorphTransition? {
        guard let window = content.window, let home = content.superview, content.frame.width >= 1, content.frame.height >= 1 else {
            return nil
        }
        guard let host = StoryMorphTransition.makeHost(in: window) else {
            return nil
        }
        let rest = StoryMorphShape(rect: host.convert(content.frame, from: home), cornerRadius: targetRadius)
        guard rest.isValid else {
            host.removeFromSuperview()
            return nil
        }
        let transition = StoryMorphTransition(content: content, host: host, phase: .closing, targetRadius: targetRadius, chrome: chrome, restore: nil)
        transition.adopt(content: content, rest: rest.rect)
        let restState = rest.state(openness: 1)
        transition.beginClose(to: control, completion: completion, start: {
            return (restState, .zero, StoryMorphFades.Values(snapshot: 0, chrome: 1, bubble: 1, source: 0))
        })
        return transition
    }

    func close(to control: NSView?, completion: @escaping () -> Void) {
        switch self.phase {
        case .open, .closing, .closed:
            completion()
            return
        case .opening:
            break
        }
        let openPlan = self.isStartPending ? nil : self.timeline?.plan
        let openStart = self.startTime
        let openFades = self.fades
        let provisional = self.provisional
        let previousFaded = self.fadedView
        let restState = StoryMorphShape(rect: self.bubble.frame, cornerRadius: self.targetRadius).state(openness: 1)
        self.cancelPendingStart()
        self.generation += 1
        self.phase = .closing
        self.restore = nil
        self.beginClose(to: control, completion: completion, start: {
            previousFaded?.layer?.removeAnimation(forKey: "storyMorph.opacity")
            if let openPlan = openPlan {
                let t = max(0, CACurrentMediaTime() - openStart)
                let state = openPlan.state(at: t)
                return (state, openPlan.velocity(at: t), openFades.values(openness: state.openness))
            }
            if let provisional = provisional {
                return (provisional.0, .zero, provisional.1)
            }
            return (restState, .zero, StoryMorphFades.Values(snapshot: 0, chrome: 1, bubble: 1, source: 0))
        })
    }

    func finish() {
        guard self.phase == .opening || self.phase == .closing else {
            return
        }
        self.complete(generation: self.generation)
    }

    private func beginClose(to control: NSView?, completion: @escaping () -> Void, start: @escaping () -> (StoryMorphState, StoryMorphVelocity, StoryMorphFades.Values)) {
        self.completion = completion
        let previousHold = self.hold
        self.hold = nil
        self.fadedView = nil
        self.endpointView = nil

        let destination = control.flatMap { StoryMorphEndpoint.resolve($0, in: self.host) }
        if let destination = destination {
            self.attach(endpoint: destination)
        }
        previousHold?.release(fadeDuration: 0.2)

        let hasSnapshot = destination?.snapshot != nil
        let hasDestination = destination != nil
        let destinationState = destination?.shape.state(openness: 0)
        self.run(removeOnCompletion: false, prepare: {
            let (state, velocity, current) = start()
            let targetState: StoryMorphState
            if let destinationState = destinationState {
                targetState = destinationState
            } else {
                let rect = state.rect
                let shrunk = CGRect(x: rect.midX - rect.width * 0.45, y: rect.midY - rect.height * 0.45, width: rect.width * 0.9, height: rect.height * 0.9)
                targetState = StoryMorphState(center: CGPoint(x: shrunk.midX, y: shrunk.midY), size: shrunk.size, roundness: state.roundness, openness: 0)
            }
            let fades = StoryMorphFades.closing(hasSnapshot: hasSnapshot, hasDestination: hasDestination, startOpenness: state.openness, start: current)
            return (StoryMorphPlan(from: state, to: targetState, velocity: velocity, springs: .collapse), fades)
        })
    }

    private func adopt(content: NSView, rest: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.host.addSubview(self.bubble)
        self.bubble.frame = rest
        self.bubble.addSubview(content)
        content.frame = CGRect(origin: .zero, size: self.contentSize)
        content.alphaValue = 1
        self.bubble.addSubview(self.snapshotHost)
        self.snapshotHost.frame = CGRect(origin: .zero, size: rest.size)
        self.snapshotHost.layer?.addSublayer(self.snapshotLayer)
        self.snapshotLayer.frame = CGRect(origin: .zero, size: rest.size)
        self.snapshotLayer.opacity = 0
        CATransaction.commit()
    }

    private func attach(endpoint: StoryMorphEndpoint) {
        self.snapshotLayer.contents = endpoint.snapshot
        self.snapshotLayer.contentsScale = self.host.window?.backingScaleFactor ?? 2.0
        self.hold = StoryMorphHold(endpoint.view)
        self.endpointView = endpoint.view
        self.fadedView = endpoint.snapshot == nil ? endpoint.view : nil
    }

    private var provisional: (StoryMorphState, StoryMorphFades.Values)?

    private func run(removeOnCompletion: Bool, prepare: @escaping () -> (StoryMorphPlan, StoryMorphFades)) {
        StoryMorphTransition.active[ObjectIdentifier(self)] = self
        self.generation += 1
        let generation = self.generation
        self.startTime = CACurrentMediaTime()
        self.cancelPendingStart()
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue, false, 1_999_999, { [weak self] _, _ in
            guard let self = self else {
                return
            }
            self.cancelPendingStart()
            guard generation == self.generation else {
                return
            }
            let (plan, fades) = prepare()
            guard generation == self.generation else {
                return
            }
            self.begin(plan: plan, fades: fades, generation: generation, removeOnCompletion: removeOnCompletion)
        })
        self.pendingStart = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        DispatchQueue.main.asyncAfter(deadline: .now() + StoryMorphSampling.maximumDuration + 1.0, execute: { [weak self] in
            self?.complete(generation: generation)
        })
    }

    private func begin(plan: StoryMorphPlan, fades: StoryMorphFades, generation: Int, removeOnCompletion: Bool) {
        self.fades = fades
        let timeline = StoryMorphTimeline(plan: plan, contentSize: self.contentSize, fades: fades)
        self.timeline = timeline
        self.provisional = nil
        self.removeAnimations()

        let last = timeline.samples[timeline.samples.count - 1]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.bubble.frame = last.geometry.bubble
        self.snapshotHost.frame = CGRect(origin: .zero, size: last.geometry.bubble.size)
        self.bubble.layer?.cornerRadius = last.geometry.cornerRadius
        self.snapshotLayer.frame = last.geometry.snapshotFrame
        self.snapshotLayer.opacity = Float(last.fades.snapshot)
        if removeOnCompletion {
            self.bubble.layer?.opacity = Float(last.fades.bubble)
        }
        CATransaction.commit()

        guard plan.duration > 0, timeline.samples.count > 1 else {
            self.complete(generation: generation)
            return
        }
        self.startAnimations(timeline: timeline, generation: generation, removeOnCompletion: removeOnCompletion)
    }

    private var pendingStart: CFRunLoopObserver?

    var isStartPending: Bool {
        return self.pendingStart != nil
    }

    private func cancelPendingStart() {
        if let observer = self.pendingStart {
            self.pendingStart = nil
            CFRunLoopObserverInvalidate(observer)
        }
    }

    private func startAnimations(timeline: StoryMorphTimeline, generation: Int, removeOnCompletion: Bool) {
        let plan = timeline.plan
        self.startTime = CACurrentMediaTime()
        let chromeViews = self.chrome()
        let keyTimes = timeline.keyTimes
        let samples = timeline.samples
        let duration = plan.duration

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))

        func add(_ layer: CALayer?, _ keyPath: String, _ values: [Any], key: String, delegate: CAAnimationDelegate? = nil) {
            guard let layer = layer else {
                return
            }
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = keyTimes
            animation.duration = duration
            animation.calculationMode = .linear
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.beginTime = layer.convertTime(self.startTime, from: nil)
            animation.fillMode = .both
            animation.isRemovedOnCompletion = removeOnCompletion
            animation.delegate = delegate
            layer.add(animation, forKey: key)
        }

        let bubbleLayer = self.bubble.layer
        let bubbleAnchor = bubbleLayer?.anchorPoint ?? .zero
        let contentLayer = self.content.layer
        let contentAnchor = contentLayer?.anchorPoint ?? .zero
        let contentSize = self.contentSize

        let completionDelegate = CALayerAnimationDelegate(completion: { [weak self] _ in
            self?.complete(generation: generation)
        })

        add(bubbleLayer, "position", samples.map { NSValue(point: NSPoint(x: $0.geometry.bubble.minX + bubbleAnchor.x * $0.geometry.bubble.width, y: $0.geometry.bubble.minY + bubbleAnchor.y * $0.geometry.bubble.height)) }, key: "storyMorph.position", delegate: completionDelegate)
        add(bubbleLayer, "bounds", samples.map { NSValue(rect: CGRect(origin: .zero, size: $0.geometry.bubble.size)) }, key: "storyMorph.bounds")
        add(bubbleLayer, "cornerRadius", samples.map { NSNumber(value: Double($0.geometry.cornerRadius)) }, key: "storyMorph.cornerRadius")
        add(bubbleLayer, "opacity", samples.map { NSNumber(value: Double($0.fades.bubble)) }, key: "storyMorph.opacity")

        add(contentLayer, "position", samples.map { sample -> NSValue in
            let frame = sample.geometry.contentFrame
            let scale = sample.geometry.contentScale
            return NSValue(point: NSPoint(x: frame.minX + contentAnchor.x * contentSize.width * scale, y: frame.minY + contentAnchor.y * contentSize.height * scale))
        }, key: "storyMorph.position")
        add(contentLayer, "transform", samples.map { NSValue(caTransform3D: CATransform3DMakeScale($0.geometry.contentScale, $0.geometry.contentScale, 1)) }, key: "storyMorph.transform")

        add(self.snapshotLayer, "position", samples.map { NSValue(point: $0.geometry.snapshotFrame.origin) }, key: "storyMorph.position")
        add(self.snapshotLayer, "bounds", samples.map { NSValue(rect: CGRect(origin: .zero, size: $0.geometry.snapshotFrame.size)) }, key: "storyMorph.bounds")
        add(self.snapshotLayer, "opacity", samples.map { NSNumber(value: Double($0.fades.snapshot)) }, key: "storyMorph.opacity")

        self.animatedChrome = []
        self.syncChrome(chromeViews)

        if let faded = self.fadedView {
            let alpha = Double(StoryMorphHold.originalAlpha(of: faded))
            add(faded.layer, "opacity", samples.map { NSNumber(value: alpha * Double($0.fades.source)) }, key: "storyMorph.opacity")
        }

        #if DEBUG
        StoryMorphTransition.debugDidRun?(self)
        #endif
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.3, execute: { [weak self] in
            self?.complete(generation: generation)
        })
    }

    private var animatedChrome: [WeakReference<NSView>] = []

    func syncChrome() {
        self.syncChrome(self.chrome())
    }

    private func syncChrome(_ views: [NSView]) {
        guard self.pendingStart == nil, self.phase == .opening || self.phase == .closing, let timeline = self.timeline, timeline.plan.duration > 0, timeline.samples.count > 1 else {
            return
        }
        let animated = Set(self.animatedChrome.compactMap { $0.value.map(ObjectIdentifier.init) })
        let fresh = views.filter { !animated.contains(ObjectIdentifier($0)) }
        guard !fresh.isEmpty else {
            return
        }
        let begin = self.startTime
        storyMorphIsolatedAnimations(duration: timeline.plan.duration) {
            for view in fresh {
                guard let layer = view.layer else {
                    continue
                }
                let alpha = Double(layer.opacity)
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = timeline.samples.map { NSNumber(value: alpha * Double($0.fades.chrome)) }
                animation.keyTimes = timeline.keyTimes
                animation.duration = timeline.plan.duration
                animation.calculationMode = .linear
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                animation.beginTime = layer.convertTime(begin, from: nil)
                animation.fillMode = .both
                animation.isRemovedOnCompletion = self.restore != nil || self.phase == .opening
                layer.add(animation, forKey: "storyMorph.opacity")
                self.animatedChrome.append(WeakReference(value: view))
            }
        }
    }

    private func removeAnimations() {
        let layers: [CALayer?] = [self.bubble.layer, self.content.layer, self.snapshotLayer, self.fadedView?.layer] + self.animatedChrome.map { $0.value?.layer }
        for layer in layers {
            for key in StoryMorphTransition.animationKeys {
                layer?.removeAnimation(forKey: key)
            }
        }
    }

    private func complete(generation: Int) {
        guard generation == self.generation, self.phase == .opening || self.phase == .closing else {
            return
        }
        self.generation += 1
        let finishedPhase = self.phase
        self.cancelPendingStart()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.removeAnimations()
        switch finishedPhase {
        case .opening:
            self.phase = .open
            if let restore = self.restore {
                self.restore = nil
                restore(self.content)
            }
            self.host.removeFromSuperview()
            self.hold?.release(fadeDuration: 0.2)
            self.hold = nil
            self.fadedView = nil
        case .closing:
            self.phase = .closed
            self.host.removeFromSuperview()
            self.hold?.release()
            self.hold = nil
            self.fadedView = nil
        default:
            break
        }
        CATransaction.commit()
        let completion = self.completion
        self.completion = nil
        completion?()
        self.onPhaseCompleted?(self.phase)
        StoryMorphTransition.active[ObjectIdentifier(self)] = nil
    }
}
