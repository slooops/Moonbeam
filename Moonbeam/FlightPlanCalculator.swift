import Foundation

extension JetLagPlan {
    var beforeFlightCount: Int { (nights.count + 1) / 2 }
    var transitionDayCount: Int { nights.count + (flight == nil ? 0 : 1) }

    /// A flight is one additional shift step, between the pre- and post-flight nights.
    func applyingFlights(_ flights: [FlightSchedule]) -> JetLagPlan {
        guard Self.itineraryError(flights) == nil,
              let flight = flights.first, let lastFlight = flights.last else { return self }
        var updated = self
        updated.flights = flights
        let before = beforeFlightCount
        let total = nights.count + 1
        var origin = Calendar(identifier: .gregorian)
        origin.timeZone = flight.departureTimeZone
        var destination = Calendar(identifier: .gregorian)
        destination.timeZone = lastFlight.arrivalTimeZone

        func window(forStep step: Int) -> JetLagSleepWindow {
            let delta = Int((Double(updated.tzShiftMinutes) * Double(step) / Double(total)).rounded())
            return JetLagSleepWindow(bedMinutes: idealBedMinutes - delta, wakeMinutes: idealWakeMinutes - delta)
        }
        func bedtime(on day: Date, minutes: Int, calendar: Calendar) -> Date {
            let offset = minutes < 720 ? minutes + 1440 : minutes
            return calendar.date(byAdding: .minute, value: offset, to: calendar.startOfDay(for: day))!
        }

        // Position the final pre-flight night wholly before boarding.
        let lastBeforeWindow = window(forStep: before)
        var lastBeforeDay = origin.startOfDay(for: flight.departure)
        while bedtime(on: lastBeforeDay, minutes: lastBeforeWindow.bedMinutes, calendar: origin)
            .addingTimeInterval(Double(lastBeforeWindow.durationMinutes) * 60) > flight.departure.addingTimeInterval(-3600) {
            lastBeforeDay = origin.date(byAdding: .day, value: -1, to: lastBeforeDay)!
        }

        // Position the first post-flight night after landing, using the destination clock.
        let firstAfterWindow = window(forStep: before + 2)
        let firstAfterBedMinutes = ((firstAfterWindow.bedMinutes + updated.tzShiftMinutes) % 1440 + 1440) % 1440
        var firstAfterDay = destination.startOfDay(for: lastFlight.arrival)
        if firstAfterBedMinutes < 720 {
            firstAfterDay = destination.date(byAdding: .day, value: -1, to: firstAfterDay)!
        }
        while bedtime(on: firstAfterDay, minutes: firstAfterBedMinutes, calendar: destination) < lastFlight.arrival.addingTimeInterval(3600) {
            firstAfterDay = destination.date(byAdding: .day, value: 1, to: firstAfterDay)!
        }

        updated.nights = nights.indices.map { index in
            let isBefore = index < before
            let sleepWindow = window(forStep: index + (isBefore ? 1 : 2))
            let calendar = isBefore ? origin : destination
            let day = calendar.date(byAdding: .day,
                value: isBefore ? index - before + 1 : index - before,
                to: isBefore ? lastBeforeDay : firstAfterDay)!
            let localBedMinutes = isBefore ? sleepWindow.bedMinutes
                : ((sleepWindow.bedMinutes + updated.tzShiftMinutes) % 1440 + 1440) % 1440
            var night = JetLagNightPlan(nightIndex: index, date: day, sleepWindow: sleepWindow)
            night.scheduledBedDate = bedtime(on: day, minutes: localBedMinutes, calendar: calendar)
            return night
        }
        return updated
    }

    func removingFlight() -> JetLagPlan {
        var updated = self
        updated.flights = nil
        return updated.withNightCount(nights.count)
    }

    static func itineraryError(_ flights: [FlightSchedule]) -> String? {
        guard (1...3).contains(flights.count), flights.allSatisfy(\.isValid) else {
            return "Add one to three flights with valid departure and arrival times."
        }
        for (previous, next) in zip(flights, flights.dropFirst()) {
            guard previous.arrivalAirport.uppercased() == next.departureAirport.uppercased() else {
                return "Connecting flights must depart from the previous arrival airport."
            }
            guard next.departure >= previous.arrival else {
                return "A connecting flight must depart after the previous flight arrives. Check the local dates and times."
            }
        }
        return nil
    }

    /// Intersect the itinerary's shift step with time aloft, allowing for takeoff/landing.
    /// Total sleep across all legs is capped at the usual sleep duration; layovers are excluded.
    func inFlightSleep(for flight: FlightSchedule) -> DateInterval? {
        guard let flights, flights.contains(where: { $0.id == flight.id }) else { return nil }
        let fraction = Double(beforeFlightCount + 1) / Double(transitionDayCount)
        let delta = Int((Double(tzShiftMinutes) * fraction).rounded())
        let window = JetLagSleepWindow(bedMinutes: idealBedMinutes - delta, wakeMinutes: idealWakeMinutes - delta)
        var remaining = Double(window.durationMinutes) * 60
        for leg in flights {
            guard let interval = sleepOverlap(for: leg, window: window) else { continue }
            let duration = min(interval.duration, remaining)
            remaining -= duration
            if leg.id == flight.id {
                return duration >= 3600 ? DateInterval(start: interval.start, duration: duration) : nil
            }
        }
        return nil
    }

    private func sleepOverlap(for flight: FlightSchedule, window: JetLagSleepWindow) -> DateInterval? {
        let cruiseStart = flight.departure.addingTimeInterval(3600)
        let cruiseEnd = flight.arrival.addingTimeInterval(-2700)
        guard cruiseEnd.timeIntervalSince(cruiseStart) >= 3600 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = self.flight?.departureTimeZone ?? flight.departureTimeZone
        let day = calendar.startOfDay(for: flight.departure)
        var best: DateInterval?
        for offset in -1...2 {
            let candidateDay = calendar.date(byAdding: .day, value: offset, to: day)!
            let start = calendar.date(byAdding: .minute, value: window.bedMinutes, to: candidateDay)!
            let end = start.addingTimeInterval(Double(window.durationMinutes) * 60)
            let overlapStart = max(start, cruiseStart)
            let overlapEnd = min(end, cruiseEnd)
            guard overlapEnd.timeIntervalSince(overlapStart) >= 3600 else { continue }
            let overlap = DateInterval(start: overlapStart, end: overlapEnd)
            if overlap.duration > (best?.duration ?? 0) { best = overlap }
        }
        return best
    }
}

struct JetLagAlarmEvent {
    let id: String
    let title: String
    let bedtime: Date
    let wakeTime: Date
}

extension JetLagPlan {
    var alarmEvents: [JetLagAlarmEvent] {
        var events = nights.map { night in
            JetLagAlarmEvent(id: "night.\(night.nightIndex)",
                title: "Night \(night.nightIndex + 1) · \(destinationCity)",
                bedtime: night.bedDate, wakeTime: night.wakeDate)
        }
        for (index, flight) in (flights ?? []).enumerated() {
            if let sleep = inFlightSleep(for: flight) {
                events.append(JetLagAlarmEvent(id: "flight.\(index)", title: "Flight \(flight.number)",
                    bedtime: sleep.start, wakeTime: sleep.end))
            }
        }
        return events.sorted { $0.bedtime < $1.bedtime }
    }
}
