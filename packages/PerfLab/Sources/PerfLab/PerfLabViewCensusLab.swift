#if DEBUG
import AppKit

public final class PerfLabViewCensusLab {
    public struct Screen {
        public let name: String
        public let open: () -> Void

        public init(_ name: String, open: @escaping () -> Void) {
            self.name = name
            self.open = open
        }
    }

    private static var current: PerfLabViewCensusLab?

    private let configuration: PerfLabConfiguration
    private let window: NSWindow
    private let screens: [Screen]
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()

    @discardableResult
    public static func startIfRequested(window: NSWindow, outputDirectory: URL, screens: [Screen]) -> Bool {
        guard self.current == nil, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "view-census" else {
            return false
        }
        let lab = PerfLabViewCensusLab(configuration: configuration, window: window, screens: screens)
        self.current = lab
        DispatchQueue.main.asyncAfter(deadline: .now() + configuration.double("-PerfLabStartDelay", 6.0)) {
            lab.run(index: 0)
        }
        return true
    }

    private init(configuration: PerfLabConfiguration, window: NSWindow, screens: [Screen]) {
        self.configuration = configuration
        self.window = window
        let wanted = Set(configuration.scenarios.filter { $0 != "warm" })
        self.screens = wanted.isEmpty ? screens : screens.filter { wanted.contains($0.name) }
        self.report = PerfLabReport(configuration: configuration)
    }

    private func run(index: Int) {
        guard index < self.screens.count else {
            _ = self.report.write()
            PerfLabViewCensusLab.current = nil
            if self.configuration.quitWhenDone {
                NSApp.terminate(nil)
            }
            return
        }
        let screen = self.screens[index]
        self.window.makeKeyAndOrderFront(nil)
        if self.configuration.double("-PerfLabFloatWindow", 1.0) != 0 {
            self.window.level = .floating
        }
        screen.open()
        DispatchQueue.main.asyncAfter(deadline: .now() + self.configuration.double("-PerfLabCensusDelay", 4.0)) { [weak self] in
            guard let self, let root = self.window.contentView else {
                return
            }
            root.layoutSubtreeIfNeeded()
            let census = PerfLabViewCensus.take(root)
            var metrics = census.metrics
            metrics["footprintMB"] = Double(self.processMonitor.snapshot().footprint) / 1048576.0
            var notes = census.notes(top: 60)
            for className in self.configuration.string("-PerfLabCensusTree", "").split(separator: ",") {
                if let tree = PerfLabViewCensus.tree(of: String(className), in: root) {
                    notes["tree.\(className)"] = tree
                }
            }
            if let path = self.snapshot(name: screen.name) {
                notes["snapshot"] = path
            }
            self.report.add(scenario: screen.name, run: 0, metrics: metrics, notes: notes)
            self.run(index: index + 1)
        }
    }

    private func snapshot(name: String) -> String? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            return nil
        }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        guard let image = create(.null, 1 << 3, UInt32(self.window.windowNumber), 1 << 0 | 1 << 3)?.takeRetainedValue() else {
            return nil
        }
        let url = self.configuration.outputDirectory.appendingPathComponent("\(self.configuration.label)-\(name).png")
        try? FileManager.default.createDirectory(at: self.configuration.outputDirectory, withIntermediateDirectories: true)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else {
            return nil
        }
        return url.path
    }
}
#endif
