/// Configuración de la conexión con ThingsBoard.
///
/// Aquí NO van contraseñas ni tokens: el usuario inicia sesión desde la app
/// y el token de sesión se guarda cifrado en el teléfono.
class AppConfig {
  /// Servidor de ThingsBoard Cloud (REST y WebSocket).
  static const String tbHost = 'thingsboard.cloud';

  /// Nombre del dispositivo ESP32 en ThingsBoard (el nodo físico).
  static const String deviceName = 'nodo-huerta-test';

  /// El ESP32 publica telemetría cada 10 s; si pasa más de este tiempo
  /// sin datos, la app considera que el nodo está desconectado.
  static const Duration offlineAfter = Duration(seconds: 45);

  /// Tiempo máximo de espera de la respuesta del ESP32 a un comando RPC.
  static const Duration rpcTimeout = Duration(seconds: 10);

  static Uri api(String path, [Map<String, String>? query]) =>
      Uri.https(tbHost, path, query);

  static Uri get webSocket => Uri.parse('wss://$tbHost/api/ws');
}
