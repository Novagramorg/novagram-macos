import Foundation
import AVFoundation
import CoreImage
import CoreMedia
import VideoToolbox
import AppKit
import Accelerate

struct Options {
    var command = ""
    var input = ""
    var output = ""
    var mode = "sw"
    var concurrent = 12
    var frames = 250
    var threads = 3
    var limit = 1000
    var snapshots: String?
    var strip = false
    var side = 60

    static func parse() -> Options {
        var options = Options()
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty else {
            return options
        }
        options.command = arguments.removeFirst()
        while !arguments.isEmpty {
            let name = arguments.removeFirst()
            let value = arguments.isEmpty ? "" : arguments.removeFirst()
            switch name {
            case "--input": options.input = value
            case "--output": options.output = value
            case "--mode": options.mode = value
            case "--concurrent": options.concurrent = Int(value) ?? options.concurrent
            case "--frames": options.frames = Int(value) ?? options.frames
            case "--threads": options.threads = Int(value) ?? options.threads
            case "--limit": options.limit = Int(value) ?? options.limit
            case "--snapshots": options.snapshots = value
            case "--strip": options.strip = value == "1"
            case "--side": options.side = Int(value) ?? options.side
            default:
                print("unknown argument \(name)")
                exit(1)
            }
        }
        return options
    }
}

func cpuTime() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6 + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
}

func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1048576.0 : -1
}

func fourCC(_ value: FourCharCode) -> String {
    let bytes = [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    return String(bytes: bytes, encoding: .ascii) ?? "\(value)"
}

func scan(_ options: Options) {
    let directory = URL(fileURLWithPath: options.input)
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".mp4") }.sorted { (Int($0.dropLast(4)) ?? 0) < (Int($1.dropLast(4)) ?? 0) }
    var selected: [String] = []
    var codecs: [String: Int] = [:]
    var colorTags: [String: Int] = [:]
    var sizes: [String] = []
    for name in files {
        let url = directory.appendingPathComponent(name)
        let asset = AVURLAsset(url: url)
        let video = asset.tracks(withMediaType: .video)
        let audio = asset.tracks(withMediaType: .audio)
        guard let track = video.first else {
            continue
        }
        let duration = CMTimeGetSeconds(asset.duration)
        guard audio.isEmpty, duration > 0, duration <= 30 else {
            continue
        }
        var codec = "?"
        if let description = (track.formatDescriptions as? [CMFormatDescription])?.first {
            codec = fourCC(CMFormatDescriptionGetMediaSubType(description))
            let matrix = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String ?? "unspecified"
            let primaries = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String ?? "unspecified"
            let fullRange = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_FullRangeVideo) as? Bool ?? false
            colorTags["\(matrix)/\(primaries)\(fullRange ? "/full" : "")", default: 0] += 1
        }
        codecs[codec, default: 0] += 1
        let size = track.naturalSize
        sizes.append("\(Int(size.width))x\(Int(size.height))@\(Int(track.nominalFrameRate.rounded()))")
        selected.append(url.path)
    }
    try? selected.joined(separator: "\n").write(toFile: options.output, atomically: true, encoding: .utf8)
    print("files \(files.count), gif-like \(selected.count), codecs \(codecs)")
    print("color tags \(colorTags)")
    let counted = Dictionary(sizes.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.value > $1.value }.prefix(12)
    print("common sizes \(counted.map { "\($0.key) x\($0.value)" }.joined(separator: ", "))")
}

