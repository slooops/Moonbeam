//
//  MoonbeamApp.swift
//  Moonbeam
//
//  Created by jack on 6/4/25.
//

import SwiftUI

@main
struct MoonbeamApp: App {
    @StateObject private var profile = SleepProfile()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profile)
        }
    }
}
