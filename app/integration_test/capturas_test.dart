// Recorre la app en modo demo y guarda capturas de cada pantalla.
//   flutter test integration_test/capturas_test.dart -d windows --dart-define=OUT=capturas
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huerta_manzanos/main.dart';
import 'package:huerta_manzanos/state/providers.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'capturas');
final _key = GlobalKey();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> wait(WidgetTester t, [int ms = 600]) async {
    await t.runAsync(() => Future.delayed(Duration(milliseconds: ms)));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    await wait(t, 300);
    final b = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await t.runAsync(() async {
      final img = await b.toImage(pixelRatio: 2);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    });
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  }

  Future<void> tap(WidgetTester t, Finder f, {int ms = 600}) async {
    await t.tap(f.first);
    await wait(t, ms);
  }

  testWidgets('capturas modo demo', (t) async {
    await initializeDateFormatting('es_MX');
    t.view.physicalSize = const Size(780, 1688);
    t.view.devicePixelRatio = 2;

    await t.pumpWidget(RepaintBoundary(key: _key, child: const ProviderScope(child: HuertaApp())));
    await wait(t, 1500);
    await shot(t, '01_login');

    await tap(t, find.text('Entrar'));
    await shot(t, '02_login_validacion');

    await tap(t, find.text('Entrar en modo demo (sin el nodo)'), ms: 2500);
    await shot(t, '03_panel');

    await tap(t, find.text('Zona 2'), ms: 1200);
    await shot(t, '04_detalle_zona');
    await tap(t, find.byType(BackButton));

    await tap(t, find.text('Riego'));
    await shot(t, '05_control_riego');
    await tap(t, find.text('Regar'));
    await shot(t, '06_confirmar_riego');
    await tap(t, find.widgetWithText(FilledButton, 'Regar').last, ms: 1500);
    await shot(t, '07_riego_enviado');

    await tap(t, find.text('Alarmas'), ms: 1200);
    await tap(t, find.text('Todas'), ms: 800);
    await shot(t, '08_alarmas');

    await tap(t, find.text('Historial'), ms: 2000);
    await shot(t, '09_historial');

    await tap(t, find.text('Más'));
    await shot(t, '10_mas');
    await tap(t, find.text('Tarjetas RFID'), ms: 1000);
    await shot(t, '11_tarjetas_rfid');
    await tap(t, find.text('Registrar tarjeta'), ms: 1000);
    await t.enterText(find.byType(TextFormField).first, 'Reyes Zubía');
    await tap(t, find.text('Leer tarjeta en el nodo'), ms: 2500);
    await shot(t, '12_registrar_tarjeta');

    final c = ProviderScope.containerOf(t.element(find.byType(HuertaApp)));
    await c.read(repoProvider).close();
    t.view.reset();
  });
}
