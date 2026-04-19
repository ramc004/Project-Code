import SwiftUI

struct SavedBulbControlView: View {
    let savedBulb: SavedBulb

    @StateObject private var bleManager = BLEManager()
    @State private var isConnecting = true
    @State private var connectionFailed = false
    @State private var showDeleteConfirm = false
    @State private var showEditName = false
    @State private var editedName = ""
    @State private var editedRoom = ""
    @Environment(\.dismiss) var dismiss

    private var userEmail: String {
        UserDefaults.standard.string(forKey: "currentUserEmail") ?? ""
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.92, blue: 1.0),
                    Color(red: 0.98, green: 0.94, blue: 0.9),
                    Color(red: 0.9,  green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if isConnecting {
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.5)
                    Text("Connecting to \(savedBulb.bulb_name)...")
                        .font(.headline).foregroundColor(.gray)
                }
            } else if connectionFailed {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60)).foregroundColor(.orange)
                    Text("Unable to Connect").font(.title2).bold()
                    if savedBulb.is_simulated {
                        Text("This is a simulated bulb. Make sure Simulator Mode is enabled in Settings.")
                            .font(.subheadline).foregroundColor(.gray)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    } else {
                        Text("Make sure the strip is powered on and nearby")
                            .font(.subheadline).foregroundColor(.gray)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                    Button("Try Again") {
                        isConnecting = true; connectionFailed = false; connectToBulb()
                    }
                    .buttonStyle(ModernButtonStyle(backgroundColor: .blue)).padding(.horizontal, 60)
                    Button("Go Back") { dismiss() }
                        .buttonStyle(ModernButtonStyle(backgroundColor: .gray)).padding(.horizontal, 60)
                }
            } else {
                ScrollView {
                    VStack(spacing: 30) {

                        // ── Header ──────────────────────────────────────────
                        HStack {
                            Button(action: { bleManager.disconnect(); dismiss() }) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 20, weight: .bold))
                            }
                            .buttonStyle(CircularIconButtonStyle(backgroundColor: .blue, foregroundColor: .white))

                            Spacer()

                            // Schedule button
                            NavigationLink(destination: ScheduleView(bulbId: savedBulb.bulb_id,
                                                                      bulbName: savedBulb.bulb_name)) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .buttonStyle(CircularIconButtonStyle(
                                backgroundColor: Color(red: 0.4, green: 0.3, blue: 0.9),
                                foregroundColor: .white))

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

                        // ── Bulb Visual ─────────────────────────────────────
                        BulbVisualView(state: bleManager.bulbState).padding(.top, 20)

                        // ── Device name ─────────────────────────────────────
                        VStack(spacing: 5) {
                            Text(savedBulb.bulb_name).font(.title).bold()
                            if let room = savedBulb.room_name, !room.isEmpty {
                                Text(room).font(.subheadline).foregroundColor(.gray)
                            }
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

                        // ── Power Toggle ────────────────────────────────────
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

                        // ── Brightness ──────────────────────────────────────
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

                        // ── Colour Temperature ──────────────────────────────
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Colour Temperature")
                                .font(.headline)

                            // Labels
                            HStack {
                                Label("Cool", systemImage: "snowflake")
                                    .font(.caption).foregroundColor(Color(red: 0.75, green: 0.9, blue: 1))
                                Spacer()
                                Label("Warm", systemImage: "sun.max.fill")
                                    .font(.caption).foregroundColor(Color(red: 1, green: 0.75, blue: 0.4))
                            }

                            // Gradient track with slider overlaid
                            ZStack(alignment: .center) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.85, green: 0.95, blue: 1.0), // cool left
                                                Color(red: 1.0,  green: 0.75, blue: 0.4)  // warm right
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 10)

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

                            // Presets
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

                        // ── Effects ─────────────────────────────────────────
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

            // ── Edit Name Dialog ─────────────────────────────────────────────
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
                            Button("Save") { updateBulbDetails() }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .blue))
                                .disabled(editedName.isEmpty)
                        }
                    }
                    .padding().frame(width: 320).background(Color.white).cornerRadius(20).shadow(radius: 20)
                }
            }

            // ── Delete Confirmation ──────────────────────────────────────────
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
            // Register immediately so the in-app timer can fire schedules
            // even before the peripheral connection completes.
            ScheduleManager.shared.registerActiveBLEManager(bleManager, for: savedBulb.bulb_id)
            connectToBulb()
            // Load schedules so the in-app timer can fire them
            ScheduleManager.shared.loadSchedules(for: savedBulb.bulb_id)
        }
        .onDisappear {
            // Do NOT disconnect BLE or unregister here.
            // Keeping the connection alive means:
            //  (a) The ESP32 autonomous engine already has schedules in flash and fires them independently.
            //  (b) If the notification fires while the app is foregrounded (e.g. user on HomeView),
            //      executeSchedule can still send the BLE command directly.
            // BLE is disconnected only when the user explicitly leaves via the back button (see dismiss() calls).
        }
        // UI sync when a schedule fires (BLE already sent by ScheduleManager.executeSchedule)
        .onReceive(NotificationCenter.default.publisher(for: .scheduleTriggered)) { notif in
            guard let schedule = notif.userInfo?["schedule"] as? BulbSchedule,
                  schedule.bulbId == savedBulb.bulb_id else { return }
            syncUIState(from: schedule)
        }
        // When BLE connects: register BLEManager and immediately reload+push schedules to ESP32 flash.
        // This guarantees the ESP32 autonomous engine has the latest schedule list even if
        // loadSchedules completed before the BLE connection was established (race condition).
        // When BLE disconnects: force-unregister so executeSchedule doesn't try a dead connection.
        .onReceive(bleManager.$connectedBulb) { connectedBulb in
            if connectedBulb != nil {
                ScheduleManager.shared.registerActiveBLEManager(bleManager, for: savedBulb.bulb_id)
                // Re-push schedules now that BLE is confirmed live.
                // loadSchedules completion handler calls pushAllSchedules automatically.
                ScheduleManager.shared.loadSchedules(for: savedBulb.bulb_id)
            } else {
                ScheduleManager.shared.forceUnregisterActiveBLEManager(for: savedBulb.bulb_id)
            }
        }
    }

    // MARK: - Sync UI after schedule fires (BLE already applied by ScheduleManager)
    func syncUIState(from schedule: BulbSchedule) {
        switch schedule.action {
        case .powerOn:
            bleManager.bulbState.power = true
        case .powerOff:
            bleManager.bulbState.power = false
        case .dimWarm:
            bleManager.bulbState.power = true
            bleManager.bulbState.brightness = UInt8(schedule.brightness)
            bleManager.bulbState.colourTemp = 255
        case .brightenCool:
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
        guard !bleManager.simulatorMode else { isConnecting = false; connectionFailed = true; return }
        bleManager.startScanning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if let bulb = bleManager.discoveredBulbs.first(where: { $0.id.uuidString == savedBulb.bulb_id }) {
                bleManager.connect(to: bulb); isConnecting = false
            } else {
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

    func updateBulbDetails() {
        guard let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/update_bulb", body: [
            "email": userEmail, "bulb_id": savedBulb.bulb_id,
            "bulb_name": editedName.trimmingCharacters(in: .whitespacesAndNewlines),
            "room_name": editedRoom.trimmingCharacters(in: .whitespacesAndNewlines)
        ]) { _ in showEditName = false }
    }

    func deleteBulb() {
        guard let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(endpoint: "/delete_bulb",
                                   body: ["email": userEmail, "bulb_id": savedBulb.bulb_id]) { _ in
            bleManager.disconnect(); dismiss()
        }
    }
}

struct SavedBulbControlView_Previews: PreviewProvider {
    static var previews: some View {
        SavedBulbControlView(savedBulb: SavedBulb(
            bulb_id: "test", bulb_name: "Living Room", room_name: "Living Room", is_simulated: false))
    }
}
