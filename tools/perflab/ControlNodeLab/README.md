# ChatLayerControlNode equivalence lab

Proves that `ChatLayerControlNode` (packages/ChatUI/Sources/ChatUI/ChatLayerControlNode.swift) fires the same handler events and state transitions as TGUIKit's `Control` for the same pointer input.

```sh
python3 tools/perflab/ControlNodeLab/prepare.py
swift test --package-path tools/perflab/ControlNodeLab
LAB_EXPECT_MUTANT_EQUAL=1 swift test --package-path tools/perflab/ControlNodeLab --filter testMutantIsDetected
```

The last command is the oracle check and is expected to fail. The package builds the real TGUIKit by path (the SSignalKit path needs an initialized `submodules/telegram-ios`).

## Setup

- `prepare.py` copies `ChatLayerScene.swift` and `ChatLayerControlNode.swift` byte for byte into `Sources/SceneLab/Generated`. `Stubs.swift` stubs the three `ChatLayerTextNode` tooltip/hover calls and `clearBubbleSelection()` that the scene uses from other ChatUI files.
- `SceneLabMutant` is the same scene, with the node's long-press delay changed from 0.35 s to 0.2 s. `prepare.py` asserts that the edit applies exactly once.
- `ControlHarness` puts a real `Control` subclass (it only overrides `sendRightMouseAnyway`) at (50, 50, 100, 40) in a `RecordingView` content view. `NodeHarness` puts a `ChatLayerControlNode` at the same scene rect, nested as (30, 30) in a group node at (20, 20), inside a `ChatLayerSceneView` that fills a `RecordingView`. `RecordingView` logs any mouse event that reaches it as the next responder.
- Both harnesses get the same synthetic `NSEvent.mouseEvent(...)` sequence and record into one ordered log. The log holds every event handler, every state handler (`.Normal/.Hover/.Highlight/.Other`, with the state at that moment), each context-menu request and presentation, writes to `Control.lastHandledClickTimestamp`, next-responder hits, and press-scale animations (class, duration, removedOnCompletion, from/to transform). Each test asserts that the two logs are identical. It also checks key facts against the Control log, so an empty log can't pass.
- Deterministic input, with no hooks in production code:
  - `LabWindow` overrides `mouseLocationOutsideOfEventStream`. `Control.mouseInside()` / `invokeLongDown` and the node read the same injected pointer.
  - `+[NSEvent pressedMouseButtons]` is replaced with an injected value: 1 between left down and up, 2 for right.
  - A menu counts as presented when `AppMenu.show` registers its KVO observer on the `ContextMenu` (the menu is empty, so nothing is drawn). `System.legacyMenu = false`, so `NSMenu.popUpContextMenu` never blocks.
  - `addToolTipRect:owner:userData:` and `removeToolTip:` are swizzled to record the live tooltip rects per view.
- The lab simulates AppKit's routing. For `Control`, it calls `mouseEntered/Exited` when the pointer crosses the frame on a move with no button pressed: Control's tracking area has no `.enabledDuringMouseDrag`, so AppKit sends no enter/exit while a button is down. Drags and ups go to the view that received the down. For the scene, it calls the scene's own `mouseMoved/Down/Dragged/Up/rightMouse*/mouseExited`.

## Proven (23 tests pass)

