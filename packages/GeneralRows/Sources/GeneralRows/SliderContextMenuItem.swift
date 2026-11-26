import Foundation

import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Cocoa
import LocalAnimations
import Localization



public final class SliderContextMenuItem : ContextMenuItem {
    private let didUpdateValue:((CGFloat, Bool)->Void)?
    private let volume: CGFloat
    private let drawable: LocalAnimatedSticker
    private let drawable_muted: LocalAnimatedSticker
    private let minValue: CGFloat
    private let maxValue: CGFloat
    private let midValue: CGFloat?
    public init(volume: CGFloat, minValue: CGFloat = 0, maxValue: CGFloat = 2.0, midValue: CGFloat? = nil, drawable: LocalAnimatedSticker = .menu_speaker, drawable_muted: LocalAnimatedSticker = .menu_speaker_muted, _ didUpdateValue:((CGFloat, Bool)->Void)? = nil) {
        self.volume = volume
        self.minValue = minValue
        self.maxValue = maxValue
        self.midValue = midValue
        self.didUpdateValue = didUpdateValue
        self.drawable = drawable
        self.drawable_muted = drawable_muted
        super.init("")
    }
    
    public required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    public override func rowItem(presentation: AppMenu.Presentation, interaction: AppMenuBasicItem.Interaction) -> TableRowItem {
        return SliderContextMenuRowItem(.zero, presentation: presentation, interaction: interaction, menuItem: self, minValue: minValue, maxValue: maxValue, midValue: midValue, drawable: drawable, drawable_muted: drawable_muted, volume: volume, didUpdateValue: self.didUpdateValue)
    }
}


private final class SliderContextMenuRowItem : AppMenuBasicItem {
    fileprivate let didUpdateValue:((CGFloat, Bool)->Void)?
    fileprivate let volume: CGFloat
    fileprivate let drawable: LocalAnimatedSticker
    fileprivate let drawable_muted: LocalAnimatedSticker
    fileprivate let minValue: CGFloat
    fileprivate let maxValue: CGFloat
    fileprivate let midValue: CGFloat?
    init(_ initialSize: NSSize, presentation: AppMenu.Presentation, interaction: AppMenuBasicItem.Interaction, menuItem: ContextMenuItem, minValue: CGFloat, maxValue: CGFloat, midValue: CGFloat?, drawable: LocalAnimatedSticker, drawable_muted: LocalAnimatedSticker, volume: CGFloat, didUpdateValue:((CGFloat, Bool)->Void)?) {
        self.didUpdateValue = didUpdateValue
        self.volume = volume
        self.minValue = minValue
        self.maxValue = maxValue
        self.midValue = midValue
        self.drawable = drawable
        self.drawable_muted = drawable_muted
        super.init(initialSize, presentation: presentation, menuItem: menuItem, interaction: interaction)
    }
    
    override func viewClass() -> AnyClass {
        return SliderContextMenuRowView.self
    }
    
    override var effectiveSize: NSSize {
        return NSMakeSize(200, super.effectiveSize.height)
    }
    
    override var height: CGFloat {
        return 28
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverCommonVolume
    }

    override var accessibilityValue: String? {
        let value = (view as? SliderContextMenuRowView)?.volumeControl.value ?? volume
        return "\(Int((value * 100).rounded()))%"
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .slider
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        return [
            NSAccessibilityCustomAction(name: strings().voiceOverCommonUp, handler: { [weak self] in
                return self?.adjustVolume(1) ?? false
            }),
            NSAccessibilityCustomAction(name: strings().voiceOverCommonDown, handler: { [weak self] in
                return self?.adjustVolume(-1) ?? false
            })
        ]
    }

    override func accessibilityPerformPress() -> Bool {
        return false
    }

    private func adjustVolume(_ direction: CGFloat) -> Bool {
        guard let view = view as? SliderContextMenuRowView else {
            return false
        }
        let step = (maxValue - minValue) / 20
        let value = min(maxValue, max(minValue, view.volumeControl.value + step * direction))
        view.volumeControl.value = value
        didUpdateValue?(value, true)
        view.updateValue(value)
        return true
    }
}


private final class SliderContextMenuRowView : AppMenuBasicItemView {
    let volumeControl = VolumeMenuItemView(frame: NSMakeRect(0, 0, 200, 26))
    private var drawable_muted: AppMenuAnimatedImage?
    private var drawable: AppMenuAnimatedImage?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(volumeControl)
       

        containerView.set(handler: { [weak self] _ in
            self?.drawable?.updateState(.Hover)
        }, for: .Hover)
        containerView.set(handler: { [weak self] _ in
            self?.drawable?.updateState(.Highlight)
        }, for: .Highlight)
        containerView.set(handler: { [weak self] _ in
            self?.drawable?.updateState(.Normal)
        }, for: .Normal)
        containerView.set(handler: { [weak self] _ in
            self?.drawable?.updateState(.Other)
        }, for: .Other)
           
    }
    
    deinit {
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func layout() {
        super.layout()
        let x: CGFloat = 11 + 18
        volumeControl.setFrameSize(contentSize.width - x - 2, 26)
        volumeControl.centerY(x: x)
        self.drawable?.centerY(x: 11)
        self.drawable_muted?.centerY(x: 11)
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? SliderContextMenuRowItem else {
            return
        }
        volumeControl.minValue = item.minValue
        volumeControl.maxValue = item.maxValue
        volumeControl.middleValue = item.midValue
        volumeControl.value = item.volume
        
        volumeControl.lineColor = item.presentation.borderColor.darker(amount: 0.4)
        volumeControl.blobColor = item.presentation.textColor
        volumeControl.didUpdateValue = { [weak item, weak self] value, sync in
            item?.didUpdateValue?(value, sync)
            self?.updateValue(value)
        }
        
        if self.drawable == nil, let menuItem = item.menuItem {
            self.drawable = AppMenuAnimatedImage(item.drawable, item.presentation.textColor, menuItem)
            self.drawable?.setFrameSize(NSMakeSize(18, 18))
            self.addSubview(self.drawable!)
        }
        if self.drawable_muted == nil, let menuItem = item.menuItem {
            self.drawable_muted = AppMenuAnimatedImage(item.drawable_muted, item.presentation.textColor, menuItem)
            self.drawable_muted?.setFrameSize(NSMakeSize(18, 18))
            self.addSubview(self.drawable_muted!)
        }
        self.drawable?.change(opacity: item.volume > 0 ? 1 : 0, animated: animated)
        self.drawable_muted?.change(opacity: item.volume > 0 ? 0 : 1, animated: animated)

        needsLayout = true
    }
    
    fileprivate func updateValue(_ value: CGFloat) {
        self.drawable?.change(opacity: value > 0 ? 1 : 0)
        self.drawable_muted?.change(opacity: value > 0 ? 0 : 1)
    }
}
