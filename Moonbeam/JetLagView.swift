//
//  JetLagView.swift
//  Moonbeam
//

import SwiftUI

struct JetLagView: View {
    @EnvironmentObject private var sunTimes: SunTimesService
    @EnvironmentObject private var profile: SleepProfile
    @State private var originQuery: String = ""
    @State private var destinationCity: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var plan: JetLagPlan?
    @State private var showingPlan = false

    /// Generic zone name like "Pacific Time (GMT-7)". The identifier's city
    /// ("Los Angeles") would usually be wrong — most users aren't in the city
    /// their timezone is named after.
    private static func timeZoneDisplayName(_ tz: TimeZone) -> String {
        let name = tz.localizedName(for: .generic, locale: .current)
            ?? tz.identifier.split(separator: "/").last.map {
                $0.replacingOccurrences(of: "_", with: " ")
            } ?? tz.identifier
        let hours = tz.secondsFromGMT() / 3600
        return "\(name) (GMT\(hours >= 0 ? "+" : "")\(hours))"
    }

    private var deviceTimeZoneLabel: String {
        Self.timeZoneDisplayName(TimeZone.current)
    }

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            ScrollView {
                VStack(spacing: 20) {
                    tripEntrySection
                    howItWorksSection

                    if let plan = plan {
                        NavigationLink {
                            JetLagPlanView(plan: plan)
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
                JetLagPlanView(plan: plan)
            }
        }
    }

    // MARK: - Trip Entry

    private var tripEntrySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Plan your trip", systemImage: "airplane.departure")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("LEAVING FROM")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(deviceTimeZoneLabel, text: $originQuery)
                    .textInputAutocapitalization(.words)
                    .jetLagFieldStyle()

                Text("Defaults to your device's timezone. Enter a city, airport code, or timezone to override.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("FLYING TO")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("City or airport code (e.g. Tokyo, LHR)", text: $destinationCity)
                    .textInputAutocapitalization(.words)
                    .jetLagFieldStyle()
            }

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

            Text("Plans are built around your usual sleep — \(SleepCalculator.formattedTime(minutesSinceMidnight: profile.idealBedMinutes)) to \(SleepCalculator.formattedTime(minutesSinceMidnight: profile.idealWakeMinutes)). Adjust it in Settings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .moonbeamCard()
    }

    // MARK: - How It Works

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How it works", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                bulletPoint("1", "Enter your destination")
                bulletPoint("2", "We calculate the timezone shift and plan your transition nights")
                bulletPoint("3", "Pick how many nights you have — each one nudges your sleep toward destination time")
                bulletPoint("4", "Set alarms for the whole plan and arrive refreshed")
            }
        }
        .moonbeamCard()
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
            // Origin: device timezone unless the user typed an override.
            let originName: String
            let originOffset: Int
            let originSun: (sunrise: Int, sunset: Int)

            let originInput = originQuery.trimmingCharacters(in: .whitespaces)
            if originInput.isEmpty {
                let tz = TimeZone.current
                originName = tz.localizedName(for: .generic, locale: .current)
                    ?? tz.identifier.split(separator: "/").last.map {
                        $0.replacingOccurrences(of: "_", with: " ")
                    } ?? tz.identifier
                originOffset = tz.secondsFromGMT() / 3600
                // GPS-based sun times from the home dial; same clock as the device.
                originSun = (sunTimes.sunriseMinutes, sunTimes.sunsetMinutes)
            } else {
                let resolved = try await JetLagPlanCalculator.resolvePlace(originInput)
                originName = resolved.name
                originOffset = resolved.offsetHours
                originSun = await JetLagPlanCalculator.fetchSunTimes(
                    lat: resolved.latitude,
                    lng: resolved.longitude,
                    timeZone: resolved.timeZone
                )
            }

            let destination = try await JetLagPlanCalculator.resolvePlace(city)
            let destSun = await JetLagPlanCalculator.fetchSunTimes(
                lat: destination.latitude,
                lng: destination.longitude,
                timeZone: destination.timeZone
            )

            let newPlan = JetLagPlanCalculator.generatePlan(
                originName: originName,
                destinationCity: destination.name,
                nightCount: 3,
                originSunrise: originSun.sunrise,
                originSunset: originSun.sunset,
                destSunrise: destSun.sunrise,
                destSunset: destSun.sunset,
                localOffsetHours: originOffset,
                destOffsetHours: destination.offsetHours,
                idealBedMinutes: profile.idealBedMinutes,
                idealWakeMinutes: profile.idealWakeMinutes
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

private extension View {
    func jetLagFieldStyle() -> some View {
        self
            .font(.body)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
    }
}

#Preview("Jet Lag") {
    NavigationStack {
        JetLagView()
    }
    .environmentObject(SunTimesService())
    .environmentObject(SleepProfile())
}
