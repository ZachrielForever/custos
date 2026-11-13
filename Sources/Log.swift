import Foundation

/// JSONL attempt logger. One structured record per event; greppable,
/// jq-queryable. Every seal cycle gets a session ID so a whole incident
/// reads as a narrative.
enum Log {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static var sessionID = ""

    static func beginSeal(reason: String) -> String {
        sessionID = String(UUID().uuidString.prefix(8))
        event("seal", tier: 0, ["reason": reason])
        return sessionID
    }

    static func event(_ name: String, tier: Int, _ fields: [String: String] = [:]) {
        var record: [String: Any] = [
            "ts": formatter.string(from: Date()),
            "session": sessionID,
            "event": name,
            "tier": tier,
        ]
        for (k, v) in fields { record[k] = v }

        let url = CustosConfig.load().logURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let line = (try JSONSerialization.data(withJSONObject: record)) 
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line + [0x0A]))
        } catch {
            NSLog("Custos: log write failed: \(error)")
        }
    }
}