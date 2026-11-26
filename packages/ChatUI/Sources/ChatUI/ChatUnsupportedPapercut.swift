import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import TelegramTheme

private let papercutBandPanelGap: CGFloat = 4.0
private let papercutPanelVerticalPadding: CGFloat = 8.0
private let papercutPanelHorizontalPadding: CGFloat = 10.0
private let papercutPanelCornerRadius: CGFloat = 12.0
private let papercutPanelAlphaDark: CGFloat = 0.10
private let papercutWellAlphaLight: CGFloat = 0.25
private let papercutWellAlphaDark: CGFloat = 0.20

private let papercutRowIconSize: CGFloat = 40.0
private let papercutRowIconSpacing: CGFloat = 10.0
private let papercutRowTitleSpacing: CGFloat = 2.0
private let papercutRowActionSpacing: CGFloat = 10.0
private let papercutRowPillHorizontalInset: CGFloat = 10.0
private let papercutRowPillVerticalInset: CGFloat = 5.0

private let papercutEdgeHeight: CGFloat = 10.0
private let papercutHorizontalOverhang: CGFloat = 4.0
private let papercutVerticalOverhang: CGFloat = 4.0
private let papercutSliverThreshold: CGFloat = 8.0
private let papercutTopEdgeLift: CGFloat = 0.0
private let papercutEdgeInset: CGFloat = -1.0
private let papercutTailInset: CGFloat = 6.0

public struct ChatUnsupportedPapercutBand: Equatable {
    public let frame: CGRect
    public let hasTopEdge: Bool
    public let hasBottomEdge: Bool
}

public struct ChatUnsupportedPapercutTailInsets: Equatable {
    public let left: CGFloat
    public let right: CGFloat

    public init(incoming: Bool) {
        self.left = incoming ? papercutTailInset : 0.0
        self.right = incoming ? 0.0 : papercutTailInset
    }
}

private enum PapercutEdge: Hashable {
    case top
    case bottom

    var assetName: String {
        switch self {
        case .top:      return "Icon_Unsupported_Edge_Top"
        case .bottom:   return "Icon_Unsupported_Edge_Bottom"
        }
    }
}

/// `NSImage(named:)` rather than a generated asset symbol on purpose: the edge assets must stay
/// genuinely optional, so removing one skips its strip instead of failing to compile.
private var papercutEdgeTileCache: [PapercutEdge: (scale: CGFloat, image: CGImage)] = [:]

private func papercutEdgeTile(_ edge: PapercutEdge, scale: CGFloat) -> CGImage? {
    if let cached = papercutEdgeTileCache[edge], cached.scale == scale {
        return cached.image
    }
    guard let image = NSImage(named: edge.assetName) else {
        return nil
    }
    let tile = image.precomposed(scale: scale)
    papercutEdgeTileCache[edge] = (scale, tile)
    return tile
}

private struct PapercutMaskKey: Hashable {
    let width: CGFloat
    let edge: PapercutEdge
    let scale: CGFloat
}

private var papercutMaskCache: [PapercutMaskKey: CGImage] = [:]

/// A full-width alpha mask built by repeating the edge tile horizontally. Cached because the band is
/// repainted on every theme change and every scroll pass.
private func papercutEdgeMask(_ edge: PapercutEdge, width: CGFloat) -> CGImage? {
    let scale = max(1.0, System.backingScale)
    guard width > 0.0, let tile = papercutEdgeTile(edge, scale: scale) else {
        return nil
    }
    let key = PapercutMaskKey(width: width, edge: edge, scale: scale)
    if let cached = papercutMaskCache[key] {
        return cached
    }
    let tileSize = CGSize(width: CGFloat(tile.width) / scale, height: CGFloat(tile.height) / scale)
    guard tileSize.width > 0, tileSize.height > 0 else {
        return nil
    }
    let mask = generateImage(CGSize(width: width, height: tileSize.height), contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        ctx.interpolationQuality = .none
        var x: CGFloat = 0.0
        while x < size.width {
            ctx.draw(tile, in: CGRect(x: x, y: 0.0, width: tileSize.width, height: tileSize.height))
            x += tileSize.width
        }
    }, scale: scale)
    if let mask = mask {
        if papercutMaskCache.count > 32 {
            papercutMaskCache.removeAll()
        }
        papercutMaskCache[key] = mask
    }
    return mask
}

