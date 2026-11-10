import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'widgets.dart';

enum _Filter { activas, todas, resueltas }

class AlarmasScreen extends ConsumerStatefulWidget {
  const AlarmasScreen({super.key});
  @override
  ConsumerState<AlarmasScreen> createState() => _AlarmasScreenState();
}

class _AlarmasScreenState extends ConsumerState<AlarmasScreen> {
  _Filter _filter = _Filter.activas;
  final _busy = <String>{};

  Future<void> _ack(AlarmItem a) async {
    setState(() => _busy.add(a.id));
    try {
      await ref.read(alarmsProvider.notifier).acknowledge(a.id);
      if (mounted) toast(context, 'Alarma reconocida', icon: Icons.task_alt_rounded);
    } catch (e) {
      if (mounted) toast(context, '$e', icon: Icons.error_rounded, error: true);
    }
    if (mounted) setState(() => _busy.remove(a.id));
  }

  @override
  Widget build(BuildContext context) {
    final alarms = ref.watch(alarmsProvider);
    return Scaffold(
      appBar: header('Alarmas', 'Generadas por el Rule Engine'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s4, AppSpace.s4, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_Filter>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Filter.activas, label: Text('Activas')),
                ButtonSegment(value: _Filter.todas, label: Text('Todas')),
                ButtonSegment(value: _Filter.resueltas, label: Text('Resueltas')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
        ),
        Expanded(
          child: alarms.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: ErrorView(e, onRetry: () => ref.invalidate(alarmsProvider))),
            data: (list) {
              final shown = list.where((a) => switch (_filter) {
                    _Filter.activas => a.isActive,
                    _Filter.resueltas => !a.isActive,
                    _Filter.todas => true,
                  }).toList();
              return RefreshIndicator(
                onRefresh: () => ref.read(alarmsProvider.notifier).refresh(),
                child: shown.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 80),
                        Icon(Icons.verified_rounded, size: 48, color: AppColors.verde),
                        SizedBox(height: 8),
                        Center(child: Text('No hay alarmas en esta categoría', style: TextStyle(color: AppColors.texto2))),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpace.s4),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.s3),
                        itemBuilder: (_, i) => _AlarmCard(
                            alarm: shown[i], busy: _busy.contains(shown[i].id), onAck: () => _ack(shown[i])),
                      ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  final AlarmItem alarm;
  final bool busy;
  final VoidCallback onAck;
  const _AlarmCard({required this.alarm, required this.busy, required this.onAck});

  @override
  Widget build(BuildContext context) {
    final a = alarm;
    final sevKind = switch (a.severity) {
      'CRITICAL' => ChipKind.error,
      'MAJOR' => ChipKind.warn,
      _ => ChipKind.info,
    };
    final status = switch (a.state) {
      AlarmState.activeUnack => 'Activa · sin reconocer',
      AlarmState.activeAck => 'Activa · reconocida',
      AlarmState.clearedUnack => 'Limpiada automáticamente · sin reconocer',
      AlarmState.clearedAck => 'Resuelta',
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: a.isActive ? AppColors.ambar : AppColors.borde, width: 4)),
        ),
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(a.type, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            if (!a.isAcknowledged)
              busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          foregroundColor: AppColors.ambarTexto,
                          side: const BorderSide(color: AppColors.ambar, width: 1.5)),
                      onPressed: onAck,
                      child: const Text('Reconocer'),
                    )
            else
              const StatusChip('Reconocida', kind: ChipKind.ok, icon: Icons.check_rounded),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            StatusChip(a.severity[0] + a.severity.substring(1).toLowerCase(), kind: sevKind),
            const Spacer(),
            Text(shortDate(a.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.texto2)),
          ]),
          const SizedBox(height: 6),
          Text(status, style: const TextStyle(fontSize: 12, color: AppColors.texto2)),
          if (a.clearedAt != null)
            Text('Limpiada ${shortDate(a.clearedAt!)}', style: const TextStyle(fontSize: 12, color: AppColors.texto2)),
        ]),
      ),
    );
  }
}
