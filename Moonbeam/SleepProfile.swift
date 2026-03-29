//
//  SleepProfile.swift
//  Moonbeam
//

import SwiftUI

final class SleepProfile: ObservableObject {
    @AppStorage("remCycleMinutes") var remCycleMinutes: Int = 90
    @AppStorage("fallAsleepMinutes") var fallAsleepMinutes: Int = 15

    static let minCycles = 1
    static let maxCycles = 8

    var remCycleSeconds: TimeInterval {
        TimeInterval(remCycleMinutes * 60)
    }

    var fallAsleepSeconds: TimeInterval {
        TimeInterval(fallAsleepMinutes * 60)
    }
}
