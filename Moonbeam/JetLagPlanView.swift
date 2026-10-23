//
//  JetLagPlanView.swift
//  Moonbeam
//

import SwiftUI

struct JetLagPlanView: View {
    @EnvironmentObject private var tripStore: JetLagTripStore
    @State private var plan: JetLagPlan
    @State private var showingSaveConfirmation = false
    @State private var saveError: String?
    @State private var alarmsSet = false
    @State private var alarmError: String?

    private let barHeight: CGFloat = 40   // gradient boxes, same as dial ringWidth
    private let sleepBarHeight: CGFloat = 30

    /// Airport timelines show two days; sleep rows show one noon-to-noon day.
    private static let axisStartMinute = 720
    private static let axisDurationMinutes = 2880

    private static let sleepAxisDurationMinutes = 1440

    private static func sleepAxisFraction(_ minutes: Int) -> CGFloat {
        CGFloat(((minutes - axisStartMinute) % 1440 + 1440) % 1440)
            / CGFloat(sleepAxisDurationMinutes)
    }

    init(plan: JetLagPlan) {
        _plan = State(initialValue: plan)
    }

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            ScrollView {
                VStack(spacing: 16) {
                    headerSection

                    airportSection

                    nightsSection

                    timezoneAndAlarmSection
                }
                .padding()
            }
        }
        .navigationTitle("Transition Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save Plan") {
                    do {
                        try tripStore.savePlan(plan)
                        showingSaveConfirmation = true
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
            }
        }
        .alert("Plan Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your plan is available under Saved Plans in Jet Lag.")
        }
        .alert("Unable to Save Plan", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(plan.nights.count)-Night Plan", systemImage: "bed.double.circle")
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())

                Spacer()

                nightStepper
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moonbeamCard()
    }

    private var nightStepper: some View {
        HStack(spacing: 14) {
            stepperButton(systemImage: "minus", enabled: plan.nights.count > 1) {
                setNightCount(plan.nights.count - 1)
            }
            stepperButton(systemImage: "plus", enabled: plan.nights.count < plan.maxNightCount) {
                setNightCount(plan.nights.count + 1)
            }
        }
    }

    private func stepperButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        .clipShape(Circle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func setNightCount(_ count: Int) {
        let clamped = max(1, min(plan.maxNightCount, count))
        guard clamped != plan.nights.count else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            plan = plan.withNightCount(clamped)
            alarmsSet = false
        }
    }

    // MARK: - Gradient Cards (origin / destination day-night cycle)

    private var airportSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(plan.originName, systemImage: "airplane.departure")
                .font(.subheadline.weight(.semibold))

            gradientBar(
                sunriseMinutes: plan.originSunriseMinutes,
                sunsetMinutes: plan.originSunsetMinutes
            )

            timeAxisLabels

            gradientBar(
                sunriseMinutes: plan.destSunriseLocalMinutes,
                sunsetMinutes: plan.destSunsetLocalMinutes
            )

            Label(plan.destinationCity, systemImage: "airplane.arrival")
                .font(.subheadline.weight(.semibold))
        }
        .moonbeamCard()
    }

    private func gradientBar(sunriseMinutes: Int, sunsetMinutes: Int) -> some View {
        RoundedRectangle(cornerRadius: barHeight / 2)
            .fill(Self.skyGradient(sunriseMinutes: sunriseMinutes, sunsetMinutes: sunsetMinutes))
            .saturation(0.5)
            .frame(height: barHeight)
    }

    private var airportTimeZoneLabel: String {
        if let flight = plan.flight {
            return flight.departureTimeZone.abbreviation(for: flight.departure) ?? "Origin time"
        }
        return "UTC\(plan.localOffsetHours >= 0 ? "+" : "−")\(abs(plan.localOffsetHours))"
    }

    private var timeAxisLabels: some View {
        HStack {
            Text("12PM")
            Spacer()
            Text("12AM")
            Spacer()
            Text(airportTimeZoneLabel)
                .foregroundStyle(.secondary)
            Spacer()
            Text("12AM")
            Spacer()
            Text("12PM")
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.35))
    }

    private var sleepTimeAxisLabels: some View {
        HStack {
            Text("12PM")
            Spacer()
            Text("6PM")
            Spacer()
            Text("12AM")
            Spacer()
            Text("6AM")
            Spacer()
            Text("12PM")
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.35))
    }

    // MARK: - Night Sleep Bars

    private var nightsSection: some View {
        let beforeCount = plan.beforeFlightCount
        let beforeFlight = Array(plan.nights.prefix(beforeCount))
        let afterFlight = Array(plan.nights.dropFirst(beforeCount))

        return VStack(alignment: .leading, spacing: 14) {
            if let flight = plan.flight {
                flightTimeZoneLabel(name: plan.originName, timeZone: flight.departureTimeZone, date: flight.departure)
            } else {
                timeZoneLabel(name: plan.originName, offsetHours: plan.localOffsetHours)
            }

            Text("Before flight · \(beforeFlight.count) night\(beforeFlight.count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
            ForEach(beforeFlight) { night in
                nightRow(night: night)
            }
            sleepTimeAxisLabels

            if let itinerary = plan.flights, !itinerary.isEmpty {
                VStack(spacing: 12) {
                    ForEach(Array(itinerary.enumerated()), id: \.element.id) { index, flight in
                        if index > 0 {
                            Text("Connection at \(flight.departureAirport) · \(FlightTimelineView.durationLabel(flight.departure.timeIntervalSince(itinerary[index - 1].arrival)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        FlightTimelineView(flight: flight, sleep: plan.inFlightSleep(for: flight))
                    }
                }
            } else {
                HStack(spacing: 10) {
                    dashedFlightLine
                    Label("Flight", systemImage: "airplane")
                        .font(.caption.weight(.medium))
                        .fixedSize()
                    dashedFlightLine
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }

            Text("After flight · \(afterFlight.count) night\(afterFlight.count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
            ForEach(afterFlight) { night in
                nightRow(night: night, clockOffsetMinutes: plan.tzShiftMinutes)
            }
            if !afterFlight.isEmpty {
                sleepTimeAxisLabels
            }

            if let flight = plan.flight {
                flightTimeZoneLabel(name: plan.destinationCity, timeZone: (plan.flights?.last ?? flight).arrivalTimeZone, date: (plan.flights?.last ?? flight).arrival)
            } else {
                timeZoneLabel(name: plan.destinationCity, offsetHours: plan.destinationOffsetHours)
            }
        }
        .moonbeamCard()
    }

    private var dashedFlightLine: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .frame(height: 1)
    }

    private func flightTimeZoneLabel(name: String, timeZone: TimeZone, date: Date) -> some View {
        Text("\(name) · \(timeZone.abbreviation(for: date) ?? timeZone.identifier)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func timeZoneLabel(name: String, offsetHours: Int) -> some View {
        Text("\(name) · UTC\(offsetHours >= 0 ? "+" : "−")\(abs(offsetHours))")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func nightRow(night: JetLagNightPlan, clockOffsetMinutes: Int = 0) -> some View {
        let window = JetLagSleepWindow(
            bedMinutes: night.sleepWindow.bedMinutes + clockOffsetMinutes,
            wakeMinutes: night.sleepWindow.wakeMinutes + clockOffsetMinutes
        )

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Night \(night.nightIndex + 1)")
                    .font(.caption.weight(.semibold))
                Text(nightDateLabel(night))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.05))

                    sleepSegments(window: window, width: width)
                }
            }
            .frame(height: sleepBarHeight)
        }
    }

    private func nightDateLabel(_ night: JetLagNightPlan) -> String {
        let formatter = DateFormatter()
        if let flight = plan.flight {
            formatter.timeZone = night.nightIndex < plan.beforeFlightCount
                ? flight.departureTimeZone : (plan.flights?.last ?? flight).arrivalTimeZone
        }
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: night.date)
    }

    @ViewBuilder
    private func sleepSegments(window: JetLagSleepWindow, width: CGFloat) -> some View {
        let bedFrac = Self.sleepAxisFraction(window.bedMinutes)
        let wakeFrac = bedFrac + CGFloat(window.durationMinutes) / CGFloat(Self.sleepAxisDurationMinutes)
        let bedTime = SleepCalculator.formattedTime(minutesSinceMidnight: window.bedMinutes)
        let wakeTime = SleepCalculator.formattedTime(minutesSinceMidnight: window.wakeMinutes)

        if wakeFrac > 1 {
            let split = Double((1 - bedFrac) / (wakeFrac - bedFrac))
            sleepSegment(
                startFrac: bedFrac, endFrac: 1, width: width,
                gradient: Self.sleepGradient(from: 0, to: split)
            ) {
                HStack {
                    sleepChip(icon: "bed.double.fill", time: bedTime)
                    Spacer(minLength: 0)
                }
            }
            sleepSegment(
                startFrac: 0, endFrac: wakeFrac - 1, width: width,
                gradient: Self.sleepGradient(from: split, to: 1)
            ) {
                HStack {
                    Spacer(minLength: 0)
                    sleepChip(icon: "alarm.fill", time: wakeTime)
                }
            }
        } else {
            sleepSegment(
                startFrac: bedFrac, endFrac: wakeFrac, width: width,
                gradient: Self.sleepGradient(from: 0, to: 1)
            ) {
                HStack {
                    sleepChip(icon: "bed.double.fill", time: bedTime)
                    Spacer(minLength: 2)
                    sleepChip(icon: "alarm.fill", time: wakeTime)
                }
            }
        }
    }

    private func sleepChip(icon: String, time: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(time)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(.white)
    }

    private func sleepSegment<Content: View>(
        startFrac: CGFloat,
        endFrac: CGFloat,
        width: CGFloat,
        gradient: LinearGradient,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let segWidth = max(0, (endFrac - startFrac) * width)
        let offset = startFrac * width

        return Capsule()
            .fill(gradient)
            .overlay(
                // One scrim across the whole gradient keeps the capsule's own
                // rounding and gives the labels consistent contrast.
                Capsule()
                    .fill(Color("DeepSpace").opacity(0.38))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .overlay(
                content()
                    .padding(.horizontal, 9)
            )
            .frame(width: segWidth, height: sleepBarHeight)
            .offset(x: offset)
    }

    // MARK: - Timezone & Alarm

    private var timezoneAndAlarmSection: some View {
        let shiftHours = Double(abs(plan.tzShiftMinutes)) / 60.0
        let direction = plan.tzShiftMinutes > 0 ? "earlier" : "later"
        let shiftText = shiftHours == shiftHours.rounded()
            ? String(format: "%.0f", shiftHours)
            : String(format: "%.1f", shiftHours)

        return VStack(alignment: .leading, spacing: 14) {
            Label("Timezone Shift", systemImage: "globe")
                .font(.subheadline.weight(.semibold))
            Text("To match \(plan.destinationCity), your sleep shifts \(shiftText) hour\(shiftHours == 1 ? "" : "s") \(direction) across \(plan.nights.count) night\(plan.nights.count == 1 ? "" : "s").")
                .font(.caption)
                .foregroundStyle(.secondary)

            if plan.flight != nil {
                Text("The itinerary adds one transition day: \(plan.nights.count) nights + travel = \(plan.transitionDayCount) days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.3)

            if alarmsSet {
                Label(plan.flight == nil ? "Alarms set for all \(plan.nights.count) nights" : "Plan alarms set, including in-flight sleep", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Text("Wake-up alarms sound even in Silent mode. Bedtime reminders arrive as notifications. Manage or delete individual alarms in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    AlarmService.shared.cancelMoonbeamAlarms()
                    withAnimation { alarmsSet = false }
                } label: {
                    Label("Turn Off Alarms", systemImage: "bell.slash.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
            } else {
                Button {
                    Task {
                        let result = await AlarmService.shared.scheduleJetLagPlanAlarms(plan: plan)
                        withAnimation {
                            switch result {
                            case .success:
                                alarmsSet = true
                                alarmError = nil
                            case .failure(let error):
                                alarmError = error.localizedDescription
                            }
                        }
                    }
                } label: {
                    Label(plan.flight == nil ? "Set Alarms for All \(plan.nights.count) Nights" : "Set Plan Alarms", systemImage: "alarm.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)

                if let alarmError {
                    Text(alarmError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moonbeamCard()
    }

    // MARK: - Sky Gradient

    private typealias RGB = (r: Double, g: Double, b: Double)

    /// The night arc of the sky palette — dusk through night to dawn, with the
    /// white daylight removed. Bedtime sits at the gold/orange end, wake-up at
    /// the last blue before the sky turns white.
    private static let sleepArcKeys: [(Double, RGB)] = [
        (0.00, (0.92, 0.66, 0.45)),  // orange
        (0.09, (0.90, 0.38, 0.35)),  // sunset red
        (0.16, (0.60, 0.20, 0.42)),  // magenta
        (0.26, (0.25, 0.10, 0.32)),  // deep purple
        (0.42, (0.06, 0.04, 0.18)),  // night
        (0.62, (0.06, 0.04, 0.18)),  // night
        (0.80, (0.10, 0.11, 0.34)),
        (0.93, (0.15, 0.25, 0.50)),  // twilight blue
        (1.00, (0.45, 0.65, 0.85)),  // sunrise blue
    ]

    /// A slice of the night arc, for sleep windows split across the bar edge.
    static func sleepGradient(from f0: Double, to f1: Double) -> LinearGradient {
        let sampleCount = 24
        let stops = (0...sampleCount).map { i -> Gradient.Stop in
            let frac = Double(i) / Double(sampleCount)
            let rgb = rampColor(sleepArcKeys, f0 + (f1 - f0) * frac)
            return Gradient.Stop(
                color: Color(red: rgb.r, green: rgb.g, blue: rgb.b),
                location: frac
            )
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private static func rampColor(_ keys: [(Double, RGB)], _ x: Double) -> RGB {
        if x <= keys.first!.0 { return keys.first!.1 }
        if x >= keys.last!.0 { return keys.last!.1 }
        for i in 1..<keys.count where x <= keys[i].0 {
            let (x0, a) = keys[i - 1]
            let (x1, b) = keys[i]
            let s = (x - x0) / (x1 - x0)
            let e = s * s * (3 - 2 * s)  // smoothstep
            return (a.r + (b.r - a.r) * e, a.g + (b.g - a.g) * e, a.b + (b.b - a.b) * e)
        }
        return keys.last!.1
    }

    /// Builds a 48-hour day/night gradient for arbitrary sunrise/sunset times,
    /// including daylight spans that wrap past the bar edges (e.g. a far-shifted
    /// destination drawn on the origin's clock, or the noon-centered axis).
    /// Sampled rather than hand-placed stops so no clamping is needed. The
    /// twilight palette mirrors the home-screen dial: long gold/amber approach
    /// to sunset, red at the horizon, purple after, deep blue before dawn.
    static func skyGradient(sunriseMinutes: Int, sunsetMinutes: Int) -> LinearGradient {
        let day: RGB = (0.84, 0.81, 0.69)
        let night: RGB = (0.09, 0.07, 0.24)

        // Blend sunrise blue directly into daytime cream without a white band.
        let morning: [(Double, RGB)] = [
            (0, (0.56, 0.74, 0.95)),     // sunrise blue at the horizon
            (210, day),
        ]
        // Minutes until sunset → color, the long warm slide into golden hour.
        let afternoon: [(Double, RGB)] = [
            (0, (0.94, 0.42, 0.40)),     // sun on the horizon
            (35, (0.98, 0.80, 0.52)),    // warm gold
            (95, day),
            (190, day),
            (300, day),
        ]
        // Minutes after sunset → color, through the purples into night.
        let dusk: [(Double, RGB)] = [
            (0, (0.94, 0.42, 0.40)),
            (30, (0.72, 0.26, 0.50)),    // magenta
            (70, (0.40, 0.15, 0.42)),    // deep purple
            (150, night),
        ]
        // Minutes until sunrise → color, night brightening toward dawn.
        let preDawn: [(Double, RGB)] = [
            (0, (0.56, 0.74, 0.95)),     // sunrise blue at the horizon
            (35, (0.18, 0.26, 0.56)),
            (110, night),
        ]

        let sunrise = Double(((sunriseMinutes % 1440) + 1440) % 1440)
        let sunset = Double(((sunsetMinutes % 1440) + 1440) % 1440)
        var daySpan = sunset - sunrise
        if daySpan <= 0 { daySpan += 1440 }

        func color(atMinute m: Double) -> Color {
            var posInDay = (m - sunrise).truncatingRemainder(dividingBy: 1440)
            if posInDay < 0 { posInDay += 1440 }

            let rgb: RGB
            if posInDay < daySpan {
                let fromDawn = posInDay
                let toDusk = daySpan - posInDay
                rgb = fromDawn <= toDusk ? rampColor(morning, fromDawn) : rampColor(afternoon, toDusk)
            } else {
                let fromDusk = posInDay - daySpan
                let toDawn = 1440 - posInDay
                rgb = fromDusk <= toDawn ? rampColor(dusk, fromDusk) : rampColor(preDawn, toDawn)
            }
            return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        }

        let sampleCount = Self.axisDurationMinutes / 10  // 10-minute steps keep the horizon edges crisp
        let stops = (0...sampleCount).map { i -> Gradient.Stop in
            let frac = Double(i) / Double(sampleCount)
            let minute = (Double(Self.axisStartMinute) + frac * Double(Self.axisDurationMinutes)).truncatingRemainder(dividingBy: 1440)
            return Gradient.Stop(color: color(atMinute: minute), location: frac)
        }

        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}

#Preview {
    let plan = JetLagPlanCalculator.generatePlan(
        originName: "San Francisco",
        destinationCity: "Tokyo",
        nightCount: 3,
        originSunrise: 5 * 60 + 48,
        originSunset: 20 * 60 + 33,
        destSunrise: 4 * 60 + 25,
        destSunset: 19 * 60 + 0,
        localOffsetHours: -7,
        destOffsetHours: 9
    )

    NavigationStack {
        JetLagPlanView(plan: plan)
    }
    .environmentObject(JetLagTripStore())
}
