import Cocoa

public class WeakReference<T> where T:AnyObject {
    
    public private(set) weak var value:T?
    
    public init(value:T?) {
        self.value = value
    }
}

