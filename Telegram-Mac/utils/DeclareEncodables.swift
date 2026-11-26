import Cocoa
import Postbox
import TelegramMediaResources
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

private var telegramUIDeclaredEncodables: Void = {
    declareEncodable(VideoLibraryMediaResource.self, f: { VideoLibraryMediaResource(decoder: $0) })
    declareEncodable(LocalFileVideoMediaResource.self, f: { LocalFileVideoMediaResource(decoder: $0) })
    declareEncodable(LocalFileGifMediaResource.self, f: { LocalFileGifMediaResource(decoder: $0) })
    declareEncodable(LottieSoundMediaResource.self, f: { LottieSoundMediaResource(decoder: $0) })
    declareEncodable(LocalFileArchiveMediaResource.self, f: { LocalFileArchiveMediaResource(decoder: $0) })
    declareEncodable(ExternalMusicAlbumArtResource.self, f: { ExternalMusicAlbumArtResource(decoder: $0) })
    declareEncodable(LocalBundleResource.self, f: { LocalBundleResource(decoder: $0) })
    return
}()

public func telegramUIDeclareEncodables() {
    let _ = telegramUIDeclaredEncodables
}
