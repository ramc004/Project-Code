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

// ---------------- BLE OBJECTS ----------------
BLECharacteristic *powerChar;
BLECharacteristic *brightnessChar;
BLECharacteristic *colourTempChar;
BLECharacteristic *modeChar;
BLECharacteristic *statusChar;

// ---------------- STATE ----------------
bool    powerState = false;
uint8_t brightness = 255;
uint8_t warmValue  = 255;
uint8_t coolValue  = 0;
uint8_t mode       = 0;

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
// [power, brightness, warmValue, 0, coolValue, mode] — 6 bytes
void sendStatus() {
  uint8_t status[6] = {
    powerState ? (uint8_t)1 : (uint8_t)0,
    brightness,
    warmValue,
    0,
    coolValue,
    mode
  };
  statusChar->setValue(status, 6);
  statusChar->notify();
}

// ---------------- CALLBACKS ----------------
class PowerCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    powerState = (uint8_t)pCharacteristic->getValue()[0] != 0;
    updateLEDs();
    sendStatus();
  }
};

class BrightnessCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    brightness = (uint8_t)pCharacteristic->getValue()[0];
    updateLEDs();
    sendStatus();
  }
};

class ColourTempCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    std::string value = pCharacteristic->getValue();
    if (value.length() >= 3) {
      warmValue = (uint8_t)value[0];
      coolValue = (uint8_t)value[2];
    }
    updateLEDs();
    sendStatus();
  }
};

class ModeCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    mode = (uint8_t)pCharacteristic->getValue()[0];
    sendStatus();
  }
};

// ---------------- SETUP ----------------
void setup() {
  Serial.begin(115200);

  ledcSetup(0, 5000, 8);
  ledcAttachPin(WARM_PIN, 0);
  ledcSetup(1, 5000, 8);
  ledcAttachPin(COOL_PIN, 1);

  ledcWrite(0, 0);
  ledcWrite(1, 0);

  BLEDevice::init("SmartBulb-ESP32");
  BLEServer  *server  = BLEDevice::createServer();
  BLEService *service = server->createService(SERVICE_UUID);

  powerChar = service->createCharacteristic(
    POWER_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);

  brightnessChar = service->createCharacteristic(
    BRIGHTNESS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);

  colourTempChar = service->createCharacteristic(
    COLOUR_TEMP_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);

  modeChar = service->createCharacteristic(
    MODE_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);

  statusChar = service->createCharacteristic(
    STATUS_UUID,
    BLECharacteristic::PROPERTY_NOTIFY);

  statusChar->addDescriptor(new BLE2902());

  powerChar->setCallbacks(new PowerCallback());
  brightnessChar->setCallbacks(new BrightnessCallback());
  colourTempChar->setCallbacks(new ColourTempCallback());
  modeChar->setCallbacks(new ModeCallback());

  service->start();

  // Set initial values so app reads correct state on connect
  uint8_t initPower      = 0;
  uint8_t initBrightness = 255;
  uint8_t initColour[3]  = {255, 0, 0};  // warmValue=255, coolValue=0
  uint8_t initMode       = 0;
  powerChar->setValue(&initPower, 1);
  brightnessChar->setValue(&initBrightness, 1);
  colourTempChar->setValue(initColour, 3);
  modeChar->setValue(&initMode, 1);

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->start();

  Serial.println("Smart Strip BLE Ready");
}

// ---------------- LOOP ----------------
void loop() {
  if (!powerState || mode != 1) return;

  for (int b = 50; b <= 255; b += 3) {
    if (!powerState || mode != 1) return;
    ledcWrite(0, ((uint16_t)warmValue * b) / 255);
    ledcWrite(1, ((uint16_t)coolValue * b) / 255);
    delay(10);
  }
  for (int b = 255; b >= 50; b -= 3) {
    if (!powerState || mode != 1) return;
    ledcWrite(0, ((uint16_t)warmValue * b) / 255);
    ledcWrite(1, ((uint16_t)coolValue * b) / 255);
    delay(10);
  }
}
