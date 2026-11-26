import XCTest
import AppKit
import TGUIKit
import TelegramTheme
import Postbox
import TelegramCore
@testable import ChatListUI

final class ChatListStateProjectionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func base() -> PeerListState {
        return PeerListState(proxySettings: .defaultSettings, connectionStatus: .online(proxyAddress: nil), splitState: .dual, searchState: .None, peer: nil, forumPeer: nil, mode: .plain, activities: .init(activities: [:]), appear: .normal, controllerAppear: .normal, hiddenItems: .default, selectedForum: nil, stories: nil, isContacts: false, filterData: FilterData(requestTimestamp: 10), presentation: theme, privacy: nil, displaySavedAsTopics: false)
    }

    func testFieldsTheChatListDoesNotReadDoNotRebuildIt() {
        let state = base()
        var other = state
        other.connectionStatus = .waitingForNetwork
        other.searchQuery = "query"
        other.searchState = .Focus
        other.hasDownloads = true
        other.isContacts = true
        other.filterData = FilterData(filter: state.filterData.filter, tabs: state.filterData.tabs, sidebar: true, showTags: state.filterData.showTags, request: .Initial(100, nil), badges: .init(total: 42, filters: []), requestTimestamp: state.filterData.requestTimestamp, isTop: false)
        XCTAssertNotEqual(state, other)
        XCTAssertEqual(ChatListStateProjection(state), ChatListStateProjection(other))
    }

    func testFieldsTheChatListReadsStillRebuildIt() {
        let state = base()
        var appear = state
        appear.appear = .short
        XCTAssertNotEqual(ChatListStateProjection(state), ChatListStateProjection(appear))

        var split = state
        split.splitState = .single
        XCTAssertNotEqual(ChatListStateProjection(state), ChatListStateProjection(split))

        var tags = state
        tags.filterData = FilterData(showTags: true, requestTimestamp: 10)
        XCTAssertNotEqual(ChatListStateProjection(state), ChatListStateProjection(tags))

        var request = state
        request.filterData = FilterData(requestTimestamp: 11)
        XCTAssertNotEqual(ChatListStateProjection(state), ChatListStateProjection(request))

        var controllerAppear = state
        controllerAppear.controllerAppear = .short
        XCTAssertNotEqual(ChatListStateProjection(state), ChatListStateProjection(controllerAppear))
    }

    func testVoiceChatActivitiesDoNotRebuildTheList() {
        let state = base()
        var speaking = state
        let space = PeerActivitySpace(peerId: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(5)), category: .voiceChat)
        speaking.activities = .init(activities: [space: []])
        XCTAssertEqual(ChatListStateProjection(state), ChatListStateProjection(speaking))

        var typing = state
        typing.activities = .init(activities: [PeerActivitySpace(peerId: space.peerId, category: .global): []])
        XCTAssertNotEqual(ChatListStateProjection(state), ChatListStateProjection(typing))
    }
}
