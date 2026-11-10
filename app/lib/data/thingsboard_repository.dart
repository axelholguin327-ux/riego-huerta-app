// Implementación real: se conecta a ThingsBoard Cloud con la API REST y el
// WebSocket de telemetría, usando la sesión (JWT) de un usuario de
// ThingsBoard.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import 'models.dart';
import 'repository.dart';

class TbSession {
  final String token;
  final String refreshToken;
  const TbSession(this.token, this.refreshToken);
}

class ThingsBoardRepository implements HuertaRepository {
  ThingsBoardRepository._(this._client, this._session, this._user, this._device, this.onSession);

  final http.Client _client;
  TbSession _session;
  final Map<String, dynamic> _user;
  final DeviceInfo _device;

  /// Se llama cuando el token se renueva, para guardarlo de nuevo.
  final void Function(TbSession) onSession;

  WebSocketChannel? _ws;
  StreamController<Telemetry>? _telemetry;
  Telemetry _last = Telemetry.empty;
  Timer? _pollTimer;
  bool _closed = false;

  // ------------------------------------------------------------ sesión ---

  /// Inicia sesión con usuario y contraseña de ThingsBoard.
  static Future<TbSession> login(String email, String password, {http.Client? client}) async {
    final c = client ?? http.Client();
    final res = await _send(() => c.post(AppConfig.api('/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': email, 'password': password})));
    if (res.statusCode == 401) throw const AppException('Correo o contraseña incorrectos');
    _check(res);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return TbSession(j['token'] as String, j['refreshToken'] as String);
  }

  /// Abre el repositorio con una sesión existente: obtiene el usuario y
  /// busca el dispositivo configurado.
  static Future<ThingsBoardRepository> open(TbSession session,
      {required void Function(TbSession) onSession, http.Client? client}) async {
    final c = client ?? http.Client();
    var s = session;
    Future<http.Response> authGet(Uri u) => _send(() => c.get(u, headers: {'X-Authorization': 'Bearer ${s.token}'}));

    var userRes = await authGet(AppConfig.api('/api/auth/user'));
    if (userRes.statusCode == 401) {
      s = await _refresh(c, s);
      onSession(s);
      userRes = await authGet(AppConfig.api('/api/auth/user'));
    }
    _check(userRes);
    final user = jsonDecode(userRes.body) as Map<String, dynamic>;

    // Un usuario de cliente solo ve los dispositivos asignados a su cliente.
    final isTenant = user['authority'] == 'TENANT_ADMIN';
    final Uri devicesUri = isTenant
        ? AppConfig.api('/api/tenant/devices', {'pageSize': '50', 'page': '0', 'textSearch': AppConfig.deviceName})
        : AppConfig.api('/api/customer/${user['customerId']['id']}/devices',
            {'pageSize': '50', 'page': '0', 'textSearch': AppConfig.deviceName});
    final devRes = await authGet(devicesUri);
    _check(devRes);
    final list = (jsonDecode(devRes.body)['data'] as List).cast<Map<String, dynamic>>();
    final dev = list.where((d) => d['name'] == AppConfig.deviceName).firstOrNull;
    if (dev == null) {
      throw const AppException('Tu usuario no tiene asignado el dispositivo '
          '"${AppConfig.deviceName}". Pide que lo asignen a tu cliente en ThingsBoard.');
    }
    final repo = ThingsBoardRepository._(
        c, s, user, DeviceInfo(id: dev['id']['id'] as String, name: dev['name'] as String), onSession);
    return repo;
  }

  static Future<TbSession> _refresh(http.Client c, TbSession s) async {
    final res = await _send(() => c.post(AppConfig.api('/api/auth/token'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refreshToken': s.refreshToken})));
    if (res.statusCode != 200) throw const AppException('Tu sesión expiró. Vuelve a iniciar sesión.');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return TbSession(j['token'] as String, j['refreshToken'] as String);
  }

  @override
  String get userName {
    final n = '${_user['firstName'] ?? ''} ${_user['lastName'] ?? ''}'.trim();
    return n.isEmpty ? userEmail : n;
  }

  @override
  String get userEmail => _user['email'] as String? ?? '';

  @override
  bool get isDemo => false;

  String get _id => _device.id;

  // ------------------------------------------------------------ HTTP ---

  static Future<http.Response> _send(Future<http.Response> Function() f) async {
    try {
      return await f().timeout(const Duration(seconds: 15));
    } on SocketException {
      throw const AppException('Sin conexión a Internet');
    } on TimeoutException {
      throw const AppException('El servidor tardó demasiado en responder');
    } on http.ClientException {
      throw const AppException('No se pudo conectar con ThingsBoard');
    }
  }

  static void _check(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    String msg = 'Error del servidor (${r.statusCode})';
    try {
      final m = jsonDecode(r.body)['message'];
      if (m is String && m.isNotEmpty) msg = m;
    } catch (_) {}
    if (r.statusCode == 403) msg = 'Tu usuario no tiene permiso para esta acción';
    throw AppException(msg);
  }

  /// Petición autenticada; si el token expiró lo renueva y reintenta.
  Future<http.Response> _req(String method, String path, {Map<String, String>? query, Object? body}) async {
    Future<http.Response> go() {
      final uri = AppConfig.api(path, query);
      final h = {'X-Authorization': 'Bearer ${_session.token}', 'Content-Type': 'application/json'};
      final b = body == null ? null : jsonEncode(body);
      return _send(() => method == 'GET' ? _client.get(uri, headers: h) : _client.post(uri, headers: h, body: b));
    }

    var res = await go();
    if (res.statusCode == 401) {
      _session = await _refresh(_client, _session);
      onSession(_session);
      res = await go();
    }
    return res;
  }

  Future<dynamic> _getJson(String path, [Map<String, String>? query]) async {
    final r = await _req('GET', path, query: query);
    _check(r);
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  // ------------------------------------------------------------ dispositivo ---

  @override
  Future<DeviceInfo> device() async {
    final attrs = (await _getJson('/api/plugins/telemetry/DEVICE/$_id/values/attributes',
        {'keys': 'active,lastActivityTime,fw'}) as List);
    final m = {for (final a in attrs) a['key'] as String: a['value']};
    return DeviceInfo(
      id: _id,
      name: _device.name,
      firmware: m['fw']?.toString(),
      active: m['active'] == true,
      lastActivity: m['lastActivityTime'] is num
          ? DateTime.fromMillisecondsSinceEpoch((m['lastActivityTime'] as num).toInt())
          : null,
    );
  }

  // ------------------------------------------------------------ telemetría ---

  static Map<String, (int, String)> _parseTs(Map<String, dynamic> data) => {
        for (final e in data.entries)
          if (e.value is List && (e.value as List).isNotEmpty)
            e.key: _point(e.value as List),
      };

  // REST: [{"ts":..,"value":".."}] · WebSocket: [[ts,".."]]
  static (int, String) _point(List l) {
    final p = l.first;
    if (p is Map) return ((p['ts'] as num).toInt(), p['value'].toString());
    return (((p as List)[0] as num).toInt(), p[1].toString());
  }

  Future<void> _loadLatest() async {
    final data = await _getJson('/api/plugins/telemetry/DEVICE/$_id/values/timeseries',
        {'keys': telemetryKeys.join(',')}) as Map<String, dynamic>;
    _emit(_parseTs(data));
  }

  void _emit(Map<String, (int, String)> values) {
    if (values.isEmpty) return;
    _last = _last.merge(values);
    _telemetry?.add(_last);
  }

  @override
  Stream<Telemetry> telemetry() {
    if (_telemetry != null) return _telemetry!.stream;
    _telemetry = StreamController<Telemetry>.broadcast(onListen: () {
      _telemetry!.add(_last);
    });
    _start();
    return _telemetry!.stream;
  }

  Future<void> _start() async {
    try {
      await _loadLatest();
    } catch (e) {
      _telemetry?.addError(e);
    }
    _connectWs();
  }

  /// Suscripción en vivo por WebSocket. Si falla, se consulta por REST cada
  /// 10 s y se reintenta el WebSocket.
  void _connectWs() {
    if (_closed) return;
    try {
      final ch = WebSocketChannel.connect(AppConfig.webSocket);
      _ws = ch;
      ch.sink.add(jsonEncode({
        'authCmd': {'cmdId': 0, 'token': _session.token},
        'cmds': [
          {
            'type': 'TIMESERIES',
            'entityType': 'DEVICE',
            'entityId': _id,
            'scope': 'LATEST_TELEMETRY',
            'cmdId': 10,
          }
        ],
      }));
      _pollTimer?.cancel();
      ch.stream.listen((msg) {
        final j = jsonDecode(msg as String) as Map<String, dynamic>;
        if ((j['errorCode'] ?? 0) != 0) return;
        final data = j['data'];
        if (data is Map<String, dynamic>) _emit(_parseTs(data));
      }, onError: (_) => _fallback(), onDone: _fallback, cancelOnError: true);
    } catch (_) {
      _fallback();
    }
  }

  void _fallback() {
    if (_closed || (_pollTimer?.isActive ?? false)) return;
    var ticks = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (t) async {
      try {
        await _loadLatest();
      } catch (_) {}
      if (++ticks >= 3) {
        t.cancel();
        _connectWs();
      }
    });
  }

  // ------------------------------------------------------------ control ---

  Future<Map<String, dynamic>?> _rpc(String method, Map<String, dynamic> params) async {
    final r = await _req('POST', '/api/plugins/rpc/twoway/$_id', body: {
      'method': method,
      'params': params,
      'timeout': AppConfig.rpcTimeout.inMilliseconds,
    });
    if (r.statusCode == 504 || r.statusCode == 408 || r.statusCode == 409) {
      throw const AppException('El nodo no respondió. Revisa que el ESP32 esté encendido y con Wi-Fi.');
    }
    _check(r);
    return r.body.isEmpty ? null : jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _saveShared(Map<String, dynamic> values) async {
    final r = await _req('POST', '/api/plugins/telemetry/DEVICE/$_id/attributes/SHARED_SCOPE', body: values);
    _check(r);
  }

  @override
  Future<void> setIrrigation(int zone, bool state, int durationS) async {
    final res = await _rpc('setIrrigation', {'zone': zone, 'state': state, 'duration_s': durationS});
    if (res != null && res['ok'] == false) throw const AppException('El nodo rechazó el comando');
    // Refleja el cambio de inmediato; la telemetría lo confirmará.
    _emit({'valve$zone': (DateTime.now().millisecondsSinceEpoch, '$state')});
  }

  @override
  Future<bool> setMode(String mode) async {
    // El atributo compartido hace que el modo se conserve aunque el ESP32 se
    // reinicie (lo pide al conectarse) y se aplica en cuanto lo recibe.
    await _saveShared({'mode': mode});
    try {
      await _rpc('setMode', {'mode': mode});
      return true;
    } on AppException {
      return false;
    }
  }

  @override
  Future<void> setThreshold(int pct) => _saveShared({'soil_threshold_pct': pct});

  // ------------------------------------------------------------ alarmas ---

  @override
  Future<List<AlarmItem>> alarms() async {
    final j = await _getJson('/api/alarm/DEVICE/$_id', {
      'pageSize': '50',
      'page': '0',
      'sortProperty': 'createdTime',
      'sortOrder': 'DESC',
    }) as Map<String, dynamic>;
    return [
      for (final a in (j['data'] as List).cast<Map<String, dynamic>>())
        AlarmItem(
          id: a['id']['id'] as String,
          type: a['type'] as String,
          severity: a['severity'] as String? ?? 'MAJOR',
          state: AlarmItem.parseStatus(a['status'] as String? ?? 'ACTIVE_UNACK'),
          createdAt: DateTime.fromMillisecondsSinceEpoch((a['createdTime'] as num).toInt()),
          clearedAt: (a['clearTs'] as num? ?? 0) > 0
              ? DateTime.fromMillisecondsSinceEpoch((a['clearTs'] as num).toInt())
              : null,
          detail: a['details'] is Map ? jsonEncode(a['details']) : null,
        )
    ];
  }

  @override
  Future<void> ackAlarm(String id) async => _check(await _req('POST', '/api/alarm/$id/ack'));

  // ------------------------------------------------------------ historial ---

  Future<Map<String, dynamic>> _series(List<String> keys, Duration range,
      {String agg = 'NONE', int? interval, int limit = 1000, String order = 'ASC'}) async {
    final end = DateTime.now().millisecondsSinceEpoch;
    return await _getJson('/api/plugins/telemetry/DEVICE/$_id/values/timeseries', {
      'keys': keys.join(','),
      'startTs': '${end - range.inMilliseconds}',
      'endTs': '$end',
      'agg': agg,
      'interval': '${interval ?? 0}',
      'limit': '$limit',
      'orderBy': order,
    }) as Map<String, dynamic>;
  }

  @override
  Future<List<SoilPoint>> soilHistory(Duration range) async {
    // Promedios por intervalo para no traer miles de lecturas.
    final interval = (range.inMilliseconds / 48).round();
    final j = await _series(['soil1', 'soil2'], range, agg: 'AVG', interval: interval);
    final byTs = <int, List<double?>>{};
    for (final (i, k) in [(0, 'soil1'), (1, 'soil2')]) {
      for (final p in (j[k] as List? ?? const [])) {
        final ts = (p['ts'] as num).toInt();
        byTs.putIfAbsent(ts, () => [null, null])[i] = double.tryParse(p['value'].toString());
      }
    }
    final keys = byTs.keys.toList()..sort();
    return [for (final t in keys) SoilPoint(DateTime.fromMillisecondsSinceEpoch(t), byTs[t]![0], byTs[t]![1])];
  }

  @override
  Future<List<IrrigationEvent>> irrigationEvents(Duration range) async {
    final j = await _series(['valve1', 'valve2'], range, limit: 5000);
    final out = <IrrigationEvent>[];
    for (final zone in [1, 2]) {
      final series = [
        for (final p in (j['valve$zone'] as List? ?? const []))
          ((p['ts'] as num).toInt(), p['value'].toString() == 'true')
      ];
      out.addAll(deriveIrrigationEvents(zone, series));
    }
    out.sort((a, b) => b.start.compareTo(a.start));
    return out;
  }

  @override
  Future<List<RfidAccess>> rfidAccesses({int limit = 20}) async {
    final j = await _series(['rfid_uid', 'rfid_ok', 'zone'], const Duration(days: 30),
        limit: limit, order: 'DESC');
    Map<int, String> idx(String k) => {
          for (final p in (j[k] as List? ?? const [])) (p['ts'] as num).toInt(): p['value'].toString()
        };
    final uid = idx('rfid_uid'), ok = idx('rfid_ok'), zone = idx('zone');
    final ts = uid.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final t in ts)
        RfidAccess(
          ts: DateTime.fromMillisecondsSinceEpoch(t),
          uid: uid[t]!,
          authorized: ok[t] == 'true',
          zone: int.tryParse(zone[t] ?? ''),
        )
    ];
  }

  // ------------------------------------------------------------ tarjetas ---

  @override
  Future<List<RfidCard>> rfidCards() async {
    final attrs = await _getJson('/api/plugins/telemetry/DEVICE/$_id/values/attributes/SHARED_SCOPE',
        {'keys': 'rfid_cards'}) as List;
    if (attrs.isEmpty) return [];
    var v = attrs.first['value'];
    if (v is String) v = jsonDecode(v);
    return [for (final c in (v as List)) RfidCard.fromJson(c as Map<String, dynamic>)];
  }

  @override
  Future<void> saveRfidCards(List<RfidCard> cards) =>
      _saveShared({'rfid_cards': [for (final c in cards) c.toJson()]});

  @override
  Future<void> close() async {
    _closed = true;
    _pollTimer?.cancel();
    await _ws?.sink.close();
    await _telemetry?.close();
    _client.close();
  }
}