- Click, double click (`SingleClick`/`DoubleClick`/`Click`, timestamp write).
- Press, drag out, release: no Click, Normal state handler fires, state ends Normal. Drag out and back in: Click.
- Long press held still: `LongMouseDown`, then `Up` + `LongMouseUp`, no Click. Released at 0.27 s: Click, no long press. Moved 3 pt: no long press. Moved 1 pt: long press.
- Long press with a context menu: the menu is presented only when there is no `.LongMouseDown` handler. Click with a menu and no handlers at all: the menu appears on mouseUp.
- Right click with a menu: the menu appears, nothing goes to the next responder, `RightUp` still fires on up. Right click without a menu: `RightDown`, and the next responder gets it only when `sendRightMouseAnyway` is true.
- Control-click with every combination of menu and `sendRightMouseAnyway`: menu, `RightDown`, next-responder `mouseDown` only when forwarding, `RightUp` on up.
- `userInteractionEnabled = false`: hover states still update, and down/drag/up/right down/right up all reach the next responder. `isEnabled = false`: `Down` and the state changes fire, `Up` and `Click` don't.
- Window moved between down and up (`setFrameOrigin` on the test window): no `Up`, no `Click`.
- Hover enter and exit state handlers, `LongOver` after 0.3 s, and leaving the window.
- `scaleOnClick` / `scaleDownOnClick`: the same `CASpringAnimation` on `transform` (1→1.03 / 0.97, removedOnCompletion false), and the same scale-back spring on release or drag-out.
- Tooltip (node only): `addToolTip` on the scene at the scene rect of the nested node, re-registered on a frame change. After an ancestor moves, it is re-registered on the next pointer event. It is removed on nil, removed when the node leaves the scene, and restored when the node is re-added.
- Negative control: the 0.2 s mutant fires `LongMouseDown` in the 0.27 s release scenario where `Control` clicks. Run under the equality oracle, this fails (`XCTAssertEqual failed`). The kept test asserts that the mismatch is detected.

## Differences and gaps

- Forwarding goes to `scene.nextResponder` and skips ancestor nodes. This applies wherever `Control` calls `super` while the node keeps the pointer captured: control-click with `sendRightMouseAnyway`, `rightMouseDown` with forwarding, and drags/ups after a captured down. Plain declines return `false`, so the scene still offers those events to ancestor nodes before calling `super`. Examples are a left down with `userInteractionEnabled = false` and other mouse buttons.
- `isEnabled` follows `Control` semantics: the node still gets events while disabled. The node overrides `isEnabled` and `isEffectivelyEnabled`, so the scene never blocks it, and its accessibility element reports enabled.
- Menus are presented with `AppMenu.show(..., for: scene)`. `AppMenu` sets `isSelected` only on `Control` views, so the node chains `ContextMenu.onShow/onClose` to set `isSelected`. The presentation callbacks are not exercised here because the menus are empty. `ModalMorphContextSource.registerOwner` ignores non-Control views, so a modal opened from the menu does not morph from the node.
- Not reproduced: `appTooltip` (TGUIKit's custom tooltip view; the node uses an NSView tooltip rect instead), glass touch effects, `mouseDownCanMoveWindow`, `hideAnimated`, `scrollWheel`, `redirectView`, and `mouseEntered/Exited` forwarding when `userInteractionEnabled` is false. `apply(state:)` touches the layer background only after `set(background:for:)` has been used, and the cursor only after `set(cursor:for:)`. The cursor is applied through `node.cursor`, so it changes on the next pointer update.
- Enter/exit during a press: the scene updates hover on every drag, and the node ignores `.entered/.exited` while `NSEvent.pressedMouseButtons != 0`, as Control's tracking area does. With this in place, a drag-out logs `MouseDragging` and then the Normal state, matching real AppKit. An earlier oracle synthesized enter/exit during drags and hid an ordering bug (Normal fired before `MouseDragging`). Against the fixed oracle, that node failed `testDragOut`, `testDragOutAndBack` and `testScaleDownOnClick`. Untested: whether AppKit sends a late `mouseExited` to a Control after a drag released outside. If it does, Control gets one more `.Other` handler call that the node does not.
- Tooltip rects ignore layer transforms. If an ancestor moves, the rect stays stale until the node's own frame changes or the next pointer event reaches the node. `ChatLayerSceneView.removeAllToolTips()` does not notify the node, because the scene's tooltip registry is typed to `ChatLayerTextNode`.
- `.cancelled` (scene capture invalidated by hiding, removal, or window resigning key) resets the node to Normal and cancels the long-press timers. `Control` has no equivalent. Removing the node from the scene also resets it to Normal, like `Control.viewDidMoveToWindow(nil)`.
- The long-press and long-over timers are shared among nodes, as the file-level disposables are among Controls, but not between nodes and Controls. Cancellation on `.cancelled` or on leaving the scene clears a shared timer only when this node scheduled it, so recycling one row does not kill another node's pending long press.
- Not tested: a hover entering during a drag that started in another view, live resize, and `moveNextEventDeep`.
