import XCTest
@testable import WalletEngineFFI

@available(macOS 10.15, *)
final class WalletEncryptedCommentRecipientTests: XCTestCase {
    private static let recipientWords = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    private static let senderWords = "legal winner thank year wave sausage worth useful legal winner thank yellow"
    private static let currentKeyHolderWords = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong"
    private static let onChainPublicKeyHex = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
    private static let undeployedAccountStates = ["nonexist", "uninit"]

    func testActiveRecipientIgnoresSuppliedKeyAndUsesOnChainKey() async throws {
        let platform = MemoryPlatformHost()
        let sender = try await importWallet(words: Self.senderWords, recordId: "sender-wallet", platform: platform)
        let recipient = try await importWallet(words: Self.recipientWords, recordId: "recipient-wallet", platform: platform)
        let onChainKey = try XCTUnwrap(Data(hexString: Self.onChainPublicKeyHex))
        XCTAssertNotEqual(recipient.publicKey, onChainKey)

        for suppliedKey in [recipient.publicKey, Data(repeating: 0x33, count: 32)] {
            let chain = RecipientChainHost(accountState: "active", onChainPublicKey: onChainKey)
            let client = try makeClient(wallet: sender, canSign: false, chain: chain, platform: platform)

            let resolved = try await client.resolveEncryptedCommentRecipient(
                request: EncryptedCommentRecipientRequest(recipient: recipient.address, recipientPublicKey: suppliedKey)
            )

            XCTAssertEqual(resolved.hexString, onChainKey.hexString)
            XCTAssertEqual(chain.calls, try recipientLookup(recipient.address, readsOnChainKey: true))
        }
        XCTAssertTrue(platform.secretReasons.isEmpty)
    }

    func testUndeployedRecipientUsesSuppliedKeyAfterReadingAccountState() async throws {
        let platform = MemoryPlatformHost()
        let sender = try await importWallet(words: Self.senderWords, recordId: "sender-wallet", platform: platform)
        let recipient = try await importWallet(words: Self.recipientWords, recordId: "recipient-wallet", platform: platform)
        let onChainKey = try XCTUnwrap(Data(hexString: Self.onChainPublicKeyHex))

        for accountState in Self.undeployedAccountStates {
            let chain = RecipientChainHost(accountState: accountState, onChainPublicKey: onChainKey)
            let client = try makeClient(wallet: sender, canSign: false, chain: chain, platform: platform)

            let resolved = try await client.resolveEncryptedCommentRecipient(
                request: EncryptedCommentRecipientRequest(recipient: recipient.address, recipientPublicKey: recipient.publicKey)
            )

            XCTAssertEqual(resolved.hexString, recipient.publicKey.hexString, accountState)
            XCTAssertEqual(chain.calls, try recipientLookup(recipient.address, readsOnChainKey: false), accountState)
        }
        XCTAssertTrue(platform.secretReasons.isEmpty)
    }

    func testUndeployedRecipientRejectsSuppliedKeyThatDoesNotDeriveItsAddress() async throws {
        let platform = MemoryPlatformHost()
        let sender = try await importWallet(words: Self.senderWords, recordId: "sender-wallet", platform: platform)
        let recipient = try await importWallet(words: Self.recipientWords, recordId: "recipient-wallet", platform: platform)
        let onChainKey = try XCTUnwrap(Data(hexString: Self.onChainPublicKeyHex))
        XCTAssertNotEqual(sender.publicKey, recipient.publicKey)

        for accountState in Self.undeployedAccountStates {
            let chain = RecipientChainHost(accountState: accountState, onChainPublicKey: onChainKey)
            let client = try makeClient(wallet: sender, canSign: false, chain: chain, platform: platform)

            do {
                let resolved = try await client.resolveEncryptedCommentRecipient(
                    request: EncryptedCommentRecipientRequest(recipient: recipient.address, recipientPublicKey: sender.publicKey)
                )
                XCTFail("\(accountState): a key of another wallet resolved to \(resolved.hexString)")
            } catch let WalletClientError.EncryptedCommentUnavailable(diagnostic) {
                XCTAssertFalse(diagnostic.isEmpty, accountState)
            }
            XCTAssertEqual(chain.calls, try recipientLookup(recipient.address, readsOnChainKey: false), accountState)

            let resolved = try await client.resolveEncryptedCommentRecipient(
                request: EncryptedCommentRecipientRequest(recipient: recipient.address, recipientPublicKey: recipient.publicKey)
            )
            XCTAssertEqual(resolved.hexString, recipient.publicKey.hexString, accountState)
            XCTAssertEqual(chain.calls.count, 2, accountState)
        }
        XCTAssertTrue(platform.secretReasons.isEmpty)
    }

