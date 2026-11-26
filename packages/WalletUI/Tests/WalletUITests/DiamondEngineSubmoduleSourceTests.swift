import XCTest
import Foundation

private struct SourceBlock {
    let file: String
    let signature: String
    let adaptations: [(String, String)]

    init(_ file: String, _ signature: String, _ adaptations: [(String, String)] = []) {
        self.file = file
        self.signature = signature
        self.adaptations = adaptations
    }
}

private let commonAdaptations: [(String, String)] = [
    ("self.isInHierarchy, self.isApplicationInForeground, self.isRenderingEnabled", "self.isInHierarchy, self.isRenderingEnabled"),
    ("self.isInHierarchy && self.isApplicationInForeground && self.isRenderingEnabled", "self.isInHierarchy && self.isRenderingEnabled"),
    ("self.isInHierarchy, UIApplication.shared.applicationState == .active, self.isRenderingEnabled", "self.isInHierarchy, self.isRenderingEnabled"),
    ("self.isInHierarchy && UIApplication.shared.applicationState == .active && self.isRenderingEnabled", "self.isInHierarchy && self.isRenderingEnabled"),
    ("UIAccessibility.isReduceMotionEnabled", "NSWorkspace.shared.accessibilityDisplayShouldReduceMotion"),
    ("InteractiveDiamondComponent.", "InteractiveDiamondView."),
    ("UIGestureRecognizer.State", "NSGestureRecognizer.State"),
    ("metalLibrary(device:", "gramDiamondMetalLibrary(device:"),
    ("PremiumDiamondComponentBundle/default.metallib", "SceneEffects/default.metallib")
]

