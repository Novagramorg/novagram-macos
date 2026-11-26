import Postbox
import TelegramCore
import SwiftSignalKit

private final class PeerMediaSearchPagination {
    private let request: (SearchMessagesState?) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError>
    private let publish: ([Message]?) -> Void
    private let requestDisposable = MetaDisposable()
    private let loadMoreDisposable = MetaDisposable()
    private let disposed = Atomic(value: false)
    private var state: SearchMessagesState?
    private var messages: [Message] = []
    private var loading = false
    private var completed = false

    init(request: @escaping (SearchMessagesState?) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError>, publish: @escaping ([Message]?) -> Void) {
        self.request = request
        self.publish = publish
    }

    func start(loadMore: Signal<Void, NoError>) {
        loadMoreDisposable.set((loadMore |> deliverOnMainQueue).start(next: { [weak self] in
            self?.loadNext()
        }))
        publish(nil)
        loadNext()
    }

    private func loadNext() {
        guard !disposed.with({ $0 }), !loading, !completed else {
            return
        }
        loading = true
        let currentRequest = MetaDisposable()
        requestDisposable.set(currentRequest)
        var receivedResult = false
        currentRequest.set((request(state) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] result, state in
            guard let self, !self.disposed.with({ $0 }) else {
                return
            }
            receivedResult = true
            self.state = state
            self.messages = result.messages
            self.completed = result.completed
            self.loading = false
            self.publish(result.messages)
        }, completed: { [weak self] in
            guard let self, !receivedResult, !self.disposed.with({ $0 }) else {
                return
            }
            self.loading = false
            self.publish(self.messages)
        }))
    }

    func dispose() {
        _ = disposed.swap(true)
        requestDisposable.dispose()
        loadMoreDisposable.dispose()
    }

    deinit {
        dispose()
    }
}

func peerMediaSearchMessages(loadMore: Signal<Void, NoError>, request: @escaping (SearchMessagesState?) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError>) -> Signal<[Message]?, NoError> {
    return Signal { subscriber in
        let pagination = PeerMediaSearchPagination(request: request, publish: { subscriber.putNext($0) })
        pagination.start(loadMore: loadMore)
        return ActionDisposable {
            pagination.dispose()
        }
    } |> runOn(.mainQueue())
}
