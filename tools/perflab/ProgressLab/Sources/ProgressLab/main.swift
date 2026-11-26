import AppKit
import QuartzCore
@testable import TGUIKit

private typealias WindowCaptureFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

private let windowCapture: WindowCaptureFunction = {
    let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage")!
    return unsafeBitCast(symbol, to: WindowCaptureFunction.self)
}()

private func log(_ text: String) {
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
}

private func rgb(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: alpha)
}

private enum Palette {
    static let chat = rgb(0x0e1621)
    static let incoming = rgb(0x182533)
    static let outgoing = rgb(0x2b5278)
    static let accent = rgb(0x5eb5f7)
    static let overlay = NSColor.black.withAlphaComponent(0.5)
}

private func glyph(_ size: CGFloat, color: NSColor, draw: (CGContext, CGFloat) -> Void) -> CGImage {
    let scale = System.backingScale
    let pixels = Int(size * scale)
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(color.cgColor)
    context.setStrokeColor(color.cgColor)
    draw(context, size)
    return context.makeImage()!
}

private func playIcon(_ color: NSColor) -> CGImage {
    return glyph(16, color: color) { context, size in
        context.move(to: CGPoint(x: 4, y: 2))
        context.addLine(to: CGPoint(x: 14, y: 8))
        context.addLine(to: CGPoint(x: 4, y: 14))
        context.closePath()
        context.fillPath()
    }
}

private func fileIcon(_ color: NSColor) -> CGImage {
    return glyph(16, color: color) { context, size in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 3, y: 1))
        path.addLine(to: CGPoint(x: 13, y: 1))
        path.addLine(to: CGPoint(x: 13, y: 11))
        path.addLine(to: CGPoint(x: 9, y: 15))
        path.addLine(to: CGPoint(x: 3, y: 15))
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }
}

private func stopIcon(_ color: NSColor) -> CGImage {
    return glyph(10, color: color) { context, size in
        context.fill(CGRect(x: 2, y: 2, width: 6, height: 6))
    }
}

private struct LabCase {
    let name: String
    let size: CGFloat
    let theme: () -> RadialProgressTheme
    let backdrop: NSColor?
    let photo: Bool
    let done: () -> RadialProgressState?
    let fadesOut: Bool
}

private func makeCases() -> [LabCase] {
    return [
        LabCase(name: "file in", size: 40, theme: { RadialProgressTheme(backgroundColor: Palette.accent, foregroundColor: Palette.incoming) }, backdrop: Palette.incoming, photo: false, done: { .Icon(image: fileIcon(Palette.incoming)) }, fadesOut: false),
        LabCase(name: "file out", size: 40, theme: { RadialProgressTheme(backgroundColor: .white, foregroundColor: Palette.outgoing, blendMode: .clear) }, backdrop: Palette.outgoing, photo: false, done: { .Icon(image: fileIcon(.white)) }, fadesOut: false),
        LabCase(name: "thumb", size: 40, theme: { RadialProgressTheme(backgroundColor: Palette.overlay, foregroundColor: .white) }, backdrop: nil, photo: true, done: { nil }, fadesOut: true),
        LabCase(name: "photo", size: 40, theme: { RadialProgressTheme(backgroundColor: Palette.overlay, foregroundColor: .white) }, backdrop: nil, photo: true, done: { .None }, fadesOut: true),
        LabCase(name: "video", size: 40, theme: { RadialProgressTheme(backgroundColor: Palette.overlay, foregroundColor: .white, icon: playIcon(.white)) }, backdrop: nil, photo: true, done: { .Play }, fadesOut: false),
        LabCase(name: "voice in", size: 40, theme: { RadialProgressTheme(backgroundColor: Palette.accent, foregroundColor: Palette.incoming, icon: playIcon(Palette.incoming), iconInset: NSEdgeInsets(left: 1)) }, backdrop: Palette.incoming, photo: false, done: { .Icon(image: playIcon(Palette.incoming)) }, fadesOut: false),
        LabCase(name: "voice out", size: 40, theme: { RadialProgressTheme(backgroundColor: .white, foregroundColor: Palette.outgoing, icon: playIcon(.white), iconInset: NSEdgeInsets(left: 1), blendMode: .clear) }, backdrop: Palette.outgoing, photo: false, done: { .Icon(image: playIcon(.white)) }, fadesOut: false),
        LabCase(name: "album 30", size: 30, theme: { RadialProgressTheme(backgroundColor: Palette.overlay, foregroundColor: .white) }, backdrop: nil, photo: true, done: { .None }, fadesOut: true),
        LabCase(name: "small 22", size: 22, theme: { RadialProgressTheme(backgroundColor: Palette.overlay, foregroundColor: .white) }, backdrop: nil, photo: true, done: { .None }, fadesOut: false),
        LabCase(name: "tiny 18", size: 18, theme: { RadialProgressTheme(backgroundColor: Palette.overlay, foregroundColor: .white) }, backdrop: nil, photo: true, done: { .None }, fadesOut: false),
        LabCase(name: "stream 24", size: 24, theme: { RadialProgressTheme(backgroundColor: .clear, foregroundColor: .white, cancelFetchingIcon: stopIcon(.white)) }, backdrop: nil, photo: true, done: { .None }, fadesOut: false),
    ]
}

