import XCTest
import Cocoa
import WalletContext
import TelegramCore
import Postbox
@testable import WalletUI

private func repositoryRoot() -> URL {
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func source(_ path: String) throws -> String {
    return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
}

private func collapsed(_ text: String) -> String {
    return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}

private func submoduleStrings() throws -> [String: String] {
    let data = try Data(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/Telegram/Telegram-iOS/en.lproj/Localizable.strings"))
    return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
}

private let submoduleItemPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletTransactionItemComponent/Sources/WalletTransactionItemComponent.swift"
private let submoduleScreenPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletTransactionScreen/Sources/WalletTransactionScreen.swift"
private let submodulePeerSelectionPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletPeerSelectionScreen/Sources/WalletPeerSelectionScreen.swift"

private func submoduleCounterparty(_ address: String?, unknownAddress: String) -> String {
    guard let address, !address.isEmpty else {
        return unknownAddress
    }
    let edgeLength = 4
    guard address.count > edgeLength * 2 else {
        return address
    }
    return "\(address.prefix(edgeLength))…\(address.suffix(edgeLength))"
}

private func submoduleAddressTitle(address: String, domain: String?, unknownAddress: String) -> (title: String, chipAddress: String?) {
    if let domain = domain?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty {
        return (domain, nil)
    }
    let address = WalletContext.transferAddress(from: address, preserveBounce: true) ?? address
    let peerTitle = submoduleCounterparty(address, unknownAddress: unknownAddress)
    return (peerTitle, address.count > 12 ? address : nil)
}

private func submoduleAddressGroups(_ address: String) -> [String] {
    return [
        String(address.prefix(4)),
        String(address.dropFirst(4).prefix(2)) + String(address.suffix(6).prefix(2)),
        String(address.suffix(4))
    ]
}

private func submoduleChipFrame(index: Int) -> CGRect {
    return CGRect(x: CGFloat(index) * 52.0, y: 0.0, width: 48.0, height: 22.0)
}

private func submoduleChipScale(availableWidth: CGFloat) -> CGFloat {
    let contentSize = CGSize(width: 152.0, height: 22.0)
    return min(1.0, max(0.0, availableWidth) / contentSize.width)
}

private func submoduleDisplaysSendButton(counterpartyWidth: CGFloat, addressLineCount: Int) -> Bool {
    return counterpartyWidth > 0.0 && addressLineCount <= 3
}

private func submoduleShortAddress(_ address: String) -> String {
    let address = WalletContext.transferAddress(from: address, preserveBounce: true) ?? address
    guard address.count > 8 else {
        return address
    }
    return "\(address.prefix(4))…\(address.suffix(4))"
}

private func submodulePreviewPeer(recipient: String, recipientPeer: EnginePeer?) -> WalletContext.Transaction.Peer {
    if let recipientPeer {
        return .user(recipientPeer, address: recipient, domain: nil)
    } else {
        return .address(recipient, domain: nil)
    }
}

private func submoduleCounterpartyTitle(isPreview: Bool, isFinishedPreview: Bool, peer: WalletContext.Transaction.Peer, direction: WalletContext.Transaction.Direction, strings: [String: String]) -> String {
    if isPreview && !isFinishedPreview, case .address = peer {
        return strings["Wallet.Transaction.Address"]!
    }
    switch direction {
    case .incoming:
        return strings["Wallet.Transaction.Sender"]!
    case .outgoing:
        return strings["Wallet.Transaction.Recipient"]!
    case .unknown:
        return strings["Wallet.Transaction.Address"]!
    }
}

final class WalletTransactionAddressSubmoduleCompatibilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        applyMacEnglishStrings()
    }

    override func tearDown() {
        applyMacEnglishStrings([:])
        super.tearDown()
    }

    private func friendlyAddress(hashByte: UInt8, bounceable: Bool) -> String {
        var bytes: [UInt8] = [bounceable ? 0x11 : 0x51, 0x00]
        bytes += Array(repeating: hashByte, count: 32)
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0 ..< 8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        bytes += [UInt8(crc >> 8), UInt8(crc & 0xff)]
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }

    private func rawAddress(hashByte: UInt8) -> String {
        return "0:" + String(repeating: String(format: "%02x", hashByte), count: 32)
    }

    private func user(_ id: Int64, firstName: String) -> EnginePeer {
        return .user(TelegramUser(id: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: firstName, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
    }

    private var addresses: [String] {
        return [
            friendlyAddress(hashByte: 0x11, bounceable: false),
            friendlyAddress(hashByte: 0x2a, bounceable: true),
            rawAddress(hashByte: 0x5c),
            "UQAREREREREREREREREREREREREREREREREREREREREREbvW",
            "abcdefghijklm",
            "abcdefghijkl",
            "abcdefghi",
            "abcdefgh",
            "abc",
            ""
        ]
    }

    func testAddressTitleMatchesSubmodule() throws {
        let unknownAddress = try XCTUnwrap(submoduleStrings()["Wallet.Transaction.UnknownAddress"])
        for address in addresses {
            for domain in [nil, "durov.ton", "  ", " wallet.t.me "] as [String?] {
                let peer = WalletContext.Transaction.Peer.address(address, domain: domain)
                let actual = walletTransactionAddressTitle(address: address, domain: peer.domain)
                let submodule = submoduleAddressTitle(address: address, domain: domain, unknownAddress: unknownAddress)
                XCTAssertEqual(actual.title, submodule.title, "\(address) \(String(describing: domain))")
                XCTAssertEqual(actual.chipAddress, submodule.chipAddress, "\(address) \(String(describing: domain))")
            }
        }
        XCTAssertEqual(walletTransactionAddressTitle(address: rawAddress(hashByte: 0x5c), domain: nil).chipAddress, WalletContext.transferAddress(from: rawAddress(hashByte: 0x5c), preserveBounce: true))
    }

    func testSubmoduleAddressTitleIsStillTheCopiedOne() throws {
        let item = collapsed(try source(submoduleItemPath))
        for line in [
            "if let domain = domain?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty { peerTitle = domain } else { let address = WalletContext.transferAddress(from: address, preserveBounce: true) ?? address peerTitle = walletTransactionCounterparty(address, strings: component.strings) if address.count > 12 { titleAddress = address } }",
            "guard let address, !address.isEmpty else { return strings.Wallet_Transaction_UnknownAddress }",
            "let edgeLength = 4 guard address.count > edgeLength * 2 else { return address } return \"\\(address.prefix(edgeLength))…\\(address.suffix(edgeLength))\"",
            "self.title.view?.isHidden = titleAddress != nil"
        ] {
            XCTAssertTrue(item.contains(collapsed(line)), line)
        }
        let row = collapsed(try source("packages/WalletUI/Sources/WalletUI/WalletTransactionRowItem.swift"))
        for line in [
            "let addressTitle = walletTransactionAddressTitle(address: address, domain: transaction.peer.domain) titleText = addressTitle.title titleAddress = addressTitle.chipAddress",
            "titleView.isHidden = item.titleAddress != nil"
        ] {
            XCTAssertTrue(row.contains(collapsed(line)), line)
        }
    }

    func testAddressGroupsMatchSubmodule() {
        for address in addresses {
            XCTAssertEqual(walletTransactionAddressTitleGroups(address), submoduleAddressGroups(address), address)
        }
        XCTAssertEqual(walletTransactionAddressTitleGroups("UQAREREREREREREREREREREREREREREREREREREREREREbvW"), ["UQAR", "ERER", "EbvW"])
    }

    func testChipGeometryMatchesSubmodule() throws {
        for scale in [walletTransactionAddressTitleScale, 0.5, 0.25] as [CGFloat] {
            for index in 0 ..< 3 {
                let submodule = submoduleChipFrame(index: index)
                let actual = walletTransactionAddressTitleChipFrame(index: index, scale: scale)
                XCTAssertEqual(actual.minX, submodule.minX * scale, accuracy: 1e-9)
                XCTAssertEqual(actual.minY, submodule.minY * scale, accuracy: 1e-9)
                XCTAssertEqual(actual.width, submodule.width * scale, accuracy: 1e-9)
                XCTAssertEqual(actual.height, submodule.height * scale, accuracy: 1e-9)
            }
        }
        XCTAssertEqual(walletTransactionAddressTitleContentSize, NSMakeSize(152, 22))
        XCTAssertEqual(walletTransactionAddressTitleScale, 14.0 / 17.0, accuracy: 1e-12)
        for width in [0.0, 60.0, 100.0, 125.0, 152.0, 200.0, 400.0] as [CGFloat] {
            let actual = min(walletTransactionAddressTitleScale, width / walletTransactionAddressTitleContentSize.width)
            XCTAssertEqual(actual, min(walletTransactionAddressTitleScale, submoduleChipScale(availableWidth: width)), accuracy: 1e-12, "\(width)")
        }

        let item = collapsed(try source(submoduleItemPath))
        for line in [
            "let background = UIView(frame: CGRect(x: CGFloat(index) * 52.0, y: 0.0, width: 48.0, height: 22.0))",
            "background.layer.cornerRadius = 6.0",
            "label.font = Font.with(size: 16.0, design: .monospace, weight: .semibold)",
            "label.textAlignment = .center",
            "if index == 1 { let mask = CAGradientLayer() mask.frame = label.bounds mask.startPoint = CGPoint(x: 0.0, y: 0.5) mask.endPoint = CGPoint(x: 1.0, y: 0.5) mask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor] mask.locations = [0.0, 0.15, 0.5, 0.85, 1.0] label.layer.mask = mask }",
            "let contentSize = CGSize(width: 152.0, height: 22.0)",
            "let scale = min(1.0, max(0.0, availableSize.width) / contentSize.width)",
            "textColor: component.theme.list.itemPrimaryTextColor, backgroundColor: component.theme.list.itemSecondaryTextColor.withAlphaComponent(0.08)",
            "origin: CGPoint(x: textOriginX, y: 2.0 + floorToScreenPixels((titleSize.height - addressTitleSize.height) * 0.5))",
            "var contentHeight: CGFloat = 2.0 if let titleView = self.title.view {"
        ] {
            XCTAssertTrue(item.contains(collapsed(line)), line)
        }

        let actualSource = try source("packages/WalletUI/Sources/WalletUI/WalletTransactionRowItem.swift")
        let row = collapsed(actualSource)
        for line in [
            "chips[index].cornerRadius = 6 * scale",
            "chips[index].backgroundColor = theme.colors.grayText.withAlphaComponent(0.08).cgColor",
            "let font = NSFont.monospacedSystemFont(ofSize: 16 * addressTitleScale, weight: .semibold)",
            "let layout = TextViewLayout(.initialize(string: group, color: theme.colors.text, font: font), maximumNumberOfLines: 1)",
            "addressTitleScale = min(walletTransactionAddressTitleScale, titleWidth / walletTransactionAddressTitleContentSize.width)",
            "titleView.setFrameOrigin(NSMakePoint(textX, 7)) if let addressTitleView { addressTitleView.setFrameOrigin(NSMakePoint(textX, 7 + floorToScreenPixels(backingScaleFactor, (titleView.frame.height - addressTitleView.frame.height) / 2))) }"
        ] {
            XCTAssertTrue(row.contains(collapsed(line)), line)
        }
        XCTAssertFalse(actualSource.contains("fadeMask"), "The middle address chip is drawn without a fade")
    }

    func testSendButtonRuleMatchesSubmodule() throws {
        for width in [-10.0, 0.0, 0.5, 120.0, 400.0] as [CGFloat] {
            for lines in 0 ... 6 {
                XCTAssertEqual(walletDetailsAddressDisplaysAction(availableWidth: width, addressLineCount: lines), submoduleDisplaysSendButton(counterpartyWidth: width, addressLineCount: lines), "\(width) \(lines)")
            }
        }
        let screen = collapsed(try source(submoduleScreenPath))
        for line in [
            "let counterpartyWidth = max(0.0, context.availableSize.width - sendButton.size.width - context.component.spacing)",
            "displaysSendButton = counterpartyWidth > 0.0 && addressLayout.numberOfLines <= 3",
            "width: displaysSendButton ? counterpartyWidth : context.availableSize.width,",
            "if case .address = counterpartyContentId { counterpartyAddressText = addressText } else { counterpartyAddressText = nil }",
            "} else if let addressComponent, let address = transaction.peer.address { counterpartyContentId = .address(address)"
        ] {
            XCTAssertTrue(screen.contains(collapsed(line)), line)
        }
        let details = collapsed(try source("packages/WalletUI/Sources/WalletUI/WalletDetailsTableRowItem.swift"))
        for line in [
            "measured.displaysAction = true if measured.row.isAddress, measured.actionLayout != nil { measured.valueLayout.measure(width: max(0, availableWidth)) measured.displaysAction = walletDetailsAddressDisplaysAction(availableWidth: availableWidth, addressLineCount: measured.valueLayout.numberOfLines) if !measured.displaysAction { availableWidth += measured.actionSize.width + WalletDetailsTableRowItem.badgeSpacing } } measured.valueLayout.measure(width: max(0, availableWidth))",
            "if measured.actionLayout != nil, measured.displaysAction {",
            "actionView.isHidden = !measured.displaysAction",
            "let actionView = rowViews[index].actionView, !actionView.isHidden, NSPointInRect(point, actionView.frame)"
        ] {
            XCTAssertTrue(details.contains(collapsed(line)), line)
        }
        let controller = collapsed(try source("packages/WalletUI/Sources/WalletUI/WalletTransactionController.swift"))
        XCTAssertTrue(controller.contains(collapsed("} else if let row = addressRow(detailsData.counterpartyTitle, sendAction) {")))
    }

    func testPreviewRecipientMatchesSubmodule() {
        let jack = user(77, firstName: "Jack")
        for recipient in [friendlyAddress(hashByte: 0x11, bounceable: false), rawAddress(hashByte: 0x5c)] {
            for peer in [nil, jack] as [EnginePeer?] {
                XCTAssertEqual(walletPreviewTransactionPeer(recipient: recipient, recipientPeer: peer), submodulePreviewPeer(recipient: recipient, recipientPeer: peer))
            }
        }
    }

    func testCounterpartyTitleMatchesSubmodule() throws {
        let strings = try submoduleStrings()
        let jack = user(77, firstName: "Jack")
        let address = friendlyAddress(hashByte: 0x11, bounceable: false)
        let peers: [WalletContext.Transaction.Peer] = [
            .address(address, domain: nil),
            .address(address, domain: "durov.ton"),
            .user(jack, address: address, domain: nil),
            .onramp(address: address, domain: nil, providerName: "MoonPay"),
            .unsupported
        ]
        for peer in peers {
            for direction in [.incoming, .outgoing, .unknown] as [WalletContext.Transaction.Direction] {
                for (isPreview, isFinished) in [(false, false), (true, false), (true, true)] {
                    XCTAssertEqual(
                        walletTransactionCounterpartyTitle(isUnfinishedPreview: isPreview && !isFinished, peer: peer, direction: direction),
                        submoduleCounterpartyTitle(isPreview: isPreview, isFinishedPreview: isFinished, peer: peer, direction: direction, strings: strings),
                        "\(peer) \(direction) \(isPreview) \(isFinished)"
                    )
                }
            }
        }
        let screen = collapsed(try source(submoduleScreenPath))
        XCTAssertTrue(screen.contains(collapsed("if self.isPreview && !self.isFinishedPreview, case .address = transaction.peer { counterpartyTitle = environment.strings.Wallet_Transaction_Address } else {")))
        let controller = collapsed(try source("packages/WalletUI/Sources/WalletUI/WalletTransactionController.swift"))
        XCTAssertTrue(controller.contains(collapsed("let counterpartyTitle = walletTransactionCounterpartyTitle(isUnfinishedPreview: isPreview && !state.previewOperation.isTerminal, peer: transaction.peer, direction: displayedDirection)")))
    }

    func testCollectibleSuccessNamesTheRecipientLikeSubmodule() throws {
        for address in addresses {
            for name in [nil, "Jack"] as [String?] {
                XCTAssertEqual(walletCollectibleSuccessRecipient(peerName: name, address: address), name ?? submoduleShortAddress(address), "\(address) \(String(describing: name))")
            }
            XCTAssertEqual(walletTransactionShortAddress(address), submoduleShortAddress(address), address)
        }
        XCTAssertEqual(walletCollectibleSuccessRecipient(peerName: nil, address: rawAddress(hashByte: 0x5c)), submoduleShortAddress(rawAddress(hashByte: 0x5c)))
        XCTAssertFalse(walletCollectibleSuccessRecipient(peerName: nil, address: rawAddress(hashByte: 0x5c)).hasPrefix("0:"))

        let screen = collapsed(try source(submoduleScreenPath))
        for line in [
            "let recipientName = self.previewSource?.recipientPeer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? walletTransactionShortAddress(address)",
            "content: .emoji(name: \"Celebrate\", text: presentationData.strings.Wallet_Transfer_CollectibleSuccess(recipientName).string)",
            "let address = WalletContext.transferAddress(from: address, preserveBounce: true) ?? address guard address.count > 8 else { return address } return \"\\(address.prefix(4))…\\(address.suffix(4))\""
        ] {
            XCTAssertTrue(screen.contains(collapsed(line)), line)
        }
        let controllerSource = try source("packages/WalletUI/Sources/WalletUI/WalletTransactionController.swift")
        let controller = collapsed(controllerSource)
        for line in [
            "let recipient = walletCollectibleSuccessRecipient(peerName: subjectRecipientName, address: address)",
            "let recipientName = subjectRecipientName var session: PasscodeSession? = nil",
            "subjectRecipientName = recipientPeer.map { environment.peerTitle($0._asPeer(), compact: false) }"
        ] {
            XCTAssertTrue(controller.contains(collapsed(line)), line)
        }
        let send = collapsed(try source("packages/WalletUI/Sources/WalletUI/WalletSendController.swift"))
        XCTAssertTrue(send.contains(collapsed("let recipient = walletCollectibleSuccessRecipient(peerName: recipientName, address: recipientAddress)")))
    }

    func testPeerSelectionPassesThePeerLikeSubmodule() throws {
        let selection = collapsed(try source(submodulePeerSelectionPath))
        XCTAssertTrue(selection.contains(collapsed("address: recipient.address, recipientPeer: peer?.peer ?? selectedPeer, collectible: collectible,")))
        let recipient = collapsed(try source("packages/WalletUI/Sources/WalletUI/WalletRecipientController.swift"))
        for line in [
            "subject: .collectiblePreview(address: address, recipientPeer: recipientPeer, collectible: collectible)",
            "case let .collectiblePreview(address, collectible): openCollectiblePreview(address, owner?.peer, collectible)",
            "if let address { openCollectiblePreview(address, selectedPeer, collectible)"
        ] {
            XCTAssertTrue(recipient.contains(collapsed(line)), line)
        }
    }
}
