import XCTest
import AppKit
@testable import WalletUI

final class WalletAmountDirectionSubmoduleCompatibilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func collapsed(_ text: String) -> String {
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func block(_ text: String, from start: String, to end: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let lower = try XCTUnwrap(text.range(of: start), start, file: file, line: line)
        let upper = try XCTUnwrap(text.range(of: end, range: lower.upperBound ..< text.endIndex), end, file: file, line: line)
        return String(text[lower.lowerBound ..< upper.lowerBound])
    }

    private var submoduleField: String {
        get throws { try source("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletSendScreen/Sources/WalletSendAmountField.swift") }
    }

    private var actualRow: String {
        get throws { try source("packages/WalletUI/Sources/WalletUI/WalletAmountRowItem.swift") }
    }

    private func configure(_ view: NSTextView) {
        view.textContainer?.lineFragmentPadding = 0
        view.font = .systemFont(ofSize: 34)
        view.alignment = .left
    }

    private func textStartX(_ view: NSTextView) -> CGFloat {
        let layoutManager = view.layoutManager!
        let textContainer = view.textContainer!
        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.usedRect(for: textContainer).minX
    }

    func testParagraphStyleMatchesSubmodule() throws {
        let style = collapsed(try block(try submoduleField, from: "static let paragraphStyle: NSParagraphStyle = {", to: "}()"))
        XCTAssertTrue(style.contains("style.alignment = .left"))
        XCTAssertTrue(style.contains("style.baseWritingDirection = .leftToRight"))
        XCTAssertEqual(walletAmountParagraphStyle.alignment, .left)
        XCTAssertEqual(walletAmountParagraphStyle.baseWritingDirection, .leftToRight)
    }

    func testEmptyFieldKeepsTheCaretLeftAfterRightToLeftDirection() {
        let plain = NSTextView(frame: NSMakeRect(0, 0, 300, 50))
        configure(plain)
        plain.makeBaseWritingDirectionRightToLeft(nil)
        XCTAssertGreaterThan(textStartX(plain), 100)

        let field = WalletAmountTextView(frame: NSMakeRect(0, 0, 300, 50))
        configure(field)
        field.makeBaseWritingDirectionRightToLeft(nil)
        XCTAssertEqual(textStartX(field), 0)
        XCTAssertEqual((field.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.baseWritingDirection, .leftToRight)
        XCTAssertEqual((field.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment, .left)

        field.insertText("5", replacementRange: field.selectedRange())
        XCTAssertEqual(textStartX(field), 0)
        XCTAssertEqual((field.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.baseWritingDirection, .leftToRight)
    }

    func testTypingAttributesAlwaysKeepTheLeftToRightStyle() {
        let field = WalletAmountTextView(frame: NSMakeRect(0, 0, 300, 50))
        let rightToLeft = NSMutableParagraphStyle()
        rightToLeft.alignment = .right
        rightToLeft.baseWritingDirection = .rightToLeft
        field.typingAttributes = [.font: NSFont.systemFont(ofSize: 34), .paragraphStyle: rightToLeft]
        let style = field.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(style?.baseWritingDirection, .leftToRight)
        XCTAssertEqual(style?.alignment, .left)
        XCTAssertEqual(field.typingAttributes[.font] as? NSFont, NSFont.systemFont(ofSize: 34))
    }

    func testAmountAndPlaceholderUseTheStyleLikeSubmodule() throws {
        let field = collapsed(try submoduleField)
        for line in [
            "attributedText.addAttribute(.paragraphStyle, value: WalletSendAmountTextLayout.paragraphStyle, range: NSRange(location: 0, length: attributedText.length))",
            "self.textField.attributedPlaceholder = self.amountTextLayout(\"0\").attributedText",
            "self.defaultTextAttributes[.paragraphStyle] = WalletSendAmountTextLayout.paragraphStyle",
            "override func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) { super.setBaseWritingDirection(.leftToRight, for: range) }"
        ] {
            XCTAssertTrue(field.contains(collapsed(line)), line)
        }

        let row = try actualRow
        let attributed = collapsed(try block(row, from: "private func amountAttributedText(", to: "private func groupingOffsets("))
        XCTAssertTrue(attributed.contains("result.addAttribute(.paragraphStyle, value: walletAmountParagraphStyle, range: NSMakeRange(0, result.length)) return result"))
        let placeholder = collapsed(try block(row, from: "private func applyPlaceholderPresentation()", to: "private func updateTypingAttributes()"))
        XCTAssertTrue(placeholder.contains("placeholderInputView.setAttributedText(amountAttributedText(\"0\", integralFont: mainFont, color: amountTextColor)"))
        let typing = collapsed(try block(row, from: "public override var typingAttributes: [NSAttributedString.Key: Any] {", to: "public override func readSelection("))
        XCTAssertTrue(typing.contains("attributes[.paragraphStyle] = walletAmountParagraphStyle super.typingAttributes = attributes"))
        let collapsedRow = collapsed(row)
        XCTAssertEqual(collapsedRow.components(separatedBy: "private let placeholderInputView = WalletAmountTextView()").count - 1, 1)
        XCTAssertEqual(collapsedRow.components(separatedBy: "private let inputView = WalletAmountTextView()").count - 1, 1)
    }
}
