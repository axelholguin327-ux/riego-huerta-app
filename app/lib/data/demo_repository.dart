// Modo demo: simula el nodo ESP32 con la misma lógica del firmware
// (humedad que baja, riego automático por umbral, válvulas con temporizador,
// bomba y alarmas). Sirve para probar y presentar la app sin el hardware.
import 'dart:async';
import 'dart:math';

import 'models.dart';
import 'repository.dart';

class DemoRepository implements HuertaRepository {
  DemoRepository({this.tick = const Duration(seconds: 2)}) {
    _seedHistory();
    _timer = Timer.periodic(tick, (_) => _step());
  }

  final Duration tick;
  final _rnd = Random(7);
  final _ctrl = StreamController<Telemetry>.broadcast();
  late final Timer _timer;

  double _soil1 = 62, _soil2 = 31, _temp = 24.5, _hum = 44;
  final _offAt = <int, DateTime?>{1: null, 2: null};
  final _autoRun = <int, bool>{1: false, 2: false};
  String _mode = 'auto';
  int _threshold = 35;
  String? _rfidUid;
  bool? _rfidOk;
  DateTime? _rfidAt;

  final _history = <SoilPoint>[];
  final _events = <IrrigationEvent>[];
  final _access = <RfidAccess>[];
  final _alarms = <AlarmItem>[];
  final _openStart = <int, DateTime>{};
  var _cards = <RfidCard>[
    const RfidCard(uid: 'SIM00001', name: 'Axel Holguín', zones: [1, 2]),
    const RfidCard(uid: 'SIM00002', name: 'Daniel Varela', zones: [2]),
  ];

  @override
  String get userName => 'Usuario demo';
  @override
  String get userEmail => 'demo@huerta.mx';
  @override
  bool get isDemo => true;

  bool _on(int z) => _offAt[z] != null;

  Telemetry get _state => Telemetry(
        tempC: double.parse(_temp.toStringAsFixed(1)),
        humAmb: double.parse(_hum.toStringAsFixed(1)),
        soil1: _soil1.round(),
        soil2: _soil2.round(),
        valve1: _on(1),
        valve2: _on(2),
        pump: _on(1) || _on(2),
        mode: _mode,
        threshold: _threshold,
        updatedAt: DateTime.now(),
        rfidUid: _rfidUid,
        rfidOk: _rfidOk,
        rfidAt: _rfidAt,
      );

  void _seedHistory() {
    final now = DateTime.now();
    for (var i = 7 * 24; i >= 0; i--) {
      final t = now.subtract(Duration(hours: i));
      _history.add(SoilPoint(t, 55 + 12 * sin(i / 9), 40 + 22 * sin(i / 5 + 1)));
    }
    _events.addAll([
      IrrigationEvent(zone: 2, start: now.subtract(const Duration(hours: 3)), end: now.subtract(const Duration(hours: 3, minutes: -2))),
      IrrigationEvent(zone: 1, start: now.subtract(const Duration(hours: 20)), end: now.subtract(const Duration(hours: 20, minutes: -1))),
    ]);
    _access.addAll([
      RfidAccess(ts: now.subtract(const Duration(hours: 2)), uid: 'SIM00001', authorized: true, zone: 1),
      RfidAccess(ts: now.subtract(const Duration(hours: 5)), uid: 'A1B2C3D4', authorized: false, zone: 1),
    ]);
    _alarms.add(AlarmItem(
        id: 'demo-0', type: 'Humedad de suelo baja', severity: 'MAJOR', state: AlarmState.clearedAck,
        createdAt: now.subtract(const Duration(days: 1, hours: 2)), clearedAt: now.subtract(const Duration(days: 1))));
  }

  void _setZone(int z, bool on, int durS, {bool auto = false}) {
    final now = DateTime.now();
    if (on && !_on(z)) _openStart[z] = now;
    if (!on && _on(z)) {
      _events.insert(0, IrrigationEvent(zone: z, start: _openStart[z] ?? now, end: now));
    }
    _offAt[z] = on ? now.add(Duration(seconds: durS)) : null;
    _autoRun[z] = on && auto;
  }

