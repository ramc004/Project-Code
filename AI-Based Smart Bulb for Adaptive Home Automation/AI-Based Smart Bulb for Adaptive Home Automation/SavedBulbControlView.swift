// SavedBulbControlView.swift
// AI-Based Smart Bulb for Adaptive Home Automation
//
// The full-screen control panel for a previously paired bulb. On appearance it
// attempts a BLE connection and, once connected, exposes power, brightness,
// colour-temperature, and effect controls. Also provides access to the schedule
// editor and inline dialogs for renaming or removing the bulb.

import SwiftUI

// MARK: - Saved Bulb Control View

/// The primary control surface for a bulb that has already been paired and saved to the user's account

/// On appearance the view:
/// 1. Registers the shared "BLEManager" with "ScheduleManager" so in-app schedule timers can dispatch commands even before the peripheral connects
/// 2. Calls "connectToBulb()" which handles both real and simulated peripherals
/// 3. Loads the bulb's schedule list so the in-app timer is primed
///
/// Three top-level states are rendered inside the root "ZStack":
/// - **Connecting** – a centred spinner while BLE scanning is in progress
/// - **Connection failed** – an error card with retry / back actions
/// - **Connected** – a scrollable control panel (power, brightness, colour temperature, effects) together with a header row of icon buttons

/// Two modal overlays ("showEditName", "showDeleteConfirm") are layered above the main content inside the same "ZStack"
struct SavedBulbControlView: View {

    // MARK: Properties

    /// The persisted bulb record supplied by the calling list view
    let savedBulb: SavedBulb

    /// Manages Bluetooth scanning, connection, and characteristic writes
    @StateObject private var bleManager = BLEManager()

    /// "true" while BLE scanning / connection is in progress
    @State private var isConnecting = true

    /// "true" when the scan timeout elapses without finding the peripheral
    @State private var connectionFailed = false

    /// Controls visibility of the destructive remove-bulb confirmation overlay
    @State private var showDeleteConfirm = false

    /// Controls visibility of the edit-name / edit-room inline dialog
    @State private var showEditName = false

    /// Staging value for the bulb-name text field in the edit dialog
    @State private var editedName = ""

    /// Staging value for the room-name text field in the edit dialog
    @State private var editedRoom = ""

    /// Dismisses this view when the user presses the back button or after a successful delete
    @Environment(\.dismiss) var dismiss

    /// The email address of the currently logged-in user, read from "UserDefaults"
    /// Used when logging usage events to the server
    private var userEmail: String {
        UserDefaults.standard.string(forKey: "currentUserEmail") ?? ""
    }

    // MARK: Body

    var body: some View {
        ZStack {
            // Soft purple-peach-mint tricolour gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.92, blue: 1.0),
                    Color(red: 0.98, green: 0.94, blue: 0.9),
                    Color(red: 0.9,  green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Connecting State
            if isConnecting {
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.5)
                    Text("Connecting to \(savedBulb.bulb_name)...")
                        .font(.headline).foregroundColor(.gray)
                }

            // Connection-Failed State
            } else if connectionFailed {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60)).foregroundColor(.orange)
                    Text("Unable to Connect").font(.title2).bold()

                    // Provide context-specific guidance for simulated vs real bulbs
                    if savedBulb.is_simulated {
                        Text("This is a simulated bulb. Make sure Simulator Mode is enabled in Settings.")
                            .font(.subheadline).foregroundColor(.gray)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    } else {
                        Text("Make sure the strip is powered on and nearby")
                            .font(.subheadline).foregroundColor(.gray)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }

                    // Reset state and attempt BLE connection again
                    Button("Try Again") {
                        isConnecting = true; connectionFailed = false; connectToBulb()
                    }
                    .buttonStyle(ModernButtonStyle(backgroundColor: .blue)).padding(.horizontal, 60)

