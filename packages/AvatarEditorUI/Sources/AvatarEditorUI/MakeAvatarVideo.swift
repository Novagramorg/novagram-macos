import Foundation
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit

public func makeAvatarVideo(_ object: MediaObjectToAvatar, updatePhoto: @escaping(Signal<NSImage, NoError>) -> Void, updateVideo: @escaping(Signal<VideoAvatarGeneratorState, NoError>) -> Void) {
    
    switch object.object.foreground.type {
    case .emoji, .sticker:
        updatePhoto(object.start() |> mapToSignal { value in
            if let result = value.result {
                switch result {
                case let .image(image):
                    return .single(image)
                default:
                    return .complete()
                }
            } else {
                return .complete()
            }
        })
    default:
        let signal:Signal<VideoAvatarGeneratorState, NoError> = object.start() |> map { value in
            if let result = value.result {
                switch result {
                case let .video(path, thumb):
                    return .complete(thumb: thumb, video: path, keyFrame: nil)
                default:
                    return .error
                }
            } else if let status = value.status {
                switch status {
                case let .initializing(thumb):
                    return .start(thumb: thumb)
                case let .converting(progress):
                    return .progress(progress)
                default:
                    return .error
                }
            } else {
                return .error
            }
        }
        updateVideo(signal)
    }
}
