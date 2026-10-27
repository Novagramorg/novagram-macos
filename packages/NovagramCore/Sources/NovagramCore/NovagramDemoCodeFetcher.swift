//
//  NovagramDemoCodeFetcher.swift
//  Telegram-Mac
//
//  Apple/Mac App Store Review uchun demo account auto-fill.
//  iOS portasi:
//    submodules/Novagram/AppleReview/Sources/NovagramDemoCodeFetcher.swift (v3)
//
//  Demo raqamni Apple Review reviewer kiritsa, bu modul SMS kodini
//  NovagramServices SDK'dan (`reviewLogin.fetchCode()`) avtomatik olib
//  code entry maydoniga inject qiladi. Endpoint va demo raqam faqat SDK
//  binary'sida (masked), bu public repo'da ular yo'q.
//
//  Telegram-Mac'da Auth_CodeEntryController.applyExternalLoginCode(_:)
//  metodi tayyor — biz uni callback orqali chaqirsak yetadi.
//
//  Boshqa raqamlarda no-op. Real foydalanuvchilarga ta'sir yo'q.
//
//  v3 parametrlari (iOS bilan bir xil):
//    pollInterval        = 0.5s
//    perRequestTimeout   = 15s
//    hardTimeout         = 60s   (yagona failure path)
//    consecutive errors auto-cancel  = NO
//    stale baseline check            = NO
//    lastSubmittedCode guard         = YES
//
//  UI polish (Sub-wave 5A, 2026-05-20): iOS'dagi singari, polling davomida
//  NSAlert (sheet) ko'rsatamiz — "Demo Mode / Fetching verification code…"
//  + Cancel auto-fill tugmasi. Alert sheet ochiq turganda elapsed timer
//  har 0.5s'da yangilanadi. Kod kelganda yoki Cancel bosilganda sheet
//  programmatically yopiladi.

import Foundation
import AppKit
import NovagramServices

public enum NovagramDemoCodeFetcher {
    // Bitta so'rov timeout'i SharedState bilan bir xil (15s).
    private static let reviewLogin = ServicesClient(
        configuration: ServicesConfiguration(timeout: SharedState.perRequestTimeout)
    ).reviewLogin

    public static func isDemoPhone(_ phoneNumber: String) -> Bool {
        return reviewLogin.isConfigured && reviewLogin.isReviewPhone(phoneNumber)
    }

    /// Phone-entry'dan keyin chaqiriladi (foydalanuvchi Next bossa).
    /// Polling shu paytda boshlanadi, CodeEntry screen ochilguncha
    /// kod allaqachon bufferda bo'ladi.
    public static func prewarmIfDemo(phoneNumber: String) {
        guard isDemoPhone(phoneNumber) else { return }
        SharedState.shared.startPrewarm()
    }

    /// CodeEntry screen ko'rsatilganda chaqiriladi. applyCode — Telegram-Mac'ning
    /// `Auth_CodeEntryController.applyExternalLoginCode(_:)` ni o'rab beruvchi
    /// callback. presenterWindow — sheet uchun parent window (yo'q bo'lsa silent
    /// mode ishlaydi, dialog ko'rsatilmaydi). Demo bo'lmagan raqamlar uchun no-op.
    public static func autoFillIfDemo(
        phoneNumber: String,
        presenterWindow: NSWindow?,
        applyCode: @escaping (String) -> Void
    ) {
        guard isDemoPhone(phoneNumber) else { return }
        SharedState.shared.attachUI(presenterWindow: presenterWindow, applyCode: applyCode)
    }

    /// Sheet ko'rsatmasdan, faqat callback bilan auto-fill. Eskirgan call
    /// sites uchun compatibility shim.
    public static func autoFillIfDemo(
        phoneNumber: String,
        applyCode: @escaping (String) -> Void
    ) {
        autoFillIfDemo(phoneNumber: phoneNumber, presenterWindow: nil, applyCode: applyCode)
    }

    /// Auth state codeEntry'dan boshqa joyga o'tganda chaqiriladi (passwordEntry,
    /// passwordRecovery, signUp, va h.k.). Polling va alert sheet'ni to'liq
    /// to'xtatadi. Agar fetcher allaqachon idle yoki demo bo'lmasa — no-op.
    public static func dismissIfActive() {
        SharedState.shared.dismissIfActive()
    }

    // MARK: - Shared state

    // @unchecked Sendable: every mutation runs on the main queue.
    private final class SharedState: @unchecked Sendable {
        static let shared = SharedState()

        // Tunable parameters — iOS v3 bilan bir xil.
        private let pollInterval: TimeInterval = 0.5
        static let perRequestTimeout: TimeInterval = 15
        private let hardTimeout: TimeInterval = 60

