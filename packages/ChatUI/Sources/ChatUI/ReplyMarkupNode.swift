import Cocoa
import TelegramCore

import TGUIKit
import Postbox
import SwiftSignalKit
import Localization
import TelegramTheme
import TelegramUtils
import GeneralRows
import InlineStickerLayer


final class ReplyMarkupContainerView: View {
    var accountIdentity: ObjectIdentifier?
}

public class ReplyMarkupButtonLayout {

    public private(set) var width:CGFloat = 0
    public let text:TextViewLayout
    public let button:ReplyMarkupButton
    public let presentation: TelegramPresentationTheme
    public let styleBackgroundColor: NSColor?

    public init(button:ReplyMarkupButton, theme: TelegramPresentationTheme, isInput: Bool, paid: Bool, xtrAmount: Int64?) {
        self.button = button
        self.presentation = theme
        let attr = NSMutableAttributedString()

        var styleColor: NSColor? = nil
        if let color = button.style?.color {
            switch color {
            case .success:
                styleColor = theme.colors.greenUI.withAlphaComponent(isInput ? 1 : 0.8)
            case .danger:
                styleColor = theme.colors.redUI.withAlphaComponent(isInput ? 1 : 0.8)
            case .primary:
                styleColor = theme.colors.accent.withAlphaComponent(isInput ? 1 : 0.8)
            }
        }
        self.styleBackgroundColor = styleColor

        let color: NSColor
        if let styleColor = styleColor {
            color = styleColor.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
        } else {
            color = theme.controllerBackgroundMode.hasWallpaper && !isInput ? theme.chatServiceItemTextColor : theme.colors.text
        }

        attr.append(string: paid ? strings().messageReplyActionButtonShowReceipt : button.title.fixed, color: color, font: .semibold(.short))

        if let iconFileId = button.style?.iconFileId {
            attr.insert(.initialize(string: clown_space), at: 0)
            
            attr.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(source: .attribute(.init(fileId: iconFileId, file: nil, emoji: clown, color: nil))), range: NSMakeRange(0, clown.length))
        }

        switch button.action {
        case let .url(url):
            switch url {
            case SuggestedPostMessageAttribute.commandApprove:
                attr.insert(.initialize(string: clown_space), at: 0)
                attr.insertEmbedded(.embedded(name: "Icon_SuggestPost_Approve", color: theme.chatServiceItemTextColor, resize: false), for: clown)
            case SuggestedPostMessageAttribute.commandDecline:
                attr.insert(.initialize(string: clown_space), at: 0)
                attr.insertEmbedded(.embedded(name: "Icon_SuggestPost_Decline", color: theme.chatServiceItemTextColor, resize: false), for: clown)
            case SuggestedPostMessageAttribute.commandChanges:
                attr.insert(.initialize(string: clown_space), at: 0)
                attr.insertEmbedded(.embedded(name: "Icon_SuggestPost_Edit", color: theme.chatServiceItemTextColor, resize: false), for: clown)
            default:
                break
            }
        default:
            break
        }

        self.text = TextViewLayout(attr, maximumNumberOfLines: 1, truncationType: .middle, cutout: nil, alignment: .center, alwaysStaticItems: true)
    }
    
    public func measure(_ width:CGFloat) {
        text.measure(width: width - 8)
        self.width = width
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
}

/// A rounded-rect path with independent per-corner radii (layer coords: y=0 top, y=height bottom),
/// for masking reply-markup buttons that mix the normal small radius with a larger outer corner.
private func replyMarkupRoundedPath(size: NSSize, topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let w = size.width
    let h = size.height
    path.move(to: CGPoint(x: topLeft, y: 0))
    path.addLine(to: CGPoint(x: w - topRight, y: 0))
    path.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: topRight), radius: topRight)
    path.addLine(to: CGPoint(x: w, y: h - bottomRight))
    path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - bottomRight, y: h), radius: bottomRight)
    path.addLine(to: CGPoint(x: bottomLeft, y: h))
    path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - bottomLeft), radius: bottomLeft)
    path.addLine(to: CGPoint(x: 0, y: topLeft))
    path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: topLeft, y: 0), radius: topLeft)
    path.closeSubpath()
    return path
}

public class ReplyMarkupNode: Node {

    public static let buttonHeight:CGFloat = 34
    public static let buttonPadding:CGFloat = 2
    public static let rowHeight = buttonHeight + buttonPadding

    private var width:CGFloat = 0
    private var height:CGFloat = 0

    private let markup:[[ReplyMarkupButtonLayout]]
    private let flags:ReplyMarkupMessageFlags

