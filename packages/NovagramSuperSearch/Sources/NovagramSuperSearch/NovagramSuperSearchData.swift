import Foundation
import NovagramSearchKit

public enum NovagramSuperSearchData {
    public static func clear(accountRecordId: Int64) {
        NovagramJobStore.clear(accountRecordId: accountRecordId)
    }
}
