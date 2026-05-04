//
//  JetLagPlanCalculator.swift
//  Moonbeam
//

import CoreLocation
import Foundation

struct JetLagSleepWindow: Identifiable, Codable {
    let id: UUID
    let bedMinutes: Int
    let wakeMinutes: Int

    init(bedMinutes: Int, wakeMinutes: Int) {
        self.id = UUID()
        self.bedMinutes = ((bedMinutes % 1440) + 1440) % 1440
        self.wakeMinutes = ((wakeMinutes % 1440) + 1440) % 1440
    }

    var durationMinutes: Int {
        var d = wakeMinutes - bedMinutes
        if d <= 0 { d += 1440 }
        return d
    }
}

struct JetLagDayPlan: Identifiable, Codable {
    let id: UUID
    let dayIndex: Int
    let sleepWindow: JetLagSleepWindow
    let sunriseMinutes: Int
    let sunsetMinutes: Int

    init(dayIndex: Int, sleepWindow: JetLagSleepWindow, sunriseMinutes: Int, sunsetMinutes: Int) {
        self.id = UUID()
        self.dayIndex = dayIndex
        self.sleepWindow = sleepWindow
        self.sunriseMinutes = sunriseMinutes
        self.sunsetMinutes = sunsetMinutes
    }
}

struct JetLagPlan: Codable {
    let destinationCity: String
    let localOffsetHours: Int
    let destinationOffsetHours: Int
    let days: [JetLagDayPlan]
    let createdAt: Date
}

enum JetLagPlanCalculator {

    static func generatePlan(
        destinationCity: String,
        localSunrise: Int,
        localSunset: Int,
        destSunrise: Int,
        destSunset: Int,
        localOffsetHours: Int,
        destOffsetHours: Int,
        idealBedMinutes: Int = 22 * 60 + 30,
        idealWakeMinutes: Int = 7 * 60,
        sleepDurationMinutes: Int = 7 * 60 + 30
    ) -> JetLagPlan {
        let tzDiffMinutes = (destOffsetHours - localOffsetHours) * 60

        let currentBed = idealBedMinutes
        let currentWake = idealWakeMinutes

        var days: [JetLagDayPlan] = []

        for i in 0..<3 {
            let fraction = Double(i + 1) / 3.0

            let shiftedBed = currentBed + Int(Double(tzDiffMinutes) * fraction)
            let shiftedWake = currentWake + Int(Double(tzDiffMinutes) * fraction)

            let window = JetLagSleepWindow(bedMinutes: shiftedBed, wakeMinutes: shiftedWake)

            let sr = interpolate(from: localSunrise, to: destSunrise, fraction: fraction)
            let ss = interpolate(from: localSunset, to: destSunset, fraction: fraction)

            days.append(JetLagDayPlan(
                dayIndex: i,
                sleepWindow: window,
                sunriseMinutes: ((sr % 1440) + 1440) % 1440,
                sunsetMinutes: ((ss % 1440) + 1440) % 1440
            ))
        }

        return JetLagPlan(
            destinationCity: destinationCity,
            localOffsetHours: localOffsetHours,
            destinationOffsetHours: destOffsetHours,
            days: days,
            createdAt: Date()
        )
    }

    private static func interpolate(from a: Int, to b: Int, fraction: Double) -> Int {
        var diff = b - a
        if diff > 720 { diff -= 1440 }
        if diff < -720 { diff += 1440 }
        return a + Int(Double(diff) * fraction)
    }

    static func resolveCity(_ city: String) async throws -> (offsetHours: Int, lat: Double, lng: Double, name: String) {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(city)
        guard let place = placemarks.first,
              let tz = place.timeZone,
              let loc = place.location else {
            throw CityResolveError.notFound
        }
        let offsetSeconds = tz.secondsFromGMT()
        let offsetHours = offsetSeconds / 3600
        let displayName = place.locality ?? place.name ?? city
        return (offsetHours, loc.coordinate.latitude, loc.coordinate.longitude, displayName)
    }

    static func fetchSunTimes(lat: Double, lng: Double) async -> (sunrise: Int, sunset: Int) {
        guard let url = URL(string: "https://api.sunrise-sunset.org/json?lat=\(lat)&lng=\(lng)&formatted=0") else {
            return (390, 1200)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SunAPIPublicResponse.self, from: data)
            guard response.status == "OK" else { return (390, 1200) }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var sr = formatter.date(from: response.results.sunrise)
            var ss = formatter.date(from: response.results.sunset)
            if sr == nil || ss == nil {
                formatter.formatOptions = [.withInternetDateTime]
                sr = sr ?? formatter.date(from: response.results.sunrise)
                ss = ss ?? formatter.date(from: response.results.sunset)
            }
            guard let sunrise = sr, let sunset = ss else { return (390, 1200) }

            let cal = Calendar.current
            let srMin = cal.component(.hour, from: sunrise) * 60 + cal.component(.minute, from: sunrise)
            let ssMin = cal.component(.hour, from: sunset) * 60 + cal.component(.minute, from: sunset)
            return (srMin, ssMin)
        } catch {
            return (390, 1200)
        }
    }

    enum CityResolveError: LocalizedError {
        case notFound
        var errorDescription: String? { "Could not find that city. Try a different name." }
    }
}

private struct SunAPIPublicResponse: Codable, Sendable {
    let results: SunAPIPublicResults
    let status: String
}

private struct SunAPIPublicResults: Codable, Sendable {
    let sunrise: String
    let sunset: String
}
