import Foundation
import UIKit
import HealthKit
import Combine
import UserNotifications

// MARK: - Data Models

enum ScheduleAction: String, CaseIterable, Codable {
    case powerOn         = "power_on"
    case powerOff        = "power_off"
    case dimWarm         = "dim_warm"
    case brightenCool    = "brighten_cool"
    case brightnessChange = "brightness_change"
    case colourChange    = "colour_change"

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

struct BulbSchedule: Identifiable, Codable {
    let id: Int
    var bulbId: String
    var scheduleName: String
    var scheduleType: String
    var triggerHour: Int
    var triggerMinute: Int
    var endHour: Int?
    var endMinute: Int?
    var action: ScheduleAction
    var brightness: Int
    var colourTemp: Int
    var isEnabled: Bool
    var confidence: Double
    var source: String
    var daysOfWeek: String   // "1,2,3,4,5,6,7"  (1=Mon … 7=Sun)

    var timeString: String {
        String(format: "%02d:%02d", triggerHour, triggerMinute)
    }

    var daysArray: [Int] {
        daysOfWeek.split(separator: ",").compactMap { Int($0) }
    }

    var sourceIcon: String {
        switch source {
        case "auto":  return "cpu"
        case "sleep": return "moon.zzz.fill"
        default:      return "hand.tap.fill"
        }
    }

    var sourceLabel: String {
        switch source {
        case "auto":  return "AI Suggested"
        case "sleep": return "Sleep Linked"
        default:      return "Manual"
        }
    }
}

struct ScheduleSuggestion: Identifiable, Codable {
    let id: Int
    var suggestionType: String
    var triggerHour: Int
    var triggerMinute: Int
    var windowStartHour: Int?
    var windowStartMinute: Int?
    var windowEndHour: Int?
    var windowEndMinute: Int?
    var action: ScheduleAction
    var brightness: Int
    var colourTemp: Int
    var confidence: Double
    var observationCount: Int
    var status: String

    var confidencePercent: Int { Int(confidence * 100) }
    var confidenceColour: String {
        confidence >= 0.8 ? "green" : confidence >= 0.65 ? "orange" : "yellow"
    }

    var windowString: String {
        guard let sh = windowStartHour, let eh = windowEndHour else { return timeString }
        let sm = windowStartMinute ?? 0; let em = windowEndMinute ?? 0
        return String(format: "%02d:%02d – %02d:%02d", sh, sm, eh, em)
    }

    var timeString: String {
        String(format: "%02d:%02d", triggerHour, triggerMinute)
    }

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

    var isSleepBased: Bool { suggestionType.hasPrefix("sleep_") }
}

// MARK: - ScheduleManager

class ScheduleManager: NSObject, ObservableObject {
    static let shared = ScheduleManager()

    @Published var schedules: [BulbSchedule] = []
    @Published var suggestions: [ScheduleSuggestion] = []
    @Published var isLoadingSchedules = false
    @Published var isLoadingSuggestions = false
    @Published var healthKitAuthorised = false
    @Published var healthKitAvailable = HKHealthStore.isHealthDataAvailable()
    @Published var sleepBedtime: Date?
    @Published var sleepWakeTime: Date?
    @Published var autoScheduleEnabled: Bool = {
        // Default to TRUE so schedules fire without the user needing to tap the Auto pill
        if UserDefaults.standard.object(forKey: "autoScheduleEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "autoScheduleEnabled")
            return true
        }
        return UserDefaults.standard.bool(forKey: "autoScheduleEnabled")
    }()
    @Published var lastError: String = ""
    @Published var notificationsAuthorised = false

    private let healthStore = HKHealthStore()

    // In-app timer fires every 15 s as a foreground BLE fallback.
    private var inAppTimer: Timer?
    private var firedThisMinute: Set<Int> = []
    private var lastFiredMinute: Int = -1

    private var foregroundObserver: NSObjectProtocol?

    // MARK: - Active BLE manager reference
    // SavedBulbControlView registers its BLEManager here so ScheduleManager
    // can drive BLE directly — whether the app is foregrounded or the
    // notification fires while the control view is on screen.
    private weak var activeBLEManager: BLEManager?
    private var activeBulbId: String?

