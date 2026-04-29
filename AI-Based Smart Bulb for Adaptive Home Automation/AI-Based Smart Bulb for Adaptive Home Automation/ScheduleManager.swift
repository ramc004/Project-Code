// ScheduleManager.swift
// AI-Based Smart Bulb for Adaptive Home Automation
//
// A singleton responsible for the full schedule lifecycle:
//   - Fetching schedules and AI suggestions from the Flask backend.
//   - Registering recurring local notifications so the system can wake the app
//     and fire BLE commands even when it is backgrounded.
//   - Running an in-app 15-second timer as a foreground BLE fallback, ensuring
//     schedules fire even if the notification fires while the app is active.
//   - Reading HealthKit sleep data to power AI sleep-linked schedule suggestions.
//   - Logging usage events so the backend's AI model can improve over time.

import Foundation
import UIKit
import HealthKit
import Combine
import UserNotifications

// MARK: - Schedule Action

/// The set of lighting actions that a schedule entry can trigger.
///
/// Raw values match the string keys used by the Flask backend API and the
/// BLEManager.actionByte(for:) mapping sent to the ESP32 firmware.
enum ScheduleAction: String, CaseIterable, Codable {
    case powerOn          = "power_on"
    case powerOff         = "power_off"
    case dimWarm          = "dim_warm"
    case brightenCool     = "brighten_cool"
    case brightnessChange = "brightness_change"
    case colourChange     = "colour_change"

    /// A short human-readable label shown in the schedule list and notification body.
    var displayName: String {
        switch self {
        case .powerOn:          return "Turn On"
        case .powerOff:         return "Turn Off"
        case .dimWarm:          return "Dim & Warm"
        case .brightenCool:     return "Brighten & Cool"
        case .brightnessChange: return "Set Brightness"
        case .colourChange:     return "Set Colour"
        }
    }

    /// The SF Symbol name used to represent this action in the UI.
    var icon: String {
        switch self {
        case .powerOn:          return "power"
        case .powerOff:         return "power.dotted"
        case .dimWarm:          return "moon.fill"
        case .brightenCool:     return "sun.max.fill"
        case .brightnessChange: return "slider.horizontal.3"
        case .colourChange:     return "paintpalette.fill"
        }
    }
}

// MARK: - Bulb Schedule Model

/// A single schedule entry stored in the backend database and pushed to the ESP32.
///
/// Conforms to Identifiable for SwiftUI list rendering and Codable so it
/// can be embedded in UNNotification user info dictionaries and decoded on delivery.
struct BulbSchedule: Identifiable, Codable {

    /// The backend database primary key for this schedule.
    let id: Int

    /// The bulb_id of the bulb this schedule applies to.
    var bulbId: String

    /// The user-assigned or AI-generated display name (e.g. "Morning Wake-Up").
    var scheduleName: String

    /// The schedule category string from the backend (e.g. "manual", "auto").
    var scheduleType: String

    /// The hour (0-23) at which this schedule fires.
    var triggerHour: Int

    /// The minute (0-59) at which this schedule fires.
    var triggerMinute: Int

    /// Optional end hour for duration-based schedules.
    var endHour: Int?

    /// Optional end minute for duration-based schedules.
    var endMinute: Int?

    /// The lighting action to perform when the schedule triggers.
    var action: ScheduleAction

    /// The target brightness level (0-255) applied for relevant actions.
    var brightness: Int

    /// The target colour temperature (0-255) applied for relevant actions.
    var colourTemp: Int

    /// Whether this schedule is currently active and should fire.
    var isEnabled: Bool

    /// The AI model's confidence score (0.0-1.0) for auto-generated schedules.
    var confidence: Double

    /// The origin of this schedule: "manual", "auto", or "sleep".
    var source: String

    /// A comma-separated string of day numbers (1=Monday to 7=Sunday)
    /// indicating which days of the week this schedule repeats.
    var daysOfWeek: String

    /// A formatted HH:MM string representing the trigger time.
    var timeString: String {
        String(format: "%02d:%02d", triggerHour, triggerMinute)
    }

    /// The daysOfWeek string parsed into an array of integers.
    var daysArray: [Int] {
        daysOfWeek.split(separator: ",").compactMap { Int($0) }
    }

    /// The SF Symbol name representing the schedule's source origin.
    var sourceIcon: String {
        switch source {
        case "auto":  return "cpu"
        case "sleep": return "moon.zzz.fill"
        default:      return "hand.tap.fill"
        }
    }

    /// A human-readable label for the schedule's source origin.
    var sourceLabel: String {
        switch source {
        case "auto":  return "AI Suggested"
        case "sleep": return "Sleep Linked"
        default:      return "Manual"
        }
    }
}

// MARK: - Schedule Suggestion Model

