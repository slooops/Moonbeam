//
//  SunTimesService.swift
//  Moonbeam
//

import CoreLocation
import MapKit
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

/// The visible credit sunrise-sunset.org requires; its terms allow it on an About screen.
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
    @Published private(set) var locationName = "Current location"
    @Published private(set) var locationDetails = "Finding your location…"
    @Published private(set) var isLocating = false
    @Published private(set) var sunEvents: SunEventTimes?
    @Published private(set) var isLoadingSunEvents = false
    @Published private(set) var sunEventsError: String?
    @Published private(set) var locationTimeZone = TimeZone.current

    private let manager = CLLocationManager()
    private var wantsLocationName = false
    private var geocodingTask: Task<Void, Never>?
    private var sunTimesTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            showLocationUnavailable("Location access is off. Enable it for Moonbeam in Settings to see your current city.")
        @unknown default:
            showLocationUnavailable("Your location is currently unavailable. Please try again.")
        }
    }

    func requestLocationDetails() {
        geocodingTask?.cancel()
        sunTimesTask?.cancel()
        sunEvents = nil
        sunEventsError = nil
        isLoadingSunEvents = true
        wantsLocationName = true
        isLocating = true
        locationName = "Current location"
        locationDetails = "Finding your location…"
        requestLocation()
    }

    private func showLocationUnavailable(_ message: String) {
        geocodingTask?.cancel()
        sunTimesTask?.cancel()
        sunEvents = nil
        isLoadingSunEvents = false
        sunEventsError = nil
        locationName = "Location unavailable"
        locationDetails = message
        isLocating = false
    }

    private func resolveLocationName(_ location: CLLocation) {
        geocodingTask?.cancel()
        geocodingTask = Task {
            let coordinates = String(format: "%.2f°, %.2f°", location.coordinate.latitude, location.coordinate.longitude)
            do {
                guard let request = MKReverseGeocodingRequest(location: location),
                      let place = try await request.mapItems.first else {
                    throw CLError(.geocodeFoundNoResult)
                }
                guard !Task.isCancelled else { return }
                let address = place.addressRepresentations
                locationTimeZone = place.timeZone ?? .current
                locationName = address?.cityName ?? place.name ?? "Current location"
                locationDetails = address?.regionName ?? coordinates
            } catch {
                guard !Task.isCancelled else { return }
                locationName = "Current location"
                locationDetails = "\(coordinates)\nA place name couldn’t be found. Please try again."
            }
            isLocating = false
        }
    }

    private func fetchSunTimes(lat: Double, lng: Double) async {
        guard let url = SunAPI.url(lat: lat, lng: lng) else { return }
        isLoadingSunEvents = true
        sunEventsError = nil

        do {
            let (data, httpResponse) = try await URLSession.shared.data(from: url)
            guard (httpResponse as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let response = try JSONDecoder().decode(SunAPIResponse.self, from: data)
            guard response.status == "OK" else {
                throw URLError(.badServerResponse)
            }
            guard !Task.isCancelled else { return }
            sunEvents = response.results

            let cal = Calendar.current
            if let sunrise = response.results.sunrise {
                sunriseMinutes = cal.component(.hour, from: sunrise) * 60 + cal.component(.minute, from: sunrise)
            }
            if let sunset = response.results.sunset {
                sunsetMinutes = cal.component(.hour, from: sunset) * 60 + cal.component(.minute, from: sunset)
            }
        } catch {
            guard !Task.isCancelled else { return }
            sunEvents = nil
            sunEventsError = "Sun times couldn’t be loaded. Please try refreshing."
        }
        isLoadingSunEvents = false
    }
}

extension SunTimesService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        Task { @MainActor [weak self] in
            if let self, self.wantsLocationName {
                self.resolveLocationName(location)
            }
            guard let self else { return }
            self.sunTimesTask?.cancel()
            self.sunTimesTask = Task {
                await self.fetchSunTimes(lat: lat, lng: lng)
            }
        }
    }

    /// The first `requestLocation()` fails while the permission prompt is
    /// still up, so ask again once the user grants access.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            self?.showLocationUnavailable("Couldn’t get your location. Check Location Services and try again.")
        }
    }
}

private struct SunAPIResponse: Decodable, Sendable {
    let results: SunEventTimes
    let status: String
}

struct SunEventTimes: Decodable, Sendable {
    let sunrise: Date?
    let sunset: Date?
    let civilDawn: Date?
    let civilDusk: Date?
    let nauticalDawn: Date?
    let nauticalDusk: Date?
    let astronomicalDawn: Date?
    let astronomicalDusk: Date?

    private enum CodingKeys: String, CodingKey {
        case sunrise, sunset
        case civilDawn = "civil_twilight_begin"
        case civilDusk = "civil_twilight_end"
        case nauticalDawn = "nautical_twilight_begin"
        case nauticalDusk = "nautical_twilight_end"
        case astronomicalDawn = "astronomical_twilight_begin"
        case astronomicalDusk = "astronomical_twilight_end"
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let formatter = ISO8601DateFormatter()
        func date(_ key: CodingKeys) throws -> Date? {
            guard let text = try values.decodeIfPresent(String.self, forKey: key) else { return nil }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }
        sunrise = try date(.sunrise)
        sunset = try date(.sunset)
        civilDawn = try date(.civilDawn)
        civilDusk = try date(.civilDusk)
        nauticalDawn = try date(.nauticalDawn)
        nauticalDusk = try date(.nauticalDusk)
        astronomicalDawn = try date(.astronomicalDawn)
        astronomicalDusk = try date(.astronomicalDusk)
    }
}
