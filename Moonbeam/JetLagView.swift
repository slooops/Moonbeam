//
//  JetLagView.swift
//  Moonbeam
//

import SwiftUI

struct JetLagView: View {
    @State private var showingFlightEntry = false

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

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
        }
    }
}

private struct FlightDetailsEntryView: View {
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
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Jet Lag") {
    NavigationStack {
        JetLagView()
    }
}
