# Firmware del nodo y configuración de ThingsBoard

## 1. Cargar el firmware 0.4

Cambios respecto a la versión 0.3 (en el código están marcados con `[0.4]`):

| Cambio | Para qué |
|---|---|
| Credenciales en `secrets.h` | El token y la contraseña del Wi-Fi ya no van en el código que se sube a GitHub. |
| Atributo compartido `rfid_cards` | El ESP32 autoriza las tarjetas que se registran desde la app (pantalla Más → Tarjetas RFID). |
| La tarjeta riega su zona | Riega la primera zona que la tarjeta tiene permitida; antes siempre era la 1. |
| Pide `mode` y `rfid_cards` al conectarse | El modo elegido en la app se conserva aunque el ESP32 se reinicie. |
| `setBufferSize(1024)` | Hace falta para recibir la lista de tarjetas. |
| `fw = 0.4` | La pantalla Dispositivo de la app muestra la versión. |

Mientras la app no tenga tarjetas registradas, el nodo sigue funcionando como antes (`REQUIRE_AUTH` / `ALLOWED_UIDS`).

**Pasos:**
1. Copia `secrets.h.example` como `secrets.h` en la misma carpeta y escribe tu Wi-Fi y el token de `nodo-huerta-test`. Lo copias desde ThingsBoard: Devices → nodo-huerta-test → *Copy access token*.
2. Abre `sketch_riego_fisico.ino` en el Arduino IDE, selecciona la placa **ESP32 Dev Module** y súbelo.
3. En el monitor serie debe aparecer `=== SISTEMA DE RIEGO INICIADO (fw 0.4) ===`, luego `MQTT OK` y `Tarjetas RFID cargadas: N`.

> `secrets.h` está en `.gitignore`: nunca se sube al repositorio.

## 2. Usuario para la app en ThingsBoard

La app **no** usa la cuenta de administrador. Crea un usuario de cliente:

1. **Customers & users → Customers → +** → Title: `Huerta Manzanos` → Add.
2. Abre el customer → pestaña **Users** → **+** → escribe tu correo y nombre. En *User group* elige **Customer Administrators**, porque necesita permiso para mandar comandos y editar atributos. En *Activation method* elige *Display activation link*, abre el enlace y define la contraseña.
3. **Devices** → `nodo-huerta-test` → **Assign to customer** (o *Change owner*) → `Huerta Manzanos`.
4. En la app, inicia sesión con ese correo y contraseña.

## 3. Recomendado

- En `nodo-huerta-test` → **Attributes** → *Shared attributes* → **+**: agrega `mode` = `auto`. La app también lo crea la primera vez que cambias el modo.
- Antes de usarlo en campo, sube `AUTO_MAX_S` a 120 y `RFID_RUN_S` a 30, como indica el comentario del código.
- `nodo-huerta-01` ya no se usa. Puedes renombrarlo a `nodo-huerta-sim` para que no se confunda.