public enum ChatUnsupportedPapercutEdges {
    public static func resolveBands(_ zones: [CGRect], backgroundSize: CGSize) -> [ChatUnsupportedPapercutBand] {
        guard !zones.isEmpty, backgroundSize.height > 0.0 else {
            return []
        }

        var ranges: [(min: CGFloat, max: CGFloat)] = []
        for zone in zones {
            let minY = max(0.0, zone.minY)
            let maxY = min(backgroundSize.height, zone.maxY)
            if maxY > minY {
                ranges.append((min: minY, max: maxY))
            }
        }
        guard !ranges.isEmpty else {
            return []
        }

        ranges.sort(by: { $0.min < $1.min })
        ranges = self.merge(ranges)

        for index in ranges.indices {
            ranges[index].min -= papercutEdgeHeight + papercutTopEdgeLift
            ranges[index].max += papercutEdgeHeight

            if ranges[index].min <= papercutSliverThreshold {
                ranges[index].min = -papercutVerticalOverhang
            }
            if backgroundSize.height - ranges[index].max <= papercutSliverThreshold {
                ranges[index].max = backgroundSize.height + papercutVerticalOverhang
            }
        }
        ranges = self.merge(ranges)

        return ranges.map { range in
            ChatUnsupportedPapercutBand(
                frame: CGRect(
                    x: -papercutHorizontalOverhang,
                    y: range.min,
                    width: backgroundSize.width + papercutHorizontalOverhang * 2.0,
                    height: range.max - range.min
                ),
                hasTopEdge: range.min > 0.0,
                hasBottomEdge: range.max < backgroundSize.height
            )
        }
    }

    private static func merge(_ ranges: [(min: CGFloat, max: CGFloat)]) -> [(min: CGFloat, max: CGFloat)] {
        var result: [(min: CGFloat, max: CGFloat)] = []
        for range in ranges {
            if var last = result.last, range.min <= last.max {
                last.max = max(last.max, range.max)
                result[result.count - 1] = last
            } else {
                result.append(range)
            }
        }
        return result
    }

