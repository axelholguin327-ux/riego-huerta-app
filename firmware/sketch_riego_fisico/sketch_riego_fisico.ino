// Firmware del nodo de riego (ESP32) · versión 0.4
// Cambios respecto a la 0.3 (marcados con [0.4]):
//  - Credenciales en secrets.h (no se suben al repositorio).
//  - Tarjetas RFID administradas desde la app: atributo compartido "rfid_cards".
//  - La tarjeta riega la primera zona que tiene permitida (antes siempre la 1).
//  - Pide "mode" y "rfid_cards" al conectarse, así el modo elegido en la app
//    se conserva aunque el ESP32 se reinicie.
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <SPI.h>
#include <MFRC522.h>
#include "secrets.h"   // [0.4] copia secrets.h.example como secrets.h

// ---------- WiFi / ThingsBoard ----------
const char* WIFI_SSID = WIFI_SSID_VALUE;
const char* WIFI_PASS = WIFI_PASS_VALUE;

const char* TB_HOST  = "mqtt.thingsboard.cloud";
const int   TB_PORT  = 1883;
const char* TB_TOKEN = TB_TOKEN_VALUE;

#define DHTPIN 27
#define DHTTYPE DHT22
DHT dht(DHTPIN, DHTTYPE);

// RC522 con pines remapeados (RST del módulo conectado directo a 3V3)
#define RFID_SCK  14
#define RFID_MISO 12
#define RFID_MOSI 13
#define SS_PIN    33
MFRC522 rfid(SS_PIN, MFRC522::UNUSED_PIN);

#define SOIL_ZONA1 34
#define SOIL_ZONA2 35
#define RELAY_ZONA1 25
#define RELAY_ZONA2 26
#define RELAY_BOMBA 32

// Módulos de relé típicos: se activan con LOW. Si el clic sale al revés, intercambia estos dos.
#define RELAY_ON  LOW
#define RELAY_OFF HIGH

// CALIBRAR con los valores RAW del monitor serie: SOIL_DRY = al aire (seco), SOIL_WET = en agua.
// Valores iniciales de ejemplo para YL-69.
const int SOIL_DRY = 4095;
const int SOIL_WET = 1800;
const bool DEBUG_RAW = true;   // imprime lecturas crudas; ponlo en false al terminar de calibrar

// ---------- Parámetros ----------
const unsigned long SAMPLE_MS    = 1000UL;
const unsigned long TELEMETRY_MS = 10000UL;
const unsigned long AUTO_MAX_S   = 15;    // pruebas con agua; subir a 120 en uso real
const unsigned long RFID_RUN_S   = 10;    // riego por tarjeta; subir a 30 en uso real
const bool REQUIRE_AUTH = false;               // solo se usa si la app aún no registró tarjetas
const char* ALLOWED_UIDS[] = { "SIM00001" };   // respaldo si "rfid_cards" está vacío

// [0.4] Tarjetas autorizadas desde la app (atributo compartido "rfid_cards")
struct Card { String uid; uint8_t zones; bool active; };   // zones: bit0 = zona 1, bit1 = zona 2
const int MAX_CARDS = 20;
Card cards[MAX_CARDS];
int cardCount = 0;

// ---------- Estado ----------
struct Zone { int pin; bool on; unsigned long offAt; bool autoRun; };
Zone zones[2] = { {RELAY_ZONA1, false, 0, false}, {RELAY_ZONA2, false, 0, false} };
bool pumpOn = false;
String mode = "manual";   // arranca en manual; al conectarse toma el modo guardado desde la app
int thresholdPct = 35;
int soilPct[2] = {0, 0};
float temperatura = 0, humedadAmbiente = 0;
unsigned long lastTelemetry = 0, lastSample = 0, lastMqttTry = 0, lastCard = 0;

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);

// ---------- Actuadores ----------
void updatePump() {
  pumpOn = zones[0].on || zones[1].on;
  digitalWrite(RELAY_BOMBA, pumpOn ? RELAY_ON : RELAY_OFF);
}

void setZone(int i, bool st, unsigned long durS = 0, bool byAuto = false) {
  zones[i].on = st;
  zones[i].autoRun = st && byAuto;
  zones[i].offAt = (st && durS > 0) ? millis() + durS * 1000UL : 0;
  digitalWrite(zones[i].pin, st ? RELAY_ON : RELAY_OFF);
  updatePump();
}

