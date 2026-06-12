//
//  JetLagPlanCalculator.swift
//  Moonbeam
//

import CoreLocation
import Foundation

struct JetLagSleepWindow: Identifiable, Codable {
    let id: UUID
    let bedMinutes: Int
    let wakeMinutes: Int

    init(bedMinutes: Int, wakeMinutes: Int) {
        self.id = UUID()
        self.bedMinutes = ((bedMinutes % 1440) + 1440) % 1440
        self.wakeMinutes = ((wakeMinutes % 1440) + 1440) % 1440
    }

    var durationMinutes: Int {
        var d = wakeMinutes - bedMinutes
        if d <= 0 { d += 1440 }
        return d
    }
}

struct JetLagNightPlan: Identifiable, Codable {
    let id: UUID
    let nightIndex: Int
    /// Calendar day on which this night begins (the evening of).
    let date: Date
    let sleepWindow: JetLagSleepWindow

    init(nightIndex: Int, date: Date, sleepWindow: JetLagSleepWindow) {
        self.id = UUID()
        self.nightIndex = nightIndex
        self.date = date
        self.sleepWindow = sleepWindow
    }

    /// Absolute bedtime. A bed time before noon belongs to the following
    /// calendar morning (e.g. "Night of June 8, bed at 1:50 AM" = June 9, 01:50).
    var bedDate: Date {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let offset = sleepWindow.bedMinutes < 720
            ? sleepWindow.bedMinutes + 1440
            : sleepWindow.bedMinutes
        return cal.date(byAdding: .minute, value: offset, to: dayStart) ?? dayStart
    }

    var wakeDate: Date {
        Calendar.current.date(byAdding: .minute, value: sleepWindow.durationMinutes, to: bedDate) ?? bedDate
    }
}

struct JetLagPlan: Codable {
    let originName: String
    let destinationCity: String
    let localOffsetHours: Int
    let destinationOffsetHours: Int
    let idealBedMinutes: Int
    let idealWakeMinutes: Int
    let sleepDurationMinutes: Int
    /// Origin sunrise/sunset on the origin's clock.
    let originSunriseMinutes: Int
    let originSunsetMinutes: Int
    /// Destination sunrise/sunset on the destination's clock.
    let destSunriseMinutes: Int
    let destSunsetMinutes: Int
    let nights: [JetLagNightPlan]
    let createdAt: Date

    /// Timezone difference normalized to the shortest direction, in minutes.
    /// Positive = destination ahead (shift sleep earlier), negative = behind
    /// (shift sleep later). A +14 h shift becomes a −10 h delay — delaying
    /// sleep is easier than advancing it.
    var tzShiftMinutes: Int {
        Self.normalizedShiftMinutes(
            localOffsetHours: localOffsetHours,
            destOffsetHours: destinationOffsetHours
        )
    }

    /// Destination sunrise/sunset converted onto the origin's clock, so both
    /// day/night cycles can be drawn on the same time axis.
    var destSunriseLocalMinutes: Int {
        (((destSunriseMinutes - tzShiftMinutes) % 1440) + 1440) % 1440
    }

    var destSunsetLocalMinutes: Int {
        (((destSunsetMinutes - tzShiftMinutes) % 1440) + 1440) % 1440
    }

    static func normalizedShiftMinutes(localOffsetHours: Int, destOffsetHours: Int) -> Int {
        var d = ((destOffsetHours - localOffsetHours) * 60) % 1440
        d = ((d % 1440) + 1440) % 1440
        if d > 720 { d -= 1440 }
        return d
    }

    /// Same trip, different number of transition nights.
    func withNightCount(_ count: Int) -> JetLagPlan {
        JetLagPlanCalculator.generatePlan(
            originName: originName,
            destinationCity: destinationCity,
            nightCount: count,
            originSunrise: originSunriseMinutes,
            originSunset: originSunsetMinutes,
            destSunrise: destSunriseMinutes,
            destSunset: destSunsetMinutes,
            localOffsetHours: localOffsetHours,
            destOffsetHours: destinationOffsetHours,
            idealBedMinutes: idealBedMinutes,
            idealWakeMinutes: idealWakeMinutes,
            sleepDurationMinutes: sleepDurationMinutes
        )
    }

