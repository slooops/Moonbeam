//
//  CycleTimerView.swift
//  Moonbeam
//

import SwiftUI

struct CycleTimerView: View {
    @State private var bedMinutes = 22 * 60 + 30
    @State private var wakeMinutes = 7 * 60
    @State private var sleepNowTrigger = 0
    @State private var isUpdatingAlarm = false
    @State private var schedulingError: String?
    @ObservedObject private var alarms = AlarmService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 12) {
                    SleepSliderView(
                        publishedBedMinutes: $bedMinutes,
                        publishedWakeMinutes: $wakeMinutes,
                        sleepNowTrigger: $sleepNowTrigger,
                        alarmSet: homeAlarm != nil,
                        isUpdatingAlarm: isUpdatingAlarm
                    ) {
                        guard !isUpdatingAlarm else { return }
                        let alarmToDelete = homeAlarm
                        isUpdatingAlarm = true
                        Task {
                            defer { isUpdatingAlarm = false }
                            if let alarmToDelete {
                                do {
                                    try alarms.deleteAlarm(id: alarmToDelete.id)
                                } catch {
                                    schedulingError = error.localizedDescription
                                }
                            } else {
                                let result = await alarms.scheduleSleepAlarm(
                                    bedMinutes: bedMinutes,
                                    wakeMinutes: wakeMinutes,
                                    label: "Sleep Cycle"
                                )
                                if case .failure(let error) = result {
                                    schedulingError = error.localizedDescription
                                }
                            }
                        }
                    }
                    .moonbeamCard()
                    .frame(maxHeight: min(geometry.size.width + 170, geometry.size.height * 0.79))

                    tomorrowAlarms
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { alarms.checkAuthorization(); alarms.refreshScheduledAlarms() }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                alarms.checkAuthorization()
                alarms.refreshScheduledAlarms()
            }
        }
        .task { await alarms.observeAlarmChanges() }
        .alert("Couldn’t update alarm", isPresented: Binding(
            get: { schedulingError != nil },
            set: { if !$0 { schedulingError = nil } }
        )) {
            Button("OK", role: .cancel) { schedulingError = nil }
        } message: {
            Text(schedulingError ?? "Please try again.")
        }

    }

    private var homeAlarm: ScheduledAlarm? {
        alarms.scheduledAlarms.first {
            $0.title == "Wake Up — Sleep Cycle" && $0.fireDate > Date()
        }
    }

    private var tomorrowAlarms: some View {
        let upcoming = ScheduledAlarm.forTomorrow(alarms.scheduledAlarms)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tomorrow’s alarms")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Moonbeam")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if upcoming.isEmpty {
                Text(alarms.isAuthorized ? "No alarms set for tomorrow." : "Create an alarm to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcoming) { alarm in
                    HStack(spacing: 10) {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(.secondary)
                        Text(alarm.fireDate, style: .time)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        Spacer()
                        Text(alarm.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text("Other alarms created in iOS are not visible here")
                .font(.caption2)
                .foregroundStyle(.tertiary)

        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
    }

}

#Preview {
    NavigationStack {
        CycleTimerView()
    }
    .environmentObject(SleepProfile())
    .environmentObject(SunTimesService())
}
