//
//  ContentView.swift
//  Moonbeam
//
//  Created by jack on 6/4/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                CycleTimerView()
            }
            .tabItem {
                Label("Sleep", systemImage: "moon.zzz.fill")
            }

            NavigationStack {
                JetLagView()
            }
            .tabItem {
                Label("Jet Lag", systemImage: "airplane.departure")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(SleepProfile())
        .environmentObject(JetLagTripStore())
        .environmentObject(SunTimesService())
}
