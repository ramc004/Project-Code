// AddBulbView.swift
// AI-Based Smart Bulb for Adaptive Home Automation

// Presents the bulb pairing screen, allowing the user to scan for nearby ESP32 bulbs via Bluetooth Low Energy (or simulated bulbs in Simulator Mode), assign a name and optional room, and save the bulb to their backend account

import SwiftUI

/// The bulb pairing screen, navigated to from "HomeView" via the (+) button

/// On appearance, "BLEManager" begins scanning for nearby "SmartBulb" devices.
/// Discovered bulbs are shown in a scrollable list
/// Tapping a bulb opens a naming dialog where the user can assign a display name and optional room before saving the bulb to the backend via "/add_bulb"

/// In Simulator Mode, "BLEManager" injects virtual bulbs instead of performing real Bluetooth discovery, allowing the full pairing flow to be tested without physical ESP32 hardware

/// Scanning stops automatically when the view disappears, and restarts with refreshed simulator state whenever a "SimulatorModeChanged" notification is received from "SettingsView"
struct AddBulbView: View {

    // MARK: - State

    /// The BLE manager responsible for scanning and maintaining the list of discovered bulbs
    /// Created fresh each time this view is presented
    @StateObject private var bleManager = BLEManager()

    /// The bulb selected by the user from the discovered list, held until the naming dialog is confirmed or cancelled
    @State private var selectedBulb: SmartBulb?

    /// Controls visibility of the bulb naming dialog overlay
    @State private var showNameDialog = false

    /// The display name the user assigns to the bulb in the naming dialog
    @State private var bulbName = ""

    /// The optional room name the user assigns to the bulb in the naming dialog
    @State private var roomName = ""

    /// True while the save request is in flight to prevent duplicate submissions
    @State private var savingBulb = false

    /// An inline error message shown when a save or validation step fails
    @State private var errorMessage = ""

    /// A brief success message shown after a bulb is saved successfully
    @State private var successMessage = ""

    /// Used to dismiss this view and return to "HomeView"
    @Environment(\.dismiss) var dismiss

    // MARK: - Body

