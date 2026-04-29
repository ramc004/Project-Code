// AI_Based_Smart_Bulb_for_Adaptive_Home_AutomationApp.swift
// AI-Based Smart Bulb for Adaptive Home Automation

// The application entry point
// Defines the root SwiftUI App struct and the UIKit AppDelegate, which is required to configure the UserNotifications framework and handle notification delivery for scheduled bulb commands

import SwiftUI
import UserNotifications

// MARK: - App Entry Point

/// The root SwiftUI application struct, marked with "@main" to designate it as the entry point

/// Uses "@UIApplicationDelegateAdaptor" to bridge to "AppDelegate", which is needed to set the "UNUserNotificationCenterDelegate" before the app finishes launching, this cannot be done from a pure SwiftUI lifecycle

/// "WelcomeView" is set as the root view, from which the full navigation hierarchy (registration, login, home, bulb control) is accessible
@main
struct AI_Based_Smart_Bulb_for_Adaptive_Home_AutomationApp: App {

    /// Bridges to the UIKit "AppDelegate" to handle notification centre setup and notification response callbacks
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            // WelcomeView is the root of the navigation hierarchy
            WelcomeView()
        }
    }
}

// MARK: - App Delegate

/// The UIKit application delegate, responsible for configuring push and local notification handling at launch and routing delivered notifications to "ScheduleManager" for execution of the related bulb command

/// Fits to both "UIApplicationDelegate" and "UNUserNotificationCenterDelegate" so it can act as the single delegate for application lifecycle and notification events
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Called by the system after the app has finished launching
    
    /// Registers this class as the "UNUserNotificationCenter" delegate so that foreground notification presentation and notification response callbacks are routed here rather than ignored
    
    /// - Returns: "true" to indicate successful launch setup
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Called when a local notification is delivered while the app is in the foreground

    /// Forwards the notification payload to "ScheduleManager" so the selected BLE bulb command is executed, then instructs the system to display the notification as a banner with sound rather than suppressing it
    
    /// - Parameters:
    ///   - center: The notification centre managing the notification
    ///   - notification: The notification that was delivered
    ///   - completionHandler: Must be called with the desired presentation options
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Execute the scheduled bulb command with this notification
        ScheduleManager.shared.handleNotification(userInfo: notification.request.content.userInfo)
        // Show a banner and play a sound even though the app is in the foreground
        completionHandler([.banner, .sound])
    }

    /// Called when the user taps a delivered notification while the app is backgrounded or closed, bringing it to the foreground
    
    /// Forwards the notification payload to "ScheduleManager" so the BLE bulb command is executed on app resume
    
    /// - Parameters:
    ///   - center: The notification centre managing the notification
    ///   - response: The user's response to the notification, containing the payload
    ///   - completionHandler: Must be called when handling is complete
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Execute the scheduled bulb command now that the app is active
        ScheduleManager.shared.handleNotification(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
}
