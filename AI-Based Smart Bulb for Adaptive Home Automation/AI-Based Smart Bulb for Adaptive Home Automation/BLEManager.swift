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
    var isSimulated: Bool = false
    
    static func == (lhs: SmartBulb, rhs: SmartBulb) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Bulb State
// colourTemp: 0 = full warm white, 255 = full cool white
struct BulbState {
    var power: Bool = false
    var brightness: UInt8 = 255
    var colourTemp: UInt8 = 255  // 255 = warm, 0 = cool
    var mode: UInt8 = 0          // 0 = solid, 1 = fade/pulse
}

// MARK: - BLE Manager
class BLEManager: NSObject, ObservableObject {
    @Published var discoveredBulbs: [SmartBulb] = []
    @Published var connectedBulb: SmartBulb?
    @Published var bulbState: BulbState = BulbState()
    @Published var isScanning: Bool = false
    @Published var bluetoothState: String = "Unknown"
    
    var simulatorMode: Bool {
        if UserDefaults.standard.object(forKey: "simulatorMode") == nil {
            UserDefaults.standard.set(true, forKey: "simulatorMode")
            return true
        }
        return UserDefaults.standard.bool(forKey: "simulatorMode")
    }
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    
    // Service and Characteristic UUIDs (must match ESP32)
    private let serviceUUID    = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    private let powerUUID      = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    private let brightnessUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a9")
    // colourTemp uses the old colorUUID slot — one byte: 0=warm, 255=cool
    private let colourTempUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26aa")
    private let modeUUID       = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26ab")
    private let statusUUID     = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26ac")
    
