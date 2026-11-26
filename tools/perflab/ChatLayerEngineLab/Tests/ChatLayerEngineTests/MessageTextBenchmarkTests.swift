import Cocoa
import QuartzCore
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

private final class NativeMessageText {
    let view = View()
    var blocks: [TextView] = []

    func update(_ layout: FoldingTextLayout) {
        while blocks.count > layout.blocks.count { blocks.removeLast().removeFromSuperview() }
        while blocks.count < layout.blocks.count {
            let text = TextView()
            text.disableBackgroundDrawing = true
            blocks.append(text)
            view.addSubview(text)
        }
        var y: CGFloat = 0
        for (text, block) in zip(blocks, layout.blocks) {
            text.update(block.text)
            text.frame.origin = NSPoint(x: 0, y: y)
            y += text.frame.height
        }
        view.frame.size = layout.size
    }
}

final class MessageTextBenchmarkTests: XCTestCase {
    func testPreparationAndBindingCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_MESSAGE_TEXT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in message text cost breakdown") }
        TGUIKitTestBootstrap.install()
        let fixture = MessageTextTests()
        var results: [String: [Double]] = [:]
        var sink: CGFloat = 0
        for count in [1, 3, 12] {
            let source = fixture.layout((0..<count).map { "Paragraph \($0): a representative message with enough text to wrap across several lines and compare binding cost." })
            let presentation = ChatLayerMessageTextPresentation(source)
            let scene = ChatLayerSceneView(frame: .zero)
            let body = ChatLayerMessageTextNode(id: "body")
            try scene.root.setChildren([body])
            try body.update(presentation, messageId: 1, selectable: true)
            for batch in 0..<9 {
                for mode in batch % 2 == 0 ? [0, 1, 2] : [2, 1, 0] {
                    let start = CACurrentMediaTime()
                    for _ in 0..<10000 {
                        try autoreleasepool {
                            if mode == 0 {
                                sink += ChatLayerMessageTextPresentation(source).blocks.last?.frame.maxY ?? 0
                            } else if mode == 1 {
                                try body.update(presentation, messageId: 1, selectable: true)
                                scene.frame.size = body.frame.size
                                sink += scene.frame.height
                            } else {
                                sink += LegacyChatLayerMessageTextPresentation(source).blocks.last?.frame.maxY ?? 0
                            }
                        }
                    }
                    let name = "\(["prepare", "bind_prepared", "legacy_prepare"][mode])_\(count)_blocks"
                    results[name, default: []].append((CACurrentMediaTime() - start) * 1_000_000 / 10000)
                }
            }
        }
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches": results, "sink": sink], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-message-text-costs.json"))
    }

    func testConstructionAndBindingIncludingPresentationPreparation() throws {
        guard ProcessInfo.processInfo.environment["CHAT_MESSAGE_TEXT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in message text benchmark") }
        TGUIKitTestBootstrap.install()
        let fixture = MessageTextTests()
        var results: [String: [[Double]]] = [:]
        var sink: CGFloat = 0
        func record(_ name: String, count: Int, native: () throws -> Void, layers: () throws -> Void) rethrows {
            var batches = [[Double](), [Double]()]
            for _ in 0..<100 { try native(); try layers() }
            for batch in 0..<9 {
                for mode in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for _ in 0..<count {
                        try autoreleasepool {
                            if mode == 0 { try native() } else { try layers() }
                        }
                    }
                    batches[mode].append((CACurrentMediaTime() - start) * 1_000_000 / Double(count))
                }
            }
            results[name] = batches
        }
        for count in [1, 3, 12] {
            let source = fixture.layout((0..<count).map { "Paragraph \($0): a representative message with enough text to wrap across several lines and compare binding cost." })
            try record("construct_\(count)_blocks", count: 1000, native: {
                let row = NativeMessageText()
                row.update(source)
                sink += row.view.frame.height
            }, layers: {
                let scene = ChatLayerSceneView(frame: .zero)
                let body = ChatLayerMessageTextNode(id: "body")
                try scene.root.setChildren([body])
                try body.update(ChatLayerMessageTextPresentation(source), messageId: 1, selectable: true)
                scene.frame.size = body.frame.size
                sink += scene.frame.height
            })
            let native = NativeMessageText()
            let scene = ChatLayerSceneView(frame: .zero)
            let body = ChatLayerMessageTextNode(id: "body")
            try scene.root.setChildren([body])
            try record("rebind_\(count)_blocks", count: 3000, native: {
                native.update(source)
                sink += native.view.frame.height
            }, layers: {
                try body.update(ChatLayerMessageTextPresentation(source), messageId: 1, selectable: true)
                scene.frame.size = body.frame.size
                sink += scene.frame.height
            })
            let sources = [source, fixture.layout((0..<count).map { "Replacement \($0): different message text that changes wrapping and tests reused row content." }, width: 200)]
            var nativeIndex = 0, layerIndex = 0
            try record("rebind_changed_\(count)_blocks", count: 3000, native: {
                nativeIndex = 1 - nativeIndex
                native.update(sources[nativeIndex])
                sink += native.view.frame.height
            }, layers: {
                layerIndex = 1 - layerIndex
                try body.update(ChatLayerMessageTextPresentation(sources[layerIndex]), messageId: layerIndex, selectable: true)
                scene.frame.size = body.frame.size
                sink += scene.frame.height
            })
        }
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_native_then_layer": results, "sink": sink], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-message-text-benchmark.json"))
    }
}
