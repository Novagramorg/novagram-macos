import AppKit

private func pairedMedianTime(iterations: Int, baseline: () -> Void, candidate: () -> Void) -> (baseline: Double, candidate: Double) {
    for _ in 0 ..< 5 { baseline(); candidate() }
    var oldSamples: [Double] = []
    var newSamples: [Double] = []
    func measure(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< iterations { body() }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
    for pass in 0 ..< 11 {
        if pass % 2 == 0 {
            oldSamples.append(measure(baseline))
            newSamples.append(measure(candidate))
        } else {
            newSamples.append(measure(candidate))
            oldSamples.append(measure(baseline))
        }
    }
    return (oldSamples.sorted()[5], newSamples.sorted()[5])
}

@inline(never)
private func baselineScrollTick(_ fixture: BaselineScroller, state: ChatHistoryState, offset: CGFloat) {
    fixture.tableView.documentOffset.y = offset
    fixture.updateScroller(state)
}

@inline(never)
private func candidateScrollTick(_ fixture: CandidateScroller, state: ChatHistoryState, offset: CGFloat) {
    fixture.tableView.documentOffset.y = offset
    fixture.updateScroller(state, onlyIfVisibilityChanged: true)
}

public func runLab(arguments: [String]) throws {
    _ = NSApplication.shared
    let text = "Synthetic message for native text layout. Unicode: café 東京 🙂. "
    let rows = (0 ..< 121).map { index in
        TableRowItem(index, height: index == 60 ? 500 : 60, text: String(repeating: text, count: index == 60 ? 30 : 3))
    }
    let baseline = selectBaseline(rows, state: center(60), viewport: 720)
    let candidate = selectCandidate(rows, state: center(60), viewport: 720)
    if arguments.contains("--preview") || arguments.contains("--snapshot") {
        let old = TableFixture(rows: baseline.rows, anchor: 60, viewport: 720)
        let new = TableFixture(rows: candidate.rows, anchor: 60, viewport: 720)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 768), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "ChatController Lab — identical viewport, fewer initial measurements"
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 768))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
        for (fixture, x, title) in [(old, CGFloat(0), "Baseline: \(baseline.rows.count) rows measured"), (new, CGFloat(500), "Candidate: \(candidate.rows.count) rows measured")] {
            fixture.scroll.removeFromSuperview()
            fixture.scroll.frame.origin = CGPoint(x: x, y: 0)
            root.addSubview(fixture.scroll)
            let label = NSTextField(labelWithString: title)
            label.textColor = .white
            label.frame = NSRect(x: x + 20, y: 735, width: 460, height: 24)
            root.addSubview(label)
        }
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[index + 1]))
        }
        if arguments.contains("--preview") {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            withExtendedLifetime((old, new)) { NSApp.run() }
        }
        return
    }
    var checksum = 0.0
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14)]
    func measure(_ item: TableRowItem) {
        checksum += (item.text as NSString).boundingRect(with: NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).height
    }
    let opening = pairedMedianTime(iterations: 100, baseline: {
        checksum += Double(selectBaseline(rows, state: center(60), viewport: 720, measure: measure).rows.count)
    }, candidate: {
        checksum += Double(selectCandidate(rows, state: center(60), viewport: 720, measure: measure).rows.count)
    })
    let oldOpening = opening.baseline
    let newOpening = opening.candidate
    let oldScroller = BaselineScroller()
    let newScroller = CandidateScroller()
    let state = ChatHistoryState()
    oldScroller.tableView.documentOffset.y = 200
    newScroller.tableView.documentOffset.y = 200
    var oldTick = 0
    var newTick = 0
    let scrolling = pairedMedianTime(iterations: 10000, baseline: {
        oldTick += 1
        baselineScrollTick(oldScroller, state: state, offset: CGFloat(100 + oldTick % 1000))
    }, candidate: {
        newTick += 1
        candidateScrollTick(newScroller, state: state, offset: CGFloat(100 + newTick % 1000))
    })
    let oldScrolling = scrolling.baseline
    let newScrolling = scrolling.candidate
    var openingScenarios: [[String: Any]] = []
    for (name, anchor, anchorHeight) in [("short-center", 60, CGFloat(60)), ("medium-center", 60, CGFloat(300)), ("tall-center-fallback", 60, CGFloat(900)), ("history-edge-fill", 0, CGFloat(60))] {
        let scenarioRows = (0 ..< 121).map { index in
            TableRowItem(index, height: index == anchor ? anchorHeight : 60, text: String(repeating: text, count: index == anchor ? max(3, Int(anchorHeight / 17)) : 3))
        }
        let oldSelection = selectBaseline(scenarioRows, state: center(anchor), viewport: 720)
        let newSelection = selectCandidate(scenarioRows, state: center(anchor), viewport: 720)
        let timing = pairedMedianTime(iterations: 100, baseline: {
            checksum += Double(selectBaseline(scenarioRows, state: center(anchor), viewport: 720, measure: measure).rows.count)
        }, candidate: {
            checksum += Double(selectCandidate(scenarioRows, state: center(anchor), viewport: 720, measure: measure).rows.count)
        })
        let oldTime = timing.baseline
        let newTime = timing.candidate
        openingScenarios.append(["scenario": name, "iterations": 100, "baseline_ms": oldTime, "candidate_ms": newTime, "baseline_rows": oldSelection.rows.count, "candidate_rows": newSelection.rows.count, "speedup": oldTime / newTime])
    }
    let output: [String: Any] = [
        "measurement": "Median of 11 paired batches with alternating baseline/candidate order after warmup",
        "environment": ProcessInfo.processInfo.operatingSystemVersionString,
        "opening": ["iterations": 100, "baseline_ms": oldOpening, "candidate_ms": newOpening, "baseline_rows": baseline.rows.count, "candidate_rows": candidate.rows.count, "speedup": oldOpening / newOpening],
        "scroll_controls": ["iterations": 10000, "baseline_ms": oldScrolling, "candidate_ms": newScrolling, "baseline_frame_updates": oldScroller.frameUpdates, "candidate_frame_updates": newScroller.frameUpdates, "speedup": oldScrolling / newScrolling],
        "opening_scenarios": openingScenarios,
        "checksum": checksum
    ]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
