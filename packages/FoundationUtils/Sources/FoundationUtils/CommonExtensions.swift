import Foundation
import CoreGraphics

public func synced(_ lock: Any, closure: ()->Void) {
    objc_sync_enter(lock)
    closure()
    objc_sync_exit(lock)
}

public extension Double {
    
    func toString(decimal: Int = 9) -> String {
        let value = decimal < 0 ? 0 : decimal
        var string = String(format: "%.\(value)f", self)
        
        while string.last == "0" || string.last == "." {
            if string.last == "." { string = String(string.dropLast()); break}
            string = String(string.dropLast())
        }
        return string
    }
}

public extension String {
    func rightJustified(width: Int, pad: String = " ", truncate: Bool = false) -> String {
        guard width > count else {
            return truncate ? String(suffix(width)) : self
        }
        return String(repeating: pad, count: width - count) + self
    }
    
    func leftJustified(width: Int, pad: String = " ", truncate: Bool = false) -> String {
        guard width > count else {
            return truncate ? String(prefix(width)) : self
        }
        return self + String(repeating: pad, count: width - count)
    }
}

public func freeSystemGigabytes() -> UInt64? {
    let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/")
    
    if let freeBytes = attrs?[FileAttributeKey.systemFreeSize] as? UInt64 {
        return freeBytes / 1073741824
    }
    return nil
}

public extension Int32 {
    static var secondsInDay: Int32 {
        return 60 * 60 * 24
    }
    static var secondsInWeek: Int32 {
        return secondsInDay * 7
    }
    static var secondsInMonth: Int32 {
        return secondsInDay * 31
    }
}
