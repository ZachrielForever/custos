import AppKit
import CryptoKit
import Darwin
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

    /// CLI-only secret rotation. Once set, the window can never touch the
    /// secret — reconfiguration of it is a deliberate terminal ritual.
    static func rotateSecret() {
        var cfg = CustosConfig.load()
        guard cfg.unlockSecretHash != nil else {
            FileHandle.standardError.write(Data("custos: no secret configured yet — run `custos setup` first\n".utf8))
            exit(1)
        }
        let ctx = LAContext()
        var ok = false
        let sem = DispatchSemaphore(value: 0)
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Verify ownership to rotate the Custos unlock secret") { success, _ in
            ok = success
            sem.signal()
        }
        sem.wait()
        guard ok else {
            print("custos: Touch ID failed — secret unchanged")
            exit(1)
        }
        while true {
            guard let a = readSecret("New unlock secret (min 4 chars): "), a.count >= 4 else {
                print("custos: secret must be at least 4 characters")
                continue
            }
            guard let b = readSecret("Confirm: "), a == b else {
                print("custos: secrets do not match")
                continue
            }
            let salt = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
            let digest = SHA512.hash(data: Data((salt + a).utf8))
            cfg.unlockSecretSalt = salt
            cfg.unlockSecretHash = digest.map { String(format: "%02x", $0) }.joined()
            break
        }
        do {
            let dir = CustosConfig.path.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(cfg).write(to: CustosConfig.path, options: [.atomic])
            print("custos: unlock secret rotated — agent picks it up on next config poll")
        } catch {
            FileHandle.standardError.write(Data("custos: save failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    /// Terminal read with echo disabled — the secret never lands in scrollback.
    private static func readSecret(_ prompt: String) -> String? {
        print(prompt, terminator: "")
        var oldt = termios()
        tcgetattr(STDIN_FILENO, &oldt)
        var noecho = oldt
        noecho.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &noecho)
        let line = readLine()
        tcsetattr(STDIN_FILENO, TCSANOW, &oldt)
        print("")
        return line?.trimmingCharacters(in: .whitespaces)
    }

    private static func buildAndShow(app: NSApplication) {
        let cfg = CustosConfig.load()
        let firstRun = needsInitialSetup()

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Custos Setup"
        win.center()

        let content = NSStackView(frame: NSRect(x: 0, y: 0, width: 460, height: 540))
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
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }

        // Lock delay — digits only, validated >= 5 at save. Fires after the
        // blur onset, if enabled.
        let idleField = NSTextField(string: String(cfg.idleThresholdSeconds))
        idleField.tag = 1
        idleField.placeholderString = "15"
        row("Lock delay (sec)", idleField)

        // Touch ID attempts: fixed by the escalation design, not user choice
        content.addArrangedSubview(
            NSTextField(labelWithString: "Max Touch ID attempts: 3 (fixed)"))

        // Privacy blur: cosmetic curtain before the seal
        let blurSwitch = NSButton(checkboxWithTitle: "Enable privacy blur",
                                  target: nil, action: nil)
        blurSwitch.state = cfg.blurEnabled ? .on : .off
        content.addArrangedSubview(blurSwitch)

        let blurField = NSTextField(string: String(cfg.blurThresholdSeconds))
        blurField.tag = 3
        blurField.placeholderString = "3"
        blurField.isEnabled = cfg.blurEnabled
        row("Blur onset (sec)", blurField)

        content.addArrangedSubview(
            NSTextField(labelWithString: "Lock fires at blur onset + lock delay (0 = fastest blur)"))

        // Unlock secret: settable exactly once, in this window, on first run.
        // Afterwards the window never touches it — rotation is `custos secret`.
        var secretA: NSSecureTextField? = nil
        var secretB: NSSecureTextField? = nil
        if firstRun {
            secretA = NSSecureTextField()
            secretA!.placeholderString = "Tier 4 unlock secret (min 4 chars)"
            row("Unlock secret", secretA!)
            secretB = NSSecureTextField()
            secretB!.placeholderString = "Confirm secret"
            row("Confirm", secretB!)
        } else {
            content.addArrangedSubview(
                NSTextField(labelWithString: "Unlock secret: configured — rotate via `custos secret`"))
        }

        // Notifications are optional — toggle gates the endpoint field
        let notifSwitch = NSButton(checkboxWithTitle: "Enable notifications (ntfy)",
                                   target: nil, action: nil)
        notifSwitch.state = cfg.notifyEndpoints.isEmpty ? .off : .on
        content.addArrangedSubview(notifSwitch)

        let endpointField = NSTextField(string: cfg.notifyEndpoints.first ?? "")
        endpointField.placeholderString = "https://ntfy.sh/your-long-random-topic"
        endpointField.isEnabled = notifSwitch.state == .on
        row("Notification topic", endpointField)

        // Location logging
        let locSwitch = NSButton(checkboxWithTitle: "Log location on attempts",
                                 target: nil, action: nil)
        locSwitch.state = cfg.locationLogging ? .on : .off
        content.addArrangedSubview(locSwitch)

        // Test notification
        let testBtn = NSButton(title: "Send test notification", target: nil, action: nil)
        testBtn.bezelStyle = .rounded
        content.addArrangedSubview(testBtn)

        // Save
        let saveBtn = NSButton(title: "Save configuration", target: nil, action: nil)
        saveBtn.keyEquivalent = "\r"
        saveBtn.bezelStyle = .regularSquare
        content.addArrangedSubview(saveBtn)

        // Inline status line — the single save confirmation
        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .systemGreen
        content.addArrangedSubview(statusLabel)

        // Save closure wiring
        let onSave = { () -> Void in
            func fail(_ msg: String) {
                statusLabel.stringValue = msg
                statusLabel.textColor = .systemRed
                let a = NSAlert(); a.messageText = msg; a.runModal()
            }

            // Number fields are digits-only live; bounds checked here
            guard let idle = Int(trimmed(idleField.stringValue)), idle >= 5 else {
                fail("Lock delay must be a whole number of at least 5 seconds")
                return
            }

            // Blur onset: 0 allowed — instant curtain
            var blurOnset = 0
            if blurSwitch.state == .on {
                guard let b = Int(trimmed(blurField.stringValue)), b >= 0 else {
                    fail("Blur onset must be a whole number of at least 0 seconds")
                    return
                }
                blurOnset = b
            }

            var newCfg = CustosConfig.load()
            newCfg.idleThresholdSeconds = idle
            newCfg.blurEnabled = blurSwitch.state == .on
            newCfg.blurThresholdSeconds = blurOnset
            newCfg.maxTouchIDAttempts = 3   // hardcoded: escalation design is fixed
            newCfg.theaterIntensity = "full"   // always full; no longer configurable
            newCfg.locationLogging = locSwitch.state == .on

            if notifSwitch.state == .on {
                let ep = trimmed(endpointField.stringValue)
                guard !ep.isEmpty else {
                    fail("Notifications enabled but topic is empty")
                    return
                }
                newCfg.notifyEndpoints = [ep]
            } else {
                newCfg.notifyEndpoints = []
            }

            // Secret: first run only, mandatory, min length. Later runs never
            // modify it here.
            if firstRun {
                let sa = secretA?.stringValue ?? ""
                let sb = secretB?.stringValue ?? ""
                guard !sa.isEmpty else { fail("Unlock secret is required"); return }
                guard sa.count >= 4 else { fail("Unlock secret must be at least 4 characters"); return }
                guard sa == sb else { fail("Secrets do not match"); return }
                let salt = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
                let digest = SHA512.hash(data: Data((salt + sa).utf8))
                newCfg.unlockSecretSalt = salt
                newCfg.unlockSecretHash = digest.map { String(format: "%02x", $0) }.joined()
            }

            do {
                let dir = CustosConfig.path.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try JSONEncoder().encode(newCfg).write(to: CustosConfig.path, options: [.atomic])
                // hot reload: agent picks this up within its 1s poll
                statusLabel.stringValue = "✓ Configuration saved"
                statusLabel.textColor = .systemGreen
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    win.orderOut(nil)
                    NSApp.terminate(nil)
                }
            } catch {
                fail("Save failed: \(error.localizedDescription)")
            }
        }

        let onTest = { () -> Void in
            var probe = CustosConfig.load()
            if notifSwitch.state == .on, !trimmed(endpointField.stringValue).isEmpty {
                probe.notifyEndpoints = [trimmed(endpointField.stringValue)]
            }
            Notifier.ownerPing(tier: 1, detail: "Custos test notification", endpoints: probe.notifyEndpoints)
        }

        let onToggleNotify = { () -> Void in
            let on = notifSwitch.state == .on
            endpointField.isEnabled = on
            // autopopulate the template on enable; user edits or clears freely
            if on && trimmed(endpointField.stringValue).isEmpty {
                endpointField.stringValue = "https://ntfy.sh/"
            }
            if !on { statusLabel.stringValue = "" }
        }

        let onToggleBlur = { () -> Void in
            blurField.isEnabled = blurSwitch.state == .on
        }

        // objc selectors via closures (pattern: static trampoline)
        let trampoline = SelectorTrampoline(onTest: onTest, onSave: onSave,
                                            onToggle: onToggleNotify, onToggleBlur: onToggleBlur)

        // NSControl.target is weak — pin the trampoline or ARC frees it and
        // button clicks die silently.
        SelectorTrampoline.active = trampoline

        // digits-only live filtering for the tagged number fields
        idleField.delegate = trampoline
        blurField.delegate = trampoline

        testBtn.target = trampoline
        testBtn.action = NSSelectorFromString("sendTest:")
        saveBtn.target = trampoline
        saveBtn.action = NSSelectorFromString("saveConfig:")
        notifSwitch.target = trampoline
        notifSwitch.action = NSSelectorFromString("toggleNotify:")
        blurSwitch.target = trampoline
        blurSwitch.action = NSSelectorFromString("toggleBlur:")

        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
    }
}

/// Small NSObject trampoline so NSButton actions can call Swift closures.
final class SelectorTrampoline: NSObject {
    static var active: SelectorTrampoline?

    private let onTestClosure: () -> Void
    private let onSaveClosure: () -> Void
    private let onToggleClosure: () -> Void
    private let onToggleBlurClosure: () -> Void

    init(onTest: @escaping () -> Void, onSave: @escaping () -> Void,
         onToggle: @escaping () -> Void, onToggleBlur: @escaping () -> Void) {
        self.onTestClosure = onTest
        self.onSaveClosure = onSave
        self.onToggleClosure = onToggle
        self.onToggleBlurClosure = onToggleBlur
        super.init()
    }

    @objc func sendTest(_ sender: Any?) { onTestClosure() }
    @objc func saveConfig(_ sender: Any?) { onSaveClosure() }
    @objc func toggleNotify(_ sender: Any?) { onToggleClosure() }
    @objc func toggleBlur(_ sender: Any?) { onToggleBlurClosure() }
}

extension SelectorTrampoline: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, f.tag == 1 || f.tag == 3 else { return }
        let filtered = f.stringValue.filter { $0.isASCII && $0.isNumber }
        if filtered != f.stringValue { f.stringValue = filtered }
    }
}