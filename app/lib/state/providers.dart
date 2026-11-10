// Capa de lógica y estado (Riverpod). Las pantallas solo leen estos
// providers y llaman a sus métodos; no hablan directo con ThingsBoard.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../data/demo_repository.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/thingsboard_repository.dart';

// ------------------------------------------------------------------ sesión ---

const _storage = FlutterSecureStorage();
const _sessionKey = 'tb_session';

/// Repositorio activo: null = sin sesión.
class AuthController extends AsyncNotifier<HuertaRepository?> {
  @override
  Future<HuertaRepository?> build() async {
    // Restaura la sesión guardada (token cifrado en el dispositivo).
    try {
      final saved = await _storage.read(key: _sessionKey);
      if (saved == null) return null;
      final j = jsonDecode(saved) as Map<String, dynamic>;
      return await ThingsBoardRepository.open(
        TbSession(j['token'] as String, j['refreshToken'] as String),
        onSession: _save,
      );
    } catch (_) {
      try {
        await _storage.delete(key: _sessionKey);
      } catch (_) {}
      return null;
    }
  }

  Future<void> _save(TbSession s) =>
      _storage.write(key: _sessionKey, value: jsonEncode({'token': s.token, 'refreshToken': s.refreshToken}));

  /// Inicia sesión con un usuario de ThingsBoard. Lanza [AppException] si falla.
  Future<void> login(String email, String password) async {
    final session = await ThingsBoardRepository.login(email, password);
    final repo = await ThingsBoardRepository.open(session, onSession: _save);
    await _save(session);
    state = AsyncData(repo);
  }

  void demo() => state = AsyncData(DemoRepository());

  Future<void> logout() async {
    await state.value?.close();
    await _storage.delete(key: _sessionKey);
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthController, HuertaRepository?>(AuthController.new);

/// Repositorio de la sesión actual (solo se usa en pantallas con sesión).
final repoProvider = Provider<HuertaRepository>((ref) {
  final repo = ref.watch(authProvider).value;
  if (repo == null) throw StateError('Sin sesión');
  return repo;
});

// ------------------------------------------------------------- telemetría ---

final telemetryProvider = StreamProvider<Telemetry>((ref) => ref.watch(repoProvider).telemetry());

/// Reloj que avanza cada 5 s para "hace X s" y para detectar el nodo
/// desconectado.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 5), (_) => DateTime.now());
});

final nodeOnlineProvider = Provider<bool>((ref) {
  final t = ref.watch(telemetryProvider).value;
  final now = ref.watch(clockProvider).value ?? DateTime.now();
  if (ref.watch(repoProvider).isDemo) return true;
  return t != null && t.isOnline(now, AppConfig.offlineAfter);
});

final deviceProvider = FutureProvider<DeviceInfo>((ref) => ref.watch(repoProvider).device());

// --------------------------------------------------------------- alarmas ---

class AlarmsController extends AsyncNotifier<List<AlarmItem>> {
  Timer? _timer;

  @override
  Future<List<AlarmItem>> build() {
    final repo = ref.watch(repoProvider);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    ref.onDispose(() => _timer?.cancel());
    return repo.alarms();
  }

  Future<void> refresh() async {
    final repo = ref.read(repoProvider);
    state = await AsyncValue.guard(repo.alarms);
  }

  Future<void> acknowledge(String id) async {
    await ref.read(repoProvider).ackAlarm(id);
    await refresh();
  }
}

final alarmsProvider = AsyncNotifierProvider<AlarmsController, List<AlarmItem>>(AlarmsController.new);

final activeAlarmsProvider = Provider<List<AlarmItem>>(
    (ref) => (ref.watch(alarmsProvider).value ?? const []).where((a) => a.isActive).toList());

// ------------------------------------------------------------- historial ---

enum HistoryRange {
  hour('1 h', Duration(hours: 1)),
  day('24 h', Duration(hours: 24)),
  week('7 d', Duration(days: 7));

  const HistoryRange(this.label, this.duration);
  final String label;
  final Duration duration;
}

final soilHistoryProvider = FutureProvider.family<List<SoilPoint>, HistoryRange>(
    (ref, r) => ref.watch(repoProvider).soilHistory(r.duration));

final irrigationEventsProvider = FutureProvider.family<List<IrrigationEvent>, HistoryRange>(
    (ref, r) => ref.watch(repoProvider).irrigationEvents(r.duration));

final rfidAccessProvider = FutureProvider<List<RfidAccess>>((ref) => ref.watch(repoProvider).rfidAccesses());

// --------------------------------------------------------------- tarjetas ---

class RfidCardsController extends AsyncNotifier<List<RfidCard>> {
  @override
  Future<List<RfidCard>> build() => ref.watch(repoProvider).rfidCards();

  Future<void> _save(List<RfidCard> cards) async {
    await ref.read(repoProvider).saveRfidCards(cards);
    state = AsyncData(cards);
  }

  Future<void> add(RfidCard card) async {
    final current = state.value ?? await future;
    if (current.any((c) => c.uid == card.uid)) {
      throw AppException('La tarjeta ${card.uid} ya está registrada');
    }
    await _save([...current, card]);
  }

  Future<void> toggle(String uid) async {
    final current = state.value ?? const [];
    await _save([for (final c in current) c.uid == uid ? c.copyWith(active: !c.active) : c]);
  }

  Future<void> remove(String uid) async {
    final current = state.value ?? const [];
    await _save(current.where((c) => c.uid != uid).toList());
  }
}

final rfidCardsProvider = AsyncNotifierProvider<RfidCardsController, List<RfidCard>>(RfidCardsController.new);

/// Nombre del encargado dueño de un UID (para mostrar en el historial).
final cardNameProvider = Provider.family<String?, String>((ref, uid) {
  final cards = ref.watch(rfidCardsProvider).value ?? const [];
  return cards.where((c) => c.uid == uid).firstOrNull?.name;
});
