//
//  AlarmService.swift
//  Moonbeam
//

import AlarmKit
import SwiftUI
import UserNotifications

/// AlarmKit requires a metadata type; Moonbeam's alarms carry no extra state.
struct MoonbeamAlarmMetadata: AlarmMetadata {
    init() {}
}

@MainActor
final class AlarmService: ObservableObject {
    @Published var isAuthorized: Bool = false

    static let shared = AlarmService()

    private static let alarmIDsKey = "moonbeam.alarmkit.ids"
    private static let snoozeMinutes: TimeInterval = 9 * 60

    private init() {
        checkAuthorization()
    }

    enum AlarmSchedulingError: LocalizedError {
        case notAuthorized
        case nothingToSchedule

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Alarm access is off. Enable it in Settings → Moonbeam."
            case .nothingToSchedule:
                return "All of this plan's nights are in the past. Pick a later flight date."
            }
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            isAuthorized = state == .authorized
        } catch {
            isAuthorized = false
        }

        // Bedtime reminders still arrive as regular notifications.
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    func checkAuthorization() {
        isAuthorized = AlarmManager.shared.authorizationState == .authorized
    }

    private func ensureAuthorized() async -> Bool {
        checkAuthorization()
        if !isAuthorized {
            await requestAuthorization()
        }
        return isAuthorized
    }

    // MARK: - Single Sleep Alarm (home screen)

    func scheduleSleepAlarm(bedMinutes: Int, wakeMinutes: Int, label: String = "Moonbeam") async {
        guard await ensureAuthorized() else { return }

        cancelMoonbeamAlarms()

        let bedDate = nextOccurrence(minutesSinceMidnight: bedMinutes)
        let wakeDate = nextOccurrence(minutesSinceMidnight: wakeMinutes, after: bedDate)

        await scheduleBedtimeReminder(at: bedDate, body: "Your \(label) bedtime is now. Sweet dreams!", id: "moonbeam.bedtime")
        try? await scheduleWakeAlarm(at: wakeDate, title: "Wake Up — \(label)")
    }

    // MARK: - Jet Lag Plan Alarms

    /// Schedules a wake-up alarm (AlarmKit, sounds through Silent mode) and a
    /// bedtime reminder notification for every future night in the plan.
    func scheduleJetLagPlanAlarms(plan: JetLagPlan) async -> Result<Void, Error> {
        guard await ensureAuthorized() else {
            return .failure(AlarmSchedulingError.notAuthorized)
        }

        cancelMoonbeamAlarms()

        let now = Date()
        var scheduledAny = false

        for night in plan.nights {
            guard night.wakeDate > now else { continue }

            do {
                try await scheduleWakeAlarm(
                    at: night.wakeDate,
                    title: "Night \(night.nightIndex + 1) Wake-Up · \(plan.destinationCity)"
                )
            } catch {
                return .failure(error)
            }

            if night.bedDate > now {
                await scheduleBedtimeReminder(
                    at: night.bedDate,
                    body: "Night \(night.nightIndex + 1) of your \(plan.destinationCity) transition. Bedtime is now.",
                    id: "moonbeam.jetlag.bedtime.\(night.nightIndex)"
                )
            }

            scheduledAny = true
        }

        guard scheduledAny else {
            return .failure(AlarmSchedulingError.nothingToSchedule)
        }
        return .success(())
    }

    // MARK: - AlarmKit Wake Alarm

    private func scheduleWakeAlarm(at date: Date, title: String) async throws {
        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "checkmark.circle.fill"
        )
        let snoozeButton = AlarmButton(
            text: "Snooze",
            textColor: .white,
            systemImageName: "zzz"
        )

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let attributes = AlarmAttributes<MoonbeamAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: MoonbeamAlarmMetadata(),
            tintColor: .indigo
        )

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: Self.snoozeMinutes),
            schedule: .fixed(date),
            attributes: attributes
        )

        let id = UUID()
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        rememberAlarmID(id)
    }

    // MARK: - Bedtime Reminder (notification)

    private func scheduleBedtimeReminder(at date: Date, body: String, id: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Time for Bed"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "MOONBEAM_REMINDER"

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cancel

    func cancelMoonbeamAlarms() {
        for idString in UserDefaults.standard.stringArray(forKey: Self.alarmIDsKey) ?? [] {
            if let id = UUID(uuidString: idString) {
                try? AlarmManager.shared.cancel(id: id)
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.alarmIDsKey)
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func cancelAll() {
        cancelMoonbeamAlarms()
    }

    // MARK: - Helpers

    private func rememberAlarmID(_ id: UUID) {
        var ids = UserDefaults.standard.stringArray(forKey: Self.alarmIDsKey) ?? []
        ids.append(id.uuidString)
        UserDefaults.standard.set(ids, forKey: Self.alarmIDsKey)
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
}
