import Cocoa
import XCTest
import TGUIKit

final class IconIdentityBenchmarkTests: XCTestCase {
    func testBindingCost() throws {
        guard ProcessInfo.processInfo.environment["TOPIC_IDENTITY_TIMING"] != nil else { throw XCTSkip("Opt-in icon identity benchmark") }
        TGUIKitTestBootstrap.install()
        theme = FixtureTheme()
        let reverse = ProcessInfo.processInfo.environment["TOPIC_REVERSE"] != nil
        let context = FixtureContext()
        let info = FixtureTopicInfo(title: "Alpha", iconColor: 1, icon: nil)
        let items = (0..<400).map { TopicReplyItemLayout("Topic \($0)") }
        var samples: [String: [Double]] = [:]
        for batch in -1..<9 {
            for native in ((batch % 2 == 0) != reverse ? [true, false] : [false, true]) {
                for changingThread in [false, true] {
                    for kind in ["separator", "vertical"] {
                        autoreleasepool {
                            let before = ChatInterfaceHooks.shared.fileCalls
                            let bind: (Int64) -> Void
                            if kind == "separator" {
                                if native {
                                    let view = NativeSeparator(frame: .zero)
                                    bind = { view.bind(info, threadId: $0, context: context) }
                                } else {
                                    let view = CandidateSeparator(frame: .zero)
                                    bind = { view.bind(info, threadId: $0, context: context) }
                                }
                            } else {
                                if native {
                                    let view = NativeVertical(frame: .zero)
                                    bind = { view.bind(FixtureVerticalItem(context: context, item: FixtureTopicTab(uniqueId: $0, item: FixtureThreadItem(threadData: FixtureThreadData(info: info)))), fileId: 0) }
                                } else {
                                    let view = CandidateVertical(frame: .zero)
                                    bind = { view.bind(FixtureVerticalItem(context: context, item: FixtureTopicTab(uniqueId: $0, item: FixtureThreadItem(threadData: FixtureThreadData(info: info)))), fileId: 0) }
                                }
                            }
                            bind(5)
                            let count = 1000
                            let start = CACurrentMediaTime()
                            for index in 0..<count { bind(changingThread ? Int64(index % 2 + 6) : 5) }
                            let elapsed = (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
                            let key = "\(kind)-\(changingThread ? "same-icon-different-thread" : "unchanged")-\(native ? "before" : "after")"
                            if batch >= 0 { samples[key, default: []].append(elapsed) }
                            XCTAssertEqual(ChatInterfaceHooks.shared.fileCalls - before, native && changingThread ? count + 1 : 1)
                            withExtendedLifetime(bind) { CATransaction.flush() }
                        }
                    }
                }
                autoreleasepool {
                    let bind: (TopicReplyItemLayout) -> Void
                    if native {
                        let view = PreIdentityTopicView(frame: .zero)
                        bind = { view.update(item: $0, animated: false) }
                    } else {
                        let view = CandidateTopicView(frame: .zero)
                        bind = { view.update(item: $0, animated: false) }
                    }
                    bind(items[0])
                    let count = 4000
                    let start = CACurrentMediaTime()
                    for index in 0..<count { bind(items[index % items.count]) }
                    let elapsed = (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
                    if batch >= 0 { samples["reply-unchanged-\(native ? "before" : "after")", default: []].append(elapsed) }
                    withExtendedLifetime(bind) { CATransaction.flush() }
                }
            }
        }
        let payload: [String: Any] = ["identity_value_stride_bytes": MemoryLayout<ChatTopicIconIdentity>.stride, "microseconds_per_bind": samples, "reverse": reverse, "scope": "Production topic binding branches and complete reply view; premeasured layouts and static image stand-ins, no account or decoder work."]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: URL(fileURLWithPath: "/tmp/topic-identity-timing\(reverse ? "-reverse" : "").json"))
    }
}