private final class LabCell: NSView {
    let labCase: LabCase
    let progress: RadialProgressView

    init(frame: NSRect, labCase: LabCase) {
        self.labCase = labCase
        self.progress = RadialProgressView(theme: labCase.theme(), twist: true, size: NSMakeSize(labCase.size, labCase.size))
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.cornerRadius = 14
        self.layer?.masksToBounds = true
        if labCase.photo {
            let gradient = CAGradientLayer()
            gradient.frame = self.bounds
            gradient.colors = [rgb(0xd9a441).cgColor, rgb(0x8a3f7a).cgColor, rgb(0x2f6f8f).cgColor]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            self.layer?.addSublayer(gradient)
        } else {
            self.layer?.backgroundColor = labCase.backdrop?.cgColor
        }
        self.addSubview(self.progress)
        self.progress.setFrameOrigin(NSMakePoint(floor((frame.width - labCase.size) / 2), floor((frame.height - labCase.size) / 2)))
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func reset(_ state: RadialProgressState) {
        self.progress.layer?.removeAllAnimations()
        self.progress.alphaValue = 1
        self.progress.layer?.opacity = 1
        self.progress.theme = self.labCase.theme()
        self.progress.state = state
    }

    func finish(animated: Bool) {
        if let done = self.labCase.done() {
            self.progress.setState(done, animated: animated)
        } else if case .Fetching = self.progress.state {
            self.progress.setState(.Fetching(progress: 1, force: false), animated: animated)
        }
        if self.labCase.fadesOut {
            if animated {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 1
                animation.toValue = 0
                animation.duration = 0.25
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                animation.isRemovedOnCompletion = false
                animation.fillMode = .forwards
                self.progress.layer?.add(animation, forKey: "fade")
            } else {
                self.progress.layer?.opacity = 0
            }
        }
    }
}

private enum Action {
    case state(RadialProgressState, animated: Bool)
    case progress(Float)
    case finish(animated: Bool)
}

private struct Scenario {
    let name: String
    let initial: RadialProgressState
    let reduceMotion: Bool
    let duration: Double
    let steps: [(Double, Action)]
    let expectation: (LabCell) -> String?
}

private func fetching(_ value: Float) -> RadialProgressState {
    return .Fetching(progress: value, force: false)
}

private func expectAtRest(_ cell: LabCell, morph: CGFloat?, ring: CGFloat) -> String? {
    let values = cell.progress.displayedValuesForTesting
    var problems: [String] = []
    if values.swap != nil {
        problems.append("swap still running")
    }
    if abs(values.ring - ring) > 0.001 {
        problems.append("ring \(values.ring) != \(ring)")
    }
    if let morph = morph, abs(values.morph - morph) > 0.001 {
        problems.append("morph \(values.morph) != \(morph)")
    }
    return problems.isEmpty ? nil : problems.joined(separator: ", ")
}

private func makeScenarios() -> [Scenario] {
    return [
        Scenario(name: "download", initial: .Remote, reduceMotion: false, duration: 1.9, steps: [
            (0.15, .state(fetching(0.1), animated: true)),
            (0.45, .progress(0.25)),
            (0.7, .progress(0.5)),
            (0.95, .progress(0.8)),
            (1.15, .progress(1.0)),
            (1.3, .finish(animated: true)),
        ], expectation: { cell in cell.labCase.fadesOut ? nil : expectAtRest(cell, morph: nil, ring: 0) }),
        Scenario(name: "cancel", initial: .Remote, reduceMotion: false, duration: 1.5, steps: [
            (0.15, .state(fetching(0.1), animated: true)),
            (0.5, .progress(0.35)),
            (0.8, .state(.Remote, animated: true)),
        ], expectation: { cell in expectAtRest(cell, morph: cell.labCase.name == "stream 24" ? nil : 0, ring: 0) }),
        Scenario(name: "toggle", initial: .Remote, reduceMotion: false, duration: 1.8, steps: [
            (0.15, .state(fetching(0.1), animated: true)),
            (0.27, .state(.Remote, animated: true)),
            (0.39, .state(fetching(0.1), animated: true)),
            (0.6, .progress(0.4)),
            (0.85, .state(.Remote, animated: true)),
            (0.95, .state(fetching(0.4), animated: true)),
        ], expectation: { cell in expectAtRest(cell, morph: cell.labCase.name == "stream 24" ? nil : 1, ring: 1) }),
        Scenario(name: "upload", initial: fetching(0.05), reduceMotion: false, duration: 1.4, steps: [
            (0.15, .progress(0.3)),
            (0.4, .progress(0.65)),
            (0.6, .progress(1.0)),
            (0.75, .finish(animated: true)),
        ], expectation: { cell in cell.labCase.fadesOut ? nil : expectAtRest(cell, morph: nil, ring: 0) }),
        Scenario(name: "instant", initial: .Remote, reduceMotion: false, duration: 0.8, steps: [
            (0.15, .finish(animated: true)),
        ], expectation: { cell in cell.labCase.fadesOut ? nil : expectAtRest(cell, morph: nil, ring: 0) }),
        Scenario(name: "reduce-motion", initial: .Remote, reduceMotion: true, duration: 1.4, steps: [
            (0.15, .state(fetching(0.1), animated: true)),
            (0.45, .progress(0.4)),
            (0.75, .state(.Remote, animated: true)),
        ], expectation: { cell in expectAtRest(cell, morph: nil, ring: 0) }),
        Scenario(name: "reuse", initial: .Remote, reduceMotion: false, duration: 0.9, steps: [
            (0.15, .state(fetching(0.5), animated: false)),
            (0.4, .state(.Remote, animated: false)),
            (0.6, .finish(animated: false)),
        ], expectation: { cell in cell.labCase.fadesOut ? nil : expectAtRest(cell, morph: nil, ring: 0) }),
    ]
}

private final class Recorder {
    private let queue = DispatchQueue(label: "progresslab.capture", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var frames: [(CFTimeInterval, CGImage)] = []

    func start(windowNumber: Int, origin: CFTimeInterval) {
        self.frames = []
        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            let before = CACurrentMediaTime()
            guard let image = windowCapture(.null, 8, UInt32(windowNumber), 1 | 8)?.takeRetainedValue() else {
                return
            }
            let time = (before + CACurrentMediaTime()) / 2 - origin
            self?.lock.lock()
            self?.frames.append((time, image))
            self?.lock.unlock()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() -> [(CFTimeInterval, CGImage)] {
        self.timer?.cancel()
        self.timer = nil
        self.queue.sync {}
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.frames
    }
}

private struct Sample {
    let time: CFTimeInterval
    let values: [(progress: CGFloat, ring: CGFloat, morph: CGFloat, swap: CGFloat?)]
}

private final class Lab {
    let output: String
    let only: Set<String>?
    let range: (Double, Double)?
    let closeUp: Bool
    let cellSize = NSMakeSize(84, 84)
    let spacing: CGFloat = 12
    var window: NSWindow!
    var cells: [LabCell] = []
    let recorder = Recorder()
    var samples: [Sample] = []
    var sampler: ConstantDisplayLinkAnimator?
    var report: [String] = []

    init(output: String, only: Set<String>?, range: (Double, Double)?, closeUp: Bool) {
        self.output = output
        self.only = only
        self.range = range
        self.closeUp = closeUp
    }

    func start() {
        let screen = NSScreen.screens.first!
        System.updateScaleFactor(screen.backingScaleFactor)
        let cases = makeCases()
        let width = CGFloat(cases.count) * (self.cellSize.width + self.spacing) + self.spacing
        let height = self.cellSize.height + self.spacing * 2
        let frame = NSMakeRect(screen.visibleFrame.minX + 40, screen.visibleFrame.maxY - height - 40, width, height)
        self.window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        self.window.isReleasedWhenClosed = false
        self.window.level = .floating
        self.window.appearance = NSAppearance(named: .darkAqua)
        let content = NSView(frame: NSMakeRect(0, 0, width, height))
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.chat.cgColor
        self.window.contentView = content
        for (index, labCase) in cases.enumerated() {
            let cell = LabCell(frame: NSMakeRect(self.spacing + CGFloat(index) * (self.cellSize.width + self.spacing), self.spacing, self.cellSize.width, self.cellSize.height), labCase: labCase)
            content.addSubview(cell)
            self.cells.append(cell)
        }
        self.window.orderFrontRegardless()
        log("window \(self.window.windowNumber) \(self.window.frame)")
        self.report.append("screen \(screen.localizedName) maxFPS \(screen.maximumFramesPerSecond) scale \(screen.backingScaleFactor)")
        let scenarios = makeScenarios().filter { self.only?.contains($0.name) ?? true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.run(scenarios, index: 0)
        }
    }

    func run(_ scenarios: [Scenario], index: Int) {
        guard index < scenarios.count else {
            self.finish()
            return
        }
        let scenario = scenarios[index]
        log("scenario \(scenario.name)")
        RadialProgressView.reduceMotion = { scenario.reduceMotion }
        for cell in self.cells {
            cell.reset(scenario.initial)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let origin = CACurrentMediaTime()
            self.samples = []
            self.sampler = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] _ in
                guard let self = self else {
                    return
                }
                self.samples.append(Sample(time: CACurrentMediaTime() - origin, values: self.cells.map { $0.progress.displayedValuesForTesting }))
            })
            self.sampler?.isPaused = false
            self.recorder.start(windowNumber: self.window.windowNumber, origin: origin)
            for (time, action) in scenario.steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                    for cell in self.cells {
                        switch action {
                        case let .state(state, animated):
                            cell.progress.setState(state, animated: animated)
                        case let .progress(value):
                            if case .Fetching = cell.progress.state {
                                cell.progress.setState(fetching(value), animated: true)
                            }
                        case let .finish(animated):
                            cell.finish(animated: animated)
                        }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + scenario.duration) {
                let frames = self.recorder.stop()
                log("captured \(frames.count) samples \(self.samples.count)")
                self.sampler?.isPaused = true
                self.sampler = nil
                self.summarize(scenario, frames: frames)
                self.writeSheet(scenario, frames: frames)
                self.run(scenarios, index: index + 1)
            }
        }
    }

