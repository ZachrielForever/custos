import Foundation

struct CustosConfig: Codable {
    var enabled: Bool = true
    var idleThresholdSeconds: Int = 60
    var promptTimeoutSeconds: Int = 10
    var activeStart: String? = nil
    var activeEnd: String? = nil

    enum CodingKeys: String, CodingKey {
        case enabled
        case idleThresholdSeconds = "idle_threshold_seconds"
        case promptTimeoutSeconds = "prompt_timeout_seconds"
        case activeStart = "active_start"
        case activeEnd = "active_end"
    }

    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/custos/config.json")

    static func load() -> CustosConfig {
        guard let data = try? Data(contentsOf: path) else { return CustosConfig() }
        return (try? JSONDecoder().decode(CustosConfig.self, from: data)) ?? CustosConfig()
    }

    /// True if the config file was modified since `date` (hot reload check).
    static func fileChanged(since date: Date) -> Bool {
        guard let mtime = (try? FileManager.default.attributesOfItem(
                atPath: path.path))?[.modificationDate] as? Date else { return false }
        return mtime > date
    }

    /// Window gate: nil times = always active. Overnight windows supported.
    func isActiveNow(now: Date = Date()) -> Bool {
        guard enabled else { return false }
        guard let s = Self.parseClock(activeStart), let e = Self.parseClock(activeEnd) else {
            return true
        }
        let cal = Calendar.current
        let cur = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return s <= e ? (cur >= s && cur < e) : (cur >= s || cur < e)
    }

    private static func parseClock(_ s: String?) -> Int? {
        guard let s = s else { return nil }
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }
}