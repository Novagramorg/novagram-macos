import Foundation
import SwiftSignalKit
import Postbox
import TelegramMedia
import TelegramMediaPlayer
import TelegramCore
import TGUIKit
import TelegramTheme
import TelegramContext
import TelegramUtils

public final class SoundEffectPlay {
    private static var queue: [String: MediaPlayer] = [:]
    
    public static func play(postbox: Postbox, resource: TelegramMediaResource, volume: Float = 1.0) {
        let player = MediaPlayer(postbox: postbox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: resource), streamable: false, video: false, preferSoftwareDecoding: false, enableSound: true, volume: volume, fetchAutomatically: true)
        queue[resource.id.stringRepresentation] = player
         player.play()
         player.actionAtEnd = .action({
             DispatchQueue.main.async {
                 SoundEffectPlay.queue.removeValue(forKey: resource.id.stringRepresentation)
             }
         })
    }
    
    public static func resource(name: String?, type: String = "mp3") -> TelegramMediaResource? {
        if let name = name, let filePath = Bundle.main.path(forResource: name, ofType: type) {
            let id = arc4random64()
            return LocalFileReferenceMediaResource(localFilePath: filePath, randomId: id)
        }
        return nil
    }
    
    public static func play(postbox: Postbox, path: String, volume: Float = 1.0) {
        let id = arc4random64()
        let resource = LocalFileReferenceMediaResource(localFilePath: path, randomId: id)
        play(postbox: postbox, resource: resource, volume: volume)
    }

    public static func play(postbox: Postbox, name: String?, type: String = "mp3", volume: Float = 1.0) {
        if let name = name, let filePath = Bundle.main.path(forResource: name, ofType: type) {
            let id = arc4random64()
            let resource = LocalFileReferenceMediaResource(localFilePath: filePath, randomId: id)
            play(postbox: postbox, resource: resource, volume: volume)
        }
    }
}
