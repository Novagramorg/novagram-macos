import Cocoa
import TGUIKit
import InAppSettings

final class ChatInputRecordModeIcon: View {
    private struct Vertex {
        let point: CGPoint
        let inTangent: CGPoint
        let outTangent: CGPoint

        init(_ x: CGFloat, _ y: CGFloat, in inX: CGFloat, _ inY: CGFloat, out outX: CGFloat, _ outY: CGFloat) {
            self.point = CGPoint(x: x, y: y)
            self.inTangent = CGPoint(x: inX, y: inY)
            self.outTangent = CGPoint(x: outX, y: outY)
        }
    }

    private struct Pose {
        let scale: CGFloat
        let opacity: CGFloat
        let blur: CGFloat
    }

    static let canvasSize = NSMakeSize(30, 30)
    private static let center = CGPoint(x: 15, y: 15)
    private static let stemTop = CGPoint(x: 15, y: 23)
    private static let stemBottom = CGPoint(x: 15, y: 27)
    private static let micRect = CGRect(x: 10.5, y: 4, width: 9, height: 15)
    private static let lensRect = CGRect(x: 10, y: 10, width: 10, height: 10)
    private static let voiceHolderStart: CGFloat = 0.2533
    private static let voiceHolderEnd: CGFloat = 0.7463
    private static let lineWidth: CGFloat = 1.2
    private static let springStiffness: CGFloat = 555.027
    private static let springDamping: CGFloat = 47.118
    private static let shown = Pose(scale: 1, opacity: 1, blur: 0)
    private static let replaced = Pose(scale: 0.5, opacity: 0, blur: 5)
    private static let blurKeyPath = "filters.gaussianBlur.inputRadius"
    private static let transitionKey = "replace"

    private static let voiceHolder: [Vertex] = [
        Vertex(0, -9, in: 2.884, 0, out: -2.884, 0),
        Vertex(-5.438, -8.464, in: 1.112, -0.536, out: -1.104, 0.532),
        Vertex(-7.964, -5.938, in: 0.532, -1.104, out: -0.536, 1.112),
        Vertex(-8.5, -0.5, in: 0, -2.884, out: 0, 1.993),
        Vertex(-7.205, 4.052, in: -0.63, -1.057, out: 0.63, 1.057),
        Vertex(-4.586, 6.672, in: -0.829, -0.535, out: 0.829, 0.535),
        Vertex(0, 8, in: -2.458, 0, out: 2.458, 0),
        Vertex(4.614, 6.672, in: -0.793, 0.482, out: 0.793, -0.482),
        Vertex(7.19, 4.052, in: -0.351, 0.627, out: 0.351, -0.627),
        Vertex(8.5, -0.5, in: 0, 2.43, out: 0, -2.884),
        Vertex(7.964, -5.938, in: 0.536, 1.112, out: -0.532, -1.104),
        Vertex(5.438, -8.464, in: 1.104, 0.532, out: -1.112, -0.536)
    ]

    private static let videoHolder: [Vertex] = [
        Vertex(0, -11, in: 3.732, 0, out: -3.732, 0),
        Vertex(-7.037, -10.307, in: 1.439, -0.693, out: -1.429, 0.688),
        Vertex(-10.307, -7.037, in: 0.688, -1.429, out: -0.693, 1.439),
        Vertex(-11, 0, in: 0, -3.732, out: 0, 3.732),
        Vertex(-10.307, 7.037, in: -0.693, -1.439, out: 0.688, 1.429),
        Vertex(-7.037, 10.307, in: -1.429, -0.688, out: 1.439, 0.693),
        Vertex(0, 11, in: -3.732, 0, out: 3.732, 0),
        Vertex(7.037, 10.307, in: -1.439, 0.693, out: 1.429, -0.688),
        Vertex(10.307, 7.037, in: -0.688, 1.429, out: 0.693, -1.439),
        Vertex(11, 0, in: 0, 3.732, out: 0, -3.732),
        Vertex(10.307, -7.037, in: 0.693, 1.439, out: -0.688, -1.429),
        Vertex(7.037, -10.307, in: 1.429, 0.688, out: -1.439, -0.693)
    ]

    private let voiceGlyph = CALayer()
    private let videoGlyph = CALayer()
    private let voiceHolderShape = CAShapeLayer()
    private let voiceBodyShape = CAShapeLayer()
    private let videoShape = CAShapeLayer()
    private var state: RecordingStateSettings?

