import CoreLocation

/// One-shot location snapshot for attempt records.
/// SETUP REQUIREMENT: grant Location permission to the custos binary once
/// (Privacy & Security → Location). Note the menu-bar arrow appears briefly
/// during fetch — only ever after an attempt, so no pre-attempt tell.
/// Without Wi-Fi positioning (cellular-tethered Mac has no GPS) accuracy is
/// coarse (city-block scale); we record what the OS gives us, nothing more.
final class Locator: NSObject, CLLocationManagerDelegate {
    private static var shared: Locator?
    private var handler: ((String?) -> Void)?
    private var manager: CLLocationManager?

    static func snapshot(handler: @escaping (String?) -> Void) {
        let status = CLLocationManager.authorizationStatus()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            handler(nil); return
        }
        let loc = Locator()
        loc.handler = handler
        shared = loc   // retain: the manager dies with its delegate otherwise
        let mgr = CLLocationManager()
        mgr.delegate = loc
        loc.manager = mgr
        mgr.requestLocation()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        if let l = locs.last {
            let acc = Int(l.horizontalAccuracy.rounded())
            let coord = String(format: "%.5f,%.5f (±%dm)", l.coordinate.latitude,
                               l.coordinate.longitude, acc)
            handler?(coord)
        } else { handler?(nil) }
        Locator.shared = nil
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        handler?(nil)
        Locator.shared = nil
    }
}