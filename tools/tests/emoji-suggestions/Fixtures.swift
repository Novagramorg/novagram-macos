import Foundation

struct MediaId: Hashable {
    let namespace: Int32
    let id: Int64
}

final class TelegramMediaFile {
    let fileId: MediaId
    let customEmojiText: String?
    var parseCount = 0

    init(id: Int, namespace: Int32 = 0, text: String?) {
        self.fileId = MediaId(namespace: namespace, id: Int64(id))
        self.customEmojiText = text
    }

    struct Accessor {
        let file: TelegramMediaFile

        var fileId: MediaId {
            return file.fileId
        }

        func _parse() -> TelegramMediaFile {
            file.parseCount += 1
            return file
        }
    }
}

extension String {
    var fixed: String {
        return self
    }
}

final class FeaturedItem {
    let accessor: TelegramMediaFile.Accessor
    var reads = 0

    init(_ accessor: TelegramMediaFile.Accessor) {
        self.accessor = accessor
    }

    var file: TelegramMediaFile.Accessor {
        reads += 1
        return accessor
    }
}

struct FeaturedPack {
    let topItems: [FeaturedItem]
}
