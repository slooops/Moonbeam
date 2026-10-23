import SwiftUI

struct FlightDraft: Identifiable, Equatable {
    let id = UUID()
    var number = ""
    /// Date-only selection, represented on a UTC calendar so the selected day never drifts.
    var date = FlightDraft.today
    var schedule: FlightSchedule?

    static var today: Date {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: components)!
    }
}

struct FlightItineraryEntryView: View {
    @Binding var drafts: [FlightDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Flights (optional)", systemImage: "airplane")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            ForEach($drafts) { $draft in
                let id = draft.id
                let number = (drafts.firstIndex { $0.id == id } ?? 0) + 1
                FlightEntryView(draft: $draft, flightIndex: number) {
                    drafts.removeAll { $0.id == id }
                }
            }

            if drafts.count < 3 {
                Button(action: addFlight) {
                    Label(drafts.isEmpty ? "Add flight" : "Add another flight", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("addFlight")
                .accessibilityHint("Add up to three flights in travel order")
            }

            if !drafts.isEmpty {
                Text("Free public schedule lookup. Coverage is limited; confirm times against your booking.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Confirm each leg to fill the route automatically. The itinerary adds one travel day to your sleep transition.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addFlight() {
        guard drafts.count < 3 else { return }
        var draft = FlightDraft()
        if let previous = drafts.last {
            draft.date = previous.date
            if let schedule = previous.schedule {
                var arrivalCalendar = Calendar(identifier: .gregorian)
                arrivalCalendar.timeZone = schedule.arrivalTimeZone
                var utc = Calendar(identifier: .gregorian)
                utc.timeZone = .gmt
                let day = arrivalCalendar.dateComponents([.year, .month, .day], from: schedule.arrival)
                draft.date = utc.date(from: day) ?? previous.date
            }
        }
        withAnimation { drafts.append(draft) }
    }
}

private struct FlightSearchResults: Identifiable {
    let id = UUID()
    let flights: [FlightSchedule]
}

struct FlightEntryView: View {
    @Binding var draft: FlightDraft
    let flightIndex: Int
    let remove: () -> Void
    @State private var isLookingUp = false
    @State private var isApplyingManual = false
    @State private var errorMessage: String?
    @State private var results: FlightSearchResults?
    @State private var showingManual = false
    @State private var manualOrigin = ""
    @State private var manualDestination = ""
    @State private var manualDeparture = FlightDraft.today.addingTimeInterval(12 * 3600)
    @State private var manualArrival = FlightDraft.today.addingTimeInterval(21 * 3600)
    @State private var lookupTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Flight \(flightIndex)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: remove) {
                    Image(systemName: "xmark.circle")
                }
                .accessibilityLabel("Remove flight \(flightIndex)")
            }
            HStack(spacing: 8) {
                TextField("Flight number", text: Binding(
                    get: { draft.number },
                    set: { draft.number = $0; invalidateLookup() }
                ))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { lookup() }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.06), in: Capsule())
                .accessibilityLabel("Flight number")
                .accessibilityIdentifier("flightNumber-\(flightIndex)")

