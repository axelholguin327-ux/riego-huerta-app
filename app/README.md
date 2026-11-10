# App Huerta Manzanos (Flutter)

App móvil del sistema de riego. Se conecta a **ThingsBoard Cloud** y controla el nodo físico `nodo-huerta-test`:

- **Telemetría en vivo** por WebSocket: humedad de suelo, temperatura, válvulas, bomba y modo.
- **Riego** con el RPC `setIrrigation`, **modo** automático o manual y **umbral** de humedad (los dos como atributos compartidos).
- **Alarmas** del Rule Engine, que se pueden reconocer.
- **Historial**: gráfica de humedad, eventos de riego y accesos RFID.
- **Tarjetas RFID**: se registran desde la app y se guardan en el atributo compartido `rfid_cards`. Las lee el firmware 0.4.
- **Modo demo**: simula el nodo para probar o presentar sin hardware.

## Estructura (arquitectura por capas)

```
lib/
├─ config.dart              Servidor y nombre del dispositivo (sin contraseñas)
├─ theme.dart               Tokens de la guía de estilo
├─ router.dart              Navegación (go_router) y barra inferior
├─ data/                    Capa de datos
│  ├─ models.dart
│  ├─ repository.dart       Interfaz
│  ├─ thingsboard_repository.dart   REST + WebSocket de ThingsBoard
│  └─ demo_repository.dart  Simulación del nodo
├─ state/providers.dart     Lógica y estado (Riverpod)
└─ ui/                      Pantallas
```

## Ejecutar

La ruta del proyecto es muy larga para Visual Studio, así que en Windows se usa una unidad corta. Este paso solo hace falta una vez por cada vez que enciendes la PC:

```powershell
subst H: "C:\Users\axelh\OneDrive\Imágenes\Desktop\Tec\Noveno Semestre\Desarrollo de Aplicaciones Moviles\Unidad 3\riego-huerta-app"
cd H:\app
flutter run -d windows      # en la PC
flutter run                 # en un Android conectado por USB
```

Pruebas automáticas:

```powershell
flutter test
```

Para iniciar sesión se usa un **usuario de cliente de ThingsBoard** que tenga asignado `nodo-huerta-test`; los pasos están en [`../firmware/README.md`](../firmware/README.md). Sin ese usuario, entra con **"Entrar en modo demo"**.
