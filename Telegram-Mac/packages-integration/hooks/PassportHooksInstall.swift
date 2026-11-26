import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import PassportUI

func installPassportUIHooks() {
    installPassportHooks(.init(openFaq: { context in
        guard let context = context as? AccountContext else {
            return
        }
        openFaq(context: context)
    }, showDocumentsGallery: { context, medias, firstIndex, delegate in
        guard let context = context as? AccountContext else {
            return
        }
        showSecureIdDocumentsGallery(context: context, medias: medias, firstIndex: firstIndex, delegate)
    }))
}
