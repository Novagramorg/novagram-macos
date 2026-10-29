import AVFoundation
import CoreMedia

// Mixes the call's two audio sources (the app's output = the other side, the microphone = us) into one
// 48 kHz stereo Float32 timeline. Positions come from each buffer's presentation time; used on one serial queue.
final class NovagramCallAudioMixer {
    enum Source: Hashable {
        case app
        case microphone
    }

    static let sampleRate: Double = 48000
    private static let channels = 2
    private static let clockMismatchSeconds: Double = 1.0
    private static let maxLeadSeconds: Double = 5.0
    private static let converterSlackFrames: AVAudioFrameCount = 64

    let formatDescription: CMAudioFormatDescription?
    private var samples: [Float] = []
    private var baseFrame: Int64 = 0
    private var converters: [Source: (format: AVAudioFormat, converter: AVAudioConverter)] = [:]
    private var clockOffsets: [Source: Double] = [:]

    init() {
        var description = AudioStreamBasicDescription(
            mSampleRate: NovagramCallAudioMixer.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size * NovagramCallAudioMixer.channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size * NovagramCallAudioMixer.channels),
            mChannelsPerFrame: UInt32(NovagramCallAudioMixer.channels),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        self.formatDescription = format
    }

    func add(_ sampleBuffer: CMSampleBuffer, source: Source, start: Double, now: Double) {
        guard let frames = stereoSamples(sampleBuffer, source: source), !frames.isEmpty else {
            return
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard pts.isFinite else {
            return
        }
        let duration = Double(frames.count / NovagramCallAudioMixer.channels) / NovagramCallAudioMixer.sampleRate
        let offset = clockOffset(source: source, pts: pts, duration: duration, now: now)
        let position = Int64(((pts + offset - start) * NovagramCallAudioMixer.sampleRate).rounded())
        mix(frames, at: position)
    }

    func takeSampleBuffer(upTo limitFrame: Int64, start: Double) -> CMSampleBuffer? {
        let frameCount = Int(limitFrame - baseFrame)
        guard frameCount > 0 else {
            return nil
        }
        let valueCount = frameCount * NovagramCallAudioMixer.channels
        if samples.count < valueCount {
            samples.append(contentsOf: repeatElement(0, count: valueCount - samples.count))
        }
        var chunk = Array(samples[0 ..< valueCount])
        for index in chunk.indices {
            chunk[index] = min(max(chunk[index], -1), 1)
        }
        samples.removeFirst(valueCount)
        let pts = CMTime(seconds: start + Double(baseFrame) / NovagramCallAudioMixer.sampleRate, preferredTimescale: CMTimeScale(NovagramCallAudioMixer.sampleRate))
        baseFrame += Int64(frameCount)
        return makeSampleBuffer(chunk, frameCount: frameCount, pts: pts)
    }

    var pendingEndFrame: Int64 {
        return baseFrame + Int64(samples.count / NovagramCallAudioMixer.channels)
    }

    private func clockOffset(source: Source, pts: Double, duration: Double, now: Double) -> Double {
        if let offset = clockOffsets[source] {
            return offset
        }
        let delta = (now - duration) - pts
        let offset = abs(delta) > NovagramCallAudioMixer.clockMismatchSeconds ? delta : 0
        clockOffsets[source] = offset
        return offset
    }

    private func mix(_ frames: [Float], at position: Int64) {
        let channels = NovagramCallAudioMixer.channels
        var first = position
        var skip = 0
        if first < baseFrame {
            skip = Int(baseFrame - first) * channels
            guard skip < frames.count else {
                return
            }
            first = baseFrame
        }
        guard Double(first - baseFrame) < NovagramCallAudioMixer.maxLeadSeconds * NovagramCallAudioMixer.sampleRate else {
            return
        }
        let startIndex = Int(first - baseFrame) * channels
        let endIndex = startIndex + frames.count - skip
        if samples.count < endIndex {
            samples.append(contentsOf: repeatElement(0, count: endIndex - samples.count))
        }
        var target = startIndex
        for index in skip ..< frames.count {
            samples[target] += frames[index]
            target += 1
        }
    }

    private func stereoSamples(_ sampleBuffer: CMSampleBuffer, source: Source) -> [Float]? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        let inputFormat = AVAudioFormat(cmAudioFormatDescription: description)
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0, inputFormat.channelCount > 0, let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            return nil
        }
        input.frameLength = frameCount
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frameCount), into: input.mutableAudioBufferList) == noErr else {
            return nil
        }
        guard let floatFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: NovagramCallAudioMixer.sampleRate, channels: inputFormat.channelCount, interleaved: false) else {
            return nil
        }
        let buffer: AVAudioPCMBuffer
        if inputFormat == floatFormat {
            buffer = input
        } else {
            guard let converted = convert(input, from: inputFormat, to: floatFormat, source: source) else {
                return nil
            }
            buffer = converted
        }
        guard let channelData = buffer.floatChannelData else {
            return nil
        }
        let frames = Int(buffer.frameLength)
        let left = channelData[0]
        let right = buffer.format.channelCount > 1 ? channelData[1] : channelData[0]
        var result = [Float](repeating: 0, count: frames * NovagramCallAudioMixer.channels)
        for frame in 0 ..< frames {
            result[frame * 2] = left[frame]
            result[frame * 2 + 1] = right[frame]
        }
        return result
    }

    private func convert(_ input: AVAudioPCMBuffer, from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat, source: Source) -> AVAudioPCMBuffer? {
        let converter: AVAudioConverter
        if let cached = converters[source], cached.format == inputFormat {
            converter = cached.converter
        } else {
            guard let created = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                return nil
            }
            converters[source] = (inputFormat, created)
            converter = created
        }
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + NovagramCallAudioMixer.converterSlackFrames
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }
        var provided = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if provided {
                inputStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil else {
            return nil
        }
        return output
    }

    private func makeSampleBuffer(_ values: [Float], frameCount: Int, pts: CMTime) -> CMSampleBuffer? {
        guard let formatDescription else {
            return nil
        }
        let byteCount = values.count * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &blockBuffer) == kCMBlockBufferNoErr, let blockBuffer else {
            return nil
        }
        let copied = values.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else {
                return kCMBlockBufferBadPointerParameterErr
            }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard copied == kCMBlockBufferNoErr else {
            return nil
        }
        var sampleBuffer: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: formatDescription, sampleCount: frameCount, presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &sampleBuffer) == noErr else {
            return nil
        }
        return sampleBuffer
    }
}
