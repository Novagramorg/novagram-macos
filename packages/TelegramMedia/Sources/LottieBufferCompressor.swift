import Cocoa
import Compression
import Accelerate
import Postbox
import SwiftSignalKit
import TGUIKit
import ApiCredentials

private let enableDifference = false

private enum WriteResult {
    case success
    case failed
}
private enum ReadResult {
    case success(Data)
    case cached(Data, ()->Void)
    case failed
}

private var sharedData:Atomic<[LottieAnimationEntryKey:WeakReference<TRLotData>]> = Atomic(value: [:])

private struct FrameDst : Codable {
    let offset: Int
    let length: Int
    let finished: Bool
    init(offset: Int, length: Int, finished: Bool) {
        self.offset = offset
        self.length = length
        self.finished = finished
    }
}
private struct DstData : Codable {
    var dest: [Int : FrameDst]
    var fps: Int32
    var startFrame: Int32
    var endFrame: Int32
}


private let version = 70

private func decodeDstData(_ data: Data) -> DstData? {
    guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
        return nil
    }
    guard let dest = root["dest"] as? [String: Any], let fps = root["fps"] as? Int, let startFrame = root["startFrame"] as? Int, let endFrame = root["endFrame"] as? Int else {
        return nil
    }
    var result: [Int: FrameDst] = [:]
    result.reserveCapacity(dest.count)
    for (key, value) in dest {
        guard let frame = Int(key), let value = value as? [String: Any], let offset = value["offset"] as? Int, let length = value["length"] as? Int, let finished = value["finished"] as? Bool else {
            return nil
        }
        result[frame] = FrameDst(offset: offset, length: length, finished: finished)
    }
    return DstData(dest: result, fps: Int32(fps), startFrame: Int32(startFrame), endFrame: Int32(endFrame))
}

final class TRLotData {
    static let transientScratchBufferSize = 80 * 80 * 4
    
    
    fileprivate var map:DstData
    fileprivate let bufferSize: Int
    
    private let mapPath: String
    private let dataPath: String
    var isFinished: Bool = false {
        didSet {
            assert(queue.isCurrent())
            _ = finishedFlag.swap(isFinished)
            let cpy = map
            for (key, value) in cpy.dest {
                map.dest[key] = .init(offset: value.offset, length: value.length, finished: isFinished)
            }
            self.save()
            if isFinished {
                free(self.encodeScratch)
                self.encodeScratch = nil
                free(self.encodeDestination)
                self.encodeDestination = nil
            }
        }
    }
    fileprivate let finishedFlag: Atomic<Bool> = Atomic(value: false)
    
    private var readBuffer: UnsafeMutableRawPointer?
    private var readBufferCapacity: Int = 0
    private var decodeScratch: UnsafeMutableRawPointer?
    private var encodeScratch: UnsafeMutableRawPointer?
    private var encodeDestination: UnsafeMutablePointer<UInt8>?
    
    private var readHandle: FileHandle?
    private var writeHandle: FileHandle?
    private var isDirty: Bool = false
    private let key: LottieAnimationEntryKey
    fileprivate let queue: Queue
    
    fileprivate func hasAlreadyFrame(_ frame: Int) -> Bool {
        assert(queue.isCurrent())
        return map.dest[frame] != nil
    }
    fileprivate func readCompressedFrame(frame: Int) -> UnsafeRawBufferPointer? {
        
        self.writeHandle?.closeFile()
        self.writeHandle = nil
        assert(queue.isCurrent())
        
        if !isFinished {
            return nil
        }
        
        if let dest = map.dest[frame] {
            let readHande: FileHandle?
            if let handle = self.readHandle {
                readHande = handle
            } else {
                readHande = FileHandle(forReadingAtPath: self.dataPath)
                self.readHandle = readHande
            }
            
            guard let dataHandle = readHande else {
                self.map.dest.removeAll()
                self.isDirty = true
                return nil
            }
            
            if self.readBufferCapacity < max(dest.length, 1) {
                self.readBuffer = realloc(self.readBuffer, max(dest.length, 1))
                self.readBufferCapacity = max(dest.length, 1)
            }
            guard let readBuffer = self.readBuffer else {
                self.readBufferCapacity = 0
                return nil
            }
            let count = pread(dataHandle.fileDescriptor, readBuffer, dest.length, off_t(dest.offset))
            if count == dest.length {
                return UnsafeRawBufferPointer(start: readBuffer, count: dest.length)
            } else {
                self.map.dest.removeValue(forKey: frame)
                self.isDirty = true
                return nil
            }
        }
        
        return nil
    }
    
    fileprivate var decodeScratchBuffer: UnsafeMutableRawPointer? {
        assert(queue.isCurrent())
        if self.decodeScratch == nil {
            self.decodeScratch = malloc(compression_decode_scratch_buffer_size(COMPRESSION_LZFSE))
        }
        return self.decodeScratch
    }
    
