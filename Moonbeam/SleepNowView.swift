//
//  SleepNowView.swift
//  Moonbeam
//
//  Created by jack on 6/4/25.
//

import SwiftUI

struct SleepNowView: View {
    @State private var now = Date()
    private let cycleMinutes = 90
    private let fallAsleepBuffer = 15

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            VStack(spacing: 16) {
                Text("If you go to bed right now, try waking up at:")
                    .multilineTextAlignment(.center)

                ForEach((1..<7).reversed(), id: \.self) { cycle in
                    let totalMinutes = (cycle * cycleMinutes) + fallAsleepBuffer
                    let wakeTime = Calendar.current.date(byAdding: .minute, value: totalMinutes, to: now)!
                    Text("\(cycle) cycle\(cycle > 1 ? "s" : "") → \(formattedTime(wakeTime))")
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
                Text("Sleep Now")
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
