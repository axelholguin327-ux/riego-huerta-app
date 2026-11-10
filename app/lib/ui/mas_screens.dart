import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../data/demo_repository.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'widgets.dart';

// ------------------------------------------------------------------ Más ---

class MasScreen extends ConsumerWidget {
  const MasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repoProvider);
    final initials = repo.userName.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    return Scaffold(
      appBar: header('Más opciones', 'Cuenta y configuración'),
      body: ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
        SectionCard(
          child: Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.verdeClaro,
              child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.verde)),
            ),
            const SizedBox(width: AppSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(repo.userName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(repo.userEmail, style: const TextStyle(fontSize: 12, color: AppColors.texto2)),
              ]),
            ),
            if (repo.isDemo) const StatusChip('Demo', kind: ChipKind.info),
          ]),
        ),
        const SizedBox(height: AppSpace.s3),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
          child: DividedList(children: [
            ListRow(
              leading: const StatusIcon(Icons.contactless_rounded, kind: ChipKind.ok),
              title: 'Tarjetas RFID',
              subtitle: 'Registrar y administrar encargados',
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.texto2),
              onTap: () => context.go('/mas/rfid'),
            ),
            ListRow(
              leading: const StatusIcon(Icons.memory_rounded),
              title: 'Dispositivo',
              subtitle: AppConfig.deviceName,
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.texto2),
              onTap: () => context.go('/mas/dispositivo'),
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.s3),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
          child: ListRow(
            leading: const StatusIcon(Icons.logout_rounded, kind: ChipKind.error),
            title: 'Cerrar sesión',
            onTap: () async {
              final yes = await confirm(context,
                  title: '¿Cerrar sesión?',
                  text: 'Tendrás que volver a ingresar tu correo y contraseña.',
                  icon: Icons.logout_rounded,
                  ok: 'Cerrar sesión',
                  danger: true);
              if (yes) await ref.read(authProvider.notifier).logout();
            },
          ),
        ),
      ]),
    );
  }
}

// --------------------------------------------------------- Tarjetas RFID ---

