import Foundation
import CoreBluetooth
import Combine

// MARK: - Smart Bulb Model
struct SmartBulb: Identifiable, Equatable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral?
    var rssi: Int
    var isConnected: Bool = false
    var isSimulated: Bool = false // NEW: Track if this is a simulated bulb
    
    static func == (lhs: SmartBulb, rhs: SmartBulb) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Bulb State
struct BulbState {
    var power: Bool = false
    var brightness: UInt8 = 255
    var red: UInt8 = 255
    var green: UInt8 = 255
    var blue: UInt8 = 255
    var mode: UInt8 = 0 // 0=solid, 1=fade, 2=rainbow, 3=pulse
}

// MARK: - BLE Manager
class BLEManager: NSObject, ObservableObject {
    // Published properties for SwiftUI
    @Published var discoveredBulbs: [SmartBulb] = []
    @Published var connectedBulb: SmartBulb?
    @Published var bulbState: BulbState = BulbState()
    @Published var isScanning: Bool = false
    @Published var bluetoothState: String = "Unknown"
    
    // SIMULATOR MODE - Reads from UserDefaults
    var simulatorMode: Bool {
        // Default to true if not set
        if UserDefaults.standard.object(forKey: "simulatorMode") == nil {
            UserDefaults.standard.set(true, forKey: "simulatorMode")
            return true
        }
        return UserDefaults.standard.bool(forKey: "simulatorMode")
    }
    
    // BLE Properties
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    
    // Service and Characteristic UUIDs (must match ESP32)
    private let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    private let powerUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    private let brightnessUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a9")
    private let colorUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26aa")
    private let modeUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26ab")
    private let statusUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26ac")
    
    // Characteristics
    private var powerCharacteristic: CBCharacteristic?
    private var brightnessCharacteristic: CBCharacteristic?
    private var colorCharacteristic: CBCharacteristic?
    private var modeCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    
    // Simulated bulbs storage - persistent IDs
    private var simulatedBulbIDs: [UUID] = []
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // Load or create persistent simulated bulb IDs
        loadSimulatedBulbIDs()
        
