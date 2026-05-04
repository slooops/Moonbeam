//
//  MoonbeamApp.swift
//  Moonbeam
//
//  Created by jack on 6/4/25.
//

import SwiftUI
import UserNotifications

@main
struct MoonbeamApp: App {
    @StateObject private var profile = SleepProfile()
    @StateObject private var jetLagTrips = JetLagTripStore()
    @StateObject private var sunTimes = SunTimesService()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profile)
                .environmentObject(jetLagTrips)
                .environmentObject(sunTimes)
                .onAppear {
                    sunTimes.requestLocation()
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, @unchecked Sendable {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        return true
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
