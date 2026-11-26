import Cocoa
import TelegramCore

func installCollageHooks() {
    CollageHooks.install(CollageHooks(fileAttributes: { mime, path, isMedia, inCollage in
        return Sender.fileAttributes(for: mime, path: path, isMedia: isMedia, inCollage: inCollage)
    }))
}
