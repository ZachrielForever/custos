import AppKit
import CryptoKit
import Foundation
import LocalAuthentication

/// CLI-invocable settings window. First run (no secret configured) is open;
/// every subsequent launch requires Touch ID — reconfiguration is
/// owner-only, otherwise `custos setup` is a bypass vector.
enum Setup {
    static func needsInitialSetup() -> Bool {
        let c = CustosConfig.load()
        return c.unlockSecretHash == nil || c.unlockSecretHash!.hasPrefix("PASTE_")
    }

    static func launch(app: NSApplication) {
        if !needsInitialSetup() {
            let ctx = LAContext()
            let sem = DispatchSemaphore(value: 0)
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "Verify ownership to change Custos settings") { ok, _ in
                sem.signal()
                if ok { DispatchQueue.main.async { buildAndShow(app: app) } }
                else { NSApp.terminate(nil) }
            }
            sem.wait()
        } else {
            buildAndShow(app: app)
        }
    }

    private static func buildAndShow(app: NSApplication) {
        let cfg = CustosConfig.load()

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Custos Setup"
        win.center()

        let content = NSStackView(frame: NSRect(x: 0, y: 0, width: 460, height: 480))
        content.orientation = .vertical
        content.alignment = .leading
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        content.spacing = 12

        func row(_ label: String, _ control: NSControl) {
            let r = NSStackView(views: [NSTextField(labelWithString: label), control])
            r.orientation = .horizontal
            r.spacing = 8
            content.addArrangedSubview(r)
        }

        // Idle threshold
        let idleField = NSTextField(string: String(cfg.idleThresholdSeconds))
        idleField.placeholderString = "15"
        row("Idle threshold (sec)", idleField)

        // Max Touch ID attempts
        let attemptField = NSTextField(string: String(cfg.maxTouchIDAttempts))
        attemptField.placeholderString = "3"
        row("Max Touch ID attempts", attemptField)

        // Custos unlock secret (Tier 4)
        let secretA = NSSecureTextField()
        secretA.placeholderString = "Tier 4 unlock secret"
        row("Unlock secret", secretA)
        let secretB = NSSecureTextField()
        secretB.placeholderString = "Confirm secret"
        row("Confirm", secretB)

        // ntfy endpoint
        let endpointField = NSTextField(string: cfg.notifyEndpoints.first ?? "")
        endpointField.placeholderString = "https://ntfy.sh/your-long-random-topic"
        row("Notification topic", endpointField)

        // Theater intensity
        let intensitySeg = NSSegmentedControl(labels: ["subtle", "full"],
                                              trackingMode: .selectOne,
                                              target: nil, action: nil)
        intensitySeg.selectedSegment = cfg.theaterIntensity == "subtle" ? 0 : 1
        row("Theater", intensitySeg)

        // Location logging
        let locSwitch = NSButton(checkboxWithTitle: "Log location on attempts",
                                 target: nil, action: nil)
        locSwitch.state = cfg.locationLogging ? .on : .off
        content.addArrangedSubview(locSwitch)

        // Test notification
        let testBtn = NSButton(title: "Send test notification", target: nil, action: nil)
        testBtn.bezelStyle = .rounded
        testBtn.action = #selector(sendTest(_:))
        content.addArrangedSubview(testBtn)

        // Save
        let saveBtn = NSButton(title: "Save configuration", target: nil, action: nil)
        saveBtn.keyEquivalent = "\r"
        saveBtn.bezelStyle = .regularSquare
        content.addArrangedSubview(saveBtn)

        // Save closure wiring
        let onSave = { () -> Void in
            var newCfg = CustosConfig.load()
            newCfg.idleThresholdSeconds = Int(idleField.stringValue) ?? newCfg.idleThresholdSeconds
            newCfg.maxTouchIDAttempts = Int(attemptField.stringValue) ?? newCfg.maxTouchIDAttempts
            newCfg.theaterIntensity = intensitySeg.selectedSegment == 0 ? "subtle" : "full"
            newCfg.locationLogging = locSwitch.state == .on

            if !endpointField.stringValue.isEmpty {
                newCfg.notifyEndpoints = [endpointField.stringValue.trimmingCharacters(in: .whitespaces)]
            }

            // Secret: only set if both fields filled and matching — generate
            // salt + SHA-512 in-process.
            let sa = secretA.stringValue, sb = secretB.stringValue
            if !sa.isEmpty {
                guard sa == sb else {
                    let a = NSAlert(); a.messageText = "Secrets do not match"; a.runModal()
                    return
                }
                let salt = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
                let digest = SHA512.hash(data: Data((salt + sa).utf8))
                newCfg.unlockSecretSalt = salt
                newCfg.unlockSecretHash = digest.map { String(format: "%02x", $0) }.joined()
            }

            do {
                try JSONEncoder().encode(newCfg).write(to: CustosConfig.path)
                // hot reload: agent picks this up within its 1s poll
                let a = NSAlert(); a.messageText = "Configuration saved"; a.runModal()
                win.orderOut(nil)
            } catch {
                let a = NSAlert(); a.messageText = "Save failed: \(error.localizedDescription)"; a.runModal()
            }
        }

        // objc selectors via closures (pattern: static trampoline)
        let trampoline = SelectorTrampoline(onTest: {
            var probe = CustosConfig.load()
            if !endpointField.stringValue.isEmpty {
                probe.notifyEndpoints = [endpointField.stringValue.trimmingCharacters(in: .whitespaces)]
            }
            Notifier.ownerPing(tier: 1, detail: "Custos test notification", endpoints: probe.notifyEndpoints)
        }, onSave: onSave)

        testBtn.target = trampoline
        saveBtn.target = trampoline

        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
    }
}

/// Small NSObject trampoline so NSButton actions can call Swift closures.
final class SelectorTrampoline: NSObject {
    private let onTestClosure: () -> Void
    private let onSaveClosure: () -> Void

    init(onTest: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.onTestClosure = onTest
        self.onSaveClosure = onSave
        super.init()
    }

    @objc func sendTest(_ sender: Any?) { onTestClosure() }
    @objc func saveConfig(_ sender: Any?) { onSaveClosure() }
}