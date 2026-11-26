import AppKit
import ApplicationServices
import TGUIKit

private final class LabRowItem: TableRowItem {
    let title: String
    let detail: String?

    init(_ initialSize: NSSize, title: String, detail: String?, stableId: AnyHashable) {
        self.title = title
        self.detail = detail
        super.init(initialSize, stableId: stableId)
    }

    override var accessibilityLabel: String? {
        return title
    }

    override var accessibilityValue: String? {
        return detail
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }
}

private func image(_ side: CGFloat, _ color: NSColor) -> CGImage {
    let context = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(color.cgColor)
    context.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
    return context.makeImage()!
}

private func registerPlaceholderImages() {
    for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
        let placeholder = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.gray.setFill()
            rect.insetBy(dx: 3, dy: 3).fill()
            return true
        }
        _ = placeholder.setName(name)
    }
}

private final class Lab {
    let window: NSWindow
    var pressed: [String] = []
    var search: SearchView?
    var seek: LinearProgressControl?
    var segment: ScrollableSegmentView?
    let rowTitles = ["Notifications and Sounds", "Privacy and Security", "Data and Storage", "Appearance", "Language", "Stickers and Emoji", "Chat Folders", "Devices"]

    init() {
        window = NSWindow(contentRect: NSMakeRect(200, 200, 780, 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Accessibility Lab"
        window.isReleasedWhenClosed = false
        let content = View(frame: NSMakeRect(0, 0, 780, 640))
        window.contentView = content

        let send = ImageButton(frame: NSMakeRect(20, 20, 32, 32))
        send.set(image: image(24, .systemBlue), for: .Normal)
        send.setAccessibilityLabel("Send")
        send.set(handler: { [weak self] _ in self?.pressed.append("Send") }, for: .Click)
        content.addSubview(send)

        let attach = ImageButton(frame: NSMakeRect(60, 20, 32, 32))
        attach.set(image: image(24, .systemGreen), for: .Normal)
        attach.appTooltip = "Attach"
        attach.set(handler: { [weak self] _ in self?.pressed.append("Attach") }, for: .Click)
        content.addSubview(attach)

        let decorative = ImageButton(frame: NSMakeRect(100, 20, 32, 32))
        decorative.set(image: image(24, .systemGray), for: .Normal)
        decorative.isAccessibilityDecorative = true
        decorative.set(handler: { _ in }, for: .Click)
        content.addSubview(decorative)

        let done = TextButton()
        done.set(text: "Done", for: .Normal)
        done.set(font: .systemFont(ofSize: 13), for: .Normal)
        done.set(color: .controlAccentColor, for: .Normal)
        done.set(handler: { [weak self] _ in self?.pressed.append("Done") }, for: .Click)
        _ = done.sizeToFit()
        done.setFrameOrigin(NSMakePoint(150, 26))
        content.addSubview(done)

        let switchView = SwitchView(frame: NSMakeRect(20, 70, 36, 20))
        switchView.setAccessibilityLabel("Notifications")
        content.addSubview(switchView)

        let check = SelectingControl(unselectedImage: image(20, .systemGray), selectedImage: image(20, .systemBlue))
        check.setFrameOrigin(NSMakePoint(70, 70))
        check.setAccessibilityLabel("Select message")
        content.addSubview(check)

        let text = TextView(frame: NSMakeRect(20, 100, 380, 40))
        let layout = TextViewLayout(.initialize(string: "Telegram is a cloud-based messaging app.", color: .labelColor, font: .systemFont(ofSize: 13)))
        layout.measure(width: 380)
        text.update(layout)
        content.addSubview(text)

        let avatar = ImageView(frame: NSMakeRect(20, 150, 40, 40))
        avatar.image = image(40, .systemOrange)
        avatar.setAccessibilityLabel("Profile photo")
        content.addSubview(avatar)

        let icon = ImageView(frame: NSMakeRect(70, 150, 40, 40))
        icon.image = image(40, .systemPurple)
        icon.isAccessibilityDecorative = true
        content.addSubview(icon)

        let search = SearchView(frame: NSMakeRect(10, 200, 400, 30))
        content.addSubview(search)
        self.search = search

        let table = TableView(frame: NSMakeRect(0, 240, 420, 400))
        content.addSubview(table)
        for (index, title) in rowTitles.enumerated() {
            _ = table.addItem(item: LabRowItem(NSMakeSize(420, 50), title: title, detail: index % 2 == 0 ? nil : "On", stableId: index))
        }
        table.layoutSubtreeIfNeeded()

        let segment = ScrollableSegmentView(frame: NSMakeRect(440, 20, 320, 40))
        content.addSubview(segment)
        let segmentTheme = ScrollableSegmentTheme.standard(PresentationTheme.current.colors)
        let tabs = ["All", "Unread", "Work"].enumerated().map { ScrollableSegmentItem(title: $0.element, index: $0.offset, uniqueId: Int64($0.offset), selected: $0.offset == 0, insets: NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10), icon: nil, theme: segmentTheme, equatable: nil) }
        tabs[2].accessibilityLabel = { "Work, 3 unread" }
        segment.didChangeSelectedItem = { [weak self] item in self?.pressed.append("tab \(item.title)") }
        segment.updateItems(tabs, animated: false)

        let seek = LinearProgressControl(progressHeight: 4)
        seek.frame = NSMakeRect(440, 80, 300, 10)
        seek.onUserChanged = { [weak self] value in self?.pressed.append("seek \(Int((value * 100).rounded()))") }
        seek.set(progress: 0.5)
        content.addSubview(seek)

        let download = RadialProgressView()
        download.frame = NSMakeRect(440, 110, 40, 40)
        download.state = .Fetching(progress: 0.42, force: false)
        download.set(handler: { [weak self] _ in self?.pressed.append("cancel download") }, for: .Click)
        content.addSubview(download)

        let counter = DynamicCounterTextView(frame: NSMakeRect(440, 170, 300, 20))
        counter.update(DynamicCounterTextView.make(for: "12 participants", count: "12", font: .normal(13), textColor: .black, width: 300), animated: false)
        content.addSubview(counter)

        self.seek = seek
        self.segment = segment
    }

    func dumpTree() -> [String] {
        return AccessibilityAudit.elements(window.contentView!).map { element in
            let role = element.accessibilityRole()?.rawValue ?? "?"
            let label = element.accessibilityLabel() ?? ""
            let value = (element.accessibilityValue()).map { "\($0)" } ?? ""
            return "\(role) label=\"\(label)\" value=\"\(value)\""
        }
    }

    func scrollOverSearch() {
        guard let search = search, let window = window as NSWindow? else { return }
        let point = search.convert(NSMakePoint(search.bounds.midX, search.bounds.midY), to: nil)
        for delta in [-3, 3, -6, 6] {
            if let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(delta), wheel2: 0, wheel3: 0) {
                cgEvent.location = window.convertPoint(toScreen: point)
                if let event = NSEvent(cgEvent: cgEvent) {
                    window.sendEvent(event)
                }
            }
        }
    }

