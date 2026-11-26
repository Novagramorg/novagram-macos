import Foundation

public extension NSData {
    
    var hexString: String {
        let buf = bytes.assumingMemoryBound(to: UInt8.self)
        let charA = UInt8(UnicodeScalar("a").value)
        let char0 = UInt8(UnicodeScalar("0").value)
        
        func itoh(_ value: UInt8) -> UInt8 {
            return (value > 9) ? (charA + value - 10) : (char0 + value)
        }
        
        let hexLen = length * 2
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: hexLen)
        
        for i in 0 ..< length {
            ptr[i*2] = itoh((buf[i] >> 4) & 0xF)
            ptr[i*2+1] = itoh(buf[i] & 0xF)
        }
        
        return String(bytesNoCopy: ptr, length: hexLen, encoding: .utf8, freeWhenDone: true)!
    }
}
