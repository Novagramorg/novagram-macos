#if DEBUG
import Foundation
import TGUIKit

public enum PeerMediaGridDebug {
    public static var rowViewsCreated = 0
    public static var cellsCreated = 0
    public static var rowsSet = 0
    public static var merges = 0
    public static var mergeSeconds: Double = 0
    public static var worstMergeSeconds: Double = 0
    public static var locationChanges = 0
    public static var lastMerge = ""
    public static var willMerge: ((TableView) -> Void)?
    public static var didMerge: ((TableView) -> Void)?
    public static let tables = NSHashTable<TableView>.weakObjects()

    public static func reset() {
        self.rowViewsCreated = 0
        self.cellsCreated = 0
        self.rowsSet = 0
        self.merges = 0
        self.mergeSeconds = 0
        self.worstMergeSeconds = 0
        self.locationChanges = 0
    }
}
#endif
