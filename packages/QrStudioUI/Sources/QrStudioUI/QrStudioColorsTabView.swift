import Foundation
import Cocoa
import TGUIKit
import ColorPalette
import Localization

enum QrStudioColorsSelection: Equatable {
    case palette(QrStudioPaletteId)
    case theme(String)
}

private final class QrStudioSwatchCache {
    static let shared = QrStudioSwatchCache()

    private var images: [String: CGImage] = [:]

    func paletteImage(_ palette: QrStudioPalette, pixelSide: Int) -> CGImage? {
        let key = "\(palette.name)-\(pixelSide)"
        if let image = self.images[key] {
            return image
        }
        guard let image = qrStudioSwatchImage(colors: palette.colors, side: pixelSide) else {
            return nil
        }
        self.images[key] = image
        return image
    }

    func themeImage(_ theme: QrStudioTheme, side: CGFloat) -> CGImage? {
        let key = "theme-\(theme.id)-" + theme.colors.map { "\($0.rgb)" }.joined(separator: ",") + "-\(side)-\(System.backingScale)"
        if let image = self.images[key] {
            return image
        }
        let colors = theme.colors.map { $0.nsColor }
        let fallback = QrStudioColor(0.85, 0.85, 0.85).nsColor
        let image = generateImage(CGSize(width: side, height: side), contextGenerator: { size, context in
            let rect = CGRect(origin: CGPoint(), size: size)
            context.clear(rect)
            context.addEllipse(in: rect)
            context.clip()
            if colors.count > 2 {
                let preview = AnimatedGradientBackgroundView.generatePreview(size: CGSize(width: 32.0, height: 32.0), colors: colors)
                context.draw(preview, in: rect)
            } else if colors.count == 2, let gradient = CGGradient.evenlySpaced([colors[1], colors[0]] as [NSColor]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            } else {
                context.setFillColor((colors.first ?? fallback).cgColor)
                context.fill(rect)
            }
        })
        if let image {
            self.images[key] = image
        }
        return image
    }
}

private final class QrStudioPressRing {
    static let lineWidth: CGFloat = 2.0
    static let gap: CGFloat = 2.0
    private static let duration: Double = 0.2

    let layer = SimpleShapeLayer()
    private var isSelected: Bool?

    init() {
        self.layer.fillColor = nil
        self.layer.lineWidth = 0.0
    }

    static func pressedScale(side: CGFloat) -> CGFloat {
        guard side > 0.0 else {
            return 1.0
        }
        return max(0.0, side - (QrStudioPressRing.lineWidth + QrStudioPressRing.gap) * 2.0) / side
    }

    private func path(size: CGSize, cornerRadius: CGFloat?, inset: CGFloat) -> CGPath {
        let rect = CGRect(origin: CGPoint(), size: size).insetBy(dx: inset, dy: inset)
        if let cornerRadius {
            let radius = min(max(0.0, cornerRadius - inset), min(rect.width, rect.height) * 0.5)
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        return CGPath(ellipseIn: rect, transform: nil)
    }

    func update(frame: CGRect, cornerRadius: CGFloat?, color: NSColor, isSelected: Bool, target: CALayer?, animated: Bool) {
        let wasSelected = self.isSelected ?? false
        self.isSelected = isSelected
        let animates = animated && wasSelected != isSelected

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.layer.frame = frame
        self.layer.strokeColor = color.cgColor
        let lineWidth = isSelected ? QrStudioPressRing.lineWidth : 0.0
        let path = self.path(size: frame.size, cornerRadius: cornerRadius, inset: isSelected ? QrStudioPressRing.lineWidth * 0.5 : 0.0)
        let previousPath = self.layer.presentation()?.path ?? self.layer.path
        let previousLineWidth = self.layer.presentation()?.lineWidth ?? self.layer.lineWidth
        self.layer.path = path
        self.layer.lineWidth = lineWidth

        let scale = isSelected ? QrStudioPressRing.pressedScale(side: min(frame.width, frame.height)) : 1.0
        var previousScale: CGFloat = 1.0
        if let target {
            previousScale = ((target.presentation()?.value(forKeyPath: "transform.scale") as? NSNumber) ?? (target.value(forKeyPath: "transform.scale") as? NSNumber)).map { CGFloat($0.doubleValue) } ?? 1.0
            target.transform = CATransform3DMakeScale(scale, scale, 1.0)
        }
        CATransaction.commit()

        guard animates else {
            return
        }
        if let previousPath {
            self.layer.animate(from: previousPath, to: path, keyPath: "path", timingFunction: .easeInEaseOut, duration: QrStudioPressRing.duration)
        }
        self.layer.animate(from: NSNumber(value: Double(previousLineWidth)), to: NSNumber(value: Double(lineWidth)), keyPath: "lineWidth", timingFunction: .easeInEaseOut, duration: QrStudioPressRing.duration)
        target?.animate(from: NSNumber(value: Double(previousScale)), to: NSNumber(value: Double(scale)), keyPath: "transform.scale", timingFunction: .easeInEaseOut, duration: QrStudioPressRing.duration)
    }
}

private final class QrStudioColorsDocumentView: View {
    var click: ((NSPoint) -> Void)?
    private var downPoint: NSPoint?