    public static func cutBand(
        in ctx: CGContext,
        band: ChatUnsupportedPapercutBand,
        tailInsets: ChatUnsupportedPapercutTailInsets,
        restoreBubble: (CGContext) -> Void
    ) {
        guard band.frame.width > 0.0, band.frame.height > 0.0 else {
            return
        }

        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.fill(band.frame)
        ctx.restoreGState()

        let scale = max(1.0, System.backingScale)
        let screenPixel = 1.0 / scale
        let graphicsInset = papercutHorizontalOverhang + (1.0 - screenPixel)
        let graphicsMinX = ceil((band.frame.minX + graphicsInset + tailInsets.left) * scale) / scale
        let graphicsMaxX = floor((band.frame.maxX - graphicsInset - tailInsets.right) * scale) / scale
        let graphicsWidth = max(0.0, graphicsMaxX - graphicsMinX)

        func restoreEdge(_ edge: PapercutEdge, y: CGFloat, trimBottomPixel: Bool) {
            let nativeFrame = CGRect(
                x: graphicsMinX,
                y: floor(y * scale) / scale,
                width: graphicsWidth,
                height: papercutEdgeHeight
            )
            let visibleHeight = nativeFrame.height - (trimBottomPixel ? screenPixel : 0.0)
            guard nativeFrame.width > 0.0, visibleHeight > 0.0,
                  let mask = papercutEdgeMask(edge, width: nativeFrame.width) else {
                return
            }
            ctx.saveGState()
            ctx.clip(to: CGRect(origin: nativeFrame.origin, size: CGSize(width: nativeFrame.width, height: visibleHeight)))
            ctx.translateBy(x: nativeFrame.midX, y: nativeFrame.midY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            ctx.translateBy(x: -nativeFrame.midX, y: -nativeFrame.midY)
            let previousInterpolationQuality = ctx.interpolationQuality
            ctx.interpolationQuality = .none
            ctx.clip(to: nativeFrame, mask: mask)
            ctx.interpolationQuality = previousInterpolationQuality
            ctx.translateBy(x: nativeFrame.midX, y: nativeFrame.midY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            ctx.translateBy(x: -nativeFrame.midX, y: -nativeFrame.midY)
            restoreBubble(ctx)
            ctx.restoreGState()
        }

        if band.hasTopEdge {
            restoreEdge(.top, y: band.frame.minY + papercutEdgeInset, trimBottomPixel: true)
        }
        if band.hasBottomEdge {
            restoreEdge(.bottom, y: band.frame.maxY - papercutEdgeHeight - papercutEdgeInset, trimBottomPixel: false)
        }
    }
}

private struct PapercutIconKey: Hashable {
    let background: NSColor?
    let foreground: NSColor
}

private var papercutIconCache: [PapercutIconKey: CGImage] = [:]

/// The icon ships as two halves: a bubble silhouette and the glyph that knocks out of it. Both are
/// tinted so it follows the chat theme; the glyph takes the colour of whatever sits behind the icon, so
/// it reads as a hole rather than a white sticker. A nil `background` composes the plane alone, for the
/// case where the silhouette is a frosted view below this one. Composited once per colour pair — the
/// content repaints on every scroll pass.
private func papercutIconImage(background: NSColor?, foreground: NSColor) -> CGImage? {
    let key = PapercutIconKey(background: background, foreground: foreground)
    if let cached = papercutIconCache[key] {
        return cached
    }
    let backgroundImage = background.flatMap { TelegramThemeHooks.shared.image(.iconUnsupportedBackground).precomposed($0) }
    let foregroundImage = TelegramThemeHooks.shared.image(.iconUnsupportedForeground).precomposed(foreground)
    let size = backgroundImage?.backingSize ?? foregroundImage.backingSize
    guard size.width > 0, size.height > 0 else {
        return nil
    }
    // `rotatedContext` is flipped, matching the view context the icon draws into.
    let composed = generateImage(size, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        if let backgroundImage {
            ctx.draw(backgroundImage, in: size.bounds)
        }
        ctx.draw(foregroundImage, in: size.bounds)
    })
    if let composed = composed {
        if papercutIconCache.count > 16 {
            papercutIconCache.removeAll()
        }
        papercutIconCache[key] = composed
    }
    return composed
}

private var papercutIconMaskImage: CGImage?

/// The bubble silhouette as an alpha mask — the whole shape, plane included — so the icon can be a
/// frosted surface over the wallpaper shaped exactly like it, with the plane drawn on top rather than
/// punched out. Only the alpha matters, which is all `VisualEffect.maskContents` and `CALayer.mask`
/// read.
public func papercutIconMask() -> CGImage? {
    if let cached = papercutIconMaskImage {
        return cached
    }
    let mask = TelegramThemeHooks.shared.image(.iconUnsupportedBackground).precomposed(NSColor.white)
    papercutIconMaskImage = mask
    return mask
}

public struct ChatUnsupportedPapercutStyle {
    public var titleColor: NSColor
    public var subtitleColor: NSColor
    /// The drawn icon silhouette. Only used when `isFlat` is true; over the wallpaper the silhouette is
    /// the frosted view, in the pill's tint.
    public var iconColor: NSColor
    /// The pill label, i.e. the colour that reads on top of `pillColor` — and so the paper plane's, in
    /// both palettes, so the two surfaces agree in every theme.
    public var actionColor: NSColor
    /// The flat fallback tint of the frosted panel view `ChatRowView` inserts below the bubble. Clear
    /// when flat — there is no panel at all then.
    public var panelColor: NSColor
    /// The `VisualEffect` tint of that panel view.
    public var panelBlurTint: NSColor
    /// The "Update" pill fill. Drawn here when flat; otherwise both the flat fallback tint and the
    /// `VisualEffect` tint of the pill and icon views.
    public var pillColor: NSColor
    /// No bubble and no wallpaper: there is no panel at all, and the row paints its own pill fill and
    /// its whole icon straight onto the chat background. False over the wallpaper, where the pill and
    /// the icon are live blur views below the row and painting them here would cover the blur; then only
    /// the paper plane, the two lines and the pill label are drawn.
    public var isFlat: Bool
    /// Whether the band is a hole torn through a bubble, so its box has to reserve the two torn strips.
    /// False in list mode, where there is nothing to tear, and for a whole unsupported message.
    public var drawsTornEdges: Bool

    private static func wellColor(_ presentation: TelegramPresentationTheme, onWallpaper: NSColor) -> NSColor {
        if presentation.colors.isDark {
            return onWallpaper.withAlphaComponent(papercutWellAlphaDark)
        } else {
            return NSColor.black.withAlphaComponent(papercutWellAlphaLight)
        }
    }