/// An AI-generated schedule suggestion returned by the backend's usage analysis engine.
///
/// Suggestions are shown to the user in ScheduleView for review. The user can
/// accept (converting to a BulbSchedule), reject, or dismiss each suggestion.
struct ScheduleSuggestion: Identifiable, Codable {

    /// The backend database primary key for this suggestion.
    let id: Int

    /// The machine-readable suggestion type (e.g. "auto_power_off", "sleep_wind_down").
    var suggestionType: String

    /// The suggested trigger hour (0-23).
    var triggerHour: Int

    /// The suggested trigger minute (0-59).
    var triggerMinute: Int

    /// Optional start of the observed activity window (hour).
    var windowStartHour: Int?

    /// Optional start of the observed activity window (minute).
    var windowStartMinute: Int?

    /// Optional end of the observed activity window (hour).
    var windowEndHour: Int?

    /// Optional end of the observed activity window (minute).
    var windowEndMinute: Int?

    /// The recommended lighting action for this suggestion.
    var action: ScheduleAction

    /// The recommended brightness level (0-255).
    var brightness: Int

    /// The recommended colour temperature (0-255).
    var colourTemp: Int

    /// The AI model's confidence score (0.0-1.0).
    var confidence: Double

    /// The number of usage observations that contributed to this suggestion.
    var observationCount: Int

    /// The current review status: "pending", "accepted", or "dismissed".
    var status: String

    /// confidence expressed as a percentage integer for display purposes.
    var confidencePercent: Int { Int(confidence * 100) }

    /// A colour name string used to tint the confidence badge in the UI.
    /// Green >= 80%, orange >= 65%, yellow otherwise.
    var confidenceColour: String {
        confidence >= 0.8 ? "green" : confidence >= 0.65 ? "orange" : "yellow"
    }

    /// A formatted time-window string, or just timeString if no window is available.
    var windowString: String {
        guard let sh = windowStartHour, let eh = windowEndHour else { return timeString }
        let sm = windowStartMinute ?? 0
        let em = windowEndMinute   ?? 0
        return String(format: "%02d:%02d - %02d:%02d", sh, sm, eh, em)
    }

    /// A formatted HH:MM trigger time string.
    var timeString: String {
        String(format: "%02d:%02d", triggerHour, triggerMinute)
    }

    /// A human-readable label derived from suggestionType.
    var readableType: String {
        switch suggestionType {
        case "auto_power_off":         return "Turn Off"
        case "auto_power_on":          return "Turn On"
        case "auto_brightness_change": return "Dim Lights"
        case "sleep_wind_down":        return "Sleep Wind-Down"
        case "sleep_wake_up":          return "Gentle Wake-Up"
        default: return suggestionType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Whether this suggestion was generated from HealthKit sleep data.
    var isSleepBased: Bool { suggestionType.hasPrefix("sleep_") }
}

// MARK: - Schedule Manager

/// A singleton ObservableObject that manages the full schedule lifecycle.
///
/// Responsibilities:
/// - Fetches BulbSchedule and ScheduleSuggestion lists from the backend.
/// - Registers recurring UNCalendarNotificationTrigger entries so the system
///   can wake the app and fire BLE commands in any app state.
/// - Runs a 15-second in-app timer as a foreground fallback, ensuring schedules
///   fire via BLE even when the notification would otherwise be suppressed.
/// - Holds a strong reference to the active BLEManager so BLE commands can
///   be delivered from schedule callbacks regardless of view lifecycle.
/// - Reads HealthKit sleep data and syncs it to the backend for AI suggestions.
class ScheduleManager: NSObject, ObservableObject {

    /// The shared singleton instance used throughout the app.
    static let shared = ScheduleManager()

    // MARK: - Published Properties

    /// The current list of schedule entries for the active bulb.
    @Published var schedules: [BulbSchedule] = []

    /// The current list of AI-generated suggestions awaiting user review.
    @Published var suggestions: [ScheduleSuggestion] = []

    /// True while a loadSchedules request is in flight.
    @Published var isLoadingSchedules = false

    /// True while a loadSuggestions request is in flight.
    @Published var isLoadingSuggestions = false

    /// Whether HealthKit sleep data access has been granted by the user.
    @Published var healthKitAuthorised = false

    /// Whether HealthKit is available on the current device.
    @Published var healthKitAvailable = HKHealthStore.isHealthDataAvailable()

    /// The most recent sleep start time read from HealthKit (bedtime).
    @Published var sleepBedtime: Date?

    /// The most recent sleep end time read from HealthKit (wake time).
    @Published var sleepWakeTime: Date?

    /// Whether the automatic schedule system is enabled.
    ///
    /// Defaults to true on first launch so schedules fire without the user
    /// needing to enable the Auto pill in ScheduleView. Persisted to UserDefaults.
    @Published var autoScheduleEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "autoScheduleEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "autoScheduleEnabled")
            return true
        }
        return UserDefaults.standard.bool(forKey: "autoScheduleEnabled")
    }()

