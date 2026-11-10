import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huerta_manzanos/config.dart';
import 'package:huerta_manzanos/data/models.dart';
import 'package:huerta_manzanos/data/thingsboard_repository.dart';
import 'package:huerta_manzanos/main.dart';
import 'package:huerta_manzanos/state/providers.dart';

/// Servidor falso con las mismas respuestas (formato) que ThingsBoard Cloud.
MockClient fakeThingsBoard({List<http.Request>? log}) => MockClient((req) async {
      log?.add(req);
      final p = req.url.path;
      http.Response ok(Object body) => http.Response(jsonEncode(body), 200);
      if (p == '/api/auth/login') {
        final b = jsonDecode(req.body);
        return b['password'] == 'bien'
            ? ok({'token': 'jwt', 'refreshToken': 'r'})
            : http.Response('{"message":"Authentication failed"}', 401);
      }
      if (p == '/api/auth/user') {
        return ok({'authority': 'CUSTOMER_USER', 'customerId': {'id': 'c1'}, 'email': 'enc@huerta.mx', 'firstName': 'Ana', 'lastName': 'López'});
      }
      if (p == '/api/customer/c1/devices') {
        return ok({'data': [
          {'id': {'id': 'd1'}, 'name': AppConfig.deviceName}
        ]});
      }
      if (p == '/api/alarm/DEVICE/d1') {
        return ok({'data': [
          {'id': {'id': 'a1'}, 'type': 'Humedad de suelo baja', 'severity': 'MAJOR', 'status': 'ACTIVE_UNACK',
            'createdTime': 1791502869306, 'clearTs': 0},
          {'id': {'id': 'a2'}, 'type': 'Humedad de suelo baja', 'severity': 'MAJOR', 'status': 'CLEARED_ACK',
            'createdTime': 1791402869306, 'clearTs': 1791412869306},
        ]});
      }
      if (p == '/api/plugins/telemetry/DEVICE/d1/values/timeseries') {
        final keys = req.url.queryParameters['keys']!;
        if (keys == 'soil1,soil2') {
          return ok({
            'soil1': [{'ts': 1000, 'value': '40.5'}, {'ts': 2000, 'value': '38.0'}],
            'soil2': [{'ts': 1000, 'value': '70.0'}],
          });
        }
        if (keys == 'valve1,valve2') {
          return ok({
            'valve1': [{'ts': 1000, 'value': 'false'}, {'ts': 2000, 'value': 'true'}, {'ts': 62000, 'value': 'false'}],
            'valve2': [{'ts': 5000, 'value': 'true'}],
          });
        }
        return ok({});
      }
      if (p == '/api/plugins/rpc/twoway/d1') {
        final b = jsonDecode(req.body);
        if (b['params']['zone'] == 2) return http.Response('', 504); // nodo sin respuesta
        return ok({'ok': true, 'zone': b['params']['zone'], 'state': b['params']['state']});
      }
      if (p == '/api/plugins/telemetry/DEVICE/d1/attributes/SHARED_SCOPE') return http.Response('', 200);
      if (p == '/api/plugins/telemetry/DEVICE/d1/values/attributes/SHARED_SCOPE') {
        return ok([
          {'key': 'rfid_cards', 'value': [
            {'uid': 'sim00001', 'name': 'Axel', 'zones': [1, 2]}
          ]}
        ]);
      }
      return http.Response('no encontrado: $p', 404);
    });

