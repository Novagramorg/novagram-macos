import XCTest
import Cocoa
import Metal
@testable import ChatUI
@testable import SceneEffects

private final class SubmoduleBlobMotion {
    struct Parameters {
        var minRandomness: CGFloat
        var maxRandomness: CGFloat
        var minSpeed: CGFloat
        var maxSpeed: CGFloat
    }

    let parameters: Parameters
    private let random: () -> CGFloat

    private(set) var fromPoints: [SIMD2<Float>] = []
    private(set) var toPoints: [SIMD2<Float>] = []
    private(set) var duration: CGFloat = 1.0
    private var elapsed: CGFloat = 0.0
    private var speedLevel: CGFloat = 0.0

    init(parameters: Parameters, random: @escaping () -> CGFloat) {
        self.parameters = parameters
        self.random = random

        self.fromPoints = self.generatePoints()
        self.startNextShape()
    }

    func updateSpeedLevel(_ level: CGFloat) {
        self.speedLevel = max(self.speedLevel, level)
    }

    func advance(by deltaTime: CGFloat) {
        self.elapsed += deltaTime
        while self.elapsed >= self.duration {
            self.elapsed -= self.duration
            self.fromPoints = self.toPoints
            self.startNextShape()
        }
    }

    func progress(easing: (CGFloat) -> CGFloat) -> Float {
        return Float(easing(max(0.0, min(1.0, self.elapsed / self.duration))))
    }

    private func startNextShape() {
        self.toPoints = self.generatePoints()
        let speed = self.parameters.minSpeed + (self.parameters.maxSpeed - self.parameters.minSpeed) * self.speedLevel
        self.duration = 1.0 / max(speed, 0.05)
        self.speedLevel = 0.0
    }

    private func generatePoints() -> [SIMD2<Float>] {
        let randomness = self.parameters.minRandomness + (self.parameters.maxRandomness - self.parameters.minRandomness) * self.speedLevel
        let count = 8
        let angle = 2.0 * CGFloat.pi / CGFloat(count)
        let rangeStart = 1.0 / (1.0 + randomness / 10.0)
        let startAngle = angle * self.random()
        return (0 ..< count).map { index -> SIMD2<Float> in
            let radius = (rangeStart + self.random() * (1.0 - rangeStart)) / 2.0
            let angleRandomness = angle * 0.1
            let pointAngle = angle + angle * (angleRandomness * self.random() - angleRandomness * 0.5)
            let pointAngleFromStart = startAngle + CGFloat(index) * pointAngle
            return SIMD2<Float>(Float(sin(pointAngleFromStart) * radius), Float(cos(pointAngleFromStart) * radius))
        }
    }
}

private struct SubmoduleBlobPresence {
    private(set) var value: CGFloat
    private var from: CGFloat
    private var target: CGFloat
    private var elapsed: Double = 0.0
    private var duration: Double = 0.0
    private let easing: (CGFloat) -> CGFloat

    init(value: CGFloat, easing: @escaping (CGFloat) -> CGFloat) {
        self.value = value
        self.from = value
        self.target = value
        self.easing = easing
    }

    var isSettled: Bool {
        return self.elapsed >= self.duration
    }

    mutating func animate(to target: CGFloat, duration: Double, canAdvance: Bool = true) {
        if !canAdvance {
            self.settle(at: target)
            return
        }
        self.from = self.value
        self.target = target
        self.elapsed = 0.0
        self.duration = duration
    }

    mutating func settle(at value: CGFloat) {
        self.value = value
        self.from = value
        self.target = value
        self.elapsed = 0.0
        self.duration = 0.0
    }

    mutating func advance(by deltaTime: Double) {
        if self.isSettled {
            return
        }
        self.elapsed = min(self.duration, self.elapsed + deltaTime)
        self.value = self.from + (self.target - self.from) * self.easing(CGFloat(self.elapsed / self.duration))
    }
}

private func submoduleA(_ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return 1.0 - 3.0 * a2 + 3.0 * a1
}

private func submoduleB(_ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return 3.0 * a2 - 6.0 * a1
}

private func submoduleC(_ a1: CGFloat) -> CGFloat {
    return 3.0 * a1
}

private func submoduleCalcBezier(_ t: CGFloat, _ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return ((submoduleA(a1, a2) * t + submoduleB(a1, a2)) * t + submoduleC(a1)) * t
}

