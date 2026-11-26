
import Foundation

public struct XAttr {

    public struct Error: Swift.Error {
        public let localizedDescription = String(utf8String: strerror(errno))
    }

    public static func set(named name: String, data: Data, atPath path: String) throws {
        if setxattr(path, name, (data as NSData).bytes, data.count, 0, 0) == -1 {
            throw Error()
        }
    }

    public static func remove(named name: String, atPath path: String) throws {
        if removexattr(path, name, 0) == -1 {
            throw Error()
        }
    }

    public static func get(named name: String, atPath path: String) throws -> Data {
        let bufLength = getxattr(path, name, nil, 0, 0, 0)

        guard bufLength != -1 else {
            throw Error()
        }
        var data = Data(count: bufLength)
        let readLength = data.withUnsafeMutableBytes { buffer in
            getxattr(path, name, buffer.baseAddress, bufLength, 0, 0)
        }
        guard readLength != -1 else {
            throw Error()
        }
        if readLength < bufLength {
            data.count = readLength
        }
        return data
    }

}
