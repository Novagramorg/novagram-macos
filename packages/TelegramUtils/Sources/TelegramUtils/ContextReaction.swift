import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext

public enum ContextReaction : Equatable {
    case stars(file: TelegramMediaFile, isSelected: Bool)
    case builtin(value: MessageReaction.Reaction, staticFile: TelegramMediaFile, selectFile: TelegramMediaFile, appearFile: TelegramMediaFile, isSelected: Bool)
    case custom(value: MessageReaction.Reaction, fileId: Int64, TelegramMediaFile?, isSelected: Bool)
    
    public var file: TelegramMediaFile? {
        switch self {
        case let .builtin(_, staticFile, _, _, _):
            return staticFile
        case let .custom(_, _, file, _ ):
            return file
        case let .stars(file, _):
            return file
        }
    }
    public var fileId: Int64 {
        switch self {
        case let .builtin(_, staticFile, _, _, _):
            return staticFile.fileId.id
        case let .custom(_, fileId, _, _):
            return fileId
        case let .stars(file, _):
            return file.fileId.id
        }
    }
    public var isSelected: Bool {
        switch self {
        case let .builtin(_, _, _, _, isSelected):
            return isSelected
        case let .custom(_, _, _, isSelected):
            return isSelected
        case let .stars(_, isSelected):
            return isSelected
        }
    }
    public func selectAnimation(_ context: any AccountContextProtocol) -> Signal<TelegramMediaFile, NoError> {
        switch self {
        case let .builtin(_, _, selectAnimation, _, _):
            return .single(selectAnimation)
        case .custom:
            return .complete()
        case let .stars(file, _):
            return .single(file)
        }
    }
    public var selectedAnimation: TelegramMediaFile? {
        switch self {
        case let .builtin(_, _, selectAnimation, _, _):
            return selectAnimation
        case let .custom(_, _, file, _ ):
            return file
        case let .stars(file, _):
            return file
        }
    }
    public var appearAnimation: TelegramMediaFile? {
        switch self {
        case let .builtin(_, _, _, appearAnimation, _):
            return appearAnimation
        case .custom:
            return nil
        case .stars:
            return nil
        }
    }
    public var value: MessageReaction.Reaction {
        switch self {
        case let .builtin(value, _, _, _, _):
            return value
        case let .custom(value, _, _, _):
            return value
        case .stars:
            return .stars
        }
    }
    
}
