final class TrimTests: Case {
    override func setUpWithError() throws { try super.setUpWithError(); Backend.reset(); try Data("original".utf8).write(to: URL(fileURLWithPath: source)) }
    func trim(_ start: Double = 0.2, _ end: Double = 1.2) -> Bool { trimOpusFile(source, to: output, start: start, end: end) }
    func testNormalTrimProducesOutput() { XCTAssertTrue(trim()); XCTAssertNotNil(contents(output)); XCTAssertEqual(contents(source), Data("original".utf8)) }
    func testNegativeStartRejectedBeforeDecode() { XCTAssertFalse(trim(-1, 1)); XCTAssertEqual(Backend.readers, 0); XCTAssertNil(contents(output)) }
    func testSubSampleIntervalRejectedWithoutOutput() { XCTAssertFalse(trim(0, 0.000001)); XCTAssertNil(contents(output)) }
    func testInfiniteEndRejectedWithoutTrap() throws { if baseline { throw XCTSkip("Original unchecked Int conversion traps") }; XCTAssertFalse(trim(0, .infinity)); XCTAssertEqual(Backend.readers, 0) }
    func testOversizedEndRejectedWithoutTrap() throws { if baseline { throw XCTSkip("Original unchecked Int conversion traps") }; XCTAssertFalse(trim(0, .greatestFiniteMagnitude)); XCTAssertEqual(Backend.readers, 0) }
    func testNaNIntervalRejected() { XCTAssertFalse(trim(.nan, 1)); XCTAssertNil(contents(output)) }
    func testEmptyIntervalRejected() { XCTAssertFalse(trim(1, 1)); XCTAssertNil(contents(output)) }
    func testInputCannotBeOutput() { XCTAssertFalse(trimOpusFile(source, to: source, start: 0, end: 1)); XCTAssertEqual(contents(source), Data("original".utf8)) }
    func testExistingOutputPreserved() throws { try Data("keep".utf8).write(to: URL(fileURLWithPath: output)); XCTAssertFalse(trim()); XCTAssertEqual(contents(output), Data("keep".utf8)) }
    func testUnavailableDecoderDoesNotCreateOutput() { Backend.unavailable = true; XCTAssertFalse(trim()); XCTAssertNil(contents(output)) }
    func testWriterInitializationFailureCleansOutput() { Backend.beginOK = false; XCTAssertFalse(trim()); XCTAssertNil(contents(output)) }
    func testFrameFailureRejectsAndCleansOutput() { Backend.frameOK = false; XCTAssertFalse(trim()); XCTAssertNil(contents(output)) }
    func testPartialFrameFailureRejectsOutput() { Backend.frameOK = false; XCTAssertFalse(trim(0, 0.01)); XCTAssertNil(contents(output)) }
    func testFinalizeFailureRejectsAndCleansOutput() { Backend.finalizeOK = false; XCTAssertFalse(trim()); XCTAssertNil(contents(output)) }
    func testDecoderErrorAfterPartialOutputRejectsAndCleans() { Backend.readErrorAt = 7680; XCTAssertFalse(trim(0, 1)); XCTAssertNil(contents(output)) }
    func testPrematureEOFRejectsPartialSelection() { Backend.samples = 12000; XCTAssertFalse(trim(0, 1)); XCTAssertNil(contents(output)) }
    func testRangePastEOFLeavesNoEmptyOutput() { XCTAssertFalse(trim(3, 4)); XCTAssertNil(contents(output)) }
    func testDiskBytesMustMatchWriterMemory() { Backend.damageOutput = true; XCTAssertFalse(trim()); XCTAssertNil(contents(output)) }
    func testMissingOutputParentDoesNotReportSuccess() { let invalid = directory.appendingPathComponent("missing/out.ogg").path; XCTAssertFalse(trimOpusFile(source, to: invalid, start: 0, end: 1)); XCTAssertNil(contents(invalid)) }
}
final class StoreTests: Case {
    override func setUpWithError() throws { try super.setUpWithError(); Backend.reset() }
    func context() -> Context { let c = Context(source); c.dataItem.appendData(Data("original".utf8)); c.encoderState = ["saved": 1]; return c }
    func testRejectedWriterPreservesOriginalFileAndObjects() { let c = context(), item = c.dataItem, writer = c.oggWriter; Backend.appendOK = false; XCTAssertFalse(c.replaceStore(with: Data("replacement".utf8))); XCTAssertEqual(contents(source), Data("original".utf8)); XCTAssertTrue(c.dataItem === item); XCTAssertTrue(c.oggWriter === writer); XCTAssertNotNil(c.encoderState); XCTAssertEqual(c.liveUploading, 42) }
    func testEmptyReplacementPreservesOriginal() { let c = context(); XCTAssertFalse(c.replaceStore(with: Data())); XCTAssertEqual(contents(source), Data("original".utf8)); XCTAssertNotNil(c.encoderState) }
    func testAcceptedReplacementKeepsDiskAndMemoryIdentical() { let c = context(); let bytes = Data("replacement".utf8); XCTAssertTrue(c.replaceStore(with: bytes)); XCTAssertEqual(contents(source), bytes); XCTAssertEqual(c.dataItem.data(), bytes); XCTAssertNil(c.encoderState); XCTAssertNil(c.liveUploading) }
    func testFailedFileCommitPreservesWriterAndMemory() throws { let folder = directory.appendingPathComponent("target"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); try Data("keep".utf8).write(to: folder.appendingPathComponent("keep")); let c = Context(folder.path), writer = c.oggWriter, item = c.dataItem; c.encoderState = ["saved":1]; XCTAssertFalse(c.replaceStore(with: Data("replacement".utf8))); XCTAssertTrue(c.oggWriter === writer); XCTAssertTrue(c.dataItem === item); XCTAssertNotNil(c.encoderState); XCTAssertEqual(contents(folder.appendingPathComponent("keep").path), Data("keep".utf8)) }
    func testAppendAfterReplacementDoesNotDuplicateSeedData() { let c = context(); XCTAssertTrue(c.replaceStore(with: Data("replacement".utf8))); c.dataItem.appendData(Data("next".utf8)); XCTAssertEqual(contents(source), Data("replacementnext".utf8)); XCTAssertEqual(c.dataItem.data(), Data("replacementnext".utf8)) }
    func testMissingParentCommitRejected() { let c = Context(directory.appendingPathComponent("missing/out").path); let item = c.dataItem; XCTAssertFalse(c.replaceStore(with: Data("replacement".utf8))); XCTAssertTrue(c.dataItem === item) }
    func testApplyTrimRejectsRunningRecorder() { let c = context(); c.paused = false; XCTAssertFalse(c.applyTrim(0..<1)); XCTAssertEqual(contents(source), Data("original".utf8)); XCTAssertTrue(c.waveformTrims.isEmpty) }
    func testApplyTrimRejectsEmptyDuration() { let c = context(); Backend.duration = 0; XCTAssertFalse(c.applyTrim(0..<1)) }
    func testApplyTrimRejectsNegativeRange() { let c = context(); XCTAssertFalse(c.applyTrim(-1..<1)); XCTAssertEqual(contents(source), Data("original".utf8)) }
    func testApplyTrimRejectsOutOfBoundsRange() { let c = context(); XCTAssertFalse(c.applyTrim(1..<3)); XCTAssertEqual(contents(source), Data("original".utf8)) }
    func testApplyTrimRejectsEmptyRange() { let c = context(); XCTAssertFalse(c.applyTrim(1..<1)); XCTAssertEqual(contents(source), Data("original".utf8)) }
    func testFullRangeIsNoOp() { let c = context(); XCTAssertTrue(c.applyTrim(0..<2)); XCTAssertEqual(contents(source), Data("original".utf8)); XCTAssertTrue(c.waveformTrims.isEmpty) }
    func testFailedTrimPreservesWaveformAndStatus() { let c = context(); Backend.appendOK = false; XCTAssertFalse(c.applyTrim(0..<1)); XCTAssertEqual(contents(source), Data("original".utf8)); XCTAssertTrue(c.waveformTrims.isEmpty); XCTAssertTrue(c.recordingState.values.isEmpty) }
    func testAcceptedTrimUpdatesWaveformAndStatus() { let c = context(); XCTAssertTrue(c.applyTrim(0..<1)); XCTAssertEqual(c.waveformTrims.count, 1); XCTAssertEqual(c.waveformTrims.first?.0, 0); XCTAssertEqual(c.waveformTrims.first?.1, 0.5); XCTAssertEqual(c.recordingState.values, [2]) }
}
