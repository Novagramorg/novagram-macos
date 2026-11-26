import Foundation
import Postbox
import TelegramCore

public func resourcePath(_ postbox: Postbox, _ resource: MediaResource) -> String {
    if let resource = resource as? LocalFileReferenceMediaResource {
        return resource.localFilePath
    } else {
        return postbox.mediaBox.resourcePath(resource)
    }
}