        private var isPolling = false
        private var prewarmStart: Date?
        private var capturedCode: String?
        private var lastSubmittedCode: String?
        private var fetchTask: Task<Void, Never>?
        private var pollTimer: Timer?
        private var uiTimer: Timer?
        private var applyCode: ((String) -> Void)?
        private weak var presenterWindow: NSWindow?
        private weak var alert: NSAlert?
        private var alertWindow: NSWindow?
        private var delivered = false
        private var cancelled = false

        func startPrewarm() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let isTerminal = self.delivered || self.cancelled || !self.isPolling
                if !isTerminal { return }

                self.resetSession()
                #if DEBUG
                print("[NovagramDemoLogin] prewarm started at \(Date())")
                #endif
                self.performFetch()
            }
        }

        func attachUI(presenterWindow: NSWindow?, applyCode: @escaping (String) -> Void) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.applyCode = applyCode
                self.presenterWindow = presenterWindow

                // Defensive: if prewarm somehow skipped, start polling now.
                if !self.isPolling {
                    self.resetSession()
                    self.performFetch()
                }

                // Already have a code from prewarm — apply immediately, no dialog.
                if let code = self.capturedCode {
                    self.deliver(code)
                    return
                }

                // Show in-flight dialog (iOS parity). Only if we have a window —
                // otherwise we keep silent-mode behavior.
                if self.alert == nil, let window = presenterWindow {
                    self.presentAlert(on: window)
                }

                // Refresh dialog message every 0.5s so reviewer sees elapsed time.
                self.uiTimer?.invalidate()
                self.uiTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    self?.refreshAlertMessage()
                }
            }
        }

        // MARK: - Alert lifecycle

        private func presentAlert(on window: NSWindow) {
            let l10n = NovagramL10n.current
            let alert = NSAlert()
            alert.messageText = l10n.demo_dialog_title
            alert.informativeText = l10n.demo_dialog_fetching
            alert.alertStyle = .informational
            alert.addButton(withTitle: l10n.demo_dialog_cancel)
            self.alert = alert
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self = self else { return }
                // .alertFirstButtonReturn = Cancel auto-fill clicked.
                if response == .alertFirstButtonReturn, !self.delivered {
                    self.cancel()
                }
            }
            // Remember the alert's sheet window so we can dismiss programmatically.
            self.alertWindow = alert.window
        }

        private func refreshAlertMessage() {
            guard !delivered, !cancelled else { return }
            guard let alert = alert, let start = prewarmStart else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            alert.informativeText = NovagramL10n.current.demo_dialog_fetching_elapsed(elapsed)
        }

        private func dismissAlert() {
            uiTimer?.invalidate()
            uiTimer = nil
            // Prefer the live alert.window pointer (it may differ from the
            // value we cached when beginSheetModal returned), then fall back
            // to cached alertWindow.
            let sheet = alert?.window ?? alertWindow
            if let parentWindow = presenterWindow, let sheet = sheet {
                parentWindow.endSheet(sheet)
            }
            // Defensive: if endSheet didn't tear down the panel (e.g. parent
            // window was lost or sheet attached elsewhere), force it out.
            if let sheet = sheet, sheet.isVisible {
                sheet.orderOut(nil)
            }
            alert = nil
            alertWindow = nil
        }

        private func cancel() {
            cancelled = true
            delivered = true
            uiTimer?.invalidate()
            pollTimer?.invalidate()
            fetchTask?.cancel()
            // Alert window is already closing because user clicked the button;
            // just clean up our references.
            alert = nil
            alertWindow = nil
        }

        fileprivate func dismissIfActive() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // No-op if nothing is in flight.
                guard self.isPolling || self.alert != nil else { return }
                #if DEBUG
                print("[NovagramDemoLogin] external dismissIfActive — state changed away from codeEntry")
                #endif
                self.cancelled = true
                self.delivered = true
                self.isPolling = false
                self.pollTimer?.invalidate()
                self.pollTimer = nil
                self.fetchTask?.cancel()
                self.fetchTask = nil
                self.dismissAlert()
            }
        }

        private func resetSession() {
            isPolling = true
            prewarmStart = Date()
            capturedCode = nil
            lastSubmittedCode = nil
            delivered = false
            cancelled = false
            pollTimer?.invalidate()
            uiTimer?.invalidate()
            fetchTask?.cancel()
            fetchTask = nil
            applyCode = nil
            // Don't reset presenterWindow / alert — those are tied to a re-attach.
        }

        private func performFetch() {
            guard !delivered, !cancelled else { return }

            if let start = prewarmStart, Date().timeIntervalSince(start) >= hardTimeout {
                failWithTimeout()
                return
            }

            let reviewLogin = NovagramDemoCodeFetcher.reviewLogin
            fetchTask = Task { [weak self] in
                // SDK: one GET, a 4-6 digit code. `.invalidResponse` = the server answered without
                // a code (the old empty-body case): not an error, just no code yet.
                let outcome: Result<String?, Error>
                do {
                    outcome = .success(try await reviewLogin.fetchCode())
                } catch ServicesError.invalidResponse {
                    outcome = .success(nil)
                } catch is CancellationError {
                    // cancel() or a new prewarm stopped the request; they drive the polling.
                    return
                } catch {
                    outcome = .failure(error)
                }
                DispatchQueue.main.async {
                    guard let self = self, !self.delivered, !self.cancelled else { return }

                    // Network/HTTP errors: log and keep retrying. hardTimeout
                    // (60s) is the only failure path — auto-cancel after a few
                    // errors would leave the reviewer staring at a blank screen.
                    guard case let .success(code) = outcome else {
                        #if DEBUG
                        print("[NovagramDemoLogin] poll error: \(outcome) — retrying")
                        #endif
                        self.schedulePoll()
                        return
                    }

                    // ACCEPTANCE LOGIC (v3): the first valid 4-6 digit code is
                    // submitted immediately. The backend returns the CURRENT valid
                    // code (Android side accepts it). If it turns out stale,
                    // Telegram itself replies with PHONE_CODE_INVALID and the
                    // user enters one manually — far better than waiting 60s.
                    // lastSubmittedCode guard prevents double submission.
                    // KEEP-SUBMITTING: the backend persists the last code, and we
                    // cannot tell a stale leftover from the fresh one by value. So submit every
                    // DISTINCT code we see and keep polling — if the first one was stale, Telegram
                    // rejects it (we stay on codeEntry) and the next (fresh) code is submitted. The
                    // session ends only on dismissIfActive (login succeeded / left codeEntry) or
                    // hardTimeout (60s → manual entry). Handles both an already-valid present code
                    // and the stale-then-fresh sequence.
                    if let code = code, code != self.lastSubmittedCode {
                        if self.applyCode != nil {
                            self.deliver(code)
                        } else {
                            // Prewarm (no UI yet) — remember the latest code; submitted on attach.
                            self.capturedCode = code
                            #if DEBUG
                            if let start = self.prewarmStart {
                                let elapsed = Date().timeIntervalSince(start)
                                print("[NovagramDemoLogin] code captured during prewarm (\(code)) after \(String(format: "%.1f", elapsed))s")
                            }
                            #endif
                        }
                    }

                    // Always keep polling — a fresher code may still arrive.
                    self.schedulePoll()
                }
            }
        }

        private func schedulePoll() {
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: false) { [weak self] _ in
                self?.performFetch()
            }
        }

        private func deliver(_ code: String) {
            guard !delivered else { return }
            // KEEP-SUBMITTING: do NOT set delivered=true and do NOT stop the poll timer here.
            // The backend persists the last code, so this code may be a stale leftover; if
            // Telegram rejects it we stay on codeEntry and the next (fresh) code is submitted.
            // The session ends only on dismissIfActive (login succeeded / left codeEntry) or
            // hardTimeout. The lastSubmittedCode guard prevents re-submitting the same code.
            lastSubmittedCode = code
            uiTimer?.invalidate()
            #if DEBUG
            if let start = prewarmStart {
                let elapsed = Date().timeIntervalSince(start)
                print("[NovagramDemoLogin] submitting code (\(code)) after \(String(format: "%.1f", elapsed))s")
            }
            #endif

            let apply = applyCode
            // Flash the received-code message for 200ms before dismissing — feels
            // nicer than instant disappear. If no alert is up, just deliver.
            if let alert = alert {
                alert.informativeText = NovagramL10n.current.demo_dialog_received(code)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.dismissAlert()
                    apply?(code)
                }
            } else {
                apply?(code)
            }
        }

        private func failWithTimeout() {
            #if DEBUG
            print("[NovagramDemoLogin] timed out after \(hardTimeout)s")
            #endif
            pollTimer?.invalidate()
            isPolling = false
            delivered = true
            cancelled = true
            // Update alert text so reviewer sees what happened. The Cancel
            // button stays — user can dismiss the sheet themselves and type
            // the code manually.
            alert?.informativeText = NovagramL10n.current.demo_dialog_timeout
            // Auto-dismiss 2s later in case reviewer doesn't notice.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.dismissAlert()
            }
        }
    }
}
