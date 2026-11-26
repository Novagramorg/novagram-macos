# Accessibility (VoiceOver) for Telegram macOS

## Scope

Phase 1, this plan: VoiceOver. Every screen in `docs/analytics/coverage/macos.yaml` can be read and operated with VoiceOver: every control has a role and a label, every text is readable, every list row reads as one item, and every action a mouse user has is reachable.

Phase 2, after phase 1 is done: Full Keyboard Access (Tab focus on TGUIKit controls), Reduce Motion, Increase Contrast. Not part of this plan's definition of done.

## Definition of done

Phase 1 is done when all of these hold:

1. **Auditor clean in the lab.** `AccessibilityAudit` (TGUIKit) reports zero issues for every component rendered by the accessibility lab and the TGUIKit tests.
2. **Lint clean.** `tools/a11y_lint.py` reports zero icon buttons, image views or clickable controls created without a label or an explicit decorative mark.
3. **Ledger complete.** Every item in `docs/accessibility/ledger.yaml` (one per screen in the macOS coverage inventory) is `done` or `n/a` with a reason.
4. **Main flows match iOS.** Chat list rows, messages, the chat input, the chat header, the media viewer and calls read what iOS reads (see `docs/accessibility/ios-parity.md`).
5. **Tests pass.** TGUIKit and GeneralRows accessibility tests pass with `swift test`.

## Rules for the implementation

- Accessibility is computed lazily: override the `NSAccessibility` methods (`isAccessibilityElement()`, `accessibilityRole()`, `accessibilityLabel()`, `accessibilityValue()`, `accessibilityPerformPress()`) and never compute labels during layout. VoiceOver off means no cost.
- A label is the product name of the thing ("Send", "Attach", "Back"), never the icon name.
- Decorative images and spacers are marked decorative explicitly; an unlabeled image is a bug.
- Strings use `VoiceOver.*` keys in `Telegram-Mac/en.lproj/Localizable.strings` (UTF-16), with the iOS key name when iOS has the same thing.

## Decisions

- **Secrets** (wallet recovery phrase and similar): exposed to accessibility only while VoiceOver is running, via `TextView.isAccessibilitySensitive`. Hidden from other accessibility clients otherwise.
- **Kill switch**: the reconnected accessibility tree is on by default. It turns off when either the Developer setting "VoiceOver Accessibility Tree" is off, or the server app config sets `macos_accessibility_disabled = true`. The server value is cached, so it applies from the next launch before the config loads.
- **Lists**: TGUIKit tables are exposed as accessibility lists, never as tables, because NSTableView's own accessibility asks for columns our lists don't have (the Oct 9 2026 crash). Off-screen rows (100 on each side of the visible ones) are stand-in elements that scroll their row into view when VoiceOver reaches them.

## Layers

1. **TGUIKit base classes**: `Control`, `Button`/`ImageButton`/`TextButton`, `TextView`, `SwitchView`, `SelectingControl`, `ImageView`, `TableRowView`/`TableRowItem`, `SearchView`, `NavigationBar`/back button, `ModalViewController`, `Window`.
2. **GeneralRows**: `GeneralInteractedRowItem` and the other shared rows used by the `InputDataController` screens.
3. **Main screens, iOS parity**: chat list, chat history, chat input, chat header, peer info, media viewer, calls, stories.
4. **Long tail**: every other screen in the ledger, package by package, driven by the lint and the auditor.

## Tools

- `AccessibilityAudit` in TGUIKit: walks the accessibility tree and the view tree of a view or window and returns issues.
- Accessibility lab: a TGUIKit-only window that renders every base control and shared row and prints the audit.
- Developer menu "Accessibility Audit": audits the key window of the running app.
- `tools/a11y_lint.py`: static check of creation sites.
