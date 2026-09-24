import Foundation

enum Format {

    static func time(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func timeWithMeridiem(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    /// "Sunday", for headings that name a night.
    static func fullWeekday(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func dayAndMonth(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    static func longDate(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter.string(from: date)
    }

    /// "4h 25m", "45m", "—"
    /// Storage, in the units a person thinks in.
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

    static func arcseconds(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f\u{2033}", value) : String(format: "%.0f\u{2033}", value)
    }

    static func duration(minutes: Double) -> String {
        guard minutes.isFinite, minutes > 0 else { return "—" }
        let total = Int(minutes.rounded())
        let hours = total / 60
        let remainder = total % 60
        if hours == 0 { return "\(remainder)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    static func hours(_ value: Double) -> String {
        duration(minutes: value * 60)
    }

    static func temperature(celsius: Double, imperial: Bool) -> String {
        guard celsius.isFinite else { return "—" }
        if imperial {
            return String(format: "%.0f°F", celsius * 9 / 5 + 32)
        }
        return String(format: "%.0f°C", celsius)
    }

    static func temperatureDelta(celsius: Double, imperial: Bool) -> String {
        guard celsius.isFinite else { return "—" }
        return imperial ? String(format: "%.1f°F", celsius * 9 / 5) : String(format: "%.1f°C", celsius)
    }

    static func wind(kilometersPerHour: Double, imperial: Bool) -> String {
        guard kilometersPerHour.isFinite else { return "—" }
        if imperial {
            return String(format: "%.0f mph", kilometersPerHour * 0.621371)
        }
        return String(format: "%.0f km/h", kilometersPerHour)
    }

    static func degrees(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.0f°", value)
    }

    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    /// Right ascension as hours, minutes; declination as signed degrees, arcmin.
    static func coordinates(_ coordinate: EquatorialCoordinate) -> String {
        let raHoursTotal = coordinate.rightAscension / 15
        let raHours = Int(raHoursTotal)
        let raMinutes = (raHoursTotal - Double(raHours)) * 60
        let sign = coordinate.declination < 0 ? "−" : "+"
        let decMagnitude = abs(coordinate.declination)
        let decDegrees = Int(decMagnitude)
        let decMinutes = (decMagnitude - Double(decDegrees)) * 60
        return String(format: "%02dh %04.1fm  %@%02d° %02.0f′",
                      raHours, raMinutes, sign, decDegrees, decMinutes)
    }

    /// To the second of arc, for typing into a telescope's own app.
    ///
    /// Rounded as whole tenths of a second of time and whole seconds of arc
    /// before splitting into fields, so 59.96s carries into the next minute
    /// instead of printing as "60.0s".
    static func preciseCoordinates(_ coordinate: EquatorialCoordinate) -> String {
        let raTenths = Int((coordinate.rightAscension / 15 * 36_000).rounded()) % (24 * 36_000)
        let sign = coordinate.declination < 0 ? "−" : "+"
        let decSeconds = Int((abs(coordinate.declination) * 3600).rounded())
        return String(format: "%02dh %02dm %04.1fs  %@%02d° %02d′ %02d″",
                      raTenths / 36_000, raTenths / 600 % 60, Double(raTenths % 600) / 10,
                      sign, decSeconds / 3600, decSeconds / 60 % 60, decSeconds % 60)
    }
}
