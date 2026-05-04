//
//  SleepSliderView.swift
//  Moonbeam
//

import SwiftUI

struct SleepSliderView: View {
    @EnvironmentObject private var profile: SleepProfile
    @EnvironmentObject private var sunTimes: SunTimesService

    // Angles in radians on 24-hr dial (0 = 12 AM at top, clockwise)
    @State private var bedAngle: Double = SleepCalculator.angle(
        for: Calendar.current.date(bySettingHour: 22, minute: 30, second: 0, of: Date())!
    )
    @State private var wakeAngle: Double = SleepCalculator.angle(
        for: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
    )
    @State private var lastSnappedCycles: Int = 0
    @State private var isDraggingBed: Bool = false
    @State private var isDraggingWake: Bool = false
    @State private var isDraggingArc: Bool = false
    @State private var arcDragPreviousAngle: Double = 0
    @State private var lastDragged: HandleType = .bed

    private let ringWidth: CGFloat = 40
    private let dialPadding: CGFloat = 32
    private let handleSize: CGFloat = 44

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private enum HandleType { case bed, wake }

    // Raw duration between the two angles (minutes)
    private var rawDurationMinutes: Double {
        SleepCalculator.durationMinutes(bedAngle: bedAngle, wakeAngle: wakeAngle)
    }

    private var snappedSleepMinutes: Int {
        SleepCalculator.snapDuration(rawMinutes: rawDurationMinutes, cycleMinutes: profile.remCycleMinutes)
    }

    private var cycleCount: Int {
        SleepCalculator.cycleCount(sleepMinutes: snappedSleepMinutes, cycleMinutes: profile.remCycleMinutes)
    }

    private var totalSleepMinutes: Int {
        snappedSleepMinutes + profile.fallAsleepMinutes
    }

    private var displayBedAngle: Double {
        if lastDragged == .wake {
            let wakeMins = SleepCalculator.minutesSinceMidnight(from: wakeAngle)
            let bedMins = (wakeMins - totalSleepMinutes + 1440) % 1440
            return Double(bedMins) / 1440.0 * 2.0 * .pi
        }
        return bedAngle
    }

    private var displayWakeAngle: Double {
        if lastDragged == .bed {
            let bedMins = SleepCalculator.minutesSinceMidnight(from: bedAngle)
            let wakeMins = (bedMins + totalSleepMinutes) % 1440
            return Double(wakeMins) / 1440.0 * 2.0 * .pi
        }
        return wakeAngle
    }

    private var displayBedMinutes: Int {
        SleepCalculator.minutesSinceMidnight(from: displayBedAngle)
    }

    private var displayWakeMinutes: Int {
        SleepCalculator.minutesSinceMidnight(from: displayWakeAngle)
    }

    // Public accessors for alarm scheduling
    var currentBedMinutes: Int { displayBedMinutes }
    var currentWakeMinutes: Int { displayWakeMinutes }

    var body: some View {
        VStack(spacing: 20) {
            timeLabels
            dialView
            durationLabel
        }
    }

    // MARK: - Time Labels