void main() {
  group('Modelos', () {
    test('merge de telemetría con los nombres del firmware', () {
      final t = Telemetry.empty.merge({
        'temp_c': (1000, '24.6'),
        'soil1': (1000, '51'),
        'soil2': (1000, '100'),
        'valve1': (1000, 'true'),
        'mode': (1000, 'auto'),
        'soil_threshold_pct': (1000, '35'),
      });
      expect(t.tempC, 24.6);
      expect(t.soil(1), 51);
      expect(t.valve(1), isTrue);
      expect(t.valve(2), isFalse);
      expect(t.mode, 'auto');
      expect(t.threshold, 35);
      // Un mensaje parcial solo cambia lo que trae.
      final t2 = t.merge({'soil1': (2000, '49')});
      expect(t2.soil1, 49);
      expect(t2.tempC, 24.6);
      expect(t2.updatedAt, DateTime.fromMillisecondsSinceEpoch(2000));
    });

    test('nodo desconectado si no hay datos recientes', () {
      final t = Telemetry(updatedAt: DateTime(2026, 1, 1, 10));
      expect(t.isOnline(DateTime(2026, 1, 1, 10, 0, 20), AppConfig.offlineAfter), isTrue);
      expect(t.isOnline(DateTime(2026, 1, 1, 10, 5), AppConfig.offlineAfter), isFalse);
    });

    test('eventos de riego a partir de valve1/valve2', () {
      final ev = deriveIrrigationEvents(1, [(0, false), (1000, true), (5000, true), (61000, false), (90000, true)]);
      expect(ev, hasLength(2));
      expect(ev[0].duration, const Duration(seconds: 60));
      expect(ev[1].end, isNull); // sigue regando
    });

    test('tarjeta RFID ida y vuelta en JSON', () {
      final c = RfidCard.fromJson({'uid': 'c0ffee99', 'name': 'Ana', 'zones': [2]});
      expect(c.uid, 'C0FFEE99');
      expect(RfidCard.fromJson(c.toJson()).zones, [2]);
    });
  });

  group('ThingsBoardRepository (servidor falso)', () {
    late ThingsBoardRepository repo;
    final log = <http.Request>[];

    setUp(() async {
      log.clear();
      final client = fakeThingsBoard(log: log);
      final s = await ThingsBoardRepository.login('enc@huerta.mx', 'bien', client: client);
      repo = await ThingsBoardRepository.open(s, onSession: (_) {}, client: client);
    });

    test('login incorrecto da mensaje entendible', () async {
      expect(() => ThingsBoardRepository.login('x@y.mx', 'mal', client: fakeThingsBoard()),
          throwsA(isA<AppException>().having((e) => e.message, 'msg', 'Correo o contraseña incorrectos')));
    });

    test('encuentra el dispositivo del cliente y el nombre del usuario', () {
      expect(repo.userName, 'Ana López');
    });

    test('regar envía el RPC setIrrigation con el formato del firmware', () async {
      await repo.setIrrigation(1, true, 60);
      final rpc = log.last;
      expect(rpc.headers['X-Authorization'], 'Bearer jwt');
      expect(jsonDecode(rpc.body)['method'], 'setIrrigation');
      expect(jsonDecode(rpc.body)['params'], {'zone': 1, 'state': true, 'duration_s': 60});
    });

    test('si el nodo no responde (504) se avisa al usuario', () async {
      expect(() => repo.setIrrigation(2, true, 60),
          throwsA(isA<AppException>().having((e) => e.message, 'msg', contains('no respondió'))));
    });

    test('cambiar modo guarda el atributo compartido y manda setMode', () async {
      await repo.setMode('manual');
      final paths = log.map((r) => r.url.path).toList();
      expect(paths, contains('/api/plugins/telemetry/DEVICE/d1/attributes/SHARED_SCOPE'));
      expect(paths.last, '/api/plugins/rpc/twoway/d1');
    });

    test('alarmas, historial, eventos y tarjetas', () async {
      final alarms = await repo.alarms();
      expect(alarms.first.isActive, isTrue);
      expect(alarms.last.state, AlarmState.clearedAck);
      expect(alarms.last.clearedAt, isNotNull);

      final h = await repo.soilHistory(const Duration(hours: 24));
      expect(h, hasLength(2));
      expect(h.first.soil2, 70.0);
      expect(h.last.soil2, isNull);

      final ev = await repo.irrigationEvents(const Duration(hours: 24));
      expect(ev.where((e) => e.zone == 1).single.duration, const Duration(seconds: 60));

      final cards = await repo.rfidCards();
      expect(cards.single.uid, 'SIM00001');
    });
  });

  group('Interfaz en modo demo', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    testWidgets('login → demo → panel → riego con confirmación', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ProviderScope(child: HuertaApp()));
      await tester.pumpAndSettle();
      expect(find.text('Iniciar sesión'), findsOneWidget);

      // Validación del formulario
      await tester.tap(find.text('Entrar'));
      await tester.pump();
      expect(find.text('Escribe tu correo'), findsOneWidget);

      await tester.tap(find.text('Entrar en modo demo (sin el nodo)'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Humedad de suelo'), findsOneWidget);
      expect(find.text('Zona 1'), findsOneWidget);

      await tester.tap(find.text('Riego'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Modo de operación'), findsOneWidget);

      await tester.tap(find.text('Regar').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('¿Regar Zona 1?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Regar').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('riego iniciado'), findsOneWidget);

      // Cierra el repositorio demo para detener su temporizador.
      final container = ProviderScope.containerOf(tester.element(find.byType(HuertaApp)));
      await container.read(repoProvider).close();
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
