import Foundation
import TelegramUtils
import TelegramCore
import SwiftSignalKit
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

public enum CallListViewScrollPosition {
    case index(index: EngineMessage.Index, position: ListViewScrollPosition, directionHint: ListViewScrollToItemDirectionHint, animated: Bool)
}

public enum CallListLocation: Equatable {
    case initial(count: Int)
    case changeType(index: EngineMessage.Index)
    case navigation(index: EngineMessage.Index)
    case scroll(index: EngineMessage.Index, sourceIndex: EngineMessage.Index, scrollPosition: ListViewScrollPosition, animated: Bool)
    
    public static func ==(lhs: CallListLocation, rhs: CallListLocation) -> Bool {
        switch lhs {
            case let .navigation(index):
                switch rhs {
                    case .navigation(index):
                        return true
                    default:
                        return false
                }
            default:
                return false
        }
    }
}

public struct CallListLocationAndType: Equatable {
    public let location: CallListLocation
    public let scope: EngineCallList.Scope
    public init(location: CallListLocation, scope: EngineCallList.Scope) {
        self.location = location
        self.scope = scope
    }
}

public enum CallListViewUpdateType {
    case Initial
    case Generic
    case Reload
    case ReloadAnimated
    case UpdateVisible
}

public struct CallListViewUpdate {
    public let view: EngineCallList
    public let type: CallListViewUpdateType
    public let scrollPosition: CallListViewScrollPosition?
    public init(view: EngineCallList, type: CallListViewUpdateType, scrollPosition: CallListViewScrollPosition?) {
        self.view = view
        self.type = type
        self.scrollPosition = scrollPosition
    }
}

public func callListViewForLocationAndType(locationAndType: CallListLocationAndType, engine: TelegramEngine) -> Signal<(CallListViewUpdate, EngineCallList.Scope), NoError> {
    switch locationAndType.location {
    case let .initial(count):
        return engine.messages.callList(
            scope: locationAndType.scope,
            index: EngineMessage.Index.absoluteUpperBound(),
            itemCount: count
        )
        |> map { view -> (CallListViewUpdate, EngineCallList.Scope) in
            return (CallListViewUpdate(view: view, type: .Generic, scrollPosition: nil), locationAndType.scope)
        }
    case let .changeType(index):
        return engine.messages.callList(
            scope: locationAndType.scope,
            index: index,
            itemCount: 120
        )
        |> map { view -> (CallListViewUpdate, EngineCallList.Scope) in
            return (CallListViewUpdate(view: view, type: .ReloadAnimated, scrollPosition: nil), locationAndType.scope)
        }
    case let .navigation(index):
        var first = true
        return engine.messages.callList(
            scope: locationAndType.scope,
            index: index,
            itemCount: 120
        )
        |> map { view -> (CallListViewUpdate, EngineCallList.Scope) in
            let genericType: CallListViewUpdateType
            if first {
                first = false
                genericType = .UpdateVisible
            } else {
                genericType = .Generic
            }
            return (CallListViewUpdate(view: view, type: genericType, scrollPosition: nil), locationAndType.scope)
        }
    case let .scroll(index, sourceIndex, scrollPosition, animated):
        let directionHint: ListViewScrollToItemDirectionHint = sourceIndex > index ? .Down : .Up
        let callScrollPosition: CallListViewScrollPosition = .index(index: index, position: scrollPosition, directionHint: directionHint, animated: animated)
        var first = true
        return engine.messages.callList(
            scope: locationAndType.scope,
            index: index,
            itemCount: 120
        )
        |> map { view -> (CallListViewUpdate, EngineCallList.Scope) in
            let genericType: CallListViewUpdateType
            let scrollPosition: CallListViewScrollPosition? = first ? callScrollPosition : nil
            if first {
                first = false
                genericType = .UpdateVisible
            } else {
                genericType = .Generic
            }
            return (CallListViewUpdate(view: view, type: genericType, scrollPosition: scrollPosition), locationAndType.scope)
        }
    }
}
