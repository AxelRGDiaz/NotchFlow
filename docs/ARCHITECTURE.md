# Arquitectura

Documento de diseño de la Fase 2. Describe lo que ya existe en el repositorio y
lo que se construirá en las Fases 3 y 4. Cada apartado indica su estado.

## Decisiones de base

| Decisión | Elección | Motivo |
|---|---|---|
| macOS mínimo | 14.0 | Cubre todos los Mac con notch (el Air M3 salió con 14.3). Da `@Observable`, la API actual de permisos de EventKit y `SMAppService`. |
| Sandbox | No; Hardened Runtime | Apple Events hacia Música y Spotify y la API de Accesibilidad encajan mal o no funcionan en sandbox. Descarta la Mac App Store. |
| Distribución | Developer ID + notarización | Consecuencia de lo anterior. Procedimiento en el README. |
| Arquitectura | Solo arm64 | Todos los MacBook con notch son Apple Silicon; un binario universal duplicaría el tamaño sin ganar equipos. |
| Tipo de app | Agente (`LSUIElement`) | Sin icono en el Dock; un `NSStatusItem` propio da acceso a configuración y salida. |
| Proyecto | Paquete SwiftPM + script que ensambla el `.app` | Compila y se prueba solo con Command Line Tools; Xcode abre `Package.swift` directamente. |
| Concurrencia | Swift 6 estricto; interfaz y servicios en `@MainActor` | El trabajo lento (Apple Events, EventKit) sale del hilo principal con `async`. |
| Dependencias externas | Ninguna | Todo se resuelve con frameworks del sistema. |
| APIs privadas | Solo MediaRemote, en el módulo de música | Excepción aprobada expresamente; ver «Música». |

## Nombre del producto

El nombre comercial vive en `Config/app.env`. El script de empaquetado genera
el `Info.plist` con esos valores y el código los lee del bundle mediante
`AppIdentity`. Los módulos (`NotchKit`, `NotchApp`) tienen nombres neutros, así
que renombrar el producto no obliga a tocar código.

## Módulos

```
NotchFlow/
├─ Package.swift
├─ Config/app.env               identidad del producto
├─ App/                         [hecho] ejecutable NotchApp: arranque y AppDelegate
├─ Sources/NotchKit/
│  ├─ Core/                     [hecho] AppIdentity, Log, ServiceStatus, NotchGeometry,
│  │                            NotchLayout, NotchStateMachine
│  ├─ Models/                   [hecho] Preferences, NowPlaying, CalendarEvent,
│  │                            SystemStatus, CompactContent
│  ├─ Services/                 [hecho] PreferencesStore, LoginItemService, Calendar,
│  │                            Application, Activity, Music/ (adaptador de Apple Music),
│  │                            System/ (batería, audio, Wi-Fi, enlaces a Ajustes)
│  ├─ Windowing/                [hecho] NotchPanel, NotchWindowController
│  ├─ AppShell/                 [hecho] AppController, ModuleCoordinator, StatusItemController
│  └─ Features/                 [hecho] Notch/, Settings/, Modules/ (una vista por pestaña)
├─ Tests/NotchKitTests/         [hecho] geometría, disposición, estados, preferencias, modelos
├─ Resources/                   [hecho] AppIcon.icns (generado por Scripts/make-icon.swift)
├─ Vendor/mediaremote-adapter/  [hecho] adaptador de MediaRemote (BSD 3-Clause)
└─ Scripts/                     [hecho] build-app.sh, test.sh, package.sh, notarize.sh,
                                make-icon.swift, build-mediaremote-adapter.sh
```

Reglas de dependencia: `Core` y `Models` no importan SwiftUI ni dependen de
servicios. `Services` no conoce las vistas. `Features` lee servicios y modelos.
Solo `Windowing` toca `NSPanel` y `NSScreen`. El ejecutable solo conoce
`AppController`, el único tipo público que necesita.

No hay capa de ViewModels separada: los servicios son `@Observable` y las
vistas los leen directamente. Se añade un modelo de vista solo donde haya
lógica de presentación que probar.

## Ventana

### Qué es realmente la "integración con el notch"

macOS no permite dibujar dentro del notch. La interfaz es una ventana negra sin
borde situada sobre la barra de menús que prolonga visualmente el notch. En
reposo mide exactamente lo mismo que el notch y queda oculta detrás de él.

### Configuración del panel

