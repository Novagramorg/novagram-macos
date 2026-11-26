import Cocoa
import XCTest
import QuartzCore
@testable import FoldingBlocksHarness

final class FoldingPlaybackBenchmarkTests: XCTestCase {
    func testBlockCosts() throws {
        guard ProcessInfo.processInfo.environment["FOLDING_PLAYBACK_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in folding playback benchmark") }
        TGUIKitTestBootstrap.install()
        let fixtures = FoldingPlaybackTests()
        var results: [String: Any] = [:]
        var sink = 0
        func measure(_ name: String, count: Int, old: () -> Void, current: () -> Void) {
            var batches = [[Double](), [Double]()]
            for _ in 0..<100 { old(); current() }
            for batch in 0..<9 {
                for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for _ in 0..<count {
                        autoreleasepool {
                            if variant == 0 { old() } else { current() }
                        }
                    }
                    batches[variant].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                }
            }
            results[name] = batches
        }
        for quoted in [false, true] {
            let kind = quoted ? "quote" : "plain"
            for media in [0, 1] {
                let layout = fixtures.layout(quoted: quoted, media: media)
                measure("construct_\(kind)_media_\(media)", count: 500, old: {
                    let block = makeLegacyBlock(quoted: quoted)
                    block.update(layout)
                    sink += block.textView.textLayout!.lines.count
                }, current: {
                    let block = makeCurrentBlock(quoted: quoted)
                    block.update(layout)
                    sink += block.textView.textLayout!.lines.count
                })
                let oldBlock = makeLegacyBlock(quoted: quoted), newBlock = makeCurrentBlock(quoted: quoted)
                measure("rebind_\(kind)_media_\(media)", count: 1000, old: { oldBlock.update(layout) }, current: { newBlock.update(layout) })
            }
            for count in [40, 150] {
                for mixed in [false, true] {
                    let oldHost = FoldingPlaybackTests.Host(), newHost = FoldingPlaybackTests.Host()
                    var oldBlocks: [BlockHarness] = [], newBlocks: [BlockHarness] = []
                    for index in 0..<count {
                        let value = fixtures.layout(quoted: quoted, media: mixed && index % 4 == 0 ? 1 : 0)
                        let a = makeLegacyBlock(quoted: quoted), b = makeCurrentBlock(quoted: quoted)
                        a.update(value); b.update(value)
                        oldHost.attach(a); newHost.attach(b)
                        oldBlocks.append(a); newBlocks.append(b)
                    }
                    PlaybackCounters.calls = 0
                    oldHost.post()
                    XCTAssertEqual(PlaybackCounters.calls, count)
                    PlaybackCounters.calls = 0
                    newHost.post()
                    XCTAssertEqual(PlaybackCounters.calls, mixed ? (count + 3) / 4 : 0)
                    measure("scroll_\(kind)_\(count)_mixed_\(mixed)", count: 1000, old: { oldHost.post() }, current: { newHost.post() })
                    for block in oldBlocks + newBlocks { block.view.removeFromSuperview(); block.updateListeners() }
                }
            }
        }
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_original_then_current": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/folding-playback-benchmark.json"))
    }
}
