//
//  AlarmService.swift
//  Moonbeam
//

import UserNotifications
import SwiftUI

@MainActor
final class AlarmService: ObservableObject {
    @Published var isAuthorized: Bool = false
    @AppStorage("alarmSoundName") var alarmSoundName: String = "default"

    static let shared = AlarmService()

    private init() {
        Task { await checkAuthorization() }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule Sleep Alarm

    func scheduleSleepAlarm(bedMinutes: Int, wakeMinutes: Int, label: String = "Moonbeam") async {
        if !isAuthorized {
            await requestAuthorization()
        }
        guard isAuthorized else { return }

        let center = UNUserNotificationCenter.current()

        // Remove previous Moonbeam alarms
        center.removePendingNotificationRequests(withIdentifiers: [
            "moonbeam.bedtime", "moonbeam.wakeup"
        ])

        // Bedtime notification
        let bedContent = UNMutableNotificationContent()
        bedContent.title = "Time for Bed"
        bedContent.body = "Your \(label) bedtime is now. Sweet dreams!"
        bedContent.sound = .default
        bedContent.categoryIdentifier = "MOONBEAM_ALARM"

        let bedDate = nextOccurrence(minutesSinceMidnight: bedMinutes)
        let bedTrigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: bedDate),
            repeats: false
        )
        let bedRequest = UNNotificationRequest(identifier: "moonbeam.bedtime", content: bedContent, trigger: bedTrigger)

        // Wake-up notification
        let wakeContent = UNMutableNotificationContent()
        wakeContent.title = "Wake Up!"
        wakeContent.body = "Rise and shine — your \(label) alarm is going off."
        wakeContent.sound = alarmSound
        wakeContent.categoryIdentifier = "MOONBEAM_ALARM"

        let wakeDate = nextOccurrence(minutesSinceMidnight: wakeMinutes, after: bedDate)
        let wakeTrigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: wakeDate),
            repeats: false
        )
        let wakeRequest = UNNotificationRequest(identifier: "moonbeam.wakeup", content: wakeContent, trigger: wakeTrigger)

        try? await center.add(bedRequest)
        try? await center.add(wakeRequest)
    }

    // MARK: - Schedule Jet Lag Alarms

    func scheduleJetLagAlarms(day: JetLagDayPlan, nightLabel: String) async {
        await scheduleSleepAlarm(
            bedMinutes: day.sleepWindow.bedMinutes,
            wakeMinutes: day.sleepWindow.wakeMinutes,
            label: "Jet Lag \(nightLabel)"
        )

        // Schedule a follow-up notification for the next morning
        if day.dayIndex < 2 {
            await scheduleFollowUpReminder(afterWakeMinutes: day.sleepWindow.wakeMinutes, nextNight: day.dayIndex + 2)
        }
    }

    private func scheduleFollowUpReminder(afterWakeMinutes: Int, nextNight: Int) async {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Set Tonight's Jet Lag Alarms"
        content.body = "Open Moonbeam to set your Night \(nextNight) transition alarms."
        content.sound = .default
        content.categoryIdentifier = "MOONBEAM_REMINDER"

        let reminderMinutes = (afterWakeMinutes + 120) % 1440
        let reminderDate = nextOccurrence(minutesSinceMidnight: reminderMinutes)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: "moonbeam.jetlag.reminder.\(nextNight)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Cancel All

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Helpers

    private var alarmSound: UNNotificationSound {
        if alarmSoundName == "default" {
            return .default
        }
        return UNNotificationSound(named: UNNotificationSoundName(alarmSoundName))
    }

    private func nextOccurrence(minutesSinceMidnight mins: Int, after: Date? = nil) -> Date {
        let cal = Calendar.current
        let ref = after ?? Date()
        let h = mins / 60
        let m = mins % 60

        var date = cal.date(bySettingHour: h, minute: m, second: 0, of: ref)!
        if date <= ref {
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        return date
    }

    // MARK: - Available Sounds

    static let availableSounds: [(name: String, label: String)] = [
        ("default", "Default"),
        ("Alarm", "Classic Alarm"),
        ("Beacon", "Beacon"),
        ("Bulletin", "Bulletin"),
        ("Bamboo", "Bamboo"),
        ("Chime", "Chime"),
        ("Circuit", "Circuit"),
        ("Cosmic", "Cosmic"),
    ]
}
