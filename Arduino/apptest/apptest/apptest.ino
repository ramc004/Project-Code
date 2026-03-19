#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ---------------- PINS ----------------
#define WARM_PIN 5
#define COOL_PIN 4

// ---------------- UUIDs ----------------
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define POWER_UUID          "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BRIGHTNESS_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define COLOUR_TEMP_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define MODE_UUID           "beb5483e-36e1-4688-b7f5-ea07361b26ab"
#define STATUS_UUID         "beb5483e-36e1-4688-b7f5-ea07361b26ac"

// ---------------- STATE ----------------
bool powerState = false;
uint8_t brightness = 255;
uint8_t warmValue = 255;
uint8_t coolValue = 0;
uint8_t mode = 0;

// ---------------- BLE ----------------
BLECharacteristic *statusChar;

// ---------------- LED UPDATE ----------------
void updateLEDs() {
  if (!powerState) {
    ledcWrite(0, 0);
    ledcWrite(1, 0);
    return;
  }

  uint16_t warmPWM = ((uint16_t)warmValue * brightness) / 255;
  uint16_t coolPWM = ((uint16_t)coolValue * brightness) / 255;

  ledcWrite(0, warmPWM);
  ledcWrite(1, coolPWM);
}

// ---------------- STATUS ----------------
// 🔥 FIXED: swapped warm/cool for app consistency
void sendStatus() {
  uint8_t status[6] = {
    powerState ? 1 : 0,
    brightness,
    coolValue,  // swapped
    0,
    warmValue,  // swapped
    mode
  };
  statusChar->setValue(status, 6);
  statusChar->notify();
}

// ---------------- CALLBACKS ----------------
class PowerCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) {
    powerState = c->getValue()[0];
    updateLEDs();
    sendStatus();
  }
};

class BrightnessCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) {
    brightness = c->getValue()[0];
    updateLEDs();
    sendStatus();
  }
};

// 🔥 FIXED: swap incoming warm/cool values
class ColourTempCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) {
    std::string v = c->getValue();
    if (v.length() >= 3) {
      warmValue = (uint8_t)v[2];  // swapped
      coolValue = (uint8_t)v[0];  // swapped
    }
    updateLEDs();
    sendStatus();
  }
};

class ModeCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) {
    mode = c->getValue()[0];
    sendStatus();
  }
};

// ---------------- SERVER CALLBACK ----------------
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) {
    Serial.println("App connected");
    delay(100);
    sendStatus();
  }

  void onDisconnect(BLEServer* server) {
    Serial.println("App disconnected");
    BLEDevice::startAdvertising();
  }
};

// ---------------- SETUP ----------------
void setup() {
  Serial.begin(115200);

  // PWM
  ledcSetup(0, 5000, 8);
  ledcAttachPin(WARM_PIN, 0);
  ledcSetup(1, 5000, 8);
  ledcAttachPin(COOL_PIN, 1);

  // BLE
  BLEDevice::init("SmartBulb-ESP32");
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);

  BLECharacteristic *powerChar = service->createCharacteristic(
    POWER_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
  );

  BLECharacteristic *brightnessChar = service->createCharacteristic(
    BRIGHTNESS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
  );

  BLECharacteristic *colourTempChar = service->createCharacteristic(
    COLOUR_TEMP_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
  );

  BLECharacteristic *modeChar = service->createCharacteristic(
    MODE_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE
  );

  statusChar = service->createCharacteristic(
    STATUS_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  statusChar->addDescriptor(new BLE2902());

  // Callbacks
  powerChar->setCallbacks(new PowerCallback());
  brightnessChar->setCallbacks(new BrightnessCallback());
  colourTempChar->setCallbacks(new ColourTempCallback());
  modeChar->setCallbacks(new ModeCallback());

  service->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->start();

  Serial.println("BLE Ready");
}

// ---------------- LOOP ----------------
void loop() {
  updateLEDs();
}