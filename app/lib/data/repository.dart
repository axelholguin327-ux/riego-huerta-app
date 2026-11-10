import 'models.dart';

/// Operaciones que la app necesita del sistema de riego.
///
/// La UI y los controladores solo conocen esta interfaz; hay dos
/// implementaciones: [ThingsBoardRepository] (nodo real) y
/// [DemoRepository] (datos simulados para presentar o probar sin el nodo).
abstract class HuertaRepository {
  String get userName;
  String get userEmail;
  bool get isDemo;

  Future<DeviceInfo> device();

  /// Telemetría en vivo. Emite el estado completo cada vez que llega un dato.
  Stream<Telemetry> telemetry();

  /// RPC `setIrrigation` al ESP32.
  Future<void> setIrrigation(int zone, bool state, int durationS);

  /// Cambia el modo (atributo compartido `mode` + RPC `setMode`).
  /// Regresa false si el nodo no respondió (el cambio se aplica al reconectar).
  Future<bool> setMode(String mode);

  /// Atributo compartido `soil_threshold_pct`.
  Future<void> setThreshold(int pct);

  Future<List<AlarmItem>> alarms();
  Future<void> ackAlarm(String id);

  Future<List<SoilPoint>> soilHistory(Duration range);
  Future<List<IrrigationEvent>> irrigationEvents(Duration range);
  Future<List<RfidAccess>> rfidAccesses({int limit = 20});

  Future<List<RfidCard>> rfidCards();
  Future<void> saveRfidCards(List<RfidCard> cards);

  Future<void> close();
}