    /// In a bubble the row floats on the wallpaper on a frosted panel — either its own or the one inside
    /// the hole torn through the bubble — so it takes the service palette, the codebase's existing answer
    /// for text over the wallpaper, instead of the bubble palette, which would be invisible there.
    /// Without a bubble both collapse to a bare row on the chat background in the accent palette.
    public static func make(presentation: TelegramPresentationTheme, isBubbled: Bool, tornEdges: Bool) -> ChatUnsupportedPapercutStyle {
        guard isBubbled else {
            let accent = presentation.colors.accent
            return ChatUnsupportedPapercutStyle(
                titleColor: presentation.colors.text,
                subtitleColor: presentation.colors.grayText,
                iconColor: accent,
                actionColor: presentation.colors.underSelectedColor,
                panelColor: .clear,
                panelBlurTint: .clear,
                pillColor: accent,
                isFlat: true,
                drawsTornEdges: false
            )
        }
        let onWallpaper = presentation.chatServiceItemTextColor
        let panelColor: NSColor
        let panelBlurTint: NSColor
        if presentation.colors.isDark {
            let darkPanelColor = onWallpaper.withAlphaComponent(papercutPanelAlphaDark)
            panelColor = darkPanelColor
            panelBlurTint = darkPanelColor
        } else {
            panelColor = presentation.chatServiceItemColor
            panelBlurTint = presentation.blurServiceColor
        }
        return ChatUnsupportedPapercutStyle(
            titleColor: onWallpaper,
            subtitleColor: onWallpaper.withAlphaComponent(0.8),
            iconColor: onWallpaper,
            actionColor: onWallpaper,
            panelColor: panelColor,
            panelBlurTint: panelBlurTint,
            pillColor: wellColor(presentation, onWallpaper: onWallpaper),
            isFlat: false,
            drawsTornEdges: tornEdges
        )
    }
}

public final class ChatUnsupportedPapercutLayout {
    public let title: String
    public let subtitle: String
    public let action: String
    public let style: ChatUnsupportedPapercutStyle

    private var primary: (TextNodeLayout, TextNode)?
    private var secondary: (TextNodeLayout, TextNode)?
    private var actionNode: (TextNodeLayout, TextNode)?

    private var textBlockWidth: CGFloat = 0.0
    private var pillSize: NSSize = .zero

    public private(set) var size: NSSize = .zero

    public init(title: String, subtitle: String, action: String, style: ChatUnsupportedPapercutStyle) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.style = style
    }

    public func measure(width: CGFloat) {
        let actionString = NSMutableAttributedString()
        _ = actionString.append(string: self.action, color: self.style.actionColor, font: .medium(.short))
        let actionNode = TextNode.layoutText(actionString, nil, 1, .end, NSMakeSize(max(1.0, width), .greatestFiniteMagnitude), nil, false, .center)
        self.actionNode = actionNode
        self.pillSize = NSMakeSize(
            actionNode.0.size.width + papercutRowPillHorizontalInset * 2.0,
            actionNode.0.size.height + papercutRowPillVerticalInset * 2.0
        )

        let chrome = papercutRowIconSize + papercutRowIconSpacing + papercutRowActionSpacing + self.pillSize.width + self.horizontalPadding * 2.0
        let available = max(1.0, width - chrome)

        let titleString = NSMutableAttributedString()
        _ = titleString.append(string: self.title, color: self.style.titleColor, font: .medium(.text))
        let subtitleString = NSMutableAttributedString()
        _ = subtitleString.append(string: self.subtitle, color: self.style.subtitleColor, font: .normal(.short))
        let titleNode = TextNode.layoutText(titleString, nil, 1, .end, NSMakeSize(available, .greatestFiniteMagnitude), nil, false, .left)
        let subtitleNode = TextNode.layoutText(subtitleString, nil, 1, .end, NSMakeSize(available, .greatestFiniteMagnitude), nil, false, .left)
        self.primary = titleNode
        self.secondary = subtitleNode

        self.textBlockWidth = max(titleNode.0.size.width, subtitleNode.0.size.width)
        let textHeight = titleNode.0.size.height + papercutRowTitleSpacing + subtitleNode.0.size.height
        let rowHeight = max(papercutRowIconSize, max(textHeight, self.pillSize.height))
        let panelHeight = rowHeight + self.verticalPadding * 2.0

        if self.style.drawsTornEdges {
            let edges = papercutEdgeHeight * 2.0
            self.size = NSMakeSize(width, edges + papercutBandPanelGap * 2.0 + panelHeight)
        } else {
            self.size = NSMakeSize(min(width, chrome + self.textBlockWidth), panelHeight)
        }
    }