- `NSPanel` con `[.borderless, .nonactivatingPanel]`: no activa la app ni roba el foco.
- Nivel `.statusBar` (25), uno por encima de la barra de menús (24). No se usan
  niveles superiores.
- `collectionBehavior`: `canJoinAllSpaces`, `stationary`, `fullScreenAuxiliary`, `ignoresCycle`.
- Fondo transparente, sin sombra de ventana (la sombra la dibuja SwiftUI).
- `canBecomeKey` solo mientras el panel está expandido, para permitir navegación
  por teclado y Escape. `canBecomeMain` siempre falso.

Comprobado en un MacBook Air M3 con macOS 26.6: AppKit no desplaza el panel
fuera de la barra de menús y la app no pasa a primer plano.

### Contenido del panel

La franja a la altura del notch solo lleva la fecha a la izquierda y los
botones de fijar y configuración a la derecha: el notch tapa su centro y una
fila de iconos de módulos no cabía en los laterales. Los módulos van en una
fila de pestañas justo debajo, y el elegido ocupa todo el ancho. La pestaña
elegida se conserva entre aperturas; abrir el panel arrastrando archivos
selecciona la bandeja.

### La ventana se ciñe a la forma visible

`NotchLayout` calcula el marco de la ventana para cada estado: en reposo es
exactamente el notch, en compacto el notch más las alas, y expandido el panel
más un margen para la sombra. Así la ventana nunca cubre zonas de la barra de
menús que no esté dibujando y no depende de que los clics atraviesen áreas
transparentes.

Durante una transición la ventana ocupa la unión de los marcos inicial y final
para que la animación de SwiftUI no se recorte; al terminar se ciñe al marco
final. Todos los marcos están centrados en el notch y la vista coloca la forma
arriba y al centro.

### Cursor, clics y teclado

- La posición real del cursor frente al marco de la ventana es la fuente de
  verdad para entrar y salir. Los eventos de `NSTrackingArea` solo disparan la
  comprobación, porque no llegan cuando es la ventana la que cambia de tamaño.
- Un monitor global de clics existe solo mientras el panel está abierto y sirve
  para cerrarlo al hacer clic fuera. No requiere permisos.
- Arrastrar archivos sobre el notch abre el panel y lo lleva a la bandeja.
  Durante un arrastre no llegan eventos de entrada y salida, así que mientras
  el panel siga abierto por un arrastre se consulta la posición del cursor
  cada 250 ms; al cerrarse, la consulta se detiene.
- Abrir con el cursor o con un clic no toma el teclado. Abrir desde la barra de
  menús sí, para poder navegar con el teclado y cerrar con Escape.

### Ciclo de vida

`NotchWindowController` es el único dueño del panel y lo crea una sola vez.

| Suceso | Origen | Reacción |
|---|---|---|
| Arranque | `applicationDidFinishLaunching` | Salir si ya hay otra instancia; elegir pantalla y mostrar el panel. |
| Cambio de pantallas o resolución | `NSApplication.didChangeScreenParametersNotification` | Recalcular `NotchGeometry` y recolocar. |
| Reactivación | `NSWorkspace.didWakeNotification` | Recolocar. [Fase 4] refrescar servicios. |
| Cambio de preferencias | Observación de `PreferencesStore` | Recalcular el marco. |
| Salida | `applicationWillTerminate` | Cancelar tareas, quitar monitores y observadores. |

**Pantalla completa.** El panel está presente en los espacios a pantalla
completa (`fullScreenAuxiliary`). No hay opción para ocultarlo: no existe una
forma pública fiable de saber si el espacio activo está a pantalla completa, y
en un Mac con notch una ventana a pantalla completa y una maximizada ocupan el
mismo rectángulo. En reposo no molesta: con notch queda tras él y sin notch es
invisible (opacidad 0,01, para que siga respondiendo al cursor).

Elección de pantalla (`NotchGeometry.preferredScreen`): la que tiene notch; si
no hay, la integrada; si tampoco, la principal. Sin notch físico (tapa cerrada
con monitor externo) se usa una "píldora" virtual del alto de la barra de menús.

### Estados

`NotchStateMachine` es una función pura: recibe eventos y devuelve efectos
(programar o cancelar apertura y cierre). El controlador ejecuta los efectos
con tareas cancelables; no hay temporizadores periódicos.

