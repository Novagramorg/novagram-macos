import SwiftSignalKit

public let resourcesQueue = Queue(name: "ResourcesQueue", qos: .utility)
public let prepareQueue = Queue(name: "PrepareQueue", qos: .utility)
public let messagesViewQueue = Queue(name: "messagesViewQueue", qos: .utility)

public func deliverOnPrepareQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> {
    return signal |> deliverOn(prepareQueue)
}

public func deliverOnResourceQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> {
    return signal |> deliverOn(resourcesQueue)
}