    fileprivate var encodeScratchBuffer: UnsafeMutableRawPointer? {
        assert(queue.isCurrent())
        if self.encodeScratch == nil {
            self.encodeScratch = malloc(compression_encode_scratch_buffer_size(COMPRESSION_LZFSE))
        }
        return self.encodeScratch
    }
    
    fileprivate var encodeDestinationBuffer: UnsafeMutablePointer<UInt8> {
        assert(queue.isCurrent())
        if let buffer = self.encodeDestination {
            return buffer
        }
        let buffer = malloc(self.bufferSize)!.assumingMemoryBound(to: UInt8.self)
        self.encodeDestination = buffer
        return buffer
    }
    
    private func save() {
        queue.sync {
            self.isDirty = false
            let data = try? PropertyListEncoder().encode(self.map)
            if let data = data {
                _ = NSKeyedArchiver.archiveRootObject(data, toFile: self.mapPath)
            }
        }
    }
    
    deinit {
        if isDirty {
            save()
        }
        free(self.readBuffer)
        free(self.decodeScratch)
        free(self.encodeScratch)
        free(self.encodeDestination)
        _ = sharedData.modify { value in
            var value = value
            if value[self.key]?.value == nil {
                value.removeValue(forKey: self.key)
            }
            return value
        }
    }
    
    fileprivate func writeFrame(frame: Int, data:Data) -> WriteResult {
        self.readHandle?.closeFile()
        self.readHandle = nil
        assert(queue.isCurrent())
        if map.dest[frame] == nil {
            let writeHandle: FileHandle?
            if let handle = self.writeHandle {
                writeHandle = handle
            } else {
                writeHandle = FileHandle(forWritingAtPath: self.dataPath)
                self.writeHandle = writeHandle
            }
            
            guard let dataHandle = writeHandle else {
                return .failed
            }
            let fd = dataHandle.fileDescriptor
            let length = lseek(fd, 0, SEEK_END)
            if length < 0 {
                return .failed
            }
            let written = data.withUnsafeBytes { buffer -> Int in
                guard let baseAddress = buffer.baseAddress, buffer.count > 0 else {
                    return 0
                }
                var offset = 0
                while offset < buffer.count {
                    let result = Darwin.write(fd, baseAddress.advanced(by: offset), buffer.count - offset)
                    if result < 0 {
                        if errno == EINTR {
                            continue
                        }
                        return -1
                    }
                    offset += result
                }
                return offset
            }
            if written != data.count {
                ftruncate(fd, length)
                return .failed
            }
            var frames = self.map.dest
            frames[frame] = FrameDst(offset: Int(length), length: data.count, finished: isFinished)
            self.map = DstData(dest: frames, fps: self.map.fps, startFrame: self.map.startFrame, endFrame: self.map.endFrame)
            self.isDirty = true
        }

        return .success
    }
    
    
    static var directoryOverride: String?
    
    fileprivate static var directory: String {
        let path = directoryOverride ?? (ApiEnvironment.containerURL!.path + "/trlottie-animations/")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
        return path
    }
    
    
    static func mapPath(_ animation: LottieAnimation, bufferSize: Int) -> String {

        let path = TRLotData.directory + animation.cacheKey
        
        return path + "-v\(version)-lzfse-bs\(bufferSize)-lt\(animation.liveTime)-map"
    }
    
    static func dataPath(_ animation: LottieAnimation, bufferSize: Int) -> String {
        let path = TRLotData.directory + animation.cacheKey
        
        return path + "-v\(version)-lzfse-bs\(bufferSize)-lt\(animation.liveTime)-data"
    }
    
    init(_ animation: LottieAnimation, bufferSize: Int, queue: Queue) {
        self.queue = queue
        self.mapPath = TRLotData.mapPath(animation, bufferSize: bufferSize)
        self.dataPath = TRLotData.dataPath(animation, bufferSize: bufferSize)
        self.key = animation.key
        
        
        let deferr:(TRLotData)->Void = { data in
            if !FileManager.default.fileExists(atPath: data.mapPath) {
                FileManager.default.createFile(atPath: data.mapPath, contents: nil, attributes: nil)
            }
            if !FileManager.default.fileExists(atPath: data.dataPath) {
                FileManager.default.createFile(atPath: data.dataPath, contents: nil, attributes: nil)
            }
            try? FileManager.default.setAttributes([.modificationDate : Date()], ofItemAtPath: data.mapPath)
            try? FileManager.default.setAttributes([.modificationDate : Date()], ofItemAtPath: data.dataPath)

        }
        
        guard FileManager.default.isReadableFile(atPath: self.mapPath) else {
            self.map = .init(dest: [:], fps: 0, startFrame: 0, endFrame: 0)
            self.bufferSize = bufferSize
            deferr(self)
            return
        }
        
        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: self.mapPath) as? Data else {
            self.map = .init(dest: [:], fps: 0, startFrame: 0, endFrame: 0)
            self.bufferSize = bufferSize
            deferr(self)
            return
        }
        if let map = decodeDstData(data) {
            self.map = map
            self.bufferSize = bufferSize
            deferr(self)
        } else {
            do {
                self.map = try PropertyListDecoder().decode(DstData.self, from: data)
                self.bufferSize = bufferSize
                deferr(self)
            } catch {
                self.map = .init(dest: [:], fps: 0, startFrame: 0, endFrame: 0)
                self.bufferSize = bufferSize
                deferr(self)
            }
        }
        
