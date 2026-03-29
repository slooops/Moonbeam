//
//  ContentView.swift
//  Moonbeam
//
//  Created by jack on 6/4/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var profile: SleepProfile
    @State private var showingProfile = false
    @State private var slider = SleepSliderView()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.moonbeamBackground()

                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 16) {
                            slider
                        }
                        .moonbeamCard()

                        Button {
                            slider.sleepNow()
                        } label: {
                            Label("Sleep Now", systemImage: "moon.zzz.fill")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.glass)
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label("Moonbeam", systemImage: "moon.stars.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingProfile = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                SleepProfileView()
                    .environmentObject(profile)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(SleepProfile())
}
