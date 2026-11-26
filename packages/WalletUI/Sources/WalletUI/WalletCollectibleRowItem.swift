import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import WalletContext
import GZIP

private let walletCollectibleLottieMaximumSize = 5 * 1024 * 1024

func walletCollectibleLottieData(_ data: Data) -> Data? {
    guard data.count <= walletCollectibleLottieMaximumSize else { return nil }
    let decoded: Data
    if data.starts(with: [0x1f, 0x8b]) {
        guard let unpacked = TGGUnzipData(data, UInt32(walletCollectibleLottieMaximumSize)) else { return nil }
        decoded = unpacked
    } else {
        decoded = data
    }
    guard decoded.count <= walletCollectibleLottieMaximumSize,
          (try? JSONSerialization.jsonObject(with: decoded)) is [String: Any] else { return nil }
    return decoded
}

func walletCollectibleNameAttributedString(_ name: String, font: NSFont) -> NSAttributedString {
    let string = NSMutableAttributedString(string: name)
    string.addAttribute(.font, value: font, range: NSMakeRange(0, string.length))
    string.addAttribute(.foregroundColor, value: theme.colors.text, range: NSMakeRange(0, string.length))
    if let numberRange = name.range(of: "#[0-9]+$", options: .regularExpression) {
        string.addAttribute(.foregroundColor, value: theme.colors.grayText, range: NSRange(numberRange, in: name))
    }
    return string
}

func walletCollectibleGiftSlug(name: String) -> String? {
    guard let hash = name.lastIndex(of: "#") else {
        return nil
    }
    let title = name[..<hash].filter { $0.isLetter || $0.isNumber }
    let number = name[name.index(after: hash)...].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !number.isEmpty, number.allSatisfy(\.isNumber) else {
        return nil
    }
    return String(title) + "-" + number
}

func walletCollectibleWebFile(_ file: WalletNftFile?) -> TelegramMediaWebFile? {
    guard let file else {
        return nil
    }
    return TelegramMediaWebFile(resource: file.resource, mimeType: file.mimeType, size: file.size, attributes: [])
}