  void _step() {
    final now = DateTime.now();
    for (final z in [1, 2]) {
      if (_on(z) && now.isAfter(_offAt[z]!)) _setZone(z, false, 0);
    }
    // Sensores: el suelo se seca poco a poco y sube si se riega.
    _soil1 = (_soil1 + (_on(1) ? 4.5 : -0.35 - _rnd.nextDouble() * 0.3)).clamp(0, 100);
    _soil2 = (_soil2 + (_on(2) ? 4.5 : -0.35 - _rnd.nextDouble() * 0.3)).clamp(0, 100);
    _temp = (_temp + (_rnd.nextDouble() - 0.5) * 0.2).clamp(10, 38);
    _hum = (_hum + (_rnd.nextDouble() - 0.5) * 0.4).clamp(20, 80);

    // Misma lógica que autoControl() del firmware.
    if (_mode == 'auto') {
      for (final z in [1, 2]) {
        final s = z == 1 ? _soil1 : _soil2;
        if (!_on(z) && s < _threshold) _setZone(z, true, 120, auto: true);
        if (_on(z) && _autoRun[z]! && s >= _threshold + 10) _setZone(z, false, 0);
      }
    }
    // Misma regla del Rule Engine: alarma si alguna zona < 25 %.
    final low = _soil1 < 25 || _soil2 < 25;
    final active = _alarms.indexWhere((a) => a.isActive);
    if (low && active < 0) {
      _alarms.insert(0, AlarmItem(id: 'demo-${_alarms.length}', type: 'Humedad de suelo baja',
          severity: 'MAJOR', state: AlarmState.activeUnack, createdAt: now));
    } else if (!low && active >= 0) {
      final a = _alarms[active];
      _alarms[active] = AlarmItem(id: a.id, type: a.type, severity: a.severity,
          state: a.isAcknowledged ? AlarmState.clearedAck : AlarmState.clearedUnack,
          createdAt: a.createdAt, clearedAt: now);
    }
    if (!_ctrl.isClosed) _ctrl.add(_state);
  }

  /// Simula acercar una tarjeta al lector RC522 (para el registro).
  void simulateCard(String uid) {
    final card = _cards.where((c) => c.uid == uid && c.active).firstOrNull;
    _rfidUid = uid;
    _rfidOk = card != null;
    _rfidAt = DateTime.now();
    _access.insert(0, RfidAccess(ts: _rfidAt!, uid: uid, authorized: card != null, zone: card?.zones.first));
    if (card != null) _setZone(card.zones.first, true, 30);
    _ctrl.add(_state);
  }

  Future<void> _delay() => Future.delayed(const Duration(milliseconds: 600));

  @override
  Future<DeviceInfo> device() async => DeviceInfo(
      id: 'demo', name: 'nodo-huerta-test (demo)', firmware: '0.3', active: true, lastActivity: DateTime.now());

  @override
  Stream<Telemetry> telemetry() {
    Future.microtask(() => _ctrl.add(_state));
    return _ctrl.stream;
  }

  @override
  Future<void> setIrrigation(int zone, bool state, int durationS) async {
    await _delay();
    _setZone(zone, state, durationS);
    _ctrl.add(_state);
  }

  @override
  Future<bool> setMode(String mode) async {
    await _delay();
    _mode = mode;
    _ctrl.add(_state);
    return true;
  }

  @override
  Future<void> setThreshold(int pct) async {
    await _delay();
    _threshold = pct;
    _ctrl.add(_state);
  }

  @override
  Future<List<AlarmItem>> alarms() async => List.of(_alarms);

  @override
  Future<void> ackAlarm(String id) async {
    await _delay();
    final i = _alarms.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final a = _alarms[i];
    _alarms[i] = a.copyWith(state: a.isActive ? AlarmState.activeAck : AlarmState.clearedAck);
  }

  @override
  Future<List<SoilPoint>> soilHistory(Duration range) async {
    final from = DateTime.now().subtract(range);
    final pts = _history.where((p) => p.ts.isAfter(from)).toList();
    if (pts.length < 6) {
      // Rango corto: puntos sintéticos cada pocos minutos.
      final n = 12;
      return [
        for (var i = n; i >= 0; i--)
          SoilPoint(DateTime.now().subtract(range * (i / n)),
              _soil1 + i * 0.4, _soil2 + i * 0.5)
      ];
    }
    return pts;
  }

  @override
  Future<List<IrrigationEvent>> irrigationEvents(Duration range) async {
    final from = DateTime.now().subtract(range);
    final open = [
      for (final z in [1, 2])
        if (_on(z)) IrrigationEvent(zone: z, start: _openStart[z] ?? DateTime.now())
    ];
    return [...open, ..._events.where((e) => e.start.isAfter(from))];
  }

  @override
  Future<List<RfidAccess>> rfidAccesses({int limit = 20}) async => _access.take(limit).toList();

  @override
  Future<List<RfidCard>> rfidCards() async => List.of(_cards);

  @override
  Future<void> saveRfidCards(List<RfidCard> cards) async {
    await _delay();
    _cards = List.of(cards);
  }

  @override
  Future<void> close() async {
    _timer.cancel();
    await _ctrl.close();
  }
}
