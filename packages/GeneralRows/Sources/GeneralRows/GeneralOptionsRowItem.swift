import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

public final class GeneralOptionsRowItem : GeneralRowItem {
    
    public struct InputOption {
        public var image: NSImage
        public var title: String
        public var info: String
        public init(image: NSImage, title: String, info: String) {
            self.image = image
            self.title = title
            self.info = info
        }
    }
    
    public let options: [OptionsListView.Option]
    public let spacing: CGFloat
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, input: [InputOption], spacing: CGFloat = 20) {
        self.spacing = spacing
        self.options = input.map { input in
            GeneralOptionsRowItem.makeOption(input, width: initialSize.width - 40)
        }
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }
    
    public static func makeOption(_ input: InputOption, width: CGFloat, infoImage: CGImage? = nil, widthInset: CGFloat = 0) -> OptionsListView.Option {
        return .init(image: input.image.precomposed(theme.colors.accent), header: .init(.initialize(string: input.title, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: input.info, color: theme.colors.grayText, font: .normal(.text))), width: width, infoImage: infoImage, widthInset: widthInset)
    }
    
    public override var height: CGFloat {
        return OptionsListView.height(options: options, spacing: spacing)
    }
    
    public override func viewClass() -> AnyClass {
        return RowView.self
    }

    public override var accessibilityLabel: String? {
        let lines: [String] = options.map { option in
            [option.header.attributedString.string, option.text.attributedString.string].filter { !$0.isEmpty }.joined(separator: ", ")
        }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class RowView: GeneralContainableRowView {
    
    private let optionsView = OptionsListView(frame: .zero)
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(optionsView)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        optionsView.centerX(y: 0)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? GeneralOptionsRowItem else {
            return
        }
        optionsView.spacing = item.spacing
        optionsView.update(options: item.options)
        needsLayout = true
    }
}
