//
//  SunTimesService.swift
//  Moonbeam
//

import CoreLocation
import SwiftUI

/// sunrise-sunset.org lookups. Coordinates are rounded to two decimal places
/// (about 1 km) before they leave the device; sun times barely change at that
/// scale, and the service never sees a precise location.
enum SunAPI {
    static let attributionURL = URL(string: "https://sunrise-sunset.org")!

    static func url(lat: Double, lng: Double) -> URL? {
        let lat = String(format: "%.2f", lat)
        let lng = String(format: "%.2f", lng)
        return URL(string: "https://api.sunrise-sunset.org/json?lat=\(lat)&lng=\(lng)&formatted=0")
    }
}

/// The visible link sunrise-sunset.org requires wherever its data is shown.
struct SunAttribution: View {
    var body: some View {
        Link(destination: SunAPI.attributionURL) {
            Text("Sun times by sunrise-sunset.org")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .underline()
        }
    }
}

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
        guard let url = SunAPI.url(lat: lat, lng: lng) else { return }

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

    /// The first `requestLocation()` fails while the permission prompt is
    /// still up, so ask again once the user grants access.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
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
