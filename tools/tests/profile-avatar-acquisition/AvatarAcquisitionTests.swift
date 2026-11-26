import Foundation
import SwiftSignalKit
import XCTest

final class Window {}
final class Context {var window=Window()}
final class View {var window:AnyObject?;init(_ window:Window) {self.window=window}}
final class Controller {let view:View;var loaded=true;var willAppear:((Controller)->Void)?;var willDisappear:((Controller)->Void)?;var onDeinit:(()->Void)?;init(_ window:Window) {view=View(window)};func isLoaded()->Bool {loaded};deinit {onDeinit?()}}
final class ActiveAction {func setActive(_ active:Bool) {}}
final class Control {}
final class Application {var currentEvent:Int?=1}
let NSApp=Application()
final class ContextMenuItem {let handler:()->Void;init(_ title:String,handler:@escaping()->Void,itemImage:Int) {self.handler=handler}}
final class ContextMenu {var items:[ContextMenuItem]=[];func addItem(_ item:ContextMenuItem) {items.append(item)}}
final class AppMenu {let menu:ContextMenu;init(menu:ContextMenu) {self.menu=menu};func show(event:Int,view:Control) {UI.items=menu.items}}
enum MenuAnimation {case menu_shared_media,menu_view_sticker_set;var value:Int {1}}
struct Strings {let editAvatarPhotoOrVideo="file",editAvatarCustomize="custom",videoAvatarChooseDescProfile="video"}
func strings()->Strings {Strings()}
let photoExts=["png"],videoExts=["mp4"]
final class NSImage {let path:String;init?(contentsOfFile path:String) {guard path.hasSuffix(".png") else {return nil};self.path=path}}
struct MediaObjectToAvatar {let id:Int}
final class Log {var photos:[String]=[];var videos=0;var customized:[Int]=[]}
final class UI {static var items:[ContextMenuItem]=[];static var panels:[([String]?)->Void]=[];static var panelWindows:[Window]=[];static var videoPaths:[String]=[];static var constructors:[(MediaObjectToAvatar)->Void]=[];static func select(_ index:Int) {let handler=items[index].handler;items=[];handler()};static func reset() {items=[];panels=[];panelWindows=[];videoPaths=[];constructors=[];NSApp.currentEvent=1}}
func filePanel(with:[String],allowMultiple:Bool,canChooseDirectories:Bool,for window:Window,completion:@escaping([String]?)->Void) {UI.panels.append(completion);UI.panelWindows.append(window)}
func selectVideoAvatar(context:Context,path:String,localize:String,signal:@escaping(Signal<Int,NoError>)->Void) {UI.videoPaths.append(path);signal(.single(1))}
enum Target {case avatar}
struct Constructor {let callback:(MediaObjectToAvatar)->Void}
func AvatarConstructorController(_ context:Context,target:Target,videoSignal:@escaping(MediaObjectToAvatar)->Void)->Constructor {Constructor(callback:videoSignal)}
func showModal(with controller:Constructor,for window:Window) {UI.constructors.append(controller.callback)}
__HELPER__
final class Screen {
 let context=Context();var controller:Controller?;let avatarAcquisition=EditAccountAvatarAcquisition();let actionsDisposable=DisposableSet();let log=Log();var picker:((Control)->Void)!
 init() {
  let context=self.context;let controller=Controller(context.window);self.controller=controller;let avatarAcquisition=self.avatarAcquisition;let actionsDisposable=self.actionsDisposable;let log=self.log
  actionsDisposable.add(avatarAcquisition)
  let profileSaveAction=ActiveAction(),birthdaySaveAction=ActiveAction()
  let getController:(()->Controller?)? = { [weak controller] in controller }
  let updatePhoto:(Signal<NSImage,NoError>)->Void = {signal in _=signal.start(next:{log.photos.append($0.path)})}
  let updateVideo:(Signal<Int,NoError>)->Void = {_ in log.videos+=1}
  let makeVideo:(MediaObjectToAvatar)->Void = {log.customized.append($0.id)}
  let picker:(Control)->Void = __PICKER__
  self.picker=picker
  __HOOKS__
 }
 func menu() {picker(Control())}
 func file() {menu();UI.select(0)}
 func customize() {menu();UI.select(1)}
 func disappear() {if let controller {controller.willDisappear?(controller);controller.view.window=nil}}
 func appear() {if let controller {controller.view.window=context.window;controller.willAppear?(controller)}}
 func remove() {let profileSaveAction=ActiveAction(),birthdaySaveAction=ActiveAction();let actionsDisposable=self.actionsDisposable;let action:()->Void=__REMOVAL__;action()}
}
final class AvatarAcquisitionTests:XCTestCase {
 override func setUp() {UI.reset()}
 func testPhotoSelectionStartsOneUpdate() {let s=Screen();s.file();UI.panels[0](["a.png"]);XCTAssertEqual(s.log.photos,["a.png"]);XCTAssertTrue(UI.videoPaths.isEmpty)}
 func testVideoSelectionPresentsAndStartsGenerator() {let s=Screen();s.file();UI.panels[0](["a.mp4"]);XCTAssertEqual(UI.videoPaths,["a.mp4"]);XCTAssertEqual(s.log.videos,1)}
 func testCancelledPanelDoesNothing() {let s=Screen();s.file();UI.panels[0](nil);XCTAssertTrue(s.log.photos.isEmpty);XCTAssertTrue(UI.videoPaths.isEmpty)}
 func testEmptySelectionDoesNothing() {let s=Screen();s.file();UI.panels[0]([]);XCTAssertTrue(s.log.photos.isEmpty);XCTAssertTrue(UI.videoPaths.isEmpty)}
 func testDuplicatePanelCallbacksCannotRepeatUpdate() {let s=Screen();s.file();UI.panels[0](["a.png"]);UI.panels[0](["b.mp4"]);XCTAssertEqual(s.log.photos,["a.png"]);XCTAssertTrue(UI.videoPaths.isEmpty)}
 func testCancelledPanelCannotLaterAcceptResult() {let s=Screen();s.file();UI.panels[0](nil);UI.panels[0](["a.png"]);XCTAssertTrue(s.log.photos.isEmpty)}
 func testNewFileSelectionSupersedesOldPanel() {let s=Screen();s.file();s.file();UI.panels[1](["new.png"]);UI.panels[0](["old.png"]);XCTAssertEqual(s.log.photos,["new.png"])}
 func testConstructorSupersedesOldPanel() {let s=Screen();s.file();s.customize();UI.panels[0](["old.mp4"]);UI.constructors[0](.init(id:1));XCTAssertTrue(UI.videoPaths.isEmpty);XCTAssertEqual(s.log.customized,[1])}
 func testFileSelectionSupersedesConstructor() {let s=Screen();s.customize();s.file();UI.constructors[0](.init(id:1));UI.panels[0](["new.png"]);XCTAssertTrue(s.log.customized.isEmpty);XCTAssertEqual(s.log.photos,["new.png"])}
 func testConstructorResultIsSingleUse() {let s=Screen();s.customize();UI.constructors[0](.init(id:1));UI.constructors[0](.init(id:2));XCTAssertEqual(s.log.customized,[1])}
 func testRemovedProfileDoesNotPresentVideo() {let s=Screen();s.file();s.remove();UI.panels[0](["a.mp4"]);XCTAssertTrue(UI.videoPaths.isEmpty);XCTAssertEqual(s.log.videos,0)}
 func testHiddenProfileDoesNotPresentVideo() {let s=Screen();s.file();s.disappear();UI.panels[0](["a.mp4"]);XCTAssertTrue(UI.videoPaths.isEmpty)}
 func testHiddenProfileDoesNotAcceptConstructorResult() {let s=Screen();s.customize();s.disappear();UI.constructors[0](.init(id:1));XCTAssertTrue(s.log.customized.isEmpty)}
 func testReappearanceDoesNotReviveOldCallback() {let s=Screen();s.file();s.disappear();s.appear();UI.panels[0](["a.png"]);XCTAssertTrue(s.log.photos.isEmpty);s.file();UI.panels[1](["b.png"]);XCTAssertEqual(s.log.photos,["b.png"])}
 func testViewWindowReplacementRejectsCallback() {let s=Screen();s.file();s.controller?.view.window=Window();UI.panels[0](["a.mp4"]);XCTAssertTrue(UI.videoPaths.isEmpty)}
 func testContextWindowReplacementRejectsCallback() {let s=Screen();s.file();s.context.window=Window();UI.panels[0](["a.mp4"]);XCTAssertTrue(UI.videoPaths.isEmpty)}
 func testDetachedViewRejectsCallbackWithoutLifecycleNotification() {let s=Screen();s.file();s.controller?.view.window=nil;UI.panels[0](["a.png"]);XCTAssertTrue(s.log.photos.isEmpty)}
 func testUnloadedControllerRejectsCallback() {let s=Screen();s.file();s.controller?.loaded=false;UI.panels[0](["a.mp4"]);XCTAssertTrue(UI.videoPaths.isEmpty)}
 func testMenuActionAfterRemovalCannotOpenPanel() {let s=Screen();s.menu();s.remove();UI.select(0);XCTAssertTrue(UI.panels.isEmpty)}
 func testMenuActionAfterDisappearanceCannotOpenConstructor() {let s=Screen();s.menu();s.disappear();UI.select(1);XCTAssertTrue(UI.constructors.isEmpty)}
 func testPanelCallbackDoesNotRetainProfileContextAfterDeinit() {var s:Screen?=Screen();weak var context=s!.context;let log=s!.log;s!.file();s=nil;XCTAssertNil(context);UI.panels[0](["a.mp4"]);XCTAssertTrue(UI.videoPaths.isEmpty);XCTAssertEqual(log.videos,0)}
 func testConstructorCallbackDoesNotRetainProfileContextAfterDeinit() {var s:Screen?=Screen();weak var context=s!.context;let log=s!.log;s!.customize();s=nil;XCTAssertNil(context);UI.constructors[0](.init(id:1));XCTAssertTrue(log.customized.isEmpty)}
 func testOldMenuCannotStartAfterProfileReappears() {let s=Screen();s.menu();s.disappear();s.appear();UI.select(0);XCTAssertTrue(UI.panels.isEmpty)}
 func testOldMenuCannotCustomizeAfterProfileReappears() {let s=Screen();s.menu();s.disappear();s.appear();UI.select(1);XCTAssertTrue(UI.constructors.isEmpty)}

