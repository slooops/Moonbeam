//
//  SleepCalculator.swift
//  Moonbeam
//

import Foundation

enum SleepCalculator {

    // MARK: - Angle ↔ Time (24-hour clock face)
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
