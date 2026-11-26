enum Api {
    enum Bool {
        case boolTrue
        case boolFalse
    }

    enum functions {
        enum account {
            static func deletePasskey(id: String) -> String {
                return id
            }
        }
    }
}

enum NetworkError: Error {
    case unavailable
}

final class Network {
    let response: Signal<Api.Bool, NetworkError>
    private(set) var requestedId: String?

    init(response: Signal<Api.Bool, NetworkError>) {
        self.response = response
    }

    func request(_ id: String) -> Signal<Api.Bool, NetworkError> {
        requestedId = id
        return response
    }
}

final class PasskeysRegressionTests: XCTestCase {
    private func verify(response: Signal<Api.Bool, NetworkError>, expected: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let network = Network(response: response)
        var values: [Any] = []
        var completed = false
        let disposable = _internal_deletePasskey(network: network, id: "test-credential").start(next: { value in
            values.append(value as Any)
        }, completed: {
            completed = true
        })
        defer { disposable.dispose() }

        XCTAssertEqual(network.requestedId, "test-credential", file: file, line: line)
        XCTAssertEqual(values.count, 1, file: file, line: line)
        XCTAssertEqual(values.first as? Bool, expected, file: file, line: line)
        XCTAssertTrue(completed, file: file, line: line)
    }

    func testServerConfirmationIsReported() {
        verify(response: .single(.boolTrue), expected: true)
    }

    func testServerRejectionIsNotReportedAsDeletion() {
        verify(response: .single(.boolFalse), expected: false)
    }

    func testNetworkFailureIsNotReportedAsDeletion() {
        verify(response: .fail(.unavailable), expected: false)
    }
}
