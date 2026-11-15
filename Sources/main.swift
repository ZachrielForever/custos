import AppKit
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let args = CommandLine.arguments

switch args.count > 1 ? args[1] : "" {
case "setup":
    // exit when the last window closes — no lingering accessory process
    class QuitOnClose: NSObject, NSApplicationDelegate {
        static var pin: QuitOnClose?
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    }
    QuitOnClose.pin = QuitOnClose()
    app.delegate = QuitOnClose.pin
    Setup.launch(app: app)
    app.run()
case "secret":
    Setup.rotateSecret()
    exit(0)
case "test":
    let cfg = CustosConfig.load()
    Notifier.ownerPing(tier: 1, detail: "Custos test notification — endpoint configured correctly",
                       endpoints: cfg.notifyEndpoints)
    print("test notification dispatched to \(cfg.notifyEndpoints.count) endpoint(s)")
    exit(0)
default:
    // agent mode: refuse to arm on incomplete config. Opening setup from a
    // KeepAlive launchd job respawn-loops the window forever.
    if Setup.needsInitialSetup() {
        FileHandle.standardError.write(
            Data("custos: configuration incomplete — run `custos setup` before arming the agent\n".utf8))
        exit(1)
    }
    let agent = Custos()
    Custos.activate(agent)
    agent.start()
    app.run()
}