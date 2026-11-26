import Cocoa
import Metal
import MetalEngine
import TGUIKit

private final class WalletStickerWaveRenderer {
    static let shared = WalletStickerWaveRenderer()

    struct Uniforms {
        var frame: SIMD4<Float>
        var size: SIMD2<Float>
        var front: Float
        var angle: Float
        var shadow: Float
        var border: Float
        var lod: Float
    }

    struct Textures {
        let base: MTLTexture
        let art: MTLTexture
    }

    let device: MTLDevice
    let pipeline: MTLRenderPipelineState
    private let queue: MTLCommandQueue
    private var textures: [String: Textures] = [:]

    private init?() {
        let device = MetalEngine.shared.device
        guard let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertex = library.makeFunction(name: "walletStickerWaveVertex"),
              let fragment = library.makeFunction(name: "walletStickerWaveFragment"),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.device = device
        self.pipeline = pipeline
        self.queue = queue
    }

    func textures(_ id: String, colorSpace: CGColorSpace) -> Textures? {
        let key = "\(id)|\(colorSpace.name.map { $0 as String } ?? "")"
        if let cached = textures[key] {
            return cached
        }
        guard let baseImage = WalletCollectableImages.base(id), let artImage = WalletCollectableImages.art(id),
              let base = texture(baseImage, colorSpace: colorSpace), let art = texture(artImage, colorSpace: colorSpace) else {
            return nil
        }
        let result = Textures(base: base, art: art)
        textures[key] = result
        return result
    }

    private func texture(_ image: CGImage, colorSpace: CGColorSpace) -> MTLTexture? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else {
            return nil
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: true)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)
        if let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            command.commit()
            command.waitUntilCompleted()
        }
        return texture
    }
}

final class WalletStickerWaveLayer: MetalEngineSubjectLayer, MetalEngineSubject {
    private final class RenderState: RenderToLayerState {
        let pipelineState: MTLRenderPipelineState

        required init?(device: MTLDevice) {
            guard let renderer = WalletStickerWaveRenderer.shared else {
                return nil
            }
            pipelineState = renderer.pipeline
        }
    }

    static var isSupported: Bool {
        #if arch(arm64)
        return WalletStickerWaveRenderer.shared != nil
        #else
        return false
        #endif
    }

    var internalData: MetalEngineSubjectInternalData?
    private let id: String
    private var uniforms = WalletStickerWaveRenderer.Uniforms(frame: .zero, size: .zero, front: 1, angle: 0, shadow: 0, border: 1, lod: 0)
    private var displayScale: CGFloat = 2
    private var colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init(id: String) {
        self.id = id
        super.init()
        isOpaque = false
        contentsGravity = .resize
    }

    override init(layer: Any) {
        self.id = (layer as? WalletStickerWaveLayer)?.id ?? ""
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(side: CGFloat, pad: CGFloat, pose: WalletStickerPose, scale: CGFloat, colorSpace: CGColorSpace) {
        let extent = side + pad * 2
        let texels = CGFloat(WalletCollectableImages.cut(id)?.width ?? 512)
        uniforms = WalletStickerWaveRenderer.Uniforms(
            frame: SIMD4(Float(pad), Float(pad), Float(side), Float(extent)),
            size: SIMD2(Float(extent), Float(extent)),
            front: Float(pose.wave ?? 1),
            angle: Float(pose.bend),
            shadow: Float(pose.shade),
            border: Float(pose.border),
            lod: Float(max(0, log2(texels / max(side * scale, 1))))
        )
        displayScale = scale
        self.colorSpace = colorSpace
        setNeedsUpdate()
    }

    func update(context: MetalEngineSubjectContext) {
        guard let renderer = WalletStickerWaveRenderer.shared, !bounds.isEmpty, let textures = renderer.textures(id, colorSpace: colorSpace) else {
            return
        }
        let scale = displayScale
        var uniforms = self.uniforms
        contentsScale = scale
        context.renderToLayer(
            spec: RenderLayerSpec(size: RenderSize(width: max(1, Int(ceil(bounds.width * scale))), height: max(1, Int(ceil(bounds.height * scale)))), prefersDedicatedSurface: true),
            state: RenderState.self,
            layer: self,
            commands: { encoder, placement in
                let rect = placement.effectiveRect
                var placement = SIMD4<Float>(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height))
                encoder.setVertexBytes(&placement, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<WalletStickerWaveRenderer.Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WalletStickerWaveRenderer.Uniforms>.stride, index: 0)
                encoder.setFragmentTexture(textures.base, index: 0)
                encoder.setFragmentTexture(textures.art, index: 1)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        )
    }
}
