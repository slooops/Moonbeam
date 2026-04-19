//
//  JetLagView.swift
//  Moonbeam
//

import SwiftUI

struct JetLagView: View {
    @EnvironmentObject private var tripStore: JetLagTripStore
    @State private var showingFlightEntry = false

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            if tripStore.trips.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your trips", systemImage: "airplane")
                                .font(.headline)
                            Text("Add a flight to start planning light exposure and sleep shifts.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .moonbeamCard()
                    }
                    .padding()
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your trips", systemImage: "airplane")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.top, 8)

                    List {
                        ForEach(tripStore.trips) { trip in
                            JetLagTripRow(trip: trip)
                                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: tripStore.deleteTrips)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .navigationTitle("Jet Lag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFlightEntry = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .glassEffect(.regular.tint(Color("DeepSpace").opacity(0.55)), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add flight")
            }
        }
        .sheet(isPresented: $showingFlightEntry) {
            FlightDetailsEntryView()
                .environmentObject(tripStore)
        }
    }
}

private struct JetLagTripRow: View {
    let trip: JetLagTrip

    private var routeTitle: String {
        let d = trip.departureAirport
        let a = trip.arrivalAirport
        switch (d.isEmpty, a.isEmpty) {
        case (false, false): return "\(d) → \(a)"
        case (false, true): return d
        case (true, false): return a
        case (true, true): return "Flight"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(routeTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text(trip.flightDate, format: .dateTime.weekday(.wide).month(.abbreviated).day().year())
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text("Out \(trip.departureTime, format: .dateTime.hour().minute())")
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("In \(trip.arrivalTime, format: .dateTime.hour().minute())")
            }
            .font(.subheadline.weight(.medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.88))

            if !trip.flightNumber.isEmpty {
                Text(trip.flightNumber)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .glassEffect(.regular.tint(Color("DeepSpace").opacity(0.5)), in: .rect(cornerRadius: 26))
    }
}

private struct FlightDetailsEntryView: View {
    @EnvironmentObject private var tripStore: JetLagTripStore
    @Environment(\.dismiss) private var dismiss

    @State private var flightDate = Date()
    @State private var departureAirport = ""
    @State private var arrivalAirport = ""
    @State private var departureTime = Date()
    @State private var arrivalTime = Date()
    @State private var flightNumber = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.moonbeamBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Flight date", systemImage: "calendar")
                                .font(.headline)

                            DatePicker(
                                "Day",
                                selection: $flightDate,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.graphical)
                        }
                        .moonbeamCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Airports", systemImage: "mappin.and.ellipse")
                                .font(.headline)

                            TextField("Departing airport (e.g. SFO)", text: $departureAirport)
                                .textContentType(.none)
                                .textInputAutocapitalization(.characters)

                            TextField("Arriving airport (e.g. LHR)", text: $arrivalAirport)
                                .textContentType(.none)
                                .textInputAutocapitalization(.characters)
                        }
                        .moonbeamCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Times (local)", systemImage: "clock")
                                .font(.headline)

                            DatePicker("Departure time", selection: $departureTime, displayedComponents: .hourAndMinute)

                            DatePicker("Arrival time", selection: $arrivalTime, displayedComponents: .hourAndMinute)
                        }
                        .moonbeamCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Flight", systemImage: "airplane.departure")
                                .font(.headline)

                            TextField("Flight number (e.g. BA 117)", text: $flightNumber)
                                .textInputAutocapitalization(.characters)
                        }
                        .moonbeamCard()
                    }
                    .padding()
                }
            }
            .navigationTitle("Flight details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveTrip()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func saveTrip() {
        let trip = JetLagTrip(
            flightDate: flightDate,
            departureAirport: departureAirport.trimmingCharacters(in: .whitespacesAndNewlines),
            arrivalAirport: arrivalAirport.trimmingCharacters(in: .whitespacesAndNewlines),
            departureTime: departureTime,
            arrivalTime: arrivalTime,
            flightNumber: flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        tripStore.add(trip)
        dismiss()
    }
}

#Preview("Jet Lag") {
    NavigationStack {
        JetLagView()
    }
    .environmentObject(JetLagTripStore())
}
