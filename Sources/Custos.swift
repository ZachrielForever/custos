import Foundation
import AppKit
import CoreGraphics
import CryptoKit
import IOKit.pwr_mgt
import LocalAuthentication

final class Custos {
    enum State { case watching, t1, t2, t3, t4 }

    private var state: State = .watching
    private var config = CustosConfig.load()
    private var configLoadedAt = Date()
    // LOAD-BEARING: Touch ID isn't HID input; without this grace period,
    // unlocking without typing would re-seal instantly. Do not remove.
    private var baselineReset = Date.distantPast

    private var touchIDFails = 0
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var powerAssertion: IOPMAssertionID = 0
    private var promptTimer: Timer?
    private var tick: Timer?
    private let overlay = Overlay()

    // Tier 4 hidden credential buffer. ESC clears; Return submits.
    // Never rendered, never echoed, never forwarded to the OS.
    private var secretBuffer = ""
    private var sessionID = ""

    fileprivate static var current: Custos?
    fileprivate static var machPort: CFMachPort?

    static func activate(_ c: Custos) { current = c }

    fileprivate static func noteKeystroke(_ chars: String) {
        DispatchQueue.main.async { current?.handleKeystroke(chars) }
    }

    fileprivate static func noteOtherInput() {
        DispatchQueue.main.async { current?.handleOtherInput() }
    }

