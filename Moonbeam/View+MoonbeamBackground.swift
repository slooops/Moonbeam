//
//  View+MoonbeamBackground.swift
//  Moonbeam
//
//  Created by jack on 6/4/25.
//

import SwiftUI

extension View {
    func moonbeamBackground() -> some View {
        self.background(
            LinearGradient(
                gradient: Gradient(colors: [Color("MidnightBlue"), Color("DeepSpace")]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .ignoresSafeArea()
    }

    func moonbeamCard() -> some View {
        self
            .padding(20)
            .glassEffect(.regular.tint(.indigo.opacity(0.15)), in: .rect(cornerRadius: 24))
    }
}
