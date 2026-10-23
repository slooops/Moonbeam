import Foundation
import Testing
@testable import Moonbeam

struct FlightPlanTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func makePlan() -> JetLagPlan {
        JetLagPlanCalculator.generatePlan(originName: "San Francisco", destinationCity: "London",
            nightCount: 3, originSunrise: 420, originSunset: 1080,
            destSunrise: 420, destSunset: 1020, localOffsetHours: -8, destOffsetHours: 0)
    }

    private func flight(number: String = "BA286", from: String = "SFO", to: String = "LHR",
                        departure: String = "2026-11-10T22:00:00Z", arrival: String = "2026-11-11T08:00:00Z",
                        originZone: String = "America/Los_Angeles", destinationZone: String = "Europe/London") -> FlightSchedule {
        FlightSchedule(number: number, departureAirport: from, arrivalAirport: to,
            departure: date(departure), arrival: date(arrival),
            departureTimeZoneID: originZone, arrivalTimeZoneID: destinationZone, source: "Manual")
    }

    @Test @MainActor func deletingASavedPlanPersistsAndKeepsOtherPlans() throws {
        let suite = "MoonbeamTests.deletePlan.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = JetLagTripStore(defaults: defaults)
        let first = makePlan()
        let second = makePlan()
        try store.savePlan(first)
        try store.savePlan(second)
        #expect(store.savedPlans.count == 2)
        try store.deletePlan(first)
        #expect(store.savedPlans.map(\.createdAt) == [second.createdAt])
        let reopened = JetLagTripStore(defaults: defaults)
        #expect(reopened.savedPlans.map(\.createdAt) == [second.createdAt])
        try reopened.deletePlan(second)
        #expect(JetLagTripStore(defaults: defaults).savedPlans.isEmpty)
    }

    @Test func flightAddsAShiftDayAndAnchorsNightsToTravelDates() throws {
        let flight = flight()
        let plan = makePlan().applyingFlights([flight])
        #expect(plan.transitionDayCount == 4)
        #expect(plan.nights.count == 3)
        #expect(plan.beforeFlightCount == 2)
        #expect(plan.nights[0].sleepWindow.bedMinutes == 22 * 60 + 30 - 120)
        #expect(plan.nights[1].sleepWindow.bedMinutes == 22 * 60 + 30 - 240)
        #expect(plan.nights[1].wakeDate <= flight.departure.addingTimeInterval(-3600))
        #expect(plan.nights[2].bedDate >= flight.arrival.addingTimeInterval(3600))
        #expect((plan.nights[2].sleepWindow.bedMinutes + plan.tzShiftMinutes) % 1440 == plan.idealBedMinutes)
        let sleep = try #require(plan.inFlightSleep(for: flight))
        #expect(sleep.start >= flight.departure.addingTimeInterval(3600))
        #expect(sleep.end <= flight.arrival.addingTimeInterval(-2700))
        #expect(sleep.duration >= 3600)
        let event = try #require(plan.alarmEvents.first { $0.id == "flight.0" })
        #expect(event.bedtime == sleep.start)
        #expect(event.wakeTime == sleep.end)
    }

    @Test func nightCountChangesPreserveItineraryAndSavedPlanIdentity() {
        let original = makePlan().applyingFlights([flight()])
        let resized = original.withNightCount(5)
        #expect(resized.createdAt == original.createdAt)
        #expect(resized.flights == original.flights)
        #expect(resized.transitionDayCount == 6)
        #expect(resized.beforeFlightCount == 3)
        #expect(resized.nights[2].wakeDate <= resized.flight!.departure)
        #expect(resized.nights[3].bedDate >= resized.flights!.last!.arrival)
    }

    @Test func shortDaytimeFlightDoesNotInventSleep() {
        let short = flight(departure: "2026-11-10T18:00:00Z", arrival: "2026-11-10T19:00:00Z")
        let plan = makePlan().applyingFlights([short])
        #expect(plan.inFlightSleep(for: short) == nil)
        #expect(plan.alarmEvents.count == 3)
        #expect(plan.transitionDayCount == 4)
    }

    @Test func connectionValidationRejectsGapsAndReverseTimes() {
        let first = flight()
        let second = flight(number: "BA812", from: "LHR", to: "CPH",
            departure: "2026-11-11T10:00:00Z", arrival: "2026-11-11T12:00:00Z",
            originZone: "Europe/London", destinationZone: "Europe/Copenhagen")
        #expect(JetLagPlan.itineraryError([first, second]) == nil)
        let wrongAirport = flight(number: "BA812", from: "CDG", to: "CPH",
            departure: "2026-11-11T10:00:00Z", arrival: "2026-11-11T12:00:00Z")
        #expect(JetLagPlan.itineraryError([first, wrongAirport]) != nil)
        #expect(JetLagPlan.itineraryError([second, first]) != nil)
        #expect(JetLagPlan.itineraryError([first, second, second, second]) != nil)
    }

    @Test func threeLegJourneyUsesFinalDestinationAndExcludesLayoversFromSleep() {
        let legs = [
            flight(),
            flight(number: "BA812", from: "LHR", to: "CPH",
                departure: "2026-11-11T10:00:00Z", arrival: "2026-11-11T12:00:00Z",
                originZone: "Europe/London", destinationZone: "Europe/Copenhagen"),
            flight(number: "SK120", from: "CPH", to: "ARN",
                departure: "2026-11-11T14:00:00Z", arrival: "2026-11-11T15:00:00Z",
                originZone: "Europe/Copenhagen", destinationZone: "Europe/Stockholm")
        ]
        #expect(JetLagPlan.itineraryError(legs) == nil)
        let plan = makePlan().applyingFlights(legs)
        #expect(plan.tzShiftMinutes == 9 * 60)
        #expect(plan.transitionDayCount == 4)
        #expect(plan.nights.last!.bedDate > legs.last!.arrival)
        var totalSleep: TimeInterval = 0
        for leg in legs {
            if let sleep = plan.inFlightSleep(for: leg) {
                totalSleep += sleep.duration
                #expect(sleep.start >= leg.departure.addingTimeInterval(3600))
                #expect(sleep.end <= leg.arrival.addingTimeInterval(-2700))
            }
        }
        #expect(totalSleep <= 8.5 * 3600)
    }

    @Test func itineraryUsesFlightDateOffsetsAndSurvivesPersistence() throws {
        let leg = flight(from: "JFK", to: "DEL", departure: "2026-11-10T22:00:00Z",
            arrival: "2026-11-11T12:00:00Z", originZone: "America/New_York", destinationZone: "Asia/Kolkata")
        let plan = makePlan().applyingFlights([leg])
        #expect(plan.tzShiftMinutes == 630)
        let decoded = try JSONDecoder().decode(JetLagPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded.flights == plan.flights)
        #expect(decoded.nights.map(\.bedDate) == plan.nights.map(\.bedDate))
        #expect(decoded.nights.map(\.wakeDate) == plan.nights.map(\.wakeDate))
    }

    @Test func oldSavedPlansDecodeWithoutFlightFields() throws {
        let plan = makePlan()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        object.removeValue(forKey: "flights")
        var nights = try #require(object["nights"] as? [[String: Any]])
        for index in nights.indices { nights[index].removeValue(forKey: "scheduledBedDate") }
        object["nights"] = nights
        let decoded = try JSONDecoder().decode(JetLagPlan.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.flights == nil)
        #expect(decoded.nights.count == 3)
        #expect(decoded.transitionDayCount == 3)
    }

    @Test func scheduleDecoderUsesScheduledTimesAndSkipsIncompleteOrCancelledFlights() throws {
        let valid = FlightLookupFixture.json
        let array = try #require(JSONSerialization.jsonObject(with: Data(valid.utf8)) as? [[String: Any]])
        var cancelled = array[0]
        cancelled["status"] = "Canceled"
        var incomplete = array[0]
        var arrival = try #require(incomplete["arrival"] as? [String: Any])
        arrival.removeValue(forKey: "scheduledTime")
        incomplete["arrival"] = arrival
        let data = try JSONSerialization.data(withJSONObject: [array[0], cancelled, incomplete, array[0]])
        let schedules = try FlightScheduleService.decode(data)
        #expect(schedules.count == 1)
        #expect(schedules.first?.departure == date("2026-11-10T22:00:00Z"))
        #expect(schedules.first?.arrival == date("2026-11-11T08:00:00Z"))
    }

    @Test func lookupNormalizesNumberAndSendsSpecificDateToProxy() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlightLookupProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = FlightScheduleService(session: session,
            proxyURL: URL(string: "https://flight-test.moonbeam.example/schedule")!, developmentAPIKey: "")
        let schedules = try await service.lookup(number: " ba 286 ", date: date("2026-11-10T12:00:00Z"), timeZone: .gmt)
        #expect(schedules.count == 1)
    }

    @Test func invalidFlightNumbersFailBeforeAnyNetworkRequest() async {
        let service = FlightScheduleService(developmentAPIKey: "")
        do {
            _ = try await service.lookup(number: "../../flight", date: Date(), timeZone: .gmt)
            Issue.record("Invalid input should fail")
        } catch {
            #expect(error as? FlightScheduleService.LookupError == .invalidNumber)
        }
    }

    @Test func freeLookupUsesTheSelectedDateWithoutCredentials() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlightLookupProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = FlightScheduleService(session: session, developmentAPIKey: "")
        let schedules = try await service.lookup(number: "ba 219", date: date("2026-10-25T12:00:00Z"), timeZone: .gmt)
        #expect(schedules.first?.source == "FlightStats")
        #expect(schedules.first?.departureAirport == "LHR")
        #expect(schedules.first?.arrivalAirport == "DEN")
        #expect(schedules.first?.departure == date("2026-10-25T12:10:00Z"))
        #expect(schedules.first?.arrival == date("2026-10-25T22:10:00Z"))
    }

    @Test func freePageRejectsWrongDateAndNeverTreatsMissingDataAsASchedule() throws {
        #expect(throws: Error.self) {
            try PublicFlightSchedule.decode(PublicPageFixture.html, number: "BA219", departureDay: "2026-10-24")
        }
        #expect(throws: Error.self) {
            try PublicFlightSchedule.decode("<html>Access unavailable</html>", number: "BA219", departureDay: "2026-10-25")
        }
        #expect(throws: Error.self) {
            try PublicFlightSchedule.decode(PublicPageFixture.html, number: "BA218", departureDay: "2026-10-25")
        }
        let modernScript = "<script id=\"__NEXT_DATA__\" type=\"application/json\">" + PublicPageFixture.json + "</script>"
        #expect(try PublicFlightSchedule.decode(modernScript, number: "BA219", departureDay: "2026-10-25").count == 1)
    }

    @Test func unavailableFutureDateOffersExplicitEstimatedTimes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlightLookupProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = FlightScheduleService(session: session, developmentAPIKey: "",
            referenceDate: date("2026-10-25T12:00:00Z"))
        let schedules = try await service.lookup(number: "BA219", date: date("2026-10-28T12:00:00Z"), timeZone: .gmt)
        let schedule = try #require(schedules.first)
        #expect(schedule.referenceDeparture == date("2026-10-25T12:10:00Z"))
        #expect(schedule.departure == date("2026-10-28T12:10:00Z"))
        #expect(schedule.arrival == date("2026-10-28T22:10:00Z"))
        let decoded = try JSONDecoder().decode(FlightSchedule.self, from: JSONEncoder().encode(schedule))
        #expect(decoded.referenceDeparture == schedule.referenceDeparture)
    }

    @Test func estimatedTimesPreserveLocalClocksAcrossDSTAndOvernightArrival() throws {
        let recent = flight(number: "BA219", from: "LHR", to: "DEN",
            departure: "2026-10-23T12:35:00Z", arrival: "2026-10-23T22:25:00Z",
            originZone: "Europe/London", destinationZone: "America/Denver")
        let estimate = try PublicFlightSchedule.estimatedSchedule(from: recent, departureDay: "2026-10-28")
        #expect(estimate.departure == date("2026-10-28T13:35:00Z"))
        #expect(estimate.arrival == date("2026-10-28T22:25:00Z"))
        #expect(estimate.referenceDeparture == recent.departure)
        let overnight = try PublicFlightSchedule.estimatedSchedule(from: flight(), departureDay: "2026-12-31")
        #expect(overnight.departure == date("2026-12-31T22:00:00Z"))
        #expect(overnight.arrival == date("2027-01-01T08:00:00Z"))
    }

    @Test func cancelledFlightIsNotReplacedByUsualTimes() {
        let html = PublicPageFixture.html.replacingOccurrences(of: "\"canceled\":false", with: "\"canceled\":true")
        do {
            _ = try PublicFlightSchedule.decode(html, number: "BA219", departureDay: "2026-10-25")
            Issue.record("A cancellation should not be treated as an unknown future schedule")
        } catch {
            #expect(error as? FlightScheduleService.LookupError == .cancelled)
        }
    }

    @Test func freeLookupSeparatesAirlineCodeFromFlightNumber() throws {
        #expect(try PublicFlightSchedule.url(number: "BA219", date: "2026-10-25").path.hasSuffix("/BA/219"))
        #expect(try PublicFlightSchedule.url(number: "SAS935", date: "2026-10-25").path.hasSuffix("/SAS/935"))
        #expect(try PublicFlightSchedule.url(number: "6E6025", date: "2026-10-25").path.hasSuffix("/6E/6025"))
    }

}

