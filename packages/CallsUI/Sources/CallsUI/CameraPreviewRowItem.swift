import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import SystemPermissions
import TelegramMediaUtils
import Postbox
import AVFoundation

public class CameraPreviewRowItem: GeneralRowItem {
    fileprivate let device: AVCaptureDevice
    fileprivate let session: AVCaptureSession
    public init(_ initialSize: NSSize, stableId: AnyHashable, device: AVCaptureDevice, viewType: GeneralViewType) {
        self.device = device
        self.session = AVCaptureSession()
        let input = try? AVCaptureDeviceInput(device: device)
        if let input = input {
            self.session.addInput(input)
        }
        super.init(initialSize, height: 220, stableId: stableId, viewType: viewType)
        
        self.session.startRunning()

    }
    deinit {
        self.session.stopRunning()
    }

    public override var accessibilityLabel: String? {
        return device.localizedName
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .image
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func viewClass() -> AnyClass {
        return CameraPreviewRowView.self
    }
}

private final class CameraPreviewRowView : GeneralContainableRowView {
    private let captureLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer()
    private let view = View()
    private let progressIndicator = ProgressIndicator(frame: NSMakeRect(0, 0, 40, 40))
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(progressIndicator)
        addSubview(view)
        view.layer?.addSublayer(self.captureLayer)
    }
    
    public override func updateColors() {
        super.updateColors()
        progressIndicator.progressColor = theme.colors.text
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? CameraPreviewRowItem else {
            return
        }
        
        captureLayer.session = item.session
        captureLayer.connection?.automaticallyAdjustsVideoMirroring = false
        captureLayer.connection?.isVideoMirrored = true
        captureLayer.videoGravity = .resizeAspectFill
        
    }
    
    public override func layout() {
        super.layout()
        view.frame = containerView.bounds
        captureLayer.frame = view.bounds
        progressIndicator.center()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