    func testActiveRecipientWithoutSuppliedKeyUsesOnChainKey() async throws {
        let platform = MemoryPlatformHost()
        let sender = try await importWallet(words: Self.senderWords, recordId: "sender-wallet", platform: platform)
        let recipient = try await importWallet(words: Self.recipientWords, recordId: "recipient-wallet", platform: platform)
        let onChainKey = try XCTUnwrap(Data(hexString: Self.onChainPublicKeyHex))
        let chain = RecipientChainHost(accountState: "active", onChainPublicKey: onChainKey)
        let client = try makeClient(wallet: sender, canSign: false, chain: chain, platform: platform)

        let resolved = try await client.resolveEncryptedCommentRecipient(
            request: EncryptedCommentRecipientRequest(recipient: recipient.address)
        )

        XCTAssertEqual(resolved.hexString, onChainKey.hexString)
        XCTAssertEqual(chain.calls, try recipientLookup(recipient.address, readsOnChainKey: true))
        XCTAssertTrue(platform.secretReasons.isEmpty)
    }

    func testEncryptedCommentForActiveRecipientUsesOnChainKeyInsteadOfSuppliedKey() async throws {
        let platform = MemoryPlatformHost()
        let sender = try await importWallet(words: Self.senderWords, recordId: "sender-wallet", platform: platform)
        let recipient = try await importWallet(words: Self.recipientWords, recordId: "recipient-wallet", platform: platform)
        let currentKeyHolder = try await importWallet(words: Self.currentKeyHolderWords, recordId: "current-key-holder", platform: platform)
        let comment = "for the current key"
        let chain = RecipientChainHost(accountState: "active", onChainPublicKey: currentKeyHolder.publicKey)
        let senderClient = try makeClient(wallet: sender, canSign: true, chain: chain, platform: platform)

        let body = try await senderClient.createEncryptedComment(
            request: CreateEncryptedCommentRequest(recipient: recipient.address, comment: comment, recipientPublicKey: recipient.publicKey)
        )

        XCTAssertEqual(chain.calls, try recipientLookup(recipient.address, readsOnChainKey: true))
        XCTAssertEqual(platform.secretReasons, [.encryptComment])

        let currentKeyChain = RecipientChainHost(accountState: "active", onChainPublicKey: currentKeyHolder.publicKey)
        let currentKeyClient = try makeClient(wallet: currentKeyHolder, canSign: true, chain: currentKeyChain, platform: platform)
        let decrypted = try await currentKeyClient.decryptComment(request: DecryptCommentRequest(sender: sender.address, body: body))
        XCTAssertEqual(decrypted, comment)

        let initialKeyChain = RecipientChainHost(accountState: "active", onChainPublicKey: currentKeyHolder.publicKey)
        let initialKeyClient = try makeClient(wallet: recipient, canSign: true, chain: initialKeyChain, platform: platform)
        do {
            let leaked = try await initialKeyClient.decryptComment(request: DecryptCommentRequest(sender: sender.address, body: body))
            XCTFail("the supplied initial key decrypted the comment: \(leaked)")
        } catch WalletClientError.EncryptedCommentUnavailable {
        }
        XCTAssertTrue(currentKeyChain.calls.isEmpty)
        XCTAssertTrue(initialKeyChain.calls.isEmpty)
    }

    private func importWallet(words: String, recordId: String, platform: MemoryPlatformHost) async throws -> WalletDescriptor {
        let lifecycle = WalletLifecycle(platformHost: platform)
        return try await lifecycle.importWallet(
            request: ImportWalletRequest(
                recordId: recordId,
                network: .mainnet,
                recoveryWords: words.split(separator: " ").map(String.init)
            )
        )
    }

    private func makeClient(wallet: WalletDescriptor, canSign: Bool, chain: RecipientChainHost, platform: MemoryPlatformHost) throws -> WalletClient {
        let config = WalletClientConfig(
            recordId: wallet.recordId,
            address: wallet.address,
            publicKey: wallet.publicKey,
            localSecretRef: canSign ? wallet.secretRef : nil,
            network: wallet.network,
            sendValiditySeconds: 300,
            resolutionMarginSeconds: 60,
            providers: ProviderConfig(
                toncenterBaseUrl: RecipientChainHost.baseUrl,
                dnsRootAddress: nil,
                requestTimeoutMs: 15_000
            )
        )
        return try WalletClient(config: config, httpHost: chain, platformHost: platform)
    }

    private func recipientLookup(_ address: String, readsOnChainKey: Bool) throws -> [ProviderCall] {
        let raw = try convertTonAddress(value: address, format: .raw)
        var calls: [ProviderCall] = [.accountState(address: raw)]
        if readsOnChainKey {
            calls.append(.getMethod(address: raw, method: "get_public_key"))
        }
        return calls
    }
}