    private let interactions:ReplyMarkupInteractions
    private let isInput: Bool
    private let theme: TelegramPresentationTheme
    private let xtr: Bool
    private let isPostSuggest: Bool
    public let outerCornerRadius: CGFloat
    /// When true (input keyboard) the first row's top-outer corners are also rounded for a full block.
    /// When false (bubble-attached buttons) only the last row's bottom-outer corners round, and the
    /// other buttons keep their normal small radius instead of being squared.
    public let roundsTopCorners: Bool
    public init(_ rows:[ReplyMarkupRow], _ flags:ReplyMarkupMessageFlags, _ interactions:ReplyMarkupInteractions, _ theme: TelegramPresentationTheme, _ view:View? = nil, _ isInput: Bool = false, paid: Bool = false, xtrAmount: Int64? = nil, isPostSuggest: Bool = false, outerCornerRadius: CGFloat = 0, roundsTopCorners: Bool = true) {
        self.flags = flags
        self.isInput = isInput
        self.isPostSuggest = isPostSuggest
        self.xtr = xtrAmount != nil
        self.interactions = interactions
        self.theme = theme
        self.outerCornerRadius = outerCornerRadius
        self.roundsTopCorners = roundsTopCorners
        var layoutRows:[[ReplyMarkupButtonLayout]] = Array(repeating: [], count: rows.count)
        for i in 0 ..< rows.count {
            for button in rows[i].buttons {
                layoutRows[i].append(ReplyMarkupButtonLayout(button: button, theme: theme, isInput: isInput, paid: paid, xtrAmount: xtrAmount))
            }
        }
        self.markup = layoutRows
        super.init(view)
    }
    
    public var shouldBlurService: Bool {
        return !TelegramUtilsHooks.shared.isLite(.blur) && theme.shouldBlurService
    }
    
    public func redraw() {
        guard let view else { return }
        let previousSubviews = view.subviews
        let container = view as? ReplyMarkupContainerView
        let accountIdentity = ObjectIdentifier(interactions.context.account)
        let canReuse = container?.accountIdentity == accountIdentity && NSEvent.pressedMouseButtons == 0
        var updatedSubviews: [NSView] = []
        updatedSubviews.reserveCapacity(markup.reduce(0) { $0 + $1.count })
        for row in markup {
            for button in row {
                var actionImage: CGImage?
                switch button.button.action {
                case let .url(url):
                    if !url.isSingleEmoji, !isPostSuggest {
                        actionImage = theme.chat.chatActionUrl(theme: theme)
                    }
                    
                case .payment:
                    if !xtr {
                        actionImage = theme.chat.chatInvoiceAction(theme: theme)
                    }
                case .switchInline:
                    actionImage = theme.chat.chatActionShare(theme: theme)
                case .openUserProfile:
                    actionImage = theme.chat.chatActionProfile(theme: theme)
                case .openWebApp, .openWebView:
                    actionImage = theme.chat.chatActionWebUrl(theme: theme)
                case .copyText:
                    actionImage = theme.chat.chatActionCopy(theme: theme)
                default:
                    break
                }
                let btnView: InteractiveTextView
                let index = updatedSubviews.count
                if canReuse, index < previousSubviews.count, let current = previousSubviews[index] as? InteractiveTextView,
                   current.controlState != .Highlight, current.layer?.animationKeys()?.isEmpty != false {
                    btnView = current
                    btnView.removeAllHandlers()
                    btnView.controlState = .Normal
                    btnView.layer?.mask = nil
                    btnView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
                } else {
                    btnView = InteractiveTextView()
                }
                btnView.set(handler: { [weak self, weak button] control in
                    if let button = button {
                        self?.proccess(control, button.button)
                    }
                }, for: .Click)
                
                btnView.scaleDownOnClick = true
    
                btnView.layer?.cornerRadius = .cornerRadius
                btnView.textView.isSelectable = false
                
                if let styleColor = button.styleBackgroundColor {
                    btnView.blurBackground = nil
                    btnView.backgroundColor = styleColor
                } else if !self.isInput && shouldBlurService {
                    btnView.blurBackground = button.presentation.blurServiceColor
                    btnView.backgroundColor = .clear
                } else {
                    btnView.blurBackground = nil
                    if button.presentation.hasWallpaper && !self.isInput {
                        btnView.backgroundColor = button.presentation.chatServiceItemColor
                    } else {
                        btnView.backgroundColor = button.presentation.colors.grayForeground
                    }
                }
                btnView.set(text: button.text, context: self.interactions.context)
                
                if let actionImage {
                    let urlView = btnView.subviews.first(where: { $0 is ImageView }) as? ImageView ?? ImageView()
                    urlView.image = actionImage
                    urlView.sizeToFit()
                    urlView.isAccessibilityDecorative = true
                    if urlView.superview !== btnView { btnView.addSubview(urlView) }
                } else {
                    for child in btnView.subviews where child is ImageView { child.removeFromSuperview() }
                }
                updatedSubviews.append(btnView)
            }
        }
        if previousSubviews.count != updatedSubviews.count || !zip(previousSubviews, updatedSubviews).allSatisfy({ $0 === $1 }) {
            for previous in previousSubviews where !updatedSubviews.contains(where: { $0 === previous }) {
                (previous as? Control)?.removeAllHandlers()
            }
            view.subviews = updatedSubviews
        }
        container?.accountIdentity = accountIdentity
    }
    
    public func proccess(_ control:Control, _ button:ReplyMarkupButton) {
        interactions.proccess(button, { _ in
           // control?.backgroundColor = loading ? .black : theme.colors.grayBackground
        })
    }
    
