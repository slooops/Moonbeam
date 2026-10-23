// Scheduled gate times, rather than live estimates, keep a saved plan predictable.
import Foundation

struct FlightSchedule: Codable, Equatable, Identifiable {
    let number: String
    let departureAirport: String
    let arrivalAirport: String
    let departure: Date
    let arrival: Date
    let departureTimeZoneID: String
    let arrivalTimeZoneID: String
    let source: String
    var referenceDeparture: Date?

    var id: String { "\(number)-\(departure.timeIntervalSince1970)-\(departureAirport)-\(arrivalAirport)" }
    var duration: TimeInterval { arrival.timeIntervalSince(departure) }
    var departureTimeZone: TimeZone { TimeZone(identifier: departureTimeZoneID) ?? .gmt }
    var arrivalTimeZone: TimeZone { TimeZone(identifier: arrivalTimeZoneID) ?? .gmt }
    var isValid: Bool {
        !number.isEmpty && duration > 0 && duration <= 24 * 3600
            && TimeZone(identifier: departureTimeZoneID) != nil
            && TimeZone(identifier: arrivalTimeZoneID) != nil
    }

    func formatted(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Defaults to free public-page lookup. An optional proxy/provider can replace it later.
struct FlightScheduleService {
    let session: URLSession
    let proxyURL: URL?
    let developmentAPIKey: String?
    let referenceDate: Date

    init(session: URLSession = .shared, proxyURL: URL? = nil, developmentAPIKey: String? = nil, referenceDate: Date = Date()) {
        self.session = session
        self.referenceDate = referenceDate
        self.proxyURL = proxyURL ?? (Bundle.main.object(forInfoDictionaryKey: "FlightScheduleProxyURL") as? String).flatMap(URL.init(string:))
        #if DEBUG
        self.developmentAPIKey = developmentAPIKey ?? ProcessInfo.processInfo.environment["AERODATABOX_API_KEY"]
        #else
        self.developmentAPIKey = nil
        #endif
    }

    static func normalizedNumber(_ value: String) -> String {
        value.uppercased().filter { !$0.isWhitespace }
    }

    func lookup(number: String, date: Date, timeZone: TimeZone) async throws -> [FlightSchedule] {
        let number = Self.normalizedNumber(number)
        guard number.range(of: "^[A-Z0-9]{2,3}[0-9]{1,4}[A-Z]?$", options: .regularExpression) != nil else {
            throw LookupError.invalidNumber
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        var request: URLRequest
        if let proxyURL, proxyURL.scheme == "https" {
            var url = URLComponents(url: proxyURL, resolvingAgainstBaseURL: false)!
            url.queryItems = (url.queryItems ?? []) + [
                URLQueryItem(name: "flight", value: number),
                URLQueryItem(name: "date", value: day)
            ]
            request = URLRequest(url: url.url!)
        } else if let key = developmentAPIKey, !key.isEmpty {
            let url = URL(string: "https://aerodatabox.p.rapidapi.com/flights/number/\(number)/\(day)?dateLocalRole=Departure")!
            request = URLRequest(url: url)
            request.setValue(key, forHTTPHeaderField: "X-RapidAPI-Key")
            request.setValue("aerodatabox.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")
        } else {
            return try await lookupPublic(number: number, day: day)
        }
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let flights = try Self.decode(try await responseData(for: request))
        guard !flights.isEmpty else { throw LookupError.notFound }
        return flights
    }

    private func lookupPublic(number: String, day: String) async throws -> [FlightSchedule] {
        do {
            return try await publicSchedules(number: number, day: day)
        } catch LookupError.notFound {
            // A recent schedule can seed a distant date, but it must remain an explicit estimate.
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        guard let requested = formatter.date(from: day) else { throw LookupError.notFound }
        // Prefer the same weekday within the public source's recent coverage.
        let weekdayDifference = calendar.component(.weekday, from: requested) - calendar.component(.weekday, from: referenceDate)
        let nearestOffset = ((weekdayDifference + 10) % 7) - 3
        let nearest = calendar.date(byAdding: .day, value: nearestOffset, to: referenceDate)!
        let candidates = [formatter.string(from: nearest), formatter.string(from: referenceDate)]
        var tried: Set<String> = [day]
        for candidate in candidates where tried.insert(candidate).inserted {
            try Task.checkCancellation()
            do {
                let recent = try await publicSchedules(number: number, day: candidate)
                return try recent.map { try PublicFlightSchedule.estimatedSchedule(from: $0, departureDay: day) }
            } catch LookupError.notFound {
                continue
            }
        }
        throw LookupError.notFound
    }

    private func publicSchedules(number: String, day: String) async throws -> [FlightSchedule] {
        var request = URLRequest(url: try PublicFlightSchedule.url(number: number, date: day))
        request.timeoutInterval = 20
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data = try await responseData(for: request)
        guard data.count <= 5_000_000, let html = String(data: data, encoding: .utf8) else {
            throw LookupError.unavailable
        }
        return try PublicFlightSchedule.decode(html, number: number, departureDay: day)
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LookupError.unavailable }
        switch response.statusCode {
        case 204, 404: throw LookupError.notFound
        case 401, 403: throw LookupError.accessDenied
        case 429: throw LookupError.rateLimited
        case 200: return data
        default: throw LookupError.unavailable
        }
    }

    static func decode(_ data: Data) throws -> [FlightSchedule] {
        let flights = try JSONDecoder().decode([ProviderFlight].self, from: data)
        var seen = Set<String>()
        return flights.compactMap { flight -> FlightSchedule? in
            guard flight.status?.lowercased() != "canceled",
                  flight.status?.lowercased() != "cancelled",
                  flight.isCargo != true,
                  let departure = flight.departure.scheduledTime?.date,
                  let arrival = flight.arrival.scheduledTime?.date,
                  let originZone = flight.departure.airport.timeZone,
                  let destinationZone = flight.arrival.airport.timeZone else { return nil }
            let schedule = FlightSchedule(
                number: flight.number,
                departureAirport: flight.departure.airport.iata ?? flight.departure.airport.name,
                arrivalAirport: flight.arrival.airport.iata ?? flight.arrival.airport.name,
                departure: departure, arrival: arrival,
                departureTimeZoneID: originZone, arrivalTimeZoneID: destinationZone,
                source: "AeroDataBox"
            )
            guard schedule.isValid, seen.insert(schedule.id).inserted else { return nil }
            return schedule
        }.sorted { $0.departure < $1.departure }
    }

    enum LookupError: LocalizedError {
        case invalidNumber, unavailable, notFound, accessDenied, rateLimited, cancelled
        var errorDescription: String? {
            switch self {
            case .cancelled: "This flight is marked cancelled for the selected date. Check with the airline."
            case .invalidNumber: "Enter an airline code and flight number, such as BA219."
            case .unavailable: "Flight lookup is unavailable. Try again or enter the times manually."
            case .notFound: "No complete schedule was found for that flight and date. Check the date or enter the times manually."
            case .accessDenied: "The flight source couldn’t serve this request. You can enter the times manually."
            case .rateLimited: "Flight lookup is busy. Try again later or enter the times manually."
            }
        }
    }

    private struct ProviderFlight: Decodable {
        let number: String
        let status: String?
        let isCargo: Bool?
        let departure: Movement
        let arrival: Movement
    }
    private struct Movement: Decodable {
        let airport: Airport
        let scheduledTime: ScheduledTime?
    }
    private struct Airport: Decodable {
        let iata: String?
        let name: String
        let timeZone: String?
    }
    private struct ScheduledTime: Decodable {
        let utc: String
        var date: Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: utc) ?? ISO8601DateFormatter().date(from: utc)
        }
    }
}
