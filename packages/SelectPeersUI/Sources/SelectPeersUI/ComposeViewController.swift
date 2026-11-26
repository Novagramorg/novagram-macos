import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramUtils

public struct ComposeTitles {
    public let center:String
    public let done:String
    public init(_ center:String, _ done:String) {
        self.center = center
        self.done = done
    }
}



open class ComposeViewController<T, I, V, Context>: EmptyComposeController<I, T, V, Context> where V: NSView, Context: AccountContextProtocol {
    
    public let titles:ComposeTitles
    fileprivate(set) var enableNext:Bool = true
    
    open override func getRightBarViewOnce() -> BarView {
        return TextButtonBarView(controller: self, text: titles.done, style: navigationButtonStyle)
    }
    
    open override func executeReturn() -> Void {
        onCancel.set(Signal<Void, NoError>.single(Void()))
        super.executeReturn()
    }
    
    open override func requestUpdateRightBar() {
        super.requestUpdateRightBar()
        rightBarView.style = navigationButtonStyle
    }

    open override func returnKeyAction() -> KeyHandlerResult {
         self.executeNext()
         return .invoked
    }

    open func nextEnabled(_ enable:Bool) {
        self.enableNext = enable
        rightBarView.isEnabled = enable
    }
    
    open func executeNext() -> Void {
        
    }
    
    open override var enableBack: Bool {
        return true
    }
    
    open override func loadView() {
        super.loadView()

        setCenterTitle(titles.center)
        self.rightBarView.set(handler:{ [weak self] _ in
            self?.executeNext()
        }, for: .Click)

        if let tableView = self.genericView as? TableView {
            tableView.contentInsets = NSEdgeInsets(top: bar.height, left: 0, bottom: 0, right: 0)
        }
    }
    
    
    
    public init(titles:ComposeTitles, context: Context) {
        self.titles = titles
        super.init(context)
    }
}
