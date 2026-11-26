import Cocoa
import TGUIKit
import MapKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import ObjcUtils

enum LocationSelectCurrentState : Equatable {
    case accurate(location: CLLocation?, expanded: Bool)
    case selected(location: String)
}

class LocationSendCurrentItem: GeneralRowItem {
    fileprivate let statusLayout: TextViewLayout
    fileprivate let state: LocationSelectCurrentState
    fileprivate let destination: SelectLocationDestination
    init(_ initialSize: NSSize, stableId: AnyHashable, state: LocationSelectCurrentState, destination: SelectLocationDestination, action:@escaping()->Void) {
        self.state = state
        self.destination = destination
        let text: String
        switch state {
        case let .accurate(location, _):
            if let location = location {
                let formatter = MKDistanceFormatter()
                formatter.unitStyle = .full
                formatter.locale = Locale(identifier: appAppearance.language.languageCode)
                let formatted = formatter.string(fromDistance: location.horizontalAccuracy)
                text = strings().locationSendAccurateTo("\(formatted)")
            } else {
                text = strings().locationSendLocating
            }
            
        case let .selected(location):
            text = location
        }
        statusLayout = TextViewLayout.init(.initialize(string: text, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
        super.init(initialSize, height: 60, stableId: stableId, action: action, inset: NSEdgeInsetsMake(0, 10, 0, 10))
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        statusLayout.measure(width: width - inset.left - inset.right - theme.icons.locationPin.backingSize.width - 10)
        return success
    }
    
    var buttonText: String {
        let text: String
        switch state {
        case .accurate:
            switch destination {
            case .chat:
                text = strings().locationSendMyLocation
            case .business:
                text = strings().locationSetLocation
            case .select:
                text = strings().locationSelectMyLocation
            }
        case .selected:
            switch destination {
            case .chat:
                text = strings().locationSendThisLocation
            case .business:
                text = strings().locationSetLocation
            case .select:
                text = strings().locationSelectThisLocation
            }
        }
        return text
    }

    override var accessibilityLabel: String? {
        return buttonText
    }

    override var accessibilityValue: String? {
        return statusLayout.attributedString.string
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }

    override func viewClass() -> AnyClass {
        return LocationSendCurrentView.self
    }
}


private final class LocationSendCurrentView : TableRowView {
    private let iconView: ImageView = ImageView()
    private let statusView = TextView()
    private let button: TextButton = TextButton()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(button)
        addSubview(iconView)
        addSubview(statusView)
        iconView.isAccessibilityDecorative = true
        statusView.userInteractionEnabled = false
        statusView.isSelectable = false
        button.userInteractionEnabled = false
        button.isEventLess = true
        statusView.isEventLess = true
    }
    
    override func mouseUp(with event: NSEvent) {
        if mouseInside() {
            guard let item = item as? GeneralRowItem else {return}
            item.action()
        } else {
            super.mouseUp(with: event)
        }
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? LocationSendCurrentItem else {return}

        
        button.set(font: .medium(.title), for: .Normal)
        button.set(color: theme.colors.accent, for: .Normal)
        let text = item.buttonText
        button.set(text: text, for: .Normal)
        _ = button.sizeToFit()
        
        statusView.update(item.statusLayout)
        
        iconView.image = theme.icons.locationPin
        iconView.sizeToFit()
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        guard let item = item as? LocationSendCurrentItem else {return}
        
        switch item.state {
        case let .accurate(_, expanded):
            if expanded {
                ctx.setFillColor(theme.colors.border.cgColor)
                ctx.fill(NSMakeRect(statusView.frame.minX, frame.height - .borderSize, frame.width - statusView.frame.minX, .borderSize))
            }
        default:
            break
        }
        
    }
    
    override func layout() {
        guard let item = item as? GeneralRowItem else {return}
        
        iconView.centerY(x: item.inset.left)
        
        button.setFrameOrigin(iconView.frame.maxX + 10, frame.height / 2 - button.frame.height - 2)
        statusView.setFrameOrigin(iconView.frame.maxX + 10,  frame.height / 2 + 2)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}