func loadList(_ options: Options) -> [String] {
    let list = ((try? String(contentsOfFile: options.input, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    return Array(list.prefix(options.limit))
}

final class Worker {
    var sources: [(SoftwareVideoSource, String)] = []
    var decoded = 0
    var empty = 0
    var maxPts: [CMTime?] = []
}

func decode(_ options: Options) {
    let files = loadList(options)
    guard !files.isEmpty else {
        print("no files")
        return
    }
    let hardware = options.mode == "hw"
    let footprintStart = footprintMB()
    let openStart = CFAbsoluteTimeGetCurrent()
    let cpuOpenStart = cpuTime()
    var workers = (0 ..< options.threads).map { _ in Worker() }
    var unopened = 0
    for index in 0 ..< options.concurrent {
        let path = files[index % files.count]
        let source = SoftwareVideoSource(path: path, hintVP9: false, unpremultiplyAlpha: true, useHardwareAcceleration: hardware)
        if !source.hasStream {
            unopened += 1
        }
        workers[index % options.threads].sources.append((source, path))
        workers[index % options.threads].maxPts.append(nil)
    }
    let openWall = CFAbsoluteTimeGetCurrent() - openStart
    let openCpu = cpuTime() - cpuOpenStart

    let start = CFAbsoluteTimeGetCurrent()
    let cpuStart = cpuTime()
    let group = DispatchGroup()
    for worker in workers {
        group.enter()
        let thread = Thread {
            for _ in 0 ..< options.frames {
                for i in 0 ..< worker.sources.count {
                    autoreleasepool {
                        let (frame, _, _, loop) = worker.sources[i].0.readFrame(maxPts: worker.maxPts[i])
                        if let frame = frame {
                            worker.decoded += 1
                            if loop {
                                worker.maxPts[i] = CMTimeAdd(frame.position, frame.duration)
                            }
                        } else {
                            worker.empty += 1
                        }
                    }
                }
            }
            group.leave()
        }
        thread.qualityOfService = .utility
        thread.start()
    }
    group.wait()
    let wall = CFAbsoluteTimeGetCurrent() - start
    let cpu = cpuTime() - cpuStart
    let footprintPlaying = footprintMB()
    let decoded = workers.reduce(0) { $0 + $1.decoded }
    let empty = workers.reduce(0) { $0 + $1.empty }
    workers = []
    print(String(format: "mode=%@ gifs=%d threads=%d frames=%d decoded=%d empty=%d unopened=%d | wall %.2fs cpu %.2fs | cpu/frame %.3f ms | %.0f fps total | open %.0f ms wall %.0f ms cpu", options.mode as NSString, options.concurrent, options.threads, options.frames, decoded, empty, unopened, wall, cpu, decoded > 0 ? cpu / Double(decoded) * 1000 : 0, Double(decoded) / wall, openWall * 1000, openCpu * 1000) + String(format: " | footprint +%.0f MB while playing, +%.0f MB after release", footprintPlaying - footprintStart, footprintMB() - footprintStart))
}

var stripColorAttachments = false
var printedSurfaceValues = false
let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB(), .outputColorSpace: CGColorSpaceCreateDeviceRGB()])

func render(_ sampleBuffer: CMSampleBuffer) -> (CGImage, [UInt8], OSType, String)? {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        return nil
    }
    if stripColorAttachments {
        if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
            if !printedSurfaceValues && CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, nil) != nil {
                printedSurfaceValues = true
                print("surface values before: \(String(describing: IOSurfaceCopyAllValues(surface)))")
                print("buffer attachments before: \(String(describing: CVBufferCopyAttachments(pixelBuffer, .shouldPropagate)))")
            }
            for key in ["IOSurfaceYCbCrMatrix", "IOSurfaceColorPrimaries", "IOSurfaceTransferFunction", "IOSurfaceColorSpace", "IOSurfaceICCProfile"] {
                IOSurfaceRemoveValue(surface, key as CFString)
            }
        }
        CVBufferRemoveAllAttachments(pixelBuffer)
    }
    let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let matrix = (CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, nil)?.takeUnretainedValue() as? String) ?? "none"
    let image = CIImage(cvPixelBuffer: pixelBuffer)
    guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
        return nil
    }
    let width = cgImage.width
    let height = cgImage.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (cgImage, pixels, format, matrix)
}

