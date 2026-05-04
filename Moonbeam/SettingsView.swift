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

            Text("Adjust your REM cycle length and how long it takes you to fall asleep.")
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
                Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task { await alarmService.requestAuthorization() }
                } label: {
                    Label("Enable Notifications", systemImage: "bell.badge")
                        .font(.subheadline.weight(.medium))
                }
            }

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 8) {
                Text("Alarm Sound")
                    .font(.subheadline.weight(.medium))

                Picker("Sound", selection: $alarmService.alarmSoundName) {
                    ForEach(AlarmService.availableSounds, id: \.name) { sound in
                        Text(sound.label).tag(sound.name)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }

            Text("Moonbeam uses local notifications for alarms. For richer alarm sounds, set a wake-up alarm in the Clock app alongside Moonbeam's notifications.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .moonbeamCard()
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
