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

    /// Keeps content at a comfortable reading width on wide screens such as
    /// the unfolded iPhone Duo, centered in the available space.
    func moonbeamReadableWidth(_ maxWidth: CGFloat = 560) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    func moonbeamCard() -> some View {
        self
            .padding(20)
            .glassEffect(.regular.tint(Color("DeepSpace").opacity(0.55)), in: .rect(cornerRadius: 24))
    }
}
