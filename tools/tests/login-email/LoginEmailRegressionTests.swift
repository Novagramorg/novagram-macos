private struct ChangeLoginEmailData: Equatable {
    let email: String
    let length: Int32
}

private enum SendError: Error { case limitExceeded, generic, codeExpired, timeout, invalidEmail, emailNotAllowed }
private enum VerifyError: Error { case limitExceeded, invalidCode, generic, codeExpired, timeout, invalidEmailToken, emailNotAllowed }
private enum Verification { case emailCode(String) }

private final class PendingRequest<T, E> {
    private var subscriber: Subscriber<T, E>?
    private(set) var disposed = false
    var signal: Signal<T, E> {
        Signal { subscriber in
            self.subscriber = subscriber
            return ActionDisposable { self.disposed = true }
        }
    }
    func succeed(_ value: T) {
        subscriber?.putNext(value)
        subscriber?.putCompletion()
    }
    func complete() { subscriber?.putCompletion() }
    func fail(_ error: E) { subscriber?.putError(error) }
}

private final class Account {
    var emails: [String] = []
    var codes: [String] = []
    var sends: [PendingRequest<ChangeLoginEmailData, SendError>] = []
    var verifications: [PendingRequest<Never, VerifyError>] = []
}

private func sendLoginEmailChangeCode(account: Account, email: String) -> Signal<ChangeLoginEmailData, SendError> {
    let request = PendingRequest<ChangeLoginEmailData, SendError>()
    account.emails.append(email)
    account.sends.append(request)
    return request.signal
}

private func verifyLoginEmailChange(account: Account, code: Verification) -> Signal<Never, VerifyError> {
    let request = PendingRequest<Never, VerifyError>()
    if case let .emailCode(value) = code { account.codes.append(value) }
    account.verifications.append(request)
    return request.signal
}

final class LoginEmailRegressionTests: XCTestCase {
    private func startEmail(_ context: Context, _ modal: InputDataModalController, email: String = "first@example.test") {
        _ = modal.controller.updateDatas([_id_input: .string(email)])
        modal.controller.returnKeyAction()
    }

    private func showCode(_ context: Context, _ modal: InputDataModalController) {
        startEmail(context, modal)
        context.account.sends.last?.succeed(ChangeLoginEmailData(email: "first@example.test", length: 6))
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        Queue.mainQueue().async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    func testRepeatedSubmitStartsOneSend() {
        let context = Context()
        let modal = SetupEmailController(context: context, pattern: nil)
        defer { modal.close() }
        startEmail(context, modal)
        modal.controller.returnKeyAction()
        XCTAssertEqual(context.account.emails, ["first@example.test"])
        XCTAssertTrue(modal.controller.snapshot.state.isLoading)
        XCTAssertFalse(modal.interactions!.button.isEnabled)
    }

    func testSendFailureRestoresRetry() {
        let context = Context()
        let modal = SetupEmailController(context: context, pattern: nil)
        defer { modal.close() }
        startEmail(context, modal)
        context.account.sends[0].fail(.timeout)
        XCTAssertFalse(modal.controller.snapshot.state.isLoading)
        XCTAssertEqual(context.window.messages, ["emailNetworkError"])
        modal.controller.returnKeyAction()
        XCTAssertEqual(context.account.sends.count, 2)
        drainMainQueue()
        XCTAssertTrue(modal.controller.snapshot.state.isLoading)
    }

    func testCancellingSendProgressAllowsRetry() {
        let context = Context()
        let modal = SetupEmailController(context: context, pattern: nil)
        defer { modal.close() }
        startEmail(context, modal)
        context.window.progress?.dispose()
        drainMainQueue()
        XCTAssertTrue(context.account.sends[0].disposed)
        XCTAssertFalse(modal.controller.snapshot.state.isLoading)
        modal.controller.returnKeyAction()
        XCTAssertEqual(context.account.sends.count, 2)
    }

    func testVerificationStaysLockedAcrossOldCleanupAndEditEvents() {
        let context = Context()
        let modal = SetupEmailController(context: context, pattern: nil)
        defer { modal.close() }
        showCode(context, modal)
        modal.controller.snapshot.arguments.takeNext("123456")
        drainMainQueue()
        XCTAssertTrue(modal.controller.snapshot.state.isLoading)
        modal.controller.snapshot.arguments.takeError()
        modal.controller.snapshot.arguments.takeNext("123456")
        XCTAssertTrue(modal.controller.snapshot.state.isLoading)
        XCTAssertEqual(context.account.codes, ["123456"])
    }

    func testCancellingVerificationProgressUnlocksCodeEntry() {
        let context = Context()
        let modal = SetupEmailController(context: context, pattern: nil)
        defer { modal.close() }
        showCode(context, modal)
        modal.controller.snapshot.arguments.takeNext("123456")
        context.window.progress?.dispose()
        drainMainQueue()
        XCTAssertFalse(modal.controller.snapshot.state.isLoading)
        modal.controller.snapshot.arguments.takeNext("654321")
        XCTAssertEqual(context.account.codes, ["123456", "654321"])
    }

    func testReturningToEmailCancelsVerificationAndIgnoresLateSuccess() {
        let context = Context()
        let modal = SetupEmailController(context: context, pattern: nil)
        defer { modal.close() }
        showCode(context, modal)
        modal.controller.snapshot.arguments.takeNext("123456")
        modal.controller.returnKeyAction()
        XCTAssertTrue(context.account.verifications[0].disposed)
        startEmail(context, modal, email: "second@example.test")
        context.account.verifications[0].complete()
        drainMainQueue()
        XCTAssertFalse(modal.closed)
        XCTAssertTrue(modal.controller.snapshot.state.isLoading)
        XCTAssertTrue(context.window.messages.isEmpty)
    }

    func testClosingScreenCancelsSendAndIgnoresLateResponse() {
        let context = Context()
        let modal = SetupEmailController(context: context, pattern: nil)
        startEmail(context, modal)
        modal.close()
        XCTAssertTrue(context.account.sends[0].disposed)
        context.account.sends[0].succeed(ChangeLoginEmailData(email: "first@example.test", length: 6))
        if case .code = modal.controller.snapshot.state.state { XCTFail("Closed controller accepted a stale response") }
    }

    func testVerificationFailureAllowsRetryAndSuccessCloses() {
        let context = Context()
        let modal = SetupEmailController(context: context, pattern: nil)
        showCode(context, modal)
        modal.controller.snapshot.arguments.takeNext("123456")
        context.account.verifications[0].fail(.invalidCode)
        XCTAssertFalse(modal.controller.snapshot.state.isLoading)
        XCTAssertEqual(modal.controller.snapshot.state.error?.description, "emailInvalidCodeError")
        modal.controller.snapshot.arguments.takeNext("654321")
        XCTAssertNil(modal.controller.snapshot.state.error)
        context.account.verifications[1].complete()
        XCTAssertTrue(modal.closed)
        XCTAssertEqual(context.window.messages, ["loginEmailChanged"])
    }
}
