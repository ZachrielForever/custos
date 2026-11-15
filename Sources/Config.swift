import Foundation

struct CustosConfig: Codable {
    var enabled: Bool = true
    var idleThresholdSeconds: Int = 60
    var promptTimeoutSeconds: Int = 8
    var activeStart: String? = nil
    var activeEnd: String? = nil

    // Tier engine
    var maxTouchIDAttempts: Int = 3
    var theaterIntensity: String = "full"   // "full" | "subtle"

    // Privacy blur: cosmetic curtain before the seal. Blur engages at
    // blurThresholdSeconds of idle; the seal fires at blur + idleThreshold.
    var blurEnabled: Bool = true
    var blurThresholdSeconds: Int = 3

    // Tier 4 unlock secret: salted SHA-512. Deliberately NOT the macOS
    // account password — a leaked system password gains nothing here, and
    // this secret grants nothing else.
    var unlockSecretSalt: String? = nil
    var unlockSecretHash: String? = nil

    // Owner notification. ntfy endpoints; list can hold several so
    // "multiple endpoints notified" stays literally true.
    // Topic names are effectively passwords — use long random strings.
    var notifyEndpoints: [String] = []

    // Logging
    var locationLogging: Bool = true
    var logPath: String = "~/.config/custos/attempts.log"

    enum CodingKeys: String, CodingKey {
        case enabled
        case idleThresholdSeconds = "idle_threshold_seconds"
        case promptTimeoutSeconds = "prompt_timeout_seconds"
        case activeStart = "active_start"
        case activeEnd = "active_end"
        case maxTouchIDAttempts = "max_touchid_attempts"
        case theaterIntensity = "theater_intensity"
        case blurEnabled = "blur_enabled"
        case blurThresholdSeconds = "blur_threshold_seconds"
        case unlockSecretSalt = "unlock_secret_salt"
        case unlockSecretHash = "unlock_secret_hash"
        case notifyEndpoints = "notify_endpoints"
        case locationLogging = "location_logging"
        case logPath = "log_path"
    }

    init() {}

    /// Missing keys fall back to defaults instead of failing the whole
    /// decode — otherwise adding config fields would silently wipe saved
    /// secrets on upgrade.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        idleThresholdSeconds = try c.decodeIfPresent(Int.self, forKey: .idleThresholdSeconds) ?? 60
        promptTimeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .promptTimeoutSeconds) ?? 8
        activeStart = try c.decodeIfPresent(String.self, forKey: .activeStart)
        activeEnd = try c.decodeIfPresent(String.self, forKey: .activeEnd)
        maxTouchIDAttempts = try c.decodeIfPresent(Int.self, forKey: .maxTouchIDAttempts) ?? 3
        theaterIntensity = try c.decodeIfPresent(String.self, forKey: .theaterIntensity) ?? "full"
        blurEnabled = try c.decodeIfPresent(Bool.self, forKey: .blurEnabled) ?? true
        blurThresholdSeconds = try c.decodeIfPresent(Int.self, forKey: .blurThresholdSeconds) ?? 3
        unlockSecretSalt = try c.decodeIfPresent(String.self, forKey: .unlockSecretSalt)
        unlockSecretHash = try c.decodeIfPresent(String.self, forKey: .unlockSecretHash)
        notifyEndpoints = try c.decodeIfPresent([String].self, forKey: .notifyEndpoints) ?? []
        locationLogging = try c.decodeIfPresent(Bool.self, forKey: .locationLogging) ?? true
        logPath = try c.decodeIfPresent(String.self, forKey: .logPath) ?? "~/.config/custos/attempts.log"
    }

    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/custos/config.json")

    static func load() -> CustosConfig {
        guard let data = try? Data(contentsOf: path) else { return CustosConfig() }
        return (try? JSONDecoder().decode(CustosConfig.self, from: data)) ?? CustosConfig()
    }

    static func fileChanged(since date: Date) -> Bool {
        guard let mtime = (try? FileManager.default.attributesOfItem(
                atPath: path.path))?[.modificationDate] as? Date else { return false }
        return mtime > date
    }

    var logURL: URL {
        URL(fileURLWithPath: (logPath as NSString).expandingTildeInPath)
    }

    /// Seconds of idle before the blur curtain rises. Floored at 1s: with a
    /// poll-based watcher, 0 and 1 are indistinguishable, and literal 0
    /// would fight active typing.
    var blurOnset: Double {
        blurEnabled ? max(Double(blurThresholdSeconds), 1) : 0
    }

    /// Seconds of idle before the seal. Blur counts toward the total.
    var totalIdle: Double {
        blurOnset + Double(idleThresholdSeconds)
    }

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