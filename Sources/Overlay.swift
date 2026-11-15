import AppKit
import QuartzCore

/// Fullscreen borderless overlay. Four skins, one window — pre-attempt it
/// doesn't exist, first input summons it, and everything the snoop sees is
/// drawn by us on this canvas. NSVisualEffectView dim at T1, faux-terminal
/// at T2, silent alarm at T3, void at T4.
final class Overlay {
    private var window: NSWindow?
    private var text: NSTextField?        // messages (T1)
    private var textView: NSTextView?     // the "terminal" canvas (T2/T3)
    private var cursor: Timer?            // blinking block for T2/T4

    // MARK: - lifecycle

    func show() {
        guard window == nil else { return }
        guard let screen = NSScreen.main else { return }

        let w = NSWindow(contentRect: screen.frame,
                         styleMask: .borderless,
                         backing: .buffered,
                         defer: false)
        w.level = .screenSaver + 1          // above nearly everything incl. Spotlight
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = false        // tier curtains eat clicks by existing on top;
                                            // real suppression is the event tap
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.alphaValue = 1                    // fade-in state from a prior blur may linger
        w.orderFrontRegardless()
        window = w

        let bg = NSVisualEffectView(frame: screen.frame)
        bg.material = .underWindowBackground
        bg.blendingMode = .behindWindow
        bg.state = .active
        w.contentView = bg
    }

    func hide() {
        cursor?.invalidate(); cursor = nil
        window?.orderOut(nil)
        window = nil
        text = nil
        textView = nil
    }

    // MARK: - Privacy blur (cosmetic curtain; no auth, no tap)

    /// Frosted glass over the live screen. Real-time behindWindow blur, so
    /// no screen capture and no Screen Recording permission. Passes input
    /// through — it is a curtain, not a shield. Fades in for civility.
    func renderBlur() {
        show()
        guard let w = window, let bg = w.contentView else { return }
        w.ignoresMouseEvents = true         // clicks reach the apps beneath
        bg.subviews.forEach { $0.removeFromSuperview() }
        (bg as? NSVisualEffectView)?.material = .fullScreenUI

        let dim = NSView(frame: bg.bounds)
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        bg.addSubview(dim)

        text = nil
        textView = nil
        w.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            w.animator().alphaValue = 1
        }
    }

    // MARK: - Tier 1: dim + stern popup

    func renderTier1(msg: String) {
        show()
        guard let bg = window?.contentView else { return }
        window?.ignoresMouseEvents = false   // restore click-eating after a blur
        bg.subviews.forEach { $0.removeFromSuperview() }
        (bg as? NSVisualEffectView)?.material = .hudWindow

        let label = NSTextField(labelWithString: msg)
        label.alignment = .center
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .white
        label.frame = NSRect(x: 0, y: bg.bounds.midY - 20,
                             width: bg.bounds.width, height: 40)
        bg.addSubview(label)
        text = label
    }

    // MARK: - Tier 2/3: faux terminal

    /// Full-screen fake TTY. Monospace, green-on-black at T2; red-on-black
    /// at T3. Caller supplies all banner lines; we render + blink a block
    /// cursor. SCANLINES optional flourish disabled until v0.3.
    func renderTerminal(lines: [String], danger: Bool) {
        show()
        guard let bg = window?.contentView else { return }
        window?.ignoresMouseEvents = false
        bg.subviews.forEach { $0.removeFromSuperview() }
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.cgColor

        let tv = NSTextView(frame: bg.bounds.insetBy(dx: 24, dy: 24))
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.textColor = danger ? NSColor.systemRed : NSColor.green
        tv.backgroundColor = .black

        let header = lines.joined(separator: "\n")
        tv.string = header

        bg.addSubview(tv)
        textView = tv

        // Blinking block cursor at the end
        cursor = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            guard let self = self, let tv = self.textView else { return }
            let tail = tv.string.hasSuffix("\u{2588}") ? String(tv.string.dropLast()) : tv.string + "\u{2588}"
            tv.string = tail
        }
    }

    // MARK: - Tier 4: the void

    /// Pure black, blinking underscore. Nothing else. Behind it, the engine
    /// listens for the secret.
    func renderVoid() {
        show()
        guard let bg = window?.contentView else { return }
        window?.ignoresMouseEvents = false
        bg.subviews.forEach { $0.removeFromSuperview() }
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.cgColor

        let tv = NSTextView(frame: bg.bounds.insetBy(dx: 24, dy: 24))
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.textColor = .white
        tv.string = "_"
        bg.addSubview(tv)
        textView = tv

        cursor = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self = self, let tv = self.textView else { return }
            tv.string = (tv.string == "_") ? " " : "_"
        }
    }
}