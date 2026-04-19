//
//  ContentView.swift
//  Moonbeam
//
//  Created by jack on 6/4/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            MoonbeamMenuView()
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(SleepProfile())
        .environmentObject(JetLagTripStore())
}