 func testRejectedCallbackCannotReviveWhenWindowReturns() {let s=Screen();s.file();let window=s.context.window;s.context.window=Window();UI.panels[0](["old.png"]);s.context.window=window;UI.panels[0](["old.png"]);XCTAssertTrue(s.log.photos.isEmpty)}

}
final class AcquisitionOwnerTests:XCTestCase {
 func testInactiveOwnerRejectsStart() {let owner=EditAccountAvatarAcquisition();owner.setActive(false);let result:((Int)->Void)?=owner.start(canPresent:{true},selected:{_ in XCTFail()});XCTAssertNil(result)}
 func testDisposedOwnerCannotBeReactivated() {let owner=EditAccountAvatarAcquisition();owner.dispose();owner.setActive(true);let result:((Int)->Void)?=owner.start(canPresent:{true},selected:{_ in XCTFail()});XCTAssertNil(result)}
 func testFalsePresentationPredicateRejectsStart() {let owner=EditAccountAvatarAcquisition();let result:((Int)->Void)?=owner.start(canPresent:{false},selected:{_ in XCTFail()});XCTAssertNil(result)}
 func testCallbackDoesNotRetainOwner() {var owner:EditAccountAvatarAcquisition?=EditAccountAvatarAcquisition();weak var weakOwner=owner;let callback:((Int)->Void)?=owner!.start(canPresent:{true},selected:{_ in XCTFail()});owner=nil;XCTAssertNil(weakOwner);callback?(1)}
 func testDisappearanceReleasesPendingSelectionCaptures() {let owner=EditAccountAvatarAcquisition();var object:Log?=Log();weak var weakObject=object;let callback:((Int)->Void)?=owner.start(canPresent:{true},selected:{[object] _ in _=object});object=nil;XCTAssertNotNil(weakObject);owner.setActive(false);XCTAssertNil(weakObject);callback?(1)}
 func testPredicateReentrantDisposalCannotDeliverSelection() {let owner=EditAccountAvatarAcquisition();var checkCount=0;let callback:((Int)->Void)?=owner.start(canPresent:{checkCount+=1;if checkCount==2 {owner.dispose()};return true},selected:{_ in XCTFail()});callback?(1)}
 func testPredicateReplacementPreservesNewSelection() {let owner=EditAccountAvatarAcquisition();var checkCount=0;var next:((Int)->Void)?;var results:[Int]=[];let callback:((Int)->Void)?=owner.start(canPresent:{checkCount+=1;if checkCount==2 {next=owner.start(canPresent:{true},selected:{results.append($0)})};return true},selected:{_ in XCTFail()});callback?(1);next?(2);XCTAssertEqual(results,[2])}
 func testCallbackCanStartNewSelectionWithoutOldCleanupErasingIt() {let owner=EditAccountAvatarAcquisition();var next:((Int)->Void)?;var results:[Int]=[];let callback:((Int)->Void)?=owner.start(canPresent:{true},selected:{value in results.append(value);next=owner.start(canPresent:{true},selected:{results.append($0)})});callback?(1);next?(2);XCTAssertEqual(results,[1,2])}
 func testRejectedPresentationReleasesSelectedClosure() {let owner=EditAccountAvatarAcquisition();var valid=true;var object:Log?=Log();weak var weakObject=object;let callback:((Int)->Void)?=owner.start(canPresent:{valid},selected:{[object] _ in _=object;XCTFail()});object=nil;XCTAssertNotNil(weakObject);valid=false;callback?(1);XCTAssertNil(weakObject);valid=true;callback?(2)}
 func testStartingPredicateCannotOverwriteReentrantSelection() {let owner=EditAccountAvatarAcquisition();var next:((Int)->Void)?;var values:[Int]=[];let callback:((Int)->Void)?=owner.start(canPresent:{next=owner.start(canPresent:{true},selected:{values.append($0)});return true},selected:{_ in XCTFail()});XCTAssertNil(callback);next?(2);XCTAssertEqual(values,[2])}

}