        // Create simulated bulbs if in simulator mode
        if simulatorMode {
            updateBluetoothStateForSimulator()
        }
    }
    
    // MARK: - Simulator Functions
    private func loadSimulatedBulbIDs() {
        // Load saved UUIDs from UserDefaults, or create new ones
        if let savedIDs = UserDefaults.standard.array(forKey: "simulatedBulbIDs") as? [String] {
            simulatedBulbIDs = savedIDs.compactMap { UUID(uuidString: $0) }
        }
        
        // If no saved IDs or not enough, create new ones
        if simulatedBulbIDs.count < 3 {
            simulatedBulbIDs = [UUID(), UUID(), UUID()]
            // Save to UserDefaults
            let idStrings = simulatedBulbIDs.map { $0.uuidString }
            UserDefaults.standard.set(idStrings, forKey: "simulatedBulbIDs")
        }
    }
    
    private func createSimulatedBulbs() -> [SmartBulb] {
        let names = [
            "Smart Bulb (Simulated)",
            "Living Room Light (Simulated)",
            "Bedroom Light (Simulated)"
        ]
        
        return zip(simulatedBulbIDs, names).enumerated().map { index, pair in
            SmartBulb(
                id: pair.0,
                name: pair.1,
                peripheral: nil,
                rssi: -45 - (index * 10),
                isSimulated: true
            )
        }
    }
    
    private func updateBluetoothStateForSimulator() {
        DispatchQueue.main.async {
            self.bluetoothState = "Simulator Mode"
        }
    }
    
    // MARK: - Public method to refresh simulator mode state
    func refreshSimulatorMode() {
        // Always clear discovered bulbs when mode changes
        discoveredBulbs.removeAll()
        connectedBulb = nil
        isScanning = false
        
        if simulatorMode {
            print("✅ Switched to Simulator Mode")
            updateBluetoothStateForSimulator()
        } else {
            print("✅ Switched to Real Hardware Mode")
            updateBluetoothStateMessage()
        }
    }
    
    // MARK: - Scanning
    func startScanning() {
        if simulatorMode {
            // Simulate scanning delay
            isScanning = true
            bluetoothState = "Simulator Mode"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.discoveredBulbs = self.createSimulatedBulbs()
                print("Simulator: Discovered \(self.discoveredBulbs.count) simulated bulbs")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.stopScanning()
            }
            return
        }
        
        // Real Bluetooth scanning
        guard centralManager.state == .poweredOn else {
            print("Bluetooth not ready: \(centralManager.state.rawValue)")
            updateBluetoothStateMessage()
            return
        }
        
        discoveredBulbs.removeAll()
        isScanning = true
        
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        print("Started scanning for smart bulbs...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.stopScanning()
        }
    }
    
    func stopScanning() {
        if simulatorMode {
            isScanning = false
            print("Simulator: Stopped scanning")
            return
        }
        
        centralManager.stopScan()
        isScanning = false
        print("Stopped scanning")
    }
    
    // MARK: - Connection
    func connect(to bulb: SmartBulb) {
        if simulatorMode && bulb.isSimulated {
            // Simulate connection delay
            print("Simulator: Connecting to \(bulb.name)...")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                var connectedBulb = bulb
                connectedBulb.isConnected = true
                self.connectedBulb = connectedBulb
                
                // Update in discovered bulbs list
                if let index = self.discoveredBulbs.firstIndex(where: { $0.id == bulb.id }) {
                    self.discoveredBulbs[index].isConnected = true
                }
                
                print("Simulator: Connected to \(bulb.name)")
                
                // Simulate initial state
                self.bulbState = BulbState(
                    power: false,
                    brightness: 255,
                    red: 255,
                    green: 255,
                    blue: 255,
                    mode: 0
                )
            }
            return
        }
        
        // Real Bluetooth connection
        guard let peripheral = bulb.peripheral else { return }
        stopScanning()
        centralManager.connect(peripheral, options: nil)
        print("Attempting to connect to \(bulb.name)...")
    }
    
    func disconnect() {
        if simulatorMode {
            print("Simulator: Disconnecting...")
            connectedBulb = nil
            
            for index in discoveredBulbs.indices {
                discoveredBulbs[index].isConnected = false
            }
            return
        }
        
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        print("Disconnecting...")
    }
    
    // MARK: - Control Functions
    func setPower(_ on: Bool) {
        if simulatorMode {
            print("Simulator: Power \(on ? "ON" : "OFF")")
            bulbState.power = on
            return
        }
        
        guard let characteristic = powerCharacteristic else { return }
        let value = Data([on ? 1 : 0])
        connectedPeripheral?.writeValue(value, for: characteristic, type: .withResponse)
        bulbState.power = on
    }
    
    func setBrightness(_ brightness: UInt8) {
        if simulatorMode {
            print("Simulator: Brightness \(brightness)")
            bulbState.brightness = brightness
            return
        }
        
        guard let characteristic = brightnessCharacteristic else { return }
        let value = Data([brightness])
        connectedPeripheral?.writeValue(value, for: characteristic, type: .withResponse)
        bulbState.brightness = brightness
    }
    
    func setColor(red: UInt8, green: UInt8, blue: UInt8) {
        if simulatorMode {
            print("Simulator: Color R:\(red) G:\(green) B:\(blue)")
            bulbState.red = red
            bulbState.green = green
            bulbState.blue = blue
            return
        }
        
        guard let characteristic = colorCharacteristic else { return }
        let value = Data([red, green, blue])
        connectedPeripheral?.writeValue(value, for: characteristic, type: .withResponse)
        bulbState.red = red
        bulbState.green = green
        bulbState.blue = blue
    }
    
    func setMode(_ mode: UInt8) {
        if simulatorMode {
            let modes = ["Solid", "Fade", "Rainbow", "Pulse"]
            print("Simulator: Mode \(modes[Int(mode)])")
            bulbState.mode = mode
            return
        }
        
        guard let characteristic = modeCharacteristic else { return }
        let value = Data([mode])
        connectedPeripheral?.writeValue(value, for: characteristic, type: .withResponse)
        bulbState.mode = mode
    }
    
    // MARK: - Helper to update Bluetooth state message
    private func updateBluetoothStateMessage() {
        DispatchQueue.main.async {
            switch self.centralManager.state {
            case .poweredOn:
                self.bluetoothState = "Ready"
            case .poweredOff:
                self.bluetoothState = "Bluetooth Off"
            case .unauthorized:
                self.bluetoothState = "Unauthorized"
            case .unsupported:
                self.bluetoothState = "Not Supported"
            case .resetting:
                self.bluetoothState = "Resetting"
            case .unknown:
                self.bluetoothState = "Unknown"
            @unknown default:
                self.bluetoothState = "Unknown"
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if simulatorMode {
            bluetoothState = "Simulator Mode"
            return
        }
        
        updateBluetoothStateMessage()
        
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
        case .poweredOff:
            print("Bluetooth is powered off")
        case .unauthorized:
            print("Bluetooth is unauthorized")
        case .unsupported:
            print("⚠️ Bluetooth is not supported on this device (iOS Simulator doesn't support Bluetooth)")
            print("💡 To test Bluetooth features, please use a physical iPhone/iPad")
        default:
            print("Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if simulatorMode { return }
        
        let name = peripheral.name ?? "Unknown Device"
        let rssiValue = RSSI.intValue
        
        let bulb = SmartBulb(
            id: peripheral.identifier,
            name: name,
            peripheral: peripheral,
            rssi: rssiValue,
            isSimulated: false
        )
        
        if !discoveredBulbs.contains(where: { $0.id == bulb.id }) {
            discoveredBulbs.append(bulb)
            print("Discovered: \(name) (RSSI: \(rssiValue))")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if simulatorMode { return }
        
        print("Connected to \(peripheral.name ?? "Unknown")")
        
        connectedPeripheral = peripheral
        peripheral.delegate = self
        
        if let index = discoveredBulbs.firstIndex(where: { $0.peripheral?.identifier == peripheral.identifier }) {
            discoveredBulbs[index].isConnected = true
            connectedBulb = discoveredBulbs[index]
        }
        
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if simulatorMode { return }
        
        print("Disconnected from \(peripheral.name ?? "Unknown")")
        
        connectedPeripheral = nil
        connectedBulb = nil
        
        if let index = discoveredBulbs.firstIndex(where: { $0.peripheral?.identifier == peripheral.identifier }) {
            discoveredBulbs[index].isConnected = false
        }
        
        powerCharacteristic = nil
        brightnessCharacteristic = nil
        colorCharacteristic = nil
        modeCharacteristic = nil
        statusCharacteristic = nil
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if simulatorMode { return }
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if simulatorMode { return }
        
        guard error == nil, let services = peripheral.services else {
            print("Error discovering services: \(error?.localizedDescription ?? "Unknown")")
            return
        }
        
        for service in services {
            if service.uuid == serviceUUID {
                print("Found Smart Bulb service")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if simulatorMode { return }
        
        guard error == nil, let characteristics = service.characteristics else {
            print("Error discovering characteristics: \(error?.localizedDescription ?? "Unknown")")
            return
        }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case powerUUID:
                powerCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
                print("Found power characteristic")
                
            case brightnessUUID:
                brightnessCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
                print("Found brightness characteristic")
                
            case colorUUID:
                colorCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
                print("Found color characteristic")
                
            case modeUUID:
                modeCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
                print("Found mode characteristic")
                
            case statusUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("Found status characteristic (notifications enabled)")
                
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if simulatorMode { return }
        
        guard error == nil, let value = characteristic.value else {
            print("Error reading value: \(error?.localizedDescription ?? "Unknown")")
            return
        }
        
        switch characteristic.uuid {
        case powerUUID:
            if let power = value.first {
                bulbState.power = (power == 1)
            }
            
        case brightnessUUID:
            if let brightness = value.first {
                bulbState.brightness = brightness
            }
            
        case colorUUID:
            if value.count >= 3 {
                bulbState.red = value[0]
                bulbState.green = value[1]
                bulbState.blue = value[2]
            }
            
        case modeUUID:
            if let mode = value.first {
                bulbState.mode = mode
            }
            
        case statusUUID:
            if value.count >= 6 {
                bulbState.power = (value[0] == 1)
                bulbState.brightness = value[1]
                bulbState.red = value[2]
                bulbState.green = value[3]
                bulbState.blue = value[4]
                bulbState.mode = value[5]
                print("Status updated from device")
            }
            
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if simulatorMode { return }
        
        if let error = error {
            print("Write error: \(error.localizedDescription)")
        }
    }
}
