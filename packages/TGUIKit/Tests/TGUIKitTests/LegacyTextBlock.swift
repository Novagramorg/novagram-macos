import Cocoa
import TGUIKit

extension TextViewLayout {
    func legacyGenerateBlock(for range: NSRange, backgroundColor: NSColor) -> (CGPoint, CGImage?) {

        let rectsAndLines = rects(range)
        var rects = rectsAndLines.map { $0.0 }
        let lines = rectsAndLines.map { $0.1 }

        if !rects.isEmpty {
            let sortedIndices = (0 ..< rects.count).sorted(by: { rects[$0].width > rects[$1].width })
            for i in 0 ..< sortedIndices.count {
                let index = sortedIndices[i]
                for j in -1 ... 1 {
                    if j != 0 && index + j >= 0 && index + j < sortedIndices.count {
                        if abs(rects[index + j].width - rects[index].width) < 10 {
                            rects[index + j].size.width = max(rects[index + j].width, rects[index].width)
                        }
                    }
                }
            }

            for i in 0 ..< rects.count {
                let height = rects[i].size.height
                rects[i] = rects[i].insetBy(dx: 0, dy: floor((rects[i].height - height) / 2.0))
                rects[i].size.height = height

                if lines[i].penFlush == 1.0 {
                    rects[i].origin.x = layoutSize.width - rects[i].width
                } else if lines[i].penFlush == 0.5 {
                    rects[i].origin.x = floor((layoutSize.width - rects[i].width) / 2.0)
                }

            }

            return generateRectsImage(color: backgroundColor, rects: rects, inset: 0, outerRadius: 4, innerRadius: 4, useModernPathCalculation: false)

        } else {
            return (.zero, nil)
        }

    }

    func legacyGenerateBlock(backgroundColor: NSColor) -> (CGPoint, CGImage?) {

        let lines = self.lines.filter { self.attributedString.attributedSubstring(from: $0.range).string != "\n" }
        var rects = lines.map({ $0.frame })


        if !rects.isEmpty {
            let sortedIndices = (0 ..< rects.count).sorted(by: { rects[$0].width > rects[$1].width })
            for i in 0 ..< sortedIndices.count {
                let index = sortedIndices[i]
                for j in -1 ... 1 {
                    if j != 0 && index + j >= 0 && index + j < sortedIndices.count {
                        if abs(rects[index + j].width - rects[index].width) < 10 {
                            rects[index + j].size.width = max(rects[index + j].width, rects[index].width)
                        }
                    }
                }
            }

            for i in 0 ..< rects.count {
                let height = rects[i].size.height + 5
                rects[i] = rects[i].insetBy(dx: 0, dy: floor((rects[i].height - height) / 2.0))
                rects[i].size.height = height

                if lines[i].penFlush == 1.0 {
                    rects[i].origin.x = layoutSize.width - rects[i].width - 5
                    rects[i].size.width += 10
                } else if lines[i].penFlush == 0.5 {
                    rects[i].origin.x = floor((layoutSize.width - rects[i].width) / 2.0)
                    rects[i].size.width += 20
                } else {
                    rects[i].size.width += 10
                    rects[i].origin.x -= 5
                }

            }

            var image = legacyBlockRectsImage(color: backgroundColor, rects: rects, inset: 0, outerRadius: lines.count == 1 ? rects[0].height / 2 : 10, innerRadius: .cornerRadius)
            image.0 = NSMakePoint(0, 0)

            return image
        } else {
            return (.zero, nil)
        }
    }

}

private enum LegacyBlockCornerType {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}


private func legacyBlockDrawFullCorner(context: CGContext, color: NSColor, at point: CGPoint, type: LegacyBlockCornerType, radius: CGFloat) {
    context.setFillColor(color.cgColor)
    switch type {
    case .topLeft:
        context.clear(CGRect(origin: point, size: CGSize(width: radius, height: radius)))
        context.fillEllipse(in: CGRect(origin: point, size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .topRight:
        context.clear(CGRect(origin: CGPoint(x: point.x - radius, y: point.y), size: CGSize(width: radius, height: radius)))
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x - radius * 2.0, y: point.y), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .bottomLeft:
        context.clear(CGRect(origin: CGPoint(x: point.x, y: point.y - radius), size: CGSize(width: radius, height: radius)))
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x, y: point.y - radius * 2.0), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .bottomRight:
        context.clear(CGRect(origin: CGPoint(x: point.x - radius, y: point.y - radius), size: CGSize(width: radius, height: radius)))
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x - radius * 2.0, y: point.y - radius * 2.0), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    }
}

