import Foundation
import Cocoa
import Metal
import TGUIKit
import MetalEngine

public protocol LiquidGlassShapesSource: AnyObject {
    func liquidGlassShapesAdvance(by deltaTime: CGFloat)
    func liquidGlassShapes(size: CGSize, isFlat: Bool) -> LiquidGlassShapeSet?
    func liquidGlassAppearance(mode: LiquidGlassRenderMode, isDarkAppearance: Bool) -> LiquidGlassShapesAppearance
}

func liquidGlassColorVector(_ color: NSColor) -> SIMD4<Float> {
    let color = color.usingColorSpace(.sRGB) ?? color
    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    var alpha: CGFloat = 0.0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
}

private func encodeShapeKernel<Parameters>(commandBuffer: MTLCommandBuffer, pipelineState: MTLComputePipelineState, parameters: Parameters, sampleCount: Int, output: MTLBuffer) -> MTLBuffer? {
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
        return nil
    }
    encoder.setComputePipelineState(pipelineState)
    withUnsafeBytes(of: parameters) { bytes in
        encoder.setBytes(bytes.baseAddress!, length: MemoryLayout<Parameters>.stride, index: 0)
    }
    encoder.setBuffer(output, offset: 0, index: 1)
    let threadCount = min(sampleCount, pipelineState.maxTotalThreadsPerThreadgroup)
    encoder.dispatchThreadgroups(MTLSize(width: 3, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: threadCount, height: 1, depth: 1))
    encoder.endEncoding()
    return output
}

public final class LiquidGlassShapesLayer: SimpleLayer, MetalEngineSubject {
    enum Constants {
        static let glassBlurRadius: CGFloat = 1.0
        static let backdropScale: CGFloat = 1.0
        static let colorTransitionDuration: Double = 0.3
        static let edgeInset = 2
    }

    private struct ColorTransition {
        var from: (SIMD4<Float>, SIMD4<Float>)
        var startTimestamp: Double
    }

    public var internalData: MetalEngineSubjectInternalData?
    public weak var source: LiquidGlassShapesSource?

    public var glassMapScale: CGSize = CGSize(width: System.backingScale, height: System.backingScale)

    public var releasesSurfacesWhenHidden: Bool {
        get {
            return self.surfaceReleasePolicy.releasesWhenHidden
        } set {
            self.surfaceReleasePolicy.releasesWhenHidden = newValue
        }
    }

