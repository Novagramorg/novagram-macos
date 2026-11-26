import Cocoa
let context = CGContext(data: nil, width: 1200, height: 300, bitsPerComponent: 8, bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.scaleBy(x: 2, y: 2)
context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
for text in ["12:34", "Hello with styled text and a second line\nMore text 👩🏽‍💻", "👨‍👩‍👧‍👦 👩🏽‍💻 🦆 🇦🇪 🙂", "مرحبا بالعالم English שלום", "中文 日本語 한글 café ffi"] {
    let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
    let line = CTLineCreateWithAttributedString(string)
    func draw(_ mode: Int) {
        if mode == 0 {
            for item in CTLineGetGlyphRuns(line) as NSArray {
                let run = item as! CTRun
                let count = CTRunGetGlyphCount(run)
                _ = CTRunGetStringRange(run)
                context.textPosition = CGPoint(x: 10, y: 30)
                CTRunDraw(run, context, CFRange(location: 0, length: count))
            }
        } else {
            let runs = CTLineGetGlyphRuns(line)
            for index in 0..<CFArrayGetCount(runs) {
                let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, index), to: CTRun.self)
                let count = mode == 1 ? 0 : CTRunGetGlyphCount(run)
                context.textPosition = CGPoint(x: 10, y: 30)
                CTRunDraw(run, context, CFRange(location: 0, length: count))
            }
        }
    }
    func measure(_ mode: Int) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<3000 { draw(mode) }
        return Double(DispatchTime.now().uptimeNanoseconds - start)/3000
    }
    var values = [[Double](), [Double](), [Double]()]
    for round in 0..<12 {
        for step in 0..<3 { let mode = (round + step) % 3; values[mode].append(measure(mode)) }
    }
    print(text, values.map { $0.sorted()[6] })
}
