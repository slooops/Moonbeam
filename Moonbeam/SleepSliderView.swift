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

    // The "display" angles — whichever handle is being dragged stays put,
    // the other snaps to the nearest whole-cycle position.
    private var displayBedAngle: Double {
        if lastDragged == .wake {
            // Wake is the anchor; compute bed from wake
            let wakeMins = SleepCalculator.minutesSinceMidnight(from: wakeAngle)
            let bedMins = (wakeMins - totalSleepMinutes + 1440) % 1440
            return Double(bedMins) / 1440.0 * 2.0 * .pi
        }
        return bedAngle
    }

    private var displayWakeAngle: Double {
        if lastDragged == .bed {
            // Bed is the anchor; compute wake from bed
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
                // 3D track ring — layered for depth
                // Outer shadow (recessed groove)
                Circle()
                    .stroke(Color.black.opacity(0.4), lineWidth: ringWidth + 4)
                    .blur(radius: 4)
                    .frame(width: midRadius * 2, height: midRadius * 2)
                    .position(center)

                // Base ring
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: ringWidth)
                    .frame(width: midRadius * 2, height: midRadius * 2)
                    .position(center)

                // Inner edge highlight (top-lit bevel)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.12), .clear, .clear, .white.opacity(0.04)],
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
                            colors: [.clear, .black.opacity(0.15), .black.opacity(0.2), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: midRadius * 2 - ringWidth + 2, height: midRadius * 2 - ringWidth + 2)
                    .position(center)

                // Clock tick marks & labels
                clockFace(center: center, midRadius: midRadius)

                // Filled sleep arc
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

    // MARK: - Clock Face

    private func clockFace(center: CGPoint, midRadius: CGFloat) -> some View {
        // Labels sit inside the ring, icons sit further in near center
        let innerRingEdge = midRadius - ringWidth / 2
        let labelRadius = innerRingEdge - 16
        let iconRadius = innerRingEdge - 40

        return ZStack {
            hourTickMarks(center: center, midRadius: midRadius)

            // Cardinal labels — inside the ring
            clockLabel("12AM", angle: -.pi / 2, radius: labelRadius, center: center)
            clockLabel("6AM", angle: 0, radius: labelRadius, center: center)
            clockLabel("12PM", angle: .pi / 2, radius: labelRadius, center: center)
            clockLabel("6PM", angle: .pi, radius: labelRadius, center: center)

            // Moon at top (12 AM) — well inside the dial
            Image(systemName: "moon.fill")
                .font(.system(size: 16))
                .foregroundStyle(.indigo.opacity(0.7))
                .position(
                    x: center.x,
                    y: center.y - iconRadius
                )

            // Sun at bottom (12 PM) — well inside the dial
            Image(systemName: "sun.max.fill")
                .font(.system(size: 16))
                .foregroundStyle(.yellow.opacity(0.7))
                .position(
                    x: center.x,
                    y: center.y + iconRadius
                )
        }
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

    // MARK: - Sleep Arc

    private func sleepArc(center: CGPoint, radius: CGFloat) -> some View {
        // Convert from our 24-hr convention (0 = 12AM top) to SwiftUI angles (0 = right)
        let startSwiftUI = displayBedAngle - .pi / 2
        let endSwiftUI = displayWakeAngle - .pi / 2

        // Arc span — always positive, handles wrapping past 6 AM (0°)
        var arcSpan = endSwiftUI - startSwiftUI
        if arcSpan <= 0 { arcSpan += 2 * .pi }

        // Trim fraction: what portion of the circle the arc covers
        let trimEnd = CGFloat(arcSpan / (2 * .pi))

        // Sunset -> midnight -> sunrise color stops
        let gradientColors: [Color] = [
            Color(red: 0.95, green: 0.45, blue: 0.20),  // sunset orange
            Color(red: 0.85, green: 0.28, blue: 0.35),  // warm rose
            Color(red: 0.65, green: 0.22, blue: 0.55),  // plum
            Color(red: 0.45, green: 0.20, blue: 0.65),  // purple
            Color(red: 0.35, green: 0.25, blue: 0.70),  // deep violet (midnight)
            Color(red: 0.30, green: 0.30, blue: 0.72),  // midnight blue-violet
            Color(red: 0.25, green: 0.38, blue: 0.75),  // deep blue
            Color(red: 0.25, green: 0.50, blue: 0.80),  // pre-dawn blue
            Color(red: 0.35, green: 0.65, blue: 0.85),  // morning sky
            Color(red: 0.55, green: 0.78, blue: 0.60),  // dawn green-gold
            Color(red: 0.85, green: 0.75, blue: 0.35),  // sunrise amber
        ]

        // Gradient from 0 to arcSpan — never crosses the 0°/360° seam
        let gradient = AngularGradient(
            colors: gradientColors,
            center: .center,
            startAngle: .zero,
            endAngle: .radians(arcSpan)
        )

        return ZStack {
            // Glow layer behind the arc for depth
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(gradient, style: StrokeStyle(lineWidth: ringWidth + 12, lineCap: .round))
                .blur(radius: 10)
                .opacity(0.35)
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.radians(startSwiftUI))
                .position(center)

            // Main arc — sunset at bedtime -> midnight -> sunrise at wake
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(gradient, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.radians(startSwiftUI))
                .position(center)

            // Top highlight on the arc for 3D roundness
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    style: StrokeStyle(lineWidth: ringWidth - 8, lineCap: .round)
                )
                .frame(width: radius * 2, height: radius * 2)
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
                var angle = atan2(dy, dx) + .pi / 2 // convert from SwiftUI coords to our convention
                if angle < 0 { angle += 2 * .pi }

                // Both handles get 15-min granular control
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

                // Check for cycle boundary crossing -> haptic
                let newCycles = cycleCount
                if newCycles != lastSnappedCycles {
                    haptic.impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        lastSnappedCycles = newCycles
                    }
                }
            }
            .onEnded { _ in
                // Sync both raw angles to their display (snapped) positions
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    bedAngle = displayBedAngle
                    wakeAngle = displayWakeAngle
                }
                isDraggingBed = false
                isDraggingWake = false
            }
    }

    // MARK: - Arc Drag Gesture (whole-window slide)

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

                // Compute angular delta, clamped to avoid big jumps across 0/2pi
                var delta = currentAngle - arcDragPreviousAngle
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }

                // Shift both angles continuously — no per-frame snapping
                bedAngle = (bedAngle + delta).truncatingRemainder(dividingBy: 2 * .pi)
                wakeAngle = (wakeAngle + delta).truncatingRemainder(dividingBy: 2 * .pi)
                if bedAngle < 0 { bedAngle += 2 * .pi }
                if wakeAngle < 0 { wakeAngle += 2 * .pi }

                arcDragPreviousAngle = currentAngle
            }
            .onEnded { _ in
                isDraggingArc = false
                // Snap to 15-min grid on release
                let bedMins = SleepCalculator.minutesSinceMidnight(from: bedAngle)
                let snappedBedMins = ((bedMins + 7) / 15) * 15  // round to nearest
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
            .foregroundColor(.white)
            .padding()
    }
}
