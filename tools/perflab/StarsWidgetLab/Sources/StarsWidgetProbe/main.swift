import AppKit
import TGUIKit
import Effects

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
System.updateScaleFactor(2)
if CommandLine.arguments.last == "broken" {
    let view = BrokenBadge(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
    view.update(size: view.frame.size, emitterPosition: CGPoint(x: 30, y: 15))
    let emitters = view.layer!.sublayers!.compactMap { $0 as? CAEmitterLayer }
    print("Original initialized with \(emitters.count) emitters; textured cells: \(emitters.flatMap { $0.emitterCells ?? [] }.filter { $0.contents != nil }.count)")
} else {
    let view = CandidateBadge(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
    view.update(size: view.frame.size, emitterPosition: CGPoint(x: 30, y: 15))
    let emitters = view.layer!.sublayers!.compactMap { $0 as? CAEmitterLayer }
    print("Candidate initialized with \(emitters.count) emitters; textured cells: \(emitters.flatMap { $0.emitterCells ?? [] }.filter { $0.contents != nil }.count)")
}