// ---------- Sensores ----------
int readSoilPct(int pin) {
  long sum = 0;
  for (int k = 0; k < 8; k++) sum += analogRead(pin);
  return constrain(map(sum / 8, SOIL_DRY, SOIL_WET, 0, 100), 0, 100);
}

void sampleSensors() {
  float t = dht.readTemperature(), h = dht.readHumidity();
  if (!isnan(t)) temperatura = t;
  if (!isnan(h)) humedadAmbiente = h;
  if (DEBUG_RAW) Serial.printf("RAW soil1=%d soil2=%d\n", analogRead(SOIL_ZONA1), analogRead(SOIL_ZONA2));
  soilPct[0] = readSoilPct(SOIL_ZONA1);
  soilPct[1] = readSoilPct(SOIL_ZONA2);
}

void autoControl() {
  if (mode != "auto") return;
  for (int i = 0; i < 2; i++) {
    if (!zones[i].on && soilPct[i] < thresholdPct) setZone(i, true, AUTO_MAX_S, true);
    else if (zones[i].on && zones[i].autoRun && soilPct[i] >= thresholdPct + 10) setZone(i, false);
  }
}

// ---------- Telemetría (mismos nombres que usa el dashboard y la app) ----------
void publicarTelemetria() {
  JsonDocument d;
  d["temp_c"] = temperatura;
  d["hum_amb"] = humedadAmbiente;
  d["soil1"] = soilPct[0];
  d["soil2"] = soilPct[1];
  d["valve1"] = zones[0].on;
  d["valve2"] = zones[1].on;
  d["pump"] = pumpOn;
  d["mode"] = mode;
  d["soil_threshold_pct"] = thresholdPct;
  char buf[384];
  serializeJson(d, buf);
  Serial.println(buf);
  if (mqtt.connected()) mqtt.publish("v1/devices/me/telemetry", buf);
}

// ---------- Comandos y atributos desde ThingsBoard ----------
// [0.4] Lee la lista [{"uid":"5C8E21A7","name":"...","zones":[1,2],"active":true}, ...]
void loadCards(JsonArray arr) {
  cardCount = 0;
  for (JsonObject c : arr) {
    if (cardCount >= MAX_CARDS) break;
    uint8_t mask = 0;
    for (int z : c["zones"].as<JsonArray>()) if (z >= 1 && z <= 2) mask |= (1 << (z - 1));
    String uid = c["uid"] | "";
    uid.toUpperCase();
    cards[cardCount++] = { uid, mask, c["active"] | true };
  }
  Serial.printf("Tarjetas RFID cargadas: %d\n", cardCount);
}

void applyShared(JsonObject o) {
  if (o["soil_threshold_pct"].is<int>()) thresholdPct = o["soil_threshold_pct"];
  if (o["mode"].is<const char*>()) mode = o["mode"].as<String>();
  if (o["rfid_cards"].is<JsonArray>()) loadCards(o["rfid_cards"].as<JsonArray>());   // [0.4]
}

void handleRpc(const String& id, JsonDocument& doc) {
  const char* method = doc["method"] | "";
  JsonObject p = doc["params"];
  JsonDocument res;
  if (strcmp(method, "setIrrigation") == 0) {
    int zone = p["zone"] | 0;
    bool st = p["state"] | false;
    unsigned long dur = p["duration_s"] | 60;
    if (zone >= 1 && zone <= 2) {
      setZone(zone - 1, st, constrain(dur, 1UL, 600UL));
      res["ok"] = true; res["zone"] = zone; res["state"] = st;
    } else res["ok"] = false;
  } else if (strcmp(method, "setMode") == 0) {
    mode = p["mode"] | "auto";
    res["ok"] = true; res["mode"] = mode;
  } else res["ok"] = false;
  char out[128];
  serializeJson(res, out);
  mqtt.publish(("v1/devices/me/rpc/response/" + id).c_str(), out);
  publicarTelemetria();
}

void onMessage(char* topic, byte* payload, unsigned int len) {
  JsonDocument doc;
  if (deserializeJson(doc, payload, len)) return;
  String t(topic);
  const String rpcPrefix = "v1/devices/me/rpc/request/";
  if (t.startsWith(rpcPrefix)) {
    handleRpc(t.substring(rpcPrefix.length()), doc);
  } else if (t.startsWith("v1/devices/me/attributes")) {
    JsonObject src = doc["shared"].is<JsonObject>() ? doc["shared"].as<JsonObject>()
                                                    : doc.as<JsonObject>();
    applyShared(src);
  }
}