    override func mouseDown(with event: NSEvent) {
        self.downPoint = self.convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        if let downPoint = self.downPoint, abs(downPoint.x - point.x) < 8.0, abs(downPoint.y - point.y) < 8.0 {
            self.click?(point)
        }
        self.downPoint = nil
    }
}

final class QrStudioColorsTabView: View {
    private struct Cell {
        let selection: QrStudioColorsSelection
        let frame: CGRect
    }

    let scrollView = ScrollView()
    var selected: ((QrStudioPaletteId) -> Void)?
    var selectedTheme: ((String) -> Void)?

    private let documentView = QrStudioColorsDocumentView()
    private let swatchHost = View()
    private let titleView = TextView()
    private var paletteLayers: [QrStudioPaletteId: SimpleLayer] = [:]
    private var paletteNames: [QrStudioPaletteId: String] = [:]
    private var paletteIds: [QrStudioPaletteId] = []
    private var themeLayers: [String: SimpleLayer] = [:]
    private var themeSignatures: [String: String] = [:]
    private var themeIds: [String] = []
    private var cells: [Cell] = []
    private var paletteRings: [QrStudioPaletteId: QrStudioPressRing] = [:]
    private var themeRings: [String: QrStudioPressRing] = [:]
    private var paletteFrames: [QrStudioPaletteId: CGRect] = [:]
    private var themeFrames: [String: CGRect] = [:]
    private var paletteColors: [QrStudioPaletteId: NSColor] = [:]
    private var themeColors: [String: NSColor] = [:]
    private var didApplySelection = false
    private var appliedIsDark: Bool?
    private var contentHeight: CGFloat = 0.0

    private var size = CGSize()

    private static let swatchSide: CGFloat = 48.0
    private static let cellSide: CGFloat = 58.0
    private static let columns = 6
    private static let colorsTitle = strings().qrStudioColorsTabViewTitle

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.scrollView.background = .clear
        self.scrollView.hasVerticalScroller = false
        self.scrollView.verticalScrollElasticity = .allowed
        self.scrollView.documentView = self.documentView
        self.addSubview(self.scrollView)

        self.swatchHost.isEventLess = true
        self.documentView.addSubview(self.swatchHost)

        self.titleView.userInteractionEnabled = false
        self.titleView.isSelectable = false
        self.titleView.isEventLess = true
        self.documentView.addSubview(self.titleView)