        if !self.map.dest.isEmpty, self.map.dest.filter ({ $0.value.finished }).count == self.map.dest.count {
            self.isFinished = true
            _ = self.finishedFlag.swap(true)
        }
    }
    
    func initialize(fps: Int32, startFrame: Int32, endFrame: Int32) {
        self.map.fps = fps
        self.map.startFrame = startFrame
        self.map.endFrame = endFrame
        self.isDirty = true
    }
    
}

private let lzfseQueue = Queue(name: "LZFSE BUFFER Queue", qos: DispatchQoS.default)


enum TRLotCachedFrame {
    case decoded(Data)
    case sameAsPrevious
}

final class TRLotFileSupplyment {
    fileprivate let bufferSize: Int
    fileprivate let data:TRLotData
    fileprivate let queue: Queue
    private var lastCompressed: UnsafeMutableRawPointer?
    private var lastCompressedCapacity: Int = 0
    private var lastCompressedLength: Int = 0
    private var lastCompressedFrame: Int?
    
    deinit {
        free(self.lastCompressed)
    }
    
    init(_ animation:LottieAnimation, bufferSize: Int, queue: Queue) {
        let key = animation.key
        let data: TRLotData
        if let cached = sharedData.with({ $0[key]?.value }) {
            data = cached
        } else {
            let created = TRLotData(animation, bufferSize: bufferSize, queue: queue)
            var registered: TRLotData = created
            _ = sharedData.modify { value in
                var value = value
                if let existing = value[key]?.value {
                    registered = existing
                } else {
                    value[key] = WeakReference(value: created)
                }
                return value
            }
            data = registered
        }
        self.data = data
        self.queue = data.queue
        self.bufferSize = bufferSize
    }
    
    func initialize(fps: Int32, startFrame: Int32, endFrame: Int32) {
        queue.sync {
            self.data.initialize(fps: fps, startFrame: startFrame, endFrame: endFrame)
        }

    }
    
    var fps: Int32 {
        var fps: Int32 = 0
        queue.sync {
            fps = self.data.map.fps
        }
        return fps
    }
    var endFrame: Int32 {
        var endFrame: Int32 = 0
        queue.sync {
            endFrame = self.data.map.endFrame
        }
        return endFrame
    }
    var startFrame: Int32 {
        var startFrame: Int32 = 0
        queue.sync {
            startFrame = self.data.map.startFrame
        }
        return startFrame
    }

    func markFinished() {
        _ = self.data.finishedFlag.swap(true)
        queue.async {
            if !self.data.isFinished {
                self.data.isFinished = true
            }
        }
    }
    var isFinished: Bool {
        return self.data.finishedFlag.with { $0 }
    }
    

    
    func addFrame(_ previous: Data?, _ current: (Data, Int32)) {
        queue.async {
            
            if !self.data.hasAlreadyFrame(Int(current.1)) {
                current.0.withUnsafeBytes { pointer in
                    let address = pointer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let ui64Address = pointer.baseAddress!.assumingMemoryBound(to: UInt64.self)
                    let dst: UnsafeMutablePointer<UInt8> = self.data.encodeDestinationBuffer
                    var length:Int = self.bufferSize
                    if let previous = previous, enableDifference {
                        let uint64Bs = self.bufferSize / 8
                        let dstDelta: UnsafeMutablePointer<UInt8> = malloc(self.bufferSize)!.assumingMemoryBound(to: UInt8.self)
                        
                        previous.withUnsafeBytes { pointer in
                            memcpy(dstDelta, pointer.baseAddress!.assumingMemoryBound(to: UInt8.self), self.bufferSize)
                            
                            let ui64Dst = dstDelta.withMemoryRebound(to: UInt64.self, capacity: uint64Bs, { previousBytes in
                                return previousBytes
                            })
                            
                            var i: Int = 0
                            while i < uint64Bs {
                                ui64Dst[i] = ui64Dst[i] ^ ui64Address[i]
                                i &+= 1
                            }
                            
                            let ui8 = ui64Dst.withMemoryRebound(to: UInt8.self, capacity: self.bufferSize, { body in
                                return body
                            })
                            
                            length = compression_encode_buffer(dst, self.bufferSize, ui8, self.bufferSize, nil, COMPRESSION_LZFSE)
                            dstDelta.deallocate()
                        }
                        
                        
                    } else {
                        let scratch = self.bufferSize <= TRLotData.transientScratchBufferSize ? nil : self.data.encodeScratchBuffer
                        length = compression_encode_buffer(dst, self.bufferSize, address, self.bufferSize, scratch, COMPRESSION_LZFSE)
                    }
                    let _ = self.data.writeFrame(frame: Int(current.1), data: Data(bytes: dst, count: length))
                }
            }
        }
    }


