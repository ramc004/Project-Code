import SwiftUI

struct AddBulbView: View {
    @StateObject private var bleManager = BLEManager()
    @State private var selectedBulb: SmartBulb?
    @State private var showNameDialog = false
    @State private var bulbName = ""
    @State private var roomName = ""
    @State private var savingBulb = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.92, blue: 1.0),
                    Color(red: 0.98, green: 0.94, blue: 0.9),
                    Color(red: 0.9, green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(CircularIconButtonStyle(backgroundColor: .blue, foregroundColor: .white))
                    
                    Spacer()
                    
                    Text("Bluetooth: \(bleManager.bluetoothState)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                .padding(.top, 30)
                
                Text("Add Smart Bulb")
                    .font(.largeTitle)
                    .bold()
                
                if bleManager.simulatorMode {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.orange)
                        Text("Simulator Mode - Testing without hardware")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                } else {
                    Text("Searching for nearby bulbs...")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // Scan Button
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
                
                // Messages
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                if !successMessage.isEmpty {
                    Text(successMessage)
                        .foregroundColor(.green)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Device List
                if bleManager.discoveredBulbs.isEmpty {
                    Spacer()
                    VStack(spacing: 15) {
                        Image(systemName: bleManager.isScanning ? "antenna.radiowaves.left.and.right" : "lightbulb.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text(bleManager.isScanning ? "Scanning..." : "No bulbs found")
                            .font(.title3)
                            .foregroundColor(.gray)
                        
                        if bleManager.simulatorMode {
                            Text("Simulated bulbs will appear after scanning")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        } else {
                            Text("Make sure your ESP32 bulb is powered on and nearby")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 15) {
                            ForEach(bleManager.discoveredBulbs) { bulb in
                                Button(action: {
                                    selectedBulb = bulb
                                    bulbName = bulb.name
                                    roomName = ""
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
            
            // Name Dialog Overlay
            if showNameDialog {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Text("Name Your Bulb")
                            .font(.headline)
                        
                        if let bulb = selectedBulb, bulb.isSimulated {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .font(.caption)
                                Text("This is a simulated bulb for testing")
                                    .font(.caption)
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bulb Name").font(.subheadline).bold()
                            TextField("e.g., Living Room Light", text: $bulbName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Room (Optional)").font(.subheadline).bold()
                            TextField("e.g., Living Room", text: $roomName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        if savingBulb {
                            ProgressView("Saving...")
                        }
                        
                        HStack(spacing: 15) {
                            Button("Cancel") {
                                showNameDialog = false
                                bulbName = ""
                                roomName = ""
                            }
                            .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                            .disabled(savingBulb)
                            
                            Button("Add Bulb") {
                                saveBulbToDatabase()
                            }
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
        .onAppear {
            bleManager.startScanning()
        }
        .onDisappear {
            bleManager.stopScanning()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SimulatorModeChanged"))) { _ in
            // Stop current scan and clear bulbs
            bleManager.stopScanning()
            bleManager.refreshSimulatorMode()
            
            // Wait a moment then start fresh scan
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                bleManager.startScanning()
            }
        }
    }
    
    func saveBulbToDatabase() {
        guard let bulb = selectedBulb,
              let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else {
            errorMessage = "User not logged in"
            return
        }
        
        savingBulb = true
        errorMessage = ""
        successMessage = ""
        
        // ⭐ CRITICAL: Log what we're saving
        print("💾 Saving bulb to database:")
        print("   Name: \(bulb.name)")
        print("   ID: \(bulb.id.uuidString)")
        print("   isSimulated: \(bulb.isSimulated)")
        
        guard let url = URL(string: "\(APIConfig.baseURL)/add_bulb") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let requestData: [String: Any] = [
            "email": userEmail,
            "bulb_id": bulb.id.uuidString,
            "bulb_name": bulbName.trimmingCharacters(in: .whitespacesAndNewlines),
            "room_name": roomName.trimmingCharacters(in: .whitespacesAndNewlines),
            "is_simulated": bulb.isSimulated  // ⭐ CRITICAL: Send the simulated flag
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
                        successMessage = "✅ Bulb added successfully!"
                        showNameDialog = false
                        
                        // Navigate back after 1.5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    } else if httpResponse.statusCode == 409 {
                        errorMessage = "This bulb is already added to your account"
                        showNameDialog = false
                    } else if let data = data,
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = json["message"] as? String {
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
struct DiscoveredBulbRowView: View {
    let bulb: SmartBulb
    
    var body: some View {
        HStack(spacing: 15) {
            // Bulb Icon with signal indicator
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 25))
                    .foregroundColor(.yellow)
                
                // Signal strength indicator OR simulated indicator
                if bulb.isSimulated {
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
                    Circle()
                        .fill(signalColor)
                        .frame(width: 12, height: 12)
                        .offset(x: 18, y: -18)
                }
            }
            
            // Bulb Info
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(bulb.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if bulb.isSimulated {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
                
                if !bulb.isSimulated {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                        Text("Signal: \(signalStrength)")
                            .font(.caption)
                    }
                    .foregroundColor(.gray)
                } else {
                    Text("Simulated for testing")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            // Add button
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.green)
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    var signalColor: Color {
        if bulb.rssi > -50 {
            return .green
        } else if bulb.rssi > -70 {
            return .orange
        } else {
            return .red
        }
    }
    
    var signalStrength: String {
        if bulb.rssi > -50 {
            return "Excellent"
        } else if bulb.rssi > -70 {
            return "Good"
        } else {
            return "Weak"
        }
    }
}

struct AddBulbView_Previews: PreviewProvider {
    static var previews: some View {
        AddBulbView()
    }
}