// ---------- WiFi / MQTT ----------
void conectarWifi() {
  Serial.print("Conectando a WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  int intentos = 0;
  while (WiFi.status() != WL_CONNECTED && intentos < 20) {
    delay(300);
    Serial.print(".");
    intentos++;
  }
  Serial.println(WiFi.status() == WL_CONNECTED ? " OK" : " sin conexion (se reintenta en el loop)");
}

void conectarMqtt() {
  Serial.print("Conectando a ThingsBoard...");
  if (mqtt.connect("nodo-riego-huerta", TB_TOKEN, NULL)) {
    Serial.println(" MQTT OK");
    mqtt.subscribe("v1/devices/me/rpc/request/+");
    mqtt.subscribe("v1/devices/me/attributes");
    mqtt.subscribe("v1/devices/me/attributes/response/+");
    mqtt.publish("v1/devices/me/attributes", "{\"fw\":\"0.4\"}");   // [0.4]
    mqtt.publish("v1/devices/me/attributes/request/1",
                 "{\"sharedKeys\":\"mode,soil_threshold_pct,rfid_cards\"}");   // [0.4]
  } else {
    Serial.print(" fallo, rc=");
    Serial.println(mqtt.state());
  }
}

// ---------- RFID ----------
void manejarTarjeta() {
  if (millis() - lastCard < 2000) return;
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) return;
  lastCard = millis();

  String uid = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (rfid.uid.uidByte[i] < 0x10) uid += "0";
    uid += String(rfid.uid.uidByte[i], HEX);
  }
  uid.toUpperCase();
  rfid.PICC_HaltA();

  // [0.4] Si la app ya registró tarjetas, se usa esa lista; si no, la lógica anterior.
  bool ok = false;
  int zone = 1;
  if (cardCount > 0) {
    for (int i = 0; i < cardCount; i++) {
      if (cards[i].uid == uid && cards[i].active && cards[i].zones) {
        ok = true;
        zone = (cards[i].zones & 1) ? 1 : 2;   // primera zona permitida
        break;
      }
    }
  } else {
    ok = !REQUIRE_AUTH;
    for (auto u : ALLOWED_UIDS) if (uid == u) ok = true;
  }

  JsonDocument d;
  d["rfid_uid"] = uid;
  d["rfid_ok"] = ok;
  d["action"] = ok ? "manual_irrigation" : "denied";
  d["zone"] = zone;
  char buf[160];
  serializeJson(d, buf);
  Serial.println(buf);
  if (mqtt.connected()) mqtt.publish("v1/devices/me/telemetry", buf);

  if (ok) { setZone(zone - 1, true, RFID_RUN_S); publicarTelemetria(); }
}

// ---------- Arduino ----------
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("=== SISTEMA DE RIEGO INICIADO (fw 0.4) ===");

  dht.begin();
  SPI.begin(RFID_SCK, RFID_MISO, RFID_MOSI, SS_PIN);
  rfid.PCD_Init();

  // Apagado ANTES de configurar como salida, para que el relé no haga clic al arrancar
  digitalWrite(RELAY_ZONA1, RELAY_OFF);
  digitalWrite(RELAY_ZONA2, RELAY_OFF);
  digitalWrite(RELAY_BOMBA, RELAY_OFF);
  pinMode(RELAY_ZONA1, OUTPUT);
  pinMode(RELAY_ZONA2, OUTPUT);
  pinMode(RELAY_BOMBA, OUTPUT);

  sampleSensors();
  conectarWifi();
  mqtt.setServer(TB_HOST, TB_PORT);
  mqtt.setBufferSize(1024);   // [0.4] la lista de tarjetas necesita más espacio (antes 512)
  mqtt.setCallback(onMessage);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) conectarWifi();
  if (!mqtt.connected()) {
    if (millis() - lastMqttTry > 5000) { lastMqttTry = millis(); conectarMqtt(); }
  } else {
    mqtt.loop();
  }

  // Apagado por temporizador (riego manual / RPC / RFID)
  for (int i = 0; i < 2; i++)
    if (zones[i].on && zones[i].offAt && (long)(millis() - zones[i].offAt) >= 0)
      setZone(i, false);

  manejarTarjeta();

  if (millis() - lastSample >= SAMPLE_MS) {
    lastSample = millis();
    sampleSensors();
    autoControl();
  }

  if (millis() - lastTelemetry >= TELEMETRY_MS) {
    lastTelemetry = millis();
    publicarTelemetria();
  }

  delay(50);
}
