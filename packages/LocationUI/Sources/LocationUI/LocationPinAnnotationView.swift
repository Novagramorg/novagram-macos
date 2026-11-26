import Cocoa
import TGUIKit
import MapKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import ObjcUtils

public final class LocationPinAnnotationView : MKAnnotationView {
    private let locationPin = ImageView()
    
    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        
        self.wantsLayer = true
        layer?.masksToBounds = false
        
        locationPin.image = TelegramThemeHooks.shared.darkAppearance().icons.locationMapPin
        locationPin.sizeToFit()
        locationPin.isAccessibilityDecorative = true
        
        frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        
        addSubview(locationPin)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        locationPin.center()
        locationPin.setFrameOrigin(NSMakePoint(locationPin.frame.minX, locationPin.frame.minY - locationPin.frame.height / 2))
    }
    
    public static var reuseIdentifier: String {
        return "peer"
    }
}

public extension MKMapView {
    func focusVenue(at userLocation: CLLocationCoordinate2D) {
        var region = MKCoordinateRegion()
        var span = MKCoordinateSpan()
        span.latitudeDelta = CLLocationDegrees(0.005)
        span.longitudeDelta = CLLocationDegrees(0.005)
        var location = CLLocationCoordinate2D()
        location.latitude = userLocation.latitude
        location.longitude = userLocation.longitude
        region.span = span
        region.center = location
        setRegion(region, animated: false)
    }
}