    func readFrame(previous: Data?, frame: Int) -> Data? {
        switch self.readFrame(previous: previous, frame: frame, previousFrame: nil) {
        case let .decoded(data):
            return data
        case .sameAsPrevious, .none:
            return nil
        }
    }
    
    func readFrame(previous: Data?, frame: Int, previousFrame: Int?) -> TRLotCachedFrame? {
        if !self.data.finishedFlag.with({ $0 }) {
            return nil
        }
        var rendered: TRLotCachedFrame? = nil
        queue.sync {
            
            if self.data.isFinished {
                if let compressed = self.data.readCompressedFrame(frame: frame) {
                    let isSameAsPrevious = previousFrame != nil && previousFrame == self.lastCompressedFrame && compressed.count == self.lastCompressedLength && (compressed.count == 0 || memcmp(compressed.baseAddress!, self.lastCompressed!, compressed.count) == 0)
                    if self.lastCompressedCapacity < max(compressed.count, 1) {
                        self.lastCompressed = realloc(self.lastCompressed, max(compressed.count, 1))
                        self.lastCompressedCapacity = max(compressed.count, 1)
                    }
                    if let lastCompressed = self.lastCompressed, let baseAddress = compressed.baseAddress, compressed.count > 0 {
                        memcpy(lastCompressed, baseAddress, compressed.count)
                    }
                    self.lastCompressedLength = compressed.count
                    self.lastCompressedFrame = frame
                    if isSameAsPrevious {
                        rendered = .sameAsPrevious
                        return
                    }
                    let address = malloc(bufferSize)!.assumingMemoryBound(to: UInt8.self)
                    do {
                        let unsafePointer = compressed.baseAddress!.assumingMemoryBound(to: UInt8.self)

                        let _ = compression_decode_buffer(address, bufferSize, unsafePointer, compressed.count, self.data.decodeScratchBuffer, COMPRESSION_LZFSE)

                        if let previous = previous, enableDifference {
                            previous.withUnsafeBytes { pointer in
                                let previousBytes = pointer.baseAddress!.assumingMemoryBound(to: UInt64.self)
                                let uint64Bs = self.bufferSize / 8
                                address.withMemoryRebound(to: UInt64.self, capacity: uint64Bs, { address in
                                    var i = 0
                                    while i < uint64Bs {
                                        address[i] = previousBytes[i] ^ address[i]
                                        i &+= 1
                                    }
                                })
                            }
                        }
                    }
                    rendered = .decoded(Data(bytesNoCopy: address, count: bufferSize, deallocator: .free))
                } else {
                    self.lastCompressedFrame = nil
                }
            }
        }
        return rendered
    }
    
    
}




private final class CacheRemovable {
    init() {
       
    }
    
    fileprivate func start() {
        let signal = Signal<Void, NoError>.single(Void()) |> deliverOn(lzfseQueue) |> then (Signal<Void, NoError>.single(Void()) |> delay(30 * 60, queue: lzfseQueue) |> restart)
        
        
        _ = signal.start(next: {
            self.clean()
        })
    }
    
    private func clean() {
        
        let fileURLs = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: TRLotData.directory), includingPropertiesForKeys: nil, options: .skipsHiddenFiles )
        if let fileURLs = fileURLs {
            for url in fileURLs {
                let path = url.path
                let name = path.nsstring.lastPathComponent
                if let index = name.range(of: "-lt", options: .backwards) {
                    let tail = String(name[index.upperBound...])
                    if let until = tail.range(of: "-") {
                        if let liveTime = TimeInterval(tail[..<until.lowerBound]) {
                            if let createdAt = FileManager.default.modificationDateForFileAtPath(path: path), createdAt.timeIntervalSince1970 + liveTime < Date().timeIntervalSince1970 {
                                try? FileManager.default.removeItem(at: url)
                            }
                            continue
                        }
                    }
                }
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        
    }
    
}
private let cleaner = CacheRemovable()

public func startLottieCacheCleaner() {
    cleaner.start()
}


