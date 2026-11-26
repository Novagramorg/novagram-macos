import Cocoa

var comparisons = 0
var randomState: UInt64 = 0x17ad9e53
var checksum: Double = 0

func random(_ upperBound: Int) -> Int {
    randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
    return Int((randomState >> 32) % UInt64(upperBound))
}

func equalWidth(_ actual: CGFloat, _ expected: CGFloat, _ label: String) {
    precondition(actual == expected || (actual.isNaN && expected.isNaN), "\(label): \(actual) != \(expected)")
}

func compare(_ item: ChatRowItem, size: NSSize, label: String) {
    let baseline = ReferenceFrames(item, size: size)
    let candidate = Frames(item, size: size)
    precondition(candidate.rectangles == baseline.rectangles, "Geometry changed: \(label)")
    equalWidth(candidate.width, baseline.width, label)
    equalWidth(candidate.width, baseline.width, "Repeated read: \(label)")
    let copy = candidate
    equalWidth(copy.width, baseline.width, "Copied frames: \(label)")
    comparisons += 1
}

func compareRectangles(_ rectangles: [CGRect?], overlay: Bool, label: String) {
    let baseline = ReferenceFrames(rectangles: rectangles, overlay: overlay)
    let candidate = Frames(rectangles: rectangles, overlay: overlay)
    equalWidth(candidate.width, baseline.width, label)
    comparisons += 1
}

let layoutSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 16)
for flags in 0..<(1 << 17) {
    System.backingScale = [1, 2, 3][flags % 3]
    compare(ChatRowItem(flags: flags), size: layoutSize, label: "Flags \(flags)")
}

for index in 0..<5_000 {
    var item = ChatRowItem(flags: random(1 << 17), textWidth: CGFloat(random(1200)) / 4)
    item.presentation.chat.sizes = (0..<7).map { _ in
        NSSize(width: CGFloat(random(120)) / 4, height: CGFloat(random(120)) / 4)
    }
    item.presentation.icons.sentFailed.backingSize = NSSize(width: CGFloat(random(80)) / 4, height: 16)
    let width = CGFloat(random(800)) / 2
    let height = CGFloat(random(120)) / 4
    System.backingScale = CGFloat(random(3) + 1)
    compare(item, size: NSSize(width: width, height: height), label: "Resized \(index)")
    let original = Frames(item, size: layoutSize)
    let originalWidth = original.width
    item.date = TextLayout(layoutSize: NSSize(width: CGFloat(random(1000)), height: 16))
    item.isRead.toggle()
    item.isStateOverlayLayout.toggle()
    compare(item, size: layoutSize, label: "Updated state \(index)")
    equalWidth(original.width, originalWidth, "Previous snapshot remains unchanged")
}

for index in 0..<10_000 {
    let rectangles: [CGRect?] = (0..<18).map { _ in
        if random(4) == 0 { return nil }
        return CGRect(x: CGFloat(random(600) - 300) / 4,
                      y: CGFloat(random(120) - 60) / 4,
                      width: CGFloat(random(120) - 60) / 4,
                      height: CGFloat(random(80) - 40) / 4)
    }
    compareRectangles(rectangles, overlay: index % 2 == 0, label: "Rectangle set \(index)")
}

for overlay in [false, true] {
    let empty = Array<CGRect?>(repeating: nil, count: 18)
    compareRectangles(empty, overlay: overlay, label: "Empty")
    compareRectangles(Array(repeating: CGRect.zero, count: 18), overlay: overlay, label: "All zero")
    for field in 0..<18 {
        for rect in [CGRect.zero, CGRect(x: -30, y: 2, width: 10, height: 14), CGRect(x: 30, y: 2, width: 0, height: 14)] {
            var rectangles = empty
            rectangles[field] = rect
            compareRectangles(rectangles, overlay: overlay, label: "Single field \(field)")
        }
        for other in 0..<18 {
            var rectangles = empty
            rectangles[field] = CGRect(x: 30, y: 2, width: 10, height: 14)
            rectangles[other] = CGRect(x: 20, y: 4, width: 20, height: 12)
            compareRectangles(rectangles, overlay: overlay, label: "Equal maxX \(field)/\(other)")
            rectangles[other] = rectangles[field]
            compareRectangles(rectangles, overlay: overlay, label: "Equal rect \(field)/\(other)")
        }
    }
    for value in [CGFloat.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
        for field in 0..<18 {
            var rectangles = empty
            rectangles[15] = CGRect(x: 10, y: 2, width: 30, height: 14)
            rectangles[field] = CGRect(x: value, y: 2, width: 10, height: 14)
            compareRectangles(rectangles, overlay: overlay, label: "Boundary \(field)/\(value)")
        }
    }
}

