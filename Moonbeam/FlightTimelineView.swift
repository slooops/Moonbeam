import SwiftUI

struct FlightTimelineView: View {
    let flight: FlightSchedule
    let sleep: DateInterval?

    static func durationLabel(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int(duration / 60))
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(flight.number, systemImage: "airplane")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(Self.durationLabel(flight.duration)) flight")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if flight.referenceDeparture != nil {
                Text("Usual times · confirm against your booking")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.04))
                    if let sleep {
                        let start = sleep.start.timeIntervalSince(flight.departure) / flight.duration
                        let fraction = sleep.duration / flight.duration
                        Capsule()
                            .fill(JetLagPlanView.sleepGradient(from: 0, to: 1))
                            .saturation(0.5)
                            .overlay {
                                Image(systemName: "moon.zzz.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                            }
                            .frame(width: max(1, geometry.size.width * fraction))
                            .offset(x: geometry.size.width * start)
                    }
                    Capsule()
                        .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    HStack {
                        Text(flight.formatted(flight.departure, in: flight.departureTimeZone))
                        Spacer()
                        Text(flight.formatted(flight.arrival, in: flight.arrivalTimeZone))
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .padding(.horizontal, 12)
                }
            }
            .frame(height: 38)
            .accessibilityLabel(sleep == nil ? "Flight: stay awake" : "Flight with highlighted sleep window")

            HStack(alignment: .top) {
                endpoint(airport: flight.departureAirport, date: flight.departure, timeZone: flight.departureTimeZone)
                Spacer()
                endpoint(airport: flight.arrivalAirport, date: flight.arrival, timeZone: flight.arrivalTimeZone)
                    .multilineTextAlignment(.trailing)
            }

            if let sleep {
                Text("Sleep \(flight.formatted(sleep.start, in: flight.arrivalTimeZone))–\(flight.formatted(sleep.end, in: flight.arrivalTimeZone)) · \(Self.durationLabel(sleep.duration)) · \(flight.arrivalAirport) time")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Stay awake on this leg; sleep during the next planned window.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func endpoint(airport: String, date: Date, timeZone: TimeZone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(airport) · \(flight.formatted(date, in: timeZone))")
                .font(.caption.weight(.medium))
            Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: timeZone)) + " · " + (timeZone.abbreviation(for: date) ?? timeZone.identifier))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}
