import Foundation
import Metal
import MetalEngine

private let metalLibraryLock = NSLock()
private var metalLibraryValue: (device: MTLDevice, library: MTLLibrary)?

private func liquidGlassShapesMetalLibrary(device: MTLDevice) -> MTLLibrary? {
    metalLibraryLock.lock()
    defer {
        metalLibraryLock.unlock()
    }
    if let metalLibraryValue, metalLibraryValue.device === device {
        return metalLibraryValue.library
    }
    guard let library = try? device.makeDefaultLibrary(bundle: .module) else {
        return nil
    }
    metalLibraryValue = (device, library)
    return library
}

protocol LiquidGlassShapesPass {
    static var fragmentFunctionName: String { get }
}

enum LiquidGlassContentPass: LiquidGlassShapesPass {
    static let fragmentFunctionName = "liquidGlassShapesContentFragment"
}

enum LiquidGlassMultiplyPass: LiquidGlassShapesPass {
    static let fragmentFunctionName = "liquidGlassShapesMultiplyFragment"
}

enum LiquidGlassBackdropMaskPass: LiquidGlassShapesPass {
    static let fragmentFunctionName = "liquidGlassShapesMaskFragment"
}

enum LiquidGlassDisplacementPass: LiquidGlassShapesPass {
    static let fragmentFunctionName = "liquidGlassShapesDisplacementFragment"
}

protocol LiquidGlassShapesKind {
    static var shapeKind: LiquidGlassShapeKind { get }
    static var kernelFunctionName: String { get }
    static var sampleCount: Int { get }
}

enum LiquidGlassCrestKind: LiquidGlassShapesKind {
    static let shapeKind: LiquidGlassShapeKind = .crest
    static let kernelFunctionName = "liquidGlassCrestKernel"
    static let sampleCount = LiquidGlassShapesConstants.crestSampleCount
}

enum LiquidGlassRadialKind: LiquidGlassShapesKind {
    static let shapeKind: LiquidGlassShapeKind = .radial
    static let kernelFunctionName = "liquidGlassRadialKernel"
    static let sampleCount = LiquidGlassShapesConstants.radialSampleCount
}

final class LiquidGlassShapesPipelines {
    static let shared = LiquidGlassShapesPipelines()

    private let lock = NSLock()
    private var renderPipelineStates: [String: MTLRenderPipelineState] = [:]
    private var computePipelineStates: [String: MTLComputePipelineState] = [:]

    func renderPipelineState(device: MTLDevice, fragmentFunctionName: String, shapeKind: LiquidGlassShapeKind) -> MTLRenderPipelineState? {
        let key = "\(fragmentFunctionName)_\(shapeKind.rawValue)"
        self.lock.lock()
        let cached = self.renderPipelineStates[key]
        self.lock.unlock()
        if let cached {
            return cached
        }

        guard let library = liquidGlassShapesMetalLibrary(device: device) else {
            return nil
        }
        let constantValues = MTLFunctionConstantValues()
        var shapeKindValue = shapeKind.rawValue
        constantValues.setConstantValue(&shapeKindValue, type: .int, index: 0)
        guard let vertexFunction = library.makeFunction(name: "liquidGlassShapesVertex"), let fragmentFunction = try? library.makeFunction(name: fragmentFunctionName, constantValues: constantValues) else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        self.lock.lock()
        self.renderPipelineStates[key] = pipelineState
        self.lock.unlock()
        return pipelineState
    }

    func computePipelineState(device: MTLDevice, functionName: String) -> MTLComputePipelineState? {
        self.lock.lock()
        let cached = self.computePipelineStates[functionName]
        self.lock.unlock()
        if let cached {
            return cached
        }

        guard let library = liquidGlassShapesMetalLibrary(device: device), let function = library.makeFunction(name: functionName), let pipelineState = try? device.makeComputePipelineState(function: function) else {
            return nil
        }

        self.lock.lock()
        self.computePipelineStates[functionName] = pipelineState
        self.lock.unlock()
        return pipelineState
    }
}

final class LiquidGlassShapesRenderState<Pass: LiquidGlassShapesPass, Kind: LiquidGlassShapesKind>: RenderToLayerState {
    let pipelineState: MTLRenderPipelineState

    init?(device: MTLDevice) {
        guard let pipelineState = LiquidGlassShapesPipelines.shared.renderPipelineState(device: device, fragmentFunctionName: Pass.fragmentFunctionName, shapeKind: Kind.shapeKind) else {
            return nil
        }
        self.pipelineState = pipelineState
    }
}

final class LiquidGlassShapesComputeState<Kind: LiquidGlassShapesKind>: ComputeState {
    let pipelineState: MTLComputePipelineState

    init?(device: MTLDevice) {
        guard let pipelineState = LiquidGlassShapesPipelines.shared.computePipelineState(device: device, functionName: Kind.kernelFunctionName) else {
            return nil
        }
        self.pipelineState = pipelineState
    }
}
