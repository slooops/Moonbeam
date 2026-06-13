//
//  SettingsView.swift
//  Moonbeam
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var profile: SleepProfile
    @ObservedObject private var alarmService = AlarmService.shared

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            ScrollView {
                VStack(spacing: 20) {
                    sleepProfileSection
                    alarmSection
                    homeKitSection
                    sonosSection
                }
                .padding()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sleep Profile

    private var sleepProfileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sleep Profile", systemImage: "brain.head.profile")
                .font(.headline)

            Stepper(
                "REM Cycle: \(profile.remCycleMinutes) min",
                value: $profile.remCycleMinutes,
                in: 75...120,
                step: 5
            )
            .font(.body.monospacedDigit())

            Stepper(
                "Fall Asleep: \(profile.fallAsleepMinutes) min",
                value: $profile.fallAsleepMinutes,
                in: 0...45,
                step: 5
            )
            .font(.body.monospacedDigit())

            Divider().opacity(0.3)

            HStack {
                Text("Usual Bedtime")
                Spacer()
                DatePicker("", selection: timeBinding($profile.idealBedMinutes), displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            HStack {
                Text("Usual Wake-Up")
                Spacer()
                DatePicker("", selection: timeBinding($profile.idealWakeMinutes), displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            Text("Adjust your REM cycle length and how long it takes you to fall asleep. Your usual sleep window sets how much sleep jet lag plans schedule each night.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .moonbeamCard()
    }

    // MARK: - Alarm Settings

    private var alarmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Alarms & Notifications", systemImage: "alarm.fill")
                .font(.headline)

            if alarmService.isAuthorized {
                Label("Alarm access granted", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task { await alarmService.requestAuthorization() }
                } label: {
                    Label("Enable Alarms", systemImage: "bell.badge")
                        .font(.subheadline.weight(.medium))
                }
            }

            if !alarmService.scheduledAlarms.isEmpty {
                Divider().opacity(0.3)

                Text("UPCOMING ALARMS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(alarmService.scheduledAlarms) { alarm in
                    alarmRow(alarm)
                }

                Button(role: .destructive) {
                    withAnimation { alarmService.cancelMoonbeamAlarms() }
                } label: {
                    Label("Cancel All Alarms", systemImage: "bell.slash.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
            }

            Text("Wake-up alarms are real system alarms — they sound even in Silent mode, with full-screen snooze and stop. Bedtime reminders arrive as notifications.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .moonbeamCard()
        .onAppear { alarmService.refreshScheduledAlarms() }
    }

    private func alarmRow(_ alarm: ScheduledAlarm) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "alarm.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(alarm.fireDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation { alarmService.cancelAlarm(id: alarm.id) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(alarm.title)")
        }
        .padding(.vertical, 2)
    }

    /// Bridges minutes-since-midnight storage to a DatePicker's Date binding.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let cal = Calendar.current
                minutes.wrappedValue = cal.component(.hour, from: newDate) * 60 + cal.component(.minute, from: newDate)
            }
        )
    }

    // MARK: - HomeKit

    private var homeKitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("HomeKit Light Alarm", systemImage: "lightbulb.fill")
                .font(.headline)

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Coming Soon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("HomeKit integration for light-based wake-up alarms. Gradually brighten your lights at wake time.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .moonbeamCard()
    }

    // MARK: - Sonos

    private var sonosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sonos Integration", systemImage: "hifispeaker.2.fill")
                .font(.headline)

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Coming Soon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Wake up to your favorite music on your Sonos speakers.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .moonbeamCard()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(SleepProfile())
}
