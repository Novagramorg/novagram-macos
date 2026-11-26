import AppKit
import CoreText
import Baseline
import Candidate

_ = NSApplication.shared
var sink = 0.0

func paired(iterations: Int, baseline: () -> Void, candidate: () -> Void) -> [String: Double] {
    for _ in 0 ..< 3 { baseline(); candidate() }
    func time(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< iterations { body() }
        return Double(DispatchTime.now().uptimeNanoseconds-start)/1e6
    }
    var old: [Double] = [], new: [Double] = []
    for pass in 0 ..< 9 {
        if pass % 2 == 0 { old.append(time(baseline)); new.append(time(candidate)) }
        else { new.append(time(candidate)); old.append(time(baseline)) }
    }
    let a = old.sorted()[4], b = new.sorted()[4]
    return ["baseline_ms":a,"candidate_ms":b,"speedup":a/b,"iterations":Double(iterations)]
}

func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self,capacity:Int(count)) { task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count) }
    }
    precondition(status == KERN_SUCCESS)
    return info.resident_size
}
if CommandLine.arguments.contains("--memory") {
    let useCandidate = CommandLine.arguments.contains("candidate")
    let maximum: Int32 = CommandLine.arguments.contains("--truncated") ? 3 : 0
    let text = String(repeating:"Retained text layout with wrapping and Unicode café. ",count:76)
    precondition(text.utf16.count+4 <= 4096)
    for _ in 0 ..< 20 {
        let layout = Candidate.TextViewLayout(Candidate.input(text)); layout.measure(width:280)
        let old = Baseline.TextViewLayout(Baseline.input(text)); old.measure(width:280)
    }
    let before = residentBytes()
    let retained: [AnyObject] = autoreleasepool {
        (0 ..< 300).map { index -> AnyObject in
            let value = "\(index) "+text
            if useCandidate {
                let layout = Candidate.TextViewLayout(Candidate.input(value),maximumNumberOfLines:maximum); layout.measure(width:280);layout.measure(width:290);return layout
            } else {
                let layout = Baseline.TextViewLayout(Baseline.input(value),maximumNumberOfLines:maximum); layout.measure(width:280);layout.measure(width:290);return layout
            }
        }
    }
    withExtendedLifetime(retained) {
        print("{\"candidate\":\(useCandidate),\"layouts\":300,\"maximum_lines\":\(maximum),\"utf16_per_layout\":\(text.utf16.count),\"before_bytes\":\(before),\"after_bytes\":\(residentBytes())}")
    }
    exit(0)
}

let prose = "A message with text layout, wrapping and selection. "
let cases: [(String,String,Int,Int32,Int)] = [
    ("short-label","Last seen recently",0,1,1500),
    ("chat-paragraph",String(repeating:prose,count:5),0,0,400),
    ("unicode","More مرحبا 🙂 שלום नमस्ते 中文 café 👩🏽‍💻 mixed text with fi AVATAR",0,0,400),
    ("plain-4k",String(repeating:prose,count:78),0,0,50),
    ("links-4k",String(repeating:prose,count:78),1,0,40),
    ("links-16k",String(repeating:prose,count:320),1,0,10),
    ("decorations",String(repeating:prose,count:78),2,0,30),
    ("quotes",String(repeating:prose,count:78),3,0,30),
    ("color-markers",String(repeating:prose,count:78),4,0,30),
    ("embedded",String(repeating:prose,count:78),5,0,30),
    ("mixed-fonts",String(repeating:prose,count:78),6,0,30),
    ("truncated-rich",String(repeating:prose,count:78),1,3,100)
]
var results: [[String:Any]] = []
for (name,text,style,maximum,iterations) in cases {
    let oldText = Baseline.input(text,style:style), newText = Candidate.input(text,style:style)
    let timing = paired(iterations:iterations,baseline:{
        let layout = Baseline.TextViewLayout(oldText,maximumNumberOfLines:maximum,strokeLinks:true,disableTooltips:false)
        layout.measure(width:280)
        sink += layout.layoutSize.height + layout.layoutSize.width
    },candidate:{
        let layout = Candidate.TextViewLayout(newText,maximumNumberOfLines:maximum,strokeLinks:true,disableTooltips:false)
        layout.measure(width:280)
        sink += layout.layoutSize.height + layout.layoutSize.width
    })
    let oldLayout = Baseline.TextViewLayout(oldText, maximumNumberOfLines:maximum,strokeLinks:true,disableTooltips:false)
    let newLayout = Candidate.TextViewLayout(newText, maximumNumberOfLines:maximum,strokeLinks:true,disableTooltips:false)
    var oldTick = 0, newTick = 0
    let repeated = paired(iterations:iterations,baseline:{
        oldTick += 1
        oldLayout.measure(width:oldTick % 2 == 0 ? 280 : 290)
        sink += oldLayout.layoutSize.height
    },candidate:{
        newTick += 1
        newLayout.measure(width:newTick % 2 == 0 ? 280 : 290)
        sink += newLayout.layoutSize.height
    })
    results.append(["scenario":name,"utf16":text.utf16.count,"cold_measure":timing,"resize_measure":repeated])
}