    func pressAll() -> [String] {
        for element in AccessibilityAudit.elements(window.contentView!) where element.accessibilityRole() == .button {
            _ = element.accessibilityPerformPress()
        }
        return pressed
    }
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value = value else {
        return nil
    }
    return value as? String
}

private func axWalk(_ element: AXUIElement, depth: Int, lines: inout [String]) {
    guard depth < 40 else { return }
    var names: CFArray?
    _ = AXUIElementCopyAttributeNames(element, &names)
    for name in (names as? [String]) ?? [] {
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    }
    for parameterized in ["AXCellForColumnAndRow"] {
        var value: CFTypeRef?
        let index = [0, 0] as CFArray
        _ = AXUIElementCopyParameterizedAttributeValue(element, parameterized as CFString, index, &value)
    }
    let role = axString(element, kAXRoleAttribute) ?? "?"
    let label = axString(element, kAXDescriptionAttribute) ?? axString(element, kAXTitleAttribute) ?? ""
    lines.append(String(repeating: "  ", count: depth) + "\(role) \"\(label)\"")
    var children: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success, let list = children as? [AXUIElement] {
        for child in list {
            axWalk(child, depth: depth + 1, lines: &lines)
        }
    }
}

private func runOutOfProcessStyleWalk(completion: @escaping ([String]) -> Void) {
    let scrolling = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
        lab.scrollOverSearch()
    }
    DispatchQueue.global().async {
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetMessagingTimeout(app, 5)
        var lines: [String] = []
        for _ in 0 ..< 20 {
            lines.removeAll()
            axWalk(app, depth: 0, lines: &lines)
        }
        DispatchQueue.main.sync {
            scrolling.invalidate()
        }
        DispatchQueue.main.async {
            completion(lines)
        }
    }
}

