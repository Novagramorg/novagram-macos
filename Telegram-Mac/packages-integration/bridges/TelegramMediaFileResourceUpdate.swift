import Foundation
import TelegramCore
import Postbox

extension TelegramMediaFile {
    func withUpdatedResource(_ resource: TelegramMediaResource) -> TelegramMediaFile {
        return TelegramMediaFile(fileId: self.fileId, partialReference: self.partialReference, resource: resource, previewRepresentations: self.previewRepresentations, videoThumbnails: self.videoThumbnails, immediateThumbnailData: self.immediateThumbnailData, mimeType: self.mimeType, size: self.size, attributes: self.attributes, alternativeRepresentations: self.alternativeRepresentations)
    }
}
