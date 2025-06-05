//
//  ContentView.swift
//  Moonbeam
//
//  Created by jack on 6/4/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            ZStack {
                Color.clear.moonbeamBackground()

                VStack(spacing: 20) {
                    Text("Moonbeam 🌙")
                        .font(.system(size: 36, weight: .bold))

                    NavigationLink(destination: SleepNowView()) {
                        Text("I’m going to sleep now")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    NavigationLink(destination: WakeTimeView()) {
                        Text("I want to wake up at...")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
                .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    ContentView()
}
