import Cocoa
import Postbox
import SwiftSignalKit
import TGUIKit
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

public final class ChatMessageThrottledProcessingManager {
    private let queue = messagesViewQueue
    
    private let delay: Double
    private let submitInterval: Double?
    
    public var process: ((Set<MessageId>) -> Void)?
    
    private var timer: SwiftSignalKit.Timer?
    private var processedList: [MessageId] = []
    private var processed: [MessageId: Double] = [:]
    private var buffer = Set<MessageId>()
    private var latest: [MessageId] = []
    private var isActive: Bool = true
    private struct ActivityState {
        var isActive = true
        var generation = 0
    }
    private let activityState = Atomic(value: ActivityState())
    
    private let disposable = MetaDisposable()
    
    public init(delay: Double = 1.0, submitInterval: Double? = nil) {
        self.delay = delay
        self.submitInterval = submitInterval
    }
    
    deinit {
        timer?.invalidate()
        disposable.dispose()
    }

    public func setProcess(process: @escaping (Set<MessageId>) -> Void) {
        self.queue.async { [weak self] in
            self?.process = process
        }
    }
    
    public func setActive(_ isActive: Bool) {
        _ = self.activityState.modify { current in
            var current = current
            if current.isActive != isActive {
                current.isActive = isActive
                current.generation &+= 1
            }
            return current
        }
        self.queue.async { [weak self] in
            guard let self else { return }
            if self.isActive == isActive {
                return
            }
            self.isActive = isActive
            if isActive {
                if self.submitInterval != nil, !self.latest.isEmpty {
                    self.enqueue(self.latest)
                }
            } else {
                self.disposable.set(nil)
                self.timer?.invalidate()
                self.timer = nil
                self.buffer.removeAll()
                self.processed.removeAll()
                self.processedList.removeAll()
            }
        }
    }
    
    public func add(_ messageIds: [MessageId]) {
        self.queue.async { [weak self] in
            guard let self else { return }
            self.latest = messageIds
            self.enqueue(messageIds)
        }
    }
    
    private func enqueue(_ messageIds: [MessageId]) {
        guard self.isActive else { return }
        let timestamp = CFAbsoluteTimeGetCurrent()
        
        for id in messageIds {
            if let processedTimestamp = self.processed[id] {
                if let submitInterval = self.submitInterval, (timestamp - processedTimestamp) >= submitInterval {
                    self.processed[id] = timestamp
                    self.processedList.append(id)
                    self.buffer.insert(id)
                }
            } else {
                self.processed[id] = timestamp
                self.processedList.append(id)
                self.buffer.insert(id)
            }
        }
        
        if self.processedList.count > 1000 {
            for i in 0 ..< 200 {
                self.processed.removeValue(forKey: self.processedList[i])
            }
            self.processedList.removeSubrange(0 ..< 200)
        }
        
        if self.timer == nil {
            let generation = self.activityState.with { $0.generation }
            var completionImpl: (() -> Void)?
            let timer = SwiftSignalKit.Timer(timeout: self.delay, repeat: false, completion: {
                completionImpl?()
            }, queue: self.queue)
            completionImpl = { [weak self, weak timer] in
                if let strongSelf = self, let timer, strongSelf.timer === timer, strongSelf.isActive {
                    strongSelf.timer = nil
                    let buffer = strongSelf.buffer
                    strongSelf.buffer.removeAll()
                    
                    if let submitInterval = strongSelf.submitInterval, submitInterval > 0, strongSelf.isActive {
                        strongSelf.disposable.set((delaySignal(submitInterval) |> deliverOn(strongSelf.queue)).start(completed: { [weak strongSelf] in
                            if let strongSelf = strongSelf, strongSelf.isActive {
                                strongSelf.enqueue(strongSelf.latest)
                            }
                        }))
                    } else {
                        strongSelf.disposable.set(nil)
                    }
                    DispatchQueue.main.async { [weak strongSelf] in
                        guard let strongSelf, strongSelf.activityState.with({ $0.isActive && $0.generation == generation }) else { return }
                        strongSelf.process?(buffer)
                    }
                }
            }
            self.timer = timer
            timer.start()
        }
    }
}


public final class ChatMessageVisibleThrottledProcessingManager {
    private let queue = Queue()
    
    private let delay: Double
    
    private var currentIds = Set<MessageId>()
    
    public var process: ((Set<MessageId>) -> Void)?
    
    private var timer: SwiftSignalKit.Timer?
    
    public init(delay: Double = 1.0) {
        self.delay = delay
    }
    
    public func setProcess(process: @escaping (Set<MessageId>) -> Void) {
        self.queue.async {
            self.process = process
        }
    }
    
    public func update(_ ids: Set<MessageId>) {
        self.queue.async { [self] in
            if self.currentIds != ids {
                self.currentIds = ids
                if self.timer == nil {
                    var completionImpl: (() -> Void)?
                    let timer = SwiftSignalKit.Timer(timeout: self.delay, repeat: false, completion: {
                        completionImpl?()
                    }, queue: self.queue)
                    completionImpl = { [weak self, weak timer] in
                        if let strongSelf = self {
                            if let timer = timer, strongSelf.timer === timer {
                                strongSelf.timer = nil
                            }
                            strongSelf.process?(strongSelf.currentIds)
                        }
                    }
                    self.timer = timer
                    timer.start()
                }
            }
        }
    }
}
