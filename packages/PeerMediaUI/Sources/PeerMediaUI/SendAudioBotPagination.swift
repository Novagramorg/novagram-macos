import TelegramCore
import SwiftSignalKit

private final class SendAudioBotPagination {
    private let request: (String) -> Signal<ChatContextResultCollection?, NoError>
    private let publish: ([ChatContextResult]) -> Void
    private let requestDisposable = MetaDisposable()
    private let loadMoreDisposable = MetaDisposable()
    private let disposed = Atomic(value: false)
    private var results: [ChatContextResult] = []
    private var resultIds = Set<String>()
    private var offsets = Set<String>()
    private var offset = ""
    private var loading = false
    private var completed = false

    init(request: @escaping (String) -> Signal<ChatContextResultCollection?, NoError>, publish: @escaping ([ChatContextResult]) -> Void) {
        self.request = request
        self.publish = publish
    }

    func start(loadMore: Signal<Void, NoError>) {
        loadMoreDisposable.set((loadMore |> deliverOnMainQueue).start(next: { [weak self] in
            self?.loadNext()
        }))
        loadNext()
    }

    private func loadNext() {
        guard !disposed.with({ $0 }), !loading, !completed else {
            return
        }
        loading = true
        let currentOffset = offset
        let currentRequest = MetaDisposable()
        requestDisposable.set(currentRequest)
        var receivedResult = false
        let finishWithoutResult: () -> Void = { [weak self] in
            guard let self, !receivedResult, !self.disposed.with({ $0 }) else {
                return
            }
            self.loading = false
            self.publish(self.results)
        }
        currentRequest.set((request(currentOffset) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] collection in
            guard let self, !self.disposed.with({ $0 }) else {
                return
            }
            receivedResult = true
            if let collection {
                self.offsets.insert(currentOffset)
                for result in collection.results where self.resultIds.insert(result.id).inserted {
                    self.results.append(result)
                }
                if let nextOffset = collection.nextOffset, !nextOffset.isEmpty, !self.offsets.contains(nextOffset) {
                    self.offset = nextOffset
                } else {
                    self.completed = true
                }
            }
            self.loading = false
            self.publish(self.results)
        }, completed: finishWithoutResult))
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

func sendAudioBotSearchResults(loadMore: Signal<Void, NoError>, request: @escaping (String) -> Signal<ChatContextResultCollection?, NoError>) -> Signal<[ChatContextResult], NoError> {
    return Signal { subscriber in
        let pagination = SendAudioBotPagination(request: request, publish: { subscriber.putNext($0) })
        pagination.start(loadMore: loadMore)
        return ActionDisposable {
            pagination.dispose()
        }
    } |> runOn(.mainQueue())
}
