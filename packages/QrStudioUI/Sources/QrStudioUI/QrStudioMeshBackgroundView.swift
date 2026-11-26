import Foundation
import Cocoa
import TGUIKit

private func qrStudioMeshWeights(_ t: Double) -> (Double, Double, Double) {
    var u = min(max(t, 0.0), 1.0) * 2.0
    let isSecond = u >= 1.0
    if isSecond {
        u -= 1.0
    }
    let u2 = u * u
    let u3 = u2 * u
    let h00 = 2.0 * u3 - 3.0 * u2 + 1.0
    let h10 = u3 - 2.0 * u2 + u
    let h01 = -2.0 * u3 + 3.0 * u2
    let h11 = u3 - u2
    if isSecond {
        return (-h10 * 0.5, h00 - h11, h10 * 0.5 + h01 + h11)
    }
    return (h00 - h10 - h11 * 0.5, h10 + h01, h11 * 0.5)
}

private func qrStudioMeshSurface(_ values: [Double], stride: Int, component: Int, _ ws: (Double, Double, Double), _ wt: (Double, Double, Double)) -> Double {
    func row(_ r: Int) -> Double {
        let base = r * 3 * stride + component
        return values[base] * ws.0 + values[base + stride] * ws.1 + values[base + 2 * stride] * ws.2
    }
    return row(0) * wt.0 + row(1) * wt.1 + row(2) * wt.2
}

private func qrStudioMeshPoint(_ points: [Double], _ s: Double, _ t: Double) -> (x: Double, y: Double) {
    let ws = qrStudioMeshWeights(s)
    let wt = qrStudioMeshWeights(t)
    return (qrStudioMeshSurface(points, stride: 2, component: 0, ws, wt), qrStudioMeshSurface(points, stride: 2, component: 1, ws, wt))
}

private func qrStudioMeshInverse(_ points: [Double], _ x: Double, _ y: Double) -> (s: Double, t: Double) {
    var s = x
    var t = y
    let h = 1e-4
    for _ in 0 ..< 8 {
        let p = qrStudioMeshPoint(points, s, t)
        let ex = p.x - x
        let ey = p.y - y
        if abs(ex) < 1e-5 && abs(ey) < 1e-5 {
            break
        }
        let s0 = max(0.0, s - h)
        let s1 = min(1.0, s + h)
        let t0 = max(0.0, t - h)
        let t1 = min(1.0, t + h)
        let ps1 = qrStudioMeshPoint(points, s1, t)
        let ps0 = qrStudioMeshPoint(points, s0, t)
        let pt1 = qrStudioMeshPoint(points, s, t1)
        let pt0 = qrStudioMeshPoint(points, s, t0)
        let dsx = (ps1.x - ps0.x) / (s1 - s0)
        let dsy = (ps1.y - ps0.y) / (s1 - s0)
        let dtx = (pt1.x - pt0.x) / (t1 - t0)
        let dty = (pt1.y - pt0.y) / (t1 - t0)
        let det = dsx * dty - dtx * dsy
        guard abs(det) > 1e-9 else {
            break
        }
        s = min(max(s - (dty * ex - dtx * ey) / det, 0.0), 1.0)
        t = min(max(t - (-dsy * ex + dsx * ey) / det, 0.0), 1.0)
    }
    return (s, t)
}

private func qrStudioMeshBackdropImage(colors: [QrStudioColor], points: [SIMD2<Float>], width: Int, height: Int, overscan: Double) -> CGImage? {
    guard colors.count == 9, points.count == 9, width > 1, height > 1, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
        return nil
    }
    var lab: [Double] = []
    lab.reserveCapacity(27)
    for color in colors {
        let (l, a, b) = color.oklab
        lab.append(Double(l))
        lab.append(Double(a))
        lab.append(Double(b))
    }
    var mesh: [Double] = []
    mesh.reserveCapacity(18)
    for point in points {
        mesh.append(Double(point.x))
        mesh.append(Double(point.y))
    }
    let span = 1.0 + overscan * 2.0

    let gridX = 17
    let gridY = max(17, min(48, Int(ceil(17.0 * Double(height) / Double(width)))))
    var gridS = [Double](repeating: 0.0, count: gridX * gridY)
    var gridT = [Double](repeating: 0.0, count: gridX * gridY)
    for j in 0 ..< gridY {
        for i in 0 ..< gridX {
            let st = qrStudioMeshInverse(mesh, Double(i) / Double(gridX - 1), Double(j) / Double(gridY - 1))
            gridS[j * gridX + i] = st.s
            gridT[j * gridX + i] = st.t
        }
    }

    func sample(_ grid: [Double], _ i0: Int, _ j0: Int, _ fx: Double, _ fy: Double) -> Double {
        let a = grid[j0 * gridX + i0]
        let b = grid[j0 * gridX + i0 + 1]
        let c = grid[(j0 + 1) * gridX + i0]
        let d = grid[(j0 + 1) * gridX + i0 + 1]
        let top = a + (b - a) * fx
        let bottom = c + (d - c) * fx
        return top + (bottom - top) * fy
    }

    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0 ..< height {
        let v = min(max(-overscan + (Double(y) + 0.5) / Double(height) * span, 0.0), 1.0)
        let gy = v * Double(gridY - 1)
        let j0 = min(Int(gy), gridY - 2)
        let fy = gy - Double(j0)
        for x in 0 ..< width {
            let u = min(max(-overscan + (Double(x) + 0.5) / Double(width) * span, 0.0), 1.0)
            let gx = u * Double(gridX - 1)
            let i0 = min(Int(gx), gridX - 2)
            let fx = gx - Double(i0)
            let ws = qrStudioMeshWeights(sample(gridS, i0, j0, fx, fy))
            let wt = qrStudioMeshWeights(sample(gridT, i0, j0, fx, fy))
            let color = QrStudioColor(oklab: CGFloat(qrStudioMeshSurface(lab, stride: 3, component: 0, ws, wt)), CGFloat(qrStudioMeshSurface(lab, stride: 3, component: 1, ws, wt)), CGFloat(qrStudioMeshSurface(lab, stride: 3, component: 2, ws, wt)))
            let index = (y * width + x) * 4
            pixels[index] = UInt8(min(max(color.r * 255.0, 0.0), 255.0))
            pixels[index + 1] = UInt8(min(max(color.g * 255.0, 0.0), 255.0))
            pixels[index + 2] = UInt8(min(max(color.b * 255.0, 0.0), 255.0))
        }
    }
    return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        return context?.makeImage()
    }
}