                    Button("Go Back") { dismiss() }
                        .buttonStyle(ModernButtonStyle(backgroundColor: .gray)).padding(.horizontal, 60)
                }

            // Connected State
            } else {
                ScrollView {
                    VStack(spacing: 30) {

                        // Header
                        // Row of icon buttons: back (left), schedule and more-menu (right)
                        HStack {
                            // Disconnect BLE and pop the view
                            Button(action: { bleManager.disconnect(); dismiss() }) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 20, weight: .bold))
                            }
                            .buttonStyle(CircularIconButtonStyle(backgroundColor: .blue, foregroundColor: .white))

                            Spacer()

                            // Navigate to the schedule editor for this bulb
                            NavigationLink(destination: ScheduleView(bulbId: savedBulb.bulb_id,
                                                                      bulbName: savedBulb.bulb_name)) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .buttonStyle(CircularIconButtonStyle(
                                backgroundColor: Color(red: 0.4, green: 0.3, blue: 0.9),
                                foregroundColor: .white))

                            // Context menu: rename or remove the bulb
                            Menu {
                                Button(action: {
                                    editedName = savedBulb.bulb_name
                                    editedRoom = savedBulb.room_name ?? ""
                                    showEditName = true
                                }) { Label("Edit Name", systemImage: "pencil") }

                                Button(role: .destructive, action: { showDeleteConfirm = true }) {
                                    Label("Remove Bulb", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 20, weight: .bold))
                            }
                            .buttonStyle(CircularIconButtonStyle(backgroundColor: .gray, foregroundColor: .white))
                        }
                        .padding(.horizontal).padding(.top, 30)

                        // Bulb Visual
                        // Animated illustration that reflects the current bulb state
                        BulbVisualView(state: bleManager.bulbState).padding(.top, 20)

                        // Device Name
                        VStack(spacing: 5) {
                            Text(savedBulb.bulb_name).font(.title).bold()

                            // Only show the room label when one has been assigned
                            if let room = savedBulb.room_name, !room.isEmpty {
                                Text(room).font(.subheadline).foregroundColor(.gray)
                            }

                            // Badge shown when either the saved record or the live
                            // BLE manager is operating in simulator mode
                            if savedBulb.is_simulated || bleManager.simulatorMode {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.circle.fill").font(.caption)
                                    Text("Simulated").font(.caption)
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1)).cornerRadius(8)
                            }
                        }

                        // Power Toggle
                        // Writes the new power state over BLE and logs the event to the server for AI-based usage analysis
                        Toggle("Power", isOn: Binding(
                            get: { bleManager.bulbState.power },
                            set: { newVal in
                                bleManager.setPower(newVal)
                                ScheduleManager.shared.logUsageEvent(
                                    email: userEmail, bulbId: savedBulb.bulb_id,
                                    eventType: newVal ? "power_on" : "power_off",
                                    power: newVal,
                                    brightness: Int(bleManager.bulbState.brightness),
                                    colourTemp: Int(bleManager.bulbState.colourTemp))
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .padding().background(Color.white.opacity(0.7)).cornerRadius(15).padding(.horizontal)

                        // Brightness
                        // Raw value is 0–255 (UInt8); the label converts to a 0–100 % percentage
                        // The drag-end gesture logs the final settled value to the server
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Brightness: \(Int((Double(bleManager.bulbState.brightness) / 255.0) * 100))%")
                                .font(.headline)
                            Slider(
                                value: Binding(
                                    get: { Double(bleManager.bulbState.brightness) },
                                    set: { bleManager.setBrightness(UInt8($0)) }
                                ),
                                in: 0...255, step: 1
                            )
                            .disabled(!bleManager.bulbState.power)
                        }
                        .padding().background(Color.white.opacity(0.7)).cornerRadius(15).padding(.horizontal)
                        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in
                            guard bleManager.bulbState.power else { return }
                            ScheduleManager.shared.logUsageEvent(
                                email: userEmail, bulbId: savedBulb.bulb_id,
                                eventType: "brightness_change", power: true,
                                brightness: Int(bleManager.bulbState.brightness),
                                colourTemp: Int(bleManager.bulbState.colourTemp))
                        })

                        // Colour Temperature
                        // 0 = coolest (blue-white), 255 = warmest (amber)
                        // A gradient-filled track visually reinforces the scale
                        // Three preset buttons jump to Cool (0), Neutral (128), and Warm (255)
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Colour Temperature")
                                .font(.headline)

                            // Cool / Warm end-point labels
                            HStack {
                                Label("Cool", systemImage: "snowflake")
                                    .font(.caption).foregroundColor(Color(red: 0.75, green: 0.9, blue: 1))
                                Spacer()
                                Label("Warm", systemImage: "sun.max.fill")
                                    .font(.caption).foregroundColor(Color(red: 1, green: 0.75, blue: 0.4))
                            }

                            // Gradient track with the interactive slider overlaid on top
                            ZStack(alignment: .center) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.85, green: 0.95, blue: 1.0), // cool (left)
                                                Color(red: 1.0,  green: 0.75, blue: 0.4)  // warm (right)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 10)

                                // Accent colour is cleared so the default blue thumb does not obscure the gradient track
                                Slider(
                                    value: Binding(
                                        get: { Double(bleManager.bulbState.colourTemp) },
                                        set: { bleManager.setColourTemp(UInt8($0)) }
                                    ),
                                    in: 0...255, step: 1
                                )
                                .disabled(!bleManager.bulbState.power)
                                .accentColor(.clear)
                            }

                            // Quick-select preset buttons
                            HStack(spacing: 12) {
                                Button(action: { bleManager.setColourTemp(0) }) {
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(Color(red: 0.85, green: 0.95, blue: 1.0))
                                            .frame(width: 36, height: 36)
                                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 2))
                                        Text("Cool").font(.caption).foregroundColor(.primary)
                                    }
                                }
                                Button(action: { bleManager.setColourTemp(128) }) {
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 0.85, green: 0.95, blue: 1.0),
                                                        Color(red: 1.0,  green: 0.75, blue: 0.4)
                                                    ],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: 36, height: 36)
                                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 2))
                                        Text("Neutral").font(.caption).foregroundColor(.primary)
                                    }
                                }
                                Button(action: { bleManager.setColourTemp(255) }) {
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(Color(red: 1.0, green: 0.75, blue: 0.4))
                                            .frame(width: 36, height: 36)
                                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 2))
                                        Text("Warm").font(.caption).foregroundColor(.primary)
                                    }
                                }
                            }
                        }
                        .padding().background(Color.white.opacity(0.7)).cornerRadius(15).padding(.horizontal)
                        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in
                            guard bleManager.bulbState.power else { return }
                            ScheduleManager.shared.logUsageEvent(
                                email: userEmail, bulbId: savedBulb.bulb_id,
                                eventType: "colour_change", power: true,
                                brightness: Int(bleManager.bulbState.brightness),
                                colourTemp: Int(bleManager.bulbState.colourTemp))
                        })

                        // Effects
                        // mode 0 = Solid, mode 1 = Pulse
                        // Additional modes can be appended to the grid without layout changes
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Effects").font(.headline)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                EffectButton(title: "Solid", icon: "circle.fill",
                                             isSelected: bleManager.bulbState.mode == 0) { bleManager.setMode(0) }
                                EffectButton(title: "Pulse", icon: "waveform",
                                             isSelected: bleManager.bulbState.mode == 1) { bleManager.setMode(1) }
                            }
                        }
                        .padding().background(Color.white.opacity(0.7)).cornerRadius(15).padding(.horizontal)

                        Spacer(minLength: 50)
                    }
                }
            }

            // Edit Name Dialog
            // Modal card for renaming the bulb and reassigning its room
            // Staged edits are only committed when the user taps Save
            if showEditName {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text("Edit Bulb Details").font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bulb Name").font(.subheadline).bold()
                            TextField("Bulb name", text: $editedName).textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Room").font(.subheadline).bold()
                            TextField("Room name (optional)", text: $editedRoom).textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        HStack(spacing: 15) {
                            Button("Cancel") { showEditName = false }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                            // Save is disabled until a non-empty bulb name is entered
                            Button("Save") { updateBulbDetails() }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .blue))
                                .disabled(editedName.isEmpty)
                        }
                    }
                    .padding().frame(width: 320).background(Color.white).cornerRadius(20).shadow(radius: 20)
                }
            }

            // Delete Confirmation
            // Destructive overlay requiring explicit confirmation before the bulb record is removed from the user's account on the server
            if showDeleteConfirm {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "trash.fill").font(.system(size: 50)).foregroundColor(.red)
                        Text("Remove Bulb?").font(.headline)
                        Text("This will remove \(savedBulb.bulb_name) from your account. It can be paired to another account afterwards.")
                            .font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center)
                        HStack(spacing: 15) {
                            Button("No") { showDeleteConfirm = false }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                            Button("Yes, Remove") { deleteBulb() }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .red))
                        }
                    }
                    .padding().frame(width: 300).background(Color.white).cornerRadius(20).shadow(radius: 20)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Register immediately so the in-app timer can fire schedules even before the peripheral connection completes
            ScheduleManager.shared.registerActiveBLEManager(bleManager, for: savedBulb.bulb_id)
            connectToBulb()
            // Load schedules so the in-app timer can fire them
            ScheduleManager.shared.loadSchedules(for: savedBulb.bulb_id)
        }
        .onDisappear {
            // Do NOT disconnect BLE or unregister here
            // Keeping the connection alive means:
            //  (a) The ESP32 autonomous engine already has schedules in flash and fires them independently
            //  (b) If the notification fires while the app is foregrounded (e.g. user on HomeView), executeSchedule can still send the BLE command directly
            // BLE is disconnected only when the user explicitly leaves via the back button (see dismiss() calls)
        }
        // UI sync when a schedule fires (BLE already sent by ScheduleManager.executeSchedule)
        .onReceive(NotificationCenter.default.publisher(for: .scheduleTriggered)) { notif in
            guard let schedule = notif.userInfo?["schedule"] as? BulbSchedule,
                  schedule.bulbId == savedBulb.bulb_id else { return }
            syncUIState(from: schedule)
        }
        // When BLE connects: register BLEManager and immediately reload+push schedules to ESP32 flash
        // This guarantees the ESP32 autonomous engine has the latest schedule list even if loadSchedules completed before the BLE connection was established (race condition)
        // When BLE disconnects: force-unregister so executeSchedule doesn't try a dead connection
        .onReceive(bleManager.$connectedBulb) { connectedBulb in
            if connectedBulb != nil {
                ScheduleManager.shared.registerActiveBLEManager(bleManager, for: savedBulb.bulb_id)
                // Re-push schedules now that BLE is confirmed live loadSchedules completion handler calls pushAllSchedules automatically
                ScheduleManager.shared.loadSchedules(for: savedBulb.bulb_id)
            } else {
                ScheduleManager.shared.forceUnregisterActiveBLEManager(for: savedBulb.bulb_id)
            }
        }
    }

    // MARK: - Sync UI After Schedule Fires

    /// Updates the in-memory "bulbState" to reflect a schedule action that "ScheduleManager.executeSchedule" has already dispatched over BLE
    
    /// Called in response to a ".scheduleTriggered" notification, ensuring the on-screen controls stay in sync without issuing a redundant BLE write
    
    /// - Parameter schedule: The "BulbSchedule" that was just executed
    func syncUIState(from schedule: BulbSchedule) {
        switch schedule.action {
        case .powerOn:
            bleManager.bulbState.power = true
        case .powerOff:
            bleManager.bulbState.power = false
        case .dimWarm:
            // Dims to the scheduled brightness and shifts to warm white (255)
            bleManager.bulbState.power = true
            bleManager.bulbState.brightness = UInt8(schedule.brightness)
            bleManager.bulbState.colourTemp = 255
        case .brightenCool:
            // Brightens to the scheduled level and shifts to cool white (0)
            bleManager.bulbState.power = true
            bleManager.bulbState.brightness = UInt8(schedule.brightness)
            bleManager.bulbState.colourTemp = 0
        case .brightnessChange:
            bleManager.bulbState.brightness = UInt8(schedule.brightness)
        case .colourChange:
            bleManager.bulbState.colourTemp = UInt8(schedule.colourTemp)
        }
    }

    // MARK: - Connect

    /// Initiates a BLE connection to the peripheral identified by "savedBulb"
    
    /// **Simulated path**  - if the saved record is flagged as simulated, checks that simulator mode is active, then after a 1-second artificial delay constructs a fake "SmartBulb" and calls "bleManager.connect(to:)"

    /// **Real path** - starts BLE scanning and polls "discoveredBulbs" after 5 s
    /// If the peripheral has not appeared a second 5-second window is allowed before marking the connection as failed and stopping the scan
    func connectToBulb() {
        if savedBulb.is_simulated {
            guard bleManager.simulatorMode else { isConnecting = false; connectionFailed = true; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let sim = SmartBulb(id: UUID(uuidString: savedBulb.bulb_id) ?? UUID(),
                                    name: savedBulb.bulb_name, peripheral: nil,
                                    rssi: -50, isConnected: true, isSimulated: true)
                bleManager.connect(to: sim)
                isConnecting = false
                // BLEManager already registered in onAppear; just ensure connected flag is set
            }
            return
        }

        // Real-hardware path: simulator mode must be off
        guard !bleManager.simulatorMode else { isConnecting = false; connectionFailed = true; return }
        bleManager.startScanning()

        // First scan window, 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if let bulb = bleManager.discoveredBulbs.first(where: { $0.id.uuidString == savedBulb.bulb_id }) {
                bleManager.connect(to: bulb); isConnecting = false
            } else {
                // Second scan window, additional 5 seconds before giving up
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if let bulb = bleManager.discoveredBulbs.first(where: { $0.id.uuidString == savedBulb.bulb_id }) {
                        bleManager.connect(to: bulb); isConnecting = false
                    } else {
                        isConnecting = false; connectionFailed = true; bleManager.stopScanning()
                    }
                }
            }
        }
    }

    // MARK: - Update Bulb Details

    /// Persists a renamed bulb and/or updated room assignment to the server
    
    /// Trims whitespace from both fields before posting to "/update_bulb"
    /// Dismisses the edit dialog on completion regardless of the server response
    func updateBulbDetails() {
        guard let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/update_bulb", body: [
            "email": userEmail, "bulb_id": savedBulb.bulb_id,
            "bulb_name": editedName.trimmingCharacters(in: .whitespacesAndNewlines),
            "room_name": editedRoom.trimmingCharacters(in: .whitespacesAndNewlines)
        ]) { _ in showEditName = false }
    }

    // MARK: - Delete Bulb

    /// Removes the bulb from the user's account on the server, then disconnects BLE and dismisses this view
    
    /// The bulb hardware itself is unaffected and can be paired to a different account afterwards
    func deleteBulb() {
        guard let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/delete_bulb",
                                   body: ["email": userEmail, "bulb_id": savedBulb.bulb_id]) { _ in
            bleManager.disconnect(); dismiss()
        }
    }
}

// MARK: - Preview

struct SavedBulbControlView_Previews: PreviewProvider {
    static var previews: some View {
        SavedBulbControlView(savedBulb: SavedBulb(
            bulb_id: "test", bulb_name: "Living Room", room_name: "Living Room", is_simulated: false))
    }
}