func comparePlanes(_ first: CMSampleBuffer, _ second: CMSampleBuffer) -> (maxY: Int, maxUV: Int, meanY: Double) {
    guard let a = CMSampleBufferGetImageBuffer(first), let b = CMSampleBufferGetImageBuffer(second) else {
        return (-1, -1, -1)
    }
    CVPixelBufferLockBaseAddress(a, .readOnly)
    CVPixelBufferLockBaseAddress(b, .readOnly)
    defer {
        CVPixelBufferUnlockBaseAddress(a, .readOnly)
        CVPixelBufferUnlockBaseAddress(b, .readOnly)
    }
    var result: [Int] = []
    var meanY = 0.0
    for plane in 0 ..< 2 {
        let width = min(CVPixelBufferGetWidthOfPlane(a, plane), CVPixelBufferGetWidthOfPlane(b, plane)) * (plane == 0 ? 1 : 2)
        let height = min(CVPixelBufferGetHeightOfPlane(a, plane), CVPixelBufferGetHeightOfPlane(b, plane))
        guard let baseA = CVPixelBufferGetBaseAddressOfPlane(a, plane)?.assumingMemoryBound(to: UInt8.self), let baseB = CVPixelBufferGetBaseAddressOfPlane(b, plane)?.assumingMemoryBound(to: UInt8.self) else {
            return (-1, -1, -1)
        }
        let strideA = CVPixelBufferGetBytesPerRowOfPlane(a, plane)
        let strideB = CVPixelBufferGetBytesPerRowOfPlane(b, plane)
        var maxDiff = 0
        var sum = 0
        for y in 0 ..< height {
            for x in 0 ..< width {
                let diff = abs(Int(baseA[y * strideA + x]) - Int(baseB[y * strideB + x]))
                maxDiff = max(maxDiff, diff)
                sum += diff
            }
        }
        if plane == 0 {
            meanY = Double(sum) / Double(max(1, width * height))
        }
        result.append(maxDiff)
    }
    return (result[0], result[1], meanY)
}

func frame(at index: Int, path: String, hardware: Bool) -> CMSampleBuffer? {
    let source = SoftwareVideoSource(path: path, hintVP9: false, unpremultiplyAlpha: true, useHardwareAcceleration: hardware)
    var result: CMSampleBuffer?
    var produced = 0
    for _ in 0 ..< index * 4 + 40 {
        let (frame, _, _, _) = source.readFrame(maxPts: nil)
        if let frame = frame {
            if produced == index {
                result = frame.sampleBuffer
                break
            }
            produced += 1
        }
    }
    return result
}

func writePNG(_ image: CGImage, to path: String) {
    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

func compare(_ options: Options) {
    let files = loadList(options)
    var worstMax = 0
    var meanSum = 0.0
    var compared = 0
    var failures = 0
    for (index, path) in files.enumerated() {
        let frameIndex = 12
        guard let software = frame(at: frameIndex, path: path, hardware: false), let hardware = frame(at: frameIndex, path: path, hardware: true) else {
            failures += 1
            print("\(index): could not decode frame \(frameIndex) in both modes")
            continue
        }
        let ptsA = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(software))
        let ptsB = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(hardware))
        let planes = comparePlanes(software, hardware)
        if index < 8 || planes.maxY > 2 {
            print(String(format: "%d: pts sw=%.3f hw=%.3f planes maxY=%d maxUV=%d meanY=%.3f", index, ptsA, ptsB, planes.maxY, planes.maxUV, planes.meanY))
        }
        guard let a = render(software), let b = render(hardware), a.1.count == b.1.count else {
            failures += 1
            print("\(index): size mismatch")
            continue
        }
        var maxDiff = 0
        var sum = 0
        for i in 0 ..< a.1.count where i % 4 != 3 {
            let diff = abs(Int(a.1[i]) - Int(b.1[i]))
            maxDiff = max(maxDiff, diff)
            sum += diff
        }
        let mean = Double(sum) / Double(a.1.count / 4 * 3)
        worstMax = max(worstMax, maxDiff)
        meanSum += mean
        compared += 1
        if index < 8 || mean > 1.0 {
            print(String(format: "%d: %dx%d sw=%@/%@ hw=%@/%@ max=%d mean=%.3f", index, a.0.width, a.0.height, fourCC(a.2) as NSString, a.3 as NSString, fourCC(b.2) as NSString, b.3 as NSString, maxDiff, mean))
        }
        if let directory = options.snapshots, index < 6 {
            writePNG(a.0, to: "\(directory)/\(index)-sw.png")
            writePNG(b.0, to: "\(directory)/\(index)-hw.png")
        }
    }
    print(String(format: "compared %d, failures %d, worst channel difference %d, average mean difference %.3f", compared, failures, worstMax, compared > 0 ? meanSum / Double(compared) : 0))
}

