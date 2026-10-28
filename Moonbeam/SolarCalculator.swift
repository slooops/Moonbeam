//
//  SolarCalculator.swift
//  Moonbeam
//

import Foundation

/// Sunrise, sunset and twilight times for one local day. A nil time means the
/// sun never crosses that altitude that day (polar day or night).
struct SunEventTimes: Equatable, Sendable {
    let sunrise: Date?
    let sunset: Date?
    let civilDawn: Date?
    let civilDusk: Date?
    let nauticalDawn: Date?
    let nauticalDusk: Date?
    let astronomicalDawn: Date?
    let astronomicalDusk: Date?
}

/// Computes sun times on the device with the NOAA sunrise equation, so no
/// location ever leaves the phone and it works offline (handy mid-flight).
/// Accurate to within a minute or two away from the poles.
enum SolarCalculator {
    /// Sun altitudes, in degrees, that define each event. Sunrise and sunset
    /// allow for atmospheric refraction and the sun's radius.
    private enum Altitude {
        static let sunrise = -0.833
        static let civil = -6.0
        static let nautical = -12.0
        static let astronomical = -18.0
    }

    /// Sun events for the calendar day containing `date` on the clock of `timeZone`.
    static func events(latitude: Double, longitude: Double, on date: Date = Date(),
                       timeZone: TimeZone = .current) -> SunEventTimes {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date

        // Days since J2000, rounded to the nearest solar day for this longitude.
        let julianNoon = noon.timeIntervalSince1970 / 86400 + 2440587.5
        let day = (julianNoon - 2451545.0 + 0.0008).rounded()
        let meanSolarNoon = day - longitude / 360

        let anomaly = normalized(357.5291 + 0.98560028 * meanSolarNoon)
        let center = 1.9148 * sin(radians(anomaly))
            + 0.0200 * sin(radians(2 * anomaly))
            + 0.0003 * sin(radians(3 * anomaly))
        let eclipticLongitude = normalized(anomaly + center + 180 + 102.9372)
        let transit = 2451545.0 + meanSolarNoon
            + 0.0053 * sin(radians(anomaly))
            - 0.0069 * sin(radians(2 * eclipticLongitude))
        let declination = asin(sin(radians(eclipticLongitude)) * sin(radians(23.4397)))

        func crossing(_ altitude: Double) -> (rise: Date, set: Date)? {
            let latitude = radians(latitude)
            let cosHourAngle = (sin(radians(altitude)) - sin(latitude) * sin(declination))
                / (cos(latitude) * cos(declination))
            guard (-1...1).contains(cosHourAngle) else { return nil }
            let offset = degrees(acos(cosHourAngle)) / 360
            return (julianDate(transit - offset), julianDate(transit + offset))
        }

        let sun = crossing(Altitude.sunrise)
        let civil = crossing(Altitude.civil)
        let nautical = crossing(Altitude.nautical)
        let astronomical = crossing(Altitude.astronomical)
        return SunEventTimes(
            sunrise: sun?.rise, sunset: sun?.set,
            civilDawn: civil?.rise, civilDusk: civil?.set,
            nauticalDawn: nautical?.rise, nauticalDusk: nautical?.set,
            astronomicalDawn: astronomical?.rise, astronomicalDusk: astronomical?.set
        )
    }

    /// Sunrise and sunset as minutes since midnight on `timeZone`'s clock, or nil
    /// when the sun doesn't rise or set that day.
    static func sunriseSunsetMinutes(latitude: Double, longitude: Double, on date: Date = Date(),
                                     timeZone: TimeZone) -> (sunrise: Int, sunset: Int)? {
        let events = events(latitude: latitude, longitude: longitude, on: date, timeZone: timeZone)
        guard let sunrise = events.sunrise, let sunset = events.sunset else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func minutes(_ date: Date) -> Int {
            calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        }
        return (minutes(sunrise), minutes(sunset))
    }

    private static func julianDate(_ julian: Double) -> Date {
        Date(timeIntervalSince1970: (julian - 2440587.5) * 86400)
    }

    private static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
