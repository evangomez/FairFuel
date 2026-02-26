import Foundation
import CoreLocation
import SwiftData

@Model
final class TripPoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var speedMps: Double
    var horizontalAccuracy: Double

    var session: DrivingSession?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(location: CLLocation, session: DrivingSession) {
        self.timestamp = location.timestamp
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.speedMps = max(0, location.speed)
        self.horizontalAccuracy = location.horizontalAccuracy
        self.session = session
    }
}
