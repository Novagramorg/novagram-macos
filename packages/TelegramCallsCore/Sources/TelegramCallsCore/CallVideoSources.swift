import Foundation
import AVFoundation
import TgVoipWebrtc
import Localization
import ColorPalette
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import SystemPermissions
import ProxyUtils

public struct DesktopCapturerObjectWrapper : Equatable {
    public static func == (lhs: DesktopCapturerObjectWrapper, rhs: DesktopCapturerObjectWrapper) -> Bool {
        if !lhs.source.isEqual(rhs.source) {
            return false
        }
        if lhs.isAvailableToStream != rhs.isAvailableToStream {
            return false
        }
        return true
    }

    public let source: VideoSourceMac
    public let isAvailableToStream: Bool
    public init(source: VideoSourceMac, isAvailableToStream: Bool) {
        self.source = source
        self.isAvailableToStream = isAvailableToStream
    }
}

public final class CameraCaptureDevice : VideoSourceMac, Equatable {
    public func isEqual(_ another: Any) -> Bool {
        if let another = another as? VideoSourceMac {
            return another.uniqueKey() == self.uniqueKey()
        } else {
            return false
        }
    }
    
    public let device: AVCaptureDevice
    public init(_ device: AVCaptureDevice) {
        self.device = device
    }
    public func deviceIdKey() -> String {
        return self.device.uniqueID
    }
    public func title() -> String {
        return device.localizedName
    }
    public func uniqueKey() -> String {
        return self.device.uniqueID
    }
    public static func ==(lhs: CameraCaptureDevice, rhs: CameraCaptureDevice) -> Bool {
        return lhs.device == rhs.device
    }
}
