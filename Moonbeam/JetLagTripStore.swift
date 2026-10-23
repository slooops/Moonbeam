//
//  JetLagTripStore.swift
//  Moonbeam
//

import Foundation
import SwiftUI

struct JetLagTrip: Identifiable, Codable, Equatable {
    let id: UUID
    var flightDate: Date
    var departureAirport: String
    var arrivalAirport: String
    var departureTime: Date
    var arrivalTime: Date
    var flightNumber: String

    init(
        id: UUID = UUID(),
        flightDate: Date,
        departureAirport: String,
        arrivalAirport: String,
        departureTime: Date,
        arrivalTime: Date,
        flightNumber: String
    ) {
        self.id = id
        self.flightDate = flightDate
        self.departureAirport = departureAirport
        self.arrivalAirport = arrivalAirport
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.flightNumber = flightNumber
    }

    /// Combines the calendar day with the departure clock time for sorting and subtitles.
    var departureSortDate: Date {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: flightDate)
        let h = cal.component(.hour, from: departureTime)
        let m = cal.component(.minute, from: departureTime)
        let s = cal.component(.second, from: departureTime)
        return cal.date(byAdding: DateComponents(hour: h, minute: m, second: s), to: dayStart) ?? dayStart
    }
}

@MainActor
final class JetLagTripStore: ObservableObject {
    @Published private(set) var trips: [JetLagTrip] = []
    @Published private(set) var savedPlans: [JetLagPlan] = []

    private static let storageKey = "jetLagTrips.v1"
    private static let plansStorageKey = "jetLagPlans.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        if let data = defaults.data(forKey: Self.plansStorageKey),
           let plans = try? JSONDecoder().decode([JetLagPlan].self, from: data) {
            savedPlans = plans.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func savePlan(_ plan: JetLagPlan) throws {
        var plans = savedPlans.filter { $0.createdAt != plan.createdAt }
        plans.append(plan)
        plans.sort { $0.createdAt > $1.createdAt }
        let data = try JSONEncoder().encode(plans)
        defaults.set(data, forKey: Self.plansStorageKey)
        savedPlans = plans
    }

    func deletePlan(_ plan: JetLagPlan) throws {
        let plans = savedPlans.filter { $0.createdAt != plan.createdAt }
        let data = try JSONEncoder().encode(plans)
        defaults.set(data, forKey: Self.plansStorageKey)
        savedPlans = plans
    }

    func add(_ trip: JetLagTrip) {
        trips.append(trip)
        trips.sort { $0.departureSortDate > $1.departureSortDate }
        save()
    }

    func deleteTrips(at offsets: IndexSet) {
        trips.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([JetLagTrip].self, from: data)
        else { return }
        trips = decoded.sorted { $0.departureSortDate > $1.departureSortDate }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(trips) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
