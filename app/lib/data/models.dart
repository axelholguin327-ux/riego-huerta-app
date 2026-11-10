// Modelos de la app. Los nombres de las claves son los mismos que publica
// el firmware del ESP32 (publicarTelemetria / manejarTarjeta).

/// Último estado conocido del nodo (telemetría más reciente).
class Telemetry {
  final double? tempC;
  final double? humAmb;
  final int? soil1;
  final int? soil2;
  final bool valve1;
  final bool valve2;
  final bool pump;
  final String mode; // 'auto' | 'manual'
  final int threshold; // soil_threshold_pct
  final DateTime? updatedAt; // hora del último dato de sensores
  final String? rfidUid;
  final bool? rfidOk;
  final DateTime? rfidAt;

  const Telemetry({
    this.tempC,
    this.humAmb,
    this.soil1,
    this.soil2,
    this.valve1 = false,
    this.valve2 = false,
    this.pump = false,
    this.mode = 'manual',
    this.threshold = 50,
    this.updatedAt,
    this.rfidUid,
    this.rfidOk,
    this.rfidAt,
  });

  static const empty = Telemetry();

  int? soil(int zone) => zone == 1 ? soil1 : soil2;
  bool valve(int zone) => zone == 1 ? valve1 : valve2;

  bool isOnline(DateTime now, Duration offlineAfter) =>
      updatedAt != null && now.difference(updatedAt!) < offlineAfter;

  /// Combina valores recibidos de ThingsBoard ({clave: [ts, valor]}) con el
  /// estado actual. Solo cambia lo que viene en el mensaje.
  Telemetry merge(Map<String, (int, String)> v) {
    DateTime? ts(String k) =>
        v[k] == null ? null : DateTime.fromMillisecondsSinceEpoch(v[k]!.$1);
    String? s(String k) => v[k]?.$2;
    double? d(String k) => s(k) == null ? null : double.tryParse(s(k)!);
    int? i(String k) => d(k)?.round();
    bool? b(String k) => s(k) == null ? null : s(k) == 'true' || s(k) == '1';

    // La hora de "actualizado" la marcan las lecturas de sensores, no el RFID.
    DateTime? sensorTs;
    for (final k in ['temp_c', 'hum_amb', 'soil1', 'soil2', 'valve1', 'pump']) {
      final t = ts(k);
      if (t != null && (sensorTs == null || t.isAfter(sensorTs))) sensorTs = t;
    }

    return Telemetry(
      tempC: d('temp_c') ?? tempC,
      humAmb: d('hum_amb') ?? humAmb,
      soil1: i('soil1') ?? soil1,
      soil2: i('soil2') ?? soil2,
      valve1: b('valve1') ?? valve1,
      valve2: b('valve2') ?? valve2,
      pump: b('pump') ?? pump,
      mode: s('mode') ?? mode,
      threshold: i('soil_threshold_pct') ?? threshold,
      updatedAt: sensorTs != null && (updatedAt == null || sensorTs.isAfter(updatedAt!)) ? sensorTs : updatedAt,
      rfidUid: s('rfid_uid') ?? rfidUid,
      rfidOk: b('rfid_ok') ?? rfidOk,
      rfidAt: ts('rfid_uid') ?? rfidAt,
    );
  }
}

/// Claves de telemetría que la app pide a ThingsBoard.
const telemetryKeys = [
  'temp_c', 'hum_amb', 'soil1', 'soil2', 'valve1', 'valve2', 'pump',
  'mode', 'soil_threshold_pct', 'rfid_uid', 'rfid_ok',
];

class DeviceInfo {
  final String id;
  final String name;
  final String? firmware;
  final bool active;
  final DateTime? lastActivity;
  const DeviceInfo({required this.id, required this.name, this.firmware, this.active = false, this.lastActivity});
}

enum AlarmState { activeUnack, activeAck, clearedUnack, clearedAck }

class AlarmItem {
  final String id;
  final String type;
  final String severity; // CRITICAL, MAJOR, MINOR, WARNING, INDETERMINATE
  final AlarmState state;
  final DateTime createdAt;
  final DateTime? clearedAt;
  final String? detail;

  const AlarmItem({
    required this.id,
    required this.type,
    required this.severity,
    required this.state,
    required this.createdAt,
    this.clearedAt,
    this.detail,
  });

  bool get isActive => state == AlarmState.activeUnack || state == AlarmState.activeAck;
  bool get isAcknowledged => state == AlarmState.activeAck || state == AlarmState.clearedAck;

  static AlarmState parseStatus(String s) => switch (s) {
        'ACTIVE_ACK' => AlarmState.activeAck,
        'CLEARED_UNACK' => AlarmState.clearedUnack,
        'CLEARED_ACK' => AlarmState.clearedAck,
        _ => AlarmState.activeUnack,
      };

  AlarmItem copyWith({AlarmState? state}) => AlarmItem(
      id: id, type: type, severity: severity, state: state ?? this.state,
      createdAt: createdAt, clearedAt: clearedAt, detail: detail);
}

/// Punto de la gráfica de humedad de suelo.
class SoilPoint {
  final DateTime ts;
  final double? soil1;
  final double? soil2;
  const SoilPoint(this.ts, this.soil1, this.soil2);
}

/// Lectura de tarjeta en el lector RC522 del nodo.
class RfidAccess {
  final DateTime ts;
  final String uid;
  final bool authorized;
  final int? zone;
  const RfidAccess({required this.ts, required this.uid, required this.authorized, this.zone});
}

/// Periodo en que una válvula estuvo abierta (se calcula del historial de
/// valve1/valve2).
class IrrigationEvent {
  final int zone;
  final DateTime start;
  final DateTime? end; // null = sigue regando
  const IrrigationEvent({required this.zone, required this.start, this.end});
  Duration? get duration => end?.difference(start);
}

/// Tarjeta autorizada. Se guarda en el atributo compartido `rfid_cards` del
/// dispositivo para que el ESP32 la pueda validar.
class RfidCard {
  final String uid;
  final String name;
  final List<int> zones;
  final bool active;

  const RfidCard({required this.uid, required this.name, required this.zones, this.active = true});

  Map<String, dynamic> toJson() => {'uid': uid, 'name': name, 'zones': zones, 'active': active};

  factory RfidCard.fromJson(Map<String, dynamic> j) => RfidCard(
        uid: (j['uid'] ?? '').toString().toUpperCase(),
        name: (j['name'] ?? '').toString(),
        zones: [for (final z in (j['zones'] as List? ?? const [])) (z as num).toInt()],
        active: j['active'] as bool? ?? true,
      );

  RfidCard copyWith({bool? active}) => RfidCard(uid: uid, name: name, zones: zones, active: active ?? this.active);
}

/// Error de comunicación con un mensaje entendible para el usuario.
class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override
  String toString() => message;
}

/// Obtiene los periodos de riego a partir de la serie de valve1/valve2
/// (ordenada de más antigua a más reciente).
List<IrrigationEvent> deriveIrrigationEvents(int zone, List<(int, bool)> series) {
  final events = <IrrigationEvent>[];
  DateTime? start;
  for (final (ts, on) in series) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts);
    if (on && start == null) {
      start = t;
    } else if (!on && start != null) {
      events.add(IrrigationEvent(zone: zone, start: start, end: t));
      start = null;
    }
  }
  if (start != null) events.add(IrrigationEvent(zone: zone, start: start));
  return events;
}
