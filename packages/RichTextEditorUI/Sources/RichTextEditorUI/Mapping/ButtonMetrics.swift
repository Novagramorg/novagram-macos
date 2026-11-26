#if canImport(AppKit)
import AppKit

/// Pill geometry, pinned to the macOS InstantPage V2 renderer's own constants
/// (`InstantPageV2Layout.swift` / `InstantPageInlineButton.swift`) so editor pills match the sent
/// message. Field names mirror the iOS `RichTextButtonMetrics` so the packing transcription ports
/// unchanged; the VALUES are the macOS renderer's, not iOS's.
///
/// Font sizes are FIXED — the renderer does not scale button labels by any font-size setting.
@available(macOS 12, *)
public struct RichTextButtonMetrics: Equatable {
    /// Label size for an inline `RichText.textButton`. Medium weight (the renderer pushes `.medium`
    /// on the inline path), unlike the semibold block pills.
    public var inlineFontSize: CGFloat
    /// Label size for a `pageBlockButtonRow` member. Semibold.
    public var blockFontSize: CGFloat
    /// Label weight for an inline pill (`InstantPageTextItem`'s `.medium` push).
    public var inlineFontWeight: NSFont.Weight
    /// Label weight for a block-row pill (`layoutButtonRowV2`'s `.semibold` push).
    public var blockFontWeight: NSFont.Weight
    /// Per-side padding between the label ink and the pill edge, inline.
    public var inlineHorizontalPadding: CGFloat
    /// Per-side horizontal padding for a block-row pill. The macOS renderer uses ONE padding for both
    /// pill kinds (`instantPageInlineButtonHorizontalPadding`), unlike iOS's wider 19pt block padding.
    public var blockHorizontalPadding: CGFloat
    /// What a block-row pill falls back to when its label does not fit at `blockHorizontalPadding` —
    /// the renderer's `instantPageBlockButtonMinimumHorizontalPaddingV2` (6.0), which arms the two-try
    /// re-measure so a truncating label wins the padding difference back as label room.
    public var blockMinimumHorizontalPadding: CGFloat
    /// Per-side vertical padding, both pill kinds. The renderer trims half a physical pixel off this
    /// for raster centring — a backing-scale detail the editor cannot express, so the nominal value.
    public var verticalPadding: CGFloat
    /// Reserved (unused): extra gap between two DIRECTLY ADJACENT inline pills. No macOS renderer rule
    /// or editor consumer reads it; kept so the iOS field layout survives.
    public var adjacentSpacing: CGFloat
    /// Fixed height of a block-row pill (`instantPageBlockButtonHeightV2`).
    public var blockRowHeight: CGFloat
    /// Gap between two pills in a block row, and between two wrapped rows.
    public var blockSpacing: CGFloat
    /// Horizontal room a badge-bearing pill keeps clear on EACH side so a centred label cannot run
    /// under the corner action icon: an 8pt icon (url/copy) plus its `max(5, round(32 * 0.3)) = 10`
    /// inset on both sides (`instantPageButtonIconAllowance` at pill height 32). Per-action reserves
    /// (10pt share/profile icons → 30) derive from `richTextButtonBadgeReserve`; this flat value is
    /// the `.unsupported` approximation — the opaque action blob doesn't say which icon the renderer
    /// would pick, and url/copy's 28 is the most common. The editor draws no badge, but must reserve
    /// the same room or its labels would ellipsise differently than the sent message.
    public var blockIconReserve: CGFloat
    /// Maximum pills laid out in one visual row before wrapping.
    public var maximumButtonsPerRow: Int

    public init(
        inlineFontSize: CGFloat,
        blockFontSize: CGFloat,
        inlineFontWeight: NSFont.Weight = .medium,
        blockFontWeight: NSFont.Weight = .semibold,
        inlineHorizontalPadding: CGFloat,
        blockHorizontalPadding: CGFloat,
        blockMinimumHorizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        adjacentSpacing: CGFloat,
        blockRowHeight: CGFloat,
        blockSpacing: CGFloat,
        blockIconReserve: CGFloat,
        maximumButtonsPerRow: Int
    ) {
        self.inlineFontSize = inlineFontSize
        self.blockFontSize = blockFontSize
        self.inlineFontWeight = inlineFontWeight
        self.blockFontWeight = blockFontWeight
        self.inlineHorizontalPadding = inlineHorizontalPadding
        self.blockHorizontalPadding = blockHorizontalPadding
        self.blockMinimumHorizontalPadding = blockMinimumHorizontalPadding
        self.verticalPadding = verticalPadding
        self.adjacentSpacing = adjacentSpacing
        self.blockRowHeight = blockRowHeight
        self.blockSpacing = blockSpacing
        self.blockIconReserve = blockIconReserve
        self.maximumButtonsPerRow = maximumButtonsPerRow
    }

    /// The values the macOS V2 renderer ships.
    public static let `default` = RichTextButtonMetrics(
        inlineFontSize: 13.0,
        blockFontSize: 14.0,
        inlineHorizontalPadding: 7.0,
        blockHorizontalPadding: 7.0,
        blockMinimumHorizontalPadding: 6.0,
        verticalPadding: 1.0,
        adjacentSpacing: 3.0,
        blockRowHeight: 32.0,
        blockSpacing: 6.0,
        blockIconReserve: 28.0,
        maximumButtonsPerRow: 8
    )
}
#endif
