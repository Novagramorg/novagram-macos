import Cocoa
import TGUIKit
import SceneEffects

final class ChatRecordingBlobView: View {
    var isFlat: Bool {
        get {
            return self.shapesLayer.isFlat
        } set {
            self.shapesLayer.isFlat = newValue
        }
    }

    var isDarkAppearance: Bool = false {
        didSet {
            self.shapesLayer.isDarkAppearance = self.isDarkAppearance
        }
    }

    var centreDiameter: CGFloat {
        return self.bounds.width * CGFloat(ChatRecordingBlobAppearance.centreScale)
    }

    private let shapesLayer: LiquidGlassShapesLayer
    private let outerBlob: ChatRecordingBlobMotion
    private let middleBlob: ChatRecordingBlobMotion
    private var presence: ChatRecordingBlobPresence
    private var audioLevel: CGFloat = 0.0
    private var presentationAudioLevel: CGFloat = 0.0
    private var isRecording = false

    required init(frame frameRect: NSRect) {
        self.shapesLayer = LiquidGlassShapesLayer(colors: (.white, .white))
        self.outerBlob = ChatRecordingBlobMotion(parameters: ChatRecordingBlobAppearance.waveMotion)
        self.middleBlob = ChatRecordingBlobMotion(parameters: ChatRecordingBlobAppearance.waveMotion)
        self.presence = ChatRecordingBlobPresence(value: ChatRecordingBlobAppearance.restingPresence, easing: ChatRecordingBlobAppearance.easing)

        super.init(frame: frameRect)

        self.isEventLess = true
        self.backgroundColor = .clear
        self.layer?.masksToBounds = false
        self.shapesLayer.source = self
        self.shapesLayer.releasesSurfacesWhenHidden = true
        self.layer?.addSublayer(self.shapesLayer)
        self.updateShapesFrame()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLevel(_ level: CGFloat) {
        let normalizedLevel = min(1.0, max(level / ChatRecordingBlobAppearance.maxLevel, 0.0))
        self.outerBlob.updateSpeedLevel(normalizedLevel)
        self.middleBlob.updateSpeedLevel(normalizedLevel)
        self.audioLevel = normalizedLevel
    }

    func setColor(_ color: NSColor, animated: Bool) {
        self.shapesLayer.updateColors((color, color), animated: animated)
    }

    func startAnimating() {
        if self.isRecording {
            return
        }
        self.isRecording = true
        self.presence.animate(to: 1.0, duration: ChatRecordingBlobAppearance.presenceInDuration)
        self.shapesLayer.isAnimating = true
    }

    func stopAnimating() {
        if !self.isRecording {
            return
        }
        self.isRecording = false
        let canAdvance = self.window != nil
        self.presence.animate(to: ChatRecordingBlobAppearance.restingPresence, duration: ChatRecordingBlobAppearance.presenceOutDuration, canAdvance: canAdvance)
        if !canAdvance {
            self.shapesLayer.isAnimating = false
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if self.window == nil && !self.isRecording {
            self.presence.settle(at: ChatRecordingBlobAppearance.restingPresence)
            self.shapesLayer.isAnimating = false
        }
        self.shapesLayer.isInWindow = self.window != nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        self.updateShapesFrame()
    }

    override func layout() {
        super.layout()
        self.updateShapesFrame()
    }

    private func updateShapesFrame() {
        let overflow = ChatRecordingBlobAppearance.overflow(side: self.bounds.width)
        let shapesFrame = self.bounds.insetBy(dx: -overflow, dy: -overflow)
        if self.shapesLayer.frame != shapesFrame {
            self.shapesLayer.frame = shapesFrame
            self.shapesLayer.updateLayout()
        }
    }
}

extension ChatRecordingBlobView: LiquidGlassShapesSource {
    func liquidGlassShapesAdvance(by deltaTime: CGFloat) {
        let smoothing = pow(ChatRecordingBlobAppearance.levelSmoothing, deltaTime * 60.0)
        self.presentationAudioLevel = self.presentationAudioLevel * smoothing + self.audioLevel * (1.0 - smoothing)
        self.outerBlob.advance(by: deltaTime)
        self.middleBlob.advance(by: deltaTime)
        self.presence.advance(by: Double(deltaTime))
        if !self.isRecording && self.presence.isSettled {
            self.shapesLayer.isAnimating = false
        }
    }

    func liquidGlassShapes(size: CGSize, isFlat: Bool) -> LiquidGlassShapeSet? {
        if self.bounds.width <= 0.0 {
            return nil
        }
        let parameters = ChatRecordingBlobAppearance.radialParameters(
            outer: isFlat ? nil : self.outerBlob,
            middle: isFlat ? nil : self.middleBlob,
            size: Float(self.bounds.width),
            level: self.presentationAudioLevel,
            presence: self.presence.value,
            easing: ChatRecordingBlobAppearance.easing
        )
        return LiquidGlassShapeSet(parameters: parameters, center: SIMD2<Float>(Float(size.width * 0.5), Float(size.height * 0.5)))
    }

    func liquidGlassAppearance(mode: LiquidGlassRenderMode, isDarkAppearance: Bool) -> LiquidGlassShapesAppearance {
        return ChatRecordingBlobAppearance.appearance(mode: mode, isDarkAppearance: isDarkAppearance)
    }
}