func sequence(_ options: Options) {
    let files = loadList(options)
    var mismatchedFiles = 0
    var totalFrames = 0
    for (index, path) in files.enumerated() {
        let software = SoftwareVideoSource(path: path, hintVP9: false, unpremultiplyAlpha: true, useHardwareAcceleration: false)
        let hardware = SoftwareVideoSource(path: path, hintVP9: false, unpremultiplyAlpha: true, useHardwareAcceleration: true)
        var maxPtsA: CMTime?
        var maxPtsB: CMTime?
        var mismatch: String?
        for step in 0 ..< options.frames {
            let a = software.readFrame(maxPts: maxPtsA)
            let b = hardware.readFrame(maxPts: maxPtsB)
            if (a.0 == nil) != (b.0 == nil) || a.3 != b.3 {
                mismatch = "step \(step): presence/loop differs sw=\(a.0 != nil)/\(a.3) hw=\(b.0 != nil)/\(b.3)"
                break
            }
            if let fa = a.0, let fb = b.0 {
                totalFrames += 1
                if CMTimeCompare(fa.position, fb.position) != 0 || CMTimeCompare(fa.duration, fb.duration) != 0 {
                    mismatch = "step \(step): pts sw=\(CMTimeGetSeconds(fa.position)) hw=\(CMTimeGetSeconds(fb.position))"
                    break
                }
                let planes = comparePlanes(fa.sampleBuffer, fb.sampleBuffer)
                if planes.maxY != 0 || planes.maxUV != 0 {
                    mismatch = "step \(step): planes differ maxY=\(planes.maxY) maxUV=\(planes.maxUV)"
                    break
                }
                if a.3 {
                    maxPtsA = CMTimeAdd(fa.position, fa.duration)
                }
                if b.3 {
                    maxPtsB = CMTimeAdd(fb.position, fb.duration)
                }
            }
        }
        if let mismatch {
            mismatchedFiles += 1
            print("\(index): \(mismatch)")
        }
    }
    print("files \(files.count), frames compared \(totalFrames), files with any difference \(mismatchedFiles)")
}

func scaledFrame(_ frame: MediaTrackFrame, side: Int) -> Data? {
    let bytesPerRow = side * 4
    var data = Data(count: side * bytesPerRow)
    let ok = data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) -> Bool in
        guard let base = bytes.baseAddress, let imageBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer) else {
            return false
        }
        CVPixelBufferLockBaseAddress(imageBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(imageBuffer, [])
        }
        guard let source = CVPixelBufferGetBaseAddress(imageBuffer) else {
            return false
        }
        var sourceBuffer = vImage_Buffer(data: source, height: vImagePixelCount(CVPixelBufferGetHeight(imageBuffer)), width: vImagePixelCount(CVPixelBufferGetWidth(imageBuffer)), rowBytes: CVPixelBufferGetBytesPerRow(imageBuffer))
        var destination = vImage_Buffer(data: base, height: vImagePixelCount(side), width: vImagePixelCount(side), rowBytes: bytesPerRow)
        return vImageScale_ARGB8888(&sourceBuffer, &destination, nil, vImage_Flags(kvImageDoNotTile)) == kvImageNoError
    }
    return ok ? data : nil
}

