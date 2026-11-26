import XCTest
import Cocoa
import TGUIKit
import SwiftSignalKit
@testable import InputDataUI

private final class MessageIdentifier: InputDataIdentifier {
    let message: Int

    init(_ message: Int) {
        self.message = message
        super.init("message")
    }

    override func isEqual(to other: InputDataIdentifier) -> Bool {
        return (other as? MessageIdentifier)?.message == message
    }
}

private final class FormattingResponder: InputDataTextFormatting {
    var actions: [String] = []
    func makeBold() { actions.append("bold") }
    func makeItalic() { actions.append("italic") }
    func makeMonospace() { actions.append("monospace") }
    func makeUrl() { actions.append("link") }
}

final class InputDataUITests: XCTestCase {
    private func installHooks(detect: @escaping (String) -> String? = { _ in nil },
                              submit: @escaping (NSEvent) -> Bool = { _ in false },
                              loadingRow: @escaping (NSSize, AnyHashable) -> TableRowItem = { _, _ in fatalError("Unexpected loading row") }) {
        InputDataUIHooks.install(InputDataUIHooks(
            checkSendingAbility: submit,
            mainWindow: { fatalError("Unexpected window access") },
            showAlert: { _, _ in XCTFail("Unexpected alert") },
            showModalText: { _, _ in XCTFail("Unexpected modal text") },
            detectExternalURL: detect,
            makeLoadingRow: loadingRow
        ))
    }

    func testIdentifierSubclassEqualityAndDictionaryLookup() {
        let first = MessageIdentifier(1)
        let same = MessageIdentifier(1)
        let other = MessageIdentifier(2)
        XCTAssertEqual(first, same)
        XCTAssertNotEqual(first, other)
        let values: [InputDataIdentifier: InputDataValue] = [first: .string("first"), other: .string("second")]
        XCTAssertEqual(values[same], .string("first"))
        XCTAssertEqual(values[other], .string("second"))
    }

    func testEntryOrderingAndSearchIdentityRemainUnchanged() {
        let identifier = InputDataIdentifier("search")
        let entry = InputDataEntry.search(sectionId: 1, index: 3, value: .string("query"), identifier: identifier, update: { _ in })
        XCTAssertEqual(entry.stableId, .custom(identifier))
        XCTAssertEqual(entry.index, 100003)
        XCTAssertLessThan(InputDataEntry.sectionId(0, type: .normal), entry)
        XCTAssertLessThan(entry, InputDataEntry.sectionId(1, type: .normal))
    }

    func testComparableIndexUsesProvidedOrdering() {
        func index(_ value: Int) -> InputDataComparableIndex {
            InputDataComparableIndex(data: value, compare: { ($0 as! Int) > ($1 as! Int) }, equatable: { ($0 as! Int) == ($1 as! Int) })
        }
        XCTAssertLessThan(index(2), index(1))
        XCTAssertEqual(index(2), index(2))
    }

    func testValuesPreserveAttributedTextAndSelectorEquality() {
        let text = NSAttributedString(string: "hello", attributes: [.underlineStyle: 1])
        let value = InputDataValue.attributedString(text)
        XCTAssertEqual(value.stringValue, "hello")
        XCTAssertEqual(value.attributedString, text)
        XCTAssertEqual(ValuesSelectorValue(localized: "One", value: 1), ValuesSelectorValue(localized: "Uno", value: 1))
        XCTAssertNotEqual(InputDataValue.date(1, 2, 2026), .date(2, 2, 2026))
    }

    func testFormattingDispatchAndUnsupportedResponder() {
        let responder = FormattingResponder()
        for action in InputDataTextFormattingAction.allCases {
            action.apply(to: responder)
            action.apply(to: NSObject())
            action.apply(to: nil)
        }
        XCTAssertEqual(responder.actions, ["bold", "italic", "monospace", "link"])
    }

    func testLoadingEntryPreservesFactorySizeAndIdentity() {
        let size = NSSize(width: 300, height: 200)
        let row = TableRowItem(size)
        var calls = 0
        installHooks(loadingRow: { receivedSize, receivedId in
            XCTAssertEqual(receivedSize, size)
            XCTAssertEqual(receivedId, AnyHashable(InputDataEntryId.loading))
            calls += 1
            return row
        })
        let arguments = InputDataArguments(select: { _ in XCTFail("Unexpected selection") }, dataUpdated: {})
        XCTAssertTrue(InputDataEntry.loading.item(arguments: arguments, initialSize: size) === row)
        XCTAssertEqual(calls, 1)
    }

    func testSubmissionPreferenceIsEvaluatedForEachEvent() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        var enabled = false
        var calls = 0
        installHooks(submit: { received in
            XCTAssertTrue(received === event)
            calls += 1
            return enabled
        })
        XCTAssertFalse(InputDataUIHooks.shared.checkSendingAbility(event))
        enabled = true
        XCTAssertTrue(InputDataUIHooks.shared.checkSendingAbility(event))
        XCTAssertEqual(calls, 2)
    }

    func testURLNormalizationPreservesPathAndQueryCase() {
        XCTAssertEqual(caseNormalizedURL("  HTTPS://EXAMPLE.COM/SomePath?Key=Value  "), "https://example.com/SomePath?Key=Value")
        XCTAssertEqual(caseNormalizedURL("EXAMPLE.COM/SomePath"), "example.com/SomePath")
    }

    func testURLDetectionTriesOriginalBeforeNormalized() {
        var candidates: [String] = []
        installHooks(detect: { candidate in
            candidates.append(candidate)
            return candidate == "https://example.com/Path" ? candidate : nil
        })
        XCTAssertEqual(inputDataExternalURL("HTTPS://EXAMPLE.COM/Path"), "https://example.com/Path")
        XCTAssertEqual(candidates, ["HTTPS://EXAMPLE.COM/Path", "https://example.com/Path"])
    }

    func testURLDetectionStopsAtFirstMatchAndDoesNotRetryIdenticalInput() {
        var candidates: [String] = []
        installHooks(detect: { candidates.append($0); return "resolved" })
        XCTAssertEqual(inputDataExternalURL("HTTPS://EXAMPLE.COM"), "resolved")
        XCTAssertEqual(candidates.count, 1)
        candidates.removeAll()
        installHooks(detect: { candidates.append($0); return nil })
        XCTAssertNil(inputDataExternalURL("https://example.com"))
        XCTAssertEqual(candidates, ["https://example.com"])
    }

    func testDeferredValidationInvokesCompletionWithoutLoadingView() {
        let controller = InputDataController(dataSignal: .never(), title: "Validation")
        var complete: ((InputDataValidation) -> Void)?
        var calls = 0
        controller.proccessValidation(.fail(.doSomething(next: { complete = $0 })))
        XCTAssertNotNil(complete)
        XCTAssertEqual(calls, 0)
        complete?(.success(.custom { calls += 1 }))
        XCTAssertEqual(calls, 1)
        controller.proccessValidation(.none)
        controller.proccessValidation(.fail(.none))
        XCTAssertEqual(calls, 1)
    }
}
