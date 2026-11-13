import AppKit
import Foundation

// Faceless app: NSApplication with LSUIElement (no Dock icon), a run loop,
// and the agent riding on it. The overlay needs an app context to draw.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // programmatic LSUIElement equivalent

let agent = Custos()
Custos.activate(agent)
agent.start()

app.run()