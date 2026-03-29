//
//  SleepSliderView.swift
//  Moonbeam
//

import SwiftUI

struct SleepSliderView: View {
    @EnvironmentObject private var profile: SleepProfile

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

    private let ringWidth: CGFloat = 40
    private let dialPadding: CGFloat = 32
    private let handleSize: CGFloat = 44

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private var snappedSleepMinutes: Int {
        let raw = SleepCalculator.durationMinutes(bedAngle: bedAngle, wakeAngle: wakeAngle)
        return SleepCalculator.snapDuration(rawMinutes: raw, cycleMinutes: profile.remCycleMinutes)
    }

    private var cycleCount: Int {
        SleepCalculator.cycleCount(sleepMinutes: snappedSleepMinutes, cycleMinutes: profile.remCycleMinutes)
    }

    private var totalSleepMinutes: Int {
        snappedSleepMinutes + profile.fallAsleepMinutes
    }

    private var bedMinutes: Int {
        SleepCalculator.minutesSinceMidnight(from: bedAngle)
    }

    private var wakeMinutes: Int {
        let snappedWake = bedMinutes + totalSleepMinutes
        return snappedWake % 1440
    }

    private var snappedWakeAngle: Double {
        Double(wakeMinutes) / 1440.0 * 2.0 * .pi
    }

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
                Text(SleepCalculator.formattedTime(minutesSinceMidnight: bedMinutes))
                    .font(.title2.weight(.bold).monospacedDigit())
                Text(bedMinutes >= 720 ? "Tonight" : "Tomorrow")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Label("WAKE UP", systemImage: "alarm.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(SleepCalculator.formattedTime(minutesSinceMidnight: wakeMinutes))
                    .font(.title2.weight(.bold).monospacedDigit())
                Text(wakeMinutes < 720 ? "Tomorrow" : "Today")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Duration Label

    private var durationLabel: some View {
        VStack(spacing: 4) {
            Text(SleepCalculator.formattedDuration(minutes: totalSleepMinutes))
                .font(.title3.weight(.semibold).monospacedDigit())
            Text("\(cycleCount) REM cycle\(cycleCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                // Outer track ring
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: ringWidth)
                    .frame(width: outerRadius * 2 - ringWidth, height: outerRadius * 2 - ringWidth)

                // Clock tick marks & labels
                clockFace(radius: outerRadius, midRadius: midRadius)

                // Filled sleep arc
                sleepArc(radius: midRadius)

                // REM segment dividers
                remSegmentDividers(radius: midRadius)

                // Bedtime handle
                handleView(
                    angle: bedAngle,
                    radius: midRadius,
                    icon: "bed.double.fill",
                    isDragging: isDraggingBed
                )
                .gesture(dragGesture(for: .bed, center: center))

                // Wake handle
                handleView(
                    angle: snappedWakeAngle,
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

    // MARK: - Clock Face

    private func clockFace(radius: CGFloat, midRadius: CGFloat) -> some View {
        ZStack {
            // Hour tick marks
            ForEach(0..<24, id: \.self) { hour in
                let tickAngle = Double(hour) / 24.0 * 2.0 * .pi - .pi / 2
                let isMajor = hour % 6 == 0
                let tickLength: CGFloat = isMajor ? 12 : 6
                let outerR = radius + 2
                let innerR = outerR - tickLength

                Path { path in
                    path.move(to: CGPoint(
                        x: radius + cos(tickAngle) * outerR,
                        y: radius + sin(tickAngle) * outerR
                    ))
                    path.addLine(to: CGPoint(
                        x: radius + cos(tickAngle) * innerR,
                        y: radius + sin(tickAngle) * innerR
                    ))
                }
                .stroke(Color.white.opacity(isMajor ? 0.4 : 0.15), lineWidth: isMajor ? 2 : 1)
            }

            // Cardinal labels
            clockLabel("12AM", angle: -.pi / 2, radius: radius - ringWidth - 20, refRadius: radius)
            clockLabel("6AM", angle: 0, radius: radius - ringWidth - 20, refRadius: radius)
            clockLabel("12PM", angle: .pi / 2, radius: radius - ringWidth - 20, refRadius: radius)
            clockLabel("6PM", angle: .pi, radius: radius - ringWidth - 20, refRadius: radius)

            // Moon at top (12 AM)
            Image(systemName: "moon.fill")
                .font(.system(size: 14))
                .foregroundStyle(.indigo.opacity(0.8))
                .position(
                    x: radius,
                    y: radius + cos(.pi) * (radius - ringWidth - 6)
                )

            // Sun at bottom (12 PM)
            Image(systemName: "sun.max.fill")
                .font(.system(size: 14))
                .foregroundStyle(.yellow.opacity(0.8))
                .position(
                    x: radius,
                    y: radius + cos(0) * (radius - ringWidth - 6)
                )
        }
    }

    private func clockLabel(_ text: String, angle: Double, radius: CGFloat, refRadius: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .position(
                x: refRadius + cos(angle) * radius,
                y: refRadius + sin(angle) * radius
            )
    }

    // MARK: - Sleep Arc

    private func sleepArc(radius: CGFloat) -> some View {
        // Convert from our 24-hr convention (0 = 12AM top) to SwiftUI angles (0 = right)
        let startSwiftUI = bedAngle - .pi / 2
        let endSwiftUI = snappedWakeAngle - .pi / 2

        return Circle()
            .trim(from: normalizedFraction(startSwiftUI), to: normalizedFractionEnd(startSwiftUI, endSwiftUI))
            .stroke(
                AngularGradient(
                    colors: [.indigo, .purple, .blue, .indigo],
                    center: .center,
                    startAngle: .radians(startSwiftUI),
                    endAngle: .radians(endSwiftUI + (endSwiftUI <= startSwiftUI ? 2 * .pi : 0))
                ),
                style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
            )
            .frame(width: radius * 2, height: radius * 2)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: snappedWakeAngle)
    }

    private func normalizedFraction(_ angle: Double) -> CGFloat {
        var a = angle / (2 * .pi)
        while a < 0 { a += 1 }
        return CGFloat(a.truncatingRemainder(dividingBy: 1.0))
    }

    private func normalizedFractionEnd(_ start: Double, _ end: Double) -> CGFloat {
        let s = normalizedFraction(start)
        var e = CGFloat(end / (2 * .pi))
        while e < 0 { e += 1 }
        e = e.truncatingRemainder(dividingBy: 1.0)
        if e <= s { e += 1.0 }
        return e
    }

    // MARK: - REM Segment Dividers

    private func remSegmentDividers(radius: CGFloat) -> some View {
        let count = cycleCount
        let cycleFraction = Double(profile.remCycleMinutes) / 1440.0 * 2.0 * .pi

        return ForEach(1..<count, id: \.self) { i in
            let divAngle = bedAngle + Double(profile.fallAsleepMinutes) / 1440.0 * 2.0 * .pi + cycleFraction * Double(i)
            let swAngle = divAngle - .pi / 2

            Path { path in
                let innerR = radius - ringWidth / 2 + 4
                let outerR = radius + ringWidth / 2 - 4
                path.move(to: CGPoint(
                    x: radius + cos(swAngle) * innerR,
                    y: radius + sin(swAngle) * outerR
                ))
                path.addLine(to: CGPoint(
                    x: radius + cos(swAngle) * outerR,
                    y: radius + sin(swAngle) * innerR
                ))
            }
            .stroke(Color.white.opacity(0.6), lineWidth: 2)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: count)
        }
    }

    // MARK: - Handle

    private func handleView(angle: Double, radius: CGFloat, icon: String, isDragging: Bool) -> some View {
        let swAngle = angle - .pi / 2
        let x = radius + cos(swAngle) * radius
        let y = radius + sin(swAngle) * radius

        return Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: handleSize, height: handleSize)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            )
            .scaleEffect(isDragging ? 1.15 : 1.0)
            .animation(.spring(response: 0.3), value: isDragging)
            .position(x: x, y: y)
    }

    // MARK: - Drag Gesture

    private enum HandleType { case bed, wake }

    private func dragGesture(for handle: HandleType, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                var angle = atan2(dy, dx) + .pi / 2 // convert from SwiftUI coords to our convention
                if angle < 0 { angle += 2 * .pi }

                switch handle {
                case .bed:
                    isDraggingBed = true
                    // Snap bedtime to 15-min increments for smoother feel
                    let mins = SleepCalculator.minutesSinceMidnight(from: angle)
                    let snappedMins = (mins / 15) * 15
                    bedAngle = Double(snappedMins) / 1440.0 * 2.0 * .pi
                case .wake:
                    isDraggingWake = true
                    wakeAngle = angle
                }

                // Check for cycle boundary crossing → haptic
                let newCycles = cycleCount
                if newCycles != lastSnappedCycles {
                    haptic.impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        lastSnappedCycles = newCycles
                    }
                }
            }
            .onEnded { _ in
                isDraggingBed = false
                isDraggingWake = false

                // Snap wake angle to the computed snapped position
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    wakeAngle = snappedWakeAngle
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
            .foregroundColor(.white)
            .padding()
    }
}
