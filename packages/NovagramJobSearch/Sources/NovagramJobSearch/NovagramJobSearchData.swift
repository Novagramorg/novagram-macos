import Foundation
import NovagramSearchKit

public enum NovagramJobSearchData {
    public static func clear(accountRecordId: Int64) {
        NovagramJobStore.clear(accountRecordId: accountRecordId)
    }
}
