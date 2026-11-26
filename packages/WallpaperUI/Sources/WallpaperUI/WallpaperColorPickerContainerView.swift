import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore

import Postbox

import CoreGraphics
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme


private final class ColorsListView : View {
    
    private class Color : Control {
        
        var removed: Bool = false
        
        var click:(()->Void)? = nil
        
        private var selection:View?
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            layer?.cornerRadius = frameRect.height / 2
            
            scaleOnClick = true
            
            self.set(handler: { [weak self] _ in
                if self?.removed == false {
                    self?.click?()
                }
            }, for: .Click)
        }
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        func update(color: NSColor, isSelected: Bool, animated: Bool) {
            self.backgroundColor = color.withAlphaComponent(1)
            if animated {
                self.layer?.animateBackground()
            }
            if isSelected {
                let current: View
                if let c = self.selection {
                    current = c
                } else {
                    current = View(frame: self.bounds.insetBy(dx: 2, dy: 2))
                    current.layer?.cornerRadius = current.frame.height / 2
                    current.layer?.borderWidth = 2
                    self.selection = current
                    addSubview(current)
                    if animated {
                        current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                        current.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.3, removeOnCompletion: false, bounce: false)
                    }
                }
                current.layer?.borderColor = theme.colors.grayBackground.cgColor
                current.layer?.animateBorderColor()
            } else {
                if let selection = selection {
                    self.selection = nil
                    performSubviewRemoval(selection, animated: animated)
                    selection.layer?.animateScaleSpring(from: 1, to: 0.1, duration: 0.3, bounce: false)
                }
            }
        }
        override func layout() {
            super.layout()
            selection?.center()
        }
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    public override init() {
        super.init(frame: .zero)
        setup()
    }
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private func setup() {
        
    }
    
    private(set) var selected: Int = 0
    
    public var selectedColor: NSColor {
        return self.colors[selected]
    }
    
    private var colors: [NSColor] = []
    
    public var select:((Int)->Void)? = nil
    
    public var count: Int {
        return colors.count
    }
    
    public func update(colors: [NSColor], selected: Int, animated: Bool) {
        self.colors = colors
        self.selected = selected
        var subviews = self.subviews.filter {
            ($0 as? Color)?.removed == false
        }
        
        if subviews.count > colors.count {
            while subviews.count != colors.count {
                if let view = subviews.removeLast() as? Color {
                    view.removed = true
                    performSubviewRemoval(view, animated: animated)
                    view.layer?.animateScaleSpring(from: 1, to: 0.1, duration: 0.3, removeOnCompletion: false, bounce: false)
                }
                
            }
        } else if subviews.count < colors.count {
            while subviews.count != colors.count {
                let count = CGFloat(subviews.count)
                let color = Color(frame: NSMakeRect(30 * count + count * 5, 0, 30, 30))
                self.addSubview(color)
                subviews.append(color)
                
                if animated {
                    color.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    color.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.3, bounce: false)
                }
            }
        }
        
        self.selected = max(0, min(colors.count - 1, self.selected))
        
        for (i, color) in colors.enumerated() {
            let view = subviews[i] as? Color
            view?.update(color: color, isSelected: selected == i, animated: animated)
            view?.click = { [weak self] in
                self?.selected = i
                self?.select?(i)
            }
        }
    }
    
    public func size() -> NSSize {
        let count = CGFloat(colors.count)
        return NSMakeSize(30 * count + max(0, (count - 1) * 5), 30)
    }
    

}

public final class WallpaperColorPickerContainerView : View {
    public let colorEditor:WallpaperAdditionColorView = WallpaperAdditionColorView(frame: NSMakeRect(0, 4, 125, 30))
    public let colorPicker = WallpaperColorPickerView()
    private let colorsContainer: View = View(frame: NSMakeRect(0, 0, 0, 38))
    private let addColor: ImageButton = ImageButton()
    private let colorsView = ColorsListView()

    public var useTransparentBackground: Bool = false {
        didSet {
            updateLocalizationAndTheme(theme: theme)
        }
    }
    
    public var modeDidUpdate:((WallpaperColorSelectMode)->Void)? = nil
    
