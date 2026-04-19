//
//  MoonbeamMenuView.swift
//  Moonbeam
//

import SwiftUI

struct MoonbeamMenuView: View {
    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            ScrollView {
                VStack(spacing: 0) {
                    Label("Moonbeam", systemImage: "moon.stars.fill")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 28)
                        .padding(.bottom, 36)

                    VStack(spacing: 14) {
                        NavigationLink {
                            CycleTimerView()
                        } label: {
                            MoonbeamMenuRow(
                                title: "Cycle Timer",
                                systemImage: "timer"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            JetLagView()
                        } label: {
                            MoonbeamMenuRow(
                                title: "Jet Lag",
                                systemImage: "airplane.departure"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ComingSoonPlaceholderView(title: "More to Com")
                        } label: {
                            MoonbeamMenuRow(
                                title: "More to Com",
                                systemImage: "sparkles"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct MoonbeamMenuRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 32)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(Color("DeepSpace").opacity(0.5)), in: .rect(cornerRadius: 26))
    }
}

struct ComingSoonPlaceholderView: View {
    let title: String

    var body: some View {
        ZStack {
            Color.clear.moonbeamBackground()

            VStack(spacing: 12) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Coming soon")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        MoonbeamMenuView()
    }
}