    private var timeLabels: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label("BEDTIME", systemImage: "bed.double.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(SleepCalculator.formattedTime(minutesSinceMidnight: displayBedMinutes))
                    .font(.title2.weight(.bold).monospacedDigit())
                Text(displayBedMinutes >= 720 ? "Tonight" : "Tomorrow")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Label("WAKE UP", systemImage: "alarm.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(SleepCalculator.formattedTime(minutesSinceMidnight: displayWakeMinutes))
                    .font(.title2.weight(.bold).monospacedDigit())
                Text(displayWakeMinutes < 720 ? "Tomorrow" : "Today")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Duration Label

    private var durationLabel: some View {
        VStack(spacing: 8) {
            Text(SleepCalculator.formattedDuration(minutes: totalSleepMinutes))
                .font(.title3.weight(.semibold).monospacedDigit())
            Text("\(cycleCount) REM cycle\(cycleCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
        }
        .contentTransition(.numericText())
    }

    // MARK: - Dial

    private var dialView: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let outerRadius = (size - dialPadding * 2) / 2
            let midRadius = outerRadius - ringWidth / 2

            ZStack {
                // Fixed background sky gradient ring
                backgroundSkyRing(center: center, radius: midRadius)

                // Recessed groove shadow
                Circle()
                    .stroke(Color.black.opacity(0.3), lineWidth: ringWidth + 4)
                    .blur(radius: 4)
                    .frame(width: midRadius * 2, height: midRadius * 2)
                    .position(center)

                // Inner edge highlight (top-lit bevel)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.10), .clear, .clear, .white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: midRadius * 2 + ringWidth - 2, height: midRadius * 2 + ringWidth - 2)
                    .position(center)

                // Inner edge shadow (bottom)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.12), .black.opacity(0.15), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: midRadius * 2 - ringWidth + 2, height: midRadius * 2 - ringWidth + 2)
                    .position(center)

                // Clock tick marks & labels
                clockFace(center: center, midRadius: midRadius)

                // Glass sleep arc
                sleepArc(center: center, radius: midRadius)

                // REM segment dividers
                remSegmentDividers(center: center, radius: midRadius)

                // Invisible arc hit target for whole-arc dragging
                arcHitTarget(center: center, radius: midRadius)
                    .gesture(arcDragGesture(center: center))

                // Bedtime handle
                handleView(
                    angle: displayBedAngle,
                    center: center,
                    radius: midRadius,
                    icon: "bed.double.fill",
                    isDragging: isDraggingBed
                )
                .gesture(dragGesture(for: .bed, center: center))

                // Wake handle
                handleView(
                    angle: displayWakeAngle,
                    center: center,
                    radius: midRadius,
                    icon: "alarm.fill",
                    isDragging: isDraggingWake
                )
                .gesture(dragGesture(for: .wake, center: center))
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Background Sky Ring

    private func backgroundSkyRing(center: CGPoint, radius: CGFloat) -> some View {
        let sunrise = max(0.15, min(0.40, Double(sunTimes.sunriseMinutes) / 1440.0))
        let sunset = max(0.60, min(0.92, Double(sunTimes.sunsetMinutes) / 1440.0))

        let postSunrise = sunrise + 0.06
        let midMorning = min((sunrise + 0.5) / 2 + 0.04, 0.48)
        let midAfternoon = max((0.5 + sunset) / 2 - 0.02, 0.52)
        let preSunset = sunset - 0.015

        let gradient = AngularGradient(
            stops: [
                .init(color: Color(red: 0.06, green: 0.04, blue: 0.18), location: 0.0),
                .init(color: Color(red: 0.08, green: 0.08, blue: 0.28), location: sunrise - 0.04),
                .init(color: Color(red: 0.15, green: 0.25, blue: 0.50), location: sunrise - 0.015),
                .init(color: Color(red: 0.45, green: 0.65, blue: 0.85), location: sunrise),
                .init(color: Color(red: 0.62, green: 0.78, blue: 0.92), location: sunrise + 0.025),
                .init(color: Color(red: 0.75, green: 0.85, blue: 0.95), location: postSunrise),
                .init(color: Color(red: 0.85, green: 0.90, blue: 0.96), location: postSunrise + 0.03),
                .init(color: Color(red: 0.90, green: 0.92, blue: 0.96), location: midMorning),
                .init(color: Color(red: 0.92, green: 0.92, blue: 0.96), location: 0.5),
                .init(color: Color(red: 0.90, green: 0.88, blue: 0.90), location: midAfternoon),
                .init(color: Color(red: 0.92, green: 0.72, blue: 0.50), location: preSunset),
                .init(color: Color(red: 0.90, green: 0.38, blue: 0.35), location: sunset),
                .init(color: Color(red: 0.60, green: 0.20, blue: 0.42), location: sunset + 0.03),
                .init(color: Color(red: 0.25, green: 0.10, blue: 0.32), location: sunset + 0.06),
                .init(color: Color(red: 0.06, green: 0.04, blue: 0.18), location: 1.0),
            ],
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )

        return Circle()
            .stroke(gradient, lineWidth: ringWidth)
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
    }

    // MARK: - Clock Face

    private func clockFace(center: CGPoint, midRadius: CGFloat) -> some View {
        let innerRingEdge = midRadius - ringWidth / 2
        let labelRadius = innerRingEdge - 18
        let sunTimeLabelRadius = innerRingEdge - 40
        let iconRadius = innerRingEdge - 44

        let sunriseText = SleepCalculator.formattedTime(minutesSinceMidnight: sunTimes.sunriseMinutes)
        let sunsetText = SleepCalculator.formattedTime(minutesSinceMidnight: sunTimes.sunsetMinutes)

        return ZStack {
            hourTickMarks(center: center, midRadius: midRadius)

            clockLabel("12AM", angle: -.pi / 2, radius: labelRadius, center: center)

            // Sunrise time + icon (right side, 6AM position)
            sunTimeLabel(
                time: sunriseText,
                icon: "sunrise.fill",
                iconColor: .orange.opacity(0.7),
                angle: 0,
                radius: sunTimeLabelRadius,
                center: center,
                iconTrailing: true
            )

            clockLabel("12PM", angle: .pi / 2, radius: labelRadius, center: center)

            // Sunset time + icon (left side, 6PM position)
            sunTimeLabel(
                time: sunsetText,
                icon: "sunset.fill",
                iconColor: .orange.opacity(0.6),
                angle: .pi,
                radius: sunTimeLabelRadius,
                center: center,
                iconTrailing: false
            )

            Image(systemName: "moon.fill")
                .font(.system(size: 16))
                .foregroundStyle(.indigo.opacity(0.7))
                .position(x: center.x, y: center.y - iconRadius)

            Image(systemName: "sun.max.fill")
                .font(.system(size: 16))
                .foregroundStyle(.yellow.opacity(0.7))
                .position(x: center.x, y: center.y + iconRadius)
        }
    }

    /// Displays a sunrise/sunset time with an icon beside it on the dial
    private func sunTimeLabel(
        time: String,
        icon: String,
        iconColor: Color,
        angle: Double,
        radius: CGFloat,
        center: CGPoint,
        iconTrailing: Bool
    ) -> some View {
        let x = center.x + cos(angle) * radius
        let y = center.y + sin(angle) * radius

        return HStack(spacing: 4) {
            if !iconTrailing {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
            }
            Text(time)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            if iconTrailing {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
            }
        }
        .position(x: x, y: y)
    }

    private func hourTickMarks(center: CGPoint, midRadius: CGFloat) -> some View {
        ForEach(0..<24, id: \.self) { hour in
            hourTick(hour: hour, center: center, midRadius: midRadius)
        }
    }

    private func hourTick(hour: Int, center: CGPoint, midRadius: CGFloat) -> some View {
        let tickAngle = Double(hour) / 24.0 * 2.0 * .pi - .pi / 2
        let isMajor = hour % 6 == 0
        let tickLength: CGFloat = isMajor ? 10 : 5
        let outerRingEdge = midRadius + ringWidth / 2
        let tickOuter = outerRingEdge + 2 + tickLength
        let tickInner = outerRingEdge + 2

        return Path { path in
            path.move(to: CGPoint(
                x: center.x + cos(tickAngle) * tickOuter,
                y: center.y + sin(tickAngle) * tickOuter
            ))
            path.addLine(to: CGPoint(
                x: center.x + cos(tickAngle) * tickInner,
                y: center.y + sin(tickAngle) * tickInner
            ))
        }
        .stroke(Color.white.opacity(isMajor ? 0.4 : 0.15), lineWidth: isMajor ? 2 : 1)
    }

    private func clockLabel(_ text: String, angle: Double, radius: CGFloat, center: CGPoint) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .position(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
    }

    // MARK: - Sleep Arc (Glass Look — Continuous Fill)

    private func sleepArc(center: CGPoint, radius: CGFloat) -> some View {
        let startSwiftUI = displayBedAngle - .pi / 2
        let endSwiftUI = displayWakeAngle - .pi / 2

        var arcSpan = endSwiftUI - startSwiftUI
        if arcSpan <= 0 { arcSpan += 2 * .pi }

        let trimEnd = CGFloat(arcSpan / (2 * .pi))

        return ZStack {
            // Soft glow behind — single continuous arc
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(Color.white.opacity(0.03), style: StrokeStyle(lineWidth: ringWidth + 10, lineCap: .butt))
                .blur(radius: 10)
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.radians(startSwiftUI))
                .position(center)

            // Main glass arc — lighter, more translucent
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(Color.white.opacity(0.05), style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt))
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.radians(startSwiftUI))
                .position(center)

            // Top highlight for raised glass look — brighter specular
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: max(4, ringWidth - 8), lineCap: .butt)
                )
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.radians(startSwiftUI))
                .position(center)

