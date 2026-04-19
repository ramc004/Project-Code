/*
 * SmartBulb ESP32 Firmware
 * Supports: power, brightness, colour temp, mode, pulse effect,
 *           time sync, and autonomous schedule execution stored in flash.
 *
 * Schedule payload written by the iOS app over BLE (SCHEDULE_UUID):
 *   Byte 0:     command  — 0=clear all, 1=add schedule, 2=delete by slot
 *   Byte 1:     slot     — 0..19 (max 20 schedules)
 *   Byte 2:     hour     — 0..23
 *   Byte 3:     minute   — 0..59
 *   Byte 4:     action   — 0=powerOn,1=powerOff,2=dimWarm,3=brightenCool,
 *                          4=setBrightness,5=setColour
 *   Byte 5:     brightness — 0..255
 *   Byte 6:     colourTemp — 0..255 (0=cool, 255=warm)
 *   Byte 7:     days_bitmask — bit0=Mon..bit6=Sun  (0x7F = every day)
 *   Byte 8:     enabled  — 0 or 1
 *
 * Time sync payload written by the iOS app over BLE (TIME_UUID):
 *   Byte 0: hour   (0..23)
 *   Byte 1: minute (0..59)
 *   Byte 2: second (0..59)
 *   Byte 3: weekday (1=Mon..7=Sun)
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>
#include <math.h>

// ---------------- PINS ----------------
#define WARM_PIN 5
#define COOL_PIN 4

// ---------------- UUIDs ----------------
#define SERVICE_UUID     "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define POWER_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BRIGHTNESS_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define COLOUR_TEMP_UUID "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define MODE_UUID        "beb5483e-36e1-4688-b7f5-ea07361b26ab"
#define STATUS_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26ac"
// NEW:
#define SCHEDULE_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26ad"
#define TIME_UUID        "beb5483e-36e1-4688-b7f5-ea07361b26ae"

// ---------------- SCHEDULE STORAGE ----------------
#define MAX_SCHEDULES 20

struct Schedule {
  bool     valid;       // slot occupied?
  uint8_t  hour;
  uint8_t  minute;
  uint8_t  action;      // 0=powerOn 1=powerOff 2=dimWarm 3=brightenCool 4=brightness 5=colour
  uint8_t  brightness;
  uint8_t  colourTemp;  // 0=cool 255=warm
  uint8_t  daysMask;    // bit0=Mon..bit6=Sun
  bool     enabled;
};

Schedule schedules[MAX_SCHEDULES];
Preferences prefs;

// ---------------- CLOCK (maintained by millis()) ----------------
uint8_t clockHour    = 0;
uint8_t clockMinute  = 0;
uint8_t clockSecond  = 0;
uint8_t clockWeekday = 1; // 1=Mon..7=Sun
unsigned long lastMillis = 0;

// Tracks which (minute) we last fired per slot to prevent double-fire
uint8_t lastFiredMinute[MAX_SCHEDULES];

// ---------------- LED STATE ----------------
bool    powerState = false;
uint8_t brightness = 255;
uint8_t warmValue  = 255;
uint8_t coolValue  = 0;
uint8_t mode       = 0;

// Pulse effect
float   pulsePhase    = 0.0;
bool    pulseBrighter = true;
unsigned long lastPulseMillis = 0;

BLECharacteristic *statusChar;

// ---------------- FLASH PERSISTENCE ----------------
void saveScheduleToFlash(int slot) {
  char key[16];
  prefs.begin("schedules", false);

  snprintf(key, sizeof(key), "v%d",   slot); prefs.putBool(key,  schedules[slot].valid);
  snprintf(key, sizeof(key), "h%d",   slot); prefs.putUChar(key, schedules[slot].hour);
  snprintf(key, sizeof(key), "m%d",   slot); prefs.putUChar(key, schedules[slot].minute);
  snprintf(key, sizeof(key), "a%d",   slot); prefs.putUChar(key, schedules[slot].action);
  snprintf(key, sizeof(key), "b%d",   slot); prefs.putUChar(key, schedules[slot].brightness);
  snprintf(key, sizeof(key), "c%d",   slot); prefs.putUChar(key, schedules[slot].colourTemp);
  snprintf(key, sizeof(key), "d%d",   slot); prefs.putUChar(key, schedules[slot].daysMask);
  snprintf(key, sizeof(key), "e%d",   slot); prefs.putBool(key,  schedules[slot].enabled);

  prefs.end();
}

void loadAllSchedulesFromFlash() {
  char key[16];
  prefs.begin("schedules", true);  // read-only

  for (int i = 0; i < MAX_SCHEDULES; i++) {
    snprintf(key, sizeof(key), "v%d", i);
    schedules[i].valid = prefs.getBool(key, false);
    if (schedules[i].valid) {
      snprintf(key, sizeof(key), "h%d", i); schedules[i].hour       = prefs.getUChar(key, 0);
      snprintf(key, sizeof(key), "m%d", i); schedules[i].minute     = prefs.getUChar(key, 0);
      snprintf(key, sizeof(key), "a%d", i); schedules[i].action     = prefs.getUChar(key, 1);
      snprintf(key, sizeof(key), "b%d", i); schedules[i].brightness = prefs.getUChar(key, 255);
      snprintf(key, sizeof(key), "c%d", i); schedules[i].colourTemp = prefs.getUChar(key, 255);
      snprintf(key, sizeof(key), "d%d", i); schedules[i].daysMask   = prefs.getUChar(key, 0x7F);
      snprintf(key, sizeof(key), "e%d", i); schedules[i].enabled    = prefs.getBool(key, true);
      Serial.printf("  Loaded slot %d: %02d:%02d action=%d days=%02X\n",
                    i, schedules[i].hour, schedules[i].minute,
                    schedules[i].action, schedules[i].daysMask);
    }
    lastFiredMinute[i] = 255; // sentinel = never fired
  }

  prefs.end();

  int count = 0;
  for (int i = 0; i < MAX_SCHEDULES; i++) if (schedules[i].valid && schedules[i].enabled) count++;
  Serial.printf("Schedules loaded from flash: %d enabled slot(s)\n", count);
}

void clearAllSchedulesFromFlash() {
  prefs.begin("schedules", false);
  prefs.clear();
  prefs.end();
  for (int i = 0; i < MAX_SCHEDULES; i++) {
    schedules[i].valid   = false;
    schedules[i].enabled = false;
    lastFiredMinute[i]   = 255;
  }
  Serial.println("All schedules cleared from flash.");
}

// ---------------- GAMMA ----------------
float applyGamma(uint8_t value) {
  float normalized = value / 255.0;
  return pow(normalized, 2.2);
}

// ---------------- LED UPDATE ----------------
void updateLEDs() {
  if (!powerState) {
    ledcWrite(0, 0);
    ledcWrite(1, 0);
    return;
  }

  float b = applyGamma(brightness);
  uint16_t total = warmValue + coolValue;
  float warmNorm = 0, coolNorm = 0;
  if (total > 0) {
    warmNorm = (float)warmValue / total;
    coolNorm = (float)coolValue / total;
  }

  if (mode == 1) {
    // Pulse: slow sine wave on brightness
    float pulse = 0.4 + 0.6 * (0.5 + 0.5 * sin(pulsePhase));
    b *= pulse;
  }

  uint16_t warmPWM = (uint16_t)(warmNorm * b * 255);
  uint16_t coolPWM = (uint16_t)(coolNorm * b * 255);
  ledcWrite(0, warmPWM);
  ledcWrite(1, coolPWM);
}

// ---------------- STATUS NOTIFY ----------------
void sendStatus() {
  uint8_t status[6] = {
    powerState ? 1 : 0,
    brightness,
    coolValue, 0, warmValue,
    mode
  };
  statusChar->setValue(status, 6);
  statusChar->notify();
}

// ---------------- SCHEDULE EXECUTION ----------------
void executeAction(int slot) {
  Schedule &s = schedules[slot];
  Serial.printf("⏰ Firing slot %d: action=%d bright=%d ct=%d\n",
                slot, s.action, s.brightness, s.colourTemp);
  switch (s.action) {
    case 0: // powerOn
      powerState = true;
      break;
    case 1: // powerOff
      powerState = false;
      break;
    case 2: // dimWarm
      powerState = true;
      brightness = s.brightness;
      warmValue  = 255;
      coolValue  = 0;
      break;
    case 3: // brightenCool
      powerState = true;
      brightness = s.brightness;
      warmValue  = 0;
      coolValue  = 255;
      break;
    case 4: // setBrightness
      brightness = s.brightness;
      break;
    case 5: // setColour  (colourTemp: 255=warm, 0=cool)
      warmValue = s.colourTemp;
      coolValue = 255 - s.colourTemp;
      break;
  }
  updateLEDs();
  sendStatus();
}

void checkSchedules() {
  // Convert weekday (1=Mon..7=Sun) to bitmask bit position (bit0=Mon)
  uint8_t dayBit = (uint8_t)(1 << (clockWeekday - 1));
  Serial.printf("⏱ Tick %02d:%02d weekday=%d dayBit=0x%02X\n",
                clockHour, clockMinute, clockWeekday, dayBit);

  for (int i = 0; i < MAX_SCHEDULES; i++) {
    if (!schedules[i].valid || !schedules[i].enabled) continue;
    if (!(schedules[i].daysMask & dayBit))             continue;
    if (schedules[i].hour   != clockHour)              continue;
    if (schedules[i].minute != clockMinute)            continue;
    if (lastFiredMinute[i]  == clockMinute)            continue; // already fired this minute

    lastFiredMinute[i] = clockMinute;
    executeAction(i);
  }
}

// ---------------- CLOCK TICK ----------------
void tickClock() {
  unsigned long now = millis();
  unsigned long elapsed = now - lastMillis;
  if (elapsed < 1000) return;

  // Handle millis() overflow gracefully
  lastMillis = now;

  clockSecond++;
  if (clockSecond >= 60) {
    clockSecond = 0;
    clockMinute++;
    // Reset lastFiredMinute sentinels so each schedule can fire once per
    // matching minute. Clear only slots that fired in a *different* minute,
    // so a time-sync that nudges the clock back a few seconds into the same
    // minute cannot cause an immediate double-fire.
    for (int i = 0; i < MAX_SCHEDULES; i++) {
      if (lastFiredMinute[i] != clockMinute) {
        lastFiredMinute[i] = 255; // 255 = "not yet fired this minute"
      }
    }
    if (clockMinute >= 60) {
      clockMinute = 0;
      clockHour++;
      if (clockHour >= 24) {
        clockHour = 0;
        clockWeekday = (clockWeekday % 7) + 1;
      }
    }
    // Check schedules once per minute (at second 0)
    checkSchedules();
  }
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
  }
};

class ColourTempCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) {
    std::string v = c->getValue();
    if (v.length() >= 3) {
      warmValue = (uint8_t)v[2];
      coolValue = (uint8_t)v[0];
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

// NEW: receives schedule payloads from the iOS app
class ScheduleCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) {
    std::string v = c->getValue();
    if (v.length() < 1) return;

    uint8_t command = (uint8_t)v[0];

    if (command == 0) {
      // Clear all schedules
      clearAllSchedulesFromFlash();
      Serial.println("BLE: clear all schedules");
      return;
    }

    if (v.length() < 9) return;
    uint8_t slot = (uint8_t)v[1];
    if (slot >= MAX_SCHEDULES) return;

    if (command == 2) {
      // Delete single slot
      schedules[slot].valid   = false;
      schedules[slot].enabled = false;
      saveScheduleToFlash(slot);
      Serial.printf("BLE: deleted slot %d\n", slot);
      return;
    }

    if (command == 1) {
      // Add / update schedule
      schedules[slot].valid      = true;
      schedules[slot].hour       = (uint8_t)v[2];
      schedules[slot].minute     = (uint8_t)v[3];
      schedules[slot].action     = (uint8_t)v[4];
      schedules[slot].brightness = (uint8_t)v[5];
      schedules[slot].colourTemp = (uint8_t)v[6];
      schedules[slot].daysMask   = (uint8_t)v[7];
      schedules[slot].enabled    = (bool)v[8];
      lastFiredMinute[slot]      = 255;  // reset so it can fire today
      saveScheduleToFlash(slot);
      Serial.printf("BLE: added slot %d  %02d:%02d  action=%d  days=%02X\n",
                    slot, schedules[slot].hour, schedules[slot].minute,
                    schedules[slot].action, schedules[slot].daysMask);
    }
  }
};

// NEW: receives current time from the iOS app for clock sync
class TimeCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) {
    std::string v = c->getValue();
    if (v.length() < 4) return;
    clockHour    = (uint8_t)v[0];
    clockMinute  = (uint8_t)v[1];
    clockSecond  = (uint8_t)v[2];
    clockWeekday = (uint8_t)v[3];  // 1=Mon..7=Sun
    lastMillis   = millis();
    Serial.printf("Clock synced: %02d:%02d:%02d weekday=%d\n",
                  clockHour, clockMinute, clockSecond, clockWeekday);
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) {
    Serial.println("App connected");
    delay(100);
    sendStatus();
  }
  void onDisconnect(BLEServer* server) {
    Serial.println("App disconnected — schedules still active");
    BLEDevice::startAdvertising();
  }
};

// ---------------- SETUP ----------------
void setup() {
  Serial.begin(115200);

  ledcSetup(0, 5000, 8);
  ledcAttachPin(WARM_PIN, 0);
  ledcSetup(1, 5000, 8);
  ledcAttachPin(COOL_PIN, 1);

  loadAllSchedulesFromFlash();
  lastMillis = millis();

  BLEDevice::init("SmartBulb-ESP32");
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(BLEUUID(SERVICE_UUID), 30); // 30 handles for extra chars

  auto makeChar = [&](const char* uuid, uint32_t props) {
    return service->createCharacteristic(uuid, props);
  };
  const uint32_t RW = BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE;
  const uint32_t WO = BLECharacteristic::PROPERTY_WRITE;

  auto *powerChar      = makeChar(POWER_UUID,       RW);
  auto *brightnessChar = makeChar(BRIGHTNESS_UUID,  RW);
  auto *colourTempChar = makeChar(COLOUR_TEMP_UUID, RW);
  auto *modeChar       = makeChar(MODE_UUID,        RW);
  auto *scheduleChar   = makeChar(SCHEDULE_UUID,    WO);
  auto *timeChar       = makeChar(TIME_UUID,        WO);

  statusChar = service->createCharacteristic(STATUS_UUID,
                  BLECharacteristic::PROPERTY_NOTIFY);
  statusChar->addDescriptor(new BLE2902());

  powerChar->setCallbacks(new PowerCallback());
  brightnessChar->setCallbacks(new BrightnessCallback());
  colourTempChar->setCallbacks(new ColourTempCallback());
  modeChar->setCallbacks(new ModeCallback());
  scheduleChar->setCallbacks(new ScheduleCallback());
  timeChar->setCallbacks(new TimeCallback());

  service->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->start();

  Serial.println("BLE Ready — schedule engine running");
}

// ---------------- LOOP ----------------
void loop() {
  tickClock();

  // Pulse animation update (every ~30ms when mode==1 and power on)
  if (mode == 1 && powerState) {
    unsigned long now = millis();
    if (now - lastPulseMillis >= 30) {
      lastPulseMillis = now;
      pulsePhase += 0.05;
      if (pulsePhase > 2 * PI) pulsePhase -= 2 * PI;
      updateLEDs();
    }
  } else {
    updateLEDs();
  }
}