private enum ProviderCall: Equatable, CustomStringConvertible {
    case accountState(address: String)
    case getMethod(address: String, method: String)
    case unexpected(method: String, url: String)

    @available(macOS 10.15, *)
    init(request: HttpRequest) {
        let components = URLComponents(string: request.url)
        switch (request.method, components?.path) {
        case (.get, "/api/v2/getAddressInformation"):
            if let address = components?.queryItems?.first(where: { $0.name == "address" })?.value {
                self = .accountState(address: ProviderCall.rawAddress(address))
                return
            }
        case (.post, "/api/v2/jsonRPC"):
            if let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
               object["jsonrpc"] as? String == "2.0",
               object["method"] as? String == "runGetMethod",
               let params = object["params"] as? [String: Any],
               let address = params["address"] as? String,
               let method = params["method"] as? String,
               let stack = params["stack"] as? [Any], stack.isEmpty {
                self = .getMethod(address: ProviderCall.rawAddress(address), method: method)
                return
            }
        default:
            break
        }
        self = .unexpected(method: "\(request.method)", url: request.url)
    }

    var description: String {
        switch self {
        case let .accountState(address):
            return "getAddressInformation(\(address))"
        case let .getMethod(address, method):
            return "runGetMethod(\(address), \(method))"
        case let .unexpected(method, url):
            return "unexpected \(method) \(url)"
        }
    }

    @available(macOS 10.15, *)
    private static func rawAddress(_ address: String) -> String {
        return (try? convertTonAddress(value: address, format: .raw)) ?? address
    }
}

@available(macOS 10.15, *)
private final class RecipientChainHost: WalletHttpHost, @unchecked Sendable {
    static let baseUrl = "https://provider.example"

    private let accountState: String
    private let onChainPublicKey: Data
    private let lock = NSLock()
    private var recordedCalls: [ProviderCall] = []

    init(accountState: String, onChainPublicKey: Data) {
        self.accountState = accountState
        self.onChainPublicKey = onChainPublicKey
    }

    var calls: [ProviderCall] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func executeHttp(request: HttpRequest) async throws -> HttpResponse {
        let call = ProviderCall(request: request)
        record(call)
        let body: String
        switch call {
        case .accountState:
            body = #"{"ok":true,"result":{"balance":"1000000000","state":"\#(accountState)","sync_utime":1}}"#
        case .getMethod(_, "get_public_key"):
            body = #"{"ok":true,"result":{"exit_code":0,"stack":[["num","0x\#(onChainPublicKey.hexString)"]]}}"#
        case .getMethod, .unexpected:
            throw HttpHostError.Failed(kind: .other, diagnostic: "unexpected provider request \(call)")
        }
        return HttpResponse(status: 200, headers: [], body: Data(body.utf8), finalUrl: request.url)
    }

    func cancelHttp(requestId: HttpRequestId) async {
    }

    private func record(_ call: ProviderCall) {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append(call)
    }
}

@available(macOS 10.15, *)
private final class MemoryPlatformHost: WalletPlatformHost, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: Data] = [:]
    private var reasons: [SecretAccessReason] = []

    var secretReasons: [SecretAccessReason] {
        lock.lock()
        defer { lock.unlock() }
        return reasons
    }

    func readProtectedSecret(request: ProtectedSecretRead) async throws -> Data {
        guard let secret = read(request) else {
            throw ProtectedSecretHostError.Failed(kind: .notFound, diagnostic: "no stored secret")
        }
        return secret
    }

    func storeProtectedSecret(request: ProtectedSecretStore) async throws {
        store(request)
    }

    func deleteProtectedSecret(secretRef: ProtectedSecretRef) async throws {
        delete(secretRef)
    }

    func loadJournal(key: JournalKey) async throws -> JournalRecord? {
        return nil
    }

    func compareExchangeJournal(mutation: JournalCompareExchange) async throws -> JournalCompareExchangeResult {
        throw JournalHostError.Failed(kind: .unavailable, diagnostic: "no journal in encrypted comment tests")
    }

    private func read(_ request: ProtectedSecretRead) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        reasons.append(request.reason)
        return secrets[request.secretRef.value]
    }

    private func store(_ request: ProtectedSecretStore) {
        lock.lock()
        defer { lock.unlock() }
        secrets[request.secretRef.value] = request.bytes
    }

    private func delete(_ secretRef: ProtectedSecretRef) {
        lock.lock()
        defer { lock.unlock() }
        secrets[secretRef.value] = nil
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else {
            return nil
        }
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index ..< next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
