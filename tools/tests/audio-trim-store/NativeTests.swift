final class NativeTests: Case {
    func makeRecording() throws -> Context {
        let c = Context(source)
        XCTAssertTrue(c.oggWriter.begin(with: c.dataItem))
        var samples = (0..<960).map { Int16(sin(Double($0) * 0.0576) * 6000) }
        for _ in 0..<100 { XCTAssertTrue(samples.withUnsafeMutableBytes { c.oggWriter.writeFrame($0.baseAddress!.assumingMemoryBound(to: UInt8.self), frameByteCount: UInt($0.count)) }) }
        XCTAssertTrue(c.oggWriter.writeFrame(nil, frameByteCount: 0))
        c.encoderState = c.oggWriter.pause()
        return c
    }
    func decodedCount(_ path: String) -> Int {
        guard let reader = OggOpusReader(path: path) else { XCTFail("Unreadable Opus file"); return -1 }
        var samples = [Int16](repeating: 0, count: 7680), count = 0
        while true { let n = samples.withUnsafeMutableBytes { reader.read($0.baseAddress!, bufSize: 7680) }; if n <= 0 { XCTAssertEqual(n, 0); break }; count += Int(n) }
        return count
    }
    func testRealTrimDecodesRequestedSampleCount() throws { _ = try makeRecording(); XCTAssertTrue(trimOpusFile(source, to: output, start: 0.25, end: 1.25)); XCTAssertEqual(decodedCount(output), 48000) }
    func testRealPartialFrameTrimDecodesRequestedSamples() throws { _ = try makeRecording(); XCTAssertTrue(trimOpusFile(source, to: output, start: 0.201, end: 0.732)); XCTAssertEqual(decodedCount(output), 25488) }
    func testRealStoreReplacementMatchesMemoryAndDuration() throws { let c = try makeRecording(); XCTAssertTrue(c.applyTrim(0.25..<1.25)); XCTAssertEqual(decodedCount(source), 48000); XCTAssertEqual(contents(source), c.dataItem.data()); XCTAssertEqual(c.oggWriter.encodedDuration(), 1, accuracy: 0.001); XCTAssertEqual(c.recordingState.values.count, 1) }
    func testRealRecordingCanAppendAfterReplacement() throws { let c = try makeRecording(); XCTAssertTrue(c.applyTrim(0.25..<1.25)); var samples = [Int16](repeating: 1000, count: 960); for _ in 0..<10 { XCTAssertTrue(samples.withUnsafeMutableBytes { c.oggWriter.writeFrame($0.baseAddress!.assumingMemoryBound(to: UInt8.self), frameByteCount: UInt($0.count)) }) }; XCTAssertTrue(c.oggWriter.writeFrame(nil, frameByteCount: 0)); XCTAssertEqual(c.oggWriter.encodedDuration(), 1.2, accuracy: 0.001); XCTAssertEqual(contents(source), c.dataItem.data()); XCTAssertEqual(decodedCount(source), 57600) }
    func testRealTrimBeyondEOFRejectedAndCleaned() throws { _ = try makeRecording(); let original = contents(source); XCTAssertFalse(trimOpusFile(source, to: output, start: 1, end: 3)); XCTAssertNil(contents(output)); XCTAssertEqual(contents(source), original) }
    func testRealTrimDoesNotAppendToExistingOutput() throws { _ = try makeRecording(); try Data("keep".utf8).write(to: URL(fileURLWithPath: output)); XCTAssertFalse(trimOpusFile(source, to: output, start: 0, end: 1)); XCTAssertEqual(contents(output), Data("keep".utf8)) }
    func testRealReplacementCommitFailurePreservesSourceState() throws { let c = try makeRecording(); XCTAssertTrue(trimOpusFile(source, to: output, start: 0, end: 1)); let bytes = try XCTUnwrap(contents(output)); let item = c.dataItem, writer = c.oggWriter; let backup = directory.appendingPathComponent("backup.ogg"); try FileManager.default.moveItem(atPath: source, toPath: backup.path); try FileManager.default.createDirectory(atPath: source, withIntermediateDirectories: true); try Data("keep".utf8).write(to: URL(fileURLWithPath: source).appendingPathComponent("keep")); XCTAssertFalse(c.replaceStore(with: bytes)); XCTAssertTrue(c.dataItem === item); XCTAssertTrue(c.oggWriter === writer); XCTAssertNotNil(c.encoderState); XCTAssertEqual(decodedCount(backup.path), 96000) }
}

