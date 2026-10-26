import Cocoa
import AVFoundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramMediaResources
import ChatHistoryModel
import FilePanels
import LocalAnimations
import MessageUtils
import FenixuzCore

// Round video from a file (attach menu): picks a video and sends it as an instant round video message.
func fenixuzRoundVideoMenuItem(chatInteraction: ChatInteraction) -> ContextMenuItem? {
    if let channel = chatInteraction.peer as? TelegramChannel, permissionText(from: channel, for: .banSendInstantVideos) != nil {
        return nil
    }
    return ContextMenuItem(FenixuzL10n.current.attach_roundVideo, handler: { [weak chatInteraction] in
        guard let chatInteraction else {
            return
        }
        let context = chatInteraction.context
        let peerId = chatInteraction.peerId
        let threadId = chatInteraction.chatLocation.threadId
        filePanel(with: videoExts, allowMultiple: false, canChooseDirectories: false, for: context.window, completion: { paths in
            if let path = paths?.first {
                fenixuzSendRoundVideo(path: path, context: context, peerId: peerId, threadId: threadId)
            }
        })
    }, itemImage: MenuAnimation.menu_video.value)
}

private func fenixuzSendRoundVideo(path: String, context: any AccountContextProtocol, peerId: PeerId, threadId: Int64?) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let duration = CMTimeGetSeconds(asset.duration)
    guard duration > 0 else {
        return
    }

    let randomId = arc4random64()
    let resource = LocalFileVideoMediaResource(randomId: randomId, path: path)

    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.maximumSize = CGSize(width: 320, height: 320)
    imageGenerator.appliesPreferredTrackTransform = true
    let cgImage = try? imageGenerator.copyCGImage(at: CMTime(seconds: 0.0, preferredTimescale: asset.duration.timescale), actualTime: nil)

    var representations: [TelegramMediaImageRepresentation] = []
    if let cgImage {
        let thumbResource = LocalFileMediaResource(fileId: arc4random64())
        let data = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, cgImage, nil)
            if CGImageDestinationFinalize(destination) {
                context.account.postbox.mediaBox.storeResourceData(thumbResource.id, data: data as Data)
                representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 320, height: 320), resource: thumbResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
            }
        }
    }

    let attributes: [TelegramMediaFileAttribute] = [
        .Video(duration: Double(duration), size: PixelDimensions(width: 384, height: 384), flags: [.instantRoundVideo, .supportsStreaming], preloadSize: nil, coverTime: nil, videoCodec: nil),
        .FileName(fileName: "video_message.mp4")
    ]
    let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: randomId), partialReference: nil, resource: resource, previewRepresentations: representations, videoThumbnails: [], videoCover: nil, immediateThumbnailData: nil, mimeType: "video/mp4", size: nil, attributes: attributes, alternativeRepresentations: [])

    _ = Sender.enqueue(media: file, context: context, peerId: peerId, replyId: nil, threadId: threadId).start()
}