@inline(never) func referenceWidth(_ frames: ReferenceFrames) -> CGFloat { frames.width }
@inline(never) func candidateWidth(_ frames: Frames) -> CGFloat { frames.width }

let rows = (0..<256).map { index -> ChatRowItem in
    let common = (1 << 1) | (1 << 15)
    let variants = [common, common | (1 << 2), common | (1 << 6), common | (1 << 3),
                    common | (1 << 0), common | (1 << 13), common | (1 << 11), (1 << 17) - 1]
    return ChatRowItem(flags: variants[index % variants.count], textWidth: CGFloat(20 + index % 40))
}
let baselineFrames = rows.map { ReferenceFrames($0, size: layoutSize) }
let candidateFrames = rows.map { Frames($0, size: layoutSize) }

@inline(never) func referenceWork(_ creation: Bool, reads: Int, passes: Int) -> Double {
    var total: CGFloat = 0
    for _ in 0..<passes {
        for index in rows.indices {
            let frames = creation ? ReferenceFrames(rows[index], size: layoutSize) : baselineFrames[index]
            for _ in 0..<reads { total += referenceWidth(frames) }
        }
    }
    return Double(total)
}

@inline(never) func candidateWork(_ creation: Bool, reads: Int, passes: Int) -> Double {
    var total: CGFloat = 0
    for _ in 0..<passes {
        for index in rows.indices {
            let frames = creation ? Frames(rows[index], size: layoutSize) : candidateFrames[index]
            for _ in 0..<reads { total += candidateWidth(frames) }
        }
    }
    return Double(total)
}

func measure(_ work: () -> Double) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = work()
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    checksum += value
    return Double(elapsed)
}

var timings: [[String: Any]] = []
if CommandLine.arguments.contains("--benchmark") {
    for (name, creation, reads) in [("read-existing", false, 1), ("construct-and-read-once", true, 1), ("construct-and-read-eight-times", true, 8)] {
        let passes = 200
        precondition(referenceWork(creation, reads: reads, passes: 1) == candidateWork(creation, reads: reads, passes: 1))
        checksum += referenceWork(creation, reads: reads, passes: 10)
        checksum += candidateWork(creation, reads: reads, passes: 10)
        var baseline: [Double] = []
        var candidate: [Double] = []
        for batch in 0..<9 {
            let old = { referenceWork(creation, reads: reads, passes: passes) }
            let new = { candidateWork(creation, reads: reads, passes: passes) }
            if batch % 2 == 0 {
                baseline.append(measure(old))
                candidate.append(measure(new))
            } else {
                candidate.append(measure(new))
                baseline.append(measure(old))
            }
        }
        let oldNS = baseline.sorted()[baseline.count / 2] / Double(rows.count * passes)
        let newNS = candidate.sorted()[candidate.count / 2] / Double(rows.count * passes)
        print("\(name): \(oldNS) -> \(newNS) ns/row, \(oldNS / newNS)x")
        timings.append(["workload": name, "rows_per_batch": rows.count * passes, "reads_per_row": reads,
                        "baseline_ns_per_row": oldNS, "candidate_ns_per_row": newNS, "speedup": oldNS / newNS,
                        "baseline_batches_ns": baseline, "candidate_batches_ns": candidate])
    }
}
let result: [String: Any] = ["comparisons": comparisons, "checksum": checksum, "timings": timings,
                            "reference_stride": MemoryLayout<ReferenceFrames>.stride, "candidate_stride": MemoryLayout<Frames>.stride]
if let path = ProcessInfo.processInfo.environment["WIDTH_BENCH_RESULTS"] {
    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
}
print("PASS: \(comparisons) frame comparisons; checksum \(checksum)")