    var body: some View {
        ZStack {
            // Soft purple-peach-mint diagonal gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.92, blue: 1.0),
                    Color(red: 0.98, green: 0.94, blue: 0.9),
                    Color(red: 0.9,  green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {

                // Header
                // Dismiss button (✕) on the left, current Bluetooth state on the right
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(CircularIconButtonStyle(backgroundColor: .blue, foregroundColor: .white))

                    Spacer()

                    // Live Bluetooth state label (e.g. "On", "Off", "Unauthorised")
                    Text("Bluetooth: \(bleManager.bluetoothState)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                .padding(.top, 30)

                Text("Add Smart Bulb")
                    .font(.largeTitle)
                    .bold()

                // Mode Badge
                // Shows an orange Simulator Mode badge when running without hardware, or a plain "Searching..." hint in normal Bluetooth mode
                if bleManager.simulatorMode {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill").foregroundColor(.orange)
                        Text("Simulator Mode - Testing without hardware")
                            .font(.caption).foregroundColor(.orange)
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                } else {
                    Text("Searching for nearby bulbs...")
                        .font(.subheadline).foregroundColor(.gray)
                }

                // Scan Toggle Button
                // Starts or stops BLE scanning
                // Turns red and shows "Stop Scanning" while a scan is in progress
                Button(action: {
                    if bleManager.isScanning {
                        bleManager.stopScanning()
                    } else {
                        bleManager.startScanning()
                    }
                }) {
                    HStack {
                        Image(systemName: bleManager.isScanning ? "stop.circle.fill" : "arrow.clockwise")
                        Text(bleManager.isScanning ? "Stop Scanning" : "Scan Again")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernButtonStyle(backgroundColor: bleManager.isScanning ? .red : .blue))
                .padding(.horizontal)

                // Inline Messages
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red).font(.caption)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }

                if !successMessage.isEmpty {
                    Text(successMessage)
                        .foregroundColor(.green).font(.caption)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }

                // Discovered Bulbs List / Empty State
                if bleManager.discoveredBulbs.isEmpty {
                    // Empty state, icon and hint text vary by scan state and mode
                    Spacer()
                    VStack(spacing: 15) {
                        Image(systemName: bleManager.isScanning
                              ? "antenna.radiowaves.left.and.right"
                              : "lightbulb.slash")
                            .font(.system(size: 60)).foregroundColor(.gray)

                        Text(bleManager.isScanning ? "Scanning..." : "No bulbs found")
                            .font(.title3).foregroundColor(.gray)

                        if bleManager.simulatorMode {
                            Text("Simulated bulbs will appear after scanning")
                                .font(.caption).foregroundColor(.gray)
                                .multilineTextAlignment(.center).padding(.horizontal, 40)
                        } else {
                            Text("Make sure your ESP32 bulb is powered on and nearby")
                                .font(.caption).foregroundColor(.gray)
                                .multilineTextAlignment(.center).padding(.horizontal, 40)
                        }
                    }
                    Spacer()
                } else {
                    // Scrollable list of discovered bulbs
                    // Tapping a row pre-fills the naming dialog with the bulb's advertised name and opens the dialog overlay
                    ScrollView {
                        VStack(spacing: 15) {
                            ForEach(bleManager.discoveredBulbs) { bulb in
                                Button(action: {
                                    selectedBulb   = bulb
                                    bulbName       = bulb.name
                                    roomName       = ""
                                    showNameDialog = true
                                }) {
                                    DiscoveredBulbRowView(bulb: bulb)
                                }
                            }
                        }
                        .padding()
                    }
                }

                Spacer()
            }

            // Naming Dialog Overlay
            // Modal card shown after selecting a bulb
            // Collects a display name (required) and an optional room name before saving to the backend
            if showNameDialog {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()

                    VStack(spacing: 20) {
                        Text("Name Your Bulb").font(.headline)

                        // Simulated bulb indicator inside the dialog
                        if let bulb = selectedBulb, bulb.isSimulated {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill").font(.caption)
                                Text("This is a simulated bulb for testing").font(.caption)
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1)).cornerRadius(8)
                        }

                        // Bulb name input (required, "Add Bulb" disabled if empty)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bulb Name").font(.subheadline).bold()
                            TextField("e.g., Living Room Light", text: $bulbName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        // Room name input (optional)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Room (Optional)").font(.subheadline).bold()
                            TextField("e.g., Living Room", text: $roomName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        // Progress indicator shown while the save request is in flight
                        if savingBulb {
                            ProgressView("Saving...")
                        }

                        HStack(spacing: 15) {
                            // Cancel, dismisses the dialog without saving
                            Button("Cancel") {
                                showNameDialog = false
                                bulbName       = ""
                                roomName       = ""
                            }
                            .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                            .disabled(savingBulb)

                            // Add Bulb, disabled until a name is entered
                            Button("Add Bulb") { saveBulbToDatabase() }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .green))
                                .disabled(bulbName.isEmpty || savingBulb)
                        }
                    }
                    .padding()
                    .frame(width: 320)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(radius: 20)
                }
            }
        }
        .navigationBarHidden(true)
        // Begin scanning as soon as the view is visible
        .onAppear { bleManager.startScanning() }
        // Stop scanning when leaving the view to conserve battery
        .onDisappear { bleManager.stopScanning() }
        // React to Simulator Mode changes made in SettingsView: stop the current scan, refresh the mode flag, then restart scanning after a brief delay so BLEManager has time to reset its state
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SimulatorModeChanged"))) { _ in
            bleManager.stopScanning()
            bleManager.refreshSimulatorMode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                bleManager.startScanning()
            }
        }
    }

    // MARK: - Save Bulb

    /// Saves the selected bulb to the user's backend account via the "/add_bulb" endpoint
    
    /// The bulb's UUID, trimmed display name, trimmed room name, and simulated flag are included in the request body
    /// On HTTP 200 the success message is shown and the view dismisses after 1.5 seconds
    /// HTTP 409 indicates the bulb is already linked to this account
    /// Other non-200 responses display the server's error message inline
    func saveBulbToDatabase() {
        guard let bulb = selectedBulb,
              let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else {
            errorMessage = "User not logged in"
            return
        }

        savingBulb     = true
        errorMessage   = ""
        successMessage = ""

        // Debug output to confirm the correct bulb and simulated flag are being sent
        print("💾 Saving bulb to database:")
        print("   Name: \(bulb.name)")
        print("   ID: \(bulb.id.uuidString)")
        print("   isSimulated: \(bulb.isSimulated)")

        guard let url = URL(string: "\(APIConfig.baseURL)/add_bulb") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let requestData: [String: Any] = [
            "email":        userEmail,
            "bulb_id":      bulb.id.uuidString,
            "bulb_name":    bulbName.trimmingCharacters(in: .whitespacesAndNewlines),
            "room_name":    roomName.trimmingCharacters(in: .whitespacesAndNewlines),
            "is_simulated": bulb.isSimulated   // Required for correct filtering in HomeView
        ]

        print("   Request data: \(requestData)")

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestData, options: [])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                savingBulb = false

                if let httpResponse = response as? HTTPURLResponse {
                    print("   Response status: \(httpResponse.statusCode)")

                    if httpResponse.statusCode == 200 {
                        // Success, show confirmation and dismiss after a short delay
                        successMessage = "✅ Bulb added successfully!"
                        showNameDialog = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    } else if httpResponse.statusCode == 409 {
                        // Conflict, bulb is already linked to this account
                        errorMessage   = "This bulb is already added to your account"
                        showNameDialog = false
                    } else if let data = data,
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = json["message"] as? String {
                        // Server returned a descriptive error message
                        errorMessage = message
                    } else {
                        errorMessage = "Failed to add bulb. Please try again."
                    }
                } else {
                    errorMessage = "Network error. Please check your connection."
                }
            }
        }.resume()
    }
}

