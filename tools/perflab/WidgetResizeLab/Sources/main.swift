import AppKit
import TGUIKit

typealias Block = (id: String, height: CGFloat)

let padding: CGFloat = 8

func contentHeight(_ blocks: [Block]) -> CGFloat {
    return blocks.reduce(0) { $0 + $1.height }
}

func top(of id: String, in blocks: [Block]) -> CGFloat? {
    var y: CGFloat = 0
    for block in blocks {
        if block.id == id {
            return y
        }
        y += block.height
    }
    return nil
}

final class LabItem: TableRowItem {
    let blocks: [Block]
    let anchor: TableRowResizeAnchor?

    init(id: Int, blocks: [Block], anchor: TableRowResizeAnchor? = nil) {
        self.blocks = blocks
        self.anchor = anchor
        super.init(.zero, stableId: id)
    }

    override var height: CGFloat {
        return contentHeight(blocks) + padding * 2
    }

    override func viewClass() -> AnyClass {
        return LabRowView.self
    }

    override func resizeAnchor(previous: TableRowItem) -> TableRowResizeAnchor? {
        guard let anchor = anchor else {
            return nil
        }
        return TableRowResizeAnchor(from: anchor.from + padding, to: anchor.to + padding)
    }
}

final class LabRowView: TableRowView {
    let bubble = View()
    let content = View()
    var markers: [String: View] = [:]

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bubble.layer?.masksToBounds = true
        bubble.backgroundColor = NSColor(white: 0.85, alpha: 1)
        bubble.layer?.cornerRadius = 12
        addSubview(bubble)
        bubble.addSubview(content)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? LabItem else {
            return
        }
        let ids = Set(item.blocks.map { $0.id })
        for (id, marker) in markers where !ids.contains(id) {
            marker.removeFromSuperview()
            markers.removeValue(forKey: id)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var y: CGFloat = 0
        for (index, block) in item.blocks.enumerated() {
            let frame = NSMakeRect(6, y + 2, 200, max(block.height - 4, 1))
            if let marker = markers[block.id] {
                marker.frame = frame
            } else {
                let marker = View(frame: frame)
                marker.backgroundColor = NSColor(hue: CGFloat(index) / 7, saturation: 0.5, brightness: 0.9, alpha: 1)
                content.addSubview(marker)
                markers[block.id] = marker
            }
            y += block.height
        }
        CATransaction.commit()
        if !animated {
            layoutBubble(item, transition: .immediate)
        }
    }

    private func layoutBubble(_ item: LabItem, transition: ContainedViewLayoutTransition) {
        let height = contentHeight(item.blocks)
        transition.updateFrame(view: bubble, frame: NSMakeRect(10, padding, 240, height))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.frame = NSMakeRect(0, 0, 240, height)
        CATransaction.commit()
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        if let item = item as? LabItem {
            layoutBubble(item, transition: transition)
        }
    }

    override func applyResizeAnchor(_ anchor: TableRowResizeAnchor, transition: ContainedViewLayoutTransition) {
        anchor.pin(content, transition: transition)
    }
}

struct Scenario {
    let name: String
    let offset: CGFloat
    let widget: Int
    let before: [Block]
    let after: [Block]
    let click: String?
    let tracked: String
    var second: [Block]? = nil
    var sticks: Bool { return offset == 0 }
}

func blocks(_ list: [(String, CGFloat)]) -> [Block] {
    return list.map { (id: $0.0, height: $0.1) }
}

let accordionClosed = blocks([("header", 44), ("tabs", 36), ("body", 60), ("footer", 40)])
let accordionOpen = blocks([("header", 44), ("tabs", 36), ("body", 60), ("details", 180), ("footer", 40)])
let listShort = blocks([("intro", 120), ("list", 60), ("more", 40)])
let listExpandedAbove = blocks([("intro", 120), ("list", 60), ("list2", 160), ("more", 40)])
let collapsedAbove = blocks([("list", 60), ("more", 40)])

