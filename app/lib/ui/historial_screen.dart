import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'widgets.dart';

class HistorialScreen extends ConsumerStatefulWidget {
  const HistorialScreen({super.key});
  @override
  ConsumerState<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends ConsumerState<HistorialScreen> {
  HistoryRange _range = HistoryRange.day;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(soilHistoryProvider(_range));
    final events = ref.watch(irrigationEventsProvider(_range));
    final access = ref.watch(rfidAccessProvider);
    final threshold = ref.watch(telemetryProvider).value?.threshold ?? 50;

    return Scaffold(
      appBar: header('Historial', 'Telemetría, riegos y accesos RFID'),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(soilHistoryProvider(_range));
          ref.invalidate(irrigationEventsProvider(_range));
          ref.invalidate(rfidAccessProvider);
        },
        child: ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
          SegmentedButton<HistoryRange>(
            showSelectedIcon: false,
            segments: [for (final r in HistoryRange.values) ButtonSegment(value: r, label: Text(r.label))],
            selected: {_range},
            onSelectionChanged: (s) => setState(() => _range = s.first),
          ),
          const SizedBox(height: AppSpace.s3),
          SectionCard(
            title: 'Humedad de suelo (%)',
            child: SizedBox(
              height: 200,
              child: history.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorView(e, onRetry: () => ref.invalidate(soilHistoryProvider(_range))),
                data: (pts) => pts.isEmpty
                    ? const Center(child: Text('Sin lecturas en este periodo', style: TextStyle(color: AppColors.texto2)))
                    : _SoilChart(points: pts, threshold: threshold, range: _range),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.s3),
          SectionCard(
            title: 'Accesos RFID',
            child: access.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorView(e, onRetry: () => ref.invalidate(rfidAccessProvider)),
              data: (list) => DividedList(
                empty: 'Aún no se ha leído ninguna tarjeta',
                children: [for (final a in list.take(8)) _AccessRow(a)],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.s3),
          SectionCard(
            title: 'Eventos de riego',
            child: events.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorView(e, onRetry: () => ref.invalidate(irrigationEventsProvider(_range))),
              data: (list) => DividedList(
                empty: 'Sin riegos en este periodo',
                children: [
                  for (final e in list.take(10))
                    ListRow(
                      leading: const StatusIcon(Icons.water_drop_rounded),
                      title: 'Zona ${e.zone} · ${e.end == null ? 'regando ahora' : fmtDuration(e.duration!)}',
                      subtitle: 'Inicio ${shortDate(e.start)}${e.end == null ? '' : ' · fin ${DateFormat('HH:mm').format(e.end!)}'}',
                    ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AccessRow extends ConsumerWidget {
  final RfidAccess a;
  const _AccessRow(this.a);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(cardNameProvider(a.uid));
    return ListRow(
      leading: StatusIcon(a.authorized ? Icons.check_rounded : Icons.close_rounded,
          kind: a.authorized ? ChipKind.ok : ChipKind.error),
      title: name == null ? a.uid : '${a.uid} · $name',
      subtitle: a.authorized ? 'Riego manual · Zona ${a.zone ?? 1}' : 'Tarjeta denegada',
      trailing: Text(shortDate(a.ts), style: const TextStyle(fontSize: 12, color: AppColors.texto2)),
    );
  }
}

class _SoilChart extends StatelessWidget {
  final List<SoilPoint> points;
  final int threshold;
  final HistoryRange range;
  const _SoilChart({required this.points, required this.threshold, required this.range});

  @override
  Widget build(BuildContext context) {
    final t0 = points.first.ts.millisecondsSinceEpoch.toDouble();
    double x(SoilPoint p) => (p.ts.millisecondsSinceEpoch - t0) / 60000; // minutos
    LineChartBarData line(List<FlSpot> spots, Color c) => LineChartBarData(
        spots: spots, color: c, barWidth: 2.5, isCurved: true, preventCurveOverShooting: true,
        dotData: const FlDotData(show: false));
    final fmt = range == HistoryRange.week ? DateFormat('d/M') : DateFormat('HH:mm');

    return Column(children: [
      Expanded(
        child: LineChart(LineChartData(
          minY: 0,
          maxY: 100,
          gridData: const FlGridData(drawVerticalLine: false, horizontalInterval: 25),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            line([for (final p in points) if (p.soil1 != null) FlSpot(x(p), p.soil1!)], AppColors.azul),
            line([for (final p in points) if (p.soil2 != null) FlSpot(x(p), p.soil2!)], AppColors.verde),
          ],
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(
              y: threshold.toDouble(),
              color: AppColors.rojo,
              strokeWidth: 1.5,
              dashArray: [5, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: const TextStyle(fontSize: 10, color: AppColors.rojo),
                labelResolver: (_) => 'umbral $threshold %',
              ),
            ),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 25,
                getTitlesWidget: (v, _) =>
                    Text('${v.round()}', style: const TextStyle(fontSize: 10, color: AppColors.texto2)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (x(points.last) / 4).clamp(1, double.infinity),
                getTitlesWidget: (v, meta) => v == meta.max
                    ? const SizedBox.shrink()
                    : Text(fmt.format(DateTime.fromMillisecondsSinceEpoch((t0 + v * 60000).round())),
                        style: const TextStyle(fontSize: 10, color: AppColors.texto2)),
              ),
            ),
          ),
        )),
      ),
      const SizedBox(height: 6),
      const Row(children: [
        _Legend(AppColors.azul, 'Zona 1'),
        SizedBox(width: 16),
        _Legend(AppColors.verde, 'Zona 2'),
      ]),
    ]);
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend(this.color, this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: AppColors.texto2)),
      ]);
}
