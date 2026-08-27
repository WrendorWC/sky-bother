import Foundation

extension Date {
    /// Julian Day number. Unix epoch (1970-01-01T00:00:00Z) is JD 2440587.5.
    var julianDay: Double {
        timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// Days since the J2000.0 epoch (2000-01-01T12:00:00 TT). Every ephemeris
    /// routine in Core is expressed in terms of this quantity.
    var daysSinceJ2000: Double {
        julianDay - 2451545.0
    }

    init(daysSinceJ2000 d: Double) {
        self.init(timeIntervalSince1970: (d + 2451545.0 - 2440587.5) * 86400.0)
    }

    func addingMinutes(_ minutes: Double) -> Date {
        addingTimeInterval(minutes * 60)
    }
}