func webm(_ options: Options) {
    let files = loadList(options)
    guard !files.isEmpty else {
        print("no files")
        return
    }
    let reuse = options.mode == "pool"
    let footprintStart = footprintMB()
    var workers = (0 ..< options.threads).map { _ in Worker() }
    for index in 0 ..< options.concurrent {
        let path = files[index % files.count]
        let source = SoftwareVideoSource(path: path, hintVP9: true, unpremultiplyAlpha: true, reusePixelBuffers: reuse)
        workers[index % options.threads].sources.append((source, path))
        workers[index % options.threads].maxPts.append(nil)
    }
    let start = CFAbsoluteTimeGetCurrent()
    let cpuStart = cpuTime()
    let group = DispatchGroup()
    for worker in workers {
        group.enter()
        let thread = Thread {
            for _ in 0 ..< options.frames {
                for i in 0 ..< worker.sources.count {
                    autoreleasepool {
                        let (frame, _, _, _) = worker.sources[i].0.readFrame(maxPts: nil)
                        if let frame = frame, scaledFrame(frame, side: options.side) != nil {
                            worker.decoded += 1
                        } else {
                            worker.empty += 1
                        }
                    }
                }
            }
            group.leave()
        }
        thread.qualityOfService = .utility
        thread.start()
    }
    group.wait()
    let wall = CFAbsoluteTimeGetCurrent() - start
    let cpu = cpuTime() - cpuStart
    let decoded = workers.reduce(0) { $0 + $1.decoded }
    let empty = workers.reduce(0) { $0 + $1.empty }
    print(String(format: "webm mode=%@ files=%d side=%d frames=%d decoded=%d empty=%d | wall %.2fs cpu %.2fs | cpu/frame %.3f ms | footprint +%.0f MB", options.mode as NSString, options.concurrent, options.side, options.frames, decoded, empty, wall, cpu, decoded > 0 ? cpu / Double(decoded) * 1000 : 0, footprintMB() - footprintStart))
}

func webmSequence(_ options: Options) {
    let files = loadList(options)
    var differing = 0
    var compared = 0
    for (index, path) in files.enumerated() {
        let plain = SoftwareVideoSource(path: path, hintVP9: true, unpremultiplyAlpha: true, reusePixelBuffers: false)
        let pooled = SoftwareVideoSource(path: path, hintVP9: true, unpremultiplyAlpha: true, reusePixelBuffers: true)
        var held: [MediaTrackFrame] = []
        for step in 0 ..< options.frames {
            let a = plain.readFrame(maxPts: nil)
            let b = pooled.readFrame(maxPts: nil)
            if (a.0 == nil) != (b.0 == nil) || a.3 != b.3 {
                differing += 1
                print("\(index): step \(step) presence or loop differs")
                break
            }
            guard let fa = a.0, let fb = b.0 else {
                continue
            }
            if step % 3 == 0 {
                held.append(fb)
                if held.count > 4 {
                    held.removeFirst()
                }
            }
            compared += 1
            if CMTimeCompare(fa.position, fb.position) != 0 || scaledFrame(fa, side: options.side) != scaledFrame(fb, side: options.side) {
                differing += 1
                print("\(index): step \(step) frame content differs")
                break
            }
        }
    }
    print("webm sequence files \(files.count), frames compared \(compared), files with any difference \(differing)")
}

let options = Options.parse()
stripColorAttachments = options.strip
switch options.command {
case "scan":
    scan(options)
case "decode":
    decode(options)
case "compare":
    compare(options)
case "sequence":
    sequence(options)
case "webm":
    webm(options)
case "webm-sequence":
    webmSequence(options)
case "webm-cache":
    webmCache(options)
default:
    print("usage: DecodeBench scan --input dir --output list.txt | decode --input list.txt --mode sw|hw [--concurrent 12 --frames 250 --threads 3] | compare --input list.txt [--snapshots dir]")
}
