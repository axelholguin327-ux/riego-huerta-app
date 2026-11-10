import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'widgets.dart';

/// Aviso de nodo desconectado (se usa en Panel y Riego).
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(nodeOnlineProvider)) return const SizedBox.shrink();
    final t = ref.watch(telemetryProvider).value;
    final now = ref.watch(clockProvider).value;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s3),
      child: InfoBanner(
        icon: Icons.wifi_off_rounded,
        kind: ChipKind.error,
        title: 'Nodo desconectado',
        text: 'Último dato ${timeAgo(t?.updatedAt, now)}. Revisa que el ESP32 esté encendido y con Wi-Fi.',
      ),
    );
  }
}

class PanelScreen extends ConsumerWidget {
  const PanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tel = ref.watch(telemetryProvider);
    final online = ref.watch(nodeOnlineProvider);
    final alarms = ref.watch(activeAlarmsProvider);
    final now = ref.watch(clockProvider).value;

    return Scaffold(
      appBar: header('Huerta Manzanos', '${online ? '●' : '○'} ${AppConfig.deviceName} · ${online ? 'En línea' : 'Sin conexión'}',
          actions: [
            IconButton(
              tooltip: 'Alarmas',
              onPressed: () => context.go('/alarmas'),
              icon: Badge(
                isLabelVisible: alarms.isNotEmpty,
                label: Text('${alarms.length}'),
                child: const Icon(Icons.notifications_rounded),
              ),
            ),
          ]),
      body: tel.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: ErrorView(e, onRetry: () => ref.invalidate(telemetryProvider))),
        data: (t) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(alarmsProvider);
          },
          child: ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
            const OfflineBanner(),
            Row(children: [
              const Icon(Icons.sync_rounded, size: 16, color: AppColors.texto2),
              const SizedBox(width: 4),
              Text('Actualizado ${timeAgo(t.updatedAt, now)}', style: const TextStyle(color: AppColors.texto2, fontSize: 13)),
            ]),
            const SizedBox(height: AppSpace.s3),
            Row(children: [
              Expanded(child: MetricCard(label: 'Temperatura', value: t.tempC?.toStringAsFixed(1) ?? '--', unit: '°C', caption: 'Ambiente')),
              const SizedBox(width: AppSpace.s3),
              Expanded(child: MetricCard(label: 'Humedad amb.', value: t.humAmb?.round().toString() ?? '--', unit: '%', caption: 'Relativa')),
            ]),
            const SizedBox(height: AppSpace.s3),
            SectionCard(
              title: 'Humedad de suelo',
              child: Column(children: [
                _ZoneRow(zone: 1, t: t),
                const Divider(height: AppSpace.s5, color: AppColors.borde),
                _ZoneRow(zone: 2, t: t),
              ]),
            ),
            const SizedBox(height: AppSpace.s3),
            SectionCard(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Bomba: ${t.pump ? 'encendida' : 'apagada'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Modo ${t.mode == 'auto' ? 'automático' : 'manual'} · umbral ${t.threshold} %',
                        style: const TextStyle(fontSize: 12, color: AppColors.texto2)),
                  ]),
                ),
                Icon(Icons.water_rounded, size: 32, color: t.pump ? AppColors.azul : AppColors.borde),
              ]),
            ),
            if (alarms.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s3),
              InfoBanner(
                icon: Icons.error_rounded,
                title: alarms.length == 1 ? '1 alarma activa' : '${alarms.length} alarmas activas',
                text: alarms.first.type,
                onTap: () => context.go('/alarmas'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  final int zone;
  final Telemetry t;
  const _ZoneRow({required this.zone, required this.t});

  @override
  Widget build(BuildContext context) {
    final soil = t.soil(zone);
    final low = soil != null && soil < t.threshold;
    final color = low ? AppColors.ambar : AppColors.verde;
    return InkWell(
      onTap: () => context.go('/panel/zona/$zone'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Zona $zone', style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(soil == null ? '--' : '$soil %', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: AppSpace.s2),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (soil ?? 0) / 100,
            minHeight: 8,
            color: color,
            backgroundColor: AppColors.borde,
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('Umbral ${t.threshold} %', style: const TextStyle(fontSize: 12, color: AppColors.texto2))),
          t.valve(zone)
              ? const StatusChip('Regando', kind: ChipKind.ok)
              : const StatusChip('Válvula cerrada'),
        ]),
      ]),
    );
  }
}

/// Consulta: detalle de una zona.
class ZoneScreen extends ConsumerWidget {
  final int zone;
  const ZoneScreen({super.key, required this.zone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(telemetryProvider).value ?? Telemetry.empty;
    final events = ref.watch(irrigationEventsProvider(HistoryRange.week));
    final soil = t.soil(zone);
    final low = soil != null && soil < t.threshold;

    return Scaffold(
      appBar: header('Zona $zone', 'Detalle y consulta', back: true),
      body: ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
        SectionCard(
          child: Center(
            child: Column(children: [
              SizedBox(
                width: 150,
                height: 150,
                child: CustomPaint(
                  painter: _RingPainter((soil ?? 0) / 100, low ? AppColors.ambar : AppColors.verde),
                  child: Center(
                    child: Text(soil == null ? '--' : '$soil %',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s2),
              const Text('Humedad de suelo actual', style: TextStyle(fontSize: 12, color: AppColors.texto2)),
              const SizedBox(height: AppSpace.s3),
              low
                  ? const StatusChip('Por debajo del umbral', kind: ChipKind.warn)
                  : const StatusChip('Humedad adecuada', kind: ChipKind.ok),
            ]),
          ),
        ),
        const SizedBox(height: AppSpace.s3),
        Row(children: [
          Expanded(child: MetricCard(label: 'Umbral de riego', value: '${t.threshold}', unit: '%', caption: 'Atributo compartido')),
          const SizedBox(width: AppSpace.s3),
          Expanded(
              child: MetricCard(
                  label: 'Válvula', value: t.valve(zone) ? 'Abierta' : 'Cerrada', unit: '', caption: 'Electroválvula $zone')),
        ]),
        const SizedBox(height: AppSpace.s3),
        SectionCard(
          title: 'Últimos riegos (7 días)',
          child: events.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorView(e, onRetry: () => ref.invalidate(irrigationEventsProvider)),
            data: (list) => DividedList(
              empty: 'Sin riegos registrados en esta zona',
              children: [
                for (final e in list.where((e) => e.zone == zone).take(6))
                  ListRow(
                    leading: const StatusIcon(Icons.water_drop_rounded),
                    title: e.end == null ? 'Regando ahora' : 'Riego de ${fmtDuration(e.duration!)}',
                    subtitle: 'Inicio ${shortDate(e.start)}',
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.s3),
        FilledButton.icon(
          onPressed: () => context.go('/riego'),
          icon: const Icon(Icons.water_drop_rounded),
          label: const Text('Ir a control de riego'),
        ),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  _RingPainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, 2 * pi, false, p..color = AppColors.borde);
    canvas.drawArc(r, -pi / 2, 2 * pi * value.clamp(0, 1), false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}