    /// Flat rows have no padding on either side, so the icon's leading edge lands exactly on the
    /// paragraph text's `x` and the pill on the trailing edge of the content.
    private var horizontalPadding: CGFloat {
        return self.style.isFlat ? 0.0 : papercutPanelHorizontalPadding
    }

    /// Vertically a flat row keeps only the gap that clears the neighbouring blocks; a panel breathes.
    private var verticalPadding: CGFloat {
        return self.style.isFlat ? papercutBandPanelGap : papercutPanelVerticalPadding
    }

    public var panelCornerRadius: CGFloat {
        return papercutPanelCornerRadius
    }

    /// The box the row lays out in — over the wallpaper, the frosted panel it sits on. In a torn band the
    /// panel floats inside it: the band rect inset by the torn edges and the gap that clears their teeth
    /// — horizontally it is the band itself, since the hole is widened to the whole bubble by
    /// `ChatRichTextRowView.cutBands`, so the bubble's content inset already is the margin the panel
    /// leaves on either side. Without a tear the box is the whole rect. A whole message *is* the panel.
    public func panelRect(in rect: CGRect) -> CGRect {
        guard self.style.drawsTornEdges else {
            return rect
        }
        let top = rect.minY + papercutEdgeHeight + papercutBandPanelGap
        let bottom = rect.maxY - papercutEdgeHeight - papercutBandPanelGap
        return CGRect(x: rect.minX, y: top, width: rect.width, height: max(0.0, bottom - top))
    }

    public func cleanTearRect(in rect: CGRect) -> CGRect {
        guard self.style.drawsTornEdges else {
            return rect
        }
        let top = rect.minY + papercutEdgeHeight
        let bottom = rect.maxY - papercutEdgeHeight
        return CGRect(x: rect.minX, y: top, width: rect.width, height: max(0.0, bottom - top))
    }

    private func rowRect(in rect: CGRect) -> CGRect {
        return self.panelRect(in: rect).insetBy(dx: self.horizontalPadding, dy: 0.0)
    }

    /// The icon. Over the wallpaper it is a frosted surface of its own, masked to the silhouette — same
    /// reason as `pillRect`: one piece of math for the blurred view and for what is drawn.
    public func iconRect(in rect: CGRect) -> CGRect {
        let row = self.rowRect(in: rect)
        return CGRect(
            x: row.minX,
            y: row.minY + floorToScreenPixels(System.backingScale, (row.height - papercutRowIconSize) / 2.0),
            width: papercutRowIconSize,
            height: papercutRowIconSize
        )
    }

    /// The frosted "Update" pill on that panel. Derived from `panelRect` through the very same math
    /// `drawRow` uses, so the blurred surface and the label drawn onto it can never disagree.
    public func pillRect(in rect: CGRect) -> CGRect {
        guard self.pillSize.width > 0, self.pillSize.height > 0 else {
            return .zero
        }
        let row = self.rowRect(in: rect)
        let textX = row.minX + papercutRowIconSize + papercutRowIconSpacing
        return CGRect(
            x: max(textX + papercutRowActionSpacing, row.maxX - self.pillSize.width),
            y: row.minY + floorToScreenPixels(System.backingScale, (row.height - self.pillSize.height) / 2.0),
            width: self.pillSize.width,
            height: self.pillSize.height
        )
    }

    public func draw(in ctx: CGContext, rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else {
            return
        }
        self.drawRow(in: ctx, rect: rect)
    }