let scenarios: [Scenario] = [
    Scenario(name: "grow below click, scrolled", offset: 400, widget: 8, before: accordionClosed, after: accordionOpen, click: "tabs", tracked: "tabs"),
    Scenario(name: "shrink below click, scrolled", offset: 400, widget: 8, before: accordionOpen, after: accordionClosed, click: "tabs", tracked: "tabs"),
    Scenario(name: "grow above bottom click, scrolled", offset: 400, widget: 8, before: listShort, after: listExpandedAbove, click: "more", tracked: "more"),
    Scenario(name: "collapse above bottom click, scrolled", offset: 400, widget: 8, before: listShort, after: collapsedAbove, click: "more", tracked: "more"),
    Scenario(name: "grow below click, at chat bottom", offset: 0, widget: 1, before: accordionClosed, after: accordionOpen, click: "tabs", tracked: "tabs"),
    Scenario(name: "collapse above click, at chat bottom", offset: 0, widget: 1, before: listShort, after: collapsedAbove, click: "more", tracked: "more"),
    Scenario(name: "programmatic grow, at chat bottom", offset: 0, widget: 0, before: listShort, after: listExpandedAbove, click: nil, tracked: "more"),
    Scenario(name: "programmatic grow, scrolled", offset: 400, widget: 8, before: accordionClosed, after: accordionOpen, click: nil, tracked: "header"),
    Scenario(name: "shrink last widget at chat bottom (clamp)", offset: 0, widget: 0, before: accordionOpen, after: accordionClosed, click: "tabs", tracked: "tabs"),
    Scenario(name: "huge grow below click, scrolled", offset: 400, widget: 8, before: accordionClosed, after: blocks([("header", 44), ("tabs", 36), ("body", 60), ("details", 760), ("footer", 40)]), click: "tabs", tracked: "tabs"),
    Scenario(name: "huge grow at chat bottom", offset: 0, widget: 1, before: accordionClosed, after: blocks([("header", 44), ("tabs", 36), ("body", 60), ("details", 760), ("footer", 40)]), click: "tabs", tracked: "tabs"),
    Scenario(name: "giant grow below click, scrolled", offset: 400, widget: 8, before: accordionClosed, after: blocks([("header", 44), ("tabs", 36), ("body", 60), ("details", 2600), ("footer", 40)]), click: "tabs", tracked: "tabs"),
    Scenario(name: "giant shrink above bottom click", offset: 400, widget: 8, before: blocks([("intro", 2600), ("list", 60), ("more", 40)]), after: collapsedAbove, click: "more", tracked: "more"),
    Scenario(name: "re-grow mid animation, scrolled", offset: 400, widget: 8, before: accordionClosed, after: accordionOpen, click: "tabs", tracked: "tabs", second: accordionClosed),
    Scenario(name: "collapse mid animation, bottom click", offset: 400, widget: 8, before: listShort, after: listExpandedAbove, click: "more", tracked: "more", second: collapsedAbove),
    Scenario(name: "widget cut by viewport top, bottom click", offset: 120, widget: 6, before: listShort, after: listExpandedAbove, click: "more", tracked: "more"),
    Scenario(name: "widget cut by viewport bottom, top click", offset: 450, widget: 6, before: accordionClosed, after: accordionOpen, click: "tabs", tracked: "tabs"),
]

final class Lab {
    let window: NSWindow
    var table: TableView!
    var results: [String] = []
    var failures = 0
    var index = 0
    let useAnchor: Bool

