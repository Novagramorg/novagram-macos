#if DEBUG
import AppKit

public struct PerfLabViewCensus {
    public private(set) var views: Int = 0
    public private(set) var hiddenViews: Int = 0
    public private(set) var layers: Int = 0
    public private(set) var byClass: [String: Int] = [:]
    public private(set) var containers: [String: Int] = [:]
    public private(set) var byParent: [String: Int] = [:]
    public private(set) var samplePaths: [String: String] = [:]
    public private(set) var hiddenByParent: [String: Int] = [:]
    public private(set) var hiddenPaths: [String: String] = [:]
    public private(set) var subtreeByClass: [String: (count: Int, views: Int)] = [:]
    public private(set) var drawingViews: Int = 0
    public private(set) var drawingPixels: Double = 0
    public private(set) var drawingByClass: [String: Int] = [:]

    private static let containerClasses: Set<String> = ["NSView", "View", "FlippableView", "LayerBackedView"]

    public static func take(_ root: NSView) -> PerfLabViewCensus {
        var census = PerfLabViewCensus()
        census.walk(root, hidden: false)
        if let layer = root.layer {
            census.layers = PerfLabViewCensus.countLayers(layer)
        }
        return census
    }

    @discardableResult
    private mutating func walk(_ view: NSView, hidden: Bool) -> Int {
        let isHidden = hidden || view.isHidden
        let name = String(describing: type(of: view))
        self.views += 1
        if isHidden {
            self.hiddenViews += 1
        }
        self.byClass[name, default: 0] += 1
        if !isHidden, view.wantsLayer, !view.wantsUpdateLayer, view.layer?.contents != nil {
            let scale = view.layer?.contentsScale ?? 1
            self.drawingViews += 1
            self.drawingPixels += Double(view.bounds.width * scale * view.bounds.height * scale)
            self.drawingByClass[name, default: 0] += Int(view.bounds.width * scale * view.bounds.height * scale / 1000)
        }
        let pair = "\(name)<\(view.superview.map { String(describing: type(of: $0)) } ?? "-")"
        self.byParent[pair, default: 0] += 1
        if self.samplePaths[pair] == nil {
            self.samplePaths[pair] = PerfLabViewCensus.ancestry(view, depth: 7)
        }
        if view.isHidden && !hidden {
            let subtree = PerfLabViewCensus.subtreeSize(view)
            self.hiddenByParent[pair, default: 0] += subtree
            if self.hiddenPaths[pair] == nil {
                self.hiddenPaths[pair] = PerfLabViewCensus.ancestry(view, depth: 7)
            }
        }
        if PerfLabViewCensus.containerClasses.contains(name), let superview = view.superview {
            let parent = String(describing: type(of: superview))
            let shape: String
            switch view.subviews.count {
            case 0:
                shape = "empty"
            case 1:
                shape = "wrapper"
            default:
                shape = "group"
            }
            self.containers["\(name)<\(parent) \(shape)", default: 0] += 1
        }
        var size = 1
        for subview in view.subviews {
            size += self.walk(subview, hidden: isHidden)
        }
        if !isHidden {
            let current = self.subtreeByClass[name] ?? (0, 0)
            self.subtreeByClass[name] = (current.count + 1, current.views + size)
        }
        return size
    }

    public static func scrollToBottom(_ root: NSView, minX: CGFloat) {
        if let scrollView = root as? NSScrollView, let window = root.window, let document = scrollView.documentView, scrollView.convert(scrollView.bounds, to: nil).minX >= minX * window.frame.width {
            let visible = scrollView.contentView.bounds.height
            let y = document.isFlipped ? max(0, document.frame.height - visible) : 0
            scrollView.contentView.scroll(to: NSMakePoint(scrollView.contentView.bounds.minX, y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }
        for subview in root.subviews where !subview.isHidden {
            scrollToBottom(subview, minX: minX)
        }
    }

    public static func tree(of className: String, in root: NSView) -> String? {
        func find(_ view: NSView) -> NSView? {
            if String(describing: type(of: view)) == className, !view.isHidden, view.visibleRect.height > 0 {
                return view
            }
            for subview in view.subviews {
                if let found = find(subview) {
                    return found
                }
            }
            return nil
        }
        guard let target = find(root) else {
            return nil
        }
        var lines: [String] = []
        func dump(_ view: NSView, depth: Int) {
            let frame = view.frame
            let layers = view.layer?.sublayers?.filter { layer in !view.subviews.contains(where: { $0.layer === layer }) }.count ?? 0
            lines.append(String(repeating: "  ", count: depth) + "\(type(of: view)) \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))\(view.isHidden ? " hidden" : "")\(layers > 0 ? " +\(layers)L" : "")")
            for subview in view.subviews {
                dump(subview, depth: depth + 1)
            }
        }
        dump(target, depth: 0)
        return lines.joined(separator: "\n")
    }

    private static func subtreeSize(_ view: NSView) -> Int {
        return view.subviews.reduce(1) { $0 + subtreeSize($1) }
    }

    private static func ancestry(_ view: NSView, depth: Int) -> String {
        var names: [String] = []
        var current: NSView? = view
        while let view = current, names.count < depth {
            names.append(String(describing: type(of: view)))
            current = view.superview
        }
        return names.joined(separator: "<")
    }

    private static func countLayers(_ layer: CALayer) -> Int {
        var count = 1
        for sublayer in layer.sublayers ?? [] {
            count += countLayers(sublayer)
        }
        if let mask = layer.mask {
            count += countLayers(mask)
        }
        return count
    }

    public var metrics: [String: Double] {
        return [
            "censusViews": Double(self.views),
            "censusHiddenViews": Double(self.hiddenViews),
            "censusLayers": Double(self.layers),
            "censusContainers": Double(self.containers.values.reduce(0, +)),
            "censusDrawingViews": Double(self.drawingViews),
            "censusDrawingMPixels": self.drawingPixels / 1_000_000
        ]
    }

    public func notes(top: Int = 40) -> [String: String] {
        let classes = self.byClass.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(top).map { "\($0.key)=\($0.value)" }
        let containers = self.containers.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(top).map { "\($0.key)=\($0.value)" }
        let parents = self.byParent.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(top).map { "\($0.key)=\($0.value)" }
        let paths = self.byParent.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(top).compactMap { entry in
            self.samplePaths[entry.key].map { "\($0)=\(entry.value)" }
        }
        let hiddenPaths = self.hiddenByParent.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(top).compactMap { entry in
            self.hiddenPaths[entry.key].map { "\($0)=\(entry.value)" }
        }
        let components = self.subtreeByClass.filter { !PerfLabViewCensus.containerClasses.contains($0.key) && $0.value.views > $0.value.count }.sorted(by: { $0.value.views != $1.value.views ? $0.value.views > $1.value.views : $0.key < $1.key }).prefix(top).map { "\($0.key)=\($0.value.views)/\($0.value.count)" }
        return [
            "censusComponents": components.joined(separator: ", "),
            "censusHiddenPaths": hiddenPaths.joined(separator: " | "),
            "censusPaths": paths.joined(separator: " | "),
            "censusParents": parents.joined(separator: ", "),
            "censusClasses": classes.joined(separator: ", "),
            "censusDrawingClasses": self.drawingByClass.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(top).map { "\($0.key)=\($0.value)" }.joined(separator: ", "),
            "censusContainerList": containers.joined(separator: ", ")
        ]
    }
}
#endif
