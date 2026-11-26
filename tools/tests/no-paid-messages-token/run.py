from pathlib import Path
import base64
import re
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
strings_path = root / "Telegram-Mac/en.lproj/Localizable.strings"
english = strings_path.read_text(encoding="utf-16")
ios_english = (root / "submodules/telegram-ios/Telegram/Telegram-iOS/en.lproj/Localizable.strings").read_text()
templates = {}
for key in ["Notification.NoPaidMessagesTokenUsed", "Notification.NoPaidMessagesTokenUsedYou"]:
    pattern = r'"' + re.escape(key) + r'"\s*=\s*"([^"]*)";'
    templates[key] = re.search(pattern, english).group(1)
    assert templates[key] == re.search(pattern, ios_english).group(1)


def branch(path):
    source = path.read_text()
    return source.split("case .noPaidMessagesTokenUsed:\n", 1)[1].split("case let .managedBotCreated", 1)[0]


helper = (root / "packages/MessageTextUtils/Sources/MessageTextUtils/NoPaidMessagesTokenUsedText.swift").read_text().replace("import Localization\n", "")
preview = branch(root / "packages/MessageTextUtils/Sources/MessageTextUtils/TextUtils.swift")
row = branch(root / "packages/ChatUI/Sources/ChatUI/ChatServiceItem.swift")
accessors = (root / "packages/Localization/Sources/Localization/Localizable.swift").read_text()
functions = "\n".join(re.search(r'  public static func ' + name + r'\([^}]+\}', accessors).group(0) for name in ["notificationNoPaidMessagesTokenUsed", "notificationNoPaidMessagesTokenUsedYou"])
constants = "\n".join('    "' + key + '": String(data: Data(base64Encoded: "' + base64.b64encode(value.encode()).decode() + '")!, encoding: .utf8)!,' for key, value in templates.items())
scaffold = '''import AppKit

var translations: [String: String] = [
TEMPLATES
]
final class L10n {
ACCESSORS
    static func tr(_ table: String, _ key: String, _ argument: String) -> String {
        String(format: translations[key]!, argument)
    }
}
func strings() -> L10n.Type { L10n.self }
struct Peer { let compactDisplayTitle: String }
struct MessageId { let peerId: Int64 }
struct Message { let id: MessageId; let peers: [Int64: Peer] }
struct Account { let peerId: Int64 }
struct MessageTextEntity {
    enum Kind: Equatable { case TextMention(peerId: Int64) }
    let range: Range<Int>
    let type: Kind
}
struct ChatHistoryLink {
    let peerId: Int64
    static func peerInfo(link: String, peerId: Int64, action: (() -> Void)?, openChat: Bool, postId: Int64?, callback: () -> Void) -> ChatHistoryLink {
        ChatHistoryLink(peerId: peerId)
    }
}
struct Interaction { let openInfo: () -> Void = {} }
struct Theme { let fontSize: CGFloat = 13 }
extension NSFont {
    static func normal(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size) }
    static func medium(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .medium) }
}
extension NSMutableAttributedString {
    func append(string: String, color: NSColor, font: NSFont) {
        append(NSAttributedString(string: string, attributes: [.foregroundColor: color, .font: font]))
    }
    func add(link: ChatHistoryLink, for range: NSRange, color: NSColor) {
        addAttributes([.link: link.peerId, .foregroundColor: color], range: range)
    }
}
func preview(_ message: Message, authorId: Int64?, account: Account) -> (String, [MessageTextEntity]) {
    var text = ""
    var entities: [MessageTextEntity] = []
PREVIEW
    return (text, entities)
}
func row(_ message: Message, authorId: Int64?, context: Account) -> NSAttributedString {
    let attributedString = NSMutableAttributedString(string: "")
    let grayTextColor = NSColor.gray
    let theme = Theme()
    let chatInteraction = Interaction()
ROW
    return attributedString
}
'''.replace("TEMPLATES", constants).replace("ACCESSORS", functions).replace("PREVIEW", preview).replace("ROW", row)
tests = '''
var checked = 0
for name in ["Alice", "You", "link", "message", "👩🏽‍💻 café", "مرحبا", "שלום", "", "\\u{fffc}"] {
    for author: Int64? in [1, 2, nil] {
        for hasPeer in [true, false] {
            let message = Message(id: MessageId(peerId: 2), peers: hasPeer ? [2: Peer(compactDisplayTitle: name)] : [:])
            let account = Account(peerId: 1)
            let result = preview(message, authorId: author, account: account)
            let attributed = row(message, authorId: author, context: account)
            let peerName = hasPeer ? name : ""
            let expected = author == 1 ? "You used \\(peerName)’s link to message for free" : "\\(peerName) used your link to message you for free"
            precondition(result.0 == expected)
            precondition(attributed.string == expected)
            let expectedRange = NSRange(location: author == 1 ? 9 : 0, length: peerName.utf16.count)
            precondition(result.1.count == (peerName.isEmpty ? 0 : 1))
            if let entity = result.1.first {
                precondition(entity.range == expectedRange.location ..< NSMaxRange(expectedRange))
                precondition(entity.type == .TextMention(peerId: 2))
                precondition((attributed.string as NSString).substring(with: expectedRange) == peerName)
            }
            for index in 0 ..< attributed.length {
                let link = attributed.attribute(.link, at: index, effectiveRange: nil) as? Int64
                precondition(link == (NSLocationInRange(index, expectedRange) ? 2 : nil))
            }
            checked += 1
        }
    }
}
translations["Notification.NoPaidMessagesTokenUsedYou"] = "🔗 Free message via %1$@"
let reordered = noPaidMessagesTokenUsedText(peerName: "You 👩🏽‍💻", isAuthor: true)
precondition((reordered.text as NSString).substring(with: reordered.peerRange) == "You 👩🏽‍💻")
translations["Notification.NoPaidMessagesTokenUsedYou"] = "No mention"
let missing = noPaidMessagesTokenUsedText(peerName: "Alice", isAuthor: true)
precondition(missing.peerRange.location == NSNotFound)
precondition(missing.text == "No mention")
print("Passed \\(checked) preview/row cases, reordered/missing placeholders, and iOS localization parity.")
'''
with tempfile.TemporaryDirectory(prefix="telegram-service-message-") as temporary:
    package = Path(temporary)
    (package / "Helper.swift").write_text(helper)
    (package / "main.swift").write_text(scaffold + tests)
    executable = package / "ServiceMessageTests"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(package / "cache"), str(package / "Helper.swift"), str(package / "main.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
