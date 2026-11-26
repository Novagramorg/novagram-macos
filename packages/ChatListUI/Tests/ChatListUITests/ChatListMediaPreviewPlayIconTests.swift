import XCTest
import TelegramCore
import Postbox
@testable import ChatListUI

final class ChatListMediaPreviewPlayIconTests: XCTestCase {
    private func legacyPlayIconVisible(_ media: Media) -> Bool {
        var isHidden = false
        if media is TelegramMediaImage {
            isHidden = true
        } else if let file = media as? TelegramMediaFile {
            if file.isAnimated {
                isHidden = true
            } else {
                isHidden = false
            }
        }
        return !isHidden
    }

    private func file(_ attributes: [TelegramMediaFileAttribute], mimeType: String) -> TelegramMediaFile {
        return TelegramMediaFile(fileId: MediaId(namespace: 0, id: 1), partialReference: nil, resource: LocalFileMediaResource(fileId: 1), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: nil, attributes: attributes, alternativeRepresentations: [])
    }

    private var photo: Media {
        return TelegramMediaImage(imageId: MediaId(namespace: 0, id: 2), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
    }

    private var video: Media {
        return file([], mimeType: "video/mp4")
    }

    private var gif: Media {
        return file([.Animated], mimeType: "video/mp4")
    }

    private var document: Media {
        return file([.FileName(fileName: "report.pdf")], mimeType: "application/pdf")
    }

    private var action: Media {
        return TelegramMediaAction(action: .historyCleared)
    }

    func testPlayIconRuleMatchesTheLegacyVisibility() {
        for media in [photo, video, gif, document, action] {
            XCTAssertEqual(chatListMediaShowsPlayIcon(media), legacyPlayIconVisible(media), "\(type(of: media))")
        }
    }

    func testPhotosAndGifsCreateNoPlayIcon() {
        XCTAssertFalse(chatListMediaShowsPlayIcon(photo))
        XCTAssertFalse(chatListMediaShowsPlayIcon(gif))
    }

    func testVideosKeepThePlayIcon() {
        XCTAssertTrue(chatListMediaShowsPlayIcon(video))
    }
}
