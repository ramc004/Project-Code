import SwiftUI
import UserNotifications

@main
struct AI_Based_Smart_Bulb_for_Adaptive_Home_AutomationApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            WelcomeView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Called when a notification is delivered while the app is in the FOREGROUND.
    // Display it as a banner AND fire the BLE command.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        ScheduleManager.shared.handleNotification(userInfo: notification.request.content.userInfo)
        completionHandler([.banner, .sound])
    }

    // Called when the user taps a notification (app was backgrounded or closed).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        ScheduleManager.shared.handleNotification(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
}
