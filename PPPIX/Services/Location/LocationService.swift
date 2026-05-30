import CoreLocation

final class LocationService: NSObject, @unchecked Sendable {

    nonisolated(unsafe) static let shared = LocationService()
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func getCurrentLocation() async -> CLLocationCoordinate2D? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }

        // Cache recente (< 60s) — retorna imediatamente sem delay
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -60 {
            return cached.coordinate
        }

        // Solicita leitura com timeout de 4s
        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            let helper = LocationRequestHelper(continuation: cont, fallback: self.manager.location?.coordinate)
            helper.start()
        }
    }
}

// Helper isolado para uma única leitura de localização com timeout
private final class LocationRequestHelper: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let cont: CheckedContinuation<CLLocationCoordinate2D?, Never>
    private let fallback: CLLocationCoordinate2D?
    private var finished = false

    init(continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>, fallback: CLLocationCoordinate2D?) {
        self.cont = continuation
        self.fallback = fallback
        super.init()
    }

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestLocation()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.finish(with: self?.fallback)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: fallback)
    }

    private func finish(with coord: CLLocationCoordinate2D?) {
        guard !finished else { return }
        finished = true
        cont.resume(returning: coord)
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if s == .authorizedWhenInUse || s == .authorizedAlways {
            manager.requestLocation()
        }
    }
}
