//
//  SleepProfileView.swift
//  Moonbeam
//

import SwiftUI

struct SleepProfileView: View {
    @EnvironmentObject private var profile: SleepProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.moonbeamBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        // REM Cycle Length
                        VStack(alignment: .leading, spacing: 12) {
                            Label("REM Cycle Length", systemImage: "brain.head.profile")
                                .font(.headline)

                            Stepper(
                                "\(profile.remCycleMinutes) minutes",
                                value: $profile.remCycleMinutes,
                                in: 75...120,
                                step: 5
                            )
                            .font(.body.monospacedDigit())

                            Text("Research suggests most people cycle through REM sleep every 90 minutes. Adjust if your sleep patterns differ.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .moonbeamCard()

                        // Fall Asleep Time
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Fall Asleep Time", systemImage: "clock.fill")
                                .font(.headline)

                            Stepper(
                                "\(profile.fallAsleepMinutes) minutes",
                                value: $profile.fallAsleepMinutes,
                                in: 0...45,
                                step: 5
                            )
                            .font(.body.monospacedDigit())

                            Text("Most people fall asleep in 10\u{2013}20 minutes. This buffer is added to your bedtime calculation.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .moonbeamCard()

                        // Info section
                        VStack(alignment: .leading, spacing: 8) {
                            Label("About REM Sleep", systemImage: "info.circle.fill")
                                .font(.headline)

                            Text("Each sleep cycle consists of light sleep, deep sleep, and REM (rapid eye movement) sleep. Waking at the end of a complete cycle helps you feel more refreshed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .moonbeamCard()
                    }
                    .padding()
                }
            }
            .navigationTitle("Sleep Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SleepProfileView()
        .environmentObject(SleepProfile())
}