    public var isInWindow: Bool = false {
        didSet {
            if self.isInWindow != oldValue {
                if self.surfaceReleasePolicy.update(isInWindow: self.isInWindow) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.surfaceReleasePolicy.releasesNow else {
                            return
                        }
                        self.releaseSurfaces()
                    }
                }
                self.updateDisplayLink()
                if self.isInWindow {
                    self.setNeedsUpdate()
                }
            }
        }
    }

    public var isFlat: Bool = false {
        didSet {
            if self.isFlat != oldValue {
                self.updateStyle()
                self.updateDisplayLink()
                self.setNeedsUpdate()
            }
        }
    }

    public var isAnimating: Bool = false {
        didSet {
            if self.isAnimating != oldValue {
                self.updateDisplayLink()
            }
        }
    }

    public var isDarkAppearance: Bool = false {
        didSet {
            if self.isDarkAppearance != oldValue {
                self.setNeedsUpdate()
            }
        }
    }

    public var gradientLength: CGFloat = 1.0 {
        didSet {
            if self.gradientLength != oldValue {
                self.setNeedsUpdate()
            }
        }
    }

    public var usesGlass: Bool {
        return self.backdropLayers != nil
    }

    private let contentLayer: MetalEngineSubjectLayer
    private var multiplyLayer: MetalEngineSubjectLayer?
    private var backdropLayers: LiquidGlassBackdropLayers?

    private let crestBuffer: PooledBuffer
    private let radialBuffer: PooledBuffer

    private var colors: (SIMD4<Float>, SIMD4<Float>)
    private var targetColors: (SIMD4<Float>, SIMD4<Float>)
    private var colorTransition: ColorTransition?

    private var displayLink: SharedDisplayLinkDriver.Link?
    private var lastTimestamp: Double?

    private var surfaceReleasePolicy = LiquidGlassSurfaceReleasePolicy(releasesWhenHidden: false)

    public init(colors: (NSColor, NSColor)) {
        self.contentLayer = MetalEngineSubjectLayer()
        self.crestBuffer = MetalEngine.shared.pooledBuffer(spec: BufferSpec(length: 3 * LiquidGlassShapesConstants.crestSampleCount * MemoryLayout<Float>.size))
        self.radialBuffer = MetalEngine.shared.pooledBuffer(spec: BufferSpec(length: 3 * LiquidGlassShapesConstants.radialSampleCount * MemoryLayout<Float>.size))
        self.colors = (liquidGlassColorVector(colors.0), liquidGlassColorVector(colors.1))
        self.targetColors = self.colors

        super.init()

        self.isOpaque = false
        self.masksToBounds = false
        self.addSublayer(self.contentLayer)

        self.updateStyle()
    }

    override public init(layer: Any) {
        guard let layer = layer as? LiquidGlassShapesLayer else {
            preconditionFailure()
        }
        self.contentLayer = layer.contentLayer
        self.crestBuffer = layer.crestBuffer
        self.radialBuffer = layer.radialBuffer
        self.colors = layer.colors
        self.targetColors = layer.targetColors

        super.init(layer: layer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.displayLink?.invalidate()
    }

    public func updateLayout() {
        let bounds = CGRect(origin: CGPoint(), size: self.bounds.size)
        self.contentLayer.frame = bounds
        self.multiplyLayer?.frame = bounds
        self.backdropLayers?.updateFrame(bounds)

        self.setNeedsUpdate()
    }

    public func updateColors(_ colors: (NSColor, NSColor), animated: Bool) {
        let targetColors = (liquidGlassColorVector(colors.0), liquidGlassColorVector(colors.1))
        if targetColors == self.targetColors {
            return
        }
        self.targetColors = targetColors
        if animated && self.isInWindow {
            self.colorTransition = ColorTransition(from: self.colors, startTimestamp: CACurrentMediaTime())
        } else {
            self.colorTransition = nil
            self.colors = targetColors
        }
        self.updateDisplayLink()
        self.setNeedsUpdate()
    }

    private func releaseSurfaces() {
        self.contentLayer.releaseSurface()
        self.multiplyLayer?.releaseSurface()
        self.backdropLayers?.backdropMaskLayer.releaseSurface()
        self.backdropLayers?.displacementMapLayer.releaseSurface()
    }

    private func updateStyle() {
        let bounds = CGRect(origin: CGPoint(), size: self.bounds.size)

        let wantsGlass = System.liquidGlass && !self.isFlat
        if wantsGlass {
            if self.backdropLayers == nil, let backdropLayers = LiquidGlassBackdropLayers(blurRadius: Constants.glassBlurRadius, scale: Constants.backdropScale) {
                backdropLayers.updateFrame(bounds)
                self.insertSublayer(backdropLayers.containerLayer, at: 0)
                self.backdropLayers = backdropLayers
            }
        } else if let backdropLayers = self.backdropLayers {
            self.backdropLayers = nil
            backdropLayers.containerLayer.removeFromSuperlayer()
        }

        if self.usesGlass {
            if self.multiplyLayer == nil {
                let multiplyLayer = MetalEngineSubjectLayer()
                multiplyLayer.compositingFilter = "multiplyBlendMode"
                multiplyLayer.frame = bounds
                self.insertSublayer(multiplyLayer, below: self.contentLayer)
                self.multiplyLayer = multiplyLayer
            }
            self.contentLayer.compositingFilter = "plusL"
        } else {
            if let multiplyLayer = self.multiplyLayer {
                self.multiplyLayer = nil
                multiplyLayer.removeFromSuperlayer()
            }
            self.contentLayer.compositingFilter = nil
        }
    }

    private var isAnimatingShapes: Bool {
        return self.isInWindow && self.isAnimating && !self.isFlat
    }

    private func updateDisplayLink() {
        if self.isInWindow && ((self.isAnimating && !self.isFlat) || self.colorTransition != nil) {
            if self.displayLink == nil {
                self.lastTimestamp = nil
                self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                    self?.displayLinkTick()
                })
            }
        } else if let displayLink = self.displayLink {
            self.displayLink = nil
            displayLink.invalidate()
        }
    }

    private func displayLinkTick() {
        let timestamp = CACurrentMediaTime()
        let deltaTime: CGFloat
        if let lastTimestamp = self.lastTimestamp {
            deltaTime = CGFloat(max(0.0, min(0.05, timestamp - lastTimestamp)))
        } else {
            deltaTime = 1.0 / 60.0
        }
        self.lastTimestamp = timestamp

        if self.isAnimatingShapes {
            self.source?.liquidGlassShapesAdvance(by: deltaTime)
        }

        if let colorTransition = self.colorTransition {
            let t = Float(max(0.0, min(1.0, (timestamp - colorTransition.startTimestamp) / Constants.colorTransitionDuration)))
            self.colors = (
                colorTransition.from.0 + (self.targetColors.0 - colorTransition.from.0) * t,
                colorTransition.from.1 + (self.targetColors.1 - colorTransition.from.1) * t
            )
            if t >= 1.0 {
                self.colorTransition = nil
                self.updateDisplayLink()
            }
        }

        self.setNeedsUpdate()
    }

    public func update(context: MetalEngineSubjectContext) {
        let size = self.bounds.size
        guard self.isInWindow, size.width > 0.0, size.height > 0.0, let source = self.source, let shapes = source.liquidGlassShapes(size: size, isFlat: self.isFlat) else {
            return
        }
        switch shapes {
        case let .crest(parameters):
            self.update(context: context, kind: LiquidGlassCrestKind.self, parameters: parameters, sampleBuffer: self.crestBuffer, shapeCenter: SIMD2<Float>(), size: size, source: source)
        case let .radial(parameters, center):
            self.update(context: context, kind: LiquidGlassRadialKind.self, parameters: parameters, sampleBuffer: self.radialBuffer, shapeCenter: center, size: size, source: source)
        }
    }

    private func update<Kind: LiquidGlassShapesKind, Parameters>(context: MetalEngineSubjectContext, kind: Kind.Type, parameters: Parameters, sampleBuffer: PooledBuffer, shapeCenter: SIMD2<Float>, size: CGSize, source: LiquidGlassShapesSource) {
        guard LiquidGlassShapesPipelines.shared.computePipelineState(device: MetalEngine.shared.device, functionName: Kind.kernelFunctionName) != nil, let buffer = sampleBuffer.get(context: context) else {
            return
        }
        let samples = context.compute(state: LiquidGlassShapesComputeState<Kind>.self, inputs: buffer.placeholer, commands: { commandBuffer, state, buffer -> MTLBuffer? in
            guard let buffer else {
                return nil
            }
            return encodeShapeKernel(commandBuffer: commandBuffer, pipelineState: state.pipelineState, parameters: parameters, sampleCount: Kind.sampleCount, output: buffer)
        })

        let mode: LiquidGlassRenderMode
        if self.isFlat {
            mode = .flat
        } else if self.usesGlass {
            mode = .glass
        } else {
            mode = .plain
        }
        let baseUniforms = LiquidGlassShapesUniforms(
            appearance: source.liquidGlassAppearance(mode: mode, isDarkAppearance: self.isDarkAppearance),
            colors: self.colors,
            boundsSize: size,
            gradientLength: self.gradientLength,
            shapeCenter: shapeCenter,
            mode: mode,
            isDarkAppearance: self.isDarkAppearance,
            edgeInset: Float(Constants.edgeInset)
        )

        func render<Pass: LiquidGlassShapesPass>(_ pass: Pass.Type, layer: MetalEngineSubjectLayer, scale: CGSize) {
            let renderSize = RenderSize(width: max(1, Int(ceil(size.width * scale.width))), height: max(1, Int(ceil(size.height * scale.height))))
            var uniforms = baseUniforms
            uniforms.renderSize = SIMD2<Float>(Float(renderSize.width), Float(renderSize.height))

            let spec = RenderLayerSpec(size: renderSize, edgeInset: Constants.edgeInset, prefersDedicatedSurface: true)
            context.renderToLayer(spec: spec, state: LiquidGlassShapesRenderState<Pass, Kind>.self, layer: layer, inputs: samples, commands: { encoder, placement, samples in
                guard let samples else {
                    return
                }
                let effectiveRect = placement.effectiveRect
                var rect = SIMD4<Float>(Float(effectiveRect.minX), Float(effectiveRect.minY), Float(effectiveRect.width), Float(effectiveRect.height))
                encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.size, index: 0)

                var uniforms = uniforms
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LiquidGlassShapesUniforms>.stride, index: 0)
                encoder.setFragmentBuffer(samples, offset: 0, index: 1)

                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            })
        }

        let screenScale = CGSize(width: System.backingScale, height: System.backingScale)
        render(LiquidGlassContentPass.self, layer: self.contentLayer, scale: screenScale)
        if let multiplyLayer = self.multiplyLayer {
            render(LiquidGlassMultiplyPass.self, layer: multiplyLayer, scale: screenScale)
        }
        if let backdropLayers = self.backdropLayers {
            render(LiquidGlassBackdropMaskPass.self, layer: backdropLayers.backdropMaskLayer, scale: self.glassMapScale)
            render(LiquidGlassDisplacementPass.self, layer: backdropLayers.displacementMapLayer, scale: self.glassMapScale)
        }
    }
}
