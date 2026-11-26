private typealias ViewController = InputDataController
private typealias ASPresentationAnchor = Window

private struct TelegramPasskey: Equatable { let id: String }

private final class PendingRequest<T> {
    private var subscriber: Subscriber<T, NoError>?
    private(set) var disposed = false
    var signal: Signal<T, NoError> {
        Signal { subscriber in
            self.subscriber = subscriber
            return ActionDisposable { self.disposed = true }
        }
    }
    func respond(_ value: T) {
        subscriber?.putNext(value)
        subscriber?.putCompletion()
    }
}

private final class Auth {
    var registrations: [PendingRequest<String?>] = []
    var creations: [PendingRequest<TelegramPasskey?>] = []
    var credentials: [(String, String, Data)] = []
    func requestPasskeyRegistration() -> Signal<String?, NoError> {
        let request = PendingRequest<String?>()
        registrations.append(request)
        return request.signal
    }
    func requestCreatePasskey(id: String, clientData: String, attestationObject: Data) -> Signal<TelegramPasskey?, NoError> {
        let request = PendingRequest<TelegramPasskey?>()
        creations.append(request)
        credentials.append((id, clientData, attestationObject))
        return request.signal
    }
    func deletePasskey(id: String) -> Signal<Bool, NoError> { .single(true) }
}

private final class AppConfiguration {
    var limit = 5
    func getGeneralValue(_ key: String, orElse: Int) -> Int { limit }
}
private final class Engine { let auth = Auth() }
private final class Account {
    let engine = Engine()
    let configuration = AppConfiguration()
}
private extension AccountContextProtocol {
    var engine: Engine { account.engine }
    var appConfiguration: AppConfiguration { account.configuration }
}

private protocol ASAuthorizationControllerDelegate: AnyObject {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization)
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error)
}
private protocol ASAuthorizationControllerPresentationContextProviding: AnyObject {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor
}
private struct ASAuthorizationError: Error {
    enum Code { case canceled, unknown }
    let code: Code
}
private final class ASAuthorization {
    let credential: AnyObject
    init(_ credential: AnyObject) { self.credential = credential }
}
private final class ASAuthorizationPlatformPublicKeyCredentialRegistration {
    let credentialID = Data([0xfb, 0xff])
    let rawClientDataJSON = Data("{}".utf8)
    var rawAttestationObject: Data? = Data([1, 2, 3])
}
private struct RegistrationRequest {
    let relyingParty: String
    let challenge: Data
    let name: String
    let userID: Data
}
private final class ASAuthorizationPlatformPublicKeyCredentialProvider {
    let relyingPartyIdentifier: String
    init(relyingPartyIdentifier: String) { self.relyingPartyIdentifier = relyingPartyIdentifier }
    func createCredentialRegistrationRequest(challenge: Data, name: String, userID: Data) -> RegistrationRequest {
        RegistrationRequest(relyingParty: relyingPartyIdentifier, challenge: challenge, name: name, userID: userID)
    }
}
private final class ASAuthorizationController {
    static var presented: [ASAuthorizationController] = []
    let requests: [RegistrationRequest]
    weak var delegate: (any ASAuthorizationControllerDelegate)?
    weak var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)?
    private(set) var cancelled = false
    init(authorizationRequests: [RegistrationRequest]) { requests = authorizationRequests }
    func performRequests() { Self.presented.append(self) }
    func cancel() { cancelled = true }
    func succeed(_ credential: AnyObject = ASAuthorizationPlatformPublicKeyCredentialRegistration()) {
        delegate?.authorizationController(controller: self, didCompleteWithAuthorization: ASAuthorization(credential))
    }
    func fail(_ code: ASAuthorizationError.Code) {
        delegate?.authorizationController(controller: self, didCompleteWithError: ASAuthorizationError(code: code))
    }
}

final class PasskeyRegistrationRegressionTests: XCTestCase {
    private let options = #"{"publicKey":{"rp":{"id":"example.test"},"challenge":"AAE-","user":{"id":"AAE_","name":"Test"}}}"#

    override func setUp() {
        super.setUp()
        ASAuthorizationController.presented = []
    }

    private func present(_ context: Context, _ modal: InputDataModalController) throws -> ASAuthorizationController {
        modal.controller.returnKeyAction()
        context.engine.auth.registrations.last?.respond(options)
        return try XCTUnwrap(ASAuthorizationController.presented.last)
    }

    func testRepeatedClicksStartOneFlowAndCancelAllowsRetry() throws {
        let context = Context()
        let modal = PasskeysController(context: context, passkeys: [])
        defer { modal.close() }
        modal.controller.returnKeyAction()
        modal.controller.returnKeyAction()
        XCTAssertEqual(context.engine.auth.registrations.count, 1)
        XCTAssertFalse(modal.interactions!.button.isEnabled)
        context.engine.auth.registrations[0].respond(options)
        let authorization = try XCTUnwrap(ASAuthorizationController.presented.last)
        modal.controller.returnKeyAction()
        XCTAssertEqual(context.engine.auth.registrations.count, 1)
        authorization.fail(.canceled)
        XCTAssertTrue(context.window.messages.isEmpty)
        XCTAssertTrue(modal.interactions!.button.isEnabled)
        modal.controller.returnKeyAction()
        XCTAssertEqual(context.engine.auth.registrations.count, 2)
    }

    func testMissingOptionsReportsFailureAndAllowsRetry() {
        let context = Context()
        let modal = PasskeysController(context: context, passkeys: [])
        defer { modal.close() }
        modal.controller.returnKeyAction()
        context.engine.auth.registrations[0].respond(nil)
        XCTAssertEqual(context.window.messages, ["unknownError"])
        XCTAssertTrue(modal.interactions!.button.isEnabled)
        modal.controller.returnKeyAction()
        XCTAssertEqual(context.engine.auth.registrations.count, 2)
    }

