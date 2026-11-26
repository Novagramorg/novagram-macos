#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasMediaControlsTests: AppKitTestCase {
    private func canvas(_ blocks: [CanvasModelBlock], width: CGFloat = 320) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.imageProvider = { [self] _ in image(of: CGSize(width: 80, height: 60), fill: .systemPink) }
        v.mediaGroupMosaic = { ids, w in
            ids.enumerated().map { i, _ in CGRect(x: CGFloat(i % 2) * w / 2, y: CGFloat(i / 2) * 100, width: w / 2, height: 100) }
        }
        v.setModelBlocks(blocks, width: width)
        v.frame = CGRect(x: 0, y: 0, width: width, height: 600); v.layoutSubtreeIfNeeded()
        return v
    }

    func test_kind_singleImage_video_collage_slider() {
        let img = canvas([.media(MediaBlock(id: BlockID("i"), kind: .image, mediaID: "m"))]).boxes[0]
        XCTAssertEqual((img as? MediaControlsProviding)?.mediaControlsKind, .singleImage)
        let vid = canvas([.media(MediaBlock(id: BlockID("v"), kind: .video, mediaID: "m"))]).boxes[0]
        XCTAssertEqual((vid as? MediaControlsProviding)?.mediaControlsKind, .singleVideo)
        let file = canvas([.media(MediaBlock(id: BlockID("f"), kind: .file, mediaID: "m"))]).boxes[0]
        XCTAssertNil((file as? MediaControlsProviding)?.mediaControlsKind, "file gets no overlay chrome")
        let audio = canvas([.media(MediaBlock(id: BlockID("au"), kind: .audio, mediaID: "m"))]).boxes[0]
        XCTAssertNil((audio as? MediaControlsProviding)?.mediaControlsKind, "audio gets no overlay chrome")
        let map = canvas([.media(MediaBlock(id: BlockID("mp"), kind: .map, mediaID: "m"))]).boxes[0]
        XCTAssertNil((map as? MediaControlsProviding)?.mediaControlsKind, "map gets no overlay chrome")
        let col = canvas([.mediaGroup(MediaGroupBlock(id: BlockID("c"), kind: .collage, mediaIDs: ["a", "b"]))]).boxes[0]
        XCTAssertEqual((col as? MediaControlsProviding)?.mediaControlsKind, .collage)
        let sld = canvas([.mediaGroup(MediaGroupBlock(id: BlockID("s"), kind: .slideshow, mediaIDs: ["a", "b"]))]).boxes[0]
        XCTAssertEqual((sld as? MediaControlsProviding)?.mediaControlsKind, .slider)
    }

    func test_mediaAreaFrame_isAboveCaption_andTileFramesForCollage() {
        let v = canvas([.mediaGroup(MediaGroupBlock(id: BlockID("c"), kind: .collage, mediaIDs: ["a", "b"]))])
        let g = v.boxes[0] as! MediaControlsProviding
        let area = g.mediaAreaFrame
        XCTAssertEqual(area.minY, v.boxes[0].frame.minY + MediaGroupBlockBox.verticalInset, accuracy: 0.5)
        XCTAssertLessThan(area.maxY, v.boxes[0].textOrigin.y, "media area sits above the caption text")
        let tiles = g.mediaTileFrames()
        XCTAssertEqual(tiles.count, 2, "two collage tiles")
        XCTAssertTrue(area.contains(CGPoint(x: tiles[0].midX, y: tiles[0].midY)), "tiles lie within the media area")
    }

    func test_mediaTileFrames_singleMedia_isWholeArea() {
        let v = canvas([.media(MediaBlock(id: BlockID("v"), kind: .video, mediaID: "m"))])
        let m = v.boxes[0] as! MediaControlsProviding
        XCTAssertEqual(m.mediaTileFrames().count, 1)
        XCTAssertEqual(m.mediaTileFrames()[0], m.mediaAreaFrame)
    }

    func test_videoMediaAreaFrame_bleedsFullWidth() {
        let v = canvas([.media(MediaBlock(id: BlockID("v"), kind: .video, mediaID: "m"))], width: 320)
        let box = v.boxes[0] as! MediaBlockBox
        let area = box.mediaAreaFrame
        XCTAssertEqual(area.minX, box.frame.minX - CanvasMetrics.pageMargin, accuracy: 0.5,
                       "a video bleeds: its media area starts one page margin left of the content strip")
        XCTAssertEqual(area.width, box.layoutWidth + CanvasMetrics.pageMargin * 2, accuracy: 0.5,
                       "a video's media area spans the content strip plus both page margins")
    }

    func test_sliderTileFrames_isSingleWholeArea() {
        let v = canvas([.mediaGroup(MediaGroupBlock(id: BlockID("s"), kind: .slideshow, mediaIDs: ["a", "b"]))])
        let g = v.boxes[0] as! MediaControlsProviding
        XCTAssertEqual(g.mediaTileFrames().count, 1, "a slider presents one paging area, not per-tile frames")
        XCTAssertEqual(g.mediaTileFrames()[0], g.mediaAreaFrame)
    }

    func test_controlsView_created_positioned_rebuilt_removed() {
        let v = canvas([.mediaGroup(MediaGroupBlock(id: BlockID("c"), kind: .collage, mediaIDs: ["a", "b"]))])
        var builds = 0
        v.mediaControlsProvider = { ctx in
            builds += 1
            let view = NSView(); view.identifier = NSUserInterfaceItemIdentifier("controls#\(ctx.blockID)")
            return view
        }
        v.layoutSubtreeIfNeeded()
        let g = v.boxes[0] as! MediaGroupBlockBox
        let controls = v.mediaControlsViews[g.id.rawValue]
        XCTAssertNotNil(controls, "a controls view was created for the group")
        XCTAssertEqual(controls?.frame, g.mediaAreaFrame, "controls cover the media area")
        XCTAssertTrue(v.mediaBlockHost.subviews.contains(controls!), "hosted in the media host (above tiles)")
        XCTAssertEqual(builds, 1)

        v.setMediaGroupKind(groupID: BlockID("c"), kind: .slideshow)   // signature change → rebuild
        v.layoutSubtreeIfNeeded()
        XCTAssertEqual(builds, 2, "kind change rebuilds the controls view")

        v.removeMediaBlock(id: BlockID("c"))
        v.layoutSubtreeIfNeeded()
        XCTAssertNil(v.mediaControlsViews["c"], "controls removed with the block")
    }

    func test_mediaAreaHeight_cappedAtMaxMediaHeight() {
        let v = canvas([.media(MediaBlock(id: BlockID("v"), kind: .video, mediaID: "m"))])
        let box = v.boxes[0] as! MediaBlockBox
        box.hostHeight = 500
        XCTAssertEqual(box.mediaAreaHeight, CanvasMetrics.maxMediaHeight, accuracy: 0.5, "a tall video is capped")
        box.hostHeight = 120
        XCTAssertEqual(box.mediaAreaHeight, 120, accuracy: 0.5, "a short video keeps its natural height")
    }

    func test_sliderAreaHeight_cappedAtMaxMediaHeight() {
        let v = canvas([.mediaGroup(MediaGroupBlock(id: BlockID("s"), kind: .slideshow, mediaIDs: ["a", "b"]))])
        let box = v.boxes[0] as! MediaGroupBlockBox
        box.hostHeight = 600
        XCTAssertEqual(box.mediaAreaHeight, CanvasMetrics.maxMediaHeight, accuracy: 0.5, "a tall slider is capped at 320")
    }

    func test_noControlsView_forFileMedia() {
        let v = canvas([.media(MediaBlock(id: BlockID("f"), kind: .file, mediaID: "m"))])
        v.mediaControlsProvider = { _ in NSView() }
        v.layoutSubtreeIfNeeded()
        XCTAssertNil(v.mediaControlsViews["f"], "file media has no overlay chrome")
    }
}
#endif
