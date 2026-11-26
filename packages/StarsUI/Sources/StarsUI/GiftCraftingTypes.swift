import Cocoa
import TelegramCore
import Postbox
import TelegramContext

public enum GiftCraftingState: Equatable {
    case idle
    case crafting
    case failed(gifts: [ProfileGiftsContext.State.StarGift])

    public static func == (lhs: GiftCraftingState, rhs: GiftCraftingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.crafting, .crafting):
            return true
        case (.failed(let lhsGifts), .failed(let rhsGifts)):
            return lhsGifts.count == rhsGifts.count
        default:
            return false
        }
    }
}

public struct GiftCraftChanceIndicator: Equatable {
    public enum Style: Equatable {
        case backdrop([NSColor])
        case pattern(fileId: Int64)
    }
    public let style: Style
    public let name: String
    public let percent: Int
    public init(style: Style, name: String, percent: Int) {
        self.style = style
        self.name = name
        self.percent = percent
    }
}

public struct GiftCraftFeature {
    public let icon: CGImage
    public let title: String
    public let description: String
    public init(icon: CGImage, title: String, description: String) {
        self.icon = icon
        self.title = title
        self.description = description
    }
}

public struct GiftCraftingAreaData {
    public let context: (any AccountContextProtocol)
    public let selectedSlots: [ProfileGiftsContext.State.StarGift?]
    public let selectedCount: Int
    public let successChance: Int
    public let variantsCount: Int
    public let giftFile: TelegramMediaFile?
    public let initialGiftRef: StarGiftReference?
    public let backdropChances: [GiftCraftChanceIndicator]
    public let patternChances: [GiftCraftChanceIndicator]
    public let craftingState: GiftCraftingState
    public let dismiss: () -> Void
    public let craft: (@escaping()->Void, @escaping(ProfileGiftsContext.State.StarGift)->Void, @escaping([ProfileGiftsContext.State.StarGift])->Void, @escaping()->Void) -> Void
    public let removeGift: (ProfileGiftsContext.State.StarGift) -> Void
    public let showModels: () -> Void
    public let showMarketplace: (Int) -> Void
    public let showAbout: () -> Void
    public let showBackdropChanceHint: (String, Int) -> Void
    public let showPatternChanceHint: (String, Int) -> Void
    public let craftAnother: () -> Void
    public let showSuccess: (StarGift.UniqueGift) -> Void

    public init(context: (any AccountContextProtocol), selectedSlots: [ProfileGiftsContext.State.StarGift?], selectedCount: Int, successChance: Int, variantsCount: Int, giftFile: TelegramMediaFile?, initialGiftRef: StarGiftReference?, backdropChances: [GiftCraftChanceIndicator], patternChances: [GiftCraftChanceIndicator], craftingState: GiftCraftingState, dismiss: @escaping () -> Void, craft: @escaping (@escaping()->Void, @escaping(ProfileGiftsContext.State.StarGift)->Void, @escaping([ProfileGiftsContext.State.StarGift])->Void, @escaping()->Void) -> Void, removeGift: @escaping (ProfileGiftsContext.State.StarGift) -> Void, showModels: @escaping () -> Void, showMarketplace: @escaping (Int) -> Void, showAbout: @escaping () -> Void, showBackdropChanceHint: @escaping (String, Int) -> Void, showPatternChanceHint: @escaping (String, Int) -> Void, craftAnother: @escaping () -> Void, showSuccess: @escaping (StarGift.UniqueGift) -> Void) {
        self.context = context
        self.selectedSlots = selectedSlots
        self.selectedCount = selectedCount
        self.successChance = successChance
        self.variantsCount = variantsCount
        self.giftFile = giftFile
        self.initialGiftRef = initialGiftRef
        self.backdropChances = backdropChances
        self.patternChances = patternChances
        self.craftingState = craftingState
        self.dismiss = dismiss
        self.craft = craft
        self.removeGift = removeGift
        self.showModels = showModels
        self.showMarketplace = showMarketplace
        self.showAbout = showAbout
        self.showBackdropChanceHint = showBackdropChanceHint
        self.showPatternChanceHint = showPatternChanceHint
        self.craftAnother = craftAnother
        self.showSuccess = showSuccess
    }
}