private func submoduleCalcSlope(_ t: CGFloat, _ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return 3.0 * submoduleA(a1, a2) * t * t + 2.0 * submoduleB(a1, a2) * t + submoduleC(a1)
}

private func submoduleTForX(_ x: CGFloat, _ x1: CGFloat, _ x2: CGFloat) -> CGFloat {
    var t = x
    var i = 0
    while i < 4 {
        let currentSlope = submoduleCalcSlope(t, x1, x2)
        if currentSlope == 0.0 {
            return t
        } else {
            let currentX = submoduleCalcBezier(t, x1, x2) - x
            t -= currentX / currentSlope
        }
        i += 1
    }
    return t
}

private func submoduleBezierPoint(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat) -> CGFloat {
    var value = submoduleCalcBezier(submoduleTForX(x, x1, x2), y1, y2)
    if value >= 0.997 {
        value = 1.0
    }
    return value
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> CGFloat {
        self.state = self.state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(self.state >> 11) / Double(1 << 53))
    }
}

private final class RandomBox {
    var generator: SeededRandom

    init(seed: UInt64) {
        self.generator = SeededRandom(seed: seed)
    }

    func next() -> CGFloat {
        return self.generator.next()
    }
}

final class ChatRecordingBlobSubmoduleCompatibilityTests: XCTestCase {
    private static let submoduleBlobPath = "submodules/telegram-ios/submodules/TelegramUI/Components/ChatTextInputMediaRecordingButton/Sources/ChatRecordingBlobMotion.swift"
    private static let submoduleBlobViewPath = "submodules/telegram-ios/submodules/TelegramUI/Components/ChatTextInputMediaRecordingButton/Sources/ChatRecordingBlobView.swift"
    private static let submoduleShapesPath = "submodules/telegram-ios/submodules/TelegramUI/Components/LiquidGlassShapes"

    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func rawSource(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func source(_ path: String) throws -> String {
        return try rawSource(path).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func number(in path: String, _ pattern: String, file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        let text = try source(path)
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text), let value = Double(text[range]) else {
            XCTFail("\(path) does not match \(pattern)", file: file, line: line)
            return .nan
        }
        return value
    }

    private func numbers(in path: String, _ pattern: String) throws -> [Double] {
        let text = try source(path)
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            XCTFail("\(path) does not match \(pattern)")
            return []
        }
        return (1 ..< match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).flatMap { Double(text[$0]) }
        }
    }

    private func normalizedShader(_ text: String) -> String {
        return text
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "//.*$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    func testShaderMatchesSubmodule() throws {
        let submodule = try rawSource(Self.submoduleShapesPath + "/Metal/LiquidGlassShapes.metal")
        let actual = try rawSource("packages/SceneEffects/Sources/LiquidGlassShapes/LiquidGlassShapes.metal")
        XCTAssertEqual(normalizedShader(actual), normalizedShader(submodule))
        XCTAssertGreaterThan(normalizedShader(actual).count, 10_000)
    }

    func testConstantsMatchSubmodule() throws {
        let path = Self.submoduleBlobPath
        XCTAssertEqual(Double(ChatRecordingBlobAppearance.maxLevel), try number(in: path, "static let maxLevel: CGFloat = ([0-9.]+)"))
        XCTAssertEqual(Double(ChatRecordingBlobAppearance.levelSmoothing), try number(in: path, "static let levelSmoothing: CGFloat = ([0-9.]+)"))
        XCTAssertEqual(Double(ChatRecordingBlobAppearance.centreScale), try number(in: path, "static let centreScale: Float = ([0-9.]+)"), accuracy: 1e-7)
        XCTAssertEqual(Double(ChatRecordingBlobAppearance.restingPresence), try number(in: path, "static let restingPresence: CGFloat = ([0-9.]+)"))
        XCTAssertEqual(ChatRecordingBlobAppearance.presenceInDuration, try number(in: path, "static let presenceInDuration: Double = ([0-9.]+)"))
        XCTAssertEqual(ChatRecordingBlobAppearance.presenceOutDuration, try number(in: path, "static let presenceOutDuration: Double = ([0-9.]+)"))

        let outer = try numbers(in: path, "outerWaveScales: ClosedRange<CGFloat> = \\(([0-9.]+) \\* ([0-9.]+)\\) \\.\\.\\. \\(CGFloat\\(centreScale\\) \\* goldenRatio \\* goldenRatio\\)")
        XCTAssertEqual(outer.count, 2)
        let goldenRatio = (1.0 + sqrt(5.0)) / 2.0
        XCTAssertEqual(Double(ChatRecordingBlobAppearance.outerWaveScales.lowerBound), outer[0] * outer[1], accuracy: 1e-12)
        XCTAssertEqual(Double(ChatRecordingBlobAppearance.outerWaveScales.upperBound), Double(Float(0.45)) * goldenRatio * goldenRatio, accuracy: 1e-12)

        let motion = try numbers(in: path, "waveMotion = ChatRecordingBlobMotion.Parameters\\(minRandomness: ([0-9.]+), maxRandomness: ([0-9.]+), minSpeed: ([0-9.]+), maxSpeed: ([0-9.]+)\\)")
        let actualMotion = ChatRecordingBlobAppearance.waveMotion
        XCTAssertEqual(motion, [Double(actualMotion.minRandomness), Double(actualMotion.maxRandomness), Double(actualMotion.minSpeed), Double(actualMotion.maxSpeed)])

        let angle = 2.0 * Double.pi / 8.0
        XCTAssertEqual(ChatRecordingBlobAppearance.smoothness, Float(((4.0 / 3.0) * tan(angle / 4.0)) / sin(angle / 2.0) / 2.0))
        XCTAssertEqual(try number(in: Self.submoduleShapesPath + "/Sources/LiquidGlassShapesTypes.swift", "radialPointCount = ([0-9]+)"), Double(LiquidGlassShapesConstants.radialPointCount))
        XCTAssertEqual(try number(in: Self.submoduleShapesPath + "/Sources/LiquidGlassShapesTypes.swift", "radialSampleCount = ([0-9]+)"), Double(LiquidGlassShapesConstants.radialSampleCount))
        XCTAssertEqual(try number(in: Self.submoduleShapesPath + "/Sources/LiquidGlassShapesTypes.swift", "crestSampleCount = ([0-9]+)"), Double(LiquidGlassShapesConstants.crestSampleCount))
        XCTAssertEqual(try number(in: Self.submoduleShapesPath + "/Sources/LiquidGlassShapesTypes.swift", "displacementAmount: Float = ([0-9.]+)"), Double(LiquidGlassShapesConstants.displacementAmount))
    }

    func testAppearanceMatchesSubmodule() throws {
        let path = Self.submoduleBlobPath
        let pattern = "LiquidGlassLayerStyle\\(alpha: ([0-9.]+), fill: ([0-9.]+), saturation: ([0-9.]+), matte: ([0-9.]+), rim: ([0-9.]+), refracts: true, plainAlpha: ([0-9.]+)\\)"
        let text = try source(path)
        let regex = try NSRegularExpression(pattern: pattern)
        let plainLayers = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1 ..< match.numberOfRanges).compactMap { index in Range(match.range(at: index), in: text).flatMap { Double(text[$0]) } }
        }
        XCTAssertEqual(plainLayers.count, 2)
        let matte = try numbers(in: path, "LiquidGlassLayerStyle\\(alpha: ([0-9.]+), fill: ([0-9.]+), saturation: ([0-9.]+), matte: isDarkAppearance \\? ([0-9.]+) : ([0-9.]+), rim: ([0-9.]+), refracts: true, plainAlpha: ([0-9.]+)\\)")
        XCTAssertEqual(matte.count, 7)
        let shadowStrength = try number(in: path, "shadowStrength: mode == \\.glass \\? ([0-9.]+) : 0\\.0")
        let rest = try numbers(in: path, "shadowBlur: ([0-9.]+), shadowDrop: ([0-9.]+), rimWidth: ([0-9.]+), rimDarkAppearanceScale: ([0-9.]+), glassBand: ([0-9.]+), glassShift: ([0-9.]+)")
        XCTAssertEqual(rest.count, 6)

        for mode in [LiquidGlassRenderMode.plain, .glass, .flat] {
            for isDark in [false, true] {
                let actual = ChatRecordingBlobAppearance.appearance(mode: mode, isDarkAppearance: isDark)
                XCTAssertEqual(actual.layers.count, 3)
                for (index, layer) in plainLayers.enumerated() {
                    let style = actual.layers[index]
                    XCTAssertEqual([Double(style.alpha), Double(style.fill), Double(style.saturation), Double(style.matte), Double(style.rim), Double(style.plainAlpha)], layer.map { Double(Float($0)) })
                    XCTAssertTrue(style.refracts)
                }
                let main = actual.layers[2]
                XCTAssertEqual(Double(main.alpha), Double(Float(matte[0])))
                XCTAssertEqual(Double(main.fill), Double(Float(matte[1])))
                XCTAssertEqual(Double(main.saturation), Double(Float(matte[2])))
                XCTAssertEqual(Double(main.matte), Double(Float(isDark ? matte[3] : matte[4])))
                XCTAssertEqual(Double(main.rim), Double(Float(matte[5])))
                XCTAssertEqual(Double(main.plainAlpha), Double(Float(matte[6])))
                XCTAssertTrue(main.refracts)
                XCTAssertEqual(Double(actual.shadowStrength), mode == .glass ? Double(Float(shadowStrength)) : 0.0)
                XCTAssertEqual([Double(actual.shadowBlur), Double(actual.shadowDrop), Double(actual.rimWidth), Double(actual.rimDarkAppearanceScale), Double(actual.glassBand), Double(actual.glassShift)], rest.map { Double(Float($0)) })
            }
        }
    }

    func testOverflowMatchesSubmodule() throws {
        try XCTAssertTrue(source(Self.submoduleBlobViewPath).contains("let outlineReach = side * 0.5 * ChatRecordingBlobAppearance.outerWaveScales.upperBound * 1.05 return ceil(max(0.0, outlineReach - side * 0.5) + CGFloat(appearance.shadowDrop + 3.0 * appearance.shadowBlur + appearance.rimWidth * 0.5))"))
        for side: CGFloat in [88.0 + 8.0 / 9.0, 400.0 / 3.0, 220.0] {
            let reach = side * 0.5 * ChatRecordingBlobAppearance.outerWaveScales.upperBound * 1.05
            let expected = ceil(max(0.0, reach - side * 0.5) + CGFloat(Float(2.0) + 3.0 * Float(6.0) + Float(1.0) * 0.5))
            XCTAssertEqual(ChatRecordingBlobAppearance.overflow(side: side), expected)
        }
        XCTAssertEqual(ChatRecordingBlobAppearance.side(centreDiameter: 60) * CGFloat(ChatRecordingBlobAppearance.centreScale), 60, accuracy: 1e-5)
    }

    func testMotionMatchesSubmodule() throws {
        try XCTAssertTrue(source(Self.submoduleBlobPath).contains("let radius = (rangeStart + self.random() * (1.0 - rangeStart)) / 2.0 let angleRandomness = angle * 0.1 let pointAngle = angle + angle * (angleRandomness * self.random() - angleRandomness * 0.5)"))
        try XCTAssertTrue(source(Self.submoduleBlobPath).contains("self.duration = 1.0 / max(speed, 0.05) self.speedLevel = 0.0"))
        try XCTAssertTrue(source(Self.submoduleBlobViewPath).contains("bezierPoint(0.42, 0.0, 0.58, 1.0, $0)"))

        let parameters = ChatRecordingBlobAppearance.waveMotion
        let actualRandom = RandomBox(seed: 7)
        let submoduleRandom = RandomBox(seed: 7)
        let actual = ChatRecordingBlobMotion(parameters: parameters, random: actualRandom.next)
        let submodule = SubmoduleBlobMotion(parameters: .init(minRandomness: parameters.minRandomness, maxRandomness: parameters.maxRandomness, minSpeed: parameters.minSpeed, maxSpeed: parameters.maxSpeed), random: submoduleRandom.next)
        let easing: (CGFloat) -> CGFloat = { submoduleBezierPoint(0.42, 0.0, 0.58, 1.0, $0) }

        for step in 0 ..< 600 {
            let level = CGFloat((step * 37) % 101) / 100.0
            if step % 3 == 0 {
                actual.updateSpeedLevel(level)
                submodule.updateSpeedLevel(level)
            }
            let delta = CGFloat(1.0 / 60.0) * (step % 7 == 0 ? 3.0 : 1.0)
            actual.advance(by: delta)
            submodule.advance(by: delta)
            XCTAssertEqual(actual.fromPoints, submodule.fromPoints)
            XCTAssertEqual(actual.toPoints, submodule.toPoints)
            XCTAssertEqual(actual.duration, submodule.duration)
            let shape = actual.radialShape(scale: 0.8, easing: ChatRecordingBlobAppearance.easing)
            XCTAssertEqual(shape.progress, submodule.progress(easing: easing), accuracy: 1e-6)
            XCTAssertEqual(shape.scale, 0.8)
            XCTAssertEqual(shape.fromPoints.0, submodule.fromPoints[0])
            XCTAssertEqual(shape.toPoints.7, submodule.toPoints[7])
        }
    }

    func testPresenceMatchesSubmodule() {
        let easing: (CGFloat) -> CGFloat = { submoduleBezierPoint(0.42, 0.0, 0.58, 1.0, $0) }
        var actual = ChatRecordingBlobPresence(value: ChatRecordingBlobAppearance.restingPresence, easing: ChatRecordingBlobAppearance.easing)
        var submodule = SubmoduleBlobPresence(value: 0.75, easing: easing)
        actual.animate(to: 1.0, duration: ChatRecordingBlobAppearance.presenceInDuration)
        submodule.animate(to: 1.0, duration: 0.35)
        for step in 0 ..< 40 {
            if step == 12 {
                actual.animate(to: ChatRecordingBlobAppearance.restingPresence, duration: ChatRecordingBlobAppearance.presenceOutDuration)
                submodule.animate(to: 0.75, duration: 0.15)
            }
            if step == 30 {
                actual.animate(to: 1.0, duration: 0.35, canAdvance: false)
                submodule.animate(to: 1.0, duration: 0.35, canAdvance: false)
            }
            actual.advance(by: 1.0 / 60.0)
            submodule.advance(by: 1.0 / 60.0)
            XCTAssertEqual(actual.value, submodule.value, accuracy: 1e-12)
            XCTAssertEqual(actual.isSettled, submodule.isSettled)
        }
        actual.settle(at: 0.75)
        submodule.settle(at: 0.75)
        XCTAssertEqual(actual.value, submodule.value)
        XCTAssertTrue(actual.isSettled)
    }

    func testRadialParametersMatchSubmodule() throws {
        try XCTAssertTrue(source(Self.submoduleBlobPath).contains("let outerScale = (scales.lowerBound + (scales.upperBound - scales.lowerBound) * level) * presence"))
        try XCTAssertTrue(source(Self.submoduleBlobPath).contains("let middleScale = sqrt(CGFloat(ChatRecordingBlobAppearance.centreScale) * outerScale)"))
        let random = RandomBox(seed: 3)
        let outer = ChatRecordingBlobMotion(parameters: ChatRecordingBlobAppearance.waveMotion, random: random.next)
        let middle = ChatRecordingBlobMotion(parameters: ChatRecordingBlobAppearance.waveMotion, random: random.next)
        for level: CGFloat in [0.0, 0.3, 1.0] {
            for presence: CGFloat in [0.75, 0.9, 1.0] {
                let parameters = ChatRecordingBlobAppearance.radialParameters(outer: outer, middle: middle, size: 120, level: level, presence: presence, easing: ChatRecordingBlobAppearance.easing)
                let scales = ChatRecordingBlobAppearance.outerWaveScales
                let outerScale = (scales.lowerBound + (scales.upperBound - scales.lowerBound) * level) * presence
                XCTAssertEqual(parameters.shapes.0.scale, Float(outerScale))
                XCTAssertEqual(parameters.shapes.1.scale, Float(sqrt(0.45 * Double(outerScale))), accuracy: 1e-6)
                XCTAssertEqual(parameters.shapes.2.scale, 0.45)
                XCTAssertEqual(parameters.size, 120)
                XCTAssertEqual(parameters.smoothness, ChatRecordingBlobAppearance.smoothness)
            }
        }
        let flat = ChatRecordingBlobAppearance.radialParameters(outer: nil, middle: nil, size: 120, level: 1, presence: 1, easing: ChatRecordingBlobAppearance.easing)
        XCTAssertEqual(flat.shapes.0.scale, 0.45)
        XCTAssertEqual(flat.shapes.1.scale, 0.45)
        XCTAssertEqual(flat.shapes.0.fromPoints.2, SIMD2<Float>(Float(sin(Double.pi / 2) * 0.5), Float(cos(Double.pi / 2) * 0.5)))
    }

    func testFullLevelGrowsByTheGoldenRatio() {
        let parameters = ChatRecordingBlobAppearance.radialParameters(outer: ChatRecordingBlobMotion(parameters: ChatRecordingBlobAppearance.waveMotion), middle: ChatRecordingBlobMotion(parameters: ChatRecordingBlobAppearance.waveMotion), size: 100, level: 1, presence: 1, easing: ChatRecordingBlobAppearance.easing)
        let goldenRatio = Float((1.0 + sqrt(5.0)) / 2.0)
        XCTAssertEqual(parameters.shapes.1.scale / parameters.shapes.2.scale, goldenRatio, accuracy: 1e-5)
        XCTAssertEqual(parameters.shapes.0.scale / parameters.shapes.1.scale, goldenRatio, accuracy: 1e-5)
    }

    func testUniformsLayoutMatchesShader() {
        XCTAssertEqual(MemoryLayout<LiquidGlassShapesUniforms>.stride, 208)
        XCTAssertEqual(MemoryLayout<LiquidGlassRadialShape>.stride, 136)
        XCTAssertEqual(MemoryLayout<LiquidGlassRadialParameters>.stride, 416)
        XCTAssertEqual(MemoryLayout<LiquidGlassShapesUniforms>.offset(of: \LiquidGlassShapesUniforms.boundsSize), 128)
        XCTAssertEqual(MemoryLayout<LiquidGlassShapesUniforms>.offset(of: \LiquidGlassShapesUniforms.mode), 188)
        XCTAssertEqual(MemoryLayout<LiquidGlassShapesUniforms>.offset(of: \LiquidGlassShapesUniforms.shapeCenter), 192)
    }

    private func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        return device
    }

    private func radii(device: MTLDevice, parameters: LiquidGlassRadialParameters) throws -> (MTLBuffer, [Float]) {
        let pipeline = try XCTUnwrap(LiquidGlassShapesPipelines.shared.computePipelineState(device: device, functionName: LiquidGlassRadialKind.kernelFunctionName))
        let count = 3 * LiquidGlassShapesConstants.radialSampleCount
        let buffer = try XCTUnwrap(device.makeBuffer(length: count * MemoryLayout<Float>.size, options: .storageModeShared))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        withUnsafeBytes(of: parameters) { bytes in
            encoder.setBytes(bytes.baseAddress!, length: MemoryLayout<LiquidGlassRadialParameters>.stride, index: 0)
        }
        encoder.setBuffer(buffer, offset: 0, index: 1)
        let threads = min(LiquidGlassShapesConstants.radialSampleCount, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreadgroups(MTLSize(width: 3, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let pointer = buffer.contents().bindMemory(to: Float.self, capacity: count)
        return (buffer, Array(UnsafeBufferPointer(start: pointer, count: count)))
    }

    private func scaledCircle(_ factor: Float) -> LiquidGlassRadialPoints {
        let circle = LiquidGlassRadialShape.circle(scale: 1).fromPoints
        return (circle.0 * factor, circle.1 * factor, circle.2 * factor, circle.3 * factor, circle.4 * factor, circle.5 * factor, circle.6 * factor, circle.7 * factor)
    }

    func testRadialKernelReadsTheSwiftLayout() throws {
        let device = try device()
        let circle = LiquidGlassRadialShape.circle(scale: 1).fromPoints
        let half = scaledCircle(0.5)
        let parameters = LiquidGlassRadialParameters(
            shapes: (
                LiquidGlassRadialShape(fromPoints: circle, toPoints: half, progress: 0.0, scale: 1.0),
                LiquidGlassRadialShape(fromPoints: circle, toPoints: half, progress: 1.0, scale: 0.8),
                LiquidGlassRadialShape(fromPoints: circle, toPoints: half, progress: 0.25, scale: 0.45)
            ),
            size: 200,
            smoothness: ChatRecordingBlobAppearance.smoothness
        )
        let (_, values) = try radii(device: device, parameters: parameters)
        let expected: [Float] = [0.5 * 200 * 1.0, 0.25 * 200 * 0.8, (0.5 * 0.75 + 0.25 * 0.25) * 200 * 0.45]
        for shape in 0 ..< 3 {
            for sample in stride(from: 0, to: LiquidGlassShapesConstants.radialSampleCount, by: 5) {
                XCTAssertEqual(values[shape * LiquidGlassShapesConstants.radialSampleCount + sample], expected[shape], accuracy: expected[shape] * 0.001, "shape \(shape) sample \(sample)")
            }
        }
    }

    private func render(device: MTLDevice, fragment: String, uniforms: LiquidGlassShapesUniforms, samples: MTLBuffer, size: Int) throws -> [UInt8] {
        let pipeline = try XCTUnwrap(LiquidGlassShapesPipelines.shared.renderPipelineState(device: device, fragmentFunctionName: fragment, shapeKind: .radial))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        var rect = SIMD4<Float>(0, 0, 1, 1)
        encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        var uniforms = uniforms
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LiquidGlassShapesUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(samples, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(&bytes, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        return bytes
    }

    func testRenderPassesReadTheSwiftUniforms() throws {
        let device = try device()
        let side: Float = 100
        let parameters = ChatRecordingBlobAppearance.radialParameters(outer: nil, middle: nil, size: side, level: 0, presence: 1, easing: ChatRecordingBlobAppearance.easing)
        let (samples, _) = try radii(device: device, parameters: parameters)
        let edgeInset = LiquidGlassShapesLayer.Constants.edgeInset
        let renderSide = 100
        let size = renderSide + 2 * edgeInset
        let color = SIMD4<Float>(0.2, 0.4, 0.6, 1.0)

        func uniforms(_ mode: LiquidGlassRenderMode) -> LiquidGlassShapesUniforms {
            var uniforms = LiquidGlassShapesUniforms(appearance: ChatRecordingBlobAppearance.appearance(mode: mode, isDarkAppearance: false), colors: (color, color), boundsSize: CGSize(width: 100, height: 100), gradientLength: 1, shapeCenter: SIMD2<Float>(50, 50), mode: mode, isDarkAppearance: false, edgeInset: Float(edgeInset))
            uniforms.renderSize = SIMD2<Float>(Float(renderSide), Float(renderSide))
            return uniforms
        }
        func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> (b: Int, g: Int, r: Int, a: Int) {
            let index = ((y + edgeInset) * size + x + edgeInset) * 4
            return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]), Int(bytes[index + 3]))
        }

        let flat = try render(device: device, fragment: LiquidGlassContentPass.fragmentFunctionName, uniforms: uniforms(.flat), samples: samples, size: size)
        let centre = pixel(flat, 50, 50)
        XCTAssertEqual(centre.r, 51, accuracy: 1)
        XCTAssertEqual(centre.g, 102, accuracy: 1)
        XCTAssertEqual(centre.b, 153, accuracy: 1)
        XCTAssertEqual(centre.a, 255)
        XCTAssertEqual(pixel(flat, 2, 2).a, 0)
        XCTAssertEqual(pixel(flat, 50, 50 - 22).a, 255)
        XCTAssertEqual(pixel(flat, 50, 50 - 24).a, 0)

        let mask = try render(device: device, fragment: LiquidGlassBackdropMaskPass.fragmentFunctionName, uniforms: uniforms(.glass), samples: samples, size: size)
        XCTAssertEqual(pixel(mask, 50, 50).a, 255)
        XCTAssertEqual(pixel(mask, 50 + 21, 50).a, 255)
        XCTAssertEqual(pixel(mask, 50 + 24, 50).a, 0)

        let displacement = try render(device: device, fragment: LiquidGlassDisplacementPass.fragmentFunctionName, uniforms: uniforms(.glass), samples: samples, size: size)
        let still = pixel(displacement, 50, 50)
        XCTAssertEqual(still.r, 128, accuracy: 1)
        XCTAssertEqual(still.g, 128, accuracy: 1)
        XCTAssertGreaterThan(pixel(displacement, 50 + 20, 50).r, 140)
        XCTAssertLessThan(pixel(displacement, 50 - 20, 50).r, 116)
        XCTAssertLessThan(pixel(displacement, 50, 50 - 20).g, 116)
        XCTAssertGreaterThan(pixel(displacement, 50, 50 + 20).g, 140)
    }
}
