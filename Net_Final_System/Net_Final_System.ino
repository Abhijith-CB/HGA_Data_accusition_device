#include <Wire.h>
#include <WiFi.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>

#define PCA9548A_ADDRESS 0x70

TaskHandle_t IMUTask;
unsigned long lastUpdateTime;
bool imuWorking[4] = {false, false, false, false};

long accelX[4], accelY[4], accelZ[4];
float gForceX[4], gForceY[4], gForceZ[4];

long gyroX[4], gyroY[4], gyroZ[4];
float rotX[4], rotY[4], rotZ[4];

const int MPU_ADDRESS = 0x68;
const int FLEX_PIN1 = 32;
const int FLEX_PIN2 = 33;

const float VCC = 5.0;
const float R_DIV = 1000.0;
const float STRAIGHT_RESISTANCE = 10000.0;
const float BEND_RESISTANCE = 30000.0;

const char* ssid = "ZER0_TW0";
const char* password = "12345678";
AsyncWebServer server(80);
AsyncWebSocket ws("/ws");

void setup() {
  Serial.begin(115200);
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("Connected to WiFi");
server.on("/", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send_P(200, "text/html", R"rawliteral(
      <!DOCTYPE html>
      <html>
      <head>
      <title>ESP32 Data Stream</title>
      <style>
        body { font-family: Arial, sans-serif; text-align: center; border: 2px solid black; }
        .status { padding: 10px; font-size: 18px; margin: 10px auto; display: inline-block; }
        .online { background-color: #4CAF50; color: white; }
        .offline { background-color: #F44336; color: white; }
        .footer { position: fixed; bottom: 10px; width: 100%; text-align: center; font-size: 12px; }
      </style>
      </head>
      <body>
      <h1>Real-Time Sensor Data</h1>
      <div id="status"></div>
      <pre id="data"></pre>
      <div class="footer">Made by ZER0_TW0</div>
      <script>
        const socket = new WebSocket(`ws://${window.location.hostname}/ws`);
        const statusDiv = document.getElementById("status");

        socket.onopen = () => {
          statusDiv.innerHTML = "WebSocket Connected";
          statusDiv.className = "status online";
        };

        socket.onmessage = (event) => {
          const data = event.data;
          document.getElementById("data").innerText = data;
        };

        socket.onclose = () => {
          statusDiv.innerHTML = "WebSocket Disconnected";
          statusDiv.className = "status offline";
        };
      </script>
      </body>
      </html>
    )rawliteral");
  });


  ws.onEvent(onWebSocketEvent);
  server.addHandler(&ws);
  server.begin();

  Wire.begin(21, 22);
  if (!Wire.begin()) {
    Serial.println("Wire library initialization failed!");
    while (1);
  }

  Wire.beginTransmission(PCA9548A_ADDRESS);
  if (Wire.endTransmission() != 0) {
    Serial.println("PCA9548A multiplexer initialization failed!");
    while (1);
  }

  setupMPUs();
  lastUpdateTime = millis();

  xTaskCreatePinnedToCore(
    imuTask, "IMU Task", 10000, NULL, 1, &IMUTask, 1);
}

void loop() {
  ws.cleanupClients();
}

void imuTask(void* parameter) {
  for (;;) {
    if (millis() - lastUpdateTime >= 500) {
      lastUpdateTime = millis();
      String data = "";

      // Collect IMU Data
      for (int i = 0; i < 4; i++) {
        if (imuWorking[i]) {
          selectMuxChannel(i);
          recordAccelRegisters(i);
          recordGyroRegisters(i);
          data += logMPUData(i);
        }
      }

      // // IMU Status Report
      // String imuStatus = "";
      // for (int i = 0; i < 4; i++) {
      //   String statusText = imuWorking[i] ? 
      //     "IMU " + String(i + 1) + " Online" : 
      //     "IMU " + String(i + 1) + " Offline";
      //   imuStatus += statusText + "\n";
      // }
      // Flex Sensor Data
      data += readFlexSensors();
      // Send Data to WebSocket
      //ws.textAll(data + imuStatus);
      ws.textAll(data);
    }
  }
}
void onWebSocketEvent(AsyncWebSocket *server, AsyncWebSocketClient *client, AwsEventType type, void *arg, uint8_t *data, size_t len) {
  if (type == WS_EVT_CONNECT) {
    Serial.println("WebSocket client connected.");
  } else if (type == WS_EVT_DISCONNECT) {
    Serial.println("WebSocket client disconnected.");
  } else if (type == WS_EVT_DATA) {
    Serial.printf("Received Data: %s\n", (char*)data);
  }
}


void selectMuxChannel(uint8_t channel) {
  if (channel > 7) return;
  Wire.beginTransmission(PCA9548A_ADDRESS);
  Wire.write(1 << channel);
  Wire.endTransmission();
}

void setupMPUs() {
  for (int i = 0; i < 4; i++) {
    selectMuxChannel(i);
    Wire.beginTransmission(MPU_ADDRESS);
    Wire.write(0x6B);
    Wire.write(0);
    if (Wire.endTransmission() == 0) {
      imuWorking[i] = true;
      Serial.printf("IMU %d Online\n", i + 1);
    } else {
      imuWorking[i] = false;
      Serial.printf("IMU %d Offline\n", i + 1);
    }
  }
}


String logMPUData(int sensorIndex) {
  String data = "MPU6050 " + String(sensorIndex + 1) + " Gyro X=" + String(rotX[sensorIndex]) + " Y=" + String(rotY[sensorIndex]) + " Z=" + String(rotZ[sensorIndex]);
  data += " Accel X=" + String(gForceX[sensorIndex]) + " Y=" + String(gForceY[sensorIndex]) + " Z=" + String(gForceZ[sensorIndex]) + "\n";
  return data;
}

String readFlexSensors() {
  String data = "";
  int flexADC1 = analogRead(FLEX_PIN1);
  float flexV1 = flexADC1 * 3.3 / 4095.0;
  float flexR1 = R_DIV * (VCC / flexV1 - 1.0);
  float angle1 = map(flexR1, STRAIGHT_RESISTANCE, BEND_RESISTANCE, 0, 9000) / 100.0;
  data += "Bend Sensor 1: " + String(angle1) + " degrees, Resistance: " + String(flexR1) + " ohms\n";

  int flexADC2 = analogRead(FLEX_PIN2);
  float flexV2 = flexADC2 * 3.3 / 4095.0;
  float flexR2 = R_DIV * (VCC / flexV2 - 1.0);
  float angle2 = map(flexR2, STRAIGHT_RESISTANCE, BEND_RESISTANCE, 0, 9000) / 100.0;
  data += "Bend Sensor 2: " + String(angle2) + " degrees, Resistance: " + String(flexR2) + " ohms\n";

  return data;
}
void recordAccelRegisters(int sensorIndex) {
  Wire.beginTransmission(MPU_ADDRESS);
  Wire.write(0x3B);
  Wire.endTransmission();
  Wire.requestFrom(MPU_ADDRESS, 6);

  while (Wire.available() < 6);
  accelX[sensorIndex] = Wire.read() << 8 | Wire.read();
  accelY[sensorIndex] = Wire.read() << 8 | Wire.read();
  accelZ[sensorIndex] = Wire.read() << 8 | Wire.read();
  processAccelData(sensorIndex);
}
void recordGyroRegisters(int sensorIndex) {
  Wire.beginTransmission(MPU_ADDRESS);
  Wire.write(0x43);
  Wire.endTransmission();
  Wire.requestFrom(MPU_ADDRESS, 6);

  while (Wire.available() < 6);
  gyroX[sensorIndex] = Wire.read() << 8 | Wire.read();
  gyroY[sensorIndex] = Wire.read() << 8 | Wire.read();
  gyroZ[sensorIndex] = Wire.read() << 8 | Wire.read();
  processGyroData(sensorIndex);
}
void processAccelData(int sensorIndex) {
  gForceX[sensorIndex] = accelX[sensorIndex] / 16384.0;
  gForceY[sensorIndex] = accelY[sensorIndex] / 16384.0;
  gForceZ[sensorIndex] = accelZ[sensorIndex] / 16384.0;
}
void processGyroData(int sensorIndex) {
  rotX[sensorIndex] = gyroX[sensorIndex] / 131.0;
  rotY[sensorIndex] = gyroY[sensorIndex] / 131.0;
  rotZ[sensorIndex] = gyroZ[sensorIndex] / 131.0;
}
