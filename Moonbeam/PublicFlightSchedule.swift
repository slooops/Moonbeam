import Foundation

/// Best-effort, no-key lookup from the public FlightStats page. This parses embedded JSON
/// as data only; it never executes page scripts or works around access restrictions.
enum PublicFlightSchedule {
    static func url(number: String, date: String) throws -> URL {
        let expression = try NSRegularExpression(pattern: "^([A-Z]{3}|[A-Z0-9]{2})([0-9]{1,4}[A-Z]?)$")
        let range = NSRange(number.startIndex..., in: number)
        guard let match = expression.firstMatch(in: number, range: range),
              let airlineRange = Range(match.range(at: 1), in: number),
              let flightRange = Range(match.range(at: 2), in: number),
              number[airlineRange].contains(where: \.isLetter) else {
            throw FlightScheduleService.LookupError.invalidNumber
        }
        let components = date.split(separator: "-")
        guard components.count == 3 else { throw FlightScheduleService.LookupError.invalidNumber }
        var url = URLComponents(string: "https://www.flightstats.com/v2/flight-tracker/\(number[airlineRange])/\(number[flightRange])")!
        url.queryItems = [URLQueryItem(name: "year", value: String(components[0])),
                         URLQueryItem(name: "month", value: String(components[1])),
                         URLQueryItem(name: "date", value: String(components[2]))]
        return url.url!
    }

    static func decode(_ html: String, number: String, departureDay: String) throws -> [FlightSchedule] {
        let data = try embeddedJSON(in: html)
        let page = try JSONDecoder().decode(Page.self, from: data)
        if page.props.initialState.flightTracker.flight?.flightNote?.canceled == true {
            throw FlightScheduleService.LookupError.cancelled
        }
        guard let flight = page.props.initialState.flightTracker.flight,
              let departureAirport = flight.departureAirport,
              let arrivalAirport = flight.arrivalAirport,
              let departureUTC = flight.schedule?.scheduledDepartureUTC,
              let arrivalUTC = flight.schedule?.scheduledArrivalUTC,
              let departure = parseDate(departureUTC), let arrival = parseDate(arrivalUTC),
              let header = flight.ticketHeader,
              FlightScheduleService.normalizedNumber(header.carrier.fs + header.flightNumber) == number else {
            throw FlightScheduleService.LookupError.notFound
        }
        let schedule = FlightSchedule(number: number,
            departureAirport: departureAirport.iata ?? departureAirport.fs,
            arrivalAirport: arrivalAirport.iata ?? arrivalAirport.fs,
            departure: departure, arrival: arrival,
            departureTimeZoneID: departureAirport.timeZoneRegionName,
            arrivalTimeZoneID: arrivalAirport.timeZoneRegionName, source: "FlightStats")
        guard schedule.isValid else { throw FlightScheduleService.LookupError.notFound }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = schedule.departureTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        // Public pages can silently return today's flight for an unavailable date.
        guard formatter.string(from: departure) == departureDay else {
            throw FlightScheduleService.LookupError.notFound
        }
        return [schedule]
    }

    /// Reuse local clock times, accounting for different DST offsets on the chosen date.
    /// Keep the original date so the UI cannot mistake this for a confirmed schedule.
    static func estimatedSchedule(from recent: FlightSchedule, departureDay: String) throws -> FlightSchedule {
        var origin = Calendar(identifier: .gregorian)
        origin.timeZone = recent.departureTimeZone
        var destination = Calendar(identifier: .gregorian)
        destination.timeZone = recent.arrivalTimeZone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let formatter = DateFormatter()
        formatter.calendar = utc
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        guard let target = formatter.date(from: departureDay) else {
            throw FlightScheduleService.LookupError.notFound
        }
        let originDay = utc.date(from: origin.dateComponents([.year, .month, .day], from: recent.departure))!
        let destinationDay = utc.date(from: destination.dateComponents([.year, .month, .day], from: recent.arrival))!
        let arrivalDayOffset = utc.dateComponents([.day], from: originDay, to: destinationDay).day!
        let targetArrivalDay = utc.date(byAdding: .day, value: arrivalDayOffset, to: target)!
        func localDate(day: Date, clock: Date, calendar: Calendar) -> Date? {
            var components = utc.dateComponents([.year, .month, .day], from: day)
            components.hour = calendar.component(.hour, from: clock)
            components.minute = calendar.component(.minute, from: clock)
            guard let result = calendar.date(from: components),
                  calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result) == components else { return nil }
            return result
        }
        guard let departure = localDate(day: target, clock: recent.departure, calendar: origin),
              let arrival = localDate(day: targetArrivalDay, clock: recent.arrival, calendar: destination) else {
            throw FlightScheduleService.LookupError.notFound
        }
        var estimate = FlightSchedule(number: recent.number,
            departureAirport: recent.departureAirport, arrivalAirport: recent.arrivalAirport,
            departure: departure, arrival: arrival,
            departureTimeZoneID: recent.departureTimeZoneID, arrivalTimeZoneID: recent.arrivalTimeZoneID,
            source: recent.source)
        estimate.referenceDeparture = recent.departure
        guard estimate.isValid else { throw FlightScheduleService.LookupError.notFound }
        return estimate
    }

    static func embeddedJSON(in html: String) throws -> Data {
        let patterns = [
            #"\b__NEXT_DATA__\s*=\s*"#,
            #"<script\b[^>]*\bid\s*=\s*["']__NEXT_DATA__["'][^>]*>\s*"#
        ]
        var start: String.Index?
        for pattern in patterns {
            if let marker = html.range(of: pattern, options: .regularExpression) {
                start = marker.upperBound
                break
            }
        }
        guard var index = start, index < html.endIndex, html[index] == "{" else {
            throw FlightScheduleService.LookupError.unavailable
        }
        let first = index
        var depth = 0
        var inString = false
        var escaped = false
        while index < html.endIndex {
            let character = html[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else {
                if character == "\"" { inString = true }
                else if character == "{" { depth += 1 }
                else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return Data(html[first...index].utf8)
                    }
                }
            }
            index = html.index(after: index)
        }
        throw FlightScheduleService.LookupError.unavailable
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private struct Page: Decodable { let props: Props }
    private struct Props: Decodable { let initialState: State }
    private struct State: Decodable { let flightTracker: Tracker }
    private struct Tracker: Decodable { let flight: Flight? }
    private struct Flight: Decodable {
        let flightNote: Note?
        let schedule: Schedule?
        let departureAirport: Airport?
        let arrivalAirport: Airport?
        let ticketHeader: Header?
    }
    private struct Note: Decodable { let canceled: Bool? }
    private struct Schedule: Decodable {
        let scheduledDepartureUTC: String?
        let scheduledArrivalUTC: String?
    }
    private struct Airport: Decodable {
        let fs: String
        let iata: String?
        let timeZoneRegionName: String
    }
    private struct Header: Decodable {
        let carrier: Carrier
        let flightNumber: String
    }
    private struct Carrier: Decodable { let fs: String }
}