    func testMalformedOptionsReportFailureWithoutPresentingAuthorization() {
        for data in ["not-json", "{}", options.replacingOccurrences(of: "AAE-", with: "?")] {
            let context = Context()
            let modal = PasskeysController(context: context, passkeys: [])
            modal.controller.returnKeyAction()
            context.engine.auth.registrations[0].respond(data)
            XCTAssertEqual(context.window.messages, ["unknownError"])
            XCTAssertTrue(ASAuthorizationController.presented.isEmpty)
            XCTAssertTrue(modal.interactions!.button.isEnabled)
            modal.close()
        }
    }

    func testSystemFailureReportsErrorAndAllowsRetry() throws {
        let context = Context()
        let modal = PasskeysController(context: context, passkeys: [])
        defer { modal.close() }
        let authorization = try present(context, modal)
        authorization.fail(.unknown)
        XCTAssertEqual(context.window.messages, ["unknownError"])
        XCTAssertTrue(modal.interactions!.button.isEnabled)
        modal.controller.returnKeyAction()
        XCTAssertEqual(context.engine.auth.registrations.count, 2)
    }

    func testMissingAttestationReportsErrorWithoutSaving() throws {
        let context = Context()
        let modal = PasskeysController(context: context, passkeys: [])
        defer { modal.close() }
        let authorization = try present(context, modal)
        let credential = ASAuthorizationPlatformPublicKeyCredentialRegistration()
        credential.rawAttestationObject = nil
        authorization.succeed(credential)
        XCTAssertEqual(context.window.messages, ["unknownError"])
        XCTAssertTrue(context.engine.auth.creations.isEmpty)
        XCTAssertTrue(modal.interactions!.button.isEnabled)
    }

    func testServerRegistrationFailureReportsErrorWithoutAddingPasskey() throws {
        let context = Context()
        let modal = PasskeysController(context: context, passkeys: [])
        defer { modal.close() }
        let authorization = try present(context, modal)
        authorization.succeed()
        modal.controller.returnKeyAction()
        XCTAssertEqual(context.engine.auth.registrations.count, 1)
        context.engine.auth.creations[0].respond(nil)
        XCTAssertEqual(context.window.messages, ["unknownError"])
        XCTAssertTrue(modal.controller.snapshot.state.passkeys.isEmpty)
        XCTAssertTrue(modal.interactions!.button.isEnabled)
    }

    func testSuccessfulRegistrationForwardsCredentialAndKeepsIdsUnique() throws {
        let context = Context()
        let modal = PasskeysController(context: context, passkeys: [TelegramPasskey(id: "existing")])
        defer { modal.close() }
        let authorization = try present(context, modal)
        let request = try XCTUnwrap(authorization.requests.first)
        XCTAssertEqual(request.relyingParty, "example.test")
        XCTAssertEqual(request.challenge, Data([0, 1, 62]))
        XCTAssertEqual(request.userID, Data([0, 1, 63]))
        XCTAssertEqual(request.name, "Test")
        authorization.succeed()
        let credential = try XCTUnwrap(context.engine.auth.credentials.first)
        XCTAssertEqual(credential.0, "-_8")
        XCTAssertEqual(credential.1, "{}")
        XCTAssertEqual(credential.2, Data([1, 2, 3]))
        context.engine.auth.creations[0].respond(TelegramPasskey(id: "existing"))
        XCTAssertEqual(modal.controller.snapshot.state.passkeys.map(\.id), ["existing"])
        XCTAssertTrue(context.window.messages.isEmpty)
        XCTAssertTrue(modal.interactions!.button.isEnabled)
    }

    func testLoweredAccountLimitPreventsAnotherRegistration() {
        let context = Context()
        context.appConfiguration.limit = 1
        let modal = PasskeysController(context: context, passkeys: [TelegramPasskey(id: "one"), TelegramPasskey(id: "two")])
        defer { modal.close() }
        modal.controller.returnKeyAction()
        XCTAssertEqual(context.window.messages, ["limit-1"])
        XCTAssertTrue(context.engine.auth.registrations.isEmpty)
    }

    func testClosingBeforeOptionsCancelsRequestAndPreventsLateSheet() {
        let context = Context()
        let modal = PasskeysController(context: context, passkeys: [])
        modal.controller.returnKeyAction()
        modal.close()
        XCTAssertTrue(context.engine.auth.registrations[0].disposed)
        context.engine.auth.registrations[0].respond(options)
        XCTAssertTrue(ASAuthorizationController.presented.isEmpty)
    }

    func testClosingDuringAuthorizationCancelsAndIgnoresLateCredential() throws {
        let context = Context()
        let modal = PasskeysController(context: context, passkeys: [])
        let authorization = try present(context, modal)
        modal.close()
        if #available(macOS 13.0, *) { XCTAssertTrue(authorization.cancelled) }
        authorization.succeed()
        XCTAssertTrue(context.engine.auth.creations.isEmpty)
        XCTAssertTrue(context.window.messages.isEmpty)
    }

    func testClosingDuringSaveCancelsAndIgnoresLateResult() throws {
        let context = Context()
        let modal = PasskeysController(context: context, passkeys: [])
        let authorization = try present(context, modal)
        authorization.succeed()
        modal.close()
        XCTAssertTrue(context.engine.auth.creations[0].disposed)
        context.engine.auth.creations[0].respond(TelegramPasskey(id: "late"))
        XCTAssertTrue(modal.controller.snapshot.state.passkeys.isEmpty)
    }
}
