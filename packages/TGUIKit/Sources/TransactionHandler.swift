import Cocoa

public class TransactionHandler: NSObject {

    private var lock: OSSpinLock = 0

    private var handler:(() ->Void)?
    
    public func set(handler:(() ->Void)?) -> Void {
        OSSpinLockLock(&self.lock)
        self.handler = handler
        OSSpinLockUnlock(&self.lock)
    }
    
    public var isExutable:Bool {
        return handler != nil
    }
    
    public func execute() -> Bool {
        OSSpinLockLock(&self.lock)
        let success = handler != nil
        if let handler = handler {
            handler()
            self.handler = nil
        }
        OSSpinLockUnlock(&self.lock)
        return success
    }
    
}
