// SettingsView.swift
// AI-Based Smart Bulb for Adaptive Home Automation

// Presents app-level settings to the user
// Currently exposes the Simulator Mode toggle, which switches between real ESP32 Bluetooth hardware and a fully simulated bulb environment for development and testing

import SwiftUI

/// The settings screen, presented modally from "HomeView"

/// Allows the user to toggle Simulator Mode on or off. When the toggle changes:
/// - The new value is immediately persisted to "UserDefaults"
/// - A "SimulatorModeChanged" notification is broadcast via "NotificationCenter" so that all active "BLEManager" instances can react accordingly

/// When Simulator Mode is off, a Bluetooth information panel is shown to guide the user through connecting real ESP32 hardware
/// The currently logged-in user's email is displayed at the bottom of the screen

/// Simulator Mode defaults to "true" on first launch so the app is immediately usable without physical hardware
struct SettingsView: View {

    // MARK: - State

    /// The current state of the Simulator Mode toggle, persisted in "UserDefaults"
    @State private var simulatorMode: Bool = true

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
                // Circular dismiss button (✕) aligned to the leading edge
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

                // Settings Card
                VStack(spacing: 0) {

                    // Simulator Mode Toggle
                    // Persists the new value to UserDefaults and broadcasts a notification so BLEManager instances update immediately
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
                                // Persist the new preference immediately
                                UserDefaults.standard.set(newValue, forKey: "simulatorMode")
                                UserDefaults.standard.synchronize()

                                // Notify BLEManager instances to switch modes
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

                    // About Simulator Mode
                    // Explains the purpose and behaviour of Simulator Mode so the user understands when to enable or disable it
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About Simulator Mode")
                            .font(.subheadline)
                            .bold()

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Test the app without physical ESP32 bulbs")
                                .font(.caption).foregroundColor(.gray)
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Simulated bulbs appear during scanning")
                                .font(.caption).foregroundColor(.gray)
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("All controls work as if real hardware connected")
                                .font(.caption).foregroundColor(.gray)
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(.orange)
                            Text("Turn OFF when ESP32 hardware is ready")
                                .font(.caption).foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.05))
                }
                .cornerRadius(15)
                .padding(.horizontal)

                // Bluetooth Information Panel
                // Only shown when Simulator Mode is off, reminding the user that the iOS Simulator does not support Bluetooth and providing step-by-step instructions for physical device testing
                if !simulatorMode {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill").foregroundColor(.blue)
                            Text("Bluetooth Information")
                                .font(.subheadline).bold()
                        }

                        Text("⚠️ iOS Simulator doesn't support Bluetooth")
                            .font(.caption).foregroundColor(.gray)

                        Text("To test with real ESP32 hardware:")
                            .font(.caption).foregroundColor(.gray).bold()

                        // Step-by-step setup guide for hardware mode
                        VStack(alignment: .leading, spacing: 5) {
                            Text("1. Deploy app to physical iPhone/iPad")
                                .font(.caption).foregroundColor(.gray)
                            Text("2. Enable Bluetooth on device")
                                .font(.caption).foregroundColor(.gray)
                            Text("3. Power on ESP32 bulb")
                                .font(.caption).foregroundColor(.gray)
                            Text("4. Turn OFF simulator mode")
                                .font(.caption).foregroundColor(.gray)
                        }
                        .padding(.leading, 10)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(15)
                    .padding(.horizontal)
                }

                Spacer()

                // Logged-In User
                // Displays the currently logged-in user's email address, read from UserDefaults
                // Hidden if no email is stored
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
            // Read the persisted simulator mode preference on every appearance
            // If no value has been stored yet (first launch), default to true so the app is immediately usable without physical hardware
            simulatorMode = UserDefaults.standard.bool(forKey: "simulatorMode")
            if UserDefaults.standard.object(forKey: "simulatorMode") == nil {
                simulatorMode = true
                UserDefaults.standard.set(true, forKey: "simulatorMode")
            }
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