final class DiamondEngineSubmoduleSourceTests: XCTestCase {
    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func submoduleFile(_ name: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Premium/PremiumDiamondComponent").appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func actualFile(_ name: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent("packages/SceneEffects/Sources/InteractiveDiamond").appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func normalized(_ text: String) -> String {
        var lines: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") {
                continue
            }
            if let range = line.range(of: "//") {
                line = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            line = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private func block(_ signature: String, in source: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: signature), "missing \(signature)")
        let open = try XCTUnwrap(source.range(of: "{", range: start.upperBound ..< source.endIndex), "no body for \(signature)")
        var depth = 0
        var index = open.lowerBound
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[start.lowerBound ... index])
                }
            }
            index = source.index(after: index)
        }
        XCTFail("unbalanced \(signature)")
        return ""
    }

    private func assertBlocksMatch(_ blocks: [SourceBlock], submodulePrefix: String) throws {
        for item in blocks {
            var submodule = normalized(try block(item.signature, in: try submoduleFile(submodulePrefix + item.file)))
            for (from, to) in commonAdaptations + item.adaptations {
                submodule = submodule.replacingOccurrences(of: from, with: to)
            }
            let actual = normalized(try block(item.signature, in: try actualFile(item.file)))
            if submodule != actual {
                let a = submodule.components(separatedBy: "\n")
                let b = actual.components(separatedBy: "\n")
                let firstDifference = (0 ..< min(a.count, b.count)).first(where: { a[$0] != b[$0] }) ?? min(a.count, b.count)
                let submoduleLine = firstDifference < a.count ? a[firstDifference] : "<end>"
                let actualLine = firstDifference < b.count ? b[firstDifference] : "<end>"
                XCTFail("\(item.file) \(item.signature) differs at line \(firstDifference + 1)\nsubmodule: \(submoduleLine)\nactual:    \(actualLine)")
            }
        }
    }

    func testDiamondShaderMatchesSubmodule() throws {
        XCTAssertEqual(normalized(try actualFile("GramDiamond.metal")), normalized(try submoduleFile("MetalResources/GramDiamond.metal")))
    }

    func testDiamondMotionMatchesSubmodule() throws {
        let submodule = normalized(try submoduleFile("Sources/InteractiveDiamond/DiamondAnimation.swift"))
            .replacingOccurrences(of: "import UIKit", with: "import Cocoa")
            .replacingOccurrences(of: "import Display", with: "import TGUIKit")
        XCTAssertEqual(normalized(try actualFile("DiamondAnimation.swift")), submodule)
    }

    func testRendererFloatLensAndBrightnessMatchSubmodule() throws {
        try assertBlocksMatch([
            SourceBlock("DiamondRenderer.swift", "private final class Pipelines"),
            SourceBlock("DiamondRenderer.swift", "private static func makePipeline(", [
                ("guard let pipelineState = MetalEngine.shared.pipelineCache.makeRenderPipelineState(descriptor: descriptor) else {\nthrow Failure.resource(\"pipeline \\(vertex) / \\(fragment)\")\n}\nreturn pipelineState", "return try device.makeRenderPipelineState(descriptor: descriptor)")
            ]),
            SourceBlock("DiamondRenderer.swift", "private func lens("),
            SourceBlock("DiamondRenderer.swift", "private func uniforms("),
            SourceBlock("DiamondRenderer.swift", "func encode(")
        ], submodulePrefix: "Sources/InteractiveDiamond/")
    }

    func testLayerTapSpinPushAndBrightnessMatchSubmodule() throws {
        try assertBlocksMatch([
            SourceBlock("InteractiveDiamondLayer.swift", "struct DiamondStyle: Equatable"),
            SourceBlock("InteractiveDiamondLayer.swift", "private final class CompositeState", [
                ("return MetalEngine.shared.pipelineCache.makeRenderPipelineState(descriptor: descriptor)", "return try? self.device.makeRenderPipelineState(descriptor: descriptor)"),
                ("guard let pipelineState = MetalEngine.shared.pipelineCache.makeRenderPipelineState(descriptor: descriptor) else {", "guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {")
            ]),
            SourceBlock("InteractiveDiamondLayer.swift", "private final class RenderTargets"),
            SourceBlock("InteractiveDiamondLayer.swift", "private var effectiveStyle: DiamondStyle"),
            SourceBlock("InteractiveDiamondLayer.swift", "func update(style: DiamondStyle, preservingMotion: Bool = false)"),
            SourceBlock("InteractiveDiamondLayer.swift", "func resetAnimation()"),
            SourceBlock("InteractiveDiamondLayer.swift", "func pushFromBelow(strength: Float)"),
            SourceBlock("InteractiveDiamondLayer.swift", "func updateTransferState(isSending: Bool, animateCompletion: Bool)"),
            SourceBlock("InteractiveDiamondLayer.swift", "func beginReceivingTransfer("),
            SourceBlock("InteractiveDiamondLayer.swift", "func endReceivingTransfer()"),
            SourceBlock("InteractiveDiamondLayer.swift", "private func cancelTransferCompletion()"),
            SourceBlock("InteractiveDiamondLayer.swift", "private func addStarBurst("),
            SourceBlock("InteractiveDiamondLayer.swift", "private func tapSpin("),
            SourceBlock("InteractiveDiamondLayer.swift", "func cancelTapSpin()"),
            SourceBlock("InteractiveDiamondLayer.swift", "private func updateDynamicRange(", [
                ("#available(iOS 26.0, *)", "#available(macOS 26.0, *)"),
                ("#available(iOS 17.0, *)", "#available(macOS 14.0, *)")
            ]),
            SourceBlock("InteractiveDiamondLayer.swift", "private func updateMotion(at time: CFTimeInterval)", [
                ("\nself.updateExternalMotion(at: self.isInHierarchy && self.isRenderingEnabled && !self.reduceMotion ? time : nil)", ""),
                ("let scrollTilt: Float\nif self.isInHierarchy && self.isRenderingEnabled && !self.reduceMotion {\nscrollTilt = self.scrollTiltProvider?(time) ?? 0.0\n} else {\nscrollTilt = 0.0\n}\nself.motion.tilt = style.tilt + scrollTilt", "self.motion.tilt = style.tilt")
            ]),
            SourceBlock("InteractiveDiamondLayer.swift", "func updateDrag(", [
                (", playFlingHaptic: Bool = true", ""),
                ("\nif playFlingHaptic {\nself.hapticFeedback.impact(.medium)\n}", "")
            ])
        ], submodulePrefix: "Sources/InteractiveDiamond/")
    }

    func testLayerFrameSetupMatchesSubmoduleExceptTheScreen() throws {
        try assertBlocksMatch([
            SourceBlock("InteractiveDiamondLayer.swift", "func update(context: MetalEngineSubjectContext)", [
                ("let pixelsPerPoint = UIScreen.main.scale", "let pixelsPerPoint = System.backingScale"),
                ("if #available(iOS 17.0, *) {\nhighDynamicRange = UIScreen.main.potentialEDRHeadroom > 1.0", "if #available(macOS 10.15, *) {\nhighDynamicRange = (NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0) > 1.0"),
                ("commands: { [weak self] commandBuffer, renderer -> RenderedFrame? in", "commands: { [weak self] commandBuffer, renderer -> MTLTexture? in"),
                ("return RenderedFrame(texture: targets.color, commandBuffer: commandBuffer)", "return targets.color"),
                ("inputs: frame, commands: { [weak self] encoder, placement, frame in\nguard let frame else { return }", "inputs: frame, commands: { [weak self] encoder, placement, texture in\nguard let texture else { return }"),
                ("encoder.setFragmentTexture(frame.texture, index: 0)", "encoder.setFragmentTexture(texture, index: 0)"),
                ("\nself?.scheduleReady(after: frame.commandBuffer)", "")
            ])
        ], submodulePrefix: "Sources/InteractiveDiamond/")
    }

    func testWalletTransferHandOverMatchesSubmodule() throws {
        let submodule = try submoduleFile("Sources/PremiumDiamondComponent.swift")
        let actual = try actualFile("InteractiveDiamondView.swift")
        let adaptations: [(String, String)] = [
            ("self.isUserInteractionEnabled = false", "self.isInteractionEnabled = false"),
            ("\nself.onRefractionUpdated = nil", ""),
            ("\nself.scrollTiltProvider = nil", ""),
            ("\nself.externalMotion = nil", ""),
            ("self.bounds = CGRect(x: 0.0, y: 0.0, width: 150.0, height: 150.0)", "self.frame = CGRect(x: self.frame.midX - 75.0, y: self.frame.midY - 75.0, width: 150.0, height: 150.0)")
        ]
        for signature in ["public func prepareForWalletTransfer()", "public func updateWalletTransfer(width: CGFloat, rotationSpeed: Float, completion: Bool, isDark: Bool, appearance: Appearance = .blue)", "if self.isWalletTransfer", "public func beginReceivingTransfer(at startTime: CFTimeInterval, completionDelay: Double)", "public func endReceivingTransfer()"] {
            var expected = normalized(try block(signature, in: submodule))
            for (from, to) in adaptations {
                expected = expected.replacingOccurrences(of: from, with: to)
            }
            XCTAssertEqual(normalized(try block(signature, in: actual)), expected, signature)
        }
    }
}