                DatePicker("Departure date", selection: Binding(
                    get: { draft.date },
                    set: { draft.date = $0; invalidateLookup() }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.timeZone, .gmt)
                .fixedSize()

                Button(action: lookup) {
                    if isLookingUp {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.glass)
                .disabled(draft.number.trimmingCharacters(in: .whitespaces).isEmpty || isLookingUp || isApplyingManual)
                .accessibilityLabel("Look up flight")
            }

            HStack(alignment: .top) {
                if let schedule = draft.schedule {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(schedule.departureAirport) → \(schedule.arrivalAirport)")
                            .font(.subheadline.weight(.medium))
                        Text("\(schedule.formatted(schedule.departure, in: schedule.departureTimeZone)) → \(schedule.formatted(schedule.arrival, in: schedule.arrivalTimeZone)) · local airport times")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(schedule.source == "Manual" ? "Times entered manually"
                            : "\(schedule.referenceDeparture == nil ? "Scheduled times" : "Estimated usual times") · \(schedule.source)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let reference = schedule.referenceDeparture {
                            Text("Usual times from \(reference.formatted(date: .abbreviated, time: .omitted)) · confirm against your booking")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("Use the departure airport’s local date.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Enter scheduled times manually", isExpanded: $showingManual) {
                manualEntry
                    .padding(.top, 8)
            }
            .font(.caption)
        }
        .padding(12)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
        .onDisappear { lookupTask?.cancel() }
        .onChange(of: draft.date) { _, date in
            guard showingManual else { return }
            manualDeparture = date.addingTimeInterval(12 * 3600)
            manualArrival = date.addingTimeInterval(21 * 3600)
        }
        .sheet(item: $results) { result in
            NavigationStack {
                List(result.flights) { flight in
                    Button {
                        draft.schedule = flight
                        results = nil
                        errorMessage = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(flight.number) · \(flight.departureAirport) → \(flight.arrivalAirport)")
                                .font(.headline)
                            Text("\(flight.formatted(flight.departure, in: flight.departureTimeZone)) → \(flight.formatted(flight.arrival, in: flight.arrivalTimeZone)) · local times")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let reference = flight.referenceDeparture {
                                Text("Usual times from \(reference.formatted(date: .abbreviated, time: .omitted)). This flight may not run at these times—or on your selected date. Check your booking.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("Use these estimated times")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .navigationTitle("Choose flight")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { results = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Departure airport (e.g. CPH)", text: $manualOrigin)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Arrival airport (e.g. LHR)", text: $manualDestination)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            DatePicker("Departs (local)", selection: $manualDeparture)
            DatePicker("Arrives (local)", selection: $manualArrival)
            Text("Use the local date and time at each airport, including the arrival date for overnight flights.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                lookupTask?.cancel()
                isLookingUp = false
                lookupTask = Task { await applyManualTimes() }
            } label: {
                HStack {
                    if isApplyingManual { ProgressView().controlSize(.small) }
                    Text("Use these times")
                }
            }
            .disabled(isApplyingManual || draft.number.isEmpty || manualOrigin.isEmpty || manualDestination.isEmpty)
        }
        .textFieldStyle(.roundedBorder)
        .environment(\.timeZone, .gmt)
        .disabled(isApplyingManual)
        .onAppear {
            manualDeparture = draft.date.addingTimeInterval(12 * 3600)
            manualArrival = draft.date.addingTimeInterval(21 * 3600)
        }
    }

    private func invalidateLookup() {
        lookupTask?.cancel()
        isLookingUp = false
        isApplyingManual = false
        draft.schedule = nil
        errorMessage = nil
        results = nil
    }

    private func lookup() {
        lookupTask?.cancel()
        let number = draft.number
        let date = draft.date
        isLookingUp = true
        errorMessage = nil
        lookupTask = Task {
            defer { if !Task.isCancelled { isLookingUp = false } }
            do {
                let flights = try await FlightScheduleService().lookup(number: number, date: date, timeZone: .gmt)
                try Task.checkCancellation()
                results = FlightSearchResults(flights: flights)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? FlightScheduleService.LookupError)?.localizedDescription
                    ?? "Couldn’t retrieve the schedule. Try again or enter the times manually."
            }
        }
    }

    private func applyManualTimes() async {
        isApplyingManual = true
        errorMessage = nil
        defer { if !Task.isCancelled { isApplyingManual = false } }
        do {
            let number = FlightScheduleService.normalizedNumber(draft.number)
            guard number.range(of: "^[A-Z0-9]{2,3}[0-9]{1,4}[A-Z]?$", options: .regularExpression) != nil else {
                throw FlightScheduleService.LookupError.invalidNumber
            }
            let origin = try await JetLagPlanCalculator.resolvePlace(manualOrigin)
            let destination = try await JetLagPlanCalculator.resolvePlace(manualDestination)
            try Task.checkCancellation()
            let departure = try localDate(manualDeparture, in: origin.timeZone)
            let arrival = try localDate(manualArrival, in: destination.timeZone)
            let schedule = FlightSchedule(number: number,
                departureAirport: manualOrigin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                arrivalAirport: manualDestination.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                departure: departure, arrival: arrival,
                departureTimeZoneID: origin.timeZone.identifier,
                arrivalTimeZoneID: destination.timeZone.identifier, source: "Manual")
            guard schedule.isValid else { throw ManualError.invalidTimes }
            draft.schedule = schedule
            // Keep the flight-date field in sync with manually entered departure day.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            draft.date = calendar.startOfDay(for: manualDeparture)
            showingManual = false
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func localDate(_ wallDate: Date, in timeZone: TimeZone) throws -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let components = utc.dateComponents([.year, .month, .day, .hour, .minute], from: wallDate)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        guard let date = local.date(from: components),
              local.dateComponents([.year, .month, .day, .hour, .minute], from: date) == components else {
            throw ManualError.invalidTimes
        }
        return date
    }

    private enum ManualError: LocalizedError {
        case invalidTimes
        var errorDescription: String? {
            "Check the local dates and times: arrival must be after departure, and each flight must be less than 24 hours."
        }
    }
}
