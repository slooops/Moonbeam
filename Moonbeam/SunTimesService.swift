//
//  SunTimesService.swift
//  Moonbeam
//

import CoreLocation
import SwiftUI

@MainActor
final class SunTimesService: NSObject, ObservableObject {
    @Published var sunriseMinutes: Int = 390   // 6:30 AM default
    @Published var sunsetMinutes: Int = 1200   // 8:00 PM default

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    private func fetchSunTimes(lat: Double, lng: Double) async {
        guard let url = URL(string: "https://api.sunrise-sunset.org/json?lat=\(lat)&lng=\(lng)&formatted=0") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SunAPIResponse.self, from: data)

            guard response.status == "OK" else { return }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var sunriseDate = formatter.date(from: response.results.sunrise)
            var sunsetDate = formatter.date(from: response.results.sunset)

            if sunriseDate == nil || sunsetDate == nil {
                formatter.formatOptions = [.withInternetDateTime]
                sunriseDate = sunriseDate ?? formatter.date(from: response.results.sunrise)
                sunsetDate = sunsetDate ?? formatter.date(from: response.results.sunset)
            }

            guard let sr = sunriseDate, let ss = sunsetDate else { return }

            let cal = Calendar.current
            sunriseMinutes = cal.component(.hour, from: sr) * 60 + cal.component(.minute, from: sr)
            sunsetMinutes = cal.component(.hour, from: ss) * 60 + cal.component(.minute, from: ss)
        } catch {
            // Use defaults
        }
    }
}

extension SunTimesService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        Task { @MainActor [weak self] in
            await self?.fetchSunTimes(lat: lat, lng: lng)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Use defaults
    }
}

private struct SunAPIResponse: Codable, Sendable {
    let results: SunAPIResults
    let status: String
}

private struct SunAPIResults: Codable, Sendable {
    let sunrise: String
    let sunset: String
}
