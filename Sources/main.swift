import Foundation

// Entry point: register the agent, start it, park the main run loop.

let agent = Custos()
Custos.activate(agent)
agent.start()
RunLoop.current.run()