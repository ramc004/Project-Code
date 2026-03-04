import SwiftUI

struct HomeView: View {
    @State private var showLogoutPopup = false
    @State private var userBulbs: [SavedBulb] = []
    @State private var isLoadingBulbs = false
    @State private var serverOnline = true
    @State private var errorMessage = ""
    @State private var bulbToDelete: SavedBulb? = nil
    @State private var showDeleteConfirm = false
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

            VStack(alignment: .leading, spacing: 15) {
                // Header with buttons
                HStack {
                    Button(action: { showLogoutPopup = true }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(CircularIconButtonStyle(backgroundColor: .blue, foregroundColor: .white))

                    Spacer()
                    
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(CircularIconButtonStyle(backgroundColor: .purple, foregroundColor: .white))

                    NavigationLink(destination: AddBulbView()) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(CircularIconButtonStyle(backgroundColor: .green, foregroundColor: .white))
                    .disabled(!serverOnline)
                }
                .padding(.horizontal)
                .padding(.top, 30)

                // Title and subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Home Automation")
                        .font(.largeTitle)
                        .bold()

                    let simulatorMode = UserDefaults.standard.bool(forKey: "simulatorMode")
                    if !serverOnline {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text("Server Offline")
                                .font(.caption)
                            Button("Retry") {
                                loadUserBulbs()
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    } else if UserDefaults.standard.object(forKey: "simulatorMode") == nil || simulatorMode {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.caption)
                            Text("Simulator Mode Active")
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        Text("Welcome! Control your smart bulbs.")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Error message
                if !errorMessage.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                // Loading indicator or bulb list
                if isLoadingBulbs {
                    Spacer()
                    VStack(spacing: 15) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading your bulbs...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else if userBulbs.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: serverOnline ? "lightbulb.slash" : "wifi.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text(serverOnline ? "No Bulbs Added Yet" : "Cannot Load Bulbs")
                            .font(.title2)
                            .bold()
                        
                        if !serverOnline {
                            Text("Server connection required to load your bulbs")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        } else {
                            let simulatorMode = UserDefaults.standard.bool(forKey: "simulatorMode")
                            if UserDefaults.standard.object(forKey: "simulatorMode") == nil || simulatorMode {
                                Text("Tap the + button above to add simulated bulbs for testing")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            } else {
                                Text("Tap the + button above to add your first smart bulb")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    // Bulb list
                    ScrollView {
                        VStack(spacing: 15) {
                            ForEach(userBulbs) { bulb in
                                HStack(spacing: 12) {
                                    // Tappable row navigates to control view
                                    NavigationLink(destination: SavedBulbControlView(savedBulb: bulb)) {
                                        SavedBulbRowView(bulb: bulb)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    // Delete bin button
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

            // Logout confirmation popup
            if showLogoutPopup {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text("Are you sure you want to log out?")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 30) {
                            Button("No") { showLogoutPopup = false }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                            Button("Yes") {
                                showLogoutPopup = false
                                navigateToRootView()
                            }
                                .buttonStyle(ModernButtonStyle(backgroundColor: .red))
                        }
                    }
                    .padding()
                    .frame(width: 300)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(radius: 10)
                }
            }
            
            // Delete confirmation popup
            if showDeleteConfirm, let bulb = bulbToDelete {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        // X dismiss button
                        HStack {
                            Spacer()
                            Button(action: {
                                showDeleteConfirm = false
                                bulbToDelete = nil
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.gray)
                                    .frame(width: 28, height: 28)
                                    .background(Color.gray.opacity(0.15))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.bottom, -10)
                        
                        Image(systemName: "trash.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        
                        Text("Delete Bulb?")
                            .font(.title3)
                            .bold()
                        
                        Text("Are you sure you want to remove \"\(bulb.bulb_name)\" from your account? It can be paired to another account afterwards.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 15) {
                            Button("No") {
                                showDeleteConfirm = false
                                bulbToDelete = nil
                            }
                            .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                            
                            Button("Yes, Delete") {
                                if let b = bulbToDelete {
                                    deleteBulb(b)
                                }
                            }
                            .buttonStyle(ModernButtonStyle(backgroundColor: .red))
                        }
                    }
                    .padding(24)
                    .frame(width: 320)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(radius: 20)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadUserBulbs()
        }
        .refreshable {
            loadUserBulbs()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SimulatorModeChanged"))) { _ in
            print("🔄 Simulator mode changed, reloading bulbs...")
            loadUserBulbs()
        }
    }
    
    func loadUserBulbs() {
        guard let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else {
            return
        }
        
        isLoadingBulbs = true
        errorMessage = ""
        
        var simulatorMode = UserDefaults.standard.bool(forKey: "simulatorMode")
        if UserDefaults.standard.object(forKey: "simulatorMode") == nil {
            simulatorMode = true
            UserDefaults.standard.set(true, forKey: "simulatorMode")
        }
        
        print("📱 Loading bulbs - Simulator Mode: \(simulatorMode)")
        
        NetworkManager.shared.post(endpoint: "/get_bulbs", body: [
            "email": userEmail,
            "simulator_mode": simulatorMode
        ]) { result in
            isLoadingBulbs = false
            
            switch result {
            case .success(let json):
                serverOnline = true
                
                if let bulbsData = json["bulbs"] as? [[String: Any]] {
                    userBulbs = bulbsData.compactMap { dict in
                        guard let bulbId = dict["bulb_id"] as? String,
                              let bulbName = dict["bulb_name"] as? String else {
                            return nil
                        }
                        let isSimulated = dict["is_simulated"] as? Bool ?? false
                        return SavedBulb(
                            bulb_id: bulbId,
                            bulb_name: bulbName,
                            room_name: dict["room_name"] as? String,
                            is_simulated: isSimulated
                        )
                    }
                    print("✅ Loaded \(userBulbs.count) bulbs")
                }
                
            case .failure(let error):
                if case .serverUnavailable = error {
                    serverOnline = false
                    errorMessage = "Server is offline. Please start the Flask server."
                } else {
                    errorMessage = error.userMessage
                }
                userBulbs = []
            }
        }
    }
    
    func deleteBulb(_ bulb: SavedBulb) {
        guard let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        
        NetworkManager.shared.post(endpoint: "/delete_bulb", body: [
            "email": userEmail,
            "bulb_id": bulb.bulb_id
        ]) { result in
            showDeleteConfirm = false
            bulbToDelete = nil
            
            switch result {
            case .success:
                userBulbs.removeAll { $0.bulb_id == bulb.bulb_id }
            case .failure(let error):
                errorMessage = error.userMessage
            }
        }
    }
    
    func navigateToRootView() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return
        }
        window.rootViewController = UIHostingController(rootView: WelcomeView())
        window.makeKeyAndVisible()
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil, completion: nil)
    }
}

// MARK: - Saved Bulb Model
struct SavedBulb: Identifiable {
    let id = UUID()
    let bulb_id: String
    let bulb_name: String
    let room_name: String?
    let is_simulated: Bool
}

// MARK: - Saved Bulb Row View
struct SavedBulbRowView: View {
    let bulb: SavedBulb
    
    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.yellow)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
                
                if bulb.is_simulated {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.white)
                        )
                        .offset(x: 18, y: -18)
                }
            }
            
            VStack(alignment: .leading, spacing: 5) {
                Text(bulb.bulb_name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let room = bulb.room_name, !room.isEmpty {
                    Text(room)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                if bulb.is_simulated {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 8))
                        Text("Simulated")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
