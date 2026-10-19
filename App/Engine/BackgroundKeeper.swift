import CoreLocation
import Foundation

/// Keeps the app running while the phone is locked in the car, so it can keep polling
/// the player and pushing lyric lines to the Live Activity.
///
/// Prototype-only strategy: low-accuracy background location. For the App Store build
/// this is replaced by a server that pushes Live Activity updates via APNs.
@MainActor
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var session: CLBackgroundActivitySession?
    private(set) var isActive = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        session = CLBackgroundActivitySession()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        session?.invalidate()
        session = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location itself is unused; receiving updates is what keeps us alive.
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
