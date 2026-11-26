final class StoryMetadataManagerTests:XCTestCase {
    private func keys(_ ids:[Int32])->[StoryKey] { ids.map { .init(peerId:10,id:$0) } }
    func testFactoryReentryWithSameWindowStartsOneRequest() {
        let c=Context(); let m=StoryMetadataRefreshContext(now:{c.now})
        m.update(keys([1])) { peer,ids in
            m.update(self.keys([1])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) }
            return c.engine.messages.refreshStoryViews(peerId:peer,ids:ids)
        }
        XCTAssertEqual(c.requests.count,1); m.dispose()
    }
    func testFactoryDisposalDoesNotStartRequest() {
        let c=Context(); let m=StoryMetadataRefreshContext(now:{c.now})
        m.update(keys([1])) { peer,ids in m.dispose(); return c.engine.messages.refreshStoryViews(peerId:peer,ids:ids) }
        XCTAssertTrue(c.requests.isEmpty)
    }
    func testStartReentryCannotOverwriteReplacementSubscription() {
        let c=Context(); let m=StoryMetadataRefreshContext(now:{c.now}); var reentered=false
        c.engine.messages.onStart={ _ in if !reentered { reentered=true; m.update(self.keys([2])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) } } }
        m.update(keys([1])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) }
        XCTAssertEqual(c.requests.count,2); XCTAssertTrue(c.requests[0].canceled); XCTAssertFalse(c.requests[1].canceled); c.engine.messages.onStart=nil; m.dispose()
    }
    func testDisposalDuringStartStopsOtherPeerBatches() {
        let c=Context(); let m=StoryMetadataRefreshContext(now:{c.now}); c.engine.messages.onStart={ _ in m.dispose() }
        m.update([.init(peerId:10,id:1),.init(peerId:20,id:1)]) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) }
        XCTAssertEqual(c.requests.count,1); XCTAssertTrue(c.requests[0].canceled); c.engine.messages.onStart=nil
    }
    func testCanceledCompletionCannotAgeReplacement() {
        let c=Context(); let m=StoryMetadataRefreshContext(now:{c.now})
        m.update(keys([1])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) }; let obsolete=c.requests[0].subscriber
        m.update(keys([2])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) }; obsolete?.putCompletion(); c.now=20
        m.update(keys([2])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) }; XCTAssertEqual(c.requests.count,2); m.dispose()
    }
    func testReentryDuringCancellationWinsOverOldWindow() {
        let c=Context(); let m=StoryMetadataRefreshContext(now:{c.now}); var reentered=false
        m.update(keys([1])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) }
        c.engine.messages.onDispose={ _ in if !reentered { reentered=true; m.update(self.keys([3])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) } } }
        m.update(keys([2])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) }
        XCTAssertEqual(c.requests.map { $0.ids },[[1],[3]]); c.engine.messages.onDispose=nil; m.dispose()
    }
    func testCompletionDisposalReentryRespectsCooldown() {
        let c=Context(); let m=StoryMetadataRefreshContext(now:{c.now})
        m.update(keys([1])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) }
        c.engine.messages.onDispose={ _ in m.update(self.keys([1])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) } }
        c.requests[0].finish(); XCTAssertEqual(c.requests.count,1); c.engine.messages.onDispose=nil; m.dispose()
    }
    func testDisposedManagerRejectsFurtherUpdates() {
        let c=Context(); let m=StoryMetadataRefreshContext(); m.dispose()
        m.update(keys([1])) { c.engine.messages.refreshStoryViews(peerId:$0,ids:$1) }; XCTAssertTrue(c.requests.isEmpty)
    }
}
