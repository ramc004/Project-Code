// HomeView.swift
// AI-Based Smart Bulb for Adaptive Home Automation

// The main dashboard screen, reached after a successful login
// Displays the user's saved smart bulbs, filtered by the current Simulator Mode setting
// Also defines the SavedBulb model and SavedBulbRowView used throughout the bulb list

import SwiftUI

/// The main dashboard view shown after the user logs in

/// Fetches and displays the user's saved bulbs from the backend, filtered to show only simulated or only real bulbs depending on the current Simulator Mode preference stored in "UserDefaults"

/// From this screen the user can:
/// - Navigate to "SavedBulbControlView" to control an individual bulb
/// - Navigate to "ScheduleView" to manage timed bulb schedules
/// - Navigate to "AddBulbView" to pair a new bulb
/// - Navigate to "SettingsView" to toggle Simulator Mode
/// - Delete a bulb from their account via a confirmation dialog
/// - Log out, which resets the root view to "WelcomeView"

/// The bulb list reloads automatically when the view appears, when the user pulls to refresh, or when a "SimulatorModeChanged" notification is received
struct HomeView: View {

    // MARK: - State

    /// Controls visibility of the logout confirmation popup
    @State private var showLogoutPopup = false

    /// The list of saved bulbs fetched from the backend for the current user
    @State private var userBulbs: [SavedBulb] = []

    /// True while the bulb list is being fetched from the backend
    @State private var isLoadingBulbs = false

    /// Whether the Flask backend server is currently reachable
    @State private var serverOnline = true

    /// An inline error message shown when a network request fails
    @State private var errorMessage = ""

    /// The bulb selected for deletion, held until the confirmation dialog resolves
    @State private var bulbToDelete: SavedBulb? = nil

    /// Controls visibility of the delete confirmation popup
    @State private var showDeleteConfirm = false

    /// Used to dismiss this view if needed (e.g. during logout)
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

