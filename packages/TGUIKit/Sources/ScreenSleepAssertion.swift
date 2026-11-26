import Foundation
import IOKit.pwr_mgt

public final class ScreenSleepAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var success: IOReturn?
    private let reason: String
    
    public init(reason: String) {
        self.reason = reason
    }
    
    @discardableResult
    public func disableScreenSleep() -> Bool? {
        guard success == nil else { return nil }
        success = IOPMAssertionCreateWithName( kIOPMAssertionTypeNoDisplaySleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               reason as CFString,
                                               &assertionID )
        return success == kIOReturnSuccess
    }
    
    @discardableResult
    public func enableScreenSleep() -> Bool {
        if success != nil {
            success = IOPMAssertionRelease(assertionID)
            success = nil
            return true
        }
        return false
    }
}