    init(useAnchor: Bool) {
        self.useAnchor = useAnchor
        window = NSWindow(contentRect: NSMakeRect(200, 200, 360, 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.wantsLayer = true
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
    }

    func makeTable(_ scenario: Scenario) {
        table?.removeFromSuperview()
        let table = TableView(frame: window.contentView!.bounds, isFlipped: false)
        window.contentView!.addSubview(table)
        for id in 0 ..< 30 {
            let content = id == scenario.widget ? scenario.before : blocks([("text\(id)", CGFloat(40 + (id * 17) % 50))])
            _ = table.addItem(item: LabItem(id: id, blocks: content))
        }
        table.layoutSubtreeIfNeeded()
        table.clipView.updateBounds(to: NSMakePoint(0, scenario.offset))
        table.layoutSubtreeIfNeeded()
        self.table = table
    }

    var root: CALayer {
        return window.contentView!.layer!
    }

    func presented(_ view: NSView) -> CGRect? {
        guard let layer = view.layer else {
            return nil
        }
        guard let p = layer.presentation(), let r = root.presentation() else {
            return nil
        }
        return p.convert(p.bounds, to: r)
    }

    func widgetView(_ scenario: Scenario) -> LabRowView? {
        return table.viewNecessary(at: scenario.widget) as? LabRowView
    }

    func rowView(_ index: Int) -> NSView? {
        return table.viewNecessary(at: index)
    }

    func run() {
        guard index < scenarios.count else {
            print(results.joined(separator: "\n"))
            print(useAnchor ? "anchored failures: \(failures)" : "baseline (no anchor) runs: \(scenarios.count)")
            NSApp.terminate(nil)
            return
        }
        let scenario = scenarios[index]
        index += 1
        makeTable(scenario)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.measure(scenario)
        }
    }

    func measure(_ scenario: Scenario) {
        guard let view = widgetView(scenario), let marker = view.markers[scenario.tracked], let before = presented(marker) else {
            results.append("\(scenario.name): widget not visible")
            failures += 1
            run()
            return
        }
        let neighbourAbove = rowView(scenario.widget + 1)
        let neighbourBelow = scenario.widget > 0 ? rowView(scenario.widget - 1) : nil
        let aboveBefore = neighbourAbove.flatMap(presented)
        let belowBefore = neighbourBelow.flatMap(presented)
        let oldHeight = contentHeight(scenario.before)
        let newHeight = contentHeight(scenario.after)
        let click = scenario.click.flatMap { id in top(of: id, in: scenario.before).map { $0 + 10 } }
        let anchor = TableRowResizeAnchor.resolve(oldHeight: oldHeight, newHeight: newHeight, click: click, sticksToBottom: scenario.sticks)
        let item = LabItem(id: scenario.widget, blocks: scenario.after, anchor: useAnchor ? anchor : nil)
        table.merge(with: TableUpdateTransition(deleted: [], inserted: [], updated: [(scenario.widget, item)], animated: true))
        CATransaction.flush()
        var samples: [(t: Double, tracked: CGFloat, above: CGFloat?, below: CGFloat?)] = []
        let start = CACurrentMediaTime()
        if let second = scenario.second {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard let view = self.widgetView(scenario) else {
                    return
                }
                let currentHeight = contentHeight(scenario.after)
                let point = view.markers[scenario.click ?? scenario.tracked].map { view.content.convert(NSMakePoint(0, 10), from: $0).y }
                let anchor = TableRowResizeAnchor.resolve(oldHeight: currentHeight, newHeight: contentHeight(second), click: point, sticksToBottom: scenario.sticks)
                let next = LabItem(id: scenario.widget, blocks: second, anchor: self.useAnchor ? anchor : nil)
                self.table.merge(with: TableUpdateTransition(deleted: [], inserted: [], updated: [(scenario.widget, next)], animated: true))
                CATransaction.flush()
            }
        }
        let timer = Timer(timeInterval: 1.0 / 240.0, repeats: true) { timer in
            CATransaction.flush()
            let t = CACurrentMediaTime() - start
            if ProcessInfo.processInfo.environment["LAB_PARTS"].map({ scenario.name.contains($0) }) == true, t > 0.07, t < 0.11, let view = self.widgetView(scenario) {
                print(String(format: "  t %.4f row %.2f bubble %.2f content %.2f marker %.2f", t, self.presented(view)?.maxY ?? 0, self.presented(view.bubble)?.maxY ?? 0, self.presented(view.content)?.maxY ?? 0, view.markers[scenario.tracked].flatMap(self.presented)?.maxY ?? 0))
            }
            if let view = self.widgetView(scenario), let marker = view.markers[scenario.tracked], let rect = self.presented(marker) {
                samples.append((t, rect.maxY, self.rowView(scenario.widget + 1).flatMap(self.presented)?.minY, scenario.widget > 0 ? self.rowView(scenario.widget - 1).flatMap(self.presented)?.maxY : nil))
            }
            if ProcessInfo.processInfo.environment["LAB_ROWS"].map({ scenario.name.contains($0) }) == true, t > 0.06, t < 0.12, let view = self.widgetView(scenario) {
                let row = self.presented(view)
                let bubble = self.presented(view.bubble)
                let anims = (view.layer?.animationKeys() ?? []).map { key -> String in
                    guard let animation = view.layer?.animation(forKey: key) as? CABasicAnimation else { return key }
                    return "\(key)@\(String(format: "%.3f", animation.beginTime - start)) \(String(describing: animation.fromValue)) -> \(String(describing: animation.toValue)) \(ObjectIdentifier(animation).hashValue % 10000)"
                }.joined(separator: ",")
                let bubbleAnims = (view.bubble.layer?.animationKeys() ?? []).joined(separator: ",")
                let content = self.presented(view.content)
                let tracked = view.markers[scenario.tracked].flatMap(self.presented)
                print(String(format: "  t %.3f rowTop %.1f bubbleTop %.1f contentTop %.1f tracked %.1f", t, row?.maxY ?? 0, bubble?.maxY ?? 0, content?.maxY ?? 0, tracked?.maxY ?? 0))
                _ = anims; _ = bubbleAnims
            }
            if t > 0.4 {
                timer.invalidate()
                self.report(scenario, before: before.maxY, aboveBefore: aboveBefore?.minY, belowBefore: belowBefore?.maxY, samples: samples)
                self.run()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func report(_ scenario: Scenario, before: CGFloat, aboveBefore: CGFloat?, belowBefore: CGFloat?, samples: [(t: Double, tracked: CGFloat, above: CGFloat?, below: CGFloat?)]) {
        let drift = samples.map { abs($0.tracked - before) }.max() ?? .infinity
        let final = samples.last.map { $0.tracked - before } ?? 0
        if ProcessInfo.processInfo.environment["LAB_DUMP"].map({ scenario.name.contains($0) }) == true {
            print(samples.map { String(format: "%.0f@%.3f", $0.tracked - before, $0.t) }.joined(separator: " "))
        }
        var jumps: CGFloat = 0
        var neighbourSteps: CGFloat = 0
        for pair in zip(samples, samples.dropFirst()) {
            jumps = max(jumps, abs(pair.1.tracked - pair.0.tracked))
            if let a = pair.0.above, let b = pair.1.above {
                neighbourSteps = max(neighbourSteps, abs(b - a))
            }
            if let a = pair.0.below, let b = pair.1.below {
                neighbourSteps = max(neighbourSteps, abs(b - a))
            }
        }
        let firstAbove = neighbourSteps
        let firstBelow: CGFloat = jumps
        let distance = abs(contentHeight(scenario.after) - contentHeight(scenario.before))
        let limit = max(12, distance * 0.06)
        let smooth = jumps <= limit && neighbourSteps <= limit
        let clamps = scenario.name.contains("clamp")
        let ok = smooth && (clamps || drift <= (scenario.second == nil ? 1 : 2.5))
        if useAnchor && !ok {
            failures += 1
        }
        results.append(String(format: "%@ %@ drift %.1f final %.1f maxStep %.1f neighbourStep %.1f trackedStep %.1f samples %d", ok ? "OK  " : "FAIL", scenario.name.padding(toLength: 44, withPad: " ", startingAt: 0), drift, final, jumps, firstAbove, firstBelow, samples.count))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
System.updateScaleFactor(2)
var retainedImages: [NSImage] = []
for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.black.setFill()
        rect.insetBy(dx: 4, dy: 4).fill()
        return true
    }
    _ = image.setName(name)
    retainedImages.append(image)
}
let lab = Lab(useAnchor: !CommandLine.arguments.contains("--baseline"))
DispatchQueue.main.async {
    lab.run()
}
app.run()
