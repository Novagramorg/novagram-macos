import Cocoa
import PhoneNumberUtils

func installPhoneNumberUtilsHooks() {
    PhoneNumberUtilsHooks.install(PhoneNumberUtilsHooks(currentCountriesConfiguration: { context in
        return (context as! AccountContext).currentCountriesConfiguration
    }))
}
