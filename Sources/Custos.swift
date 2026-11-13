import Foundation
import CoreGraphics
import IOKit.pwr_mgt
import LocalAuthentication

final class Custos {
    enum State { case watching, armed, prompting }

    private var state: State = .watching
    private var config = CustosConfig.load()
    private var configLoadedAt = Date()
    // LOAD-BEARING: Touch ID does not count as HID input. Without this grace
    // period, unlocking without typing would re-seal instantly (idle is
    // still over threshold). Do not remove as "redundant".
    private var baselineReset = Date.distantPast

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var powerAssertion: IOPMAssertionID = 0
    private var promptTimer: Timer?
    private var tick: Timer?

    // Statics for the C tap callback, which cannot capture context.
    fileprivate static var current: Custos?
    fileprivate static var machPort: CFMachPort?

    static func activate(_ c: Custos) { current = c }

    fileprivate static func noteInputAttempt() {
        DispatchQueue.main.async { current?.inputAttempted() }
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
            let idle = secondsIdle()
            let sinceUnlock = Date().timeIntervalSince(baselineReset)
            if idle >= Double(config.idleThresholdSeconds) &&
               sinceUnlock >= Double(config.idleThresholdSeconds) {
                arm()
            }
        case .armed, .prompting:
            // Outside schedule while sealed: release (window-mode convenience).
            if !config.isActiveNow() { disarm() }
        }
    }

    private func secondsIdle() -> CFTimeInterval {
        // kCGAnyInputEventType (~0): seconds since ANY input, system-wide.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: CGEventType(rawValue: ~0)!)
    }

    // MARK: - Arm / disarm

    private func arm() {
        state = .armed
        holdDisplayAwake()

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
            state = .watching
            releaseDisplayAwake()
            return
        }
        eventTap = tap
        Self.machPort = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func disarm() {
        promptTimer?.invalidate(); promptTimer = nil
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
        Self.machPort = nil
        releaseDisplayAwake()
        baselineReset = Date()
        state = .watching
    }

    // MARK: - Touch ID gate

    private func promptUnlock() {
        guard state == .armed else { return }
        state = .prompting

        let ctx = LAContext()
        // Timeout: invalidate the context; the sheet dismisses, seal remains.
        promptTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(config.promptTimeoutSeconds),
                                           repeats: false) { _ in ctx.invalidate() }

        // Biometrics-only, no password fallback: the keyboard is sealed while
        // this prompt is up — a text fallback we can't type into is a deadlock
        // with extra steps. VERIFY on first run: prompt behavior from a
        // launchd-spawned CLI context.
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Verify to unlock this Mac") { [weak self] ok, _ in
            self?.promptTimer?.invalidate()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    self.disarm()
                } else {
                    self.state = .armed   // failed/timeout: stay sealed
                }
            }
        }
    }

    /// Called by the tap callback on swallowed input, via the static shim.
    fileprivate func inputAttempted() {
        if state == .armed { promptUnlock() }
        // While prompting: swallow silently, sheet is already up.
    }

    // MARK: - Power assertions (screen stays live while armed)

    private func holdDisplayAwake() {
        guard powerAssertion == 0 else { return }
        IOPMAssertionCreateWithName(kIOPMAssertionNoDisplaySleepString as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Custos armed" as CFString,
                                    &powerAssertion)
    }

    private func releaseDisplayAwake() {
        guard powerAssertion != 0 else { return }
        IOPMAssertionRelease(powerAssertion)
        powerAssertion = 0
    }
}

/// C-convention tap callback: swallow ALL events while sealed. Event taps sit
/// below the session, so external USB keyboards/mice are consumed too.
private func custosTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                               event: CGEvent, refcon: UnsafeMutableRawPointer?)
        -> Unmanaged<CGEvent>? {
    // macOS auto-disables taps under load; re-enable or protection silently ends.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = Custos.machPort {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    Custos.noteInputAttempt()
    return nil   // swallow: nothing reaches the OS while sealed
}