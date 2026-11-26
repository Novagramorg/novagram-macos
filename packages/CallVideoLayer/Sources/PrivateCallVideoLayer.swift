import Foundation
import TGUIKit
import MetalKit
import Accelerate
import MetalEngine


extension sizable {
    static func size() -> Int {
        return MemoryLayout<Self>.size
    }
    static func stride() -> Int {
        return MemoryLayout<Self>.stride
    }
    static func size(_ count: Int) -> Int {
        return MemoryLayout<Self>.size * count
    }
    static func stride(_ count: Int) -> Int {
        return MemoryLayout<Self>.stride * count
    }
}

protocol sizable {
    static func size(_ count: Int) -> Int
    static func stride(_ count: Int) -> Int
}

struct ModelConstants : sizable {
    static var index: Int = 2
}

private final class BundleMarker: NSObject {
}

private var metalLibraryValue: MTLLibrary?
func metalLibrary(device: MTLDevice) -> MTLLibrary? {
    if let metalLibraryValue {
        return metalLibraryValue
    }

    guard let library = try? device.makeDefaultLibrary(bundle: .module) else {
        return nil
    }
    
    metalLibraryValue = library
    return library
}

private func makeVideoRenderPipelineState(device: MTLDevice, fragmentFunctionName: String) -> MTLRenderPipelineState? {
    guard let library = metalLibrary(device: device) else {
        return nil
    }
    guard let vertexFunction = library.makeFunction(name: "mainVideoVertex"), let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
        return nil
    }
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = vertexFunction
    pipelineDescriptor.fragmentFunction = fragmentFunction
    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    return try? device.makeRenderPipelineState(descriptor: pipelineDescriptor)
}

private func makeComputePipelineState(device: MTLDevice, library: MTLLibrary, name: String) -> MTLComputePipelineState? {
    guard let function = library.makeFunction(name: name) else {
        return nil
    }
    return try? device.makeComputePipelineState(function: function)
}

private func encodeVideoGeometry(encoder: MTLRenderCommandEncoder, placement: RenderLayerPlacement, spec: RenderLayerSpec, video: VideoSource.Output) {
    let effectiveRect = placement.effectiveRect
    var rect = SIMD4<Float>(Float(effectiveRect.minX), Float(effectiveRect.minY), Float(effectiveRect.width), Float(effectiveRect.height))
    encoder.setVertexBytes(&rect, length: 4 * 4, index: 0)
    
    var mirror = SIMD2<UInt32>(
        video.mirrorDirection.contains(.horizontal) ? 1 : 0,
        video.mirrorDirection.contains(.vertical) ? 1 : 0
    )
    encoder.setVertexBytes(&mirror, length: 2 * 4, index: 1)
    
    var angle: Float = -video.rotationAngle
    encoder.setVertexBytes(&angle, length: 4, index: 2)
    
    var edge = SIMD2<Float>(
        Float(spec.edgeInset) / Float(max(1, spec.size.width + spec.edgeInset * 2)),
        Float(spec.edgeInset) / Float(max(1, spec.size.height + spec.edgeInset * 2))
    )
    encoder.setVertexBytes(&edge, length: 2 * 4, index: 3)
}

final class PrivateCallVideoLayer: MetalEngineSubjectLayer, MetalEngineSubject {
    var internalData: MetalEngineSubjectInternalData?
    
    let blurredLayer: MetalEngineSubjectLayer
    
    final class BlurState: ComputeState {
        let computePipelineStateBGRADownscale: MTLComputePipelineState
        let computePipelineStateBiPlanarDownscale: MTLComputePipelineState
        let computePipelineStateTriPlanarDownscale: MTLComputePipelineState
        let computePipelineStateHorizontal: MTLComputePipelineState
        let computePipelineStateVertical: MTLComputePipelineState
        
        required init?(device: MTLDevice) {
            guard let library = metalLibrary(device: device) else {
                return nil
            }
            guard let computePipelineStateBGRADownscale = makeComputePipelineState(device: device, library: library, name: "videoBGRADownscale"),
                  let computePipelineStateBiPlanarDownscale = makeComputePipelineState(device: device, library: library, name: "videoBiPlanarDownscale"),
                  let computePipelineStateTriPlanarDownscale = makeComputePipelineState(device: device, library: library, name: "videoTriPlanarDownscale"),
                  let computePipelineStateHorizontal = makeComputePipelineState(device: device, library: library, name: "gaussianBlurHorizontal"),
                  let computePipelineStateVertical = makeComputePipelineState(device: device, library: library, name: "gaussianBlurVertical") else {
                return nil
            }
            self.computePipelineStateBGRADownscale = computePipelineStateBGRADownscale
            self.computePipelineStateBiPlanarDownscale = computePipelineStateBiPlanarDownscale
            self.computePipelineStateTriPlanarDownscale = computePipelineStateTriPlanarDownscale
            self.computePipelineStateHorizontal = computePipelineStateHorizontal
            self.computePipelineStateVertical = computePipelineStateVertical
        }
    }
    
