//
//  SleepSliderView.swift
//  Moonbeam
//

import SwiftUI

struct SleepSliderView: View {
    /// Live displayed times, published so alarm creation uses what the dial shows.
    @Binding var publishedBedMinutes: Int
    @Binding var publishedWakeMinutes: Int
    /// Increment to snap the bedtime handle to the current time.
    @Binding var sleepNowTrigger: Int
    private let alarmSet: Bool
    private let isUpdatingAlarm: Bool
    private let alarmAction: () -> Void

    // Plain instance, not @EnvironmentObject — SleepProfile is
    // @AppStorage-backed, so every instance sees the same UserDefaults values.
    private let profile = SleepProfile()
    @EnvironmentObject private var sunTimes: SunTimesService
    @State private var showingLocation = false
    @State private var editingTime: HandleType?
    @State private var pickerDate = Date()
    @State private var usesExactTimes = false
    @State private var bedtimeLocked = false
    @State private var alarmLocked = false
    @State private var wakeByMinutes: Int?

    init(
        publishedBedMinutes: Binding<Int>,
        publishedWakeMinutes: Binding<Int>,
        sleepNowTrigger: Binding<Int>,
        alarmSet: Bool = false,
        isUpdatingAlarm: Bool = false,
        alarmAction: @escaping () -> Void = {}
    ) {
        _publishedBedMinutes = publishedBedMinutes
        _publishedWakeMinutes = publishedWakeMinutes
        _sleepNowTrigger = sleepNowTrigger
        self.alarmSet = alarmSet
        self.isUpdatingAlarm = isUpdatingAlarm
        self.alarmAction = alarmAction
    }

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

    private let ringWidth: CGFloat = 34
    private let dialPadding: CGFloat = 18
    private let handleSize: CGFloat = 44

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private enum HandleType: String, Identifiable {
        case bed, wake
        var id: String { rawValue }
    }

    private var selectedTimes: SleepCalculator.DialTimes {
        if let deadline = wakeByMinutes {
            return SleepCalculator.wakeByTimes(
                bedMinutes: SleepCalculator.minutesSinceMidnight(from: bedAngle),
                deadlineMinutes: deadline, cycleMinutes: profile.remCycleMinutes,
                fallAsleepMinutes: profile.fallAsleepMinutes)
        }
        return SleepCalculator.dialTimes(
            bedMinutes: SleepCalculator.minutesSinceMidnight(from: bedAngle),
            wakeMinutes: SleepCalculator.minutesSinceMidnight(from: wakeAngle),
            cycleMinutes: profile.remCycleMinutes,
            fallAsleepMinutes: profile.fallAsleepMinutes,
            bedLocked: bedtimeLocked, wakeLocked: alarmLocked,
            anchorBed: lastDragged == .bed, exact: usesExactTimes
        )
    }

    private var cycleCount: Int {
        totalSleepMinutes / profile.remCycleMinutes
    }

    private var totalSleepMinutes: Int {
        selectedTimes.sleepMinutes(fallAsleepMinutes: profile.fallAsleepMinutes)
    }

    private var fallAsleepBufferMinutes: Int {
        min(max(0, profile.fallAsleepMinutes), selectedTimes.durationMinutes)
    }

    private var displayBedAngle: Double {
        SleepCalculator.continuousAngle(Double(selectedTimes.bedMinutes) / 1440 * 2 * .pi, near: bedAngle)
    }

    private var displayWakeAngle: Double {
        SleepCalculator.continuousAngle(Double(selectedTimes.wakeMinutes) / 1440 * 2 * .pi, near: wakeAngle)
    }

    private var hasCycleMismatch: Bool {
        ((bedtimeLocked && alarmLocked) || wakeByMinutes != nil) && !selectedTimes.fitsCycles(
            cycleMinutes: profile.remCycleMinutes, fallAsleepMinutes: profile.fallAsleepMinutes)
    }

    private var displayBedMinutes: Int {
        SleepCalculator.minutesSinceMidnight(from: displayBedAngle)
    }

