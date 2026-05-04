//
//  CycleTimerView.swift
//  Moonbeam
//

import SwiftUI

struct CycleTimerView: View {
    @EnvironmentObject private var profile: SleepProfile
    @State private var showingProfile = false
    @State private var slider = SleepSliderView()
    @State private var alarmSet = false

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        slider
                    }
                    .moonbeamCard()

                    HStack(spacing: 14) {
                        Button {
                            slider.sleepNow()
                        } label: {
                            Label("Sleep Now", systemImage: "moon.zzz.fill")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.glass)

                        Button {
                            Task {
                                await AlarmService.shared.scheduleSleepAlarm(
                                    bedMinutes: slider.currentBedMinutes,
                                    wakeMinutes: slider.currentWakeMinutes,
                                    label: "Sleep Cycle"
                                )
                                withAnimation { alarmSet = true }
                                try? await Task.sleep(for: .seconds(3))
                                withAnimation { alarmSet = false }
                            }
                        } label: {
                            Label(
                                alarmSet ? "Alarm Set" : "Set Alarm",
                                systemImage: alarmSet ? "checkmark.circle.fill" : "alarm.fill"
                            )
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                    Text("Moonbeam")
                }
                .font(.headline)
                .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CycleTimerView()
    }
    .environmentObject(SleepProfile())
    .environmentObject(SunTimesService())
}
