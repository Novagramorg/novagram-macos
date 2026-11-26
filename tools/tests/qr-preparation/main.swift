import Foundation

struct FileId { var id: Int64 = 1 }
struct File { var fileId = FileId() }
struct Emoji { var file = File() }
struct Settings { var kind: Int32 = 0; var customFileIds: [Int64] = [] }
struct QrStudioLook {
    enum Kind: Int32 { case color, emoji, gift }
    enum Backdrop { case color, emoji }
    var kind: Kind = .color
    var backdrop: Backdrop = .color
    var themeId: String?
    var selectedTheme: Int?
    var selectedGift: Int?
    var backdropId: Int?
    var emojiInk: Int?
    var inkEmoji: Emoji?
}
struct Fixture {
    var isSetupComplete = true
    var isLookLoaded = true
    var didReceiveServerLook = true
    var pendingServerLook: Int?
    var didLoadUnicodeEmoji = true
    var rawSettings: Settings?
    var customEmojiFiles: [Int64: File] = [:]
    var resolvedCustomEmojiIds: Set<Int64> = []
    var failedEmojiInkIds: Set<Int64> = []
    var areGiftsLoaded = false
    var areBackdropsLoaded = false
    var canEdit = true
    var look = QrStudioLook()
__READINESS__
}
var count = 0
func check(_ name: String, expected: Bool, _ configure: (inout Fixture) -> Void = { _ in }) {
    var value = Fixture()
    configure(&value)
    precondition(value.isLookReady == expected, name)
    count += 1
}
check("Resolved default", expected: true)
check("Editable profile waits for server design", expected: false) { $0.didReceiveServerLook = false }
check("Read-only profile waits for server design", expected: false) { $0.canEdit = false; $0.didReceiveServerLook = false }
check("Pending server design cannot reveal local design", expected: false) { $0.pendingServerLook = 1 }
check("Synchronous data cannot reveal midway through setup", expected: false) { $0.isSetupComplete = false }
check("Local settings must finish loading", expected: false) { $0.isLookLoaded = false }
check("Unicode emoji waits for pack", expected: false) { $0.look.kind = .emoji; $0.didLoadUnicodeEmoji = false }
check("Custom emoji waits for resolution", expected: false) { $0.look.kind = .emoji; $0.rawSettings = Settings(customFileIds: [1]) }
check("Resolved custom emoji", expected: true) { $0.look.kind = .emoji; $0.rawSettings = Settings(customFileIds: [1]); $0.customEmojiFiles[1] = File() }
check("Missing deleted custom emoji cannot block forever", expected: true) { $0.look.kind = .emoji; $0.rawSettings = Settings(customFileIds: [1]); $0.resolvedCustomEmojiIds.insert(1) }
check("Template emoji needs no image ink probe", expected: true) { $0.look.kind = .emoji; $0.look.backdrop = .emoji }
check("Emoji ink waits for first frame", expected: false) { $0.look.kind = .emoji; $0.look.backdrop = .emoji; $0.look.inkEmoji = Emoji() }
check("Failed image decoding uses stable fallback ink", expected: true) { $0.look.kind = .emoji; $0.look.backdrop = .emoji; $0.look.inkEmoji = Emoji(); $0.failedEmojiInkIds.insert(1) }
check("Resolved image ink", expected: true) { $0.look.kind = .emoji; $0.look.backdrop = .emoji; $0.look.inkEmoji = Emoji(); $0.look.emojiInk = 1 }
check("Backdrop must resolve", expected: false) { $0.look.backdropId = 1 }
check("Resolved backdrop", expected: true) { $0.look.backdropId = 1; $0.areBackdropsLoaded = true }
check("Gift must resolve", expected: false) { $0.look.kind = .gift }
check("Server gift does not wait for entire gift list", expected: true) { $0.look.kind = .gift; $0.look.selectedGift = 1 }
check("Local gift cannot reveal color fallback while loading", expected: false) { $0.rawSettings = Settings(kind: 2) }
print("Passed \(count) QR preparation readiness cases")
