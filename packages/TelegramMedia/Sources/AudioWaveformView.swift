import Cocoa
import TGUIKit

fileprivate final class AudioWaveformDrawingSamples {
    struct Prepared {
        let peaks: [UInt16]
        let inverseScale: CGFloat
    }

    private var waveform: AudioWaveform?
    private var prepared: Prepared?

    func reset() {
        waveform = nil
        prepared = nil
    }

    func prepare(_ waveform: AudioWaveform, count: Int) -> Prepared {
        if self.waveform === waveform, let prepared, prepared.peaks.count == count {
            return prepared
        }
        var peaks = [UInt16](repeating: 0, count: count)
        var maximum: UInt16 = 0
        waveform.samples.withUnsafeBytes { (samples: UnsafePointer<UInt16>) -> Void in
            let sourceCount = waveform.samples.count / 2
            for index in 0 ..< sourceCount {
                let sample = samples[index]
                maximum = max(maximum, sample)
                let bucket = index * count / sourceCount
                peaks[bucket] = max(peaks[bucket], sample)
            }
        }
        let prepared = Prepared(peaks: peaks, inverseScale: 1.0 / max(1.0, CGFloat(maximum)))
        self.waveform = waveform
        self.prepared = prepared
        return prepared
    }
}

fileprivate class AudioWaveformContainerView : SimpleLayer {
    private let drawingSamples: AudioWaveformDrawingSamples

    var color:NSColor = .accent {
        didSet {
            if color != oldValue {
                self.setNeedsDisplay()
            }
        }
    }
    var waveform:AudioWaveform? {
        didSet {
            if waveform !== oldValue {
                drawingSamples.reset()
            }
            if waveform != oldValue {
                self.setNeedsDisplay()
            }
        }
    }
    var peakHeight:CGFloat = 12
    var revealProgress: CGFloat = 1.0 {
        didSet {
            if revealProgress != oldValue {
                self.setNeedsDisplay()
            }
        }
    }
    init(frame frameRect: NSRect, drawingSamples: AudioWaveformDrawingSamples) {
        self.drawingSamples = drawingSamples
        super.init()
        self.frame = frameRect
        self.needsDisplayOnBoundsChange = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(layer: Any) {
        self.drawingSamples = AudioWaveformDrawingSamples()
        super.init()
        self.needsDisplayOnBoundsChange = true
    }
    
    override func draw(in ctx: CGContext) {
        
        let sampleWidth:CGFloat = 2
        let halfSampleWidth:CGFloat = 1
        let distance:CGFloat = 2
        let size = frame.size
        
        ctx.setFillColor(color.cgColor)
        
        if let waveform = waveform {

            
            guard size.width.isFinite, size.width >= sampleWidth + distance else {
                return
            }
            let numSamples = Int(floor(size.width / (sampleWidth + distance)))
            let samples = drawingSamples.prepare(waveform, count: numSamples)
            let peakHeight: CGFloat = 12.0
            let invScale = samples.inverseScale

            let commonRevealFraction = listViewAnimationCurveSystem(self.revealProgress)

            for i in 0 ..< numSamples {
                let offset = CGFloat(i) * (sampleWidth + distance)
                let peakSample = samples.peaks[i]

                var sampleHeight = CGFloat(peakSample) * peakHeight * invScale
                if abs(sampleHeight) > peakHeight {
                    sampleHeight = peakHeight
                }

                let startFraction = CGFloat(i) / CGFloat(numSamples)
                if startFraction < commonRevealFraction {
                    sampleHeight *= max(0.0, min(1.0, (commonRevealFraction - startFraction) / (1.0 - startFraction)))
                } else {
                    sampleHeight = 0.0
                }

                let adjustedSampleHeight = sampleHeight - sampleWidth * 1.5
                if adjustedSampleHeight.isLessThanOrEqualTo(sampleWidth) {
                    ctx.fillEllipse(in: CGRect(x: offset, y: size.height - sampleWidth, width: sampleWidth, height: sampleWidth))
                } else {
                    let adjustedRect = CGRect(x: offset, y: size.height - adjustedSampleHeight, width: sampleWidth, height: adjustedSampleHeight - halfSampleWidth)
                    ctx.fillEllipse(in: CGRect(x: adjustedRect.minX, y: adjustedRect.minY - halfSampleWidth, width: sampleWidth, height: sampleWidth))
                    ctx.fillEllipse(in: CGRect(x: adjustedRect.minX, y: adjustedRect.maxY - halfSampleWidth, width: sampleWidth, height: sampleWidth))
                    ctx.fill(adjustedRect)
                }
            }
        } else {
            
            ctx.fill(NSMakeRect(halfSampleWidth, size.height - sampleWidth, size.width - sampleWidth, sampleWidth))
            ctx.fillEllipse(in: NSMakeRect(0.0, size.height - sampleWidth, sampleWidth, sampleWidth))
            ctx.fillEllipse(in: NSMakeRect(size.width - sampleWidth, size.height - sampleWidth, sampleWidth, sampleWidth))
            
  
        }
    }
    
}

public class AudioWaveformView: View {
    private let foregroundView:AudioWaveformContainerView
    private let backgroundView:AudioWaveformContainerView
    private let foregroundClippingLayer: SimpleLayer
    
    var peakHeight:CGFloat = 12 {
        didSet {
            foregroundView.peakHeight = peakHeight
            backgroundView.peakHeight = peakHeight
        }
    }
    
    public var waveform:AudioWaveform? {
        didSet {
            foregroundView.waveform = waveform
            backgroundView.waveform = waveform
        }
    }
    
    public required init(frame frameRect: NSRect) {
        let drawingSamples = AudioWaveformDrawingSamples()
        foregroundView = AudioWaveformContainerView(frame: NSMakeRect(0,0,frameRect.width,frameRect.height), drawingSamples: drawingSamples)
        backgroundView = AudioWaveformContainerView(frame: NSMakeRect(0,0,frameRect.width,frameRect.height), drawingSamples: drawingSamples)
        foregroundClippingLayer = SimpleLayer()
        foregroundClippingLayer.anchorPoint = .zero
        foregroundClippingLayer.position = .zero
        foregroundClippingLayer.bounds = CGRect(origin: .zero, size: CGSize(width: max(0, frameRect.width), height: max(0, frameRect.height)))
        foregroundClippingLayer.masksToBounds = true
        super.init(frame: frameRect)
        
        self.layer?.addSublayer(backgroundView)
        
        foregroundClippingLayer.addSublayer(foregroundView)
        self.layer?.addSublayer(foregroundClippingLayer)
    }

    public func updateForegroundClip(size: NSSize, animated: Bool) {
        let size = NSSize(width: max(0, size.width), height: max(0, size.height))
        let target = CGRect(origin: .zero, size: size)
        if !animated {
            foregroundClippingLayer.removeAnimation(forKey: "bounds")
            if foregroundClippingLayer.bounds != target {
                foregroundClippingLayer.bounds = target
            }
        } else if foregroundClippingLayer.bounds != target {
            var previous = foregroundClippingLayer.bounds
            if foregroundClippingLayer.animation(forKey: "bounds") != nil,
               let presentation = foregroundClippingLayer.presentation() {
                previous.size = presentation.bounds.size
            }
            if previous == target {
                foregroundClippingLayer.removeAnimation(forKey: "bounds")
            } else {
                foregroundClippingLayer.animateBounds(from: previous, to: target, duration: 0.2, timingFunction: .easeOut)
            }
            foregroundClippingLayer.bounds = target
        }
    }
    
    public override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    public override func layout() {
        super.layout()
        foregroundView.frame = self.bounds
        backgroundView.frame = self.bounds

    }
    
    public func set(foregroundColor:NSColor, backgroundColor:NSColor) {
        self.foregroundView.color = foregroundColor
        self.backgroundView.color = backgroundColor
    }

    private var revealAnimator: DisplayLinkAnimator?

    public func animateIn() {
        guard self.revealAnimator == nil else {
            return
        }
        let delay: CGFloat = 0.08
        let duration: CGFloat = 0.8
        self.updateRevealProgress(0.0)
        self.revealAnimator = DisplayLinkAnimator(duration: Double(delay + duration), from: 0.0, to: delay + duration, timingFunction: CAMediaTimingFunction(name: .linear), update: { [weak self] elapsed in
            self?.updateRevealProgress(max(0.0, min(1.0, (elapsed - delay) / duration)))
        }, completion: { [weak self] in
            self?.updateRevealProgress(1.0)
            self?.revealAnimator = nil
        })
    }

    private func updateRevealProgress(_ progress: CGFloat) {
        self.foregroundView.revealProgress = progress
        self.backgroundView.revealProgress = progress
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}



private class DrawingLayer : SimpleLayer {
    var color: NSColor = .black
    var particles: [ContentParticle] = [] {
        didSet {
            setNeedsDisplay()
        }
    }

    override func draw(in context: CGContext) {
        super.draw(in: context)
        
        context.setFillColor(self.color.cgColor)
        
        for particle in self.particles {
            let size: CGFloat = 1.4
            context.setAlpha(particle.alpha * 1.0)
            context.fillEllipse(in: CGRect(origin: CGPoint(x: particle.position.x - size / 2.0, y: particle.position.y - size / 2.0), size: CGSize(width: size, height: size)))
        }
    }
}

public class SparksView: View {
    private var particles: [ContentParticle] = []
    private var color: NSColor = .black
    private let drawingLayer = DrawingLayer()
    public required init(frame: CGRect) {
        super.init(frame: frame)
        drawingLayer.frame = bounds
        self.layer?.addSublayer(drawingLayer)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var presentationSampleHeight: CGFloat = 0.0
    private var sampleHeight: CGFloat = 0.0
    private var lastUpdateTimestamp: Double?
    private var pendingParticles: CGFloat = 0
    
    public func update(position: CGPoint, sampleHeight: CGFloat, color: NSColor) {
        self.color = color
        self.drawingLayer.color = color
        
    
        let timestamp = CACurrentMediaTime()
        let dt = CGFloat(min(1.0 / 20.0, max(0, timestamp - (self.lastUpdateTimestamp ?? timestamp - 1.0 / 60.0))))
        self.lastUpdateTimestamp = timestamp

        self.sampleHeight = sampleHeight
        let decay = FrameStep.decay(0.9, dt)
        self.presentationSampleHeight = self.presentationSampleHeight * decay + self.sampleHeight * (1 - decay)
        
        let v = CGPoint(x: 1.0, y: 0.0)
        let c = CGPoint(x: position.x - 4.0, y: position.y + 1.0 - self.presentationSampleHeight * CGFloat(arc4random_uniform(100)) / 100.0)
        
        var removeIndices: [Int] = []
        for i in 0 ..< self.particles.count {
            let currentTime = timestamp - self.particles[i].beginTime
            if currentTime > self.particles[i].lifetime {
                removeIndices.append(i)
            } else {
                let input: CGFloat = CGFloat(currentTime / self.particles[i].lifetime)
                let decelerated: CGFloat = (1.0 - (1.0 - input) * (1.0 - input))
                self.particles[i].alpha = 1.0 - decelerated
                
                var p = self.particles[i].position
                let d = self.particles[i].direction
                let v = self.particles[i].velocity
                p = CGPoint(x: p.x + d.x * v * dt, y: p.y + d.y * v * dt)
                self.particles[i].position = p
            }
        }
        
        for i in removeIndices.reversed() {
            self.particles.remove(at: i)
        }
        
        self.pendingParticles += 3 * FrameStep.scale(dt)
        let newParticleCount = Int(self.pendingParticles)
        self.pendingParticles -= CGFloat(newParticleCount)
        for _ in 0 ..< newParticleCount {
            let degrees: CGFloat = CGFloat(arc4random_uniform(100)) - 65.0
            let angle: CGFloat = degrees * CGFloat.pi / 180.0
            
            let direction = CGPoint(x: v.x * cos(angle) - v.y * sin(angle), y: v.x * sin(angle) + v.y * cos(angle))
            let velocity = (80.0 + (CGFloat(arc4random()) / CGFloat(UINT32_MAX)) * 4.0) * 0.5
            
            let lifetime = Double(0.65 + CGFloat(arc4random_uniform(100)) * 0.01)
            
            let particle = ContentParticle(position: c, direction: direction, velocity: velocity, alpha: 1.0, lifetime: lifetime, beginTime: timestamp)
            self.particles.append(particle)
        }
        
        drawingLayer.particles = particles
    }
    

    public override func layout() {
        super.layout()
        drawingLayer.frame = bounds
    }
    
}
