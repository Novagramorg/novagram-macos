import Cocoa

struct ChatInputGlassSlots {
    var attach: NSRect?
    var text: NSRect
    var voice: NSRect?
}

protocol ChatInputGlassMorphing: NSView {
    func glassMorphSlots(visible: Bool) -> ChatInputGlassSlots?
    func setMorphGlassHidden(_ hidden: Bool)
}
