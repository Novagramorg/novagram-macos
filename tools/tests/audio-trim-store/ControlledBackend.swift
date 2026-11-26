import Foundation

public class TGDataItem {
    private var bytes = Data()
    public init() {}
    public func appendData(_ data: Data!) { bytes.append(data) }
    public func data() -> Data { bytes }
    public func replaceData(_ data: Data!) -> Bool { guard let data else { return false }; bytes = data; return true }
}
enum Backend {
    static var samples = 96000, readErrorAt: Int?, unavailable = false, beginOK = true, appendOK = true, frameOK = true, finalizeOK = true, damageOutput = false
    static var duration: Double = 2
    static var readers = 0, writers = 0
    static func reset() { samples = 96000; readErrorAt = nil; unavailable = false; beginOK = true; appendOK = true; frameOK = true; finalizeOK = true; damageOutput = false; duration = 2; readers = 0; writers = 0 }
}
final class OggOpusReader {
    var cursor = 0
    init?(path: String) { Backend.readers += 1; if Backend.unavailable { return nil } }
    func read(_ pointer: UnsafeMutableRawPointer, bufSize: Int32) -> Int32 {
        if let error = Backend.readErrorAt, cursor >= error { return -1 }
        let count = min(Int(bufSize), max(0, Backend.samples-cursor))
        pointer.assumingMemoryBound(to: Int16.self).initialize(repeating: 1234, count: count)
        cursor += count
        return Int32(count)
    }
}
final class TGOggOpusWriter {
    var item: DataItem?
    init() { Backend.writers += 1 }
    func begin(with item: DataItem) -> Bool { self.item = item; if Backend.beginOK { item.appendData(Data("header".utf8)) }; return Backend.beginOK }
    func beginAppend(with item: DataItem) -> Bool { self.item = item; return Backend.appendOK }
    func writeFrame(_ pointer: UnsafeMutablePointer<UInt8>?, frameByteCount: UInt) -> Bool {
        let success = pointer == nil ? Backend.finalizeOK : Backend.frameOK
        if success { item?.appendData(Data(repeating: 42, count: pointer == nil ? 4 : 2)) }
        if Backend.damageOutput, let path = item?.path { try? Data("broken".utf8).write(to: URL(fileURLWithPath: path)) }
        return success
    }
    func resume(with item: DataItem, encoderState: [AnyHashable:Any]) -> Bool { self.item = item; return true }
    func encodedDuration() -> Double { Backend.duration }
    func pause() -> [AnyHashable:Any] { ["paused":true] }
}