// MARK: - Discovered Bulb Row View

/// A row view representing a single bulb discovered during a BLE scan

/// Displays the bulb's name alongside a signal strength badge (for real hardware) or an orange simulated badge (for virtual bulbs)
/// The colour of the signal badge reflects the RSSI value: green = excellent, orange = good, red = weak
struct DiscoveredBulbRowView: View {

    /// The discovered bulb to display in this row
    let bulb: SmartBulb

    var body: some View {
        HStack(spacing: 15) {

            // Bulb Icon
            // For real bulbs: a coloured signal dot in the top-right corner
            // For simulated bulbs: an orange play-badge overlay instead
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 50, height: 50)

                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 25))
                    .foregroundColor(.yellow)

                if bulb.isSimulated {
                    // Orange play-badge for simulated bulbs
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.white)
                        )
                        .offset(x: 18, y: -18)
                } else {
                    // RSSI-coloured signal dot for real BLE hardware
                    Circle()
                        .fill(signalColor)
                        .frame(width: 12, height: 12)
                        .offset(x: 18, y: -18)
                }
            }

            // Bulb Info
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(bulb.name).font(.headline).foregroundColor(.primary)
                    // Small play icon next to the name for simulated bulbs
                    if bulb.isSimulated {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 10)).foregroundColor(.orange)
                    }
                }

                if !bulb.isSimulated {
                    // Signal strength text label for real hardware
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right").font(.caption)
                        Text("Signal: \(signalStrength)").font(.caption)
                    }
                    .foregroundColor(.gray)
                } else {
                    Text("Simulated for testing").font(.caption).foregroundColor(.orange)
                }
            }

            Spacer()

            // (+) icon indicating the row can be tapped to add the bulb
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.green)
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    // MARK: - Signal Helpers

    /// The colour of the RSSI signal dot based on the bulb's received signal strength
    
    /// - Green:  RSSI > -50 dBm (excellent)
    /// - Orange: RSSI > -70 dBm (good)
    /// - Red:    RSSI ≤ -70 dBm (weak)
    var signalColor: Color {
        if bulb.rssi > -50 { return .green }
        else if bulb.rssi > -70 { return .orange }
        else { return .red }
    }

    /// A human-readable signal strength label derived from the bulb's RSSI value

    /// - "Excellent": RSSI > -50 dBm
    /// - "Good":      RSSI > -70 dBm
    /// - "Weak":      RSSI ≤ -70 dBm
    var signalStrength: String {
        if bulb.rssi > -50 { return "Excellent" }
        else if bulb.rssi > -70 { return "Good" }
        else { return "Weak" }
    }
}

// MARK: - Preview

struct AddBulbView_Previews: PreviewProvider {
    static var previews: some View {
        AddBulbView()
    }
}
