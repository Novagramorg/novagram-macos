import Cocoa
import TelegramCore
import TGUIKit
import TelegramContext
import AlertsUI
import Localization
import TelegramUtils

public func fileSizeLimitExceed(context: any AccountContextProtocol, fileSize: Int64) -> Bool {
    if context.isPremium {
        return fileSize <= context.premiumLimits.upload_max_fileparts_premium
    } else {
        return fileSize <= context.premiumLimits.upload_max_fileparts_default
    }
}

public func showFileLimit(context: any AccountContextProtocol, fileSize: Int64?) {
    if context.isPremium {
        alert(for: context.window, info: strings().appMaxFileSizeNew(String.prettySized(with: context.premiumLimits.upload_max_fileparts_premium, afterDot: 0, round: true)))
    } else {
        showPremiumLimit(context: context, type: fileSize != nil ? .uploadFile(Int(fileSize!)) : .uploadFile(nil))
    }
}
