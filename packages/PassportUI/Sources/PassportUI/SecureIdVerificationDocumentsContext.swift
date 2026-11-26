import Foundation
import TelegramCore

import SwiftSignalKit
import SecureIdUtils

private final class DocumentContext {
    private let disposable: Disposable
    
    public init(disposable: Disposable) {
        self.disposable = disposable
    }
    
    deinit {
        self.disposable.dispose()
    }
}

public final class SecureIdVerificationDocumentsContext {
    private let context: SecureIdAccessContext
    private let engine: TelegramEngine
    private let update: (Int64, SecureIdVerificationLocalDocumentState) -> Void
    private var contexts: [Int64: DocumentContext] = [:]

    public init(engine: TelegramEngine, context: SecureIdAccessContext, update: @escaping (Int64, SecureIdVerificationLocalDocumentState) -> Void) {
        self.engine = engine
        self.context = context
        self.update = update
    }

    public func stateUpdated(_ documents: [SecureIdVerificationDocument]) {
        var validIds = Set<Int64>()

        for document in documents {
            switch document {
                case let .local(info):
                    validIds.insert(info.id)
                    if self.contexts[info.id] == nil {
                        let disposable = MetaDisposable()
                        self.contexts[info.id] = DocumentContext(disposable: disposable)
                        disposable.set((uploadSecureIdFile(context: self.context, engine: self.engine, resource: EngineMediaResource(info.resource))
                        |> deliverOnMainQueue).start(next: { [weak self] result in
                            if let strongSelf = self {
                                switch result {
                                    case let .progress(value):
                                        if strongSelf.contexts[info.id] != nil {
                                            strongSelf.update(info.id, .uploading(value))
                                        }
                                    case let .result(file, _):
                                        if strongSelf.contexts[info.id] != nil {
                                            strongSelf.update(info.id, .uploaded(file))
                                        }
                                }
                            }
                        }, error: { [weak self] _ in
                            if self != nil {
                                
                            }
                        }))
                    }
                case .remote:
                    break
            }
        }
        
        var removeIds: [Int64] = []
        for (id, _) in self.contexts {
            if !validIds.contains(id) {
                removeIds.append(id)
            }
        }
        for id in removeIds {
            self.contexts.removeValue(forKey: id)
        }
    }
}
