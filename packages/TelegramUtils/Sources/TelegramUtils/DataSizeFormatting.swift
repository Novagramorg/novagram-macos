import Foundation
import FoundationUtils
import Localization

public extension DataSizeStringFormatting {
    
    static var current: DataSizeStringFormatting {
        return DataSizeStringFormatting.init(decimalSeparator: NumberFormatter().decimalSeparator, byte: { value in
            return (strings().fileSizeB(value), [])
        }, kilobyte: { value in
            return (strings().fileSizeKB(value), [])
        }, megabyte: { value in
            return (strings().fileSizeMB(value), [])
        }, gigabyte: { value in
            return (strings().fileSizeGB(value), [])
        })
    }
}
