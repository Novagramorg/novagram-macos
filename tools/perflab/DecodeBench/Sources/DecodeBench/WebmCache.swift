import Foundation
import Compression

func webmCache(_ options: Options) {
    let files = Array(loadList(options).prefix(options.concurrent))
    guard !files.isEmpty else {
        print("no files")
        return
    }
    let side = options.side
    let bufferSize = side * side * 4
    let cachePath = NSTemporaryDirectory() + "webm-cache-bench.bin"
    FileManager.default.createFile(atPath: cachePath, contents: nil)
    let writer = FileHandle(forWritingAtPath: cachePath)!
    var index: [[(offset: Int, length: Int)]] = []
    var offset = 0
    let scratch = malloc(compression_encode_scratch_buffer_size(COMPRESSION_LZFSE))!
    let encoded = malloc(bufferSize * 2)!.assumingMemoryBound(to: UInt8.self)
    var decodeFrames = 0
    let buildStart = cpuTime()
    for path in files {
        let source = SoftwareVideoSource(path: path, hintVP9: true, unpremultiplyAlpha: true, reusePixelBuffers: false)
        var previous: Data?
        var entries: [(Int, Int)] = []
        for _ in 0 ..< options.frames {
            let (frame, _, _, loop) = source.readFrame(maxPts: nil)
            guard let frame = frame, var data = scaledFrame(frame, side: side) else {
                break
            }
            decodeFrames += 1
            let current = data
            if let previous = previous {
                data.withUnsafeMutableBytes { bytes in
                    previous.withUnsafeBytes { prev in
                        let a = bytes.baseAddress!.assumingMemoryBound(to: UInt64.self)
                        let b = prev.baseAddress!.assumingMemoryBound(to: UInt64.self)
                        for i in 0 ..< bufferSize / 8 { a[i] ^= b[i] }
                    }
                }
            }
            previous = current
            let length = data.withUnsafeBytes { compression_encode_buffer(encoded, bufferSize * 2, $0.baseAddress!.assumingMemoryBound(to: UInt8.self), bufferSize, scratch, COMPRESSION_LZFSE) }
            writer.write(Data(bytes: encoded, count: length))
            entries.append((offset, length))
            offset += length
            if loop {
                break
            }
        }
        index.append(entries)
    }
    writer.closeFile()
    let buildCpu = cpuTime() - buildStart
    let framesPerFile = index.map { $0.count }
    let totalFrames = framesPerFile.reduce(0, +)
    print(String(format: "cache built: %d files, %d frames, %.1f KB on disk (%.1f KB per frame at %dx%d), first loop decode + scale + delta + LZFSE encode (nil scratch after frame 0) %.3f ms/frame", files.count, totalFrames, Double(offset) / 1024, Double(offset) / 1024 / Double(max(totalFrames, 1)), side, side, buildCpu / Double(max(decodeFrames, 1)) * 1000))

    let rounds = 3
    let reader = FileHandle(forReadingAtPath: cachePath)!
    let decodeScratch = malloc(compression_decode_scratch_buffer_size(COMPRESSION_LZFSE))!
    let readBuffer = malloc(bufferSize * 2)!
    var cachedCpu = 0.0, cachedCount = 0
    for _ in 0 ..< rounds {
        let start = cpuTime()
        for entries in index {
            var previous: Data?
            for entry in entries {
                let count = pread(reader.fileDescriptor, readBuffer, entry.length, off_t(entry.offset))
                guard count == entry.length else { continue }
                let address = malloc(bufferSize)!.assumingMemoryBound(to: UInt8.self)
                _ = compression_decode_buffer(address, bufferSize, readBuffer.assumingMemoryBound(to: UInt8.self), entry.length, decodeScratch, COMPRESSION_LZFSE)
                if let previous = previous {
                    previous.withUnsafeBytes { prev in
                        let b = prev.baseAddress!.assumingMemoryBound(to: UInt64.self)
                        address.withMemoryRebound(to: UInt64.self, capacity: bufferSize / 8) { a in
                            for i in 0 ..< bufferSize / 8 { a[i] = b[i] ^ a[i] }
                        }
                    }
                }
                previous = Data(bytesNoCopy: address, count: bufferSize, deallocator: .free)
                cachedCount += 1
            }
        }
        cachedCpu += cpuTime() - start
    }

    var decodeCpu = 0.0, decodedCount = 0
    for _ in 0 ..< rounds {
        let start = cpuTime()
        for (i, path) in files.enumerated() {
            let source = SoftwareVideoSource(path: path, hintVP9: true, unpremultiplyAlpha: true, reusePixelBuffers: true)
            for _ in 0 ..< framesPerFile[i] {
                autoreleasepool {
                    let (frame, _, _, _) = source.readFrame(maxPts: nil)
                    if let frame = frame, scaledFrame(frame, side: side) != nil {
                        decodedCount += 1
                    }
                }
            }
        }
        decodeCpu += cpuTime() - start
    }
    print(String(format: "side %d: VP9 decode + scale %.3f ms/frame (%d frames), cached read + LZFSE + XOR %.3f ms/frame (%d frames), ratio %.1fx", side, decodeCpu / Double(max(decodedCount, 1)) * 1000, decodedCount, cachedCpu / Double(max(cachedCount, 1)) * 1000, cachedCount, (decodeCpu / Double(max(decodedCount, 1))) / (cachedCpu / Double(max(cachedCount, 1)))))
    try? FileManager.default.removeItem(atPath: cachePath)
}