    private var powerCharacteristic: CBCharacteristic?
    private var brightnessCharacteristic: CBCharacteristic?
    private var colourTempCharacteristic: CBCharacteristic?
    private var modeCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    
    private var simulatedBulbIDs: [UUID] = []
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        loadSimulatedBulbIDs()
        if simulatorMode {
            updateBluetoothStateForSimulator()
        }
    }
    
    // MARK: - Simulator helpers
    private func loadSimulatedBulbIDs() {
        if let savedIDs = UserDefaults.standard.array(forKey: "simulatedBulbIDs") as? [String] {
            simulatedBulbIDs = savedIDs.compactMap { UUID(uuidString: $0) }
        }
        if simulatedBulbIDs.count < 3 {
            simulatedBulbIDs = [UUID(), UUID(), UUID()]
            UserDefaults.standard.set(simulatedBulbIDs.map { $0.uuidString }, forKey: "simulatedBulbIDs")
        }
    }
    
    private func createSimulatedBulbs() -> [SmartBulb] {
        let names = [
            "Smart Strip (Simulated)",
            "Living Room Strip (Simulated)",
            "Bedroom Strip (Simulated)"
        ]
        return zip(simulatedBulbIDs, names).enumerated().map { index, pair in
            SmartBulb(id: pair.0, name: pair.1, peripheral: nil, rssi: -45 - (index * 10), isSimulated: true)
        }
    }
    
    private func updateBluetoothStateForSimulator() {
        DispatchQueue.main.async { self.bluetoothState = "Simulator Mode" }
    }
    
    func refreshSimulatorMode() {
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
            isScanning = true
            bluetoothState = "Simulator Mode"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.discoveredBulbs = self.createSimulatedBulbs()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.stopScanning() }
            return
        }
        
        guard centralManager.state == .poweredOn else {
            updateBluetoothStateMessage()
            return
        }
        discoveredBulbs.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(withServices: [serviceUUID],
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.stopScanning() }
    }
    
    func stopScanning() {
        if simulatorMode { isScanning = false; return }
        centralManager.stopScan()
        isScanning = false
    }
    
    // MARK: - Connection
    func connect(to bulb: SmartBulb) {
        if simulatorMode && bulb.isSimulated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                var connected = bulb
                connected.isConnected = true
                self.connectedBulb = connected
                if let index = self.discoveredBulbs.firstIndex(where: { $0.id == bulb.id }) {
                    self.discoveredBulbs[index].isConnected = true
                }
                self.bulbState = BulbState(power: false, brightness: 255, colourTemp: 255, mode: 0)
            }
            return
        }
        guard let peripheral = bulb.peripheral else { return }
        stopScanning()
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        if simulatorMode {
            connectedBulb = nil
            for index in discoveredBulbs.indices { discoveredBulbs[index].isConnected = false }
            return
        }
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    // MARK: - Control
    func setPower(_ on: Bool) {
        if simulatorMode { bulbState.power = on; return }
        guard let c = powerCharacteristic else { return }
        connectedPeripheral?.writeValue(Data([on ? 1 : 0]), for: c, type: .withResponse)
        bulbState.power = on
    }
    
    func setBrightness(_ brightness: UInt8) {
        if simulatorMode { bulbState.brightness = brightness; return }
        guard let c = brightnessCharacteristic else { return }
        connectedPeripheral?.writeValue(Data([brightness]), for: c, type: .withResponse)
        bulbState.brightness = brightness
    }
    
    /// colourTemp: 0 = cool white, 255 = warm white
    func setColourTemp(_ temp: UInt8) {
        if simulatorMode {
            bulbState.colourTemp = temp
            return
        }
        guard let c = colourTempCharacteristic else { return }
        // Arduino byte[0]=warmValue, byte[2]=coolValue
        // temp=255 → full warm: byte[0]=255, byte[2]=0
        // temp=0   → full cool: byte[0]=0,   byte[2]=255
        let warmByte: UInt8 = temp
        let coolByte: UInt8 = 255 - temp
        connectedPeripheral?.writeValue(Data([warmByte, 0, coolByte]), for: c, type: .withResponse)
        bulbState.colourTemp = temp
    }
    
    func setMode(_ mode: UInt8) {
        if simulatorMode { bulbState.mode = mode; return }
        guard let c = modeCharacteristic else { return }
        connectedPeripheral?.writeValue(Data([mode]), for: c, type: .withResponse)
        bulbState.mode = mode
    }
    // MARK: - Bluetooth state helper
    private func updateBluetoothStateMessage() {
        DispatchQueue.main.async {
            switch self.centralManager.state {
            case .poweredOn:   self.bluetoothState = "Ready"
            case .poweredOff:  self.bluetoothState = "Bluetooth Off"
            case .unauthorized:self.bluetoothState = "Unauthorized"
            case .unsupported: self.bluetoothState = "Not Supported"
            case .resetting:   self.bluetoothState = "Resetting"
            default:           self.bluetoothState = "Unknown"
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if simulatorMode { bluetoothState = "Simulator Mode"; return }
        updateBluetoothStateMessage()
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if simulatorMode { return }
        let bulb = SmartBulb(id: peripheral.identifier,
                             name: peripheral.name ?? "Unknown Device",
                             peripheral: peripheral,
                             rssi: RSSI.intValue,
                             isSimulated: false)
        if !discoveredBulbs.contains(where: { $0.id == bulb.id }) {
            discoveredBulbs.append(bulb)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if simulatorMode { return }
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
        connectedPeripheral = nil
        connectedBulb = nil
        if let index = discoveredBulbs.firstIndex(where: { $0.peripheral?.identifier == peripheral.identifier }) {
            discoveredBulbs[index].isConnected = false
        }
        powerCharacteristic = nil
        brightnessCharacteristic = nil
        colourTempCharacteristic = nil
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
        guard error == nil, let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if simulatorMode { return }
        guard error == nil, let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case powerUUID:
                powerCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
            case brightnessUUID:
                brightnessCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
            case colourTempUUID:
                colourTempCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
            case modeUUID:
                modeCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
            case statusUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if simulatorMode { return }
        guard error == nil, let value = characteristic.value else { return }
        switch characteristic.uuid {
        case powerUUID:
            if let v = value.first { bulbState.power = (v == 1) }
        case brightnessUUID:
            if let v = value.first { bulbState.brightness = v }
        case colourTempUUID:
            if let v = value.first { bulbState.colourTemp = v }
        case modeUUID:
            if let v = value.first { bulbState.mode = v }
        case statusUUID:
            // Original Arduino status packet: [power, brightness, warmValue, 0, coolValue, mode]
            // warmValue (byte[2]) maps directly to our colourTemp slider (high = warm)
            if value.count >= 6 {
                bulbState.power = (value[0] == 1)
                bulbState.brightness = value[1]
                bulbState.colourTemp = value[2]  // warmValue: 255=warm, 0=cool
                bulbState.mode = value[5]
            }
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error { print("Write error: \(error.localizedDescription)") }
    }
}
