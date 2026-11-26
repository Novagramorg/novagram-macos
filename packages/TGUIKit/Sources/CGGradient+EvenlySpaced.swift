import Cocoa

public extension CGGradient {
    static func evenlySpaced(_ colors: [CGColor], colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()) -> CGGradient? {
        guard !colors.isEmpty else {
            return nil
        }
        let delta: CGFloat = 1.0 / (CGFloat(colors.count) - 1.0)
        var locations: [CGFloat] = []
        for i in 0 ..< colors.count {
            locations.append(delta * CGFloat(i))
        }
        return CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)
    }
    
    static func evenlySpaced(_ colors: [NSColor], colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()) -> CGGradient? {
        return evenlySpaced(colors.map { $0.cgColor }, colorSpace: colorSpace)
    }
}
