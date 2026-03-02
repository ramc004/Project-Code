#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "esp32-hal-ledc.h"

// ---------------- PINS ----------------
#define WARM_PIN 5
#define COOL_PIN 6

// ---------------- UUIDs (MATCH APP) ----------------
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define POWER_UUID          "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BRIGHTNESS_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define COLOR_UUID          "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define MODE_UUID           "beb5483e-36e1-4688-b7f5-ea07361b26ab"
#define STATUS_UUID         "beb5483e-36e1-4688-b7f5-ea07361b26ac"

// ---------------- BLE OBJECTS ----------------
BLECharacteristic *powerChar;
BLECharacteristic *brightnessChar;
BLECharacteristic *colorChar;
BLECharacteristic *modeChar;
BLECharacteristic *statusChar;

// ---------------- STATE VARIABLES ----------------
bool powerState = false;
uint8_t brightness = 255;
uint8_t warmValue = 255;
uint8_t coolValue = 0;
uint8_t mode = 0;

// ---------------- LED UPDATE ----------------
void updateLEDs() {

  if (!powerState) {
    ledcWrite(WARM_PIN, 0);
    ledcWrite(COOL_PIN, 0);
    return;
  }

  uint16_t warmPWM = (warmValue * brightness) / 255;
  uint16_t coolPWM = (coolValue * brightness) / 255;

  ledcWrite(WARM_PIN, warmPWM);
  ledcWrite(COOL_PIN, coolPWM);
}

// ---------------- SEND STATUS BACK TO APP ----------------
void sendStatus() {

  uint8_t status[6] = {
    powerState ? 1 : 0,
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
    powerState = pCharacteristic->getValue()[0];
    updateLEDs();
    sendStatus();
  }
};

class BrightnessCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    brightness = pCharacteristic->getValue()[0];
    updateLEDs();
    sendStatus();
  }
};

class ColorCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String value = pCharacteristic->getValue();

    if (value.length() >= 3) {
      warmValue = (uint8_t)value[0];  // RED channel
      coolValue = (uint8_t)value[2];  // BLUE channel
    }

    updateLEDs();
    sendStatus();
  }
};

class ModeCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    mode = pCharacteristic->getValue()[0];
    sendStatus();
  }
};

// ---------------- SETUP ----------------
void setup() {

  Serial.begin(115200);

  // PWM setup, modern ESP32 API
  ledcAttach(WARM_PIN, 5000, 8);
  ledcAttach(COOL_PIN, 5000, 8);

  // BLE init
  BLEDevice::init("SmartBulb-ESP32");

  BLEServer *server = BLEDevice::createServer();
  BLEService *service = server->createService(SERVICE_UUID);

  powerChar = service->createCharacteristic(
                POWER_UUID,
                BLECharacteristic::PROPERTY_READ |
                BLECharacteristic::PROPERTY_WRITE
              );

  brightnessChar = service->createCharacteristic(
                BRIGHTNESS_UUID,
                BLECharacteristic::PROPERTY_READ |
                BLECharacteristic::PROPERTY_WRITE
              );

  colorChar = service->createCharacteristic(
                COLOR_UUID,
                BLECharacteristic::PROPERTY_READ |
                BLECharacteristic::PROPERTY_WRITE
              );

  modeChar = service->createCharacteristic(
                MODE_UUID,
                BLECharacteristic::PROPERTY_READ |
                BLECharacteristic::PROPERTY_WRITE
              );

  statusChar = service->createCharacteristic(
                STATUS_UUID,
                BLECharacteristic::PROPERTY_NOTIFY
              );

  statusChar->addDescriptor(new BLE2902());

  powerChar->setCallbacks(new PowerCallback());
  brightnessChar->setCallbacks(new BrightnessCallback());
  colorChar->setCallbacks(new ColorCallback());
  modeChar->setCallbacks(new ModeCallback());

  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->start();

  Serial.println("Smart Bulb BLE Ready");
}

// ---------------- LOOP ----------------
void loop() {
}