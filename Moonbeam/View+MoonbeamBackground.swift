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
}
