import Cocoa

public enum TranscribeAudioState : Equatable {
    case loading
    case revealed(Bool)
    case collapsed(Bool)
}
