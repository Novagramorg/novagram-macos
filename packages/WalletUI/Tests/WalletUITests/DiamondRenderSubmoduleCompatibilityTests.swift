import XCTest
import Foundation
import Metal
import simd
@testable import SceneEffects

private struct RenderedDiamond {
    let pixels: [SIMD4<Float>]

    var covered: [SIMD4<Float>] {
        return pixels.filter { $0.w > 0.5 }
    }

    var brightest: Float {
        return covered.reduce(Float(0)) { max($0, $1.x, $1.y, $1.z) }
    }
}

final class DiamondRenderSubmoduleCompatibilityTests: XCTestCase {
    private let side = 192

    private func render(renderer: DiamondRenderer, device: MTLDevice, pixelFormat: MTLPixelFormat, style: DiamondStyle, highlightBoost: Float) throws -> RenderedDiamond {
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: side, height: side, mipmapped: false)
        colorDescriptor.storageMode = .shared
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        let color = try XCTUnwrap(device.makeTexture(descriptor: colorDescriptor))
        let pass = MTLRenderPassDescriptor()
        if renderer.sampleCount > 1 {
            let multisampleDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: side, height: side, mipmapped: false)
            multisampleDescriptor.textureType = .type2DMultisample
            multisampleDescriptor.sampleCount = renderer.sampleCount
            multisampleDescriptor.storageMode = .private
            multisampleDescriptor.usage = .renderTarget
            pass.colorAttachments[0].texture = try XCTUnwrap(device.makeTexture(descriptor: multisampleDescriptor))
            pass.colorAttachments[0].resolveTexture = color
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].texture = color
            pass.colorAttachments[0].storeAction = .store
        }
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: side, height: side, mipmapped: false)
        depthDescriptor.storageMode = .private
        depthDescriptor.usage = .renderTarget
        depthDescriptor.sampleCount = renderer.sampleCount
        if renderer.sampleCount > 1 {
            depthDescriptor.textureType = .type2DMultisample
        }
        pass.depthAttachment.texture = try XCTUnwrap(device.makeTexture(descriptor: depthDescriptor))
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare

        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: pass))
        var motion = DiamondMotion()
        motion.step(dt: 0, speed: 0, reduceMotion: true)
        renderer.encode(encoder: encoder, size: CGSize(width: side, height: side), time: 0, starBursts: [], starOffset: .zero, motion: motion, style: style, grow: 1, pixelsPerPoint: 2, reduceMotion: true, lightBackground: false, refractionSource: nil, refractionStrength: 0, highlightBoost: highlightBoost, colorPixelFormat: pixelFormat)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)

        var pixels: [SIMD4<Float>] = []
        pixels.reserveCapacity(side * side)
        let region = MTLRegionMake2D(0, 0, side, side)
        if pixelFormat == .rgba16Float {
            var raw = [Float16](repeating: 0, count: side * side * 4)
            color.getBytes(&raw, bytesPerRow: side * 8, from: region, mipmapLevel: 0)
            for index in 0 ..< side * side {
                pixels.append(SIMD4(Float(raw[index * 4]), Float(raw[index * 4 + 1]), Float(raw[index * 4 + 2]), Float(raw[index * 4 + 3])))
            }
        } else {
            var raw = [UInt8](repeating: 0, count: side * side * 4)
            color.getBytes(&raw, bytesPerRow: side * 4, from: region, mipmapLevel: 0)
            for index in 0 ..< side * side {
                pixels.append(SIMD4(Float(raw[index * 4 + 2]), Float(raw[index * 4 + 1]), Float(raw[index * 4]), Float(raw[index * 4 + 3])) / 255)
            }
        }
        return RenderedDiamond(pixels: pixels)
    }

    private func chatCardStyle() -> DiamondStyle {
        var style = DiamondStyle()
        style.animationMode = .continuous
        style.backgroundStars = false
        style.appearance = .cool
        style.widthPoints = 38
        style.dragGrow = 3
        style.growShift = 12
        return style
    }

    func testPressedDiamondGlowsAboveWhiteOnlyInTheWideFormat() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = try XCTUnwrap(DiamondRenderer(device: device))
        let style = chatCardStyle()

        let standard = try render(renderer: renderer, device: device, pixelFormat: .bgra8Unorm, style: style, highlightBoost: 0)
        XCTAssertGreaterThan(standard.covered.count, 500)

        let wide = try render(renderer: renderer, device: device, pixelFormat: .rgba16Float, style: style, highlightBoost: 0)
        XCTAssertEqual(wide.covered.count, standard.covered.count, accuracy: standard.covered.count / 50)
        XCTAssertLessThanOrEqual(wide.brightest, 1.001)

        let boosted = try render(renderer: renderer, device: device, pixelFormat: .rgba16Float, style: style, highlightBoost: 0.4)
        XCTAssertEqual(boosted.covered.count, wide.covered.count)
        XCTAssertGreaterThan(boosted.brightest, 1.1)
        XCTAssertLessThanOrEqual(boosted.brightest, wide.brightest * 1.4 + 0.001)

        let boostedStandard = try render(renderer: renderer, device: device, pixelFormat: .bgra8Unorm, style: style, highlightBoost: 0.4)
        XCTAssertLessThanOrEqual(boostedStandard.brightest, 1.0)
    }
}
