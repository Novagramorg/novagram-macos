import Foundation
import Cocoa
import SwiftSignalKit

public protocol PinchableView : NSView {
    func update(size: NSSize)
        
}