    func summarize(_ scenario: Scenario, frames: [(CFTimeInterval, CGImage)]) {
        let ticks = self.samples.count
        let span = (self.samples.last?.time ?? 0) - (self.samples.first?.time ?? 0)
        var gaps: [CFTimeInterval] = []
        for index in 1 ..< max(1, self.samples.count) {
            gaps.append(self.samples[index].time - self.samples[index - 1].time)
        }
        let maxGap = gaps.max() ?? 0
        self.report.append(String(format: "\n[%@] sampler %d ticks over %.2fs = %.0f Hz, max gap %.1f ms, %d captures", scenario.name, ticks, span, span > 0 ? Double(ticks - 1) / span : 0, maxGap * 1000, frames.count))
        for (index, cell) in self.cells.enumerated() {
            var updates = 0
            var maxMorphStep: CGFloat = 0
            var maxProgressStep: CGFloat = 0
            var maxRingStep: CGFloat = 0
            for sample in 1 ..< max(1, self.samples.count) {
                let a = self.samples[sample - 1].values[index]
                let b = self.samples[sample].values[index]
                if a.progress != b.progress || a.ring != b.ring || a.morph != b.morph || a.swap != b.swap {
                    updates += 1
                }
                maxMorphStep = max(maxMorphStep, abs(b.morph - a.morph))
                maxProgressStep = max(maxProgressStep, abs(b.progress - a.progress))
                maxRingStep = max(maxRingStep, abs(b.ring - a.ring))
            }
            let problem = scenario.expectation(cell)
            self.report.append(String(format: "  %-10@ updates %3d  max step morph %.3f progress %.3f ring %.3f  %@", cell.labCase.name as NSString, updates, maxMorphStep, maxProgressStep, maxRingStep, (problem.map { "FAIL: " + $0 } ?? "ok") as NSString))
        }
    }