```
idle ──actividad──▶ compact
 │  ◀─sin actividad─  │
 └── hover (con retardo) / clic / atajo ──▶ expanded(pinned)
       ◀── salida del cursor (con retardo) / Escape / clic fuera ──
```

- `idle`: tamaño del notch, invisible.
- `compact`: alas visibles con indicadores (música, próximo evento).
- `expanded`: panel completo; fijado ignora la salida del cursor.

Las alas tapan menús de la app activa a la izquierda e iconos de estado a la
derecha, y no hay API pública para saber cuánto ocupan. Por eso su ancho está
limitado por `maxWingWidth` y el reposo no muestra nada.

## Servicios

Todos son `@MainActor`, `@Observable`, implementan `ServiceLifecycle`
(`start`/`stop` idempotentes) y exponen un `ServiceStatus`. Una vista nunca
supone que su servicio está disponible: muestra el estado que este declara.

| Servicio | Mecanismo | Cómo se entera de cambios |
|---|---|---|
| `PreferencesStore` [hecho] | `UserDefaults`, un valor JSON | — |
| `MusicService` [hecho] | MediaRemote (cualquier reproductor) y, como respaldo, Apple Music por Apple Events | Notificaciones distribuidas del reproductor; refresco al expandir |
| `CalendarService` [hecho] | EventKit, de hoy a 7 días | `EKEventStoreChanged` y cambio de día |
| `ApplicationService` [hecho] | `NSWorkspace` | Notificaciones de apertura y cierre de apps |
| `BatteryService` [hecho] | IOKit `IOPS*` | Notificaciones Darwin de IOKit (`com.apple.system.powersources.*`) |
| `AudioService` [hecho] | CoreAudio | Listeners de propiedades |
| `WiFiService` [hecho] | CoreWLAN, solo encendido | Delegado de `CWWiFiClient` |
| `ActivityService` [hecho] | Eventos de los servicios anteriores, en memoria | — |
| `LoginItemService` [hecho] | `SMAppService.mainApp` | Consulta al abrir la configuración |

`ModuleCoordinator` arranca un servicio solo si su módulo está visible o su
indicador compacto activo, y lo detiene en caso contrario. También deriva el
contenido compacto con `CompactContentBuilder` (función pura) y programa un
único aviso para el siguiente cambio, en lugar de sondear.

Bluetooth no tiene servicio: leer su estado obliga a pedir el permiso de
Bluetooth, y no compensa para mostrar encendido o apagado. Es un enlace a Ajustes.

Se usa un protocolo solo donde hay varias implementaciones reales:
`MusicPlayerAdapter` (Apple Music, Spotify). El resto son clases concretas; la
lógica que merece pruebas está extraída a tipos puros (`EventTimeline`,
`NowPlaying.position(at:)`, `Preferences.normalized()`).

### Música

macOS no tiene una API pública para saber qué suena en el sistema. Por
decisión expresa del usuario, la fuente principal es **MediaRemote**, el
framework privado que usa el widget «Reproduciendo» de macOS. Desde macOS 15.4
una app normal no puede leerlo (comprobado en macOS 26.6: devuelve vacío), así
que se usa [mediaremote-adapter](../Vendor/mediaremote-adapter/VENDORED.md):
`/usr/bin/perl`, que sí tiene acceso, carga un framework propio que imprime el
estado en JSON.

- `SystemNowPlayingAdapter` mantiene un proceso `stream` mientras el módulo está
  activo y aplica sus actualizaciones (completas o diferenciales). Las órdenes
  se envían con procesos `send` de corta duración.
- Un supervisor en Perl lanza el adaptador como hijo y lo termina si la app
  desaparece, incluso por cierre forzado (comprobado con `SIGTERM` y `SIGKILL`).
- Si el adaptador no responde en 5 s o falla más de 3 veces en un minuto, se da
  por roto y `MusicService` pasa al siguiente adaptador: Apple Music por Apple
  Events, que no depende de APIs privadas. Se vuelve a intentar cada 5 minutos.
- Riesgos: Apple puede cerrar esta vía en cualquier actualización; impide la
  Mac App Store. No requiere permisos del usuario.

**Respaldo con Apple Music.** Los scripts se ejecutan en una cola en serie propia (`AppleScriptRunner`),
fuera del hilo principal, porque `NSAppleScript` no admite uso concurrente y
Música puede tardar en responder. Cada script comprueba primero
`application id … is running` para no abrir Música por su cuenta.
Spotify no está implementado: no hay forma de verificarlo en el equipo de
desarrollo. Se añadiría como otro `MusicPlayerAdapter`.

