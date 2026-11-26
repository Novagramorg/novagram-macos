import Cocoa
import TGUIKit
import GraphCore

public enum ChartStyle: Equatable {
    case classic
    case glass
    case glassFill
    
    public var usesGlass: Bool {
        return self != .classic
    }
    
    public var fillsLineArea: Bool {
        return self == .glassFill
    }
}

extension ChartTheme {
    var glassAppearance: LiquidGlassAppearance {
        let color = self.chartBackgroundColor.usingColorSpace(.sRGB) ?? self.chartBackgroundColor
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance < 0.5 ? .forceDark : .forceLight
    }
}
