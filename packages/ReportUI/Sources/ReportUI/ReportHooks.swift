import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public struct ReportHooks {
    public let makeStickerHeaderRow: (NSSize, AnyHashable, any AccountContextProtocol, NSAttributedString) -> TableRowItem

    public init(makeStickerHeaderRow: @escaping (NSSize, AnyHashable, any AccountContextProtocol, NSAttributedString) -> TableRowItem) {
        self.makeStickerHeaderRow = makeStickerHeaderRow
    }

    private static var value: ReportHooks?

    public static var shared: ReportHooks {
        guard let value = value else {
            preconditionFailure("ReportHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: ReportHooks) {
        self.value = hooks
    }
}

public func installReportHooks(_ hooks: ReportHooks) {
    ReportHooks.install(hooks)
}
