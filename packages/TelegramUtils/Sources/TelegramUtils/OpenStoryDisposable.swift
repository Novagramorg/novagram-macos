import Foundation
import SwiftSignalKit

private let globalStoryDisposable = MetaDisposable()

public func SetOpenStoryDisposable(_ disposable: Disposable?) {
    globalStoryDisposable.set(disposable)
}