    var maxNightCount: Int { 10 }
}

enum JetLagPlanCalculator {

    static func generatePlan(
        originName: String,
        destinationCity: String,
        nightCount: Int,
        originSunrise: Int,
        originSunset: Int,
        destSunrise: Int,
        destSunset: Int,
        localOffsetHours: Int,
        destOffsetHours: Int,
        idealBedMinutes: Int = 22 * 60 + 30,
        idealWakeMinutes: Int = 7 * 60,
        sleepDurationMinutes: Int = 7 * 60 + 30
    ) -> JetLagPlan {
        let shift = JetLagPlan.normalizedShiftMinutes(
            localOffsetHours: localOffsetHours,
            destOffsetHours: destOffsetHours
        )

        let count = max(1, nightCount)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var nights: [JetLagNightPlan] = []
        for i in 0..<count {
            let fraction = Double(i + 1) / Double(count)

            // Subtracting the shift moves the window toward the destination's
            // ideal bedtime as read on the origin clock: by the last night,
            // (bed + shift) mod 24h == the ideal destination bedtime.
            let delta = Int((Double(shift) * fraction).rounded())
            let window = JetLagSleepWindow(
                bedMinutes: idealBedMinutes - delta,
                wakeMinutes: idealWakeMinutes - delta
            )

            // Night 1 is tonight.
            let nightDate = cal.date(byAdding: .day, value: i, to: today) ?? today

            nights.append(JetLagNightPlan(nightIndex: i, date: nightDate, sleepWindow: window))
        }

        return JetLagPlan(
            originName: originName,
            destinationCity: destinationCity,
            localOffsetHours: localOffsetHours,
            destinationOffsetHours: destOffsetHours,
            idealBedMinutes: idealBedMinutes,
            idealWakeMinutes: idealWakeMinutes,
            sleepDurationMinutes: sleepDurationMinutes,
            originSunriseMinutes: originSunrise,
            originSunsetMinutes: originSunset,
            destSunriseMinutes: destSunrise,
            destSunsetMinutes: destSunset,
            nights: nights,
            createdAt: Date()
        )
    }

    // MARK: - Place Resolution

    struct ResolvedPlace {
        let name: String
        let timeZone: TimeZone
        let latitude: Double?
        let longitude: Double?

        var offsetHours: Int { timeZone.secondsFromGMT() / 3600 }
    }

    /// Resolves an airport code, timezone identifier, or free-text city name.
    /// IATA codes are checked against a built-in table first because free-text
    /// geocoding of codes like "LHR" is unreliable.
    static func resolvePlace(_ query: String) async throws -> ResolvedPlace {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CityResolveError.notFound }

        // 1. IATA airport code
        if trimmed.count == 3, trimmed.allSatisfy({ $0.isLetter }),
           let airport = Self.airports[trimmed.uppercased()],
           let tz = TimeZone(identifier: airport.tzID) {
            return ResolvedPlace(name: airport.city, timeZone: tz, latitude: airport.lat, longitude: airport.lng)
        }

        // 2. Timezone identifier like "Europe/London"
        if trimmed.contains("/"), let tz = TimeZone(identifier: trimmed) {
            let cityPart = trimmed.split(separator: "/").last.map {
                $0.replacingOccurrences(of: "_", with: " ")
            } ?? trimmed
            let coords = try? await geocode(String(cityPart))
            return ResolvedPlace(
                name: String(cityPart),
                timeZone: tz,
                latitude: coords?.lat,
                longitude: coords?.lng
            )
        }