let arguments = CommandLine.arguments
_ = NSApplication.shared
NSApp.setActivationPolicy(arguments.contains("--show") ? .regular : .accessory)
registerPlaceholderImages()
TGUIKitAccessibility.isEnabled = true

fileprivate let lab = Lab()
lab.window.makeKeyAndOrderFront(nil)

let issues = AccessibilityAudit.audit(lab.window)
print("== accessibility tree")
for line in lab.dumpTree() {
    print(line)
}
print("== audit: \(issues.count) issue(s)")
for issue in issues {
    print(issue)
}
let pressed = lab.pressAll()
print("== press: \(pressed)")
let tree = lab.dumpTree()
let expectedLabels = ["Send", "Attach", "Done", "Notifications", "Select message", "Profile photo", "All", "Unread", "Work, 3 unread", "VoiceOver.Common.PlaybackPosition", "VoiceOver.Common.CancelDownload"] + lab.rowTitles
let tabs = AccessibilityAudit.elements(lab.segment!).filter { $0.accessibilityRole() == .radioButton }
_ = tabs.last?.accessibilityPerformPress()
_ = lab.seek?.accessibilityPerformIncrement()
let seekValue = lab.seek?.accessibilityValue() as? String
let counterRead = tree.contains("AXStaticText label=\"\" value=\"12 participants\"")
print("== tabs: \(tabs.count) radio buttons; seek value after increment: \(seekValue ?? "nil"); counter read whole: \(counterRead); actions: \(lab.pressed)")
let missing = expectedLabels.filter { label in !tree.contains(where: { $0.contains("label=\"\(label)\"") }) }
print("== expected labels missing from the tree: \(missing)")
var failed = tabs.count != 3 || seekValue != "55%" || !counterRead || !lab.pressed.contains("tab Work") || !lab.pressed.contains("seek 55") || !issues.isEmpty || !missing.isEmpty || !["Send", "Attach", "Done"].allSatisfy(pressed.contains) || !tree.contains(where: { $0.hasPrefix("AXList") })

if arguments.contains("--ax") {
    if AXIsProcessTrusted() {
        runOutOfProcessStyleWalk { lines in
            let axMissing = lab.rowTitles.filter { title in !lines.contains(where: { $0.contains("\"\(title)\"") }) }
            print("== system accessibility API walk: \(lines.count) element(s), no crash; rows missing: \(axMissing)")
            if !axMissing.isEmpty || !lines.contains(where: { $0.contains("AXList") }) {
                failed = true
            }
            for line in lines.prefix(60) {
                print(line)
            }
            exit(failed ? 1 : 0)
        }
    } else {
        print("== system accessibility API walk skipped: grant Accessibility permission to this terminal in System Settings > Privacy & Security > Accessibility")
        exit(failed ? 1 : 0)
    }
} else if arguments.contains("--show") {
    print("== window stays open for VoiceOver (Cmd+F5); close it to quit")
} else {
    exit(failed ? 1 : 0)
}
NSApp.run()
