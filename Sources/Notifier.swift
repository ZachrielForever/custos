import Foundation

/// ntfy push notifications. Fires async, best-effort; notification failure
/// must never wedge the seal loop.
enum Notifier {
    static func ownerPing(tier: Int, detail: String, endpoints: [String]) {
        let title = tier >= 3 ? "CUSTOS: MULTIPLE FAILED VERIFICATION ATTEMPTS"
                              : "Custos: verification requested on Aegis"
        let priority = tier >= 3 ? "urgent" : "default"
        let tags = tier >= 3 ? "rotating_light" : "closed_lock_with_key"
        push(title: title, body: detail, priority: priority, tags: tags, endpoints: endpoints)
    }

    private static func push(title: String, body: String, priority: String,
                            tags: String, endpoints: [String]) {
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = "POST"
            req.setValue(title, forHTTPHeaderField: "Title")
            req.setValue(priority, forHTTPHeaderField: "Priority")
            req.setValue(tags, forHTTPHeaderField: "Tags")
            req.httpBody = Data(body.utf8)
            URLSession.shared.dataTask(with: req).resume()
        }
    }
}