import Cocoa

import SwiftSignalKit
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

public enum ListViewCenterScrollPositionOverflow {
    case Top
    case Bottom
}

public enum ListViewScrollPosition: Equatable {
    case Top
    case Bottom
    case Center(ListViewCenterScrollPositionOverflow)
}

public func ==(lhs: ListViewScrollPosition, rhs: ListViewScrollPosition) -> Bool {
    switch lhs {
    case .Top:
        switch rhs {
        case .Top:
            return true
        default:
            return false
        }
    case .Bottom:
        switch rhs {
        case .Bottom:
            return true
        default:
            return false
        }
    case let .Center(lhsOverflow):
        switch rhs {
        case let .Center(rhsOverflow) where lhsOverflow == rhsOverflow:
            return true
        default:
            return false
        }
    }
}

public enum ListViewScrollToItemDirectionHint {
    case Up
    case Down
}

public enum ListViewAnimationCurve {
    case Spring(duration: Double)
    case Default
}

public struct ListViewScrollToItem {
    public let index: Int
    public let position: ListViewScrollPosition
    public let animated: Bool
    public let curve: ListViewAnimationCurve
    public let directionHint: ListViewScrollToItemDirectionHint
    
    public init(index: Int, position: ListViewScrollPosition, animated: Bool, curve: ListViewAnimationCurve, directionHint: ListViewScrollToItemDirectionHint) {
        self.index = index
        self.position = position
        self.animated = animated
        self.curve = curve
        self.directionHint = directionHint
    }
}

public enum ListViewItemOperationDirectionHint {
    case Up
    case Down
}

public struct ListViewDeleteItem {
    public let index: Int
    public let directionHint: ListViewItemOperationDirectionHint?
    
    public init(index: Int, directionHint: ListViewItemOperationDirectionHint?) {
        self.index = index
        self.directionHint = directionHint
    }
}

public struct ListViewInsertItem {
    public let index: Int
    public let previousIndex: Int?
    public let item: ListViewItem
    public let directionHint: ListViewItemOperationDirectionHint?
    public let forceAnimateInsertion: Bool
    
    public init(index: Int, previousIndex: Int?, item: ListViewItem, directionHint: ListViewItemOperationDirectionHint?, forceAnimateInsertion: Bool = false) {
        self.index = index
        self.previousIndex = previousIndex
        self.item = item
        self.directionHint = directionHint
        self.forceAnimateInsertion = forceAnimateInsertion
    }
}

public struct ListViewUpdateItem {
    public let index: Int
    public let previousIndex: Int
    public let item: ListViewItem
    public let directionHint: ListViewItemOperationDirectionHint?
    
    public init(index: Int, previousIndex: Int, item: ListViewItem, directionHint: ListViewItemOperationDirectionHint?) {
        self.index = index
        self.previousIndex = previousIndex
        self.item = item
        self.directionHint = directionHint
    }
}

public struct ListViewDeleteAndInsertOptions: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let AnimateInsertion = ListViewDeleteAndInsertOptions(rawValue: 1)
    public static let AnimateAlpha = ListViewDeleteAndInsertOptions(rawValue: 2)
    public static let LowLatency = ListViewDeleteAndInsertOptions(rawValue: 4)
    public static let Synchronous = ListViewDeleteAndInsertOptions(rawValue: 8)
    public static let RequestItemInsertionAnimations = ListViewDeleteAndInsertOptions(rawValue: 16)
    public static let AnimateTopItemPosition = ListViewDeleteAndInsertOptions(rawValue: 32)
    public static let PreferSynchronousDrawing = ListViewDeleteAndInsertOptions(rawValue: 64)
    public static let PreferSynchronousResourceLoading = ListViewDeleteAndInsertOptions(rawValue: 128)
}


public struct ListViewItemRange: Equatable {
    public let firstIndex: Int
    public let lastIndex: Int
    public init(firstIndex: Int, lastIndex: Int) {
        self.firstIndex = firstIndex
        self.lastIndex = lastIndex
    }
}

