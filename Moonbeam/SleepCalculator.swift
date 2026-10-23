//
//  SleepCalculator.swift
//  Moonbeam
//

import Foundation

enum SleepCalculator {

    struct DialTimes: Equatable {
        let bedMinutes: Int
        let wakeMinutes: Int

        var durationMinutes: Int {
            let duration = (wakeMinutes - bedMinutes + 1440) % 1440
            return duration == 0 ? 1440 : duration
        }

        func sleepMinutes(fallAsleepMinutes: Int) -> Int {
            max(0, durationMinutes - max(0, fallAsleepMinutes))
        }

        func fitsCycles(cycleMinutes: Int, fallAsleepMinutes: Int) -> Bool {
            let sleep = durationMinutes - fallAsleepMinutes
            return cycleMinutes > 0 && sleep >= cycleMinutes && sleep % cycleMinutes == 0
        }
    }

    static func dialTimes(bedMinutes: Int, wakeMinutes: Int, cycleMinutes: Int,
                          fallAsleepMinutes: Int, bedLocked: Bool, wakeLocked: Bool,
                          anchorBed: Bool, exact: Bool) -> DialTimes {
        let original = DialTimes(bedMinutes: bedMinutes, wakeMinutes: wakeMinutes)
        if exact || (bedLocked && wakeLocked) { return original }
        let duration = snapDuration(rawMinutes: Double(original.durationMinutes), cycleMinutes: cycleMinutes)
            + fallAsleepMinutes
        if bedLocked || (!wakeLocked && anchorBed) {
            return DialTimes(bedMinutes: bedMinutes, wakeMinutes: (bedMinutes + duration) % 1440)
        }
        return DialTimes(bedMinutes: (wakeMinutes - duration + 1440) % 1440, wakeMinutes: wakeMinutes)
    }

    /// Choose the latest complete cycle ending at or before the wake deadline.
    /// If even one cycle cannot fit, preserve the requested window so the UI can warn.
    static func wakeByTimes(bedMinutes: Int, deadlineMinutes: Int, cycleMinutes: Int,
                            fallAsleepMinutes: Int) -> DialTimes {
        let window = DialTimes(bedMinutes: bedMinutes, wakeMinutes: deadlineMinutes)
        guard cycleMinutes > 0 else { return window }
        let buffer = max(0, fallAsleepMinutes)
        let cycles = (window.durationMinutes - buffer) / cycleMinutes
        guard cycles >= 1 else { return window }
        let duration = buffer + cycles * cycleMinutes
        return DialTimes(bedMinutes: bedMinutes, wakeMinutes: (bedMinutes + duration) % 1440)
    }

    // MARK: - Angle ↔ Time (24-hour clock face)

    /// Keep equivalent clock positions on the nearest turn for smooth animation at midnight.
    static func continuousAngle(_ angle: Double, near reference: Double) -> Double {
        let turn = 2 * Double.pi
        return angle + ((reference - angle) / turn).rounded() * turn
    }
    // 12 AM at top (0°/360°), 6 AM at right (90°), 12 PM at bottom (180°), 6 PM at left (270°)

    /// Convert a Date's time-of-day into an angle on the 24-hour dial (in radians).
    static func angle(for date: Date) -> Double {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let totalMinutes = Double(hour * 60 + minute)
        // 1440 minutes in 24 hours → full circle
        return (totalMinutes / 1440.0) * 2.0 * .pi
    }

    /// Convert an angle (radians, 0 = 12 AM top) back to minutes-since-midnight.
    static func minutesSinceMidnight(from angle: Double) -> Int {
        var normalized = angle.truncatingRemainder(dividingBy: 2.0 * .pi)
        if normalized < 0 { normalized += 2.0 * .pi }
        let totalMinutes = (normalized / (2.0 * .pi)) * 1440.0
        return Int(totalMinutes.rounded()) % 1440
    }

    /// Build a Date for today (or tomorrow) from minutes-since-midnight, anchored to a reference date.
    static func date(fromMinutes minutes: Int, relativeTo reference: Date) -> Date {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: reference)
        return cal.date(byAdding: .minute, value: minutes, to: startOfDay)!
    }

    // MARK: - Snapping

    /// Given a raw duration in minutes between bedtime and wake-up, snap to the nearest
    /// whole number of REM cycles (in minutes). Returns the snapped sleep duration (excluding fall-asleep buffer).
    static func snapDuration(rawMinutes: Double, cycleMinutes: Int) -> Int {
        let cycles = max(1, min(SleepProfile.maxCycles, Int((rawMinutes / Double(cycleMinutes)).rounded())))
        return cycles * cycleMinutes
    }

    /// Number of complete REM cycles that fit in a given minute duration.
    static func cycleCount(sleepMinutes: Int, cycleMinutes: Int) -> Int {
        guard cycleMinutes > 0 else { return 0 }
        return max(1, min(SleepProfile.maxCycles, sleepMinutes / cycleMinutes))
    }

    // MARK: - Duration helpers

    /// Compute the positive minute-duration between a bedtime angle and wake angle on a 24-hour dial.
    /// Handles wrapping past midnight.
    static func durationMinutes(bedAngle: Double, wakeAngle: Double) -> Double {
        var diff = wakeAngle - bedAngle
        if diff <= 0 { diff += 2.0 * .pi }
        return (diff / (2.0 * .pi)) * 1440.0
    }

    /// Formatted duration string like "7 hr 30 min"
    static func formattedDuration(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 {
            return "\(h) hr \(m) min"
        } else if h > 0 {
            return "\(h) hr"
        } else {
            return "\(m) min"
        }
    }

    /// Formatted time string from minutes-since-midnight.
    static func formattedTime(minutesSinceMidnight mins: Int) -> String {
        let h24 = (mins / 60) % 24
        let m = mins % 60
        let period = h24 < 12 ? "AM" : "PM"
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return String(format: "%d:%02d %@", h12, m, period)
    }
}