        self.documentView.click = { [weak self] point in
            self?.handleClick(point)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func handleClick(_ point: NSPoint) {
        for cell in self.cells where cell.frame.contains(point) {
            switch cell.selection {
            case let .palette(id):
                self.selected?(id)
            case let .theme(id):
                self.selectedTheme?(id)
            }
            return
        }
    }

    private static func signature(_ theme: QrStudioTheme) -> String {
        return theme.colors.map { "\($0.rgb)" }.joined(separator: ",")
    }

    private func updatePaletteLayers(_ palettes: [QrStudioPalette]) {
        let ids = palettes.compactMap { $0.id }
        let pixelSide = Int(QrStudioColorsTabView.swatchSide * System.backingScale)
        for (id, layer) in self.paletteLayers where !ids.contains(id) {
            layer.removeFromSuperlayer()
            self.paletteLayers.removeValue(forKey: id)
            self.paletteNames.removeValue(forKey: id)
        }
        for palette in palettes {
            guard let id = palette.id, self.paletteNames[id] != palette.name else {
                continue
            }
            let swatchLayer: SimpleLayer
            if let current = self.paletteLayers[id] {
                swatchLayer = current
            } else {
                swatchLayer = SimpleLayer()
                swatchLayer.contentsGravity = .resizeAspect
                self.swatchHost.layer?.addSublayer(swatchLayer)
                self.paletteLayers[id] = swatchLayer
            }
            self.paletteNames[id] = palette.name
            swatchLayer.contents = QrStudioSwatchCache.shared.paletteImage(palette, pixelSide: pixelSide)
        }
        self.paletteIds = ids
    }

    private func updateThemeLayers(_ themes: [QrStudioTheme]) {
        let ids = themes.map { $0.id }
        for (id, layer) in self.themeLayers where !ids.contains(id) {
            layer.removeFromSuperlayer()
            self.themeLayers.removeValue(forKey: id)
            self.themeSignatures.removeValue(forKey: id)
        }
        for theme in themes {
            let signature = QrStudioColorsTabView.signature(theme)
            guard self.themeSignatures[theme.id] != signature else {
                continue
            }
            let layer: SimpleLayer
            if let current = self.themeLayers[theme.id] {
                layer = current
            } else {
                layer = SimpleLayer()
                layer.contentsGravity = .resizeAspect
                self.swatchHost.layer?.addSublayer(layer)
                self.themeLayers[theme.id] = layer
            }
            self.themeSignatures[theme.id] = signature
            layer.contents = QrStudioSwatchCache.shared.themeImage(theme, side: QrStudioColorsTabView.swatchSide)
        }
        self.themeIds = ids
    }

    func update(size: CGSize, themes: [QrStudioTheme], palettes: [QrStudioPalette], selection: QrStudioColorsSelection?, revealSelection: Bool, isDark: Bool) {
        let sizeChanged = self.size != size
        let themesChanged = themes.map { $0.id } != self.themeIds || palettes.compactMap({ $0.id }) != self.paletteIds
        let appearanceChanged = self.appliedIsDark != isDark
        self.size = size
        self.appliedIsDark = isDark
        self.updateThemeLayers(themes)
        self.updatePaletteLayers(palettes)

        self.scrollView.frame = CGRect(origin: CGPoint(), size: size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let palette = qrStudioSheetPalette(isDark: isDark)
        let sideInset: CGFloat = 10.0
        let columnSpacing: CGFloat = 4.0
        let rowSpacing: CGFloat = 8.0
        let columns = QrStudioColorsTabView.columns
        let cellSide = QrStudioColorsTabView.cellSide
        let swatchSide = QrStudioColorsTabView.swatchSide
        let columnWidth = (size.width - sideInset * 2.0 - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns)

        if sizeChanged || themesChanged || appearanceChanged || self.cells.isEmpty {
            let sections: [[QrStudioColorsSelection]] = [
                themes.map { QrStudioColorsSelection.theme($0.id) },
                palettes.compactMap { $0.id.map { QrStudioColorsSelection.palette($0) } }
            ]
            var cells: [Cell] = []
            var y: CGFloat = 16.0
            self.titleView.isHidden = true
            for (sectionIndex, section) in sections.enumerated() {
                if section.isEmpty {
                    continue
                }
                if sectionIndex != 0 {
                    let title = NSAttributedString(string: QrStudioColorsTabView.colorsTitle.uppercased(), attributes: [
                        .font: NSFont.semibold(13.0),
                        .foregroundColor: palette.grayText,
                        .kern: -0.078
                    ])
                    let layout = TextViewLayout(title, maximumNumberOfLines: 1, alignment: .center)
                    layout.measure(width: max(1.0, size.width - 4.0))
                    self.titleView.update(layout)
                    self.titleView.frame = CGRect(x: floor((size.width - layout.layoutSize.width) * 0.5), y: y + floor((17.0 - layout.layoutSize.height) * 0.5), width: layout.layoutSize.width, height: layout.layoutSize.height)
                    self.titleView.isHidden = false
                    y += 17.0 + 12.0
                }
                for (offset, selection) in section.enumerated() {
                    let column = offset % columns
                    let row = offset / columns
                    let cellFrame = CGRect(x: sideInset + CGFloat(column) * (columnWidth + columnSpacing) + (columnWidth - cellSide) * 0.5, y: y + CGFloat(row) * (cellSide + rowSpacing), width: cellSide, height: cellSide)
                    cells.append(Cell(selection: selection, frame: cellFrame))
                    let swatchFrame = cellFrame.insetBy(dx: (cellSide - swatchSide) * 0.5, dy: (cellSide - swatchSide) * 0.5)
                    let swatchLayer: CALayer?
                    switch selection {
                    case let .palette(id):
                        self.paletteFrames[id] = swatchFrame
                        swatchLayer = self.paletteLayers[id]
                    case let .theme(id):
                        self.themeFrames[id] = swatchFrame
                        swatchLayer = self.themeLayers[id]
                    }
                    if let swatchLayer {
                        swatchLayer.bounds = CGRect(origin: CGPoint(), size: swatchFrame.size)
                        swatchLayer.position = CGPoint(x: swatchFrame.midX, y: swatchFrame.midY)
                    }
                }
                let rows = (section.count + columns - 1) / columns
                y += CGFloat(rows) * cellSide + CGFloat(max(0, rows - 1)) * rowSpacing + 18.0
            }
            self.cells = cells
            self.contentHeight = y + 34.0
            let documentFrame = CGRect(origin: CGPoint(), size: CGSize(width: size.width, height: self.contentHeight))
            if self.documentView.frame != documentFrame {
                self.documentView.frame = documentFrame
            }
            self.swatchHost.frame = documentFrame
        }

        for palette in palettes {
            if let id = palette.id {
                let color = palette.colors.count > 4 ? palette.colors[4] : (palette.colors.first ?? QrStudioColor(0.5, 0.5, 0.5))
                self.paletteColors[id] = color.nsColor
            }
        }
        for theme in themes {
            if let color = theme.colors.last ?? theme.colors.first {
                self.themeColors[theme.id] = color.nsColor
            }
        }

        var selectedPaletteId: QrStudioPaletteId?
        var selectedThemeId: String?
        switch selection {
        case let .palette(id):
            selectedPaletteId = id
        case let .theme(id):
            selectedThemeId = id
        case .none:
            break
        }
        if let selectedPaletteId, self.paletteRings[selectedPaletteId] == nil, self.paletteLayers[selectedPaletteId] != nil {
            let ring = QrStudioPressRing()
            self.swatchHost.layer?.addSublayer(ring.layer)
            self.paletteRings[selectedPaletteId] = ring
        }
        if let selectedThemeId, self.themeRings[selectedThemeId] == nil, self.themeLayers[selectedThemeId] != nil {
            let ring = QrStudioPressRing()
            self.swatchHost.layer?.addSublayer(ring.layer)
            self.themeRings[selectedThemeId] = ring
        }
        for (id, ring) in self.paletteRings {
            guard let frame = self.paletteFrames[id], let swatchLayer = self.paletteLayers[id] else {
                ring.layer.removeFromSuperlayer()
                self.paletteRings.removeValue(forKey: id)
                continue
            }
            ring.update(frame: frame, cornerRadius: nil, color: self.paletteColors[id] ?? palette.accent, isSelected: id == selectedPaletteId, target: swatchLayer, animated: self.didApplySelection && !revealSelection)
        }
        for (id, ring) in self.themeRings {
            guard let frame = self.themeFrames[id], let swatchLayer = self.themeLayers[id] else {
                ring.layer.removeFromSuperlayer()
                self.themeRings.removeValue(forKey: id)
                continue
            }
            ring.update(frame: frame, cornerRadius: nil, color: self.themeColors[id] ?? palette.accent, isSelected: id == selectedThemeId, target: swatchLayer, animated: self.didApplySelection && !revealSelection)
        }
        self.didApplySelection = true

        if revealSelection, size.height > 0.0, let selection, let cell = self.cells.first(where: { $0.selection == selection }) {
            let frame = cell.frame
            let offset = self.scrollView.documentVisibleRect.minY
            if frame.minY < offset + 14.0 || frame.maxY > offset + size.height - 40.0 {
                let maxOffset = max(0.0, self.contentHeight - size.height)
                self.scrollView.contentView.scroll(to: NSPoint(x: 0.0, y: min(maxOffset, max(0.0, frame.midY - size.height * 0.5))))
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            }
        }
        CATransaction.commit()
    }
}