public func ==(lhs: ListViewItemRange, rhs: ListViewItemRange) -> Bool {
    return lhs.firstIndex == rhs.firstIndex && lhs.lastIndex == rhs.lastIndex
}

public struct ListViewDisplayedItemRange: Equatable {
    public let loadedRange: ListViewItemRange?
    public let visibleRange: ListViewItemRange?
    public init(loadedRange: ListViewItemRange?, visibleRange: ListViewItemRange?) {
        self.loadedRange = loadedRange
        self.visibleRange = visibleRange
    }
}

public func ==(lhs: ListViewDisplayedItemRange, rhs: ListViewDisplayedItemRange) -> Bool {
    return lhs.loadedRange == rhs.loadedRange && lhs.visibleRange == rhs.visibleRange
}

public struct IndexRange {
    public let first: Int
    public let last: Int
    
    public func contains(_ index: Int) -> Bool {
        return index >= first && index <= last
    }
    
    public var empty: Bool {
        return first > last
    }
    public init(first: Int, last: Int) {
        self.first = first
        self.last = last
    }
}

public struct OffsetRanges {
    public var offsets: [(IndexRange, CGFloat)] = []
    
    public mutating func append(_ other: OffsetRanges) {
        self.offsets.append(contentsOf: other.offsets)
    }
    
    public mutating func offset(_ indexRange: IndexRange, offset: CGFloat) {
        self.offsets.append((indexRange, offset))
    }
    
    public func offsetForIndex(_ index: Int) -> CGFloat {
        var result: CGFloat = 0.0
        for offset in self.offsets {
            if offset.0.contains(index) {
                result += offset.1
            }
        }
        return result
    }
    public init(offsets: [(IndexRange, CGFloat)] = []) {
        self.offsets = offsets
    }
}

public func binarySearch(_ inputArr: [Int], searchItem: Int) -> Int? {
    var lowerIndex = 0;
    var upperIndex = inputArr.count - 1
    
    if lowerIndex > upperIndex {
        return nil
    }
    
    while (true) {
        let currentIndex = (lowerIndex + upperIndex) / 2
        if (inputArr[currentIndex] == searchItem) {
            return currentIndex
        } else if (lowerIndex > upperIndex) {
            return nil
        } else {
            if (inputArr[currentIndex] > searchItem) {
                upperIndex = currentIndex - 1
            } else {
                lowerIndex = currentIndex + 1
            }
        }
    }
}

public struct TransactionState {
    public let visibleSize: CGSize
    public let items: [ListViewItem]
    public init(visibleSize: CGSize, items: [ListViewItem]) {
        self.visibleSize = visibleSize
        self.items = items
    }
}



public enum ListViewInsertionOffsetDirection {
    case Up
    case Down
    
    public init(_ hint: ListViewItemOperationDirectionHint) {
        switch hint {
        case .Up:
            self = .Up
        case .Down:
            self = .Down
        }
    }
    
    public func inverted() -> ListViewInsertionOffsetDirection {
        switch self {
        case .Up:
            return .Down
        case .Down:
            return .Up
        }
    }
}

public struct ListViewInsertionPoint {
    public let index: Int
    public let point: CGPoint
    public let direction: ListViewInsertionOffsetDirection
    public init(index: Int, point: CGPoint, direction: ListViewInsertionOffsetDirection) {
        self.index = index
        self.point = point
        self.direction = direction
    }
}

public protocol ListViewItem {
    
}

public struct ListViewUpdateSizeAndInsets {
    public let size: CGSize
    public let insets: NSEdgeInsets
    public let duration: Double
    public let curve: ListViewAnimationCurve
    
    public init(size: CGSize, insets: NSEdgeInsets, duration: Double, curve: ListViewAnimationCurve) {
        self.size = size
        self.insets = insets
        self.duration = duration
        self.curve = curve
    }
}
