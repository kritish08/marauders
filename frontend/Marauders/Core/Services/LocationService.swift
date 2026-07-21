@preconcurrency import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
    }

    func start() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    func nearestCheckpoint(in checkpoints: [Checkpoint]) -> Checkpoint? {
        guard let location else { return nil }
        return checkpoints.compactMap { checkpoint -> (Checkpoint, CLLocationDistance)? in
            guard let gps = checkpoint.gps else { return nil }
            let target = CLLocation(latitude: gps.lat, longitude: gps.lng)
            let distance = location.distance(from: target)
            return distance <= gps.radius ? (checkpoint, distance) : nil
        }.min { $0.1 < $1.1 }?.0
    }

    func currentPlaceName() async -> String? {
        guard let location else { return nil }
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let place = placemarks?.first else { return nil }
        let area = [place.subLocality, place.locality].compactMap { $0 }
        return area.isEmpty ? place.subAdministrativeArea ?? place.administrativeArea : area.joined(separator: ", ")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedAlways || authorization == .authorizedWhenInUse { manager.startUpdatingLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.location = latest }
    }
}
