import SwiftUI

struct SettingsView: View {
    @State private var simulatorMode: Bool = true
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
                }
                .padding(.horizontal)
                .padding(.top, 30)
                
                Text("Settings")
                    .font(.largeTitle)
                    .bold()
                
                // Settings List
                VStack(spacing: 0) {
                    // Simulator Mode Toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.orange)
                                Text("Simulator Mode")
                                    .font(.headline)
                            }
                            
                            Text("Test without ESP32 hardware")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $simulatorMode)
                            .labelsHidden()
                            .onChange(of: simulatorMode) { newValue in
                                print("🔄 Simulator Mode changed to: \(newValue)")
                                UserDefaults.standard.set(newValue, forKey: "simulatorMode")
                                UserDefaults.standard.synchronize() // Force save immediately
                                
                                // Post notification to refresh BLE managers
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("SimulatorModeChanged"),
                                    object: nil
                                )
                            }
                    }
                    .padding()
                    .background(Color.white.opacity(0.7))
                    
                    Divider()
                        .padding(.leading)
                    
                    // Info Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About Simulator Mode")
                            .font(.subheadline)
                            .bold()
                        
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Test the app without physical ESP32 bulbs")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Simulated bulbs appear during scanning")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("All controls work as if real hardware connected")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.orange)
                            Text("Turn OFF when ESP32 hardware is ready")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.05))
                }
                .cornerRadius(15)
                .padding(.horizontal)
                
                // Bluetooth Info Section (only show when not in simulator mode)
                if !simulatorMode {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Bluetooth Information")
                                .font(.subheadline)
                                .bold()
                        }
                        
                        Text("⚠️ iOS Simulator doesn't support Bluetooth")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("To test with real ESP32 hardware:")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .bold()
                        
                        VStack(alignment: .leading, spacing: 5) {
                            Text("1. Deploy app to physical iPhone/iPad")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("2. Enable Bluetooth on device")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("3. Power on ESP32 bulb")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("4. Turn OFF simulator mode")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.leading, 10)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(15)
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // User Info
                if let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") {
                    VStack(spacing: 8) {
                        Text("Logged in as")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(userEmail)
                            .font(.subheadline)
                            .bold()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.5))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            simulatorMode = UserDefaults.standard.bool(forKey: "simulatorMode")
            if UserDefaults.standard.object(forKey: "simulatorMode") == nil {
                // Default to true for first launch
                simulatorMode = true
                UserDefaults.standard.set(true, forKey: "simulatorMode")
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