    private var displayWakeMinutes: Int {
        SleepCalculator.minutesSinceMidnight(from: displayWakeAngle)
    }

    var body: some View {
        VStack(spacing: 10) {
            timeLabels
                .fixedSize(horizontal: false, vertical: true)
            dialView
                .frame(maxHeight: .infinity)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        sleepNowTrigger += 1
                    } label: {
                        Label("Sleep Now", systemImage: "moon.zzz.fill")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    Button(action: alarmAction) {
                        Label(alarmSet ? "Delete Alarm" : "Create Alarm",
                              systemImage: alarmSet ? "trash" : "alarm.fill")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .disabled(isUpdatingAlarm)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.glass)
                .controlSize(.small)
                .offset(y: 10)
                Spacer(minLength: 0)
                locationButton
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { publishTimes() }
        .onChange(of: displayBedMinutes) { publishTimes() }
        .onChange(of: displayWakeMinutes) { publishTimes() }
        .onChange(of: sleepNowTrigger) { sleepNow() }
        .sheet(item: $editingTime) { handle in
            NavigationStack {
                DatePicker(handle == .bed ? "Bedtime" : (wakeByMinutes != nil ? "Wake by time" : "Alarm time"), selection: $pickerDate,
                           displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                    .navigationTitle(handle == .bed ? "Set Bedtime" : (wakeByMinutes != nil ? "Set Wake By Time" : "Set Alarm Time"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { editingTime = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                applyExactTime(handle)
                                editingTime = nil
                            }
                        }
                    }
            }
            .presentationDetents([.height(320)])
        }
        .sheet(isPresented: $showingLocation) {
            locationSheet
        }
    }

    private func captureDisplayedTimes() {
        let bed = displayBedAngle
        let wake = displayWakeAngle
        bedAngle = bed
        wakeAngle = wake
    }

    private func beginCycleDrag() {
        captureDisplayedTimes()
        usesExactTimes = false
    }

    private func timeLock(_ title: String, isLocked: Bool, handle: HandleType,
                          minHeight: CGFloat = 44) -> some View {
        Button {
            captureDisplayedTimes()
            usesExactTimes = true
            if handle == .bed {
                bedtimeLocked.toggle()
            } else {
                alarmLocked.toggle()
                if alarmLocked { wakeByMinutes = nil }
            }
            haptic.impactOccurred()
        } label: {
            Label(title, systemImage: isLocked ? "checkmark.square.fill" : "square")
                .font(.caption)
                .foregroundStyle(isLocked ? .white : .white.opacity(0.6))
                .frame(minHeight: minHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isLocked ? "Locked" : "Unlocked")
        .accessibilityHint("Prevents automatic changes. You can still drag or edit this time.")
        .accessibilityAddTraits(isLocked ? .isSelected : [])
    }

    private var wakeByToggle: some View {
        Button {
            captureDisplayedTimes()
            if wakeByMinutes == nil {
                wakeByMinutes = displayWakeMinutes
                alarmLocked = false
            } else {
                wakeByMinutes = nil
                usesExactTimes = true
            }
            haptic.impactOccurred()
        } label: {
            Label("Wake By Mode", systemImage: wakeByMinutes != nil ? "checkmark.square.fill" : "square")
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(wakeByMinutes != nil ? .white : .white.opacity(0.6))
                .frame(minHeight: 22)
        }
        .buttonStyle(.plain)
        .accessibilityValue(wakeByMinutes.map { SleepCalculator.formattedTime(minutesSinceMidnight: $0) } ?? "Off")
        .accessibilityHint("Allows an earlier alarm to complete a REM cycle. Drag or edit the alarm to change the deadline.")
        .accessibilityAddTraits(wakeByMinutes != nil ? .isSelected : [])
    }

    private func timeValueButton(_ handle: HandleType) -> some View {
        let minutes = handle == .bed ? displayBedMinutes : (wakeByMinutes ?? displayWakeMinutes)
        return Button {
            let editMinutes = handle == .wake ? (wakeByMinutes ?? minutes) : minutes
            pickerDate = SleepCalculator.date(fromMinutes: editMinutes, relativeTo: Date())
            editingTime = handle
        } label: {
            Text(SleepCalculator.formattedTime(minutesSinceMidnight: minutes))
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(handle == .bed ? "Edit bedtime" : (wakeByMinutes != nil ? "Edit wake by time" : "Edit alarm time"))
        .accessibilityValue(SleepCalculator.formattedTime(minutesSinceMidnight: minutes))
        .accessibilityHint("Choose an exact time to the minute")
    }

    private func applyExactTime(_ handle: HandleType) {
        captureDisplayedTimes()
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: pickerDate) * 60 + calendar.component(.minute, from: pickerDate)
        let angle = Double(minutes) / 1440 * 2 * .pi
        usesExactTimes = true
        if handle == .bed {
            bedAngle = SleepCalculator.continuousAngle(angle, near: bedAngle)
        } else {
            wakeAngle = SleepCalculator.continuousAngle(angle, near: wakeAngle)
            if wakeByMinutes != nil { wakeByMinutes = minutes }
        }
        publishTimes()
    }

    private var locationButton: some View {
        Button {
            sunTimes.requestLocationDetails()
            showingLocation = true
        } label: {
            Image(systemName: "mappin.and.ellipse")
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Current location")
        .accessibilityHint("Shows your current city or location")
        .padding(4)
    }

    private var locationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.largeTitle)
                        .foregroundStyle(.purple.opacity(0.8))
                        .accessibilityHidden(true)
                    Text(sunTimes.locationName)
                        .font(.title2.weight(.semibold))
                    Text(sunTimes.locationDetails)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let events = sunTimes.sunEvents {
                        HStack(alignment: .top, spacing: 24) {
                            sunEventColumn("Morning", events: [
                                ("Astronomical dawn", events.astronomicalDawn),
                                ("Nautical dawn", events.nauticalDawn),
                                ("Civil dawn", events.civilDawn),
                                ("Sunrise", events.sunrise)
                            ])
                            sunEventColumn("Evening", events: [
                                ("Sunset", events.sunset),
                                ("Civil dusk", events.civilDusk),
                                ("Nautical dusk", events.nauticalDusk),
                                ("Astronomical dusk", events.astronomicalDusk)
                            ])
                        }
                        .padding(.vertical, 8)
                        Text("Local times · \(sunTimes.locationTimeZone.identifier.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("— means no time is available for this date.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        SunAttribution()
                    } else if let error = sunTimes.sunEventsError {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if sunTimes.isLoadingSunEvents {
                        ProgressView("Loading sun times…")
                            .font(.caption)
                    }
                    if sunTimes.isLocating {
                        ProgressView()
                    } else {
                        Button("Refresh Location") {
                            sunTimes.requestLocationDetails()
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background {
                LinearGradient(colors: [Color("MidnightBlue"), Color("DeepSpace")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            .navigationTitle("Your Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingLocation = false }
                }
            }
        }
        .presentationDetents([.height(640), .large])
        .presentationDragIndicator(.visible)
    }


    private func sunEventColumn(_ title: String, events: [(String, Date?)]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            ForEach(0..<events.count, id: \.self) { index in
                let event = events[index]
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let date = event.1 {
                        Text(date, format: Date.FormatStyle(date: .omitted, time: .shortened,
                                                          timeZone: sunTimes.locationTimeZone))
                            .font(.body.weight(.medium).monospacedDigit())
                    } else {
                        Text("—")
                            .accessibilityLabel("Unavailable")
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func publishTimes() {
        publishedBedMinutes = displayBedMinutes
        publishedWakeMinutes = displayWakeMinutes
    }

    // MARK: - Time Labels

    private var timeLabels: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Label("BEDTIME", systemImage: "bed.double.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                timeValueButton(.bed)
                Text(displayBedMinutes >= 720 ? "Tonight" : "Tomorrow")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                timeLock("Fix Bedtime", isLocked: bedtimeLocked, handle: .bed, minHeight: 22)
                    .frame(height: 44, alignment: .top)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 112, height: 1)
            VStack(alignment: .trailing, spacing: 4) {
                Label(wakeByMinutes != nil ? "WAKE BY" : "WAKE UP", systemImage: "alarm.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                timeValueButton(.wake)
                Text((wakeByMinutes ?? displayWakeMinutes) < 720 ? "Tomorrow" : "Today")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                VStack(alignment: .trailing, spacing: 0) {
                    wakeByToggle
                    timeLock("Fix Alarm", isLocked: alarmLocked, handle: .wake, minHeight: 22)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .overlay(alignment: .top) {
            durationLabel
                .frame(width: 112)
                .offset(y: -4)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Duration Label

    private var durationLabel: some View {
        VStack(spacing: 4) {
            Text(SleepCalculator.formattedDuration(minutes: totalSleepMinutes))
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("\(cycleCount) REM cycle\(cycleCount == 1 ? "" : "s")")
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
            Label("Incomplete REM", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(hasCycleMismatch ? 1 : 0)
                .accessibilityHidden(!hasCycleMismatch)
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
                // Recessed groove shadow, drawn beneath the ring so only its
                // edges show beneath the muted sky colors.
                Circle()
                    .stroke(Color.black.opacity(0.35), lineWidth: ringWidth + 8)
                    .blur(radius: 5)
                    .frame(width: midRadius * 2, height: midRadius * 2)
                    .position(center)

                // Fixed background sky gradient ring
                backgroundSkyRing(center: center, radius: midRadius)

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
                    angle: wakeByMinutes.map { Double($0) / 1440 * 2 * .pi } ?? displayWakeAngle,
                    center: center,
                    radius: midRadius,
                    icon: "alarm.fill",
                    isDragging: isDraggingWake
                )
                .gesture(dragGesture(for: .wake, center: center))

                if wakeByMinutes != nil {
                    wakeByMarker(minutes: displayWakeMinutes, center: center, radius: midRadius)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sleepDial")
            .coordinateSpace(name: "sleepDial")
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }

    }

    // MARK: - Background Sky Ring

    private func backgroundSkyRing(center: CGPoint, radius: CGFloat) -> some View {
        let night = Color(red: 0.09, green: 0.07, blue: 0.24)
        let daylight = Color(red: 0.84, green: 0.81, blue: 0.69)
        let events = sunTimes.sunEvents
        let calendar = Calendar.current
        func minutes(_ date: Date?) -> Double? {
            guard let date else { return nil }
            return Double(calendar.component(.hour, from: date) * 60
                          + calendar.component(.minute, from: date))
        }
        func wrapped(_ value: Double) -> Double {
            (value.truncatingRemainder(dividingBy: 1440) + 1440)
                .truncatingRemainder(dividingBy: 1440)
        }

        let sunrise = minutes(events?.sunrise) ?? Double(sunTimes.sunriseMinutes)
        let sunset = sunrise + wrapped((minutes(events?.sunset) ?? Double(sunTimes.sunsetMinutes)) - sunrise)
        let nightLength = 1440 - (sunset - sunrise)
        // Use the outermost twilight boundaries, with a quiet fallback while GPS loads.
        let dawnSpan = minutes(events?.astronomicalDawn).map { wrapped(sunrise - $0) }
            ?? min(90, nightLength / 2)
        let duskSpan = minutes(events?.astronomicalDusk).map { wrapped($0 - sunset) }
            ?? min(90, nightLength / 2)
        let dawn = sunrise - dawnSpan
        let dusk = sunset + duskSpan
        let shoulder = (sunset - sunrise) * 0.18
        let anchors: [(Double, Color)] = [
            (dawn, night),
            (dawn + dawnSpan * 0.55, Color(red: 0.18, green: 0.26, blue: 0.56)),
            (sunrise, Color(red: 0.56, green: 0.74, blue: 0.95)),
            (sunrise + shoulder, daylight),
            (sunset - shoulder, daylight),
            (sunset - shoulder * 0.35, Color(red: 0.98, green: 0.80, blue: 0.52)),
            (sunset, Color(red: 0.94, green: 0.42, blue: 0.40)),
            (sunset + duskSpan * 0.32, Color(red: 0.72, green: 0.26, blue: 0.50)),
            (sunset + duskSpan * 0.64, Color(red: 0.40, green: 0.15, blue: 0.42)),
            (dusk, night), (dawn + 1440, night)
        ]

        func skyColor(at minute: Double) -> Color {
            // Unwrap around dawn so the gradient remains continuous through midnight.
            let time = dawn + wrapped(minute - dawn)
            for index in 1..<anchors.count {
                let (start, from) = anchors[index - 1]
                let (end, to) = anchors[index]
                if time <= end {
                    let fraction = max(0, min(1, (time - start) / max(1, end - start)))
                    return from.mix(with: to, by: fraction)
                }
            }
            return night
        }

        // Include the exact event positions as well as regular samples.
        let samples = Set(Array(stride(from: 0.0, through: 1440.0, by: 15.0))
            + anchors.map { wrapped($0.0) }).sorted()
        let gradient = AngularGradient(
            stops: samples.map { .init(color: skyColor(at: $0), location: $0 / 1440) },
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )

        return Circle()
            .stroke(gradient, lineWidth: ringWidth)
            .saturation(0.5)
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
    }

    // MARK: - Clock Face

    private func clockFace(center: CGPoint, midRadius: CGFloat) -> some View {
        let innerRingEdge = midRadius - ringWidth / 2
        let sunTimeLabelRadius = innerRingEdge - 18

        let sunriseText = SleepCalculator.formattedTime(minutesSinceMidnight: sunTimes.sunriseMinutes)
        let sunsetText = SleepCalculator.formattedTime(minutesSinceMidnight: sunTimes.sunsetMinutes)

        return ZStack {
            hourTickMarks(center: center, midRadius: midRadius)

            // Match each solar event to the same 24-hour angle used by the ring.
            sunTimeLabel(
                time: sunriseText,
                icon: "sunrise.fill",
                iconColor: Color(red: 0.72, green: 0.68, blue: 0.58),
                angle: Double(sunTimes.sunriseMinutes) / 1440 * 2 * .pi - .pi / 2,
                radius: sunTimeLabelRadius,
                center: center
            )

            sunTimeLabel(
                time: sunsetText,
                icon: "sunset.fill",
                iconColor: Color(red: 0.72, green: 0.68, blue: 0.58),
                angle: Double(sunTimes.sunsetMinutes) / 1440 * 2 * .pi - .pi / 2,
                radius: sunTimeLabelRadius,
                center: center
            )

        }
    }

    /// Keep each time on the icon's horizontal baseline, toward the dial center.
    private func sunTimeLabel(
        time: String,
        icon: String,
        iconColor: Color,
        angle: Double,
        radius: CGFloat,
        center: CGPoint
    ) -> some View {
        let iconX = center.x + cos(angle) * radius
        let iconY = center.y + sin(angle) * radius
        let textOffset: CGFloat = cos(angle) >= 0 ? -34 : 34
        return ZStack {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(iconColor)
                .position(x: iconX, y: iconY)
            Text(time)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize()
                .position(x: iconX + textOffset, y: iconY)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(icon == "sunrise.fill" ? "Sunrise" : "Sunset"), \(time)")
    }

    private func hourTickMarks(center: CGPoint, midRadius: CGFloat) -> some View {
        ForEach((0..<24).filter { $0 % 6 != 0 }, id: \.self) { hour in
            hourTick(hour: hour, center: center, midRadius: midRadius)
        }
    }

    private func hourTick(hour: Int, center: CGPoint, midRadius: CGFloat) -> some View {
        let tickAngle = Double(hour) / 24.0 * 2.0 * .pi - .pi / 2
        let tickLength: CGFloat = 5
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
        .stroke(Color.white.opacity(0.15), lineWidth: 1)
    }

    // MARK: - Sleep Arc (Glass Look — Continuous Fill)

    private func sleepArc(center: CGPoint, radius: CGFloat) -> some View {
        let bufferAngle = Double(fallAsleepBufferMinutes) / 1440 * 2 * .pi
        let startSwiftUI = displayBedAngle + bufferAngle - .pi / 2
        let trimEnd = CGFloat(totalSleepMinutes) / 1440

        return ZStack {
            // Bridge the fall-asleep gap along both rims without filling it in.
            if fallAsleepBufferMinutes > 0 {
                ForEach([-1.0, 1.0], id: \.self) { edge in
                    let edgeRadius = radius + CGFloat(edge) * (ringWidth / 2 - 1)
                    Circle()
                        .trim(from: 0, to: CGFloat(fallAsleepBufferMinutes) / 1440)
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: edgeRadius * 2, height: edgeRadius * 2)
                        .rotationEffect(.radians(displayBedAngle - .pi / 2))
                        .position(center)
                }
            }

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
        let trimEnd = CGFloat(selectedTimes.durationMinutes) / 1440

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

        return ForEach(1..<max(1, count), id: \.self) { i in
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

    private func wakeByMarker(minutes: Int, center: CGPoint, radius: CGFloat) -> some View {
        let angle = Double(minutes) / 1440 * 2 * .pi - .pi / 2
        let start = radius + ringWidth / 2 + 10
        let end = start + 11
        let iconRadius = end + 14
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: center.x + cos(angle) * start,
                                     y: center.y + sin(angle) * start))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * end,
                                        y: center.y + sin(angle) * end))
            }
            .stroke(.orange.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            Image(systemName: "alarm.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange.opacity(0.85))
                .overlay(alignment: .top) {
                    Text(SleepCalculator.formattedTime(minutesSinceMidnight: minutes))
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.orange.opacity(0.85))
                        .fixedSize()
                        .offset(y: -18)
                }
                .position(x: center.x + cos(angle) * iconRadius,
                          y: center.y + sin(angle) * iconRadius)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Actual alarm")
        .accessibilityValue(SleepCalculator.formattedTime(minutesSinceMidnight: minutes))
    }

    private func handleView(angle: Double, center: CGPoint, radius: CGFloat, icon: String, isDragging: Bool) -> some View {
        let isFixed = icon == "bed.double.fill" ? bedtimeLocked : alarmLocked
        let swAngle = angle - .pi / 2
        let innerRadius = radius - ringWidth / 2 - 3
        let outerRadius = radius + ringWidth / 2 + 6
        let iconRadius = radius + ringWidth / 2 + 27
        let marker = Path { path in
            path.move(to: CGPoint(x: center.x + cos(swAngle) * innerRadius,
                                  y: center.y + sin(swAngle) * innerRadius))
            path.addLine(to: CGPoint(x: center.x + cos(swAngle) * outerRadius,
                                    y: center.y + sin(swAngle) * outerRadius))
        }

        return ZStack {
            marker
                .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .shadow(color: .black.opacity(0.45), radius: 3)
            // Keep both the line and floating icon easy to grab.
            marker
                .stroke(.white.opacity(0.001), style: StrokeStyle(lineWidth: 26, lineCap: .round))
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .overlay(alignment: .topTrailing) {
                    if isFixed {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .offset(x: 8, y: -3)
                    }
                }
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                .frame(width: handleSize, height: handleSize)
                .contentShape(Circle())
                .scaleEffect(isDragging ? 1.15 : 1.0)
                .opacity(icon == "alarm.fill" && wakeByMinutes != nil ? 0 : 1)
                .position(x: center.x + cos(swAngle) * iconRadius,
                          y: center.y + sin(swAngle) * iconRadius)
        }
        .frame(width: center.x * 2, height: center.y * 2)
        .animation(.spring(response: 0.3), value: isDragging)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(icon == "bed.double.fill" ? "Bedtime" : "Wake up")
        .accessibilityValue(SleepCalculator.formattedTime(
            minutesSinceMidnight: SleepCalculator.minutesSinceMidnight(from: angle))
            + (isFixed ? ", fixed" : ""))
        .accessibilityHint(icon == "alarm.fill" && wakeByMinutes != nil
                           ? "Drag the white bar to change your wake-by deadline"
                           : "Drag to change this time")

    }

    // MARK: - Drag Gesture

    private func dragGesture(for handle: HandleType, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("sleepDial"))
            .onChanged { value in
                if !isDraggingBed && !isDraggingWake { beginCycleDrag() }
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
                    bedAngle = SleepCalculator.continuousAngle(snappedAngle, near: bedAngle)
                case .wake:
                    isDraggingWake = true
                    lastDragged = .wake
                    wakeAngle = SleepCalculator.continuousAngle(snappedAngle, near: wakeAngle)
                    if wakeByMinutes != nil { wakeByMinutes = snappedMins }
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
                guard isDraggingBed || isDraggingWake else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    captureDisplayedTimes()
                }
                isDraggingBed = false
                isDraggingWake = false
            }
    }

    // MARK: - Arc Drag Gesture

    private func arcDragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("sleepDial"))
            .onChanged { value in
                guard !(bedtimeLocked && alarmLocked) else { return }
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                var currentAngle = atan2(dy, dx) + .pi / 2
                if currentAngle < 0 { currentAngle += 2 * .pi }

                if !isDraggingArc {
                    beginCycleDrag()
                    isDraggingArc = true
                    arcDragPreviousAngle = currentAngle
                    return
                }

                var delta = currentAngle - arcDragPreviousAngle
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }

                if !bedtimeLocked {
                    bedAngle += delta
                }
                if !alarmLocked && wakeByMinutes == nil {
                    wakeAngle += delta
                }

                arcDragPreviousAngle = currentAngle
            }
            .onEnded { _ in
                guard isDraggingArc else { return }
                isDraggingArc = false
                let bedMins = SleepCalculator.minutesSinceMidnight(from: bedAngle)
                let snappedBedMins = ((bedMins + 7) / 15) * 15
                let wakeMins = SleepCalculator.minutesSinceMidnight(from: wakeAngle)
                let snappedWakeMins = ((wakeMins + 7) / 15) * 15

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if !bedtimeLocked {
                        bedAngle = SleepCalculator.continuousAngle(
                            Double(snappedBedMins % 1440) / 1440 * 2 * .pi, near: bedAngle)
                    }
                    if !alarmLocked && wakeByMinutes == nil {
                        wakeAngle = SleepCalculator.continuousAngle(
                            Double(snappedWakeMins % 1440) / 1440 * 2 * .pi, near: wakeAngle)
                    }
                    captureDisplayedTimes()
                }
            }
    }

    // MARK: - Sleep Now

    private func sleepNow() {
        beginCycleDrag()
        lastDragged = .bed
        // An exact alarm must not pull "now" onto an earlier cycle boundary.
        usesExactTimes = alarmLocked
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let nowMinutes = hour * 60 + minute

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            bedAngle = SleepCalculator.continuousAngle(
                Double(nowMinutes) / 1440 * 2 * .pi, near: bedAngle)
        }
        haptic.impactOccurred()
    }
}

#Preview {
    @Previewable @State var bed = 22 * 60 + 30
    @Previewable @State var wake = 7 * 60
    @Previewable @State var trigger = 0

    ZStack {
        Color.clear.moonbeamBackground()
        SleepSliderView(
            publishedBedMinutes: $bed,
            publishedWakeMinutes: $wake,
            sleepNowTrigger: $trigger
        )
        .environmentObject(SunTimesService())
        .foregroundColor(.white)
        .padding()
    }
}
