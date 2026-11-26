import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext
import TelegramTheme
import ColorPalette
import SwiftSignalKit

public struct QrStudioEmojiPickerHooks {
    public struct Picker {
        public let controller: ViewController
        public let setSelected: (_ fileIds: [Int64: Int], _ unicode: [String: Int]) -> Void

        public init(controller: ViewController, setSelected: @escaping (_ fileIds: [Int64: Int], _ unicode: [String: Int]) -> Void) {
            self.controller = controller
            self.setSelected = setSelected
        }
    }

    public static var make: ((_ context: any AccountContextProtocol, _ presentation: TelegramPresentationTheme, _ staticEmojiFilter: @escaping (String) -> Bool, _ select: @escaping (_ file: TelegramMediaFile?, _ unicode: String?) -> Void) -> Picker?)? = nil
}

final class QrStudioEmojiTabView: View {
    var resolveUnicode: ((String) -> QrStudioEmojiItem?)?
    var toggle: ((QrStudioEmojiItem) -> Bool)?
    var premiumRequired: (() -> Void)?

    private final class Slot {
        let picker: QrStudioEmojiPickerHooks.Picker
        var isAppeared = false
        var isOnStage = true
        var isReady = false
        var appliedFileIds: [Int64: Int]?
        var appliedUnicode: [String: Int]?
        let readyDisposable = MetaDisposable()

        init(picker: QrStudioEmojiPickerHooks.Picker) {
            self.picker = picker
        }

        deinit {
            self.readyDisposable.dispose()
        }
    }

    private let context: any AccountContextProtocol
    private var slots: [Bool: Slot] = [:]
    private var activeIsDark: Bool?
    private var selectedFileIds: [Int64: Int] = [:]
    private var selectedUnicode: [String: Int] = [:]
    private let availableEmoji = Atomic<Set<String>?>(value: nil)

    init(context: any AccountContextProtocol) {
        self.context = context
        super.init(frame: .zero)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for (_, slot) in self.slots where slot.isAppeared {
            slot.picker.controller.viewWillDisappear(false)
            slot.picker.controller.viewDidDisappear(false)
        }
    }

