import Cocoa
import WebKit

final class WebKitTimeline {
    private let inspector: NSObject
    private let frontend: WKWebView

    private static func evaluate(_ view: WKWebView, _ script: String) -> Any? {
        var finished = false
        var result: Any?
        view.evaluateJavaScript(script) { value, error in
            result = value
            if let error = error { print("timeline-eval-error: \(error)") }
            finished = true
        }
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return result
    }

    init?(_ view: WKWebView) {
        view.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        guard view.responds(to: Selector(("_inspector"))),
              let inspector = view.value(forKey: "_inspector") as? NSObject,
              inspector.responds(to: Selector(("connect"))),
              inspector.responds(to: Selector(("inspectorWebView"))) else {
            print("timeline-error: inspector API unavailable")
            return nil
        }
        self.inspector = inspector
        if #available(macOS 13.3, *) { view.isInspectable = true }
        inspector.perform(Selector(("connect")))
        if inspector.responds(to: Selector(("show"))) { inspector.perform(Selector(("show"))) }
        let deadline = Date().addingTimeInterval(10)
        var candidate: WKWebView?
        while candidate == nil && Date() < deadline {
            candidate = inspector.value(forKey: "inspectorWebView") as? WKWebView
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard let frontend = candidate else {
            print("timeline-error: frontend unavailable")
            return nil
        }
        self.frontend = frontend
        var ready = false
        while !ready && Date() < deadline {
            ready = Self.evaluate(frontend, "typeof WI !== 'undefined' && !!WI.timelineManager && WI.targets.length > 0") as? Bool == true
            if !ready { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        }
        guard ready else {
            print("timeline-error: frontend not ready")
            return nil
        }
        if inspector.responds(to: Selector(("detach"))) { inspector.perform(Selector(("detach"))) }
        if inspector.responds(to: Selector(("hide"))) { inspector.perform(Selector(("hide"))) }
    }

    func capture(seconds: Double, path: String) {
        let started = Self.evaluate(frontend, """
        (() => {
            WI.timelineManager.enable();
            WI.timelineManager.enabledTimelineTypes = [WI.TimelineRecord.Type.Layout, WI.TimelineRecord.Type.RenderingFrame];
            WI.settings.timelinesAutoStop.value = false;
            WI.timelineManager.startCapturing(true);
            return true;
        })()
        """) as? Bool == true
        guard started else {
            print("timeline-error: recording did not start")
            return
        }
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        _ = Self.evaluate(frontend, "WI.timelineManager.stopCapturing(); true")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let script = """
        JSON.stringify({
            startTime: WI.timelineManager.activeRecording.startTime,
            endTime: WI.timelineManager.activeRecording.endTime,
            records: Array.from(WI.timelineManager.activeRecording.timelines.values()).flatMap(t => t.records.map(r => ({
                type: r.type, eventType: r.eventType, startTime: r.startTime, endTime: r.endTime,
                duration: r.duration, children: r.children.map(c => ({type: c.type, eventType: c.eventType, startTime: c.startTime, endTime: c.endTime}))
            })))
        })
        """
        if let json = Self.evaluate(frontend, script) as? String {
            do {
                try json.write(toFile: path, atomically: true, encoding: .utf8)
                print("timeline-saved: \(path)")
            } catch {
                print("timeline-error: \(error)")
            }
        }
        if inspector.responds(to: Selector(("close"))) { inspector.perform(Selector(("close"))) }
    }
}
