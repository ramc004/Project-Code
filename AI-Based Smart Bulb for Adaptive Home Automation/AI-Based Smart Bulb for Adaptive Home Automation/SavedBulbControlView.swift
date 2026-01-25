import SwiftUI

struct SavedBulbControlView: View {
    let savedBulb: SavedBulb
    
    @StateObject private var bleManager = BLEManager()
    @State private var isConnecting = true
    @State private var connectionFailed = false
    @State private var selectedColor: Color = .white
    @State private var showDeleteConfirm = false
    @State private var showEditName = false
    @State private var editedName = ""
    @State private var editedRoom = ""
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
            
            if isConnecting {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Connecting to \(savedBulb.bulb_name)...")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
            } else if connectionFailed {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Unable to Connect")
                        .font(.title2)
                        .bold()
                    
                    if savedBulb.is_simulated {
                        Text("This is a simulated bulb. Make sure Simulator Mode is enabled in Settings.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    } else {
                        Text("Make sure the bulb is powered on and nearby")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Button("Try Again") {
                        isConnecting = true
                        connectionFailed = false
                        connectToBulb()
                    }
                    .buttonStyle(ModernButtonStyle(backgroundColor: .blue))
                    .padding(.horizontal, 60)
                    
                    Button("Go Back") {
                        dismiss()
                    }
                    .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                    .padding(.horizontal, 60)
                }
            } else {
                ScrollView {
                    VStack(spacing: 30) {
                        // Header
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 20, weight: .bold))
                            }
                            .buttonStyle(CircularIconButtonStyle(backgroundColor: .blue, foregroundColor: .white))
                            
                            Spacer()
                            
                            Menu {
                                Button(action: {
                                    editedName = savedBulb.bulb_name
                                    editedRoom = savedBulb.room_name ?? ""
                                    showEditName = true
                                }) {
                                    Label("Edit Name", systemImage: "pencil")
                                }
                                
                                Button(role: .destructive, action: {
                                    showDeleteConfirm = true
                                }) {
                                    Label("Remove Bulb", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 20, weight: .bold))
                            }
                            .buttonStyle(CircularIconButtonStyle(backgroundColor: .gray, foregroundColor: .white))
                        }
                        .padding(.horizontal)
                        .padding(.top, 30)
                        
                        // Bulb Visual
                        BulbVisualView(state: bleManager.bulbState)
                            .padding(.top, 20)
                        
