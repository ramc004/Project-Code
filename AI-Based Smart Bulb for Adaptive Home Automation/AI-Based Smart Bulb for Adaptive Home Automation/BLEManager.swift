// BLEManager.swift
// AI-Based Smart Bulb for Adaptive Home Automation

// Manages all Bluetooth Low Energy (BLE) communication between the iOS app and the ESP32 smart bulb hardware
// Also provides a Simulator Mode that injects virtual bulbs so the full app flow can be tested without hardware

// Architecture:
//   - BLEManager matches CBCentralManagerDelegate and CBPeripheralDelegate to handle the full BLE lifecycle: scanning → discovery → connection → service/characteristic discovery → read/write → disconnection
//   - All published properties are updated on the main thread so SwiftUI views can observe them directly
//   - BLE UUIDs are hardcoded to match the GATT service defined in the ESP32 Arduino sketch
// Any change here is be mirrored in the firmware

import Foundation
import CoreBluetooth
import Combine

// MARK: - Smart Bulb Model

/// Represents a smart bulb discovered during a BLE scan or created as a simulated device in Simulator Mode

/// Fits to "Identifiable" for use in SwiftUI lists and "Equatable" for de-duplication during scanning (equality is based on "id" only)
struct SmartBulb: Identifiable, Equatable {

    /// The unique identifier of the bulb, either the peripheral's BLE UUID (real hardware) or a locally generated UUID (simulated)
    let id: UUID

    /// The advertised display name of the bulb peripheral
    let name: String

    /// The underlying Core Bluetooth peripheral "nil" for simulated bulbs
    let peripheral: CBPeripheral?

    /// The most recently measured Received Signal Strength Indicator in dBm
    /// Simulated bulbs receive fixed values (-45, -55, -65)
    var rssi: Int

    /// Whether a BLE connection to this bulb is currently active
    var isConnected: Bool = false

    /// Whether this is a virtual simulated bulb rather than real ESP32 hardware
    var isSimulated: Bool = false

    /// Equality is determined only by "id" so that the same peripheral discovered multiple times is not added to the list more than once
    static func == (lhs: SmartBulb, rhs: SmartBulb) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Bulb State

/// A snapshot of the current lighting state of a connected bulb

/// All values are kept in sync with the ESP32 hardware via BLE characteristic reads and status notification updates.
/// In Simulator Mode, mutations are applied directly to this struct without any BLE write
struct BulbState {

    /// Whether the bulb is currently powered on
    var power: Bool = false

    /// The current brightness level (0–255)
    ///  255 = maximum brightness
    var brightness: UInt8 = 255

    /// The current colour temperature (0–255)
    /// 255 = full warm white (amber), 0 = full cool white
    var colourTemp: UInt8 = 255

    /// The current lighting effect mode
    /// 0 = solid, 1 = fade/pulse
    /// Additional modes may be defined in firmware
    var mode: UInt8 = 0
}

// MARK: - BLE Manager

/// An "ObservableObject" that owns the Core Bluetooth central manager and exposes published state for SwiftUI views to observe

/// In **real hardware mode**, "BLEManager" scans for peripherals advertising the app's custom GATT service UUID, connects on demand, discovers characteristics, reads initial state, and writes control values

/// In **Simulator Mode**, all BLE operations are bypassed
/// Three virtual "SmartBulb" values with stable UUIDs (persisted to "UserDefaults") are injected after a short artificial delay so the UI behaves as if real hardware is present
class BLEManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// The list of bulbs found during the most recent scan (real or simulated)
    @Published var discoveredBulbs: [SmartBulb] = []

    /// The bulb that is currently connected and being controlled, "nil" when idle"
    @Published var connectedBulb: SmartBulb?

    /// The live lighting state of the connected bulb, updated on BLE reads and notifications
    @Published var bulbState: BulbState = BulbState()

    /// Whether a scan is currently in progress
    @Published var isScanning: Bool = false