    func registerActiveBLEManager(_ manager: BLEManager, for bulbId: String) {
        activeBLEManager = manager
        activeBulbId = bulbId
        print("📡 ScheduleManager: registered BLEManager for bulb \(bulbId)")
    }

    func unregisterActiveBLEManager(for bulbId: String) {
        if activeBulbId == bulbId {
            activeBLEManager = nil
            activeBulbId = nil
            print("📡 ScheduleManager: unregistered BLEManager for bulb \(bulbId)")
        }
    }

    private override init() {
        super.init()
        probeSleepAccess()
        requestNotificationPermission()
        startInAppTimer()

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.probeSleepAccess()
        }
    }

    deinit {
        if let obs = foregroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Notification permission

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { self.notificationsAuthorised = granted }
        }
    }

    // MARK: - Local notifications

    func syncLocalNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.hasPrefix("sched_") }.map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            guard self.autoScheduleEnabled else { return }
            for schedule in self.schedules where schedule.isEnabled {
                self.registerNotification(for: schedule)
            }
        }
    }

    private func registerNotification(for schedule: BulbSchedule) {
        guard let encoded = try? JSONEncoder().encode(schedule),
              let dict    = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return }

        let content = UNMutableNotificationContent()
        content.title    = "Smart Bulb Schedule"
        content.body     = "\(schedule.scheduleName) — \(schedule.action.displayName)"
        content.sound    = .none
        content.userInfo = ["schedule": dict, "bulbId": schedule.bulbId]

        // daysOfWeek: 1=Mon…7=Sun  →  Gregorian weekday: 1=Sun…7=Sat
        for dayMon in schedule.daysArray {
            let gregorianWD = (dayMon % 7) + 1
            var comps        = DateComponents()
            comps.hour       = schedule.triggerHour
            comps.minute     = schedule.triggerMinute
            comps.second     = 0
            comps.weekday    = gregorianWD

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let id      = "sched_\(schedule.id)_day\(dayMon)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error { print("⚠️ Notification register error \(id): \(error)") }
            }
        }
    }

    // MARK: - Execute a schedule action directly via BLE
    // Single point where a schedule is applied. Called from both the
    // notification handler (any app state) and the in-app timer.

    func executeSchedule(_ schedule: BulbSchedule) {
        guard let ble = activeBLEManager,
              activeBulbId == schedule.bulbId else {
            print("⚠️ ScheduleManager: no active BLEManager for bulb \(schedule.bulbId) — cannot fire '\(schedule.scheduleName)'")
            // Still post so any on-screen view can react
            NotificationCenter.default.post(name: .scheduleTriggered, object: nil,
                                            userInfo: ["schedule": schedule])
            return
        }

        print("✅ ScheduleManager: firing '\(schedule.scheduleName)' (\(schedule.action.rawValue)) via BLE")
        switch schedule.action {
        case .powerOn:
            ble.setPower(true)
        case .powerOff:
            ble.setPower(false)
        case .dimWarm:
            ble.setPower(true)
            ble.setBrightness(UInt8(schedule.brightness))
            ble.setColourTemp(255)
        case .brightenCool:
            ble.setPower(true)
            ble.setBrightness(UInt8(schedule.brightness))
            ble.setColourTemp(0)
        case .brightnessChange:
            ble.setBrightness(UInt8(schedule.brightness))
        case .colourChange:
            ble.setColourTemp(UInt8(schedule.colourTemp))
        }

        // Post so UI sliders/toggle stay in sync
        NotificationCenter.default.post(name: .scheduleTriggered, object: nil,
                                        userInfo: ["schedule": schedule])
    }

    // Called by AppDelegate when a UNNotification fires.
    func handleNotification(userInfo: [AnyHashable: Any]) {
        guard let schedDict = userInfo["schedule"] as? [String: Any],
              let data      = try? JSONSerialization.data(withJSONObject: schedDict),
              let schedule  = try? JSONDecoder().decode(BulbSchedule.self, from: data) else { return }
        DispatchQueue.main.async { self.executeSchedule(schedule) }
    }

    // MARK: - In-app timer (foreground BLE fallback, fires every 15 s)

    private func startInAppTimer() {
        inAppTimer?.invalidate()
        inAppTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.checkAndFireInApp()
        }
    }

    func checkAndFireInApp() {
        // Always active — no autoScheduleEnabled gate here so real-hardware
        // foreground schedules always fire regardless of the Auto toggle state.
        let cal    = Calendar.current
        let now    = Date()
        let h      = cal.component(.hour,    from: now)
        let m      = cal.component(.minute,  from: now)
        let gregWD = cal.component(.weekday, from: now)
        let monWD  = gregWD == 1 ? 7 : gregWD - 1   // convert to 1=Mon…7=Sun

        if m != lastFiredMinute {
            firedThisMinute.removeAll()
            lastFiredMinute = m
        }

        for schedule in schedules where schedule.isEnabled {
            guard !firedThisMinute.contains(schedule.id) else { continue }
            guard schedule.daysArray.contains(monWD)     else { continue }
            guard schedule.triggerHour == h && schedule.triggerMinute == m else { continue }

            firedThisMinute.insert(schedule.id)
            print("⏰ In-app timer firing '\(schedule.scheduleName)' at \(h):\(String(format: "%02d", m))")
            executeSchedule(schedule)
        }
    }

    // MARK: - HealthKit

    func probeSleepAccess() {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            DispatchQueue.main.async { self.healthKitAuthorised = false }
            return
        }
        let sort      = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-86400 * 7), end: Date(), options: .strictEndDate)
        let probe = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                  limit: 1, sortDescriptors: [sort]) { [weak self] _, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let hkError = error as? HKError,
                   hkError.code == .errorAuthorizationDenied ||
                   hkError.code == .errorAuthorizationNotDetermined {
                    self.healthKitAuthorised = false
                    self.sleepBedtime  = nil
                    self.sleepWakeTime = nil
                } else {
                    self.healthKitAuthorised = true
                    self.fetchSleepData()
                }
            }
        }
        healthStore.execute(probe)
    }

    func requestHealthKitPermission(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(false, nil); return
        }
        healthStore.requestAuthorization(toShare: [], read: [sleepType]) { [weak self] _, error in
            self?.probeSleepAccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                completion(self?.healthKitAuthorised ?? false, error)
            }
        }
    }

    func fetchSleepData() {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: HKQuery.predicateForSamples(
                withStart: Date().addingTimeInterval(-86400 * 7), end: Date(), options: .strictEndDate),
            limit: 20, sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let self = self, let samples = samples as? [HKCategorySample] else { return }
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

    private func syncSleepToServer(bedtime: Date, wakeTime: Date) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        let fmt = ISO8601DateFormatter()
        NetworkManager.shared.post(endpoint: "/sync_sleep", body: [
            "email": email,
            "sleep_start": fmt.string(from: bedtime),
            "sleep_end":   fmt.string(from: wakeTime)
        ]) { _ in }
    }

    // MARK: - Server API

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
                // Push to ESP32 so bulb can run them without the app
                if let schedules = self?.schedules {
                    self?.activeBLEManager?.pushAllSchedules(schedules)
                }
            }
        }
    }

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

    func analyseUsage(bulbId: String) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/analyse_usage",
                                   body: ["email": email, "bulb_id": bulbId]) { [weak self] _ in
            self?.loadSuggestions(for: bulbId)
        }
    }

    func addSchedule(_ schedule: NewScheduleRequest, completion: @escaping (Bool) -> Void) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else {
            completion(false); return
        }
        var body: [String: Any] = [
            "email": email,
            "bulb_id": schedule.bulbId,
            "schedule_name": schedule.name,
            "trigger_hour": schedule.triggerHour,
            "trigger_minute": schedule.triggerMinute,
            "action": schedule.action.rawValue,
            "brightness": schedule.brightness,
            "colour_temp": schedule.colourTemp,
            "days_of_week": schedule.daysOfWeek
        ]
        if let eh = schedule.endHour   { body["end_hour"]   = eh }
        if let em = schedule.endMinute { body["end_minute"] = em }
        NetworkManager.shared.post(endpoint: "/add_schedule", body: body) { [weak self] result in
            if case .success = result {
                self?.loadSchedules(for: schedule.bulbId)
                // loadSchedules will push the full updated list to the ESP32
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    func toggleSchedule(_ id: Int, enabled: Bool) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/update_schedule", body: [
            "email": email, "schedule_id": id, "is_enabled": enabled ? 1 : 0
        ]) { [weak self] _ in
            self?.loadSchedules()   // loadSchedules pushes updated list to ESP32
        }
    }

    func deleteSchedule(_ id: Int, bulbId: String) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/delete_schedule", body: [
            "email": email, "schedule_id": id
        ]) { [weak self] _ in
            self?.loadSchedules(for: bulbId)  // loadSchedules pushes updated list to ESP32
        }
    }

    func respondToSuggestion(id: Int, response: String, bulbId: String) {
        guard let email = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/respond_suggestion", body: [
            "email": email, "suggestion_id": id, "response": response
        ]) { [weak self] _ in
            self?.loadSuggestions(for: bulbId)
            if response != "dismiss" { self?.loadSchedules(for: bulbId) }
        }
    }

    func logUsageEvent(email: String, bulbId: String, eventType: String,
                       power: Bool?, brightness: Int?, colourTemp: Int?) {
        var body: [String: Any] = ["email": email, "bulb_id": bulbId, "event_type": eventType]
        if let p = power      { body["power"]       = p ? 1 : 0 }
        if let b = brightness { body["brightness"]  = b }
        if let c = colourTemp { body["colour_temp"] = c }
        NetworkManager.shared.post(endpoint: "/log_usage", body: body) { _ in }
    }

    func setAutoSchedule(enabled: Bool) {
        autoScheduleEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "autoScheduleEnabled")
        syncLocalNotifications()
    }

    // MARK: - Parsing helpers

    static func parseSchedule(_ d: [String: Any]) -> BulbSchedule? {
        guard let id        = d["id"]             as? Int,
              let bulbId    = d["bulb_id"]        as? String,
              let name      = d["schedule_name"]  as? String,
              let actionRaw = d["action"]         as? String,
              let action    = ScheduleAction(rawValue: actionRaw),
              let tH        = d["trigger_hour"]   as? Int,
              let tM        = d["trigger_minute"] as? Int else { return nil }
        return BulbSchedule(
            id: id, bulbId: bulbId, scheduleName: name,
            scheduleType: d["schedule_type"] as? String  ?? "manual",
            triggerHour: tH, triggerMinute: tM,
            endHour:    d["end_hour"]    as? Int,
            endMinute:  d["end_minute"]  as? Int,
            action: action,
            brightness:  d["brightness"]   as? Int    ?? 255,
            colourTemp:  d["colour_temp"]  as? Int    ?? 128,
            isEnabled:  (d["is_enabled"]   as? Bool)  ?? true,
            confidence:  d["confidence"]   as? Double ?? 1.0,
            source:      d["source"]       as? String ?? "manual",
            daysOfWeek:  d["days_of_week"] as? String ?? "1,2,3,4,5,6,7"
        )
    }

    static func parseSuggestion(_ d: [String: Any]) -> ScheduleSuggestion? {
        guard let id        = d["id"]              as? Int,
              let stype     = d["suggestion_type"] as? String,
              let actionRaw = d["action"]          as? String,
              let action    = ScheduleAction(rawValue: actionRaw),
              let tH        = d["trigger_hour"]    as? Int,
              let tM        = d["trigger_minute"]  as? Int else { return nil }
        return ScheduleSuggestion(
            id: id, suggestionType: stype,
            triggerHour: tH, triggerMinute: tM,
            windowStartHour:   d["window_start_hour"]   as? Int,
            windowStartMinute: d["window_start_minute"] as? Int,
            windowEndHour:     d["window_end_hour"]     as? Int,
            windowEndMinute:   d["window_end_minute"]   as? Int,
            action: action,
            brightness:       d["brightness"]        as? Int    ?? 255,
            colourTemp:       d["colour_temp"]        as? Int    ?? 128,
            confidence:       d["confidence"]         as? Double ?? 0.0,
            observationCount: d["observation_count"]  as? Int    ?? 0,
            status:           d["status"]             as? String ?? "pending"
        )
    }
}

// MARK: - Request Model

struct NewScheduleRequest {
    var bulbId: String
    var name: String
    var triggerHour: Int
    var triggerMinute: Int
    var endHour: Int?
    var endMinute: Int?
    var action: ScheduleAction
    var brightness: Int
    var colourTemp: Int
    var daysOfWeek: String
}

// MARK: - Notification name

extension Notification.Name {
    static let scheduleTriggered = Notification.Name("scheduleTriggered")
}