                        // Device Name and Room
                        VStack(spacing: 5) {
                            Text(savedBulb.bulb_name)
                                .font(.title)
                                .bold()
                            
                            if let room = savedBulb.room_name, !room.isEmpty {
                                Text(room)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            if savedBulb.is_simulated || bleManager.simulatorMode {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.caption)
                                    Text("Simulated")
                                        .font(.caption)
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        
                        // Power Toggle
                        Toggle("Power", isOn: Binding(
                            get: { bleManager.bulbState.power },
                            set: { bleManager.setPower($0) }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .padding()
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(15)
                        .padding(.horizontal)
                        
                        // Brightness Slider
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Brightness: \(Int((Double(bleManager.bulbState.brightness) / 255.0) * 100))%")
                                .font(.headline)
                            
                            Slider(
                                value: Binding(
                                    get: { Double(bleManager.bulbState.brightness) },
                                    set: { bleManager.setBrightness(UInt8($0)) }
                                ),
                                in: 0...255,
                                step: 1
                            )
                            .disabled(!bleManager.bulbState.power)
                        }
                        .padding()
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(15)
                        .padding(.horizontal)
                        
                        // Color Picker
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Color")
                                .font(.headline)
                            
                            ColorPicker("Select Color", selection: $selectedColor)
                                .onChange(of: selectedColor) { color in
                                    let uiColor = UIColor(color)
                                    var red: CGFloat = 0
                                    var green: CGFloat = 0
                                    var blue: CGFloat = 0
                                    var alpha: CGFloat = 0
                                    
                                    uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                                    
                                    bleManager.setColor(
                                        red: UInt8(red * 255),
                                        green: UInt8(green * 255),
                                        blue: UInt8(blue * 255)
                                    )
                                }
                            
                            // Quick Colors
                            HStack(spacing: 15) {
                                QuickColorButton(color: .white, label: "White") {
                                    bleManager.setColor(red: 255, green: 255, blue: 255)
                                }
                                QuickColorButton(color: .red, label: "Red") {
                                    bleManager.setColor(red: 255, green: 0, blue: 0)
                                }
                                QuickColorButton(color: .green, label: "Green") {
                                    bleManager.setColor(red: 0, green: 255, blue: 0)
                                }
                                QuickColorButton(color: .blue, label: "Blue") {
                                    bleManager.setColor(red: 0, green: 0, blue: 255)
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(15)
                        .padding(.horizontal)
                        
                        // Effect Modes
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Effects")
                                .font(.headline)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                EffectButton(
                                    title: "Solid",
                                    icon: "circle.fill",
                                    isSelected: bleManager.bulbState.mode == 0
                                ) {
                                    bleManager.setMode(0)
                                }
                                
                                EffectButton(
                                    title: "Fade",
                                    icon: "waveform",
                                    isSelected: bleManager.bulbState.mode == 1
                                ) {
                                    bleManager.setMode(1)
                                }
                                
                                EffectButton(
                                    title: "Rainbow",
                                    icon: "rainbow",
                                    isSelected: bleManager.bulbState.mode == 2
                                ) {
                                    bleManager.setMode(2)
                                }
                                
                                EffectButton(
                                    title: "Pulse",
                                    icon: "dot.radiowaves.left.and.right",
                                    isSelected: bleManager.bulbState.mode == 3
                                ) {
                                    bleManager.setMode(3)
                                }
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(15)
                        .padding(.horizontal)
                        
                        Spacer(minLength: 50)
                    }
                }
            }
            
            // Edit Name Dialog
            if showEditName {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Text("Edit Bulb Details")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bulb Name").font(.subheadline).bold()
                            TextField("Bulb name", text: $editedName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Room").font(.subheadline).bold()
                            TextField("Room name (optional)", text: $editedRoom)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        HStack(spacing: 15) {
                            Button("Cancel") {
                                showEditName = false
                            }
                            .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                            
                            Button("Save") {
                                updateBulbDetails()
                            }
                            .buttonStyle(ModernButtonStyle(backgroundColor: .blue))
                            .disabled(editedName.isEmpty)
                        }
                    }
                    .padding()
                    .frame(width: 320)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(radius: 20)
                }
            }
            
            // Delete Confirmation
            if showDeleteConfirm {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        
                        Text("Remove Bulb?")
                            .font(.headline)
                        
                        Text("This will remove \(savedBulb.bulb_name) from your account")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 15) {
                            Button("Cancel") {
                                showDeleteConfirm = false
                            }
                            .buttonStyle(ModernButtonStyle(backgroundColor: .gray))
                            
                            Button("Remove") {
                                deleteBulb()
                            }
                            .buttonStyle(ModernButtonStyle(backgroundColor: .red))
                        }
                    }
                    .padding()
                    .frame(width: 300)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(radius: 20)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            connectToBulb()
            selectedColor = Color(
                red: Double(bleManager.bulbState.red) / 255.0,
                green: Double(bleManager.bulbState.green) / 255.0,
                blue: Double(bleManager.bulbState.blue) / 255.0
            )
        }
        .onDisappear {
            bleManager.disconnect()
        }
    }
    
    func connectToBulb() {
        // Check if this is a simulated bulb and if we're in the correct mode
        if savedBulb.is_simulated {
            // Trying to connect to a simulated bulb
            if !bleManager.simulatorMode {
                // User is in real hardware mode but trying to connect to simulated bulb
                print("⚠️ Cannot connect to simulated bulb in real hardware mode")
                isConnecting = false
                connectionFailed = true
                return
            }
            
            // In simulator mode, instantly "connect" to simulated bulb
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let simulatedBulb = SmartBulb(
                    id: UUID(uuidString: savedBulb.bulb_id) ?? UUID(),
                    name: savedBulb.bulb_name,
                    peripheral: nil,
                    rssi: -50,
                    isConnected: true,
                    isSimulated: true
                )
                bleManager.connect(to: simulatedBulb)
                isConnecting = false
            }
            return
        }
        
        // Trying to connect to a real bulb
        if bleManager.simulatorMode {
            // User is in simulator mode but trying to connect to real bulb
            print("⚠️ Cannot connect to real bulb in simulator mode")
            isConnecting = false
            connectionFailed = true
            return
        }
        
        // Real hardware connection
        bleManager.startScanning()
        
        // Wait for bulb to be discovered
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if let bulb = bleManager.discoveredBulbs.first(where: { $0.id.uuidString == savedBulb.bulb_id }) {
                bleManager.connect(to: bulb)
                isConnecting = false
            } else {
                // Try scanning a bit longer
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if let bulb = bleManager.discoveredBulbs.first(where: { $0.id.uuidString == savedBulb.bulb_id }) {
                        bleManager.connect(to: bulb)
                        isConnecting = false
                    } else {
                        isConnecting = false
                        connectionFailed = true
                        bleManager.stopScanning()
                    }
                }
            }
        }
    }
    
    func updateBulbDetails() {
        guard let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        
        guard let url = URL(string: "\(APIConfig.baseURL)/update_bulb") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": userEmail,
            "bulb_id": savedBulb.bulb_id,
            "bulb_name": editedName.trimmingCharacters(in: .whitespacesAndNewlines),
            "room_name": editedRoom.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    showEditName = false
                    // Refresh would happen when going back to HomeView
                }
            }
        }.resume()
    }
    
    func deleteBulb() {
        guard let userEmail = UserDefaults.standard.string(forKey: "currentUserEmail") else { return }
        
        guard let url = URL(string: "\(APIConfig.baseURL)/delete_bulb") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": userEmail,
            "bulb_id": savedBulb.bulb_id
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    bleManager.disconnect()
                    dismiss()
                }
            }
        }.resume()
    }
}

struct SavedBulbControlView_Previews: PreviewProvider {
    static var previews: some View {
        SavedBulbControlView(savedBulb: SavedBulb(
            bulb_id: "test",
            bulb_name: "Living Room",
            room_name: "Living Room",
            is_simulated: false
        ))
    }
}