private func legacyBlockDrawConnectingCorner(context: CGContext, color: NSColor, at point: CGPoint, type: LegacyBlockCornerType, radius: CGFloat) {
    context.setFillColor(color.cgColor)
    switch type {
    case .topLeft:
        context.fill(CGRect(origin: CGPoint(x: point.x - radius, y: point.y), size: CGSize(width: radius, height: radius)))
        context.setFillColor(NSColor.clear.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x - radius * 2.0, y: point.y), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .topRight:
        context.fill(CGRect(origin: CGPoint(x: point.x, y: point.y), size: CGSize(width: radius, height: radius)))
        context.setFillColor(NSColor.clear.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x, y: point.y), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .bottomLeft:
        context.fill(CGRect(origin: CGPoint(x: point.x - radius, y: point.y - radius), size: CGSize(width: radius, height: radius)))
        context.setFillColor(NSColor.clear.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x - radius * 2.0, y: point.y - radius * 2.0), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .bottomRight:
        context.fill(CGRect(origin: CGPoint(x: point.x, y: point.y - radius), size: CGSize(width: radius, height: radius)))
        context.setFillColor(NSColor.clear.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x, y: point.y - radius * 2.0), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    }
}




private func legacyBlockRectsImage(color: NSColor, rects: [CGRect], inset: CGFloat, outerRadius: CGFloat, innerRadius: CGFloat) -> (CGPoint, CGImage?) {
    if rects.isEmpty {
        return (CGPoint(), nil)
    }

    var topLeft = rects[0].origin
    var bottomRight = CGPoint(x: rects[0].maxX, y: rects[0].maxY)
    for i in 1 ..< rects.count {
        topLeft.x = min(topLeft.x, rects[i].origin.x)
        topLeft.y = min(topLeft.y, rects[i].origin.y)
        bottomRight.x = max(bottomRight.x, rects[i].maxX)
        bottomRight.y = max(bottomRight.y, rects[i].maxY)
    }

    topLeft.x -= inset
    topLeft.y -= inset
    bottomRight.x += inset * 2
    bottomRight.y += inset * 2

    return (topLeft, generateImage(CGSize(width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y), contextGenerator: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setFillColor(color.cgColor)

        context.setBlendMode(.copy)

        for i in 0 ..< rects.count {
            let rect = rects[i].insetBy(dx: -inset, dy: -inset)
            context.fill(rect.offsetBy(dx: -topLeft.x, dy: -topLeft.y))
        }

        for i in 0 ..< rects.count {
            let rect = rects[i].insetBy(dx: -inset, dy: -inset).offsetBy(dx: -topLeft.x, dy: -topLeft.y)

            var previous: CGRect?
            if i != 0 {
                previous = rects[i - 1].insetBy(dx: -inset, dy: -inset).offsetBy(dx: -topLeft.x, dy: -topLeft.y)
            }

            var next: CGRect?
            if i != rects.count - 1 {
                next = rects[i + 1].insetBy(dx: -inset, dy: -inset).offsetBy(dx: -topLeft.x, dy: -topLeft.y)
            }

            if let previous = previous {
                if previous.contains(rect.topLeft) {
                    if abs(rect.topLeft.x - previous.minX) >= innerRadius {
                        var radius = innerRadius
                        if let next = next {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        legacyBlockDrawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.topLeft.x, y: previous.maxY), type: .topLeft, radius: radius)
                    }
                } else {
                    legacyBlockDrawFullCorner(context: context, color: color, at: rect.topLeft, type: .topLeft, radius: outerRadius)
                }
                if previous.contains(rect.topRight.offsetBy(dx: -1.0, dy: 0.0)) {
                    if abs(rect.topRight.x - previous.maxX) >= innerRadius {
                        var radius = innerRadius
                        if let next = next {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        legacyBlockDrawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.topRight.x, y: previous.maxY), type: .topRight, radius: radius)
                    }
                } else {
                    legacyBlockDrawFullCorner(context: context, color: color, at: rect.topRight, type: .topRight, radius: outerRadius)
                }
            } else {
                legacyBlockDrawFullCorner(context: context, color: color, at: rect.topLeft, type: .topLeft, radius: outerRadius)
                legacyBlockDrawFullCorner(context: context, color: color, at: rect.topRight, type: .topRight, radius: outerRadius)
            }

            if let next = next {
                if next.contains(rect.bottomLeft) {
                    if abs(rect.bottomRight.x - next.maxX) >= innerRadius {
                        var radius = innerRadius
                        if let previous = previous {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        legacyBlockDrawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.bottomLeft.x, y: next.minY), type: .bottomLeft, radius: radius)
                    }
                } else {
                    legacyBlockDrawFullCorner(context: context, color: color, at: rect.bottomLeft, type: .bottomLeft, radius: outerRadius)
                }
                if next.contains(rect.bottomRight.offsetBy(dx: -1.0, dy: 0.0)) {
                    if abs(rect.bottomRight.x - next.maxX) >= innerRadius {
                        var radius = innerRadius
                        if let previous = previous {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        legacyBlockDrawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.bottomRight.x, y: next.minY), type: .bottomRight, radius: radius)
                    }
                } else {
                    legacyBlockDrawFullCorner(context: context, color: color, at: rect.bottomRight, type: .bottomRight, radius: outerRadius)
                }
            } else {
                legacyBlockDrawFullCorner(context: context, color: color, at: rect.bottomLeft, type: .bottomLeft, radius: outerRadius)
                legacyBlockDrawFullCorner(context: context, color: color, at: rect.bottomRight, type: .bottomRight, radius: outerRadius)
            }
        }
    }))

}

