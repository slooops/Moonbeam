//
//  WakeTimeView.swift
//  Moonbeam
//
//  Created by jack on 6/4/25.
//

import SwiftUI

struct WakeTimeView: View {
    @State private var wakeUp = Date()
    private let cycleMinutes = 90
    private let fallAsleepBuffer = 15

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            VStack(spacing: 16) {
                Text("When do you want to wake up?")
                    .font(.headline)

                DatePicker("Wake-up time", selection: $wakeUp, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .colorScheme(.dark) // Fix dark text on dark bg

                Text("Try going to bed at:")
                    .font(.subheadline)

                ForEach((1..<7).reversed(), id: \.self) { cycle in
                    let totalMinutes = (cycle * cycleMinutes) + fallAsleepBuffer
                    let bedTime = Calendar.current.date(byAdding: .minute, value: -totalMinutes, to: wakeUp)!
                    Text("\(cycle) cycle\(cycle > 1 ? "s" : "") → \(formattedTime(bedTime))")
                        .padding(.vertical, 4)
                }

                Spacer()
            }
            .padding(.top, 60)
            .padding(.horizontal)
            .foregroundColor(.white)
        }
        .navigationBarTitleDisplayMode(.inline)
        .tint(.white)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Wake Up At")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
    }

    func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
