import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'panel_screen.dart';
import 'widgets.dart';

/// Acción principal: control de riego (RPC al ESP32 y atributos compartidos).
class RiegoScreen extends ConsumerStatefulWidget {
  const RiegoScreen({super.key});
  @override
  ConsumerState<RiegoScreen> createState() => _RiegoScreenState();
}

class _RiegoScreenState extends ConsumerState<RiegoScreen> {
  int _duration = 60;
  double? _threshold; // valor mientras se arrastra el slider
  final _busyZone = <int>{};
  bool _busyMode = false;

  Future<void> _run(Future<void> Function() action, {required String ok, IconData icon = Icons.check_circle_rounded}) async {
    try {
      await action();
      if (mounted) toast(context, ok, icon: icon);
    } catch (e) {
      if (mounted) toast(context, '$e', icon: Icons.error_rounded, error: true);
    }
  }

  Future<void> _irrigate(int zone) async {
    final yes = await confirm(context,
        title: '¿Regar Zona $zone?',
        text: 'Se abrirá la electroválvula de la zona $zone y se encenderá la bomba durante $_duration s.',
        icon: Icons.water_drop_rounded,
        ok: 'Regar');
    if (!yes) return;
    setState(() => _busyZone.add(zone));
    await _run(() => ref.read(repoProvider).setIrrigation(zone, true, _duration),
        ok: 'Zona $zone: riego iniciado por $_duration s', icon: Icons.water_drop_rounded);
    if (mounted) setState(() => _busyZone.remove(zone));
  }

  Future<void> _stop(int zone) async {
    setState(() => _busyZone.add(zone));
    await _run(() => ref.read(repoProvider).setIrrigation(zone, false, 1),
        ok: 'Zona $zone: riego detenido', icon: Icons.stop_circle_rounded);
    if (mounted) setState(() => _busyZone.remove(zone));
  }

  Future<void> _setMode(String mode) async {
    final label = mode == 'auto' ? 'automático' : 'manual';
    setState(() => _busyMode = true);
    try {
      final confirmed = await ref.read(repoProvider).setMode(mode);
      if (mounted) {
        toast(context,
            confirmed ? 'Modo cambiado a $label' : 'Modo guardado como $label; se aplicará cuando el nodo se conecte',
            icon: Icons.sync_alt_rounded);
      }
    } catch (e) {
      if (mounted) toast(context, '$e', icon: Icons.error_rounded, error: true);
    }
    if (mounted) setState(() => _busyMode = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(telemetryProvider).value ?? Telemetry.empty;
    final online = ref.watch(nodeOnlineProvider);
    final th = _threshold ?? t.threshold.toDouble();

    return Scaffold(
      appBar: header('Control de riego', 'Comandos enviados al ESP32 por RPC'),
      body: ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
        const OfflineBanner(),
        SectionCard(
          title: 'Modo de operación',
          trailing: _busyMode ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'auto', label: Text('Automático'), icon: Icon(Icons.autorenew_rounded)),
                ButtonSegment(value: 'manual', label: Text('Manual'), icon: Icon(Icons.touch_app_rounded)),
              ],
              selected: {t.mode},
              onSelectionChanged: _busyMode ? null : (s) => _setMode(s.first),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.s3),
        SectionCard(
          title: 'Umbral de riego',
          trailing: Text('${th.round()} %',
              style: const TextStyle(color: AppColors.verde, fontSize: 18, fontWeight: FontWeight.w700)),
          child: Column(children: [
            Slider(
              min: 10,
              max: 90,
              divisions: 80,
              value: th.clamp(10, 90),
              label: '${th.round()} %',
              onChanged: (v) => setState(() => _threshold = v),
              onChangeEnd: (v) async {
                await _run(() => ref.read(repoProvider).setThreshold(v.round()),
                    ok: 'Umbral actualizado a ${v.round()} %', icon: Icons.tune_rounded);
                if (mounted) setState(() => _threshold = null);
              },
            ),
            const Text('En modo automático la zona se riega cuando su humedad baja de este valor',
                style: TextStyle(fontSize: 12, color: AppColors.texto2)),
          ]),
        ),
        const SizedBox(height: AppSpace.s3),
        SectionCard(
          title: 'Duración del riego manual',
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 30, label: Text('30 s')),
              ButtonSegment(value: 60, label: Text('60 s')),
              ButtonSegment(value: 120, label: Text('120 s')),
              ButtonSegment(value: 300, label: Text('5 min')),
            ],
            selected: {_duration},
            onSelectionChanged: (s) => setState(() => _duration = s.first),
          ),
        ),
        for (final zone in [1, 2]) ...[
          const SizedBox(height: AppSpace.s3),
          SectionCard(
            title: 'Zona $zone · ${t.soil(zone) ?? '--'} %',
            trailing: _busyZone.contains(zone)
                ? const StatusChip('Enviando…', kind: ChipKind.info, icon: Icons.send_rounded)
                : t.valve(zone)
                    ? const StatusChip('Regando', kind: ChipKind.ok)
                    : const StatusChip('Válvula cerrada'),
            child: Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: online && !_busyZone.contains(zone) ? () => _irrigate(zone) : null,
                  child: const Text('Regar'),
                ),
              ),
              const SizedBox(width: AppSpace.s2),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.rojo, side: const BorderSide(color: AppColors.rojo, width: 1.5)),
                  onPressed: online && !_busyZone.contains(zone) ? () => _stop(zone) : null,
                  child: const Text('Detener'),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: AppSpace.s3),
        Text(
          'Bomba ${t.pump ? 'encendida' : 'apagada'} · se enciende sola cuando alguna válvula está abierta',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.texto2),
        ),
      ]),
    );
  }
}