            VStack(alignment: .leading, spacing: 15) {

                // Header
                // Left: logout button (arrow). Right: settings and add-bulb buttons
                // The add-bulb button is disabled when the server is offline
                HStack {
                    // Logout button, tapping shows the confirmation popup
                    Button(action: { showLogoutPopup = true }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(CircularIconButtonStyle(backgroundColor: .blue, foregroundColor: .white))

                    Spacer()

                    // Settings, navigates to SettingsView
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(CircularIconButtonStyle(backgroundColor: .purple, foregroundColor: .white))

                    // Add Bulb, disabled when the server is offline
                    NavigationLink(destination: AddBulbView()) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(CircularIconButtonStyle(backgroundColor: .green, foregroundColor: .white))
                    .disabled(!serverOnline)
                }
                .padding(.horizontal)
                .padding(.top, 30)

                // Title and Status Badge
                // Shows a contextual status badge below the title:
                // - Red "Server Offline" badge with a Retry button if unreachable
                // - Orange "Simulator Mode Active" badge if simulator mode is on
                // - A plain welcome message in normal hardware mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("Home Automation")
                        .font(.largeTitle)
                        .bold()

                    let simulatorMode = UserDefaults.standard.bool(forKey: "simulatorMode")
                    if !serverOnline {
                        // Server offline badge
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                            Text("Server Offline").font(.caption)
                            Button("Retry") { loadUserBulbs() }
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.blue).foregroundColor(.white).cornerRadius(6)
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.red.opacity(0.1)).cornerRadius(8)
                    } else if UserDefaults.standard.object(forKey: "simulatorMode") == nil || simulatorMode {
                        // Simulator mode active badge
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill").font(.caption)
                            Text("Simulator Mode Active").font(.caption)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1)).cornerRadius(8)
                    } else {
                        // Normal hardware mode, plain welcome message
                        Text("Welcome! Control your smart bulbs.")
                            .font(.title3).foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)

                // Inline Error Message
                // Shown when a request fails for a reason other than the server being completely offline (e.g. a malformed response)
                if !errorMessage.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                        Text(errorMessage).font(.caption).foregroundColor(.red)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1)).cornerRadius(8).padding(.horizontal)
                }

                // Bulb List / Empty State
                if isLoadingBulbs {
                    // Loading indicator while the bulb list is being fetched
                    Spacer()
                    VStack(spacing: 15) {
                        ProgressView().scaleEffect(1.5)
                        Text("Loading your bulbs...").font(.subheadline).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()

                } else if userBulbs.isEmpty {
                    // Empty state, icon and message vary based on server status
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: serverOnline ? "lightbulb.slash" : "wifi.slash")
                            .font(.system(size: 60)).foregroundColor(.gray)
                        Text(serverOnline ? "No Bulbs Added Yet" : "Cannot Load Bulbs")
                            .font(.title2).bold()
                        if !serverOnline {
                            Text("Server connection required to load your bulbs")
                                .font(.subheadline).foregroundColor(.gray)
                                .multilineTextAlignment(.center).padding(.horizontal, 40)
                        } else {
                            // Tailor the hint text to the current mode
                            let sim = UserDefaults.standard.object(forKey: "simulatorMode") == nil ||
                                      UserDefaults.standard.bool(forKey: "simulatorMode")
                            Text(sim ? "Tap the + button above to add simulated bulbs for testing"
                                     : "Tap the + button above to add your first smart bulb")
                                .font(.subheadline).foregroundColor(.gray)
                                .multilineTextAlignment(.center).padding(.horizontal, 40)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()

                } else {
                    // Scrollable list of the user's saved bulbs
                    ScrollView {
                        VStack(spacing: 15) {
                            ForEach(userBulbs) { bulb in
                                HStack(spacing: 12) {
                                    // Tapping the row navigates to the bulb control screen
                                    NavigationLink(destination: SavedBulbControlView(savedBulb: bulb)) {
                                        SavedBulbRowView(bulb: bulb)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    // Schedule shortcut, navigates to ScheduleView for this bulb
                                    NavigationLink(destination: ScheduleView(bulbId: bulb.bulb_id, bulbName: bulb.bulb_name)) {
                                        Image(systemName: "calendar.badge.clock")
                                            .font(.system(size: 18))
                                            .foregroundColor(.white)
                                            .frame(width: 44, height: 44)
                                            .background(Color(red: 0.4, green: 0.3, blue: 0.9).opacity(0.85))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                                    }

                                    // Delete button, stores the target bulb and shows the confirmation popup
                                    Button(action: {
                                        bulbToDelete = bulb
                                        showDeleteConfirm = true
                                    }) {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(.white)
                                            .frame(width: 44, height: 44)
                                            .background(Color.red.opacity(0.85))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }

            // Logout Confirmation Popup
            // Modal overlay asking the user to confirm before logging out "Yes" clears the session and resets the root view to WelcomeView
            if showLogoutPopup {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text("Are you sure you want to log out?")
                            .font(.headline).multilineTextAlignment(.center)
                        HStack(spacing: 30) {
                            Button("No") { showLogoutPopup = false }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                            Button("Yes") { showLogoutPopup = false; navigateToRootView() }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .red))
                        }
                    }
                    .padding().frame(width: 300)
                    .background(Color.white).cornerRadius(20).shadow(radius: 10)
                }
            }

            // Delete Confirmation Popup
            // Modal overlay asking the user to confirm before removing a bulb from their account
            // Includes the bulb name for clarity
            if showDeleteConfirm, let bulb = bulbToDelete {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        // Dismiss button (✕) in the top-right corner of the card
                        HStack {
                            Spacer()
                            Button(action: { showDeleteConfirm = false; bulbToDelete = nil }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold)).foregroundColor(.gray)
                                    .frame(width: 28, height: 28)
                                    .background(Color.gray.opacity(0.15)).clipShape(Circle())
                            }
                        }
                        .padding(.bottom, -10)

                        Image(systemName: "trash.fill").font(.system(size: 48)).foregroundColor(.red)
                        Text("Delete Bulb?").font(.title3).bold()
                        Text("Are you sure you want to remove \"\(bulb.bulb_name)\" from your account? It can be paired to another account afterwards.")
                            .font(.subheadline).foregroundColor(.gray)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 15) {
                            Button("No") { showDeleteConfirm = false; bulbToDelete = nil }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                            Button("Yes, Delete") { if let b = bulbToDelete { deleteBulb(b) } }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .red))
                        }
                    }
                    .padding(24).frame(width: 320)
                    .background(Color.white).cornerRadius(20).shadow(radius: 20)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        // Load bulbs whenever the view appears
        .onAppear { loadUserBulbs() }
        // Pull-to-refresh reloads the bulb list from the backend
        .refreshable { loadUserBulbs() }
        // Reload when Simulator Mode is toggled in SettingsView so the list
        // immediately switches between simulated and real bulbs
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SimulatorModeChanged"))) { _ in
            loadUserBulbs()
        }
    }

    // MARK: - Load Bulbs

    /// Fetches the current user's saved bulbs from the "/get_bulbs" endpoint, filtered by the active Simulator Mode preference
    
    /// If no "simulatorMode" key exists in "UserDefaults" (first launch), it is initialised to "true" so the app defaults to simulator mode
    /// The fetched bulbs are decoded into "SavedBulb" values and stored in "userBulbs"
    /// On failure, "userBulbs" is cleared and an appropriate error is shown
    func loadUserBulbs() {
        guard let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        isLoadingBulbs = true
        errorMessage   = ""

        // Read simulator mode, defaulting to true if not yet set
        var simulatorMode = UserDefaults.standard.bool(forKey: "simulatorMode")
        if UserDefaults.standard.object(forKey: "simulatorMode") == nil {
            simulatorMode = true
            UserDefaults.standard.set(true, forKey: "simulatorMode")
        }

        NetworkManager.shared.post(
            endpoint: "/get_bulbs",
            body: ["email": userEmail, "simulator_mode": simulatorMode]
        ) { result in
            isLoadingBulbs = false
            switch result {
            case .success(let json):
                serverOnline = true
                // Decode each bulb dictionary into a SavedBulb, skipping malformed entries
                if let bulbsData = json["bulbs"] as? [[String: Any]] {
                    userBulbs = bulbsData.compactMap { dict in
                        guard let bulbId   = dict["bulb_id"]   as? String,
                              let bulbName = dict["bulb_name"] as? String else { return nil }
                        return SavedBulb(
                            bulb_id:      bulbId,
                            bulb_name:    bulbName,
                            room_name:    dict["room_name"]    as? String,
                            is_simulated: dict["is_simulated"] as? Bool ?? false
                        )
                    }
                }
            case .failure(let error):
                if case .serverUnavailable = error {
                    serverOnline  = false
                    errorMessage  = "Server is offline. Please start the Flask server."
                } else {
                    errorMessage = error.userMessage
                }
                userBulbs = []
            }
        }
    }

    // MARK: - Delete Bulb

    /// Removes the specified bulb from the current user's account via the "/delete_bulb" endpoint, then removes it from "userBulbs" locally on success
    
    /// Dismisses the delete confirmation popup and clears "bulbToDelete" regardless of the outcome
    /// On failure, an error message is displayed inline
    
    /// - Parameter bulb: The "SavedBulb" to remove
    func deleteBulb(_ bulb: SavedBulb) {
        guard let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        NetworkManager.shared.post(
            endpoint: "/delete_bulb",
            body: ["email": userEmail, "bulb_id": bulb.bulb_id]
        ) { result in
            showDeleteConfirm = false
            bulbToDelete      = nil
            if case .success = result {
                // Remove from the local list immediately without a full reload
                userBulbs.removeAll { $0.bulb_id == bulb.bulb_id }
            } else if case .failure(let error) = result {
                errorMessage = error.userMessage
            }
        }
    }

    // MARK: - Logout

    /// Logs the user out by replacing the root view controller with a fresh "WelcomeView", effectively clearing the entire navigation stack
    
    /// Uses a cross-dissolve transition for a smooth visual handoff
    func navigateToRootView() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        window.rootViewController = UIHostingController(rootView: WelcomeView())
        window.makeKeyAndVisible()
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil)
    }
}