class RfidScreen extends ConsumerWidget {
  const RfidScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(rfidCardsProvider);
    return Scaffold(
      appBar: header('Tarjetas RFID', 'Encargados autorizados para riego manual', back: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/mas/rfid/nueva'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Registrar tarjeta'),
      ),
      body: cards.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: ErrorView(e, onRetry: () => ref.invalidate(rfidCardsProvider))),
        data: (list) => ListView(padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s4, AppSpace.s4, 96), children: [
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
            child: DividedList(
              empty: 'No hay tarjetas registradas',
              children: [
                for (final c in list)
                  ListRow(
                    leading: StatusIcon(Icons.badge_rounded, kind: c.active ? ChipKind.ok : ChipKind.error),
                    title: c.name,
                    subtitle: 'UID ${c.uid} · Zona${c.zones.length > 1 ? 's' : ''} ${c.zones.join(' y ')}',
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Opciones',
                      child: c.active
                          ? const StatusChip('Activa', kind: ChipKind.ok)
                          : const StatusChip('Inactiva', kind: ChipKind.error),
                      onSelected: (v) async {
                        try {
                          final n = ref.read(rfidCardsProvider.notifier);
                          v == 'toggle' ? await n.toggle(c.uid) : await n.remove(c.uid);
                          if (context.mounted) toast(context, 'Cambios guardados en el nodo');
                        } catch (e) {
                          if (context.mounted) toast(context, '$e', icon: Icons.error_rounded, error: true);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'toggle', child: Text(c.active ? 'Desactivar' : 'Activar')),
                        const PopupMenuItem(value: 'remove', child: Text('Eliminar')),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.s3),
          const Text(
            'La lista se guarda en el atributo compartido "rfid_cards" del nodo, '
            'así el ESP32 valida las tarjetas aunque no haya Internet.',
            style: TextStyle(fontSize: 12, color: AppColors.texto2),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------ Registrar tarjeta ---

class RfidNuevaScreen extends ConsumerStatefulWidget {
  const RfidNuevaScreen({super.key});
  @override
  ConsumerState<RfidNuevaScreen> createState() => _RfidNuevaScreenState();
}

class _RfidNuevaScreenState extends ConsumerState<RfidNuevaScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _uid = TextEditingController();
  final _zones = <int>{1};
  bool _reading = false, _saving = false;
  StreamSubscription<Telemetry>? _sub;
  Timer? _timeout;

  /// Espera a que se acerque una tarjeta al lector del nodo y toma su UID de
  /// la telemetría (`rfid_uid`).
  void _read() {
    final repo = ref.read(repoProvider);
    final since = DateTime.now();
    setState(() => _reading = true);
    _sub = repo.telemetry().listen((t) {
      if (t.rfidAt != null && t.rfidAt!.isAfter(since.subtract(const Duration(seconds: 2))) && t.rfidUid != null) {
        _uid.text = t.rfidUid!;
        _stopReading();
        if (mounted) toast(context, 'Tarjeta leída: ${t.rfidUid}', icon: Icons.nfc_rounded);
      }
    });
    _timeout = Timer(const Duration(seconds: 30), () {
      _stopReading();
      if (mounted) toast(context, 'No se detectó ninguna tarjeta en 30 s', icon: Icons.timer_off_rounded, error: true);
    });
    if (repo is DemoRepository) {
      // En demo se simula una tarjeta nueva después de un momento.
      final uid = List.generate(4, (_) => Random().nextInt(256).toRadixString(16).padLeft(2, '0')).join().toUpperCase();
      Future.delayed(const Duration(milliseconds: 1500), () => repo.simulateCard(uid));
    }
  }

  void _stopReading() {
    _sub?.cancel();
    _timeout?.cancel();
    if (mounted) setState(() => _reading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_zones.isEmpty) {
      toast(context, 'Selecciona al menos una zona', icon: Icons.error_rounded, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(rfidCardsProvider.notifier).add(RfidCard(
            uid: _uid.text.trim().toUpperCase(),
            name: _name.text.trim(),
            zones: (_zones.toList()..sort()),
          ));
      if (!mounted) return;
      toast(context, 'Tarjeta registrada correctamente', icon: Icons.how_to_reg_rounded);
      context.go('/mas/rfid');
    } catch (e) {
      if (mounted) toast(context, '$e', icon: Icons.error_rounded, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    _name.dispose();
    _uid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: header('Registrar tarjeta', 'Nuevo encargado autorizado', back: true),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
          SectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre del encargado', prefixIcon: Icon(Icons.person_rounded)),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe el nombre del encargado' : null,
              ),
              const SizedBox(height: AppSpace.s3),
              TextFormField(
                controller: _uid,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'UID de la tarjeta', hintText: 'Léela en el nodo o escríbela', prefixIcon: Icon(Icons.contactless_rounded)),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Lee la tarjeta en el nodo para obtener su UID';
                  if (!RegExp(r'^[0-9A-Fa-f]{8,20}$').hasMatch(t) && !t.toUpperCase().startsWith('SIM')) {
                    return 'El UID debe ser hexadecimal (ej. 5C8E21A7)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpace.s2),
              OutlinedButton.icon(
                onPressed: _reading ? _stopReading : _read,
                icon: _reading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.nfc_rounded),
                label: Text(_reading ? 'Acerca la tarjeta al lector… (cancelar)' : 'Leer tarjeta en el nodo'),
              ),
              const SizedBox(height: AppSpace.s4),
              const Text('Zonas permitidas', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              for (final z in [1, 2])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('Zona $z'),
                  value: _zones.contains(z),
                  onChanged: (v) => setState(() => v! ? _zones.add(z) : _zones.remove(z)),
                ),
            ]),
          ),
          const SizedBox(height: AppSpace.s3),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Guardando…' : 'Guardar tarjeta'),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ Dispositivo ---

class DispositivoScreen extends ConsumerWidget {
  const DispositivoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dev = ref.watch(deviceProvider);
    final online = ref.watch(nodeOnlineProvider);
    final t = ref.watch(telemetryProvider).value;
    final now = ref.watch(clockProvider).value;
    return Scaffold(
      appBar: header('Dispositivo', 'Estado del nodo ESP32', back: true),
      body: ListView(padding: const EdgeInsets.all(AppSpace.s4), children: [
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
          child: DividedList(children: [
            ListRow(
              leading: StatusIcon(online ? Icons.wifi_rounded : Icons.wifi_off_rounded, kind: online ? ChipKind.ok : ChipKind.error),
              title: online ? 'En línea' : 'Desconectado',
              subtitle: 'Último dato ${timeAgo(t?.updatedAt, now)}',
            ),
            ListRow(
              leading: const StatusIcon(Icons.memory_rounded),
              title: dev.value?.name ?? AppConfig.deviceName,
              subtitle: 'ESP32 DevKit · firmware ${dev.value?.firmware ?? '…'}',
            ),
            const ListRow(
                leading: StatusIcon(Icons.sensors_rounded), title: 'Sensores', subtitle: 'DHT22 · 2× YL-69 · RC522'),
            const ListRow(
                leading: StatusIcon(Icons.plumbing_rounded), title: 'Actuadores', subtitle: '2 electroválvulas · bomba 12 V'),
            const ListRow(
                leading: StatusIcon(Icons.cloud_rounded, kind: ChipKind.warn),
                title: 'Plataforma',
                subtitle: 'ThingsBoard Cloud · MQTT'),
          ]),
        ),
      ]),
    );
  }
}