    private var shapes: [CAShapeLayer] {
        return [voiceHolderShape, voiceBodyShape, videoShape]
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
        layer?.masksToBounds = false

        let voiceBodyPath = CGMutablePath()
        voiceBodyPath.addRoundedRect(in: ChatInputRecordModeIcon.micRect, cornerWidth: ChatInputRecordModeIcon.micRect.width / 2, cornerHeight: ChatInputRecordModeIcon.micRect.width / 2)
        voiceBodyPath.move(to: ChatInputRecordModeIcon.stemBottom)
        voiceBodyPath.addLine(to: ChatInputRecordModeIcon.stemTop)
        voiceBodyShape.path = voiceBodyPath

        voiceHolderShape.path = ChatInputRecordModeIcon.path(ChatInputRecordModeIcon.voiceHolder)
        voiceHolderShape.strokeStart = ChatInputRecordModeIcon.voiceHolderStart
        voiceHolderShape.strokeEnd = ChatInputRecordModeIcon.voiceHolderEnd

        let videoPath = CGMutablePath()
        videoPath.addPath(ChatInputRecordModeIcon.path(ChatInputRecordModeIcon.videoHolder))
        videoPath.addEllipse(in: ChatInputRecordModeIcon.lensRect)
        videoShape.path = videoPath

        for (glyph, glyphShapes) in [(voiceGlyph, [voiceHolderShape, voiceBodyShape]), (videoGlyph, [videoShape])] {
            glyph.frame = ChatInputRecordModeIcon.canvasSize.bounds
            for shape in glyphShapes {
                shape.frame = ChatInputRecordModeIcon.canvasSize.bounds
                shape.fillColor = nil
                shape.lineWidth = ChatInputRecordModeIcon.lineWidth
                shape.lineCap = .round
                shape.contentsScale = System.backingScale
                glyph.addSublayer(shape)
            }
            layer?.addSublayer(glyph)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? System.backingScale
        for shape in shapes {
            shape.contentsScale = scale
        }
    }

    func update(state: RecordingStateSettings, color: NSColor, animated: Bool) {
        let previous = self.state
        self.state = state

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in shapes {
            shape.strokeColor = color.cgColor
        }
        if previous != state {
            let animated = animated && previous != nil
            apply(state == .voice ? ChatInputRecordModeIcon.shown : ChatInputRecordModeIcon.replaced, to: voiceGlyph, animated: animated)
            apply(state == .video ? ChatInputRecordModeIcon.shown : ChatInputRecordModeIcon.replaced, to: videoGlyph, animated: animated)
        }
        CATransaction.commit()
    }

    private func apply(_ pose: Pose, to glyph: CALayer, animated: Bool) {
        let current = ChatInputRecordModeIcon.visiblePose(of: glyph)

        glyph.transform = CATransform3DMakeScale(pose.scale, pose.scale, 1)
        glyph.opacity = Float(pose.opacity)

        guard animated, let blur = ee2_makeBlurFilter() else {
            glyph.removeAnimation(forKey: ChatInputRecordModeIcon.transitionKey)
            glyph.filters = nil
            return
        }
        blur.setValue(pose.blur as NSNumber, forKey: "inputRadius")
        glyph.filters = [blur]

        let animations = [
            ChatInputRecordModeIcon.spring("transform.scale", from: current.scale, to: pose.scale),
            ChatInputRecordModeIcon.spring("opacity", from: current.opacity, to: pose.opacity),
            ChatInputRecordModeIcon.spring(ChatInputRecordModeIcon.blurKeyPath, from: current.blur, to: pose.blur)
        ]
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = animations.map(\.duration).max() ?? 0
        group.completion = { [weak glyph] finished in
            if finished {
                glyph?.filters = nil
            }
        }
        glyph.add(group, forKey: ChatInputRecordModeIcon.transitionKey)
    }

    private static func visiblePose(of glyph: CALayer) -> Pose {
        let source = glyph.animation(forKey: transitionKey) != nil ? (glyph.presentation() ?? glyph) : glyph
        let progress = max(0, min(1, CGFloat(source.opacity)))
        func value(_ hidden: CGFloat, _ visible: CGFloat) -> CGFloat {
            return hidden + (visible - hidden) * progress
        }
        return Pose(scale: value(replaced.scale, shown.scale), opacity: progress, blur: value(replaced.blur, shown.blur))
    }

    private static func spring(_ keyPath: String, from: CGFloat, to: CGFloat) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = springStiffness
        animation.damping = springDamping
        animation.fromValue = from as NSNumber
        animation.toValue = to as NSNumber
        animation.duration = animation.settlingDuration
        return animation
    }

    private static func path(_ vertices: [Vertex]) -> CGPath {
        let path = CGMutablePath()
        func point(_ vertex: CGPoint, _ tangent: CGPoint = .zero) -> CGPoint {
            return CGPoint(x: center.x + vertex.x + tangent.x, y: center.y + vertex.y + tangent.y)
        }
        path.move(to: point(vertices[0].point))
        for index in vertices.indices {
            let from = vertices[index]
            let to = vertices[(index + 1) % vertices.count]
            path.addCurve(to: point(to.point), control1: point(from.point, from.outTangent), control2: point(to.point, to.inTangent))
        }
        path.closeSubpath()
        return path
    }
}