    final class BlurRenderState: RenderToLayerState {
        let pipelineState: MTLRenderPipelineState
        
        required init?(device: MTLDevice) {
            guard let pipelineState = makeVideoRenderPipelineState(device: device, fragmentFunctionName: "mainVideoFragment") else {
                return nil
            }
            self.pipelineState = pipelineState
        }
    }
    
    final class BiPlanarRenderState: RenderToLayerState {
        let pipelineState: MTLRenderPipelineState
        
        required init?(device: MTLDevice) {
            guard let pipelineState = makeVideoRenderPipelineState(device: device, fragmentFunctionName: "videoBiPlanarFragment") else {
                return nil
            }
            self.pipelineState = pipelineState
        }
    }
    
    final class TriPlanarRenderState: RenderToLayerState {
        let pipelineState: MTLRenderPipelineState
        
        required init?(device: MTLDevice) {
            guard let pipelineState = makeVideoRenderPipelineState(device: device, fragmentFunctionName: "videoTriPlanarFragment") else {
                return nil
            }
            self.pipelineState = pipelineState
        }
    }
    
    final class BGRARenderState: RenderToLayerState {
        let pipelineState: MTLRenderPipelineState
        
        required init?(device: MTLDevice) {
            guard let pipelineState = makeVideoRenderPipelineState(device: device, fragmentFunctionName: "videoBGRAFragment") else {
                return nil
            }
            self.pipelineState = pipelineState
        }
    }
    
    var video: VideoSource.Output? {
        didSet {
            self.setNeedsUpdate()
        }
    }
    
    var renderSpec: RenderLayerSpec?
    var blurredRenderSpec: RenderLayerSpec?
    
    private var downscaledTexture: PooledTexture?
    private var blurredHorizontalTexture: PooledTexture?
    private var blurredVerticalTexture: PooledTexture?
    
    override init() {
        self.blurredLayer = MetalEngineSubjectLayer()
        
        super.init()
    }
    
