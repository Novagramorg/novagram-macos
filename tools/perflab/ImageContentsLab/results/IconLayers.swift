import Cocoa
import TGUIKit
final class ReferenceChatRightIconLayer: SimpleLayer {
    var image: CGImage? {
        didSet {
            contents = image
        }
    }

    func sizeToFit() {
        if let image = image {
            bounds = CGRect(origin: .zero, size: image.backingSize)
        }
    }
}

final class CandidateChatRightIconLayer: SimpleLayer {
    var image: CGImage? {
        didSet {
            contents = image
        }
    }

    func sizeToFit() {
        if let image = image {
            bounds = CGRect(origin: .zero, size: image.backingSize)
        }
    }
}