    /// The row is stretched to the panel inside `rect`: icon and the two lines pinned to the leading
    /// edge, pill pinned to the trailing one.
    private func drawRow(in ctx: CGContext, rect: CGRect) {
        let row = self.rowRect(in: rect)
        let iconRect = self.iconRect(in: rect)
        self.drawIcon(in: ctx, rect: iconRect)

        let textX = iconRect.maxX + papercutRowIconSpacing
        let titleHeight = self.primary?.0.size.height ?? 0.0
        let subtitleHeight = self.secondary?.0.size.height ?? 0.0
        let textHeight = titleHeight + papercutRowTitleSpacing + subtitleHeight
        var y = row.minY + floorToScreenPixels(System.backingScale, (row.height - textHeight) / 2.0)
        if let primary = self.primary {
            primary.1.draw(CGRect(origin: CGPoint(x: textX, y: y), size: primary.0.size), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
            y += titleHeight + papercutRowTitleSpacing
        }
        if let secondary = self.secondary {
            secondary.1.draw(CGRect(origin: CGPoint(x: textX, y: y), size: secondary.0.size), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
        }

        guard let action = self.actionNode, self.pillSize.width > 0, self.pillSize.height > 0 else {
            return
        }
        let pillRect = self.pillRect(in: rect)
        if self.style.isFlat {
            ctx.setFillColor(self.style.pillColor.cgColor)
            ctx.addPath(CGPath(roundedRect: pillRect, cornerWidth: pillRect.height / 2.0, cornerHeight: pillRect.height / 2.0, transform: nil))
            ctx.fillPath()
        }
        let labelRect = CGRect(
            origin: CGPoint(
                x: pillRect.minX + floorToScreenPixels(System.backingScale, (pillRect.width - action.0.size.width) / 2.0),
                y: pillRect.minY + floorToScreenPixels(System.backingScale, (pillRect.height - action.0.size.height) / 2.0)
            ),
            size: action.0.size
        )
        action.1.draw(labelRect, in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    }

    /// Over the wallpaper the silhouette *is* a frosted view below this one, tinted and blurred like the
    /// Update pill, so only the plane is drawn here — in `actionColor`, the very colour that pill's label
    /// takes. With no wallpaper to frost against, the whole icon is drawn instead, its plane in the same
    /// colour on the accent silhouette.
    private func drawIcon(in ctx: CGContext, rect: CGRect) {
        let background: NSColor? = self.style.isFlat ? self.style.iconColor : nil
        guard let icon = papercutIconImage(background: background, foreground: self.style.actionColor) else {
            return
        }
        ctx.draw(icon, in: rect)
    }
}

extension ChatUnsupportedPapercutLayout {
    /// The three frosted surfaces the card carries — the rounded panel the row sits on, the icon
    /// silhouette with the plane drawn over it, and the lighter pill under the action label — in the
    /// coordinates `ChatRowView.applyCutBands` wants, i.e. bubble-local. Shared by the whole-message
    /// card and the band inside a rich message, which differ only in that offset.
    public func frostedPanels(in rect: CGRect, offsetBy offset: CGPoint) -> [ChatRowView.FrostedPanel] {
        var result: [ChatRowView.FrostedPanel] = []
        result.append(.init(
            rect: self.panelRect(in: rect).offsetBy(dx: offset.x, dy: offset.y),
            cornerRadius: self.panelCornerRadius,
            blurTint: self.style.panelBlurTint,
            flatColor: self.style.panelColor
        ))
        result.append(.init(
            rect: self.iconRect(in: rect).offsetBy(dx: offset.x, dy: offset.y),
            cornerRadius: 0,
            blurTint: self.style.pillColor,
            flatColor: self.style.pillColor,
            mask: papercutIconMask()
        ))
        let pill = self.pillRect(in: rect)
        if pill.width > 0, pill.height > 0 {
            result.append(.init(
                rect: pill.offsetBy(dx: offset.x, dy: offset.y),
                cornerRadius: pill.height / 2.0,
                blurTint: self.style.pillColor,
                flatColor: self.style.pillColor
            ))
        }
        return result
    }
}

/// Hosts a whole-message card as a message subview. Only the drawn "Update" pill is the click target;
/// everything else is transparent to hit testing and falls through to the row.
public final class ChatUnsupportedPapercutView: Control {
    private var layout: ChatUnsupportedPapercutLayout?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(layout: ChatUnsupportedPapercutLayout) {
        self.layout = layout
        self.needsDisplay = true
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let layout = self.layout, layout.pillRect(in: self.bounds).contains(self.convert(point, from: self.superview)) else {
            return nil
        }
        return super.hitTest(point)
    }

    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        guard let layout = self.layout else {
            return
        }
        layout.draw(in: ctx, rect: self.bounds)
    }
}