    private static func presentation(isDark: Bool) -> TelegramPresentationTheme {
        let current = theme
        if current.colors.isDark == isDark {
            return current
        }
        if isDark {
            return TelegramThemeHooks.shared.darkAppearance()
        }
        return current.withUpdatedColors(dayClassicPalette)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for (_, slot) in self.slots {
            self.updateAppearance(slot)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let result = super.hitTest(point) else {
            return nil
        }
        for (isDark, slot) in self.slots where isDark != self.activeIsDark {
            let view = slot.picker.controller.view
            if result === view || result.isDescendant(of: view) {
                return nil
            }
        }
        return result
    }

    private func updateAppearance(_ slot: Slot) {
        if self.window != nil {
            guard !slot.isAppeared else {
                return
            }
            slot.isAppeared = true
            slot.isOnStage = true
            slot.picker.controller.viewWillAppear(false)
            slot.picker.controller.viewDidAppear(false)
        } else {
            guard slot.isOnStage, slot.isReady else {
                return
            }
            slot.isAppeared = false
            slot.isOnStage = false
            slot.picker.controller.viewWillDisappear(false)
            slot.picker.controller.viewDidDisappear(false)
        }
    }

    private func slot(isDark: Bool, frame: CGRect) -> Slot? {
        if let current = self.slots[isDark] {
            return current
        }
        guard let make = QrStudioEmojiPickerHooks.make else {
            return nil
        }
        let availableEmoji = self.availableEmoji
        let staticEmojiFilter: (String) -> Bool = { emoji in
            return availableEmoji.with { keys in
                guard let keys else {
                    return true
                }
                return keys.contains(qrStudioNormalizedEmoji(emoji)) || keys.contains(qrStudioNormalizedEmoji(emoji, removingSkinTone: true))
            }
        }
        let picker = make(self.context, QrStudioEmojiTabView.presentation(isDark: isDark), staticEmojiFilter, { [weak self] file, unicode in
            self?.perform(file: file, unicode: unicode)
        })
        guard let picker else {
            return nil
        }
        let slot = Slot(picker: picker)
        self.slots[isDark] = slot
        let view = picker.controller.view
        picker.controller.loadViewIfNeeded(frame)
        view.frame = frame
        view.layer?.opacity = 0.0
        self.addSubview(view, positioned: .below, relativeTo: nil)
        self.updateAppearance(slot)
        slot.readyDisposable.set((picker.controller.ready.get()
        |> filter { $0 }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self, weak slot] _ in
            guard let self, let slot else {
                return
            }
            slot.isReady = true
            self.updateAppearance(slot)
        }))
        return slot
    }

    func updateAvailableEmoji(_ keys: Set<String>) {
        let _ = self.availableEmoji.swap(keys)
    }

    private func perform(file: TelegramMediaFile?, unicode: String?) {
        var resolved: QrStudioEmojiItem?
        if let unicode {
            resolved = self.resolveUnicode?(unicode)
        } else if let file {
            if let text = file.stickerText, let item = self.resolveUnicode?(text) {
                resolved = item
            } else {
                if file.isPremiumEmoji && !self.context.isPremium {
                    self.premiumRequired?()
                    return
                }
                resolved = QrStudioEmojiItem(file: file, unicode: nil)
            }
        }
        guard let resolved, let toggle = self.toggle else {
            return
        }
        let _ = toggle(resolved)
    }

    private func applySelection(_ slot: Slot) {
        guard slot.appliedFileIds != self.selectedFileIds || slot.appliedUnicode != self.selectedUnicode else {
            return
        }
        slot.appliedFileIds = self.selectedFileIds
        slot.appliedUnicode = self.selectedUnicode
        slot.picker.setSelected(self.selectedFileIds, self.selectedUnicode)
    }

    private func activate(isDark: Bool, animated: Bool) {
        guard let active = self.slots[isDark] else {
            return
        }
        self.applySelection(active)
        let activeView = active.picker.controller.view
        self.addSubview(activeView, positioned: .above, relativeTo: nil)
        for (slotIsDark, slot) in self.slots {
            guard let layer = slot.picker.controller.view.layer else {
                continue
            }
            let target: Float = slotIsDark == isDark ? 1.0 : 0.0
            let from = layer.presentation()?.opacity ?? layer.opacity
            layer.opacity = target
            if animated, from != target {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = from
                animation.toValue = target
                animation.duration = 0.4
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: "opacity")
            } else {
                layer.removeAnimation(forKey: "opacity")
            }
        }
    }

    func update(size: CGSize, selected: [QrStudioEmojiItem], isDark: Bool) {
        guard size.width > 0.0, size.height > 0.0 else {
            return
        }
        let frame = CGRect(origin: CGPoint(), size: size)

        var fileIds: [Int64: Int] = [:]
        var unicode: [String: Int] = [:]
        for (i, item) in selected.enumerated() {
            if let value = item.unicode {
                let stripped = String(String.UnicodeScalarView(value.unicodeScalars.filter { $0.value != 0xFE0F }))
                for variant in [value, stripped, stripped + "\u{FE0F}"] where unicode[variant] == nil {
                    unicode[variant] = i + 1
                }
            } else {
                fileIds[item.id] = i + 1
            }
        }
        self.selectedFileIds = fileIds
        self.selectedUnicode = unicode

        let _ = self.slot(isDark: isDark, frame: frame)
        let _ = self.slot(isDark: !isDark, frame: frame)

        for (_, slot) in self.slots {
            let view = slot.picker.controller.view
            if view.frame != frame {
                view.frame = frame
            }
        }
        if let active = self.slots[isDark] {
            self.applySelection(active)
        }

        if self.activeIsDark != isDark {
            let animated = self.activeIsDark != nil && self.window != nil
            self.activeIsDark = isDark
            self.activate(isDark: isDark, animated: animated)
        }
    }
}
