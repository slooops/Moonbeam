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
                    comingSoonSection(
                        "Sleep Debt Tracker", icon: "chart.line.uptrend.xyaxis",
                        description: "Track your accumulated sleep debt and monitor your health."
                    )
                    comingSoonSection(
                        "Wearables Integration", icon: "applewatch",
                        description: "Work with your smartwatch or Oura Ring."
                    )
                    aboutSection
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        comingSoonSection(
            "HomeKit Light Alarm", icon: "lightbulb.fill",
            description: "HomeKit integration for light-based wake-up alarms. Gradually brighten your lights at wake time."
        )
    }

    private func comingSoonSection(_ title: String, icon: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.3))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coming Soon")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moonbeamCard()
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("About", systemImage: "moon.stars.fill")
                .font(.headline)

            Link(destination: URL(string: "https://slooops.com/moonbeam/support")!) {
                Label("Support", systemImage: "questionmark.circle")
                    .font(.subheadline)
            }

            Link(destination: URL(string: "https://slooops.com/moonbeam/privacy")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
                    .font(.subheadline)
            }

            Divider().opacity(0.3)

            Text("Moonbeam \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .moonbeamCard()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(SleepProfile())
}