func linearIntersections(_ ranges: [NSRange],_ queries:[NSRange]) -> Int {
    var count = 0
    for query in queries { for range in ranges { if NSIntersectionRange(query,range).length>0 { count += 1 } } }
    return count
}
func sweepIntersections(_ ranges:[NSRange],_ queries:[NSRange]) -> Int {
    var start = 0, count = 0
    for query in queries {
        while start < ranges.count && NSMaxRange(ranges[start]) <= query.location { start += 1 }
        var row = start
        while row < ranges.count && ranges[row].location < NSMaxRange(query) {
            if NSIntersectionRange(query,ranges[row]).length>0 { count += 1 }
            row += 1
        }
    }
    return count
}
let ranges = (0 ..< 400).map { NSRange(location:$0*40,length:40) }
let queries = (0 ..< 800).map { NSRange(location:$0*20,length:12) }
precondition(linearIntersections(ranges,queries)==Candidate.binaryIntersectionCount(ranges,queries))
precondition(linearIntersections(ranges,queries)==sweepIntersections(ranges,queries))
let binary = paired(iterations:100,baseline:{sink += Double(linearIntersections(ranges,queries))},candidate:{sink += Double(Candidate.binaryIntersectionCount(ranges,queries))})
let sweep = paired(iterations:100,baseline:{sink += Double(Candidate.binaryIntersectionCount(ranges,queries))},candidate:{sink += Double(sweepIntersections(ranges,queries))})

let font = NSFont.systemFont(ofSize:13) as CTFont
var glyphExperiments: [[String:Any]] = []
for text in ["AVATAR To Wa", "office ffi fi", "مرحبا بالعالم", "हिन्दी नमस्ते", "👩🏽‍💻🇦🇪🙂", "hello world with wrapping spaces"] {
    let characters = Array(text.utf16)
    var glyphs = [CGGlyph](repeating:0,count:characters.count)
    let mapped = CTFontGetGlyphsForCharacters(font,characters,&glyphs,characters.count)
    var advances = [CGSize](repeating:.zero,count:glyphs.count)
    CTFontGetAdvancesForGlyphs(font,.horizontal,glyphs,&advances,glyphs.count)
    let sum = advances.reduce(CGFloat(0)) { $0+$1.width }
    let attributed = NSAttributedString(string:text,attributes:[.font:font])
    let line = CTLineCreateWithAttributedString(attributed)
    let actual = CTLineGetTypographicBounds(line,nil,nil,nil)
    let typesetter = CTTypesetterCreateWithAttributedString(attributed)
    var prefix: [CGFloat] = [0]
    for advance in advances { prefix.append(prefix.last!+advance.width) }
    var mismatches = 0
    for width: CGFloat in [20,40,60,90,120] {
        var lower = 0, upper = prefix.count
        while lower < upper {
            let middle = lower+(upper-lower)/2
            if prefix[middle] <= width { lower = middle+1 } else { upper = middle }
        }
        let proposed = max(0,lower-1)
        let actualBreak = CTTypesetterSuggestLineBreak(typesetter,0,Double(width))
        if proposed != actualBreak { mismatches += 1 }
    }
    glyphExperiments.append(["text":text,"all_glyphs_mapped":mapped,"sum_advance_width":Double(sum),"core_text_width":actual,"line_break_mismatches":mismatches])
}
let output: [String:Any] = ["measurement":"Median of nine paired batches; alternating order after warmup","environment":ProcessInfo.processInfo.operatingSystemVersionString,"layouts":results,"range_math":["linear_vs_binary":binary,"binary_vs_monotonic_sweep":sweep],"rejected_glyph_prefix_approximation":glyphExperiments,"checksum":sink]
print(String(decoding:try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
