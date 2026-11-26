import Cocoa
import SwiftSignalKit
public enum LoginAuthErrorState : Equatable {
    case normal
    case error(String)
}
public func ==(lhs:LoginAuthErrorState, rhs:LoginAuthErrorState) -> Bool {
    switch lhs {
    case .normal:
        if case .normal = rhs {
            return true
        } else {
            return false
        }
    case let .error(lhsError):
        if case let .error(rhsError) = rhs {
            return lhsError == rhsError
        } else {
            return false
        }
    }
}

public class LoginErrorStateView : TextViewLabel {
    public let state:ValuePromise<LoginAuthErrorState> = ValuePromise(ignoreRepeated: true)
    private let errorDisposable:MetaDisposable = MetaDisposable()
    
    deinit {
        errorDisposable.dispose()
    }
    
    public override init() {
        super.init()
        errorDisposable.set((state.get() |> deliverOnMainQueue |> distinctUntilChanged).start(next: {[weak self] (state) in
            switch state {
            case .normal:
                self?.layer?.opacity = 0
                self?.layer?.animateAlpha(from: 1, to: 0, duration: 0.2)
                
            case let .error(errorCode):
                self?.attributedString = NSAttributedString.initialize(string: errorCode, color: .redUI, font: NSFont.normal(FontSize.text))
                self?.sizeToFit()
                self?.layer?.opacity = 1
                self?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                
            }
            self?.superview?.needsLayout = true
            
        }))
        layer?.opacity = 0

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
}
