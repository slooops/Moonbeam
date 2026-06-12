//
//  SleepProfile.swift
//  Moonbeam
//

import SwiftUI

final class SleepProfile: ObservableObject {
    @AppStorage("remCycleMinutes") var remCycleMinutes: Int = 90
    @AppStorage("fallAsleepMinutes") var fallAsleepMinutes: Int = 15

    /// Usual sleep window, minutes since midnight. Jet lag plans shift this
    /// window night by night, so it also sets how long each night's sleep is.
    @AppStorage("idealBedMinutes") var idealBedMinutes: Int = 22 * 60 + 30
    @AppStorage("idealWakeMinutes") var idealWakeMinutes: Int = 7 * 60

    static let minCycles = 1
    static let maxCycles = 8

    var remCycleSeconds: TimeInterval {
        TimeInterval(remCycleMinutes * 60)
    }

    var fallAsleepSeconds: TimeInterval {
        TimeInterval(fallAsleepMinutes * 60)
    }
}
