//
//  SunTimesService.swift
//  Moonbeam
//

import CoreLocation
import MapKit
import SwiftUI

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

    private func updateSunTimes(lat: Double, lng: Double) {
        let events = SolarCalculator.events(latitude: lat, longitude: lng)
        sunEvents = events
        sunEventsError = nil
        isLoadingSunEvents = false

        let cal = Calendar.current
        if let sunrise = events.sunrise {
            sunriseMinutes = cal.component(.hour, from: sunrise) * 60 + cal.component(.minute, from: sunrise)
        }
        if let sunset = events.sunset {
            sunsetMinutes = cal.component(.hour, from: sunset) * 60 + cal.component(.minute, from: sunset)
        }
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
            self?.updateSunTimes(lat: lat, lng: lng)
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
