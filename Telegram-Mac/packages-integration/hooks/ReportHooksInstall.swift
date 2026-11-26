import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ReportUI

func installReportUIHooks() {
    installReportHooks(.init(makeStickerHeaderRow: { initialSize, stableId, context, text in
        guard let context = context as? AccountContext else {
            preconditionFailure("report header row requires a concrete AccountContext")
        }
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context, sticker: .police, text: text)
    }))
}
