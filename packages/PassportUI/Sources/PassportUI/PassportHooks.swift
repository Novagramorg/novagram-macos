import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import SecureIdUtils

public struct PassportHooks {
    public let openFaq: (any AccountContextProtocol) -> Void
    public let showDocumentsGallery: (any AccountContextProtocol, [SecureIdDocumentValue], Int, InteractionContentViewProtocol?) -> Void

    public init(openFaq: @escaping (any AccountContextProtocol) -> Void,
                showDocumentsGallery: @escaping (any AccountContextProtocol, [SecureIdDocumentValue], Int, InteractionContentViewProtocol?) -> Void) {
        self.openFaq = openFaq
        self.showDocumentsGallery = showDocumentsGallery
    }

    private static var value: PassportHooks?

    public static var shared: PassportHooks {
        guard let value = value else {
            preconditionFailure("PassportHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: PassportHooks) {
        self.value = hooks
    }
}

public func installPassportHooks(_ hooks: PassportHooks) {
    PassportHooks.install(hooks)
}