    /// A human-readable description of the current Bluetooth or simulator state, displayed in "AddBulbView" (e.g. "Ready", "Bluetooth Off", "Simulator Mode")
    @Published var bluetoothState: String = "Unknown"

    // MARK: - Simulator Mode

    /// Whether the app is currently running in Simulator Mode

    /// Reads "UserDefaults" on every access
    /// If no preference has been stored yet (first launch), it defaults to "true" and persists that value
    var simulatorMode: Bool {
        if UserDefaults.standard.object(forKey: "simulatorMode") == nil {
            UserDefaults.standard.set(true, forKey: "simulatorMode")
            return true
        }
        return UserDefaults.standard.bool(forKey: "simulatorMode")
    }

    // MARK: - Private Properties

    /// The Core Bluetooth central manager used for scanning and connecting
    private var centralManager: CBCentralManager!

    /// The currently connected peripheral, retained for writing characteristics
    private var connectedPeripheral: CBPeripheral?

    // GATT Service and Characteristic UUIDs
    // These must exactly match the UUIDs defined in the ESP32 Arduino sketch

    /// The primary GATT service UUID advertised by the ESP32 smart bulb
    private let serviceUUID    = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")

    /// Characteristic for the power on/off state (1 byte: 1 = on, 0 = off)
    private let powerUUID      = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

    /// Characteristic for the brightness level (1 byte: 0–255)
    private let brightnessUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a9")

    /// Characteristic for the colour temperature (3 bytes: warm, 0, cool)
    private let colourTempUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26aa")

    /// Characteristic for the lighting effect mode (1 byte: 0 = solid, 1 = fade/pulse)
    private let modeUUID       = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26ab")

    /// Characteristic for the full status notification packet (6 bytes: power, brightness, warmValue, 0, coolValue, mode). Subscribed for notifications on connection
    private let statusUUID     = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26ac")

    /// Characteristic for writing schedule entries to the ESP32's autonomous schedule engine
    private let scheduleUUID   = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26ad")

    /// Characteristic for syncing the current wall-clock time to the ESP32
    private let timeUUID       = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26ae")

    // Cached Characteristic References
    // Populated during service/characteristic discovery; cleared on disconnect

    private var powerCharacteristic: CBCharacteristic?
    private var brightnessCharacteristic: CBCharacteristic?
    private var colourTempCharacteristic: CBCharacteristic?
    private var modeCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var scheduleCharacteristic: CBCharacteristic?
    private var timeCharacteristic: CBCharacteristic?

    /// Stable UUIDs for the three simulated bulbs, persisted across sessions so the same bulb IDs appear every time Simulator Mode is used
    private var simulatedBulbIDs: [UUID] = []

    // MARK: - Initialisation