    /// The most recent error message from a backend or HealthKit operation.
    @Published var lastError: String = ""

    /// Whether local notification delivery permission has been granted by the user.
    @Published var notificationsAuthorised = false

    // MARK: - Private Properties

    /// The HealthKit store used for sleep data queries.
    private let healthStore = HKHealthStore()

    /// A repeating 15-second timer used as a foreground BLE fallback.
    /// Fires checkAndFireInApp() to execute schedules while the app is active.
    private var inAppTimer: Timer?

    /// The set of schedule IDs already fired within the current clock minute,
    /// preventing duplicate execution if the timer fires more than once per minute.
    private var firedThisMinute: Set<Int> = []

    /// The clock minute during which firedThisMinute was last populated.
    /// Reset when the minute changes so schedules can fire again the next minute.
    private var lastFiredMinute: Int = -1

    /// Observer token for UIApplication.willEnterForegroundNotification,
    /// used to re-probe HealthKit access when the app returns from the background.
    private var foregroundObserver: NSObjectProtocol?

    // MARK: - Active BLE Manager Reference

    /// A strong reference to the BLEManager currently connected to a bulb.
    ///
    /// SavedBulbControlView registers its BLEManager here when it appears so
    /// that ScheduleManager can drive BLE commands directly -- whether the app
    /// is foregrounded or a notification fires while the control view is on screen.
    ///
    /// Held strongly (not weakly) so the BLEManager survives after the view
    /// disappears (e.g. screen locks, app backgrounds) and scheduled commands
    /// can still be delivered via BLE when the notification fires.
    private var activeBLEManager: BLEManager?

    /// The bulb_id associated with the currently registered BLEManager.
    private var activeBulbId: String?

    // MARK: - BLE Manager Registration

    /// Registers a BLEManager instance as the active manager for the specified bulb.
    ///
    /// Called from SavedBulbControlView.onAppear so that schedule execution
    /// can send BLE commands to the correct connected peripheral.
    ///
    /// - Parameters:
    ///   - manager: The BLEManager managing the active BLE connection.
    ///   - bulbId: The bulb_id of the connected bulb.
    func registerActiveBLEManager(_ manager: BLEManager, for bulbId: String) {
        activeBLEManager = manager
        activeBulbId     = bulbId
        print("📡 ScheduleManager: registered BLEManager for bulb \(bulbId)")
    }

    /// Unregisters the active BLEManager for the specified bulb, but only if
    /// the BLE connection has already been dropped.
    ///
    /// If the bulb is still connected (e.g. the user navigated away but the
    /// peripheral is still paired), the reference is kept alive so scheduled
    /// commands can still fire via BLE. Only clears the reference if
    /// connectedBulb is nil, indicating the peripheral has disconnected.
    ///
    /// - Parameter bulbId: The bulb_id whose manager should be unregistered.
    func unregisterActiveBLEManager(for bulbId: String) {
        guard activeBulbId == bulbId else { return }
        if activeBLEManager?.connectedBulb == nil {
            activeBLEManager = nil
            activeBulbId     = nil
            print("📡 ScheduleManager: unregistered BLEManager for bulb \(bulbId) (disconnected)")
        } else {
            print("📡 ScheduleManager: kept BLEManager for bulb \(bulbId) (still connected -- schedules can still fire)")
        }
    }

    /// Unconditionally clears the active BLEManager reference for the specified bulb.
    ///
    /// Should be called from the CBCentralManagerDelegate disconnect callback
    /// to ensure the stale reference is released immediately.
    ///
    /// - Parameter bulbId: The bulb_id whose manager should be force-cleared.
    func forceUnregisterActiveBLEManager(for bulbId: String) {
        if activeBulbId == bulbId {
            activeBLEManager = nil
            activeBulbId     = nil
            print("📡 ScheduleManager: force-unregistered BLEManager for bulb \(bulbId)")
        }
    }

    // MARK: - Initialisation