    public func layout(transition: ContainedViewLayoutTransition = .immediate) {
        var y:CGFloat = 0

        var i:Int = 0
        let lastRowIdx = markup.count - 1
        for (rowIdx, row) in markup.enumerated() {
            var j:Int = 0
            var rect:NSRect = NSMakeRect(0,y,0,0)
            let lastColIdx = row.count - 1
            for button in row {
                var w = button.width
                if j == row.count - 1 {
                    w = self.width - rect.minX
                }
                rect.size = NSMakeSize(w, ReplyMarkupNode.buttonHeight)
                let btnView:InteractiveTextView? = view?.subviews[i] as? InteractiveTextView

                if let styleColor = button.styleBackgroundColor {
                    btnView?.blurBackground = nil
                    btnView?.backgroundColor = styleColor
                } else if !self.isInput && self.shouldBlurService {
                    btnView?.blurBackground = button.presentation.blurServiceColor
                    btnView?.backgroundColor = .clear
                } else {
                    btnView?.blurBackground = nil
                    if button.presentation.hasWallpaper && !self.isInput {
                        btnView?.backgroundColor = button.presentation.chatServiceItemColor
                    } else {
                        btnView?.backgroundColor = button.presentation.colors.grayForeground
                    }
                }
                if let btnView = btnView {
                    transition.updateFrame(view: btnView, frame: rect)
                    btnView.textView.setNeedsDisplayLayer()
                    if !btnView.subviews.isEmpty, let urlView = btnView.subviews.first(where: { $0 is ImageView }) {

                        transition.updateFrame(view: urlView, frame: NSMakeRect(rect.width - urlView.frame.width - 5, 5, urlView.frame.width, urlView.frame.height))

                    }
                    if outerCornerRadius > 0 {
                        if roundsTopCorners {
                            // Input keyboard: a seamless block — outer corners rounded, inner square.
                            var corners: CACornerMask = []
                            if rowIdx == 0 && j == 0 { corners.insert(.layerMinXMinYCorner) }
                            if rowIdx == 0 && j == lastColIdx { corners.insert(.layerMaxXMinYCorner) }
                            if rowIdx == lastRowIdx && j == 0 { corners.insert(.layerMinXMaxYCorner) }
                            if rowIdx == lastRowIdx && j == lastColIdx { corners.insert(.layerMaxXMaxYCorner) }
                            btnView.layer?.mask = nil
                            if !corners.isEmpty {
                                btnView.layer?.cornerRadius = outerCornerRadius
                                btnView.layer?.maskedCorners = corners
                            } else {
                                btnView.layer?.cornerRadius = 0
                                btnView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
                            }
                        } else {
                            // Bubble-attached: every corner keeps the normal small radius; only the
                            // last row's bottom-outer corners grow to `outerCornerRadius`. Mixed radii
                            // need a per-corner mask path (a single layer cornerRadius can't do it).
                            let small: CGFloat = .cornerRadius
                            var bl = small, br = small
                            if rowIdx == lastRowIdx && j == 0 { bl = outerCornerRadius }
                            if rowIdx == lastRowIdx && j == lastColIdx { br = outerCornerRadius }
                            if bl != small || br != small {
                                let mask = (btnView.layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
                                mask.path = replyMarkupRoundedPath(size: rect.size, topLeft: small, topRight: small, bottomLeft: bl, bottomRight: br)
                                btnView.layer?.cornerRadius = 0
                                btnView.layer?.mask = mask
                            } else {
                                btnView.layer?.mask = nil
                                btnView.layer?.cornerRadius = small
                                btnView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
                            }
                        }
                    }
                }

                rect = rect.offsetBy(dx: w + ReplyMarkupNode.buttonPadding, dy: 0)
                i += 1
                j += 1
            }
            y += ReplyMarkupNode.rowHeight
        }
    }
    
    public var hasButtons:Bool {
        return !markup.isEmpty
    }

    /// Height is a pure function of the row count (no width involvement),
    /// so it can be computed before `measureSize(_:)` is called. Useful for
    /// callers that need to size their container before they know the
    /// available width for button text layout.
    public var precomputedHeight: CGFloat {
        guard !markup.isEmpty else { return 0 }
        return CGFloat(markup.count) * ReplyMarkupNode.buttonHeight + CGFloat(markup.count - 1) * ReplyMarkupNode.buttonPadding
    }

    public override func measureSize(_ width: CGFloat) {
        for row in markup {
            let count = row.count
            
            let single:CGFloat = floorToScreenPixels(System.backingScale, (width - CGFloat(ReplyMarkupNode.buttonPadding * CGFloat(count - 1))) / CGFloat(count))
            for button in row {
                button.measure(single)
            }
        }
        self.width = width
        self.height = CGFloat(CGFloat(markup.count) * ReplyMarkupNode.buttonHeight) + CGFloat(CGFloat(markup.count - 1) * ReplyMarkupNode.buttonPadding)
    }
    
    public override var size: NSSize {
        get {
            return NSMakeSize(width, height)
        }
        set {
            super.size = newValue
        }
    }
    
}
