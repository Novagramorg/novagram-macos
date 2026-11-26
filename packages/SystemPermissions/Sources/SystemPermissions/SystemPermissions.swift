import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import SwiftSignalKit

public func requestMicrophonePermission() -> Signal<Bool, NoError> {
    return requestMediaPermission(.audio)
}
public func requestCameraPermission() -> Signal<Bool, NoError> {
    return requestMediaPermission(.video)
}
public func screenCaptureAvailable() -> Bool {
    if #available(macOS 13.0, *) {
        let stream = CGDisplayStream(dispatchQueueDisplay: CGMainDisplayID(), outputWidth: 1, outputHeight: 1, pixelFormat: Int32(kCVPixelFormatType_32BGRA), properties: nil, queue: DispatchQueue.main, handler: { _, _, _, _ in
        })
        _ = stream != nil
        return true
    } else {
        return false
    }
}

public func requestScreenCaptureAccess() -> Bool {
    if #available(OSX 11.0, *) {
        if !CGPreflightScreenCaptureAccess() {
            return CGRequestScreenCaptureAccess()
        } else {
            return true
        }
    } else {
        return screenCaptureAvailable()
    }
}


public func requestMediaPermission(_ type: AVFoundation.AVMediaType) -> Signal<Bool, NoError> {
    if #available(OSX 10.14, *) {
        return Signal { subscriber in
            let status = AVCaptureDevice.authorizationStatus(for: type)
            var cancelled: Bool = false
            switch status {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: type, completionHandler: { completed in
                    if !cancelled {
                        subscriber.putNext(completed)
                        subscriber.putCompletion()
                    }
                })
            case .authorized:
                subscriber.putNext(true)
                subscriber.putCompletion()
            case .denied:
                subscriber.putNext(false)
                subscriber.putCompletion()
            case .restricted:
                subscriber.putNext(false)
                subscriber.putCompletion()
            @unknown default:
                subscriber.putNext(false)
                subscriber.putCompletion()
            }
            return ActionDisposable {
                cancelled = true
            }
        } |> runOn(.concurrentDefaultQueue()) |> deliverOnMainQueue
    } else {
        return .single(true)
    }
}

public enum SystemSettingsCategory : String {
    case microphone = "Privacy_Microphone"
    case camera = "Privacy_Camera"
    case speechRecognition = "Privacy_SpeechRecognition"
    case storage = "Storage"
    case sharing = "Privacy_ScreenCapture"
    case accessibility = "Privacy_Accessibility"
    case notifications = "Notifications"
    case none = ""
}

public func openSystemSettings(_ category: SystemSettingsCategory) {
    switch category {
    case .storage:
        //if let url = URL(string: "/System/Applications/Utilities/System%20Information.app") {
            NSWorkspace.shared.launchApplication("/System/Applications/Utilities/System Information.app")
           // [[NSWorkspace sharedWorkspace] launchApplication:@"/Applications/Safari.app"];
       // }
    case .microphone, .camera, .sharing, .speechRecognition:
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(category.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    case .notifications:
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    default:
        break
    }
}
