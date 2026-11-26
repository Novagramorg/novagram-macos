import Cocoa
import TGUIKit

enum MetadataRenderType { case list, bubble }
enum MetadataForwardType { case FullHeader, ShortHeader, none }
struct MetadataForwardInfo { var psaType: String? }
struct MetadataMessage { var forwardInfo: MetadataForwardInfo? }
struct MetadataEntry { var renderType: MetadataRenderType = .list }
struct MetadataPalette {
    var grayText: NSColor = .gray
    var greenUI = NSColor(srgbRed: 0.2, green: 0.65, blue: 0.3, alpha: 1)
}
struct MetadataChatPalette {
    var gray: NSColor = .darkGray
    var green: NSColor = .systemGreen
    func grayText(_ incoming: Bool, _ bubble: Bool) -> NSColor { gray }
    func greenUI(_ incoming: Bool, _ bubble: Bool) -> NSColor { green }
}
struct MetadataPresentation {
    var colors = MetadataPalette()
    var chat = MetadataChatPalette()
}
struct MetadataStrings { var messagesForwardHeader = "Forwarded message" }
var theme = MetadataPresentation()
var metadataStrings = MetadataStrings()
func strings() -> MetadataStrings { metadataStrings }
func localizedPsa(_ key: String, type: String) -> String { "Public announcement: " + type }

class MetadataEnvironment {
    var channelViews: TextViewLayout?
    var replyCount: TextViewLayout?
    var forwardHeader: TextViewLayout?
    var guestChatBadge: TextViewLayout?
    var contentOffset = NSPoint(x: 40, y: 0)
    var hasBubble = true
    var isBubbled = false
    var isIncoming = true
    var entry = MetadataEntry()
    var renderType = MetadataRenderType.list
    var forwardType = MetadataForwardType.FullHeader
    var message: MetadataMessage?
    var presentation = MetadataPresentation()
}