    /// Initialises the Core Bluetooth central manager and loads or generates stable UUIDs for the simulated bulbs
    /// If Simulator Mode is active, the Bluetooth state label is set immediately without waiting for a real Bluetooth state update
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        loadSimulatedBulbIDs()
        if simulatorMode {
            updateBluetoothStateForSimulator()
        }
    }

    // MARK: - Simulator Helpers

    /// Loads the three stable simulated bulb UUIDs from `UserDefaults`.
    ///
    /// If fewer than three UUIDs are stored (e.g. on first launch), a fresh
    /// set of three UUIDs is generated and persisted so they remain consistent
    /// across app sessions.
    private func loadSimulatedBulbIDs() {
        if let savedIDs = UserDefaults.standard.array(forKey: "simulatedBulbIDs") as? [String] {
            simulatedBulbIDs = savedIDs.compactMap { UUID(uuidString: $0) }
        }
        if simulatedBulbIDs.count < 3 {
            // Generate and persist three stable UUIDs for the simulated bulbs
            simulatedBulbIDs = [UUID(), UUID(), UUID()]
            UserDefaults.standard.set(simulatedBulbIDs.map { $0.uuidString }, forKey: "simulatedBulbIDs")
        }
    }

    /// Creates the three virtual `SmartBulb` values used in Simulator Mode.
    ///
    /// Each bulb uses a stable UUID (from `simulatedBulbIDs`) and a fixed
    /// RSSI value that decreases with index to simulate varying signal strengths.
    ///
    /// - Returns: An array of three simulated `SmartBulb` values.
    private func createSimulatedBulbs() -> [SmartBulb] {
        let names = [
            "Smart Strip (Simulated)",
            "Living Room Strip (Simulated)",
            "Bedroom Strip (Simulated)"
        ]
        return zip(simulatedBulbIDs, names).enumerated().map { index, pair in
            SmartBulb(id: pair.0, name: pair.1, peripheral: nil,
                      rssi: -45 - (index * 10), isSimulated: true)
        }
    }

    /// Sets the `bluetoothState` label to "Simulator Mode" on the main thread.
    private func updateBluetoothStateForSimulator() {
        DispatchQueue.main.async { self.bluetoothState = "Simulator Mode" }
    }

    /// Resets the manager's discovered and connected state when Simulator Mode
    /// is toggled in `SettingsView`.
    ///
    /// Clears `discoveredBulbs`, `connectedBulb`, and `isScanning`, then updates
    /// the Bluetooth state label to reflect the new mode. Called from `AddBulbView`
    /// after receiving a `SimulatorModeChanged` notification.
    func refreshSimulatorMode() {
        discoveredBulbs.removeAll()
        connectedBulb = nil
        isScanning    = false
        if simulatorMode {
            print("✅ Switched to Simulator Mode")
            updateBluetoothStateForSimulator()
        } else {
            print("✅ Switched to Real Hardware Mode")
            updateBluetoothStateMessage()
        }
    }

    // MARK: - Scanning

    /// Begins scanning for nearby smart bulb peripherals.
    ///
    /// In **Simulator Mode**: injects three virtual bulbs after a 1.5-second
    /// artificial delay, then automatically stops scanning after 5 seconds.
    ///
    /// In **real hardware mode**: starts a Core Bluetooth scan filtered to
    /// `serviceUUID`, de-duplicating results, and auto-stops after 10 seconds.
    /// Returns early if Bluetooth is not powered on.
    func startScanning() {
        if simulatorMode {
            isScanning     = true
            bluetoothState = "Simulator Mode"
            // Inject simulated bulbs after a brief artificial discovery delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.discoveredBulbs = self.createSimulatedBulbs()
            }
            // Auto-stop after 5 seconds in simulator mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.stopScanning() }
            return
        }

        guard centralManager.state == .poweredOn else {
            updateBluetoothStateMessage()
            return
        }
        discoveredBulbs.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        // Auto-stop after 10 seconds to avoid draining the battery
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.stopScanning() }
    }

    /// Stops an active BLE scan. In Simulator Mode only clears the `isScanning` flag.
    func stopScanning() {
        if simulatorMode { isScanning = false; return }
        centralManager.stopScan()
        isScanning = false
    }

    // MARK: - Connection

    /// Connects to the specified bulb.
    ///
    /// In **Simulator Mode**: simulates a 1-second connection delay, then marks
    /// the bulb as connected and initialises `bulbState` to default values.
    ///
    /// In **real hardware mode**: stops any active scan and delegates connection
    /// to the Core Bluetooth central manager.
    ///
    /// - Parameter bulb: The `SmartBulb` to connect to.
    func connect(to bulb: SmartBulb) {
        if simulatorMode && bulb.isSimulated {
            // Simulate connection delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                var connected = bulb
                connected.isConnected = true
                self.connectedBulb    = connected
                if let index = self.discoveredBulbs.firstIndex(where: { $0.id == bulb.id }) {
                    self.discoveredBulbs[index].isConnected = true
                }
                // Initialise with default off state
                self.bulbState = BulbState(power: false, brightness: 255, colourTemp: 255, mode: 0)
            }
            return
        }
        guard let peripheral = bulb.peripheral else { return }
        stopScanning()
        centralManager.connect(peripheral, options: nil)
    }

    /// Disconnects the currently connected bulb.
    ///
    /// In Simulator Mode: clears `connectedBulb` and resets the `isConnected`
    /// flag on all entries in `discoveredBulbs`. In real hardware mode:
    /// cancels the Core Bluetooth peripheral connection.
    func disconnect() {
        if simulatorMode {
            connectedBulb = nil
            for index in discoveredBulbs.indices { discoveredBulbs[index].isConnected = false }
            return
        }
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Control

    /// Sets the bulb's power state.
    ///
    /// In Simulator Mode: updates `bulbState.power` directly.
    /// In real hardware mode: writes a 1-byte value (1 = on, 0 = off) to
    /// the power characteristic.
    ///
    /// - Parameter on: `true` to turn the bulb on, `false` to turn it off.
    func setPower(_ on: Bool) {
        if simulatorMode { bulbState.power = on; return }
        guard let c = powerCharacteristic else { return }
        connectedPeripheral?.writeValue(Data([on ? 1 : 0]), for: c, type: .withResponse)
        bulbState.power = on
    }

    /// Sets the bulb's brightness level.
    ///
    /// In Simulator Mode: updates `bulbState.brightness` directly.
    /// In real hardware mode: writes the brightness byte to the brightness characteristic.
    ///
    /// - Parameter brightness: A value from 0 (off) to 255 (maximum brightness).
    func setBrightness(_ brightness: UInt8) {
        if simulatorMode { bulbState.brightness = brightness; return }
        guard let c = brightnessCharacteristic else { return }
        connectedPeripheral?.writeValue(Data([brightness]), for: c, type: .withResponse)
        bulbState.brightness = brightness
    }

    /// Sets the bulb's colour temperature.
    ///
    /// In Simulator Mode: updates `bulbState.colourTemp` directly.
    /// In real hardware mode: writes a 3-byte packet to the colour temperature
    /// characteristic. The Arduino firmware expects [warmByte, 0, coolByte] where
    /// `warmByte = temp` and `coolByte = 255 - temp`, mapping:
    /// - `temp = 255` → full warm white (warmByte=255, coolByte=0)
    /// - `temp = 0`   → full cool white (warmByte=0, coolByte=255)
    ///
    /// - Parameter temp: Colour temperature value from 0 (cool) to 255 (warm).
    func setColourTemp(_ temp: UInt8) {
        if simulatorMode {
            bulbState.colourTemp = temp
            return
        }
        guard let c = colourTempCharacteristic else { return }
        // Arduino byte[0]=warmValue, byte[2]=coolValue
        let warmByte: UInt8 = temp
        let coolByte: UInt8 = 255 - temp
        connectedPeripheral?.writeValue(Data([warmByte, 0, coolByte]), for: c, type: .withResponse)
        bulbState.colourTemp = temp
    }

    /// Sets the bulb's lighting effect mode.
    ///
    /// In Simulator Mode: updates `bulbState.mode` directly.
    /// In real hardware mode: writes the mode byte to the mode characteristic.
    ///
    /// - Parameter mode: Effect mode byte (0 = solid, 1 = fade/pulse).
    func setMode(_ mode: UInt8) {
        if simulatorMode { bulbState.mode = mode; return }
        guard let c = modeCharacteristic else { return }
        connectedPeripheral?.writeValue(Data([mode]), for: c, type: .withResponse)
        bulbState.mode = mode
    }

    // MARK: - Time Sync

    /// Sends the current wall-clock time to the ESP32 so it can run schedules autonomously.
    ///
    /// Writes a 4-byte packet [hour, minute, second, weekday] to the time characteristic.
    /// The weekday is converted from Gregorian convention (1=Sunday…7=Saturday) to
    /// Monday-based convention (1=Monday…7=Sunday) to match the ESP32 firmware.
    ///
    /// No-op in Simulator Mode. Should be called once immediately after connection,
    /// after a short delay to allow BLE negotiation to settle.
    func syncCurrentTime() {
        if simulatorMode { return }
        guard let c = timeCharacteristic else { return }
        let cal  = Calendar.current
        let now  = Date()
        let h    = UInt8(cal.component(.hour,   from: now))
        let m    = UInt8(cal.component(.minute, from: now))
        let s    = UInt8(cal.component(.second, from: now))
        // Convert Gregorian weekday (1=Sun..7=Sat) → Monday-based (1=Mon..7=Sun)
        let gWD   = cal.component(.weekday, from: now)
        let monWD = UInt8(gWD == 1 ? 7 : gWD - 1)
        connectedPeripheral?.writeValue(Data([h, m, s, monWD]), for: c, type: .withResponse)
        print("⏱ Time synced to ESP32: \(h):\(String(format: "%02d", m)):\(String(format: "%02d", s)) weekday=\(monWD)")
    }

    // MARK: - Schedule Push Helpers

    /// Maps a `ScheduleAction` enum case to the corresponding action byte expected
    /// by the ESP32 firmware's switch statement.
    ///
    /// The byte values must exactly match the `.ino` action constants.
    ///
    /// - Parameter action: The schedule action to encode.
    /// - Returns: A `UInt8` action byte for inclusion in the schedule payload.
    private func actionByte(for action: ScheduleAction) -> UInt8 {
        switch action {
        case .powerOn:          return 0
        case .powerOff:         return 1
        case .dimWarm:          return 2
        case .brightenCool:     return 3
        case .brightnessChange: return 4
        case .colourChange:     return 5
        }
    }

    /// Writes a single schedule entry into a specific flash slot on the ESP32.
    ///
    /// Encodes the schedule into a 9-byte payload:
    /// [command=1, slot, hour, minute, action, brightness, colourTemp, daysMask, isEnabled].
    /// The `daysMask` is a bitmask where bit 0 = Monday … bit 6 = Sunday.
    ///
    /// No-op in Simulator Mode or if `slot` is out of range (≥ 20).
    ///
    /// - Parameters:
    ///   - schedule: The `BulbSchedule` to encode and push.
    ///   - slot: The zero-based flash slot index on the ESP32 (max 19).
    func pushSchedule(_ schedule: BulbSchedule, slot: Int) {
        if simulatorMode { return }
        guard let c = scheduleCharacteristic, slot < 20 else { return }
        // Build a bitmask from the schedule's day array (1=Mon…7=Sun → bits 0…6)
        let daysMask = schedule.daysArray.reduce(UInt8(0)) { mask, day in
            mask | (1 << UInt8(day - 1))
        }
        let payload: [UInt8] = [
            1,                                       // command = add schedule
            UInt8(slot),
            UInt8(schedule.triggerHour),
            UInt8(schedule.triggerMinute),
            actionByte(for: schedule.action),
            UInt8(min(255, schedule.brightness)),
            UInt8(min(255, schedule.colourTemp)),
            daysMask,
            schedule.isEnabled ? 1 : 0
        ]
        connectedPeripheral?.writeValue(Data(payload), for: c, type: .withResponse)
        print("📅 Pushed schedule slot \(slot): \(schedule.scheduleName) @ \(schedule.timeString)")
    }

    /// Clears all schedule slots on the ESP32, then pushes the complete schedule list.
    ///
    /// Sends a command byte of 0 (clear all) first, then pushes each schedule with
    /// a 150 ms delay between writes to avoid dropping BLE packets during a burst.
    ///
    /// No-op in Simulator Mode.
    ///
    /// - Parameter schedules: The full list of `BulbSchedule` values to push.
    func pushAllSchedules(_ schedules: [BulbSchedule]) {
        if simulatorMode { return }
        guard let c = scheduleCharacteristic else { return }
        // Command 0 = clear all existing schedule slots on the ESP32
        connectedPeripheral?.writeValue(Data([0]), for: c, type: .withResponse)
        // Push each schedule with a staggered delay to prevent packet loss
        for (index, schedule) in schedules.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index + 1) * 0.15) {
                self.pushSchedule(schedule, slot: index)
            }
        }
        print("📅 Pushing \(schedules.count) schedules to ESP32")
    }

    /// Sends a delete command for a single schedule slot to the ESP32.
    ///
    /// Encodes the command as a 2-byte payload [command=2, slot].
    /// No-op in Simulator Mode or if `slot` is out of range (≥ 20).
    ///
    /// - Parameter slot: The zero-based flash slot index to delete (max 19).
    func deleteScheduleSlot(_ slot: Int) {
        if simulatorMode { return }
        guard let c = scheduleCharacteristic, slot < 20 else { return }
        let payload: [UInt8] = [2, UInt8(slot)]   // command = delete
        connectedPeripheral?.writeValue(Data(payload), for: c, type: .withResponse)
        print("🗑 Deleted ESP32 schedule slot \(slot)")
    }

    // MARK: - Bluetooth State Helper

    /// Updates `bluetoothState` with a human-readable label based on the current
    /// `CBCentralManager` state. Must be called on a thread safe for UI updates.
    private func updateBluetoothStateMessage() {
        DispatchQueue.main.async {
            switch self.centralManager.state {
            case .poweredOn:    self.bluetoothState = "Ready"
            case .poweredOff:   self.bluetoothState = "Bluetooth Off"
            case .unauthorized: self.bluetoothState = "Unauthorized"
            case .unsupported:  self.bluetoothState = "Not Supported"
            case .resetting:    self.bluetoothState = "Resetting"
            default:            self.bluetoothState = "Unknown"
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    /// Called whenever the central manager's Bluetooth state changes.
    ///
    /// In Simulator Mode, overrides the state label to "Simulator Mode".
    /// In real hardware mode, updates the label via `updateBluetoothStateMessage`.
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if simulatorMode { bluetoothState = "Simulator Mode"; return }
        updateBluetoothStateMessage()
    }

    /// Called each time a peripheral advertising `serviceUUID` is discovered.
    ///
    /// Creates a `SmartBulb` from the peripheral's identifier, name, and RSSI,
    /// and appends it to `discoveredBulbs` if not already present.
    /// No-op in Simulator Mode (simulated bulbs are injected via `startScanning`).
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if simulatorMode { return }
        let bulb = SmartBulb(
            id:          peripheral.identifier,
            name:        peripheral.name ?? "Unknown Device",
            peripheral:  peripheral,
            rssi:        RSSI.intValue,
            isSimulated: false
        )
        // De-duplicate — only add if this peripheral hasn't been discovered before
        if !discoveredBulbs.contains(where: { $0.id == bulb.id }) {
            discoveredBulbs.append(bulb)
        }
    }

    /// Called when a peripheral connection is successfully established.
    ///
    /// Retains the peripheral, sets it as the delegate, marks it as connected
    /// in `discoveredBulbs`, and begins service discovery.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if simulatorMode { return }
        connectedPeripheral = peripheral
        peripheral.delegate = self
        // Mark the matching entry in discoveredBulbs as connected
        if let index = discoveredBulbs.firstIndex(where: { $0.peripheral?.identifier == peripheral.identifier }) {
            discoveredBulbs[index].isConnected = true
            connectedBulb = discoveredBulbs[index]
        }
        // Begin GATT service discovery, filtered to the app's service UUID
        peripheral.discoverServices([serviceUUID])
    }

    /// Called when a peripheral disconnects, either intentionally or due to an error.
    ///
    /// Clears all connection state and cached characteristic references so
    /// the manager is ready for a fresh connection attempt.
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if simulatorMode { return }
        connectedPeripheral = nil
        connectedBulb       = nil
        // Reset the isConnected flag on the matching discovered bulb
        if let index = discoveredBulbs.firstIndex(where: { $0.peripheral?.identifier == peripheral.identifier }) {
            discoveredBulbs[index].isConnected = false
        }
        // Clear all cached characteristic references
        powerCharacteristic      = nil
        brightnessCharacteristic = nil
        colourTempCharacteristic = nil
        modeCharacteristic       = nil
        statusCharacteristic     = nil
        scheduleCharacteristic   = nil
        timeCharacteristic       = nil
    }

    /// Called when a connection attempt fails before being established.
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if simulatorMode { return }
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    /// Called when GATT service discovery completes for a connected peripheral.
    ///
    /// Iterates over the discovered services and triggers characteristic discovery
    /// for those matching `serviceUUID`.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if simulatorMode { return }
        guard error == nil, let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    /// Called when characteristic discovery completes for a GATT service.
    ///
    /// Caches each discovered characteristic reference, issues initial read requests
    /// for control characteristics to sync `bulbState`, and subscribes to status
    /// notifications. Once all characteristics are cached, syncs the current time
    /// and pushes the full schedule list after a short stabilisation delay.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if simulatorMode { return }
        guard error == nil, let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case powerUUID:
                powerCharacteristic = characteristic
                peripheral.readValue(for: characteristic)   // Read initial power state
            case brightnessUUID:
                brightnessCharacteristic = characteristic
                peripheral.readValue(for: characteristic)   // Read initial brightness
            case colourTempUUID:
                colourTempCharacteristic = characteristic
                peripheral.readValue(for: characteristic)   // Read initial colour temp
            case modeUUID:
                modeCharacteristic = characteristic
                peripheral.readValue(for: characteristic)   // Read initial mode
            case statusUUID:
                statusCharacteristic = characteristic
                // Subscribe for live status updates (replaces polling individual chars)
                peripheral.setNotifyValue(true, for: characteristic)
            case scheduleUUID:
                scheduleCharacteristic = characteristic
            case timeUUID:
                timeCharacteristic = characteristic
            default:
                break
            }
        }
        // Sync time and push schedules after a short delay to ensure BLE
        // negotiation has settled and all writes land successfully.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.syncCurrentTime()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.pushAllSchedules(ScheduleManager.shared.schedules)
            }
        }
    }

    /// Called when a characteristic value is read or a subscribed notification arrives.
    ///
    /// Updates the corresponding field in `bulbState`. The status characteristic
    /// delivers a 6-byte packet covering all state in one notification:
    /// [power, brightness, warmValue, 0, coolValue, mode].
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if simulatorMode { return }
        guard error == nil, let value = characteristic.value else { return }
        switch characteristic.uuid {
        case powerUUID:
            if let v = value.first { bulbState.power = (v == 1) }
        case brightnessUUID:
            if let v = value.first { bulbState.brightness = v }
        case colourTempUUID:
            if let v = value.first { bulbState.colourTemp = v }
        case modeUUID:
            if let v = value.first { bulbState.mode = v }
        case statusUUID:
            // Full status packet: [power, brightness, warmValue, 0, coolValue, mode]
            // warmValue (byte[2]) maps directly to colourTemp (255=warm, 0=cool)
            if value.count >= 6 {
                bulbState.power      = (value[0] == 1)
                bulbState.brightness = value[1]
                bulbState.colourTemp = value[2]   // warmValue: 255=warm, 0=cool
                bulbState.mode       = value[5]
            }
        default:
            break
        }
    }

    /// Called after a write-with-response completes. Logs any write errors.
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Write error: \(error.localizedDescription)")
        }
    }
}
