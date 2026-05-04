//
//  JetLagView.swift
//  Moonbeam
//

import SwiftUI

struct JetLagView: View {
    @EnvironmentObject private var sunTimes: SunTimesService
    @State private var destinationCity: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var plan: JetLagPlan?
    @State private var showingPlan = false

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // Destination entry
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Where are you flying?", systemImage: "airplane.departure")
                            .font(.headline)

                        TextField("Destination city (e.g. Tokyo, London)", text: $destinationCity)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(false)
                            .font(.body)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            )

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await generatePlan() }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Label("Generate Plan", systemImage: "sparkles")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.glass)
                        .disabled(destinationCity.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                    }
                    .moonbeamCard()

                    // How it works
                    VStack(alignment: .leading, spacing: 10) {
                        Label("How it works", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))

                        VStack(alignment: .leading, spacing: 8) {
                            bulletPoint("1", "Enter your destination city")
                            bulletPoint("2", "We calculate the timezone shift and create a 3-night plan")
                            bulletPoint("3", "Each night shifts your sleep closer to destination time")
                            bulletPoint("4", "Set alarms for each night and arrive refreshed")
                        }
                    }
                    .moonbeamCard()

                    // Show current plan if exists
                    if let plan = plan {
                        NavigationLink {
                            JetLagPlanView(plan: plan) { day in
                                Task {
                                    await AlarmService.shared.scheduleJetLagAlarms(
                                        day: day,
                                        nightLabel: "Night \(day.dayIndex + 1)"
                                    )
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Active Plan: \(plan.destinationCity)")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Tap to view your transition plan")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .moonbeamCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Jet Lag")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingPlan) {
            if let plan = plan {
                JetLagPlanView(plan: plan) { day in
                    Task {
                        await AlarmService.shared.scheduleJetLagAlarms(
                            day: day,
                            nightLabel: "Night \(day.dayIndex + 1)"
                        )
                    }
                }
            }
        }
    }

    private func bulletPoint(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Generate Plan

    private func generatePlan() async {
        let city = destinationCity.trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            // Resolve city to timezone and coordinates
            let resolved = try await JetLagPlanCalculator.resolveCity(city)

            // Fetch destination sun times
            let destSun = await JetLagPlanCalculator.fetchSunTimes(lat: resolved.lat, lng: resolved.lng)

            // Get local timezone offset
            let localOffset = TimeZone.current.secondsFromGMT() / 3600

            // Generate plan
            let newPlan = JetLagPlanCalculator.generatePlan(
                destinationCity: resolved.name,
                localSunrise: sunTimes.sunriseMinutes,
                localSunset: sunTimes.sunsetMinutes,
                destSunrise: destSun.sunrise,
                destSunset: destSun.sunset,
                localOffsetHours: localOffset,
                destOffsetHours: resolved.offsetHours
            )

            plan = newPlan
            showingPlan = true
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

#Preview("Jet Lag") {
    NavigationStack {
        JetLagView()
    }
    .environmentObject(SunTimesService())
}
