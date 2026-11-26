import Cocoa
import TGUIKit
import SwiftSignalKit

struct AutoremoveAttribute {
    var countdownBeginTime: Int32?
    var timeout: Int32
}
struct Message {
    var autoremoveAttribute: AutoremoveAttribute?
}
final class Clock {
    var timestamp: Int32 = 100
}
struct Interaction {
    let interactionContext: Clock
}
class ItemEnvironment {
    let initialDate: String?
    var fullDate: String?
    var message: Message?
    let chatInteraction: Interaction
    init(date: String? = "message date", begin: Int32? = 90, timeout: Int32 = 60, clock: Clock = Clock()) {
        initialDate = date
        fullDate = date
        message = Message(autoremoveAttribute: AutoremoveAttribute(countdownBeginTime: begin, timeout: timeout))
        chatInteraction = Interaction(interactionContext: clock)
    }
}
struct LabStrings {
    func chatContextMenuAutoDelete(_ value: String) -> String { "Auto delete: " + value }
}
func strings() -> LabStrings { LabStrings() }
func smartTimeleftText(_ value: Int) -> String { "\(value)s" }

final class TimerRecord {
    var starts = 0
    var active = false
    var fires = 0
    var cancellations = 0
}
final class LabTimer {
    static var scale: Double = 0.01
    static var records: [TimerRecord] = []
    let record = TimerRecord()
    private let underlying: SwiftSignalKit.Timer
    init(timeout: Double, repeat repeats: Bool, completion: @escaping () -> Void, queue: Queue) {
        let record = self.record
        underlying = SwiftSignalKit.Timer(timeout: timeout * LabTimer.scale, repeat: repeats, completion: {
            record.fires += 1
            completion()
        }, queue: queue)
        LabTimer.records.append(record)
    }
    func start() {
        record.starts += 1
        record.active = true
        underlying.start()
    }
    func invalidate() {
        if record.active {
            record.active = false
            record.cancellations += 1
        }
        underlying.invalidate()
    }
    deinit { invalidate() }
}
class ViewEnvironment: View {
    var pointerInside = true
    override func mouseInside() -> Bool { pointerInside }
}

private let labImages = ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"].map { name in
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.black.setFill()
        rect.fill()
        return true
    }
    image.setName(name)
    return image
}
func initializeLab() {
    _ = NSApplication.shared
    _ = labImages
    System.updateScaleFactor(2)
    LabTimer.scale = 0.01
    LabTimer.records = []
}