    func start() {
        tick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        if CustosConfig.fileChanged(since: configLoadedAt) {
            config = CustosConfig.load()
            configLoadedAt = Date()
        }
        switch state {
        case .watching:
            guard config.isActiveNow() else { return }
            let idle = CGEventSource.secondsSinceLastEventType(
                .combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if idle >= Double(config.idleThresholdSeconds) &&
               Date().timeIntervalSince(baselineReset) >= Double(config.idleThresholdSeconds) {
                seal()
            }
        default:
            if !config.isActiveNow() { unseal(logEvent: "outside_schedule_release") }
        }
    }

    // MARK: - Seal / unseal

    private func seal() {
        state = .t1
        sessionID = Log.beginSeal(reason: "idle threshold reached")
        holdDisplayAwake()
        installTap()
        // Silence: no visual change yet. First input summons the overlay.
    }

    private func unseal(logEvent: String) {
        Log.event(logEvent, tier: state == .watching ? 0 : tierNumber(), ["outcome": "unsealed"])
        promptTimer?.invalidate(); promptTimer = nil
        removeTap()
        overlay.hide()
        releaseDisplayAwake()
        touchIDFails = 0
        secretBuffer = ""
        baselineReset = Date()
        state = .watching
    }

    private func tierNumber() -> Int {
        switch state { case .t1: 1; case .t2: 2; case .t3: 3; case .t4: 4; case .watching: 0 }
    }

    // MARK: - Input interpretation (all input dies here; tap forwards nothing)

    private func handleOtherInput() {
        // Mouse/trackpad/scroll events: trigger the current tier's curtain
        // if it hasn't risen yet, otherwise ignored (not meaningful input).
        summonIfNeeded()
    }

    private func handleKeystroke(_ chars: String) {
        if state == .t4 {
            // Hidden terminal: ESC clears, Return submits, else accumulate.
            for ch in chars {
                switch ch {
                case "\r":
                    submitSecret()
                case "\u{1B}":
                    secretBuffer = ""
                default:
                    secretBuffer.append(ch)
                }
            }
            return
        }
        summonIfNeeded()
    }

    /// The moment of first contact: raise the appropriate curtain.
    private func summonIfNeeded() {
        switch state {
        case .t1 where !overlayVisible():
            riseTier1()
        case .t2 where !overlayVisible():
            riseTier2()
        case .t3 where !overlayVisible():
            riseTier3()
        case .t4 where !overlayVisible():
            overlay.renderVoid()
        default:
            break
        }
    }

    private func overlayVisible() -> Bool { /* opaque check */ windowUp }

    private var windowUp = false

    // MARK: - Tier curtains

    private func riseTier1() {
        windowUp = true
        Log.event("input_attempt", tier: 1)
        Notifier.ownerPing(tier: 1, detail: "verification requested on Aegis", endpoints: config.notifyEndpoints)
        snapLocationIntoLog(tier: 1)
        overlay.renderTier1(msg: "Touch to Unlock.\nUnauthorized access will be logged and transmitted to the owner's registered device.")
        promptTouchID()
    }

    private func riseTier2() {
        windowUp = true
        Log.event("tier_escalation", tier: 2)
        Notifier.ownerPing(tier: 2, detail: "verification FAILED on Aegis (attempt 1)", endpoints: config.notifyEndpoints)
        snapLocationIntoLog(tier: 2)
        let ts = ISO8601DateFormatter().string(from: Date())
        overlay.renderTerminal(lines: [
            "aegis ttyu0 — biometric verification shell",
            "========================================================",
            "STATION:      aegis (Apple T2)",
            "LOCAL TIME:   \(ts)",
            "SESSION:      \(sessionID)-BIOVERIFY",
            "STATUS:       VERIFICATION FAILED (1/3) — LOCK HELD",
            "",
            "*** TOUCH THE SENSOR TO CONTINUE ***",
            "unauthorized contact is timestamped and forwarded",
        ], danger: false)
        promptTouchID()
    }

    private func riseTier3() {
        windowUp = true
        Log.event("tier_escalation", tier: 3)
        Notifier.ownerPing(tier: 3, detail: "verification FAILED TWICE on Aegis — sustained unauthorized contact", endpoints: config.notifyEndpoints)
        snapLocationIntoLog(tier: 3)
        let ts = ISO8601DateFormatter().string(from: Date())
        overlay.renderTerminal(lines: [
            "!!! BIOMETRIC VERIFICATION FAILURE ×2 !!!",
            "========================================================",
            "ATTEMPT FINGERPRINT DID NOT MATCH ENROLLED OWNER",
            "FORENSIC RECORD SYNCED: attempt-\(ts)",
            "OWNER DEVICES: ALERTED",
            "REGISTERED ENDPOINTS: NOTIFYING (MULTIPLE)",
            "THIS STATION REMAINS UNDER REMOTE MONITORING",
            "",
            "FINAL OPPORTUNITY: TOUCH SENSOR TO VERIFY",
            "NEXT FAILURE TRANSFERS THIS STATION TO RESTRICTED MODE",
        ], danger: true)
        promptTouchID()
    }

    // Falls to T4 after final Touch ID failure.
    private func riseTier4() {
        // Guard: no configured secret means the void has no exit but the
        // power button. Loop Touch ID instead of entering the void.
        // Setup normally prevents this state from ever existing.
        if config.unlockSecretHash == nil || config.unlockSecretHash!.hasPrefix("PASTE_") {
            state = .t3
            windowUp = false
            promptTouchID()
            return
        }

        windowUp = true
        Log.event("tier_escalation", tier: 4, ["note": "restricted mode"])
        Notifier.ownerPing(tier: 4, detail: "Custos: Aegis entering restricted mode after repeated failed verification", endpoints: config.notifyEndpoints)
        snapLocationIntoLog(tier: 4)
        promptTimer?.invalidate()
        overlay.renderVoid()
        // No timeout: T4 waits indefinitely. Owner ritual: ESC, type secret,
        // Return. Nobody else has the secret, and no visual confirms typing.
    }

    // MARK: - Touch ID / secret verification

    private func promptTouchID() {
        guard state != .t4, touchIDFails < config.maxTouchIDAttempts else { riseTier4(); return }
        let ctx = LAContext()
        promptTimer?.invalidate()
        promptTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.promptTimeoutSeconds),
                                           repeats: false) { _ in ctx.invalidate() }
        // VERIFY: sheet under our screenSaver-level overlay — may need to
        // momentarily drop window level so the system sheet shows. First-run
        // empirical; failure mode is benign (sheet hidden, tap still sealed).
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Verify ownership") { [weak self] ok, _ in
            guard let self = self else { return }
            self.promptTimer?.invalidate()
            DispatchQueue.main.async {
                if ok {
                    Log.event("owner_verified", tier: self.tierNumber(), ["method": "touchid"])
                    self.unseal(logEvent: "unlock")
                } else {
                    self.touchIDFails += 1
                    Log.event("verify_failed", tier: self.tierNumber())
                    // Escalate: t1 -> t2 -> t3 -> t4; stop asking Touch ID.
                    switch self.state {
                    case .t1: self.state = .t2
                    case .t2: self.state = .t3
                    default: self.state = .t4
                    }
                    self.windowUp = false
                    if self.state == .t4 || self.touchIDFails >= self.config.maxTouchIDAttempts {
                        self.riseTier4()
                    }
                }
            }
        }
    }

    /// T4: verify the custos secret, NOT the macOS password.
    private func submitSecret() {
        guard let salt = config.unlockSecretSalt, let want = config.unlockSecretHash,
              !secretBuffer.isEmpty else { secretBuffer = ""; return }
        let candidate = Data((salt + secretBuffer).utf8)
        let digest = SHA512.hash(data: candidate)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        if hex == want {
            Log.event("owner_verified", tier: 4, ["method": "custos_secret"])
            unseal(logEvent: "unlock")
        } else {
            Log.event("secret_rejected", tier: 4)
            secretBuffer = ""   // infinite attempts; silently reset
        }
    }

    private func snapLocationIntoLog(tier: Int) {
        guard config.locationLogging else { return }
        Locator.snapshot { coord in
            var fields = ["location": "unavailable"]
            if let c = coord { fields["location"] = c }
            Log.event("position_snapshot", tier: tier, fields)
        }
    }

    // MARK: - Event tap (unchanged core, new interpretation layer)

    private func installTap() {
        guard eventTap == nil else { return }
        var mask: UInt64 = 0
        for t: CGEventType in [.keyDown, .keyUp, .flagsChanged,
                               .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                               .otherMouseDown, .otherMouseUp, .mouseMoved,
                               .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                               .scrollWheel] {
            mask |= (1 << UInt64(t.rawValue))
        }
        guard let tap = CGEvent.tapCreate(postLocatedAt: .cghidEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          placement: .headInsertEventTap,
                                          callback: custosTapCallback,
                                          userInfo: nil) else {
            NSLog("Custos: event tap refused — check Accessibility + Input Monitoring grants")
            return
        }
        eventTap = tap
        Self.machPort = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        promptTimer = nil
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
        Self.machPort = nil
        windowUp = false
        releaseDisplayAwake()
    }

    private func holdDisplayAwake() {
        guard powerAssertion == 0 else { return }
        IOPMAssertionCreateWithName(kIOPMAssertionNoDisplaySleepString as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Custos sealed" as CFString,
                                    &powerAssertion)
    }

    private func releaseDisplayAwake() {
        guard powerAssertion != 0 else { return }
        IOPMAssertionRelease(powerAssertion)
        powerAssertion = 0
    }
}

/// C tap callback. While sealed, NOTHING reaches the OS. Keys are decoded
/// into characters for the engine's hidden buffer (T4); everything else
/// merely signals "input happened."
private func custosTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                               event: CGEvent, refcon: UnsafeMutableRawPointer?)
        -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = Custos.machPort { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if type == .keyDown, let chars = event.keyboardGetUnicodeString() {
        Custos.noteKeystroke(chars)
    } else {
        Custos.noteOtherInput()
    }
    return nil   // swallow: zero input reaches the system while sealed
}

extension CGEvent {
    /// Best-effort text extraction for hidden-buffer accumulation.
    /// VERIFY: covers the printable set; dead keys/IME corner cases
    /// may degrade silently — irrelevant to snoops, mildly annoying to
    /// an owner typing a secret with unusual characters.
    func keyboardGetUnicodeString() -> String? {
        var length: Int = 0
        keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }
        var buf = [UniChar](repeating: 0, count: length)
        keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &buf)
        return String(utf16CodeUnits: buf, count: length)
    }
}