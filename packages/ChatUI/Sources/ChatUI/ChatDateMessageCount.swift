import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext

func chatDateLoadMessages(context: any AccountContextProtocol, location: SearchMessagesLocation, state: SearchMessagesState? = nil) -> Signal<[Message]?, NoError> {
    return context.engine.messages.searchMessages(location: location, query: "", state: state, limit: 100)
    |> mapToSignal { result, nextState -> Signal<[Message]?, NoError> in
        if result.completed {
            guard case let .peer(_, _, _, _, _, minDate?, maxDate?) = location else {
                return .single(nil)
            }
            var ids = Set<MessageId>()
            return .single(result.messages.filter {
                $0.timestamp >= minDate && $0.timestamp <= maxDate && ids.insert($0.id).inserted
            }.sorted { $0.index < $1.index })
        }
        guard state != nextState else {
            return .single(nil)
        }
        return chatDateLoadMessages(context: context, location: location, state: nextState)
    }
}

func chatDateMessageCount(context: any AccountContextProtocol, location: SearchMessagesLocation) -> Signal<Int?, NoError> {
    return chatDateLoadMessages(context: context, location: location)
    |> map { $0?.count }
}