        // 3. Free-text city name
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(trimmed)
        guard let place = placemarks.first,
              let tz = place.timeZone,
              let loc = place.location else {
            throw CityResolveError.notFound
        }
        let displayName = place.locality ?? place.name ?? trimmed
        return ResolvedPlace(
            name: displayName,
            timeZone: tz,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude
        )
    }

    private static func geocode(_ query: String) async throws -> (lat: Double, lng: Double) {
        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        guard let loc = placemarks.first?.location else { throw CityResolveError.notFound }
        return (loc.coordinate.latitude, loc.coordinate.longitude)
    }

    // MARK: - Sun Times

    /// Fetches sunrise/sunset for the coordinates, expressed as minutes since
    /// midnight on the clock of `timeZone` (the place's own local time).
    static func fetchSunTimes(lat: Double?, lng: Double?, timeZone: TimeZone) async -> (sunrise: Int, sunset: Int) {
        let fallback = (390, 1200)
        guard let lat, let lng,
              let url = URL(string: "https://api.sunrise-sunset.org/json?lat=\(lat)&lng=\(lng)&formatted=0") else {
            return fallback
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SunAPIPublicResponse.self, from: data)
            guard response.status == "OK" else { return fallback }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var sr = formatter.date(from: response.results.sunrise)
            var ss = formatter.date(from: response.results.sunset)
            if sr == nil || ss == nil {
                formatter.formatOptions = [.withInternetDateTime]
                sr = sr ?? formatter.date(from: response.results.sunrise)
                ss = ss ?? formatter.date(from: response.results.sunset)
            }
            guard let sunrise = sr, let sunset = ss else { return fallback }

            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let srMin = cal.component(.hour, from: sunrise) * 60 + cal.component(.minute, from: sunrise)
            let ssMin = cal.component(.hour, from: sunset) * 60 + cal.component(.minute, from: sunset)
            return (srMin, ssMin)
        } catch {
            return fallback
        }
    }

    enum CityResolveError: LocalizedError {
        case notFound
        var errorDescription: String? { "Could not find that place. Try a city name, airport code, or timezone like Europe/London." }
    }

    // MARK: - Airport Table

    struct Airport {
        let city: String
        let tzID: String
        let lat: Double
        let lng: Double
    }

    static let airports: [String: Airport] = [
        "SFO": Airport(city: "San Francisco", tzID: "America/Los_Angeles", lat: 37.6213, lng: -122.3790),
        "LAX": Airport(city: "Los Angeles", tzID: "America/Los_Angeles", lat: 33.9416, lng: -118.4085),
        "SAN": Airport(city: "San Diego", tzID: "America/Los_Angeles", lat: 32.7338, lng: -117.1933),
        "SEA": Airport(city: "Seattle", tzID: "America/Los_Angeles", lat: 47.4502, lng: -122.3088),
        "PDX": Airport(city: "Portland", tzID: "America/Los_Angeles", lat: 45.5898, lng: -122.5951),
        "LAS": Airport(city: "Las Vegas", tzID: "America/Los_Angeles", lat: 36.0840, lng: -115.1537),
        "PHX": Airport(city: "Phoenix", tzID: "America/Phoenix", lat: 33.4373, lng: -112.0078),
        "DEN": Airport(city: "Denver", tzID: "America/Denver", lat: 39.8561, lng: -104.6737),
        "SLC": Airport(city: "Salt Lake City", tzID: "America/Denver", lat: 40.7899, lng: -111.9791),
        "DFW": Airport(city: "Dallas", tzID: "America/Chicago", lat: 32.8998, lng: -97.0403),
        "IAH": Airport(city: "Houston", tzID: "America/Chicago", lat: 29.9902, lng: -95.3368),
        "AUS": Airport(city: "Austin", tzID: "America/Chicago", lat: 30.1975, lng: -97.6664),
        "ORD": Airport(city: "Chicago", tzID: "America/Chicago", lat: 41.9742, lng: -87.9073),
        "MSP": Airport(city: "Minneapolis", tzID: "America/Chicago", lat: 44.8848, lng: -93.2223),
        "ATL": Airport(city: "Atlanta", tzID: "America/New_York", lat: 33.6407, lng: -84.4277),
        "MIA": Airport(city: "Miami", tzID: "America/New_York", lat: 25.7959, lng: -80.2870),
        "MCO": Airport(city: "Orlando", tzID: "America/New_York", lat: 28.4312, lng: -81.3081),
        "JFK": Airport(city: "New York", tzID: "America/New_York", lat: 40.6413, lng: -73.7781),
        "LGA": Airport(city: "New York", tzID: "America/New_York", lat: 40.7769, lng: -73.8740),
        "EWR": Airport(city: "Newark", tzID: "America/New_York", lat: 40.6895, lng: -74.1745),
        "BOS": Airport(city: "Boston", tzID: "America/New_York", lat: 42.3656, lng: -71.0096),
        "IAD": Airport(city: "Washington", tzID: "America/New_York", lat: 38.9531, lng: -77.4565),
        "DCA": Airport(city: "Washington", tzID: "America/New_York", lat: 38.8512, lng: -77.0402),
        "YVR": Airport(city: "Vancouver", tzID: "America/Vancouver", lat: 49.1967, lng: -123.1815),
        "YYZ": Airport(city: "Toronto", tzID: "America/Toronto", lat: 43.6777, lng: -79.6248),
        "YUL": Airport(city: "Montreal", tzID: "America/Toronto", lat: 45.4706, lng: -73.7408),
        "MEX": Airport(city: "Mexico City", tzID: "America/Mexico_City", lat: 19.4363, lng: -99.0721),
        "CUN": Airport(city: "Cancún", tzID: "America/Cancun", lat: 21.0365, lng: -86.8771),
        "GRU": Airport(city: "São Paulo", tzID: "America/Sao_Paulo", lat: -23.4356, lng: -46.4731),
        "GIG": Airport(city: "Rio de Janeiro", tzID: "America/Sao_Paulo", lat: -22.8100, lng: -43.2506),
        "EZE": Airport(city: "Buenos Aires", tzID: "America/Argentina/Buenos_Aires", lat: -34.8222, lng: -58.5358),
        "SCL": Airport(city: "Santiago", tzID: "America/Santiago", lat: -33.3930, lng: -70.7858),
        "BOG": Airport(city: "Bogotá", tzID: "America/Bogota", lat: 4.7016, lng: -74.1469),
        "LIM": Airport(city: "Lima", tzID: "America/Lima", lat: -12.0219, lng: -77.1143),
        "LHR": Airport(city: "London", tzID: "Europe/London", lat: 51.4700, lng: -0.4543),
        "LGW": Airport(city: "London", tzID: "Europe/London", lat: 51.1537, lng: -0.1821),
        "STN": Airport(city: "London", tzID: "Europe/London", lat: 51.8860, lng: 0.2389),
        "DUB": Airport(city: "Dublin", tzID: "Europe/Dublin", lat: 53.4264, lng: -6.2499),
        "CDG": Airport(city: "Paris", tzID: "Europe/Paris", lat: 49.0097, lng: 2.5479),
        "ORY": Airport(city: "Paris", tzID: "Europe/Paris", lat: 48.7262, lng: 2.3652),
        "AMS": Airport(city: "Amsterdam", tzID: "Europe/Amsterdam", lat: 52.3105, lng: 4.7683),
        "FRA": Airport(city: "Frankfurt", tzID: "Europe/Berlin", lat: 50.0379, lng: 8.5622),
        "MUC": Airport(city: "Munich", tzID: "Europe/Berlin", lat: 48.3538, lng: 11.7861),
        "BER": Airport(city: "Berlin", tzID: "Europe/Berlin", lat: 52.3667, lng: 13.5033),
        "ZRH": Airport(city: "Zurich", tzID: "Europe/Zurich", lat: 47.4647, lng: 8.5492),
        "MAD": Airport(city: "Madrid", tzID: "Europe/Madrid", lat: 40.4983, lng: -3.5676),
        "BCN": Airport(city: "Barcelona", tzID: "Europe/Madrid", lat: 41.2974, lng: 2.0833),
        "LIS": Airport(city: "Lisbon", tzID: "Europe/Lisbon", lat: 38.7756, lng: -9.1354),
        "FCO": Airport(city: "Rome", tzID: "Europe/Rome", lat: 41.8003, lng: 12.2389),
        "CPH": Airport(city: "Copenhagen", tzID: "Europe/Copenhagen", lat: 55.6181, lng: 12.6561),
        "OSL": Airport(city: "Oslo", tzID: "Europe/Oslo", lat: 60.1976, lng: 11.1004),
        "ARN": Airport(city: "Stockholm", tzID: "Europe/Stockholm", lat: 59.6498, lng: 17.9239),
        "HEL": Airport(city: "Helsinki", tzID: "Europe/Helsinki", lat: 60.3183, lng: 24.9497),
        "ATH": Airport(city: "Athens", tzID: "Europe/Athens", lat: 37.9356, lng: 23.9484),
        "IST": Airport(city: "Istanbul", tzID: "Europe/Istanbul", lat: 41.2753, lng: 28.7519),
        "DXB": Airport(city: "Dubai", tzID: "Asia/Dubai", lat: 25.2532, lng: 55.3657),
        "AUH": Airport(city: "Abu Dhabi", tzID: "Asia/Dubai", lat: 24.4330, lng: 54.6511),
        "DOH": Airport(city: "Doha", tzID: "Asia/Qatar", lat: 25.2731, lng: 51.6080),
        "TLV": Airport(city: "Tel Aviv", tzID: "Asia/Jerusalem", lat: 32.0114, lng: 34.8867),
        "CAI": Airport(city: "Cairo", tzID: "Africa/Cairo", lat: 30.1219, lng: 31.4056),
        "JNB": Airport(city: "Johannesburg", tzID: "Africa/Johannesburg", lat: -26.1367, lng: 28.2411),
        "CPT": Airport(city: "Cape Town", tzID: "Africa/Johannesburg", lat: -33.9715, lng: 18.6021),
        "BOM": Airport(city: "Mumbai", tzID: "Asia/Kolkata", lat: 19.0896, lng: 72.8656),
        "DEL": Airport(city: "Delhi", tzID: "Asia/Kolkata", lat: 28.5562, lng: 77.1000),
        "BKK": Airport(city: "Bangkok", tzID: "Asia/Bangkok", lat: 13.6900, lng: 100.7501),
        "KUL": Airport(city: "Kuala Lumpur", tzID: "Asia/Kuala_Lumpur", lat: 2.7456, lng: 101.7099),
        "SIN": Airport(city: "Singapore", tzID: "Asia/Singapore", lat: 1.3644, lng: 103.9915),
        "CGK": Airport(city: "Jakarta", tzID: "Asia/Jakarta", lat: -6.1256, lng: 106.6559),
        "HKG": Airport(city: "Hong Kong", tzID: "Asia/Hong_Kong", lat: 22.3080, lng: 113.9185),
        "TPE": Airport(city: "Taipei", tzID: "Asia/Taipei", lat: 25.0797, lng: 121.2342),
        "PVG": Airport(city: "Shanghai", tzID: "Asia/Shanghai", lat: 31.1443, lng: 121.8083),
        "PEK": Airport(city: "Beijing", tzID: "Asia/Shanghai", lat: 40.0799, lng: 116.6031),
        "CAN": Airport(city: "Guangzhou", tzID: "Asia/Shanghai", lat: 23.3924, lng: 113.2988),
        "ICN": Airport(city: "Seoul", tzID: "Asia/Seoul", lat: 37.4602, lng: 126.4407),
        "NRT": Airport(city: "Tokyo", tzID: "Asia/Tokyo", lat: 35.7720, lng: 140.3929),
        "HND": Airport(city: "Tokyo", tzID: "Asia/Tokyo", lat: 35.5494, lng: 139.7798),
        "KIX": Airport(city: "Osaka", tzID: "Asia/Tokyo", lat: 34.4347, lng: 135.2441),
        "SYD": Airport(city: "Sydney", tzID: "Australia/Sydney", lat: -33.9399, lng: 151.1753),
        "MEL": Airport(city: "Melbourne", tzID: "Australia/Melbourne", lat: -37.6690, lng: 144.8410),
        "BNE": Airport(city: "Brisbane", tzID: "Australia/Brisbane", lat: -27.3842, lng: 153.1175),
        "PER": Airport(city: "Perth", tzID: "Australia/Perth", lat: -31.9385, lng: 115.9672),
        "AKL": Airport(city: "Auckland", tzID: "Pacific/Auckland", lat: -37.0082, lng: 174.7850),
        "HNL": Airport(city: "Honolulu", tzID: "Pacific/Honolulu", lat: 21.3245, lng: -157.9251),
        "ANC": Airport(city: "Anchorage", tzID: "America/Anchorage", lat: 61.1743, lng: -149.9963),
    ]
}

private struct SunAPIPublicResponse: Codable, Sendable {
    let results: SunAPIPublicResults
    let status: String
}

private struct SunAPIPublicResults: Codable, Sendable {
    let sunrise: String
    let sunset: String
}