No existe una API pública para leer lo que suena en el sistema.
`MusicService` mantiene un adaptador por reproductor compatible y muestra el
que esté reproduciendo. Un adaptador nunca lanza la app del reproductor ni
envía Apple Events si esta no está abierta, para no provocar avisos de permiso
inesperados. La posición se interpola localmente; el reloj de progreso (1 s)
solo corre con el panel expandido y la música sonando.

### Actividad en lugar de notificaciones

Una app no puede leer las notificaciones de otras. La sección "Actividad"
muestra solo eventos generados por NotchFlow (evento próximo, cambio de
canción, batería baja) y lo indica así en la interfaz.

## Permisos

Se piden al activar la función, nunca al arrancar. Cada módulo sin permiso
muestra para qué lo necesita y un botón para concederlo o abrir Ajustes.

| Permiso | Para qué | Clave de `Info.plist` | Si se deniega |
|---|---|---|---|
| Calendario (acceso completo) | Leer eventos | `NSCalendarsFullAccessUsageDescription` | Módulo con explicación y enlace a Ajustes |
| Recordatorios (acceso completo) | Leer, crear y completar tareas | `NSRemindersFullAccessUsageDescription` (el entitlement de calendarios cubre EventKit) | Módulo con explicación y enlace a Ajustes |
| Cámara | Espejo en el panel, solo tras pulsar "Encender" | `NSCameraUsageDescription` + entitlement `com.apple.security.device.camera` | Módulo con explicación y enlace a Ajustes |
| Automatización (por app) | Leer y controlar Música | `NSAppleEventsUsageDescription` + entitlement `com.apple.security.automation.apple-events` | Ese reproductor aparece como "sin permiso" |
| Notificaciones | Avisos propios | — | Solo indicadores dentro del panel |
| Ubicación (opcional) | Nombre de la red Wi-Fi | `NSLocationUsageDescription` | Se muestra solo conectado o desconectado |

No se solicitan Accesibilidad ni Grabación de pantalla en el MVP.

## Preferencias

`Preferences` es un único valor `Codable`. La decodificación es tolerante: una
clave ausente o desconocida conserva su valor por defecto, y `normalized()`
repara datos incoherentes. Así, añadir opciones en versiones futuras no borra
la configuración existente. El inicio al iniciar sesión no se guarda: su fuente
de verdad es `SMAppService`.

## Rendimiento

- Observación de eventos del sistema en lugar de sondeo.
- Temporizadores solo de un disparo, salvo el reloj de progreso descrito arriba.
- Los servicios de módulos ocultos no se inician.
- Carátulas cacheadas en memoria por identificador de pista.

## Privacidad

Sin red en el MVP, sin telemetría y sin datos fuera de `UserDefaults`. La
bandeja guarda rutas, no copias de los archivos. La cámara solo muestra la
imagen en pantalla: no se graba ni se procesa, y se apaga al cerrar el panel. La única
función futura que usaría red (carátulas de Spotify, que el reproductor entrega
como URL) será opcional. Los registros no incluyen títulos de canciones, de
eventos ni nombres de red.

## Pruebas

- Unitarias (Swift Testing, `Scripts/test.sh`): geometría, disposición de la
  ventana, máquina de estados y su modelo de vista, preferencias y su
  persistencia, interpolación de reproducción, línea de tiempo de eventos.
  El script reintenta ante un fallo intermitente de la toolchain al cargar el
  plugin de macros de Swift Testing; ver el comentario del propio script.
- Ayudas de desarrollo al lanzar la app: `-debugExpand YES` abre el panel,
  `-debugActivity YES` muestra actividad de ejemplo y `-debug YES` añade esa
  opción al menú de la barra de menús.
- Manuales (Fase 5): pantalla completa, monitores externos, tapa cerrada,
  suspensión, permisos denegados. No son automatizables sin Xcode y UI tests.

## Límites que no se van a disfrazar

- Los iconos de barra de menús de otras apps no se pueden enumerar ni mover.
  La sección de apps muestra favoritos y apps abiertas, rotulados como accesos directos.
- Las notificaciones del sistema no son legibles.
- El brillo y el encendido de Bluetooth no tienen API pública: enlace a Ajustes.
- La detección de cualquier reproductor depende de MediaRemote, una vía no
  oficial; si Apple la cierra, solo quedará Apple Music.
