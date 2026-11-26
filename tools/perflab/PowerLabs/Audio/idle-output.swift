import Foundation
import AudioToolbox

func cpu(_ pid: String) -> Double {
    let p = Process(); p.launchPath = "/bin/ps"; p.arguments = ["-o", "time=", "-p", pid]
    let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
    let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
    return s.split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
}
func sh(_ c: String) -> String {
    let p = Process(); p.launchPath = "/bin/zsh"; p.arguments = ["-c", c]
    let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
}
let coreaudiod = sh("pgrep -x coreaudiod").split(separator: "\n").first.map(String.init) ?? ""
let me = String(getpid())

var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
let comp = AudioComponentFindNext(nil, &desc)!
var unit: AudioUnit?
AudioComponentInstanceNew(comp, &unit)
var format = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked, mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
AudioUnitSetProperty(unit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
var callback = AURenderCallbackStruct(inputProc: { _, _, _, _, _, ioData in
    if let ioData = ioData {
        for buffer in UnsafeMutableAudioBufferListPointer(ioData) { memset(buffer.mData, 0, Int(buffer.mDataByteSize)) }
    }
    return noErr
}, inputProcRefCon: nil)
AudioUnitSetProperty(unit!, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
AudioUnitSetParameter(unit!, kHALOutputParam_Volume, kAudioUnitScope_Output, 0, 0, 0)
AudioUnitInitialize(unit!)

func phase(_ name: String, running: Bool) {
    if running { AudioOutputUnitStart(unit!) } else { AudioOutputUnitStop(unit!) }
    Thread.sleep(forTimeInterval: 2)
    let a0 = cpu(coreaudiod), m0 = cpu(me), t0 = Date()
    Thread.sleep(forTimeInterval: 15)
    let dt = Date().timeIntervalSince(t0)
    let assertions = sh("pmset -g assertions | grep -i -E 'pid \\(?\(me)|coreaudiod' | grep -v '^ *$' | sed 's/^ *//' | head -3")
    print(String(format: "%@: coreaudiod %.2f%% CPU, lab %.2f%% CPU", name, (cpu(coreaudiod) - a0) / dt * 100, (cpu(me) - m0) / dt * 100))
    print("  assertions: " + (assertions.isEmpty ? "none" : assertions.replacingOccurrences(of: "\n", with: " | ")))
}
for _ in 0 ..< 2 {
    phase("paused, output running", running: true)
    phase("output stopped", running: false)
}
