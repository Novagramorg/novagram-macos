import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramMediaResources
public func freeMediaFileResourceInteractiveFetched(account: Account, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, resource: MediaResource) -> Signal<FetchResourceSourceType, FetchResourceError> {
    return fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: userLocation, userContentType: MediaResourceUserContentType(file: fileReference.media), reference: fileReference.resourceReference(resource))
}

public func freeMediaFileResourceInteractiveFetched(postbox: Postbox, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, resource: MediaResource, range: (Range<Int64>, MediaBoxFetchPriority)? = nil) -> Signal<FetchResourceSourceType, FetchResourceError> {
    return fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: userLocation, userContentType: MediaResourceUserContentType(file: fileReference.media), reference: fileReference.resourceReference(resource), range: range)
}