    func writeSheet(_ scenario: Scenario, frames: [(CFTimeInterval, CGImage)]) {
        guard let first = frames.first?.1 else {
            self.report.append("  no captures")
            return
        }
        let scale = CGFloat(first.width) / self.window.frame.width
        let columns = 26
        let cell = 64
        let labelWidth = 90
        let headerHeight = 18
        let width = labelWidth + columns * cell
        let height = headerHeight + self.cells.count * cell
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(rgb(0x202830).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white]
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.lightGray]
        for column in 0 ..< columns {
            let (from, to) = self.range ?? (0, scenario.duration)
            let time = from + (to - from) * Double(column) / Double(columns - 1)
            let frame = frames.min(by: { abs($0.0 - time) < abs($1.0 - time) })!
            ("\(Int(time * 1000))" as NSString).draw(at: NSPoint(x: labelWidth + column * cell + 4, y: height - headerHeight + 4), withAttributes: small)
            for (row, labCell) in self.cells.enumerated() {
                let rect = labCell.convert(self.closeUp ? labCell.progress.frame.insetBy(dx: -3, dy: -3) : labCell.bounds.insetBy(dx: 10, dy: 10), to: nil)
                let crop = CGRect(x: rect.minX * scale, y: (self.window.frame.height - rect.maxY) * scale, width: rect.width * scale, height: rect.height * scale)
                if let image = frame.1.cropping(to: crop) {
                    context.draw(image, in: CGRect(x: labelWidth + column * cell + 1, y: height - headerHeight - (row + 1) * cell + 1, width: cell - 2, height: cell - 2))
                }
            }
        }
        for (row, labCell) in self.cells.enumerated() {
            (labCell.labCase.name as NSString).draw(at: NSPoint(x: 6, y: height - headerHeight - (row + 1) * cell + cell / 2 - 7), withAttributes: attributes)
        }
        (scenario.name as NSString).draw(at: NSPoint(x: 6, y: height - headerHeight + 3), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let path = "\(self.output)/\(scenario.name)\(self.range == nil ? "" : "-zoom")\(self.closeUp ? "-closeup" : "").png"
        try? NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    func finish() {
        let text = self.report.joined(separator: "\n") + "\n"
        print(text)
        try? text.write(toFile: "\(self.output)/report.txt", atomically: true, encoding: .utf8)
        exit(0)
    }
}

var output = FileManager.default.currentDirectoryPath + "/progresslab-out"
var only: Set<String>?
var range: (Double, Double)?
var closeUp = false
var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let name = arguments.removeFirst()
    let value = arguments.isEmpty ? "" : arguments.removeFirst()
    switch name {
    case "--out":
        output = value
    case "--only":
        only = Set(value.split(separator: ",").map(String.init))
    case "--closeup":
        closeUp = true
        arguments.insert(value, at: 0)
    case "--range":
        let parts = value.split(separator: ",").compactMap { Double($0) }
        if parts.count == 2 {
            range = (parts[0], parts[1])
        }
    default:
        break
    }
}
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
private var namedImages: [NSImage] = []
for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.black.setFill()
        rect.insetBy(dx: 4, dy: 4).fill()
        return true
    }
    _ = image.setName(name)
    namedImages.append(image)
}
private let lab = Lab(output: output, only: only, range: range, closeUp: closeUp)
DispatchQueue.main.async {
    lab.start()
}
application.run()
