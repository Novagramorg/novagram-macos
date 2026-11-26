import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramUtils


public class ComposeState<T> {
    public let result:T
    public init(_ result:T) {
        self.result = result
    }
}

open class EmptyComposeController<I,T,R,Context>: TelegramGenericViewController<R, Context> where R:NSView, Context: AccountContextProtocol {
    public let onChange:Promise<T> = Promise()
    public let onComplete:Promise<T> = Promise()
    public let onCancel:Promise<Void> = Promise()
    public var previousResult:ComposeState<I>? = nil
    open func restart(with result:ComposeState<I>) {
        self.previousResult = result
    }
    
}
