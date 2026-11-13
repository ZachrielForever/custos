import AppKit
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let args = CommandLine.arguments

switch args.count > 1 ? args[1] : "" {
case "setup":
    Setup.launch(app: app)
case "test":
    let cfg = CustosConfig.load()
    Notifier.ownerPing(tier: 1, detail: "Custos test notification — endpoint configured correctly",
                       endpoints: cfg.notifyEndpoints)
    print("test notification dispatched to \(cfg.notifyEndpoints.count) endpoint(s)")
default:
    // agent mode: what launchd runs
    if Setup.needsInitialSetup() {
        Setup.launch(app: app)
    } else {
        let agent = Custos()
        Custos.activate(agent)
        agent.start()
    }
}

app.run()