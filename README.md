# Coro — letras en tu CarPlay (prototipo v0.1)

Coro detecta qué suena en **Spotify** o **Apple Music**, descarga la letra sincronizada y la muestra línea a línea:
- en la app (modo karaoke),
- en la pantalla de bloqueo y la Dynamic Island,
- **en CarPlay**, como Actividad en directo (iOS 26+). No hace falta ningún permiso especial de Apple para CarPlay.

> ⚠️ Ojos en la carretera. La letra en CarPlay es para un vistazo o para tus pasajeros.

---

## Para probarlo mañana en el coche (≈20 min)

### 1. Requisitos
- Mac con **Xcode 26+**.
- iPhone con **iOS 26+**, cable USB y **Modo desarrollador** activado (Ajustes › Privacidad y seguridad › Modo desarrollador).
- Coche con CarPlay.
- Para Spotify: cuenta **Premium**, porque Spotify la exige para las apps en modo desarrollo desde marzo de 2026. Si no tienes Premium, usa la fuente **Apple Music** o **Demo**.
- Apple ID: basta una cuenta gratuita. La app instalada caduca a los 7 días; con el programa de pago (99 €/año) dura 1 año. **No compartas tu contraseña de iCloud con nadie**: la firma se hace en Xcode, con tu sesión.

### 2. Crear la app en Spotify (5 min)
1. Entra en https://developer.spotify.com/dashboard › **Create app**.
2. **Redirect URI**: `coro://spotify-callback` (exactamente así).
3. En "Which API/SDKs", marca solo **Web API**.
4. Guarda la app y copia el **Client ID**. El Client Secret no hace falta.
5. En *User Management*, comprueba que tu cuenta está incluida.

### 3. Generar el proyecto
```bash
cd ~/DevProjects/coro
chmod +x setup.sh
./setup.sh          # instala XcodeGen si falta, ejecuta los tests y abre Xcode
```
Edita `Config.xcconfig`:
```
APP_BUNDLE_ID = com.tunombre.coro
SPOTIFY_CLIENT_ID = <tu client id>
```
Si cambias el xcconfig con Xcode abierto, vuelve a ejecutar `xcodegen generate`.

### 4. Firmar e instalar
1. En Xcode, abre el proyecto **Coro**, ve a *Signing & Capabilities* y elige tu equipo en los targets **Coro** y **CoroWidgets**.
2. Conecta el iPhone, selecciónalo arriba y pulsa ▶︎ (⌘R).
3. La primera vez: en el iPhone ve a Ajustes › General › VPN y gestión de dispositivos y confía en tu certificado.

### 5. Probar en casa, antes del coche
1. Elige la fuente **Demo** y pulsa **Empezar**. Bloquea el móvil: deberías ver la letra de prueba cambiar en la pantalla de bloqueo.
2. Cambia a **Spotify**, pulsa **Conectar Spotify**, pon una canción y luego **Empezar**.
3. Acepta los permisos de **ubicación** ("Al usar la app") y de Actividades en directo.

### 6. En el coche
1. Conecta CarPlay.
2. Abre Coro **con el coche parado**, pulsa **Empezar** y deja el móvil bloqueado.
3. En CarPlay, la actividad debería aparecer sola en el panel de widgets o notificaciones. Si no, revisa en el iPhone: Ajustes › General › CarPlay › tu coche, que los widgets y las actividades en directo estén permitidos, y Ajustes › Coro › Actividades en directo.
4. Si la letra va tarde o adelantada, ajusta el **desfase** en ⚙︎ (por defecto +0,3 s, que compensa el retardo de Bluetooth).

---

## Arquitectura

```
CoroKit (Swift Package, con tests)    App (SwiftUI)                    CoroWidgets (extensión)
├─ LRCParser       ─┐                 ├─ Sources/                      └─ LyricsLiveActivity
├─ LyricsSync       │  ← lógica pura  │   ├─ SpotifySource (Web API)       ├─ Lock Screen
├─ TitleNormalizer  │                 │   ├─ AppleMusicSource (local)      ├─ Dynamic Island
├─ LRCLibClient    ─┘  ← proveedor    │   └─ DemoSource                    └─ .small → CarPlay / Watch
└─ LyricsActivityAttributes ──────────┼─ Engine/LyricsEngine  ── estado ──▶ ActivityKit
                                      ├─ Engine/BackgroundKeeper
                                      └─ Spotify/SpotifyAuth (PKCE + Keychain)
```

**Flujo:** la fuente da una "foto" (canción + posición + momento). El motor extrapola la posición localmente cada 200 ms, calcula la línea activa por búsqueda binaria y solo actualiza la Live Activity cuando cambia el texto, es decir, una vez por línea.

**Decisiones clave**
| Decisión | Por qué |
|---|---|
| Live Activity en lugar de una app CarPlay | No hay categoría de CarPlay para "letras"; iOS 26 refleja las Live Activities en CarPlay sin necesidad de entitlement. |
| Consulta adaptativa (3 s, 1 s al final de la canción) + extrapolación | Unas 20 peticiones por minuto: sincronía fluida dentro del cupo del modo desarrollo de Spotify. |
| PKCE sin secreto + Keychain | Seguro para una app móvil; el token se renueva solo. |
| Protocolos `NowPlayingSource` / `LyricsProvider` | Permiten cambiar LRCLIB por Musixmatch, o el sondeo por un backend con push, sin tocar la UI. |
| Ubicación en segundo plano (prototipo) | Mantiene la app viva con el móvil bloqueado. **Apple probablemente lo rechazaría en la App Store** (ver hoja de ruta). |

## Tests
```bash
cd CoroKit && swift test
```
Cubren el parser LRC (varios timestamps, offset, CRLF, basura), la sincronía, la extrapolación de posición, la limpieza de títulos, la selección de la mejor letra, la búsqueda por título filtrada por cualquiera de los artistas, los reintentos ante errores de LRCLIB y la codificación de URLs.

## Hoja de ruta hacia la App Store
1. **Backend + push de Live Activity (APNs)**: el servidor consulta Spotify y empuja cada línea. Elimina el truco de la ubicación, ahorra batería y es lo que permite pasar la revisión de Apple.
2. **Letras con licencia** (Musixmatch u otro proveedor comercial). LRCLIB vale para uso personal, pero no basta para vender.
3. **Spotify Extended Quota**: hace falta para tener más de 5 usuarios y solo se concede a organizaciones (por ejemplo, una empresa).
4. Widget estático de CarPlay (canción actual y control), temas, tamaño de letra y traducción de letras.
5. Modelo de negocio: freemium. La competencia (CarFace, Dynamic Lyrics…) cobra entre 4 $ por semana y 10 $ al mes.

## Problemas conocidos del v0.1
- iOS puede limitar las actualizaciones de la Live Activity si la batería está baja (Modo ahorro).
- La actividad dura un máximo de 8 h; si desaparece, vuelve a pulsar Empezar.
- Las canciones que no están en LRCLIB muestran "Sin letra disponible".
- El prototipo no se ha compilado fuera de tu Mac: si Xcode marca algún error, pégamelo.