final class ContinuityTests: Case {
    func pcm(_ count: Int, offset: Int = 0) -> [Int16] { (offset..<offset+count).map { Int16(sin(Double($0) * 0.0576) * 6000) } }
    func feed(_ samples: [Int16], to writer: TGOggOpusWriter, chunk: Int = 960) {
        var index = 0
        while index < samples.count {
            var piece = Array(samples[index..<min(samples.count, index+chunk)])
            XCTAssertTrue(piece.withUnsafeMutableBytes { writer.writeFrame($0.baseAddress!.assumingMemoryBound(to: UInt8.self), frameByteCount: UInt($0.count)) })
            index += piece.count
        }
    }
    func decode(_ path: String) -> [Int16] {
        guard let reader = OggOpusReader(path: path) else { XCTFail("Unreadable stream"); return [] }
        var result: [Int16] = [], buffer = [Int16](repeating: 0, count: 7680)
        while true {
            let count = buffer.withUnsafeMutableBytes { reader.read($0.baseAddress!, bufSize: 7680) }
            if count <= 0 { XCTAssertEqual(count, 0); break }
            result += buffer.prefix(Int(count))
        }
        return result
    }
    func compareAudio(_ lhs: String, _ rhs: String) {
        guard let leftData=contents(lhs),let rightData=contents(rhs),let left=OggOpusReader.extractFrames(leftData),let right=OggOpusReader.extractFrames(rightData) else { XCTFail("Cannot read encoded packets");return }
        XCTAssertEqual(left.count,right.count)
        for (index,pair) in zip(left,right).enumerated() { XCTAssertTrue(pair.0.data == pair.1.data,"Encoded audio packet \(index) differs") }
        XCTAssertEqual(decode(lhs).count,decode(rhs).count)
    }
    func writer(_ path: String) -> (TGOggOpusWriter, DataItem) { let item = DataItem(path: path), writer = TGOggOpusWriter(); XCTAssertTrue(writer.begin(with: item)); return (writer,item) }
    func finish(_ writer: TGOggOpusWriter) { XCTAssertTrue(writer.writeFrame(nil, frameByteCount: 0)) }
    func testSingleSampleSurvivesFinalization() { let (w,_) = writer(source); feed(pcm(1), to:w); finish(w); XCTAssertEqual(decode(source).count,1) }
    func testExactFrameAndDelayBoundariesKeepAllSamples() {
        for count in [311,312,313,648,649,959,960,961,1920,1921,48000] {
            let path = directory.appendingPathComponent("\(count).ogg").path
            let (w,_) = writer(path); feed(pcm(count), to:w); finish(w)
            XCTAssertEqual(decode(path).count,count,"sample count \(count)")
            XCTAssertEqual(w.encodedDuration(),Double(count)/48000,accuracy:0.000001)
        }
    }
    func testIrregularInputChunksMatchContinuousPCM() {
        let samples = pcm(48000)
        let (a,_) = writer(source); feed(samples,to:a); finish(a)
        let (b,_) = writer(output); feed(samples,to:b,chunk:113); finish(b)
        compareAudio(source,output)
    }
    func testSameWriterPauseResumePreservesExactDecodedAudio() {
        let samples = pcm(96000)
        let (a,_) = writer(source); feed(samples,to:a); finish(a)
        let (b,item) = writer(output); feed(Array(samples.prefix(48000)),to:b)
        let state = b.pause(); XCTAssertTrue(b.resume(with:item,encoderState:state))
        feed(Array(samples.dropFirst(48000)),to:b); finish(b)
        compareAudio(source,output)
    }
    func testJSONSnapshotRestoresIntoNewWriterWithPartialFrame() throws {
        let samples = pcm(48000)
        let (a,_) = writer(source); feed(samples,to:a); finish(a)
        let (b,item) = writer(output); feed(Array(samples.prefix(12413)),to:b)
        let json = try JSONSerialization.data(withJSONObject:b.pause())
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with:json) as? [AnyHashable:Any])
        let c = TGOggOpusWriter(); XCTAssertTrue(c.resume(with:item,encoderState:state))
        feed(Array(samples.dropFirst(12413)),to:c); finish(c)
        compareAudio(source,output)
    }
    func testRepeatedPauseResumeKeepsSequenceAndDuration() {
        let (w,item) = writer(source)
        for i in 0..<10 { feed(pcm(1007,offset:i*1007),to:w); let state = w.pause(); XCTAssertTrue(w.resume(with:item,encoderState:state)) }
        finish(w); XCTAssertEqual(decode(source).count,10070)
    }
    func testTrimPausedRecordingIncludesEncoderDelayTail() {
        let c=Context(source);XCTAssertTrue(c.oggWriter.begin(with:c.dataItem));feed(pcm(96000),to:c.oggWriter);c.encoderState=c.oggWriter.pause()
        XCTAssertTrue(c.applyTrim(0.25..<2));XCTAssertEqual(decode(source).count,84000);XCTAssertEqual(c.oggWriter.encodedDuration(),1.75,accuracy:0.000001)
    }
    func testTrimPausedPartialFrameRetainsAllSelectedSamples() {
        let c=Context(source);XCTAssertTrue(c.oggWriter.begin(with:c.dataItem));feed(pcm(96413),to:c.oggWriter);c.encoderState=c.oggWriter.pause()
        let duration=c.oggWriter.encodedDuration();XCTAssertTrue(c.applyTrim(0.25..<duration));XCTAssertEqual(decode(source).count,84413)
    }
    func testTrimAtExactDurationDoesNotLoseSampleToFloatingPointRounding() {
        let c=Context(source);XCTAssertTrue(c.oggWriter.begin(with:c.dataItem));feed(pcm(96001),to:c.oggWriter);c.encoderState=c.oggWriter.pause()
        XCTAssertTrue(c.applyTrim(0.25..<c.oggWriter.encodedDuration()));XCTAssertEqual(decode(source).count,84001)
    }
    func testRejectedPausedTrimCanResumeOriginalRecording() {
        let c=Context(source);XCTAssertTrue(c.oggWriter.begin(with:c.dataItem));feed(pcm(48000),to:c.oggWriter);c.encoderState=c.oggWriter.pause();let bytes=c.dataItem.data()
        XCTAssertFalse(c.applyTrim(-1..<1));XCTAssertEqual(c.dataItem.data(),bytes);XCTAssertTrue(c.oggWriter.resume(with:c.dataItem,encoderState:c.encoderState!));feed(pcm(960),to:c.oggWriter);finish(c.oggWriter);XCTAssertEqual(decode(source).count,48960)
    }
    func testFinalizationIsIdempotent() { let (w,item)=writer(source);feed(pcm(960),to:w);finish(w);let bytes=item.data();finish(w);XCTAssertEqual(item.data(),bytes);XCTAssertEqual(decode(source).count,960) }
    func testCannotAppendPCMDirectlyToFinalizedWriter() { let (w,_)=writer(source);feed(pcm(960),to:w);finish(w);var next=pcm(960);XCTAssertFalse(next.withUnsafeMutableBytes { w.writeFrame($0.baseAddress!.assumingMemoryBound(to:UInt8.self),frameByteCount:UInt($0.count)) }) }
    func testInvalidFrameByteCountRejectedWithoutChangingDuration() { let (w,_)=writer(source);var bytes=[UInt8](repeating:0,count:1922);XCTAssertFalse(bytes.withUnsafeMutableBufferPointer { w.writeFrame($0.baseAddress!,frameByteCount:1922) });XCTAssertFalse(bytes.withUnsafeMutableBufferPointer { w.writeFrame($0.baseAddress!,frameByteCount:1) });XCTAssertEqual(w.encodedDuration(),0) }
    func testMalformedAppendSourceRejectedWithoutMutation() throws { if baseline { throw XCTSkip("Original native parser can clear an uninitialized stream") };let item=DataItem(path:source);item.appendData(Data("malformed".utf8));let original=item.data();let w=TGOggOpusWriter();XCTAssertFalse(w.beginAppend(with:item));XCTAssertEqual(item.data(),original);XCTAssertEqual(contents(source),original) }
    func testPreparingAppendDoesNotRewriteSource() { let (w,item)=writer(source);feed(pcm(48000),to:w);finish(w);let bytes=item.data();let next=TGOggOpusWriter();XCTAssertTrue(next.beginAppend(with:item));XCTAssertEqual(item.data(),bytes);XCTAssertEqual(contents(source),bytes);XCTAssertEqual(next.encodedDuration(),1,accuracy:0.000001) }
    func testAppendedStreamHasExactTotalSampleCount() { let (w,item)=writer(source);feed(pcm(12413),to:w);finish(w);let next=TGOggOpusWriter();XCTAssertTrue(next.beginAppend(with:item));feed(pcm(2387,offset:12413),to:next);finish(next);XCTAssertEqual(decode(source).count,14800);XCTAssertEqual(next.encodedDuration(),Double(14800)/48000,accuracy:0.000001) }
    func testAppendCanBePausedBeforeFirstNewFrame() throws { let (w,item)=writer(source);feed(pcm(12413),to:w);finish(w);let next=TGOggOpusWriter();XCTAssertTrue(next.beginAppend(with:item));let json=try JSONSerialization.data(withJSONObject:next.pause());let state=try XCTUnwrap(JSONSerialization.jsonObject(with:json) as? [AnyHashable:Any]);let restored=TGOggOpusWriter();XCTAssertTrue(restored.resume(with:item,encoderState:state));feed(pcm(2387,offset:12413),to:restored);finish(restored);XCTAssertEqual(decode(source).count,14800) }
    func testFailedAppendFileReplacementPreservesOriginalMemory() throws { let (w,item)=writer(source);feed(pcm(48000),to:w);finish(w);let bytes=item.data();let next=TGOggOpusWriter();XCTAssertTrue(next.beginAppend(with:item));let backup=directory.appendingPathComponent("backup");try FileManager.default.moveItem(atPath:source,toPath:backup.path);try FileManager.default.createDirectory(atPath:source,withIntermediateDirectories:true);try Data("keep".utf8).write(to:URL(fileURLWithPath:source).appendingPathComponent("keep"));var samples=pcm(960);XCTAssertFalse(samples.withUnsafeMutableBytes { next.writeFrame($0.baseAddress!.assumingMemoryBound(to:UInt8.self),frameByteCount:UInt($0.count)) });XCTAssertEqual(item.data(),bytes);XCTAssertEqual(contents(backup.path),bytes);XCTAssertEqual(next.encodedDuration(),1,accuracy:0.000001) }
    func testLegacySnapshotRecoversSavedAudioWithoutInvalidPages() {
        let (w,item)=writer(source);feed(pcm(48000),to:w);finish(w);var state=w.pause()
        for key in ["encoderData","encoderDigest","opusVersion","wordSize","pageno","bos","pcmData","finished","dataDigest"] { state.removeValue(forKey:key) }
        let next=TGOggOpusWriter();XCTAssertTrue(next.resume(with:item,encoderState:state));feed(pcm(960),to:next);finish(next);XCTAssertEqual(decode(source).count,48960)
    }
    func testSnapshotFromDifferentArchitectureRejected() { let (w,item)=writer(source);feed(pcm(960),to:w);var state=w.pause();state["architecture"]="different";let next=TGOggOpusWriter();XCTAssertFalse(next.resume(with:item,encoderState:state)) }
    func testCorruptedEncoderSnapshotRejected() { let (w,item)=writer(source);feed(pcm(960),to:w);var state=w.pause();state["encoderData"]=Data(repeating:0,count:20).base64EncodedString();let next=TGOggOpusWriter();XCTAssertFalse(next.resume(with:item,encoderState:state)) }
    func testChangedFileRejectsOldSnapshot() { let (w,item)=writer(source);feed(pcm(960),to:w);let state=w.pause();item.appendData(Data([1,2,3]));let next=TGOggOpusWriter();XCTAssertFalse(next.resume(with:item,encoderState:state)) }
    func testMalformedSnapshotFieldRejected() throws { if baseline { throw XCTSkip("Original dictionary decoding does not validate value types") };let (w,item)=writer(source);feed(pcm(960),to:w);var state=w.pause();state["rate"]=["invalid"];let next=TGOggOpusWriter();XCTAssertFalse(next.resume(with:item,encoderState:state)) }
    func testLiveRecordingFlushesAtOneSecondIntervals() { let (w,item)=writer(source);let initial=item.data().count;feed(pcm(48960),to:w);XCTAssertGreaterThan(item.data().count,initial) }
}
