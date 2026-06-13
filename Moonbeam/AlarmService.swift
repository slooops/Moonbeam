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

/// A wake alarm Moonbeam has scheduled, with the context AlarmKit itself
/// doesn't store (title, fire time, paired bedtime reminder).
struct ScheduledAlarm: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let fireDate: Date
    /// Identifier of the bedtime reminder notification paired with this alarm.
    let reminderID: String?
}

@MainActor
final class AlarmService: ObservableObject {
    @Published var isAuthorized: Bool = false
    @Published private(set) var scheduledAlarms: [ScheduledAlarm] = []

    static let shared = AlarmService()

    private static let alarmRecordsKey = "moonbeam.alarmkit.records"
    private static let legacyAlarmIDsKey = "moonbeam.alarmkit.ids"
    private static let snoozeMinutes: TimeInterval = 9 * 60

    private init() {
        checkAuthorization()
        loadRecords()
        refreshScheduledAlarms()
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
        try? await scheduleWakeAlarm(at: wakeDate, title: "Wake Up — \(label)", reminderID: "moonbeam.bedtime")
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

            let reminderID = "moonbeam.jetlag.bedtime.\(night.nightIndex)"

            do {
                try await scheduleWakeAlarm(
                    at: night.wakeDate,
                    title: "Night \(night.nightIndex + 1) Wake-Up · \(plan.destinationCity)",
                    reminderID: reminderID
                )
            } catch {
                return .failure(error)
            }

            if night.bedDate > now {
                await scheduleBedtimeReminder(
                    at: night.bedDate,
                    body: "Night \(night.nightIndex + 1) of your \(plan.destinationCity) transition. Bedtime is now.",
                    id: reminderID
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

    private func scheduleWakeAlarm(at date: Date, title: String, reminderID: String? = nil) async throws {
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
        record(ScheduledAlarm(id: id, title: title, fireDate: date, reminderID: reminderID))
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

    /// Turns off a single wake alarm and its paired bedtime reminder.
    func cancelAlarm(id: UUID) {
        try? AlarmManager.shared.cancel(id: id)
        if let reminderID = scheduledAlarms.first(where: { $0.id == id })?.reminderID {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [reminderID])
        }
        scheduledAlarms.removeAll { $0.id == id }
        saveRecords()
    }

    func cancelMoonbeamAlarms() {
        // Cancel everything AlarmKit has for this app, not just our records,
        // so alarms orphaned by older builds get cleaned up too.
        for alarm in (try? AlarmManager.shared.alarms) ?? [] {
            try? AlarmManager.shared.cancel(id: alarm.id)
        }
        for idString in UserDefaults.standard.stringArray(forKey: Self.legacyAlarmIDsKey) ?? [] {
            if let id = UUID(uuidString: idString) {
                try? AlarmManager.shared.cancel(id: id)
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyAlarmIDsKey)
        scheduledAlarms = []
        saveRecords()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func cancelAll() {
        cancelMoonbeamAlarms()
    }

    // MARK: - Alarm Records

    /// Re-syncs our records against what AlarmKit actually has scheduled, so
    /// alarms that already fired (or were stopped from the lock screen) drop
    /// out of the list.
    func refreshScheduledAlarms() {
        guard let active = try? AlarmManager.shared.alarms else { return }
        let activeIDs = Set(active.map(\.id))
        let pruned = scheduledAlarms.filter { activeIDs.contains($0.id) }
        if pruned != scheduledAlarms {
            scheduledAlarms = pruned
            saveRecords()
        }
    }

    private func record(_ alarm: ScheduledAlarm) {
        scheduledAlarms.removeAll { $0.id == alarm.id }
        scheduledAlarms.append(alarm)
        scheduledAlarms.sort { $0.fireDate < $1.fireDate }
        saveRecords()
    }

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: Self.alarmRecordsKey),
              let decoded = try? JSONDecoder().decode([ScheduledAlarm].self, from: data)
        else { return }
        scheduledAlarms = decoded.sorted { $0.fireDate < $1.fireDate }
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(scheduledAlarms) else { return }
        UserDefaults.standard.set(data, forKey: Self.alarmRecordsKey)
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