private enum FlightLookupFixture {
    static let json = """
    [{"number":"BA286","status":"Expected","departure":{"airport":{"iata":"SFO","name":"San Francisco","timeZone":"America/Los_Angeles"},"scheduledTime":{"utc":"2026-11-10T22:00:00Z","local":"2026-11-10T14:00:00-08:00"},"revisedTime":{"utc":"2026-11-10T23:00:00Z"}},"arrival":{"airport":{"iata":"LHR","name":"London Heathrow","timeZone":"Europe/London"},"scheduledTime":{"utc":"2026-11-11T08:00:00Z","local":"2026-11-11T08:00:00+00:00"}}}]
    """
}

private final class FlightLookupProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let isPublic = url.host == "www.flightstats.com"
        let valid: Bool
        if isPublic {
            valid = url.path.hasSuffix("/BA/219")
                && query.contains(URLQueryItem(name: "year", value: "2026"))
                && query.contains(URLQueryItem(name: "month", value: "10"))
                && query.contains(URLQueryItem(name: "date", value: "25"))
        } else {
            valid = query.contains(URLQueryItem(name: "flight", value: "BA286"))
                && query.contains(URLQueryItem(name: "date", value: "2026-11-10"))
        }
        let response = HTTPURLResponse(url: url, statusCode: valid ? 200 : (isPublic ? 404 : 400), httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((isPublic ? PublicPageFixture.html : FlightLookupFixture.json).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private enum PublicPageFixture {
    // Minimal shape of a publicly returned schedule, including a daylight-saving boundary.
    static let json = #"{"props":{"initialState":{"flightTracker":{"flight":{"flightNote":{"canceled":false},"ticketHeader":{"carrier":{"fs":"BA"},"flightNumber":"219"},"schedule":{"scheduledDepartureUTC":"2026-10-25T12:10:00.000Z","scheduledArrivalUTC":"2026-10-25T22:10:00.000Z"},"departureAirport":{"fs":"LHR","iata":"LHR","timeZoneRegionName":"Europe/London"},"arrivalAirport":{"fs":"DEN","iata":"DEN","timeZoneRegionName":"America/Denver"}}}}}}"#
    static let html = "<html><script>__NEXT_DATA__ = " + json + ";</script></html>"
}