    /// Private initialiser -- use ScheduleManager.shared instead.
    ///
    /// Probes HealthKit sleep access, requests notification permission, starts
    /// the in-app timer, and registers an observer to re-probe sleep access
    /// whenever the app returns to the foreground.
    private override init() {
        super.init()
        probeSleepAccess()
        requestNotificationPermission()
        startInAppTimer()

        // Re-probe HealthKit each time the app returns from the background,
        // in case the user granted or revoked access while the app was suspended.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.probeSleepAccess()
        }
    }

    deinit {
        // Clean up the foreground observer to avoid retain cycles
        if let obs = foregroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Notification Permission

    /// Requests authorisation to display alert banners, play sounds, and badge the app icon.
    ///
    /// Updates notificationsAuthorised on the main thread with the result.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { self.notificationsAuthorised = granted }
        }
    }

    // MARK: - Local Notifications

    /// Removes all existing schedule notifications and re-registers them from the
    /// current schedules list.
    ///
    /// All schedule notification identifiers are prefixed with "sched_" so they
    /// can be targeted for removal without affecting other app notifications.
    /// Notifications are only registered when autoScheduleEnabled is true and
    /// the individual schedule's isEnabled flag is set.
    func syncLocalNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            // Remove all existing schedule-owned notification requests
            let ids = requests.filter { $0.identifier.hasPrefix("sched_") }.map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            guard self.autoScheduleEnabled else { return }
            // Re-register a notification for each enabled schedule
            for schedule in self.schedules where schedule.isEnabled {
                self.registerNotification(for: schedule)
            }
        }
    }

    /// Registers a repeating UNCalendarNotificationTrigger for each day in a schedule.
    ///
    /// One notification request is created per active day so the system can
    /// independently fire each weekday occurrence. The schedule is encoded as JSON
    /// and embedded in the notification's userInfo so handleNotification(_:)
    /// can reconstruct and execute it on delivery.
    ///
    /// Day conversion: daysOfWeek uses 1=Monday to 7=Sunday; DateComponents.weekday
    /// uses Gregorian convention (1=Sunday to 7=Saturday), so the mapping is:
    /// gregorianWD = (dayMon % 7) + 1.
    ///
    /// - Parameter schedule: The BulbSchedule to register notifications for.
    private func registerNotification(for schedule: BulbSchedule) {
        guard let encoded = try? JSONEncoder().encode(schedule),
              let dict    = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return }

        let content          = UNMutableNotificationContent()
        content.title        = "Smart Bulb Schedule"
        content.body         = "\(schedule.scheduleName) -- \(schedule.action.displayName)"
        content.sound        = .none
        // Embed the full schedule so it can be reconstructed on notification delivery
        content.userInfo     = ["schedule": dict, "bulbId": schedule.bulbId]

        // Register one repeating notification per active day of the week
        for dayMon in schedule.daysArray {
            // Convert Monday-based day (1=Mon to 7=Sun) to Gregorian weekday (1=Sun to 7=Sat)
            let gregorianWD  = (dayMon % 7) + 1
            var comps        = DateComponents()
            comps.hour       = schedule.triggerHour
            comps.minute     = schedule.triggerMinute
            comps.second     = 0
            comps.weekday    = gregorianWD

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let id      = "sched_\(schedule.id)_day\(dayMon)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error { print("Warning: Notification register error \(id): \(error)") }
            }
        }
    }

    // MARK: - Schedule Execution

    /// Applies the lighting action defined by a schedule entry via the active BLEManager.
    ///
    /// This is the single execution point called by both the notification handler
    /// (any app state) and the in-app timer (foreground only). If no active
    /// BLEManager is registered or the bulb ID does not match, the action is
    /// skipped but a scheduleTriggered notification is still posted so any
    /// on-screen views can react (e.g. updating sliders without a BLE connection).
    ///
    /// - Parameter schedule: The BulbSchedule whose action should be executed.
    func executeSchedule(_ schedule: BulbSchedule) {
        guard let ble = activeBLEManager,
              activeBulbId == schedule.bulbId else {
            print("Warning: ScheduleManager: cannot fire '\(schedule.scheduleName)' -- activeBulbId='\(activeBulbId ?? "nil")' schedule.bulbId='\(schedule.bulbId)' bleManager=\(activeBLEManager == nil ? "nil" : "present")")
            // Post notification so any on-screen view can react even without BLE
            NotificationCenter.default.post(name: .scheduleTriggered, object: nil,
                                            userInfo: ["schedule": schedule])
            return
        }

        print("ScheduleManager: firing '\(schedule.scheduleName)' (\(schedule.action.rawValue)) via BLE")
        switch schedule.action {
        case .powerOn:
            ble.setPower(true)
        case .powerOff:
            ble.setPower(false)
        case .dimWarm:
            // Turn on, apply specified brightness, and set to full warm white
            ble.setPower(true)
            ble.setBrightness(UInt8(schedule.brightness))
            ble.setColourTemp(255)
        case .brightenCool:
            // Turn on, apply specified brightness, and set to full cool white
            ble.setPower(true)
            ble.setBrightness(UInt8(schedule.brightness))
            ble.setColourTemp(0)
        case .brightnessChange:
            ble.setBrightness(UInt8(schedule.brightness))
        case .colourChange:
            ble.setColourTemp(UInt8(schedule.colourTemp))
        }

        // Post notification so UI sliders and the power toggle stay in sync
        NotificationCenter.default.post(name: .scheduleTriggered, object: nil,
                                        userInfo: ["schedule": schedule])
    }

    /// Decodes a BulbSchedule from a notification's userInfo dictionary and
    /// executes it via executeSchedule(_:).
    ///
    /// Called by AppDelegate for both foreground and background notification delivery.
    /// Dispatches execution on the main thread to ensure BLE writes and UI updates
    /// are safe.
    ///
    /// - Parameter userInfo: The userInfo payload from the delivered notification.
    func handleNotification(userInfo: [AnyHashable: Any]) {
        guard let schedDict = userInfo["schedule"] as? [String: Any],
              let data      = try? JSONSerialization.data(withJSONObject: schedDict),
              let schedule  = try? JSONDecoder().decode(BulbSchedule.self, from: data) else { return }
        DispatchQueue.main.async { self.executeSchedule(schedule) }
    }

    // MARK: - In-App Timer (Foreground BLE Fallback)

    /// Starts a repeating 15-second timer that calls checkAndFireInApp().
    ///
    /// This timer acts as a foreground fallback: when the app is active, local
    /// notifications are presented as banners but their callbacks fire via
    /// AppDelegate. The timer ensures BLE commands are also sent directly
    /// without relying solely on the notification delivery path.
    private func startInAppTimer() {
        inAppTimer?.invalidate()
        inAppTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.checkAndFireInApp()
        }
    }

    /// Checks all enabled schedules against the current time and fires any that match.
    ///
    /// Runs every 15 seconds. Converts the Gregorian weekday to Monday-based convention
    /// to match the daysOfWeek format used in BulbSchedule. Uses firedThisMinute
    /// to ensure each schedule fires at most once per clock minute, even if the timer
    /// ticks multiple times within the same minute.
    ///
    /// This method is always active regardless of autoScheduleEnabled so that
    /// real-hardware foreground schedules always fire.
    func checkAndFireInApp() {
        let cal    = Calendar.current
        let now    = Date()
        let h      = cal.component(.hour,    from: now)
        let m      = cal.component(.minute,  from: now)
        let gregWD = cal.component(.weekday, from: now)
        // Convert Gregorian weekday (1=Sun to 7=Sat) to Monday-based (1=Mon to 7=Sun)
        let monWD  = gregWD == 1 ? 7 : gregWD - 1

        // Reset the per-minute deduplication set when the minute changes
        if m != lastFiredMinute {
            firedThisMinute.removeAll()
            lastFiredMinute = m
        }

        for schedule in schedules where schedule.isEnabled {
            // Skip if already fired this minute
            guard !firedThisMinute.contains(schedule.id) else { continue }
            // Skip if today is not one of the schedule's active days
            guard schedule.daysArray.contains(monWD) else { continue }
            // Skip if the current time does not match the trigger time
            guard schedule.triggerHour == h && schedule.triggerMinute == m else { continue }

            firedThisMinute.insert(schedule.id)
            print("In-app timer firing '\(schedule.scheduleName)' at \(h):\(String(format: "%02d", m))")
            executeSchedule(schedule)
        }
    }

    // MARK: - HealthKit

    /// Silently probes whether HealthKit sleep analysis access has been granted,
    /// without showing a permission dialog.
    ///
    /// Executes a lightweight query limited to 1 sample. If the query returns
    /// an authorisation error, healthKitAuthorised is set to false and the
    /// cached sleep times are cleared. Otherwise, healthKitAuthorised is set
    /// to true and fetchSleepData is called to load the most recent sleep data.
    func probeSleepAccess() {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            DispatchQueue.main.async { self.healthKitAuthorised = false }
            return
        }
        let sort      = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-86400 * 7), end: Date(), options: .strictEndDate
        )
        let probe = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                  limit: 1, sortDescriptors: [sort]) { [weak self] _, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let hkError = error as? HKError,
                   hkError.code == .errorAuthorizationDenied ||
                   hkError.code == .errorAuthorizationNotDetermined {
                    // Access denied or not yet determined -- clear cached sleep data
                    self.healthKitAuthorised = false
                    self.sleepBedtime        = nil
                    self.sleepWakeTime       = nil
                } else {
                    // Access granted -- fetch the full sleep dataset
                    self.healthKitAuthorised = true
                    self.fetchSleepData()
                }
            }
        }
        healthStore.execute(probe)
    }

    /// Requests HealthKit authorisation for read access to sleep analysis data.
    ///
    /// If access is granted, immediately calls probeSleepAccess() to refresh
    /// the authorisation state and sleep data. The completion handler is called
    /// after a short delay to allow the probe query to settle.
    ///
    /// - Parameter completion: Called with true if authorised, false otherwise,
    ///   along with any error returned by HealthKit.
    func requestHealthKitPermission(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(false, nil); return
        }
        // Request read-only access to sleep analysis (no sharing required)
        healthStore.requestAuthorization(toShare: [], read: [sleepType]) { [weak self] _, error in
            self?.probeSleepAccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                completion(self?.healthKitAuthorised ?? false, error)
            }
        }
    }

    /// Fetches sleep analysis samples from the past 7 days and extracts the
    /// earliest bedtime and latest wake time from in-bed and asleep records.
    ///
    /// Filters for inBed, asleepCore, and asleepDeep categories to cover
    /// both older and newer HealthKit sleep stage representations. Updates
    /// sleepBedtime and sleepWakeTime on the main thread, then syncs the
    /// result to the backend via syncSleepToServer.
    func fetchSleepData() {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: HKQuery.predicateForSamples(
                withStart: Date().addingTimeInterval(-86400 * 7),
                end: Date(), options: .strictEndDate
            ),
            limit: 20, sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let self = self, let samples = samples as? [HKCategorySample] else { return }
            // Include in-bed and asleep stages to cover Apple Watch and manual entries
            let inBed = samples.filter {
                $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue      ||
                $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            }
            guard let earliest = inBed.min(by: { $0.startDate < $1.startDate }),
                  let latest   = inBed.max(by: { $0.endDate   < $1.endDate   }) else { return }
            DispatchQueue.main.async {
                self.sleepBedtime  = earliest.startDate
                self.sleepWakeTime = latest.endDate
                self.syncSleepToServer(bedtime: earliest.startDate, wakeTime: latest.endDate)
            }
        }
        healthStore.execute(query)
    }

    /// Sends the most recently fetched sleep window to the Flask /sync_sleep endpoint
    /// so the AI model can generate sleep-linked schedule suggestions.
    ///
    /// Times are formatted as ISO 8601 strings. The result is discarded as the
    /// backend processes sleep data asynchronously.
    ///
    /// - Parameters:
    ///   - bedtime: The earliest sleep start time from HealthKit.
    ///   - wakeTime: The latest sleep end time from HealthKit.
    private func syncSleepToServer(bedtime: Date, wakeTime: Date) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        let fmt = ISO8601DateFormatter()
        NetworkManager.shared.post(endpoint: "/sync_sleep", body: [
            "email":       email,
            "sleep_start": fmt.string(from: bedtime),
            "sleep_end":   fmt.string(from: wakeTime)
        ]) { _ in }
    }

    // MARK: - Server API

    /// Fetches the schedule list from the /get_schedules endpoint.
    ///
    /// Optionally filtered to a specific bulbId. On success, updates schedules,
    /// re-syncs local notifications, and pushes the full list to the ESP32 via
    /// the active BLEManager so the hardware can run schedules autonomously.
    ///
    /// - Parameter bulbId: If provided, only schedules for this bulb are fetched.
    func loadSchedules(for bulbId: String? = nil) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        isLoadingSchedules = true
        var body: [String: Any] = ["email": email]
        if let b = bulbId { body["bulb_id"] = b }
        NetworkManager.shared.post(endpoint: "/get_schedules", body: body) { [weak self] result in
            self?.isLoadingSchedules = false
            if case .success(let json) = result,
               let arr = json["schedules"] as? [[String: Any]] {
                self?.schedules = arr.compactMap { Self.parseSchedule($0) }
                self?.syncLocalNotifications()
                // Push the updated schedule list to the ESP32 for autonomous execution
                if let schedules = self?.schedules {
                    self?.activeBLEManager?.pushAllSchedules(schedules)
                }
            }
        }
    }

    /// Fetches AI-generated schedule suggestions from the /get_suggestions endpoint.
    ///
    /// Optionally filtered to a specific bulbId. On success, updates suggestions.
    ///
    /// - Parameter bulbId: If provided, only suggestions for this bulb are fetched.
    func loadSuggestions(for bulbId: String? = nil) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        isLoadingSuggestions = true
        var body: [String: Any] = ["email": email]
        if let b = bulbId { body["bulb_id"] = b }
        NetworkManager.shared.post(endpoint: "/get_suggestions", body: body) { [weak self] result in
            self?.isLoadingSuggestions = false
            if case .success(let json) = result,
               let arr = json["suggestions"] as? [[String: Any]] {
                self?.suggestions = arr.compactMap { Self.parseSuggestion($0) }
            }
        }
    }

    /// Triggers the backend's AI usage analysis for a specific bulb, then
    /// refreshes the suggestions list.
    ///
    /// - Parameter bulbId: The bulb whose usage history should be analysed.
    func analyseUsage(bulbId: String) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/analyse_usage",
                                   body: ["email": email, "bulb_id": bulbId]) { [weak self] _ in
            self?.loadSuggestions(for: bulbId)
        }
    }

    /// Creates a new schedule on the backend via /add_schedule, then reloads
    /// the schedule list (which also pushes the update to the ESP32).
    ///
    /// - Parameters:
    ///   - schedule: A NewScheduleRequest describing the schedule to create.
    ///   - completion: Called with true on success, false on failure.
    func addSchedule(_ schedule: NewScheduleRequest, completion: @escaping (Bool) -> Void) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else {
            completion(false); return
        }
        var body: [String: Any] = [
            "email":          email,
            "bulb_id":        schedule.bulbId,
            "schedule_name":  schedule.name,
            "trigger_hour":   schedule.triggerHour,
            "trigger_minute": schedule.triggerMinute,
            "action":         schedule.action.rawValue,
            "brightness":     schedule.brightness,
            "colour_temp":    schedule.colourTemp,
            "days_of_week":   schedule.daysOfWeek
        ]
        if let eh = schedule.endHour   { body["end_hour"]   = eh }
        if let em = schedule.endMinute { body["end_minute"] = em }
        NetworkManager.shared.post(endpoint: "/add_schedule", body: body) { [weak self] result in
            if case .success = result {
                // Reload triggers a notification sync and ESP32 push
                self?.loadSchedules(for: schedule.bulbId)
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    /// Enables or disables a specific schedule on the backend, then reloads
    /// the schedule list to sync notifications and the ESP32.
    ///
    /// - Parameters:
    ///   - id: The schedule's backend database ID.
    ///   - enabled: true to enable, false to disable.
    func toggleSchedule(_ id: Int, enabled: Bool) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/update_schedule", body: [
            "email": email, "schedule_id": id, "is_enabled": enabled ? 1 : 0
        ]) { [weak self] _ in
            self?.loadSchedules()   // Reload triggers notification sync and ESP32 push
        }
    }

    /// Deletes a schedule from the backend, then reloads the schedule list
    /// to remove the corresponding local notification and update the ESP32.
    ///
    /// - Parameters:
    ///   - id: The schedule's backend database ID.
    ///   - bulbId: The bulb the schedule belongs to, used to filter the reload.
    func deleteSchedule(_ id: Int, bulbId: String) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/delete_schedule", body: [
            "email": email, "schedule_id": id
        ]) { [weak self] _ in
            self?.loadSchedules(for: bulbId)   // Reload triggers notification sync and ESP32 push
        }
    }

    /// Submits the user's response to an AI suggestion ("accept", "reject", or
    /// "dismiss"), then refreshes the suggestion and schedule lists.
    ///
    /// - Parameters:
    ///   - id: The suggestion's backend database ID.
    ///   - response: The response string ("accept", "reject", or "dismiss").
    ///   - bulbId: The bulb the suggestion applies to.
    func respondToSuggestion(id: Int, response: String, bulbId: String) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/respond_suggestion", body: [
            "email": email, "suggestion_id": id, "response": response
        ]) { [weak self] _ in
            self?.loadSuggestions(for: bulbId)
            // Only reload schedules if the suggestion was accepted (not dismissed/rejected)
            if response != "dismiss" { self?.loadSchedules(for: bulbId) }
        }
    }

    /// Logs a single bulb interaction event to the backend for AI training.
    ///
    /// Called from SavedBulbControlView whenever the user adjusts power,
    /// brightness, or colour temperature. Optional parameters are omitted from
    /// the request body when not applicable to the event type.
    ///
    /// - Parameters:
    ///   - email: The current user's email address.
    ///   - bulbId: The bulb being interacted with.
    ///   - eventType: A string identifying the event (e.g. "power_on", "brightness_change").
    ///   - power: The power state at the time of the event, if applicable.
    ///   - brightness: The brightness level at the time of the event, if applicable.
    ///   - colourTemp: The colour temperature at the time of the event, if applicable.
    func logUsageEvent(email: String, bulbId: String, eventType: String,
                       power: Bool?, brightness: Int?, colourTemp: Int?) {
        var body: [String: Any] = ["email": email, "bulb_id": bulbId, "event_type": eventType]
        if let p = power      { body["power"]       = p ? 1 : 0 }
        if let b = brightness { body["brightness"]  = b }
        if let c = colourTemp { body["colour_temp"] = c }
        NetworkManager.shared.post(endpoint: "/log_usage", body: body) { _ in }
    }

    /// Enables or disables the automatic schedule system and persists the
    /// preference to UserDefaults, then re-syncs local notifications.
    ///
    /// When disabled, all pending schedule notifications are removed. When
    /// re-enabled, notifications are re-registered for all enabled schedules.
    ///
    /// - Parameter enabled: true to enable automatic scheduling, false to disable.
    func setAutoSchedule(enabled: Bool) {
        autoScheduleEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "autoScheduleEnabled")
        syncLocalNotifications()
    }

    // MARK: - Parsing Helpers

    /// Parses a raw JSON dictionary from the /get_schedules response into a BulbSchedule.
    ///
    /// Returns nil if any required field is missing or the action raw value is invalid.
    ///
    /// - Parameter d: A [String: Any] dictionary from the server response.
    /// - Returns: A populated BulbSchedule, or nil if parsing fails.
    static func parseSchedule(_ d: [String: Any]) -> BulbSchedule? {
        guard let id        = d["id"]             as? Int,
              let bulbId    = d["bulb_id"]        as? String,
              let name      = d["schedule_name"]  as? String,
              let actionRaw = d["action"]         as? String,
              let action    = ScheduleAction(rawValue: actionRaw),
              let tH        = d["trigger_hour"]   as? Int,
              let tM        = d["trigger_minute"] as? Int else { return nil }
        return BulbSchedule(
            id:            id,
            bulbId:        bulbId,
            scheduleName:  name,
            scheduleType:  d["schedule_type"] as? String  ?? "manual",
            triggerHour:   tH,
            triggerMinute: tM,
            endHour:       d["end_hour"]    as? Int,
            endMinute:     d["end_minute"]  as? Int,
            action:        action,
            brightness:    d["brightness"]   as? Int    ?? 255,
            colourTemp:    d["colour_temp"]  as? Int    ?? 128,
            isEnabled:    (d["is_enabled"]   as? Bool)  ?? true,
            confidence:    d["confidence"]   as? Double ?? 1.0,
            source:        d["source"]       as? String ?? "manual",
            daysOfWeek:    d["days_of_week"] as? String ?? "1,2,3,4,5,6,7"
        )
    }

    /// Parses a raw JSON dictionary from the /get_suggestions response into a ScheduleSuggestion.
    ///
    /// Returns nil if any required field is missing or the action raw value is invalid.
    ///
    /// - Parameter d: A [String: Any] dictionary from the server response.
    /// - Returns: A populated ScheduleSuggestion, or nil if parsing fails.
    static func parseSuggestion(_ d: [String: Any]) -> ScheduleSuggestion? {
        guard let id        = d["id"]              as? Int,
              let stype     = d["suggestion_type"] as? String,
              let actionRaw = d["action"]          as? String,
              let action    = ScheduleAction(rawValue: actionRaw),
              let tH        = d["trigger_hour"]    as? Int,
              let tM        = d["trigger_minute"]  as? Int else { return nil }
        return ScheduleSuggestion(
            id:                id,
            suggestionType:    stype,
            triggerHour:       tH,
            triggerMinute:     tM,
            windowStartHour:   d["window_start_hour"]   as? Int,
            windowStartMinute: d["window_start_minute"] as? Int,
            windowEndHour:     d["window_end_hour"]     as? Int,
            windowEndMinute:   d["window_end_minute"]   as? Int,
            action:            action,
            brightness:        d["brightness"]        as? Int    ?? 255,
            colourTemp:        d["colour_temp"]       as? Int    ?? 128,
            confidence:        d["confidence"]        as? Double ?? 0.0,
            observationCount:  d["observation_count"] as? Int    ?? 0,
            status:            d["status"]            as? String ?? "pending"
        )
    }
}