    private(set) var mode: WallpaperColorSelectMode = .single(NSColor(hexString: "#ffffff")!)

    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        colorsContainer.addSubview(colorEditor)
        colorsContainer.addSubview(addColor)
        colorsContainer.addSubview(colorsView)
        addSubview(colorPicker)
        addSubview(colorsContainer)
        updateLocalizationAndTheme(theme: theme)
        
        self.layer?.cornerRadius = 20
        
        
        let updateColor:(NSColor)->Void = { [weak self] color in
            guard let strongSelf = self else {
                return
            }
            let mode = strongSelf.mode.withUpdatedColor(color)
            strongSelf.modeDidUpdate?(mode)
        }
        
        colorPicker.colorChanged = updateColor
        colorEditor.colorChanged = updateColor
        
        colorEditor.resetClick = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            let mode = strongSelf.mode.withRemovedColor(strongSelf.colorsView.selected)
            strongSelf.modeDidUpdate?(mode)
        }
        
        addColor.set(handler: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            let color = strongSelf.colorsView.selectedColor
            let index = strongSelf.colorsView.selected
            let mode = strongSelf.mode.withAddedColor(color, at: index)
            strongSelf.modeDidUpdate?(mode)
        }, for: .Click)
        
        colorsView.select = { [weak self] index in
            guard let strongSelf = self else {
                return
            }
            let mode = strongSelf.mode.withUpdatedIndex(index)
            strongSelf.modeDidUpdate?(mode)
        }
    }
    
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        let theme = theme as! TelegramPresentationTheme
        if useTransparentBackground {
            colorsContainer.backgroundColor = .clear
            colorsContainer.border = []
            backgroundColor = .clear
        } else {
            colorsContainer.backgroundColor = theme.colors.grayBackground
            colorsContainer.border = [.Top, .Bottom]
            colorsContainer.borderColor = theme.colors.border
            backgroundColor = theme.colors.background
        }
                
        addColor.set(image: theme.icons.wallpaper_color_add, for: .Normal)
        _ = addColor.sizeToFit()
        addColor.setAccessibilityLabel(strings().voiceOverCommonAdd)
    }
    
    public func updateMode(_ mode: WallpaperColorSelectMode, animated: Bool) {
        self.mode = mode
        switch mode {
        case let .single(color):
            self.colorsView.update(colors: [color], selected: 0, animated: animated)
            colorEditor.defaultColor = color
            addColor.isHidden = !canUseGradient
        case let .gradient(colors, selected, _):
            self.colorsView.update(colors: colors, selected: selected, animated: animated)
            addColor.isHidden = colors.count > 3
            colorEditor.defaultColor = colors[selected]
        }
        colorPicker.color = colorEditor.defaultColor
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate
        updateLayout(size: frame.size, transition: transition)
    }
    
    public var canUseGradient: Bool = false {
        didSet {
            addColor.isHidden = !self.canUseGradient
        }
    }
    
    public var colorChanged: ((WallpaperColorSelectMode) -> Void)? = nil

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let pickerHeight: CGFloat = size.height
        transition.updateFrame(view: colorPicker, frame: NSMakeRect(0, 38, size.width, pickerHeight - 38))
        transition.updateFrame(view: colorsContainer, frame: NSMakeRect(0, 0, size.width, 38))
        
        transition.updateFrame(view: colorsView, frame: CGRect(origin: .init(x: 10, y: 4), size: colorsView.size()))

        var c_e_w: CGFloat = colorsView.frame.width > 0 ? frame.width - (colorsView.frame.width + 30) : (size.width - 20)
        
        if colorsView.count < 4, !addColor.isHidden {
            c_e_w -= (addColor.frame.width + 10)
        }
        switch self.mode {
        case .gradient:
            transition.updateFrame(view: colorEditor, frame: NSMakeRect(10 + colorsView.frame.maxX, 4, c_e_w, 30))
            colorEditor.updateLayout(size: colorEditor.frame.size, transition: transition)
        case .single:
            transition.updateFrame(view: colorEditor, frame: NSMakeRect(10 + colorsView.frame.maxX, 4, c_e_w, 30))
            colorEditor.updateLayout(size: colorEditor.frame.size, transition: transition)
        }
        transition.updateFrame(view: addColor, frame: addColor.centerFrameY(x: frame.width - addColor.frame.width - 10))
    }
    
    public override func layout() {
        updateLayout(size: frame.size, transition: .immediate)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

