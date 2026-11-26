import Cocoa
import XCTest
import TGUIKit

final class IconIdentityTests: XCTestCase {
    override func setUp() {
        TGUIKitTestBootstrap.install()
        theme = FixtureTheme()
        ChatInterfaceHooks.shared.fileCalls = 0
    }
    private func identity(_ title: String = "Alpha", color: Int32 = 1, file: Int64? = nil, general: Bool = false, account: FixtureAccount = .shared, tint: NSColor = .gray, custom: NSColor = .blue) -> ChatTopicIconIdentity {
        ChatTopicIconIdentity(account: account, fileId: file, title: title, iconColor: color, isGeneral: general, generalColor: tint, customColor: custom)
    }
    private func row() -> CandidateTopicView { CandidateTopicView(frame: NSRect(x: 0, y: 0, width: 180, height: 25)) }
    private func vertical(_ info: FixtureTopicInfo?, thread: Int64 = 5, context: FixtureContext = FixtureContext()) -> FixtureVerticalItem {
        FixtureVerticalItem(context: context, item: FixtureTopicTab(uniqueId: thread, item: info.map { FixtureThreadItem(threadData: FixtureThreadData(info: $0)) }))
    }
    func testIdentityUsesRenderedInitialColorAccountAndSourceKind() {
        XCTAssertEqual(identity("Alpha"), identity("Another"))
        XCTAssertNotEqual(identity("Alpha"), identity("Beta"))
        XCTAssertNotEqual(identity(color: 1), identity(color: 2))
        XCTAssertNotEqual(identity(), identity(account: FixtureAccount()))
        XCTAssertNotEqual(identity(color: 42), identity(file: 42))
        XCTAssertEqual(identity(file: 0), identity(file: nil))
        XCTAssertEqual(identity("👨‍👩‍👧‍👦 Family"), identity("👨‍👩‍👧‍👦 Other"))
        XCTAssertNotEqual(identity("👨‍👩‍👧‍👦 Family"), identity("👩‍👩‍👦 Family"))
    }
    func testCustomAndGeneralKeysIgnoreUnrenderedMetadata() {
        XCTAssertEqual(identity("Alpha", color: 1, file: 42), identity("Beta", color: 2, file: 42, general: true, tint: .red))
        XCTAssertNotEqual(identity(file: 42), identity(file: 43))
        XCTAssertNotEqual(identity(file: 42), identity(file: 42, custom: .red))
        XCTAssertEqual(identity("Alpha", color: 1, general: true), identity("Beta", color: 2, general: true, custom: .red))
        XCTAssertNotEqual(identity(general: true), identity(general: true, tint: .red))
    }
    func testReplyGeneratedIconRefreshesOnRenameAndRecolor() throws {
        let view = row()
        view.update(item: TopicReplyItemLayout("Alpha", generated: true, iconColor: 1), animated: false)
        let first = try XCTUnwrap(view.iconsForTesting.first)
        XCTAssertEqual(first.resourceKey, "generated-A-1")
        first.isPlayable = true
        view.update(item: TopicReplyItemLayout("Beta", generated: true, iconColor: 1), animated: false)
        let renamed = try XCTUnwrap(view.iconsForTesting.first)
        XCTAssertFalse(renamed === first)
        XCTAssertEqual(renamed.resourceKey, "generated-B-1")
        view.update(item: TopicReplyItemLayout("Beta", generated: true, iconColor: 2), animated: false)
        XCTAssertEqual(view.iconsForTesting.first?.resourceKey, "generated-B-2")
        XCTAssertNil(first.superlayer)
        XCTAssertFalse(first.isPlayable)
    }
    func testReplyKeepsSameInitialButSeparatesCustomAndAccountChanges() throws {
        let view = row()
        view.update(item: TopicReplyItemLayout("Alpha", generated: true, iconColor: 42), animated: false)
        let first = try XCTUnwrap(view.iconsForTesting.first)
        view.update(item: TopicReplyItemLayout("Another", generated: true, iconColor: 42), animated: false)
        XCTAssertTrue(view.iconsForTesting.first === first)
        view.update(item: TopicReplyItemLayout("Another", id: 42), animated: false)
        let custom = try XCTUnwrap(view.iconsForTesting.first)
        XCTAssertFalse(custom === first)
        XCTAssertNil(custom.resourceKey)
        view.update(item: TopicReplyItemLayout("Another", id: 42, context: FixtureContext(account: FixtureAccount())), animated: false)
        XCTAssertFalse(view.iconsForTesting.first === custom)
    }
    func testReplyGeneralTintAndCustomTintRefresh() throws {
        let view = row()
        view.update(item: TopicReplyItemLayout("General", generated: true, isGeneral: true), animated: false)
        let first = try XCTUnwrap(view.iconsForTesting.first)
        view.update(item: TopicReplyItemLayout("Renamed", generated: true, iconColor: 9, isGeneral: true), animated: false)
        XCTAssertTrue(view.iconsForTesting.first === first)
        view.update(item: TopicReplyItemLayout("General", generated: true, isGeneral: true, generalColor: .red), animated: false)
        XCTAssertFalse(view.iconsForTesting.first === first)
        view.update(item: TopicReplyItemLayout("Custom", id: 42), animated: false)
        let custom = try XCTUnwrap(view.iconsForTesting.first)
        theme.colors.accent = .red
        view.update(item: TopicReplyItemLayout("Custom", id: 42), animated: false)
        XCTAssertFalse(view.iconsForTesting.first === custom)
    }
    func testSeparatorRefreshesGeneratedMetadataAndSwitchesToCustom() throws {
        let view = CandidateSeparator(frame: .zero)
        let context = FixtureContext()
        view.bind(.init(title: "Alpha", iconColor: 1, icon: nil), threadId: 5, context: context)
        let first = try XCTUnwrap(view.iconView)
        view.bind(.init(title: "Beta", iconColor: 1, icon: nil), threadId: 5, context: context)
        XCTAssertFalse(view.iconView === first)
        XCTAssertEqual(view.iconView?.animateLayer.resourceKey, "generated-B-1")
        view.bind(.init(title: "Beta", iconColor: 2, icon: nil), threadId: 5, context: context)
        XCTAssertEqual(view.iconView?.animateLayer.resourceKey, "generated-B-2")
        view.bind(.init(title: "Beta", iconColor: 2, icon: 42), threadId: 5, context: context)
        XCTAssertEqual(view.iconView?.animateLayer.fileId, 42)
        XCTAssertNil(view.iconView?.animateLayer.resourceKey)
        view.bind(.init(title: "Beta", iconColor: 2, icon: nil), threadId: 42, context: context)
        XCTAssertEqual(view.iconView?.animateLayer.resourceKey, "generated-B-2")
    }
    func testVerticalRefreshesMetadataAndAvoidsThreadIdCollision() throws {
        let view = CandidateVertical(frame: .zero)
        view.bind(vertical(.init(title: "Alpha", iconColor: 1, icon: nil)), fileId: 0)
        let first = try XCTUnwrap(view.animatedView)
        view.bind(vertical(.init(title: "Beta", iconColor: 2, icon: nil)), fileId: 0)
        XCTAssertFalse(view.animatedView === first)
        XCTAssertEqual(view.animatedView?.animateLayer.resourceKey, "generated-B-2")
        view.bind(vertical(.init(title: "Beta", iconColor: 2, icon: 42)), fileId: 42)
        XCTAssertEqual(view.animatedView?.animateLayer.fileId, 42)
        XCTAssertNil(view.animatedView?.animateLayer.resourceKey)
        view.bind(vertical(.init(title: "Beta", iconColor: 2, icon: nil), thread: 42), fileId: 0)
        XCTAssertEqual(view.animatedView?.animateLayer.resourceKey, "generated-B-2")
    }
    func testVerticalMissingMetadataBecomesGeneratedAndChangesThread() throws {
        let view = CandidateVertical(frame: .zero)
        view.bind(vertical(nil), fileId: 0)
        let first = try XCTUnwrap(view.animatedView)
        XCTAssertNil(first.animateLayer.resourceKey)
        view.bind(vertical(nil, thread: 6), fileId: 0)
        XCTAssertEqual(view.animatedView?.animateLayer.fileId, 6)
        view.bind(vertical(.init(title: "", iconColor: 0, icon: nil), thread: 6), fileId: 0)
        XCTAssertEqual(view.animatedView?.animateLayer.resourceKey, "generated--0")
        XCTAssertFalse(view.animatedView === first)
    }
    func testCustomTintInvalidatesBothBindingsWithoutChangingMetadata() throws {
        let separator = CandidateSeparator(frame: .zero)
        let verticalView = CandidateVertical(frame: .zero)
        let info = FixtureTopicInfo(title: "Custom", iconColor: 1, icon: 42)
        separator.bind(info, threadId: 5, context: FixtureContext())
        verticalView.bind(vertical(info), fileId: 42)
        let first = try XCTUnwrap(separator.iconView)
        let other = try XCTUnwrap(verticalView.animatedView)
        theme.colors.accent = .red
        separator.bind(info, threadId: 5, context: FixtureContext())
        verticalView.bind(vertical(info), fileId: 42)
        XCTAssertFalse(separator.iconView === first)
        XCTAssertFalse(verticalView.animatedView === other)
    }
    func testUnchangedBindingsDoNotRegenerateFilesOrViews() throws {
        let separator = CandidateSeparator(frame: .zero)
        let verticalView = CandidateVertical(frame: .zero)
        let context = FixtureContext()
        separator.bind(.init(title: "Alpha", iconColor: 1, icon: nil), threadId: 5, context: context)
        verticalView.bind(vertical(.init(title: "Alpha", iconColor: 1, icon: nil)), fileId: 0)
        let separatorIcon = try XCTUnwrap(separator.iconView)
        let verticalIcon = try XCTUnwrap(verticalView.animatedView)
        XCTAssertEqual(ChatInterfaceHooks.shared.fileCalls, 2)
        for _ in 0..<100 {
            separator.bind(.init(title: "Another title", iconColor: 1, icon: nil), threadId: 5, context: context)
            verticalView.bind(vertical(.init(title: "Another title", iconColor: 1, icon: nil)), fileId: 0)
        }
        XCTAssertTrue(separator.iconView === separatorIcon)
        XCTAssertTrue(verticalView.animatedView === verticalIcon)
        XCTAssertEqual(ChatInterfaceHooks.shared.fileCalls, 2)
    }
    func testSeparatorAndVerticalGeneralThemeAndAccountChanges() throws {
        let separator = CandidateSeparator(frame: .zero)
        let verticalView = CandidateVertical(frame: .zero)
        let info = FixtureTopicInfo(title: "General", iconColor: 1, icon: nil)
        separator.bind(info, threadId: 1, context: FixtureContext())
        verticalView.bind(vertical(info, thread: 1), fileId: 0)
        let first = try XCTUnwrap(separator.iconView)
        let other = try XCTUnwrap(verticalView.animatedView)
        theme.chatList.badgeMutedBackgroundColor = .red
        separator.bind(info, threadId: 1, context: FixtureContext())
        verticalView.bind(vertical(info, thread: 1), fileId: 0)
        XCTAssertFalse(separator.iconView === first)
        XCTAssertFalse(verticalView.animatedView === other)
        let themed = try XCTUnwrap(separator.iconView)
        let themedOther = try XCTUnwrap(verticalView.animatedView)
        let next = FixtureContext(account: FixtureAccount())
        separator.bind(info, threadId: 1, context: next)
        verticalView.bind(vertical(info, thread: 1, context: next), fileId: 0)
        XCTAssertFalse(separator.iconView === themed)
        XCTAssertFalse(verticalView.animatedView === themedOther)
    }
}