    override init(layer: Any) {
        self.blurredLayer = MetalEngineSubjectLayer()
        
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(context: MetalEngineSubjectContext) {
        if self.isHidden {
            return
        }
        guard let renderSpec = self.renderSpec else {
            return
        }
        guard let videoTextures = self.video else {
            return
        }
        
        if !self.blurredLayer.isHidden, let blurredRenderSpec = self.blurredRenderSpec {
            self.updateBlur(context: context, spec: blurredRenderSpec, video: videoTextures)
        }
        
        switch videoTextures.textureLayout {
        case let .biPlanar(biPlanar):
            context.renderToLayer(spec: renderSpec, state: BiPlanarRenderState.self, layer: self, commands: { encoder, placement in
                encodeVideoGeometry(encoder: encoder, placement: placement, spec: renderSpec, video: videoTextures)
                encoder.setFragmentTexture(biPlanar.y, index: 0)
                encoder.setFragmentTexture(biPlanar.uv, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            })
        case let .triPlanar(triPlanar):
            context.renderToLayer(spec: renderSpec, state: TriPlanarRenderState.self, layer: self, commands: { encoder, placement in
                encodeVideoGeometry(encoder: encoder, placement: placement, spec: renderSpec, video: videoTextures)
                encoder.setFragmentTexture(triPlanar.y, index: 0)
                encoder.setFragmentTexture(triPlanar.u, index: 1)
                encoder.setFragmentTexture(triPlanar.v, index: 2)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            })
        case let .bgra(bgra):
            context.renderToLayer(spec: renderSpec, state: BGRARenderState.self, layer: self, commands: { encoder, placement in
                encodeVideoGeometry(encoder: encoder, placement: placement, spec: renderSpec, video: videoTextures)
                encoder.setFragmentTexture(bgra.bgra, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            })
        }
        
        context.addCustomCompletion {
            let _ = videoTextures
        }
    }
    
    private func updateBlur(context: MetalEngineSubjectContext, spec: RenderLayerSpec, video videoTextures: VideoSource.Output) {
        if self.downscaledTexture == nil {
            self.downscaledTexture = MetalEngine.shared.pooledTexture(spec: TextureSpec(width: 128, height: 128, pixelFormat: .rgba8UnsignedNormalized))
        }
        if self.blurredHorizontalTexture == nil {
            self.blurredHorizontalTexture = MetalEngine.shared.pooledTexture(spec: TextureSpec(width: 128, height: 128, pixelFormat: .rgba8UnsignedNormalized))
        }
        if self.blurredVerticalTexture == nil {
            self.blurredVerticalTexture = MetalEngine.shared.pooledTexture(spec: TextureSpec(width: 128, height: 128, pixelFormat: .rgba8UnsignedNormalized))
        }
        guard let downscaledTexture = self.downscaledTexture?.get(context: context), let blurredHorizontalTexture = self.blurredHorizontalTexture?.get(context: context), let blurredVerticalTexture = self.blurredVerticalTexture?.get(context: context) else {
            return
        }
        
        let blurredTexture = context.compute(state: BlurState.self, inputs: downscaledTexture.placeholer, blurredHorizontalTexture.placeholer, blurredVerticalTexture.placeholer, commands: { commandBuffer, blurState, downscaledTexture, blurredHorizontalTexture, blurredVerticalTexture -> MTLTexture? in
            guard let downscaledTexture, let blurredHorizontalTexture, let blurredVerticalTexture else {
                return nil
            }
            guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                return nil
            }
            
            let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroupCount = MTLSize(width: (downscaledTexture.width + threadgroupSize.width - 1) / threadgroupSize.width, height: (downscaledTexture.height + threadgroupSize.height - 1) / threadgroupSize.height, depth: 1)
            
            switch videoTextures.textureLayout {
            case let .bgra(texture):
                computeEncoder.setComputePipelineState(blurState.computePipelineStateBGRADownscale)
                computeEncoder.setTexture(texture.bgra, index: 0)
                computeEncoder.setTexture(downscaledTexture, index: 1)
            case let .biPlanar(biPlanar):
                computeEncoder.setComputePipelineState(blurState.computePipelineStateBiPlanarDownscale)
                computeEncoder.setTexture(biPlanar.y, index: 0)
                computeEncoder.setTexture(biPlanar.uv, index: 1)
                computeEncoder.setTexture(downscaledTexture, index: 2)
            case let .triPlanar(triPlanar):
                computeEncoder.setComputePipelineState(blurState.computePipelineStateTriPlanarDownscale)
                computeEncoder.setTexture(triPlanar.y, index: 0)
                computeEncoder.setTexture(triPlanar.u, index: 1)
                computeEncoder.setTexture(triPlanar.v, index: 2)
                computeEncoder.setTexture(downscaledTexture, index: 3)
            }
            computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            
            computeEncoder.setComputePipelineState(blurState.computePipelineStateHorizontal)
            computeEncoder.setTexture(downscaledTexture, index: 0)
            computeEncoder.setTexture(blurredHorizontalTexture, index: 1)
            computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            
            computeEncoder.setComputePipelineState(blurState.computePipelineStateVertical)
            computeEncoder.setTexture(blurredHorizontalTexture, index: 0)
            computeEncoder.setTexture(blurredVerticalTexture, index: 1)
            computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            
            computeEncoder.endEncoding()
            
            return blurredVerticalTexture
        })
        
        context.renderToLayer(spec: spec, state: BlurRenderState.self, layer: self.blurredLayer, inputs: blurredTexture, commands: { encoder, placement, blurredTexture in
            guard let blurredTexture else {
                return
            }
            encodeVideoGeometry(encoder: encoder, placement: placement, spec: spec, video: videoTextures)
            encoder.setFragmentTexture(blurredTexture, index: 0)
            
            var brightness: Float = 0.7
            var saturation: Float = 1.3
            var overlay: SIMD4<Float> = SIMD4<Float>(1.0, 1.0, 1.0, 0.2)
            encoder.setFragmentBytes(&brightness, length: 4, index: 0)
            encoder.setFragmentBytes(&saturation, length: 4, index: 1)
            encoder.setFragmentBytes(&overlay, length: 4 * 4, index: 2)
            
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        })
    }
}