final class QrStudioMeshBackgroundView: View, QrStudioBackgroundContent {
    private static let overscan: Double = 0.12
    private static let pixelWidth: Int = 64
    private static let morphTime: Double = 9.0
    private static let morphPeriod: Double = 18.0

    private let palette: QrStudioPalette
    private let meshContainer = SimpleLayer()
    private let meshLayer = SimpleLayer()
    private let morphLayer = SimpleLayer()
    private var size = CGSize()
    private var renderedSize = CGSize()
    private var isVisible = true

    let wantsFullFrameRate: Bool = false

    init(palette: QrStudioPalette) {
        self.palette = palette

        super.init(frame: CGRect())

        let base = palette.colors.count > 4 ? palette.colors[4] : (palette.colors.first ?? QrStudioColor(1.0, 1.0, 1.0))
        self.backgroundColor = base.nsColor
        for layer in [self.meshLayer, self.morphLayer] {
            layer.contentsGravity = .resize
            layer.magnificationFilter = .linear
            layer.minificationFilter = .linear
            self.meshContainer.addSublayer(layer)
        }
        self.morphLayer.opacity = 0.0
        self.layer?.addSublayer(self.meshContainer)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(size: CGSize, revealCenter: CGPoint) {
        guard self.size != size else {
            return
        }
        self.size = size
        guard size.width > 0.0, size.height > 0.0 else {
            return
        }
        let overscan = CGFloat(QrStudioMeshBackgroundView.overscan)
        let frame = CGRect(origin: CGPoint(), size: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.meshContainer.frame = frame
        let meshFrame = frame.insetBy(dx: -size.width * overscan, dy: -size.height * overscan)
        self.meshLayer.frame = meshFrame
        self.morphLayer.frame = meshFrame
        CATransaction.commit()

        let aspect = size.height / size.width
        if abs(aspect - self.renderedSize.height / max(self.renderedSize.width, 1.0)) > 0.02 || self.renderedSize == .zero {
            self.renderedSize = size
            self.render()
        }
    }

    private func render() {
        guard self.palette.colors.count == 9, self.size.width > 0.0, self.size.height > 0.0 else {
            return
        }
        let overscan = QrStudioMeshBackgroundView.overscan
        let span = 1.0 + overscan * 2.0
        let width = max(2, Int(Double(QrStudioMeshBackgroundView.pixelWidth) * span))
        let height = max(2, min(320, Int(Double(QrStudioMeshBackgroundView.pixelWidth) * Double(self.size.height / self.size.width) * span)))
        let zero = SIMD2<Double>(0.0, 0.0)
        let base = qrStudioMeshBackdropImage(colors: self.palette.colors, points: QrStudioMesh.points(at: 0.0, pull: zero), width: width, height: height, overscan: overscan)
        let morph = qrStudioMeshBackdropImage(colors: self.palette.colors, points: QrStudioMesh.points(at: QrStudioMeshBackgroundView.morphTime, pull: zero), width: width, height: height, overscan: overscan)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.meshLayer.contents = base
        self.morphLayer.contents = morph
        CATransaction.commit()
    }

    func tick(time: Double, pan: QrStudioPan, drift: QrStudioDrift, tilt: SIMD2<Double>) {
        guard self.isVisible, self.size.width > 0.0, self.size.height > 0.0 else {
            return
        }
        let size = self.size
        let overscan = CGFloat(QrStudioMeshBackgroundView.overscan)
        let limitX = size.width * overscan * 0.9
        let limitY = size.height * overscan * 0.9
        let stretch = pan.stretch(at: time)
        let heading = QrStudioDrift.heading(time * 4.0)
        var dx = size.width * 0.03 * CGFloat(sin(time * 0.19 + heading))
        var dy = size.height * 0.02 * CGFloat(cos(time * 0.15 + heading * 0.5))
        dx += CGFloat(tilt.x) * size.width * 0.03
        dy -= CGFloat(tilt.y) * size.height * 0.03
        dx += stretch.width * 0.3
        dy += stretch.height * 0.3
        dx = min(max(dx, -limitX), limitX)
        dy = min(max(dy, -limitY), limitY)
        let morph = 0.5 - 0.5 * cos(2.0 * Double.pi * time / QrStudioMeshBackgroundView.morphPeriod)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.meshContainer.transform = CATransform3DMakeTranslation(dx, dy, 0.0)
        self.morphLayer.opacity = Float(morph)
        CATransaction.commit()
    }

    func beginReveal(at time: Double) {
    }

    func setVisible(_ isVisible: Bool) {
        self.isVisible = isVisible
    }
}
