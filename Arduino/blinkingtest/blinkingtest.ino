#define WARM_PIN 5
#define COOL_PIN 4

void setup() {
  // Setup PWM channels
  ledcSetup(0, 5000, 8); // Channel 0, 5kHz, 8-bit
  ledcAttachPin(WARM_PIN, 0);

  ledcSetup(1, 5000, 8); // Channel 1
  ledcAttachPin(COOL_PIN, 1);

  // Start OFF
  ledcWrite(0, 0);
  ledcWrite(1, 0);
}

void loop() {

  // 🔴 Warm White ONLY
  ledcWrite(0, 255); // Warm ON
  ledcWrite(1, 0);   // Cool OFF
  delay(2000);

  // 🔵 Cool White ONLY
  ledcWrite(0, 0);   
  ledcWrite(1, 255); // Cool ON
  delay(2000);

  // ⚪ Neutral White (both)
  ledcWrite(0, 255); 
  ledcWrite(1, 255);
  delay(2000);

  // 🔴 Dim Warm
  ledcWrite(0, 100);
  ledcWrite(1, 0);
  delay(2000);

  // 🔵 Dim Cool
  ledcWrite(0, 0);
  ledcWrite(1, 100);
  delay(2000);

  // ⚫ OFF
  ledcWrite(0, 0);
  ledcWrite(1, 0);
  delay(2000);
}