            // Outer rim highlight
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, lineCap: .butt))
                .frame(width: (radius + ringWidth / 2 - 1) * 2, height: (radius + ringWidth / 2 - 1) * 2)
                .rotationEffect(.radians(startSwiftUI))
                .position(center)

            // Inner rim highlight
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 0.75, lineCap: .butt))
                .frame(width: (radius - ringWidth / 2 + 1) * 2, height: (radius - ringWidth / 2 + 1) * 2)
                .rotationEffect(.radians(startSwiftUI))
                .position(center)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayWakeAngle)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayBedAngle)
    }

    // MARK: - Arc Hit Target

    private func arcHitTarget(center: CGPoint, radius: CGFloat) -> some View {
        let startSwiftUI = displayBedAngle - .pi / 2
        let endSwiftUI = displayWakeAngle - .pi / 2
        var arcSpan = endSwiftUI - startSwiftUI
        if arcSpan <= 0 { arcSpan += 2 * .pi }
        let trimEnd = CGFloat(arcSpan / (2 * .pi))

        return Circle()
            .trim(from: 0, to: trimEnd)
            .stroke(Color.white.opacity(0.001), style: StrokeStyle(lineWidth: ringWidth + 20, lineCap: .round))
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.radians(startSwiftUI))
            .position(center)
    }

    // MARK: - REM Segment Dividers

    private func remSegmentDividers(center: CGPoint, radius: CGFloat) -> some View {
        let count = cycleCount
        let cycleFraction = Double(profile.remCycleMinutes) / 1440.0 * 2.0 * .pi
        let fallAsleepOffset = Double(profile.fallAsleepMinutes) / 1440.0 * 2.0 * .pi

        return ForEach(1..<count, id: \.self) { i in
            remDivider(
                index: i,
                center: center,
                radius: radius,
                cycleFraction: cycleFraction,
                fallAsleepOffset: fallAsleepOffset
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: count)
        }
    }

    private func remDivider(
        index: Int,
        center: CGPoint,
        radius: CGFloat,
        cycleFraction: Double,
        fallAsleepOffset: Double
    ) -> some View {
        let divAngle = displayBedAngle + fallAsleepOffset + cycleFraction * Double(index)
        let swAngle = divAngle - .pi / 2
        let innerR = radius - ringWidth / 2 + 4
        let outerR = radius + ringWidth / 2 - 4

        return Path { path in
            path.move(to: CGPoint(
                x: center.x + cos(swAngle) * innerR,
                y: center.y + sin(swAngle) * innerR
            ))
            path.addLine(to: CGPoint(
                x: center.x + cos(swAngle) * outerR,
                y: center.y + sin(swAngle) * outerR
            ))
        }
        .stroke(Color.white.opacity(0.6), lineWidth: 2)
    }

    // MARK: - Handle

    private func handleView(angle: Double, center: CGPoint, radius: CGFloat, icon: String, isDragging: Bool) -> some View {
        let swAngle = angle - .pi / 2
        let x = center.x + cos(swAngle) * radius
        let y = center.y + sin(swAngle) * radius

        return Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: handleSize, height: handleSize)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            )
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: handleSize, height: handleSize)
            )
            .scaleEffect(isDragging ? 1.15 : 1.0)
            .animation(.spring(response: 0.3), value: isDragging)
            .position(x: x, y: y)
    }

    // MARK: - Drag Gesture

    private func dragGesture(for handle: HandleType, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                var angle = atan2(dy, dx) + .pi / 2
                if angle < 0 { angle += 2 * .pi }

                let mins = SleepCalculator.minutesSinceMidnight(from: angle)
                let snappedMins = (mins / 15) * 15
                let snappedAngle = Double(snappedMins) / 1440.0 * 2.0 * .pi

                switch handle {
                case .bed:
                    isDraggingBed = true
                    lastDragged = .bed
                    bedAngle = snappedAngle
                case .wake:
                    isDraggingWake = true
                    lastDragged = .wake
                    wakeAngle = snappedAngle
                }

                let newCycles = cycleCount
                if newCycles != lastSnappedCycles {
                    haptic.impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        lastSnappedCycles = newCycles
                    }
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    bedAngle = displayBedAngle
                    wakeAngle = displayWakeAngle
                }
                isDraggingBed = false
                isDraggingWake = false
            }
    }

    // MARK: - Arc Drag Gesture

    private func arcDragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                var currentAngle = atan2(dy, dx) + .pi / 2
                if currentAngle < 0 { currentAngle += 2 * .pi }

                if !isDraggingArc {
                    isDraggingArc = true
                    arcDragPreviousAngle = currentAngle
                    return
                }

                var delta = currentAngle - arcDragPreviousAngle
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }

                bedAngle = (bedAngle + delta).truncatingRemainder(dividingBy: 2 * .pi)
                wakeAngle = (wakeAngle + delta).truncatingRemainder(dividingBy: 2 * .pi)
                if bedAngle < 0 { bedAngle += 2 * .pi }
                if wakeAngle < 0 { wakeAngle += 2 * .pi }

                arcDragPreviousAngle = currentAngle
            }
            .onEnded { _ in
                isDraggingArc = false
                let bedMins = SleepCalculator.minutesSinceMidnight(from: bedAngle)
                let snappedBedMins = ((bedMins + 7) / 15) * 15
                let wakeMins = SleepCalculator.minutesSinceMidnight(from: wakeAngle)
                let snappedWakeMins = ((wakeMins + 7) / 15) * 15

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    bedAngle = Double(snappedBedMins % 1440) / 1440.0 * 2.0 * .pi
                    wakeAngle = Double(snappedWakeMins % 1440) / 1440.0 * 2.0 * .pi
                    bedAngle = displayBedAngle
                    wakeAngle = displayWakeAngle
                }
            }
    }

    // MARK: - Sleep Now

    func sleepNow() {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let nowMinutes = hour * 60 + minute
        let snappedMins = (nowMinutes / 15) * 15

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            bedAngle = Double(snappedMins) / 1440.0 * 2.0 * .pi
        }
        haptic.impactOccurred()
    }
}

#Preview {
    ZStack {
        Color.clear.moonbeamBackground()
        SleepSliderView()
            .environmentObject(SleepProfile())
            .environmentObject(SunTimesService())
            .foregroundColor(.white)
            .padding()
    }
}
