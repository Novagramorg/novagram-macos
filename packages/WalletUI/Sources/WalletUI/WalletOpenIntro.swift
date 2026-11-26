import Cocoa

protocol WalletIntroParticipant: AnyObject {
    func prepareIntro()
    func playIntro(at time: CFTimeInterval, pace: Double)
    func cancelIntro()
}

final class WalletOpenIntro {
    private final class Entry {
        weak var participant: WalletIntroParticipant?

        init(_ participant: WalletIntroParticipant) {
            self.participant = participant
        }
    }

    static let maxTransitionWait: Double = 1.0

    private(set) var isPending: Bool
    private(set) var startTime: CFTimeInterval?
    private(set) var pace: Double = 1.0
    private let rollDuration: Double
    private let minimumRollDuration: Double
    private let duration: Double
    private let tail: Double
    private var entries: [Entry] = []
    private var observer: CFRunLoopObserver?

    init(rollDuration: Double, minimumRollDuration: Double, duration: Double, tail: Double = 0) {
        self.rollDuration = rollDuration
        self.minimumRollDuration = minimumRollDuration
        self.duration = duration
        self.tail = tail
        self.isPending = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    deinit {
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    var endTime: CFTimeInterval? {
        return startTime.map { $0 + duration * pace + tail }
    }

    func attach(_ participant: WalletIntroParticipant) {
        entries.removeAll { $0.participant == nil }
        guard !entries.contains(where: { $0.participant === participant }) else {
            return
        }
        entries.append(Entry(participant))
        if isPending {
            participant.prepareIntro()
        } else if let startTime {
            participant.playIntro(at: startTime, pace: pace)
        }
    }

    func begin(with view: NSView, isReady: @escaping () -> Bool) {
        guard isPending, observer == nil else {
            return
        }
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue, false, 1_999_999, { [weak self, weak view] observer, _ in
            if let observer {
                CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
            guard let self else {
                return
            }
            self.observer = nil
            guard let view else {
                return
            }
            view.layoutSubtreeIfNeeded()
            self.start(endingAt: walletPresentationTransitionEnd(of: view), isReady: isReady())
        })
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private func start(endingAt transitionEnd: CFTimeInterval, isReady: Bool) {
        guard isPending else {
            return
        }
        isPending = false
        let participants = entries.compactMap { $0.participant }
        guard isReady else {
            participants.forEach { $0.cancelIntro() }
            return
        }
        let now = CACurrentMediaTime()
        let roll = min(rollDuration, max(minimumRollDuration, transitionEnd - now))
        let time = max(now, transitionEnd - roll)
        pace = roll / rollDuration
        startTime = time
        participants.forEach { $0.playIntro(at: time, pace: pace) }
    }
}

func walletPresentationTransitionEnd(of view: NSView) -> CFTimeInterval {
    let now = CACurrentMediaTime()
    var end = now
    var current: NSView? = view
    while let view = current {
        if let layer = view.layer {
            for key in layer.animationKeys() ?? [] {
                guard let animation = layer.animation(forKey: key), animation.repeatCount == 0, animation.repeatDuration == 0, !animation.autoreverses, animation.speed > 0 else {
                    continue
                }
                let begin = animation.beginTime > 0 ? layer.convertTime(animation.beginTime, to: nil) : now
                let finish = begin + animation.duration / Double(animation.speed)
                end = max(end, finish)
            }
        }
        current = view.superview
    }
    return min(end, now + WalletOpenIntro.maxTransitionWait)
}

final class WalletAddressReveal {
    static let fadeDuration: Double = 0.2
    static let fadeKey = "walletAddressRevealFade"

    let startTime: CFTimeInterval
    private let scrambleDuration: Double
    private let speed: Double
    private var scramble = WalletRecipientAddressScramble()
    private var lastTime: CFTimeInterval?
    private var renderedStep: WalletRecipientAddressRenderStep?

    init(startTime: CFTimeInterval, scrambleDuration: Double, speed: Double = 1.0) {
        self.startTime = startTime
        self.scrambleDuration = scrambleDuration
        self.speed = speed
        self.scramble.beginScramble()
    }

    var isFinished: Bool {
        return scramble.phase == .ready
    }

    func advance(to now: CFTimeInterval) {
        let delta = now - (lastTime ?? now)
        lastTime = now
        guard now >= startTime else {
            return
        }
        if scramble.phase == .loading, now - startTime >= scrambleDuration {
            scramble.beginReveal()
        }
        scramble.advance(by: delta * speed)
    }

    func characters(for text: String, force: Bool = false) -> [(character: Character, isSettled: Bool)]? {
        let step = scramble.renderStep(text)
        guard force || step != renderedStep else {
            return nil
        }
        renderedStep = step
        return scramble.displayedCharacters(text)
    }

    func addFade(to layer: CALayer?) {
        guard let layer else {
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = -1.0
        fade.toValue = 0.0
        fade.isAdditive = true
        fade.duration = WalletAddressReveal.fadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.beginTime = layer.convertTime(startTime, from: nil)
        fade.fillMode = .backwards
        layer.add(fade, forKey: WalletAddressReveal.fadeKey)
    }
}
