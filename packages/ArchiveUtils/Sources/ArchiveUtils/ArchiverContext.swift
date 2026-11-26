import Foundation
import Zip
import SwiftSignalKit
import TelegramMediaResources

public enum ArchiveStatus : Equatable {
    case none
    case waiting
    case done(URL)
    case fail(ZipError)
    case progress(Double)
}
public enum ArchiveSource : Hashable {
    public static func == (lhs: ArchiveSource, rhs: ArchiveSource) -> Bool {
        switch lhs {
        case let .resource(lhsResource):
            if case let .resource(rhsResource) = rhs {
                return lhsResource.isEqual(to: rhsResource)
            } else {
                return false
            }
        }
    }
    
    public var contents:[URL] {
        switch self {
        case let .resource(resource):
            if resource.path.contains("tg_temp_archive_") {
                let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: resource.path), includingPropertiesForKeys: nil, options: FileManager.DirectoryEnumerationOptions.skipsHiddenFiles)
                return files ?? [URL(fileURLWithPath: resource.path)]
            }
            return [URL(fileURLWithPath: resource.path)]
        }
    }
    
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .resource(resource):
            hasher.combine(resource.id)
        }
    }
    
    public var destinationURL: URL {
        return URL(fileURLWithPath: NSTemporaryDirectory() + "tarchive-\(self.uniqueId).zip")
    }
    
    
    public var uniqueId: Int64 {
        switch self {
        case .resource(let resource):
            return resource.randomId
        }
    }
    
    case resource(LocalFileArchiveMediaResource)
}

private final class Archiver {
    private let status: ValuePromise<ArchiveStatus> = ValuePromise(.waiting, ignoreRepeated: true)
    public var statusSignal:Signal<ArchiveStatus, NoError> {
        return status.get()
    }
    public let destination: URL
    private let source: ArchiveSource
    private let queue: Queue
    public init(source : ArchiveSource, queue: Queue) {
        self.queue = queue
        self.source = source
        self.destination = source.destinationURL
    }
    
    public func start(cancelToken:@escaping()->Bool) {
        let destination = self.destination
        let source = self.source
        queue.async { [weak status] in
            guard let status = status else {return}
            let contents = source.contents
            if !contents.isEmpty {
                do {
                    try Zip.zipFiles(paths: contents, zipFilePath: destination, password: nil, compression: ZipCompression.BestCompression, progress: { progress in
                        status.set(.progress(progress))
                    }, cancel: cancelToken)
                   status.set(.done(destination))
                } catch {
                    if let error = error as? ZipError {
                        status.set(.fail(error))
                    }
                }
            }
        }
        
    }
    
}
// добавить отмену архивирования если разлонигиваемся
private final class ArchiveStatusContext {
    public var status: ArchiveStatus = .none
    public let subscribers = Bag<(ArchiveStatus) -> Void>()
}
public class ArchiverContext {
    public var statuses:[ArchiveSource : ArchiveStatus] = [:]
    
    private let queue = Queue(name: "ArchiverContext")
    private var contexts: [ArchiveSource: Archiver] = [:]
    private let archiveQueue: Queue = Queue.concurrentDefaultQueue()
    private var statusContexts: [ArchiveSource: ArchiveStatusContext] = [:]
    private var statusesDisposable:[ArchiveSource : Disposable] = [:]
    private var cancelledTokens:[ArchiveSource : Any] = [:]
    public init() {
    }
    
    deinit {
        self.queue.sync {
            self.contexts.removeAll()
            for status in statusesDisposable {
                status.value.dispose()
            }
        }
    }
    
    public func remove(_ source: ArchiveSource) {
        queue.async {
            self.contexts.removeValue(forKey: source)
            self.statusesDisposable[source]?.dispose()
            self.statuses.removeValue(forKey: source)
            self.cancelledTokens[source] = true
        }
    }
    
    public func archive(_ source: ArchiveSource, startIfNeeded: Bool = false) -> Signal<ArchiveStatus, NoError> {
        let queue = self.queue
        return Signal { [weak self] subscriber in
            guard let `self` = self else { return EmptyDisposable }
            if self.statusContexts[source] == nil {
                self.statusContexts[source] = ArchiveStatusContext()
            }
            
            let statusContext = self.statusContexts[source]!
            
            let index = statusContext.subscribers.add({ status in
                subscriber.putNext(status)
            })
            
            if let _ = self.contexts[source] {
                if let statusContext = self.statusContexts[source] {
                    for subscriber in statusContext.subscribers.copyItems() {
                        subscriber(statusContext.status)
                    }
                }
            } else {
                if startIfNeeded {
                    let archiver = Archiver(source: source, queue: self.archiveQueue)
                    self.contexts[source] = archiver
                    self.statusesDisposable[source] = (archiver.statusSignal |> deliverOn(queue)).start(next: { status in
                        statusContext.status = status
                        for subscriber in statusContext.subscribers.copyItems() {
                            subscriber(statusContext.status)
                        }
                    }, completed: {
                        subscriber.putCompletion()
                    })
                    
                    archiver.start(cancelToken: {
                        var cancelled: Bool = false
                        queue.sync {
                            cancelled = self.cancelledTokens[source] != nil
                            self.cancelledTokens.removeValue(forKey: source)
                        }
                        return cancelled
                    })
                } else {
                    for subscriber in statusContext.subscribers.copyItems() {
                        subscriber(statusContext.status)
                    }
                }
                
            }
            
            
            return ActionDisposable {
                self.queue.async {
                    if let current = self.statusContexts[source] {
                        current.subscribers.remove(index)
                    }
                }
            }
        } |> runOn(queue)
    }

}




public let archiver: ArchiverContext = ArchiverContext()
