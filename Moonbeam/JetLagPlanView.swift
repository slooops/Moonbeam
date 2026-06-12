//
//  JetLagPlanView.swift
//  Moonbeam
//

import SwiftUI

struct JetLagPlanView: View {
    @State private var plan: JetLagPlan
    @State private var alarmsSet = false
    @State private var alarmError: String?

    private let barHeight: CGFloat = 40   // gradient boxes, same as dial ringWidth
    private let sleepBarHeight: CGFloat = 30

    /// All bars run noon → noon instead of midnight → midnight, so sleep
    /// windows (which cluster around night) stay inside their bar instead of
    /// wrapping at the edges.
    private static let axisStartMinute = 720

    private static func axisFraction(_ minutes: Int) -> CGFloat {
        CGFloat(((minutes - axisStartMinute) % 1440 + 1440) % 1440) / 1440.0
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

                    gradientCard(
                        title: plan.originName,
                        subtitle: "Origin · your local time",
                        icon: "airplane.departure",
                        sunriseMinutes: plan.originSunriseMinutes,
                        sunsetMinutes: plan.originSunsetMinutes
                    )

                    nightsSection

                    gradientCard(
                        title: plan.destinationCity,
                        subtitle: destinationSubtitle,
                        icon: "airplane.arrival",
                        sunriseMinutes: plan.destSunriseLocalMinutes,
                        sunsetMinutes: plan.destSunsetLocalMinutes
                    )

                    timezoneAndAlarmSection
                }
                .padding()
            }
        }
        .navigationTitle("Transition Plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var destinationSubtitle: String {
        let sr = SleepCalculator.formattedTime(minutesSinceMidnight: plan.destSunriseMinutes)
        let ss = SleepCalculator.formattedTime(minutesSinceMidnight: plan.destSunsetMinutes)
        return "Destination's Daylight Hours: \(sr)–\(ss)"
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(plan.nights.count)-Night Plan", systemImage: "bed.double.circle")
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())

                Spacer()

                nightStepper
            }

            Text("Gradually shift your sleep to match **\(plan.destinationCity)** time, starting tonight.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

    private func gradientCard(title: String, subtitle: String, icon: String, sunriseMinutes: Int, sunsetMinutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            RoundedRectangle(cornerRadius: barHeight / 2)
                .fill(Self.skyGradient(sunriseMinutes: sunriseMinutes, sunsetMinutes: sunsetMinutes))
                .frame(height: barHeight)

            timeAxisLabels
        }
        .moonbeamCard()
    }

    private var timeAxisLabels: some View {
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
        VStack(alignment: .leading, spacing: 14) {
            ForEach(plan.nights) { night in
                nightRow(night: night)
            }
            timeAxisLabels
        }
        .moonbeamCard()
    }

    private func nightRow(night: JetLagNightPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Night \(night.nightIndex + 1)")
                    .font(.caption.weight(.semibold))
                Text(night.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.05))

                    sleepSegments(window: night.sleepWindow, width: width)
                }
            }
            .frame(height: sleepBarHeight)
        }
    }

    @ViewBuilder
    private func sleepSegments(window: JetLagSleepWindow, width: CGFloat) -> some View {
        let bedFrac = Self.axisFraction(window.bedMinutes)
        let wakeFrac = Self.axisFraction(window.wakeMinutes)
        let bedTime = SleepCalculator.formattedTime(minutesSinceMidnight: window.bedMinutes)
        let wakeTime = SleepCalculator.formattedTime(minutesSinceMidnight: window.wakeMinutes)

        if wakeFrac < bedFrac {
            // Wraps past the bar edge: slice the night arc proportionally so
            // the warm dusk end stays with bedtime and the blue dawn end with
            // wake-up.
            let total = (1.0 - bedFrac) + wakeFrac
            let split = total > 0 ? Double((1.0 - bedFrac) / total) : 0.5

            sleepSegment(
                startFrac: bedFrac, endFrac: 1.0, width: width,
                gradient: Self.sleepGradient(from: 0, to: split)
            ) {
                HStack {
                    sleepChip(icon: "bed.double.fill", time: bedTime)
                    Spacer(minLength: 0)
                }
            }
            sleepSegment(
                startFrac: 0.0, endFrac: wakeFrac, width: width,
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

            Divider().opacity(0.3)

            if alarmsSet {
                Label("Alarms set for all \(plan.nights.count) nights", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Text("Wake-up alarms sound even in Silent mode. Bedtime reminders arrive as notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Label("Set Alarms for All \(plan.nights.count) Nights", systemImage: "alarm.fill")
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

    /// Builds a 24-hour day/night gradient for arbitrary sunrise/sunset times,
    /// including daylight spans that wrap past the bar edges (e.g. a far-shifted
    /// destination drawn on the origin's clock, or the noon-centered axis).
    /// Sampled rather than hand-placed stops so no clamping is needed. The
    /// twilight palette mirrors the home-screen dial: long gold/amber approach
    /// to sunset, red at the horizon, purple after, deep blue before dawn.
    static func skyGradient(sunriseMinutes: Int, sunsetMinutes: Int) -> LinearGradient {
        let day: RGB = (0.92, 0.92, 0.96)
        let night: RGB = (0.06, 0.04, 0.18)

        // Minutes from sunrise → color, walking up into full daylight.
        let morning: [(Double, RGB)] = [
            (0, (0.45, 0.65, 0.85)),     // sunrise blue at the horizon
            (25, (0.62, 0.78, 0.92)),
            (55, (0.75, 0.85, 0.95)),
            (110, (0.88, 0.90, 0.95)),
            (210, day),
        ]
        // Minutes until sunset → color, the long warm slide into golden hour.
        let afternoon: [(Double, RGB)] = [
            (0, (0.90, 0.38, 0.35)),     // sun on the horizon
            (35, (0.92, 0.66, 0.45)),    // orange
            (95, (0.93, 0.81, 0.58)),    // gold
            (190, (0.91, 0.88, 0.87)),   // warm-tinged white
            (300, day),
        ]
        // Minutes after sunset → color, through the purples into night.
        let dusk: [(Double, RGB)] = [
            (0, (0.90, 0.38, 0.35)),
            (30, (0.60, 0.20, 0.42)),    // magenta
            (70, (0.25, 0.10, 0.32)),    // deep purple
            (150, night),
        ]
        // Minutes until sunrise → color, night brightening toward dawn.
        let preDawn: [(Double, RGB)] = [
            (0, (0.15, 0.25, 0.50)),     // twilight blue at the horizon
            (35, (0.10, 0.11, 0.34)),
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

        let sampleCount = 144  // 10-minute steps keep the horizon edges crisp
        let stops = (0...sampleCount).map { i -> Gradient.Stop in
            let frac = Double(i) / Double(sampleCount)
            let minute = (Double(Self.axisStartMinute) + frac * 1440).truncatingRemainder(dividingBy: 1440)
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
}
