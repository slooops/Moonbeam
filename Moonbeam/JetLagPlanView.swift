//
//  JetLagPlanView.swift
//  Moonbeam
//

import SwiftUI

struct JetLagPlanView: View {
    let plan: JetLagPlan
    let onSetAlarms: (JetLagDayPlan) -> Void

    @State private var alarmsSetForDay: Int? = nil

    private let barHeight: CGFloat = 40  // same as dial ringWidth

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    VStack(spacing: 16) {
                        ForEach(plan.days) { day in
                            dayBar(day: day)
                        }
                    }

                    timezoneAndAlarmSection
                }
                .padding()
            }
        }
        .navigationTitle("Transition Plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("3-Night Plan", systemImage: "bed.double.circle")
                .font(.title3.weight(.semibold))

            Text("Gradually shift your sleep to match **\(plan.destinationCity)** time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moonbeamCard()
    }

    // MARK: - Timezone & Alarm

    private var timezoneAndAlarmSection: some View {
        let diff = plan.destinationOffsetHours - plan.localOffsetHours
        let direction = diff > 0 ? "ahead" : "behind"
        let absDiff = abs(diff)

        return VStack(alignment: .leading, spacing: 14) {
            Label("Timezone Shift", systemImage: "globe")
                .font(.subheadline.weight(.semibold))
            Text("\(plan.destinationCity) is \(absDiff) hour\(absDiff == 1 ? "" : "s") \(direction) of your current time.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().opacity(0.3)

            if let setDay = alarmsSetForDay {
                Label("Night \(setDay + 1) alarms set", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                if setDay < 2 {
                    Text("You'll get a reminder tomorrow to set Night \(setDay + 2) alarms.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                let nextDay = nextUnsetDay
                Button {
                    onSetAlarms(plan.days[nextDay])
                    withAnimation { alarmsSetForDay = nextDay }
                } label: {
                    Label("Set Night \(nextDay + 1) Alarms", systemImage: "alarm.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moonbeamCard()
    }

    private var nextUnsetDay: Int {
        // Simple: return 0, 1, or 2 based on which hasn't been set
        return min(alarmsSetForDay.map { $0 + 1 } ?? 0, 2)
    }

    // MARK: - Day Bar

    private func dayBar(day: JetLagDayPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Night \(day.dayIndex + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(SleepCalculator.formattedTime(minutesSinceMidnight: day.sleepWindow.bedMinutes)) – \(SleepCalculator.formattedTime(minutesSinceMidnight: day.sleepWindow.wakeMinutes))")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Background gradient bar
                    skyGradientBar(
                        sunriseMinutes: day.sunriseMinutes,
                        sunsetMinutes: day.sunsetMinutes,
                        width: width
                    )

                    // Glass sleep overlay
                    sleepOverlay(
                        bedMinutes: day.sleepWindow.bedMinutes,
                        wakeMinutes: day.sleepWindow.wakeMinutes,
                        width: width
                    )
                }
            }
            .frame(height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: barHeight / 2))

            // Time axis labels
            HStack {
                Text("12AM")
                Spacer()
                Text("6AM")
                Spacer()
                Text("12PM")
                Spacer()
                Text("6PM")
                Spacer()
                Text("12AM")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.35))
        }
        .moonbeamCard()
    }

    // MARK: - Sky Gradient Bar

    private func skyGradientBar(sunriseMinutes: Int, sunsetMinutes: Int, width: CGFloat) -> some View {
        let sunrise = max(0.15, min(0.40, Double(sunriseMinutes) / 1440.0))
        let sunset = max(0.60, min(0.92, Double(sunsetMinutes) / 1440.0))
        let postSunrise = sunrise + 0.03
        let midMorning = min((sunrise + 0.5) / 2 + 0.02, 0.48)
        let midAfternoon = max((0.5 + sunset) / 2 - 0.02, 0.52)
        let preSunset = sunset - 0.015

        let gradient = LinearGradient(
            stops: [
                .init(color: Color(red: 0.06, green: 0.04, blue: 0.18), location: 0.0),
                .init(color: Color(red: 0.08, green: 0.08, blue: 0.28), location: sunrise - 0.04),
                .init(color: Color(red: 0.15, green: 0.25, blue: 0.50), location: sunrise - 0.015),
                .init(color: Color(red: 0.45, green: 0.65, blue: 0.85), location: sunrise),
                .init(color: Color(red: 0.75, green: 0.85, blue: 0.95), location: postSunrise),
                .init(color: Color(red: 0.88, green: 0.90, blue: 0.95), location: midMorning),
                .init(color: Color(red: 0.92, green: 0.92, blue: 0.96), location: 0.5),
                .init(color: Color(red: 0.90, green: 0.88, blue: 0.90), location: midAfternoon),
                .init(color: Color(red: 0.92, green: 0.72, blue: 0.50), location: preSunset),
                .init(color: Color(red: 0.90, green: 0.38, blue: 0.35), location: sunset),
                .init(color: Color(red: 0.60, green: 0.20, blue: 0.42), location: sunset + 0.03),
                .init(color: Color(red: 0.25, green: 0.10, blue: 0.32), location: sunset + 0.06),
                .init(color: Color(red: 0.06, green: 0.04, blue: 0.18), location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        return RoundedRectangle(cornerRadius: barHeight / 2)
            .fill(gradient)
            .frame(height: barHeight)
    }

    // MARK: - Sleep Overlay

    private func sleepOverlay(bedMinutes: Int, wakeMinutes: Int, width: CGFloat) -> some View {
        let bedFrac = CGFloat(bedMinutes) / 1440.0
        let wakeFrac = CGFloat(wakeMinutes) / 1440.0

        // Handle wrapping past midnight
        let wraps = wakeFrac < bedFrac

        return ZStack(alignment: .leading) {
            if wraps {
                // Two segments: bed→end and start→wake
                // Segment 1: bed to end of bar
                glassSegment(startFrac: bedFrac, endFrac: 1.0, width: width)
                // Segment 2: start of bar to wake
                glassSegment(startFrac: 0.0, endFrac: wakeFrac, width: width)
            } else {
                glassSegment(startFrac: bedFrac, endFrac: wakeFrac, width: width)
            }
        }
    }

    private func glassSegment(startFrac: CGFloat, endFrac: CGFloat, width: CGFloat) -> some View {
        let segWidth = max(0, (endFrac - startFrac) * width)
        let offset = startFrac * width

        return RoundedRectangle(cornerRadius: barHeight / 3)
            .fill(Color.white.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: barHeight / 3)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: barHeight / 3)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .frame(width: segWidth, height: barHeight - 6)
            .offset(x: offset)
    }
}

#Preview {
    let plan = JetLagPlan(
        destinationCity: "Tokyo",
        localOffsetHours: -8,
        destinationOffsetHours: 9,
        days: [
            JetLagDayPlan(dayIndex: 0, sleepWindow: JetLagSleepWindow(bedMinutes: 1290, wakeMinutes: 330), sunriseMinutes: 390, sunsetMinutes: 1200),
            JetLagDayPlan(dayIndex: 1, sleepWindow: JetLagSleepWindow(bedMinutes: 1230, wakeMinutes: 270), sunriseMinutes: 360, sunsetMinutes: 1170),
            JetLagDayPlan(dayIndex: 2, sleepWindow: JetLagSleepWindow(bedMinutes: 1170, wakeMinutes: 210), sunriseMinutes: 330, sunsetMinutes: 1140),
        ],
        createdAt: Date()
    )

    NavigationStack {
        JetLagPlanView(plan: plan, onSetAlarms: { _ in })
    }
}