// MARK: - SavedBulb Model

/// A lightweight model representing a bulb saved to the user's account on the backend

/// Matches to "Identifiable" so it can be used directly in SwiftUI "ForEach" loops
struct SavedBulb: Identifiable {

    /// A locally generated unique identifier for use in SwiftUI list rendering
    let id = UUID()

    /// The unique identifier assigned to the bulb by the backend database
    let bulb_id: String

    /// The user-assigned display name of the bulb (e.g. "Bedroom Bulb")
    let bulb_name: String

    /// The optional room the bulb has been assigned to (e.g. "Living Room")
    let room_name: String?

    /// Whether this bulb is a simulated device rather than real ESP32 hardware
    let is_simulated: Bool
}

// MARK: - SavedBulbRowView

/// A row view displaying a single saved bulb's name, room, and simulated status

/// Used inside the "ForEach" loop in "HomeView"
/// Real bulbs show a plain lightbulb icon; simulated bulbs display an orange play-badge overlay and an "Simulated" label beneath the bulb name
struct SavedBulbRowView: View {

    /// The bulb to display in this row
    let bulb: SavedBulb

    var body: some View {
        HStack(spacing: 15) {
            // Bulb icon with optional simulated badge overlay
            ZStack {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 30)).foregroundColor(.yellow)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.1)).clipShape(Circle())

                // Orange play-badge in the top-right corner for simulated bulbs
                if bulb.is_simulated {
                    Circle().fill(Color.orange).frame(width: 14, height: 14)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 6)).foregroundColor(.white))
                        .offset(x: 18, y: -18)
                }
            }

            // Bulb name, optional room label, and simulated indicator
            VStack(alignment: .leading, spacing: 5) {
                Text(bulb.bulb_name).font(.headline).foregroundColor(.primary)
                if let room = bulb.room_name, !room.isEmpty {
                    Text(room).font(.caption).foregroundColor(.gray)
                }
                if bulb.is_simulated {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill").font(.system(size: 8))
                        Text("Simulated").font(.system(size: 10))
                    }
                    .foregroundColor(.orange)
                }
            }

            Spacer()
            // Chevron indicating the row is tappable
            Image(systemName: "chevron.right").foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Preview

struct HomeView_Previews: PreviewProvider {
    static var previews: some View { HomeView() }
}