// MARK: - New Schedule Request Model

/// A lightweight value type used to pass schedule creation parameters into
/// ScheduleManager.addSchedule(_:completion:).
///
/// Decoupled from BulbSchedule so callers do not need to supply fields
/// that are assigned by the backend (e.g. id, source, confidence).
struct NewScheduleRequest {

    /// The bulb_id of the bulb this schedule should apply to.
    var bulbId: String

    /// The user-assigned display name for the schedule.
    var name: String

    /// The hour (0-23) at which this schedule should fire.
    var triggerHour: Int

    /// The minute (0-59) at which this schedule should fire.
    var triggerMinute: Int

    /// Optional end hour for duration-based schedules.
    var endHour: Int?

    /// Optional end minute for duration-based schedules.
    var endMinute: Int?

    /// The lighting action this schedule should perform.
    var action: ScheduleAction

    /// The target brightness level (0-255).
    var brightness: Int

    /// The target colour temperature (0-255).
    var colourTemp: Int

    /// A comma-separated string of active day numbers (1=Monday to 7=Sunday).
    var daysOfWeek: String
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted by ScheduleManager.executeSchedule(_:) whenever a schedule fires,
    /// allowing views (e.g. SavedBulbControlView) to update their UI state.
    static let scheduleTriggered = Notification.Name("scheduleTriggered")
}
