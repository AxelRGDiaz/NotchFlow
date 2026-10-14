# Pruebas y estabilización

Estado al cierre de la Fase 5, en un MacBook Air 13" M3 con macOS 26.6.

## Automáticas

`Scripts/test.sh` ejecuta 69 pruebas unitarias (Swift Testing): geometría y
disposición de la ventana, máquina de estados, preferencias y su persistencia,
contenido compacto, cuenta atrás de eventos, lectura de Música y de
MediaRemote, favoritos y actividad.

## Comprobadas en el equipo (Fase 5)

| Comprobación | Resultado |
|---|---|
| Consumo real: 3 h 20 min abierta con un video sonando | 12,2 s de CPU en total (≈0,1 %); el adaptador, 0,2 s |
| Consumo en reposo durante 1 min | 0,0 % de CPU, ningún despertar nuevo, 10 hilos |
| Memoria | 60 MB en reposo; pico de 109 MB con el panel y la configuración abiertos, liberado después |
| Fugas (`leaks`) | 14,7 KB, todos en frameworks del sistema (XPC de AppIntents); ninguno de NotchKit |
| Cierre normal, `SIGTERM` y `SIGKILL` | Sin procesos de Perl huérfanos (supervisor) |
| Adaptador que no responde (fallo inyectado) | Pasa al respaldo de Apple Music a los 5 s, sin procesos colgados |
| Adaptador que se cae en bucle (fallo inyectado) | Tres reinicios; al cuarto fallo, respaldo; sin procesos colgados |
| Segunda instancia | Se cierra sola |
| Marcos de la ventana en reposo, compacto y expandido | Correctos (ver Fase 3) |
| Detección de un video de YouTube en Brave | Correcta; pasa sola al estado compacto |

Para repetir la inyección de fallos: copiar `build/NotchFlow.app`, sustituir
`Contents/Resources/mediaremote-adapter.pl` por `sleep 3600;` (no responde) o
por una línea JSON seguida de `exit 1;` (se cae), volver a firmar la copia con
`codesign --force --sign -` y abrirla. El registro de la categoría `music`
debe mostrar el paso al respaldo.

## Manuales

El 14 de octubre de 2026 el usuario informó de que, tras probar la app, "todo
parece funcionar". La lista sigue sirviendo como guía de regresión antes de
cada versión.

### Lista de comprobación

Requieren interacción o hardware que no se puede automatizar.

### Interacción

- [ ] Pasar el cursor por el notch abre el panel; salir lo cierra tras el retardo.
- [ ] Clic en el notch lo abre; clic fuera lo cierra; fijado, no se cierra.
- [ ] Desde el icono de la barra de menús: abre el panel y Escape lo cierra.
- [ ] Los botones del panel responden al primer clic.
- [ ] Abrir con cursor o clic no quita el teclado a la app activa.
- [ ] Con "Reducir movimiento" activado, la animación es un fundido corto.

### Permisos

- [ ] Calendario: "Permitir acceso" muestra el aviso; al aceptar aparecen los eventos.
- [ ] Calendario denegado: la tarjeta lo explica y "Abrir Ajustes" lleva a Privacidad > Calendarios.
- [ ] Concederlo después desde Ajustes: al volver a abrir el panel aparecen los eventos.
- [ ] Con la firma ad-hoc, tras recompilar, macOS puede volver a pedir los permisos (esperado hasta la Fase 6).

### Música

- [ ] Reproducir/pausar, anterior y siguiente con un video del navegador y con Música.
- [ ] La carátula aparece y cambia con la pista.
- [x] Spotify: el usuario confirmó el 14 de octubre de 2026 que funciona mediante MediaRemote.

### Pantallas y espacios

- [ ] Cambiar la resolución (Ajustes > Pantallas): el panel se recoloca centrado en el notch.
- [ ] Conectar un monitor externo: el panel sigue en la pantalla con notch.
- [ ] Tapa cerrada con monitor externo: aparece en la pantalla principal, invisible en reposo y funcional al pasar el cursor por el centro de la barra de menús.
- [ ] Desconectar el monitor: vuelve al notch.
- [ ] Cambiar de escritorio (Mission Control): el panel está en todos.
- [ ] App a pantalla completa: el panel sigue disponible junto al notch.

### Ciclo de vida

- [ ] Suspender y reactivar: el panel sigue en su sitio y los datos se actualizan.
- [ ] "Abrir al iniciar sesión": activarlo, cerrar sesión y volver a entrar.
- [ ] Usarla una jornada completa sin cierres inesperados.

## Limitaciones conocidas

- Si el adaptador de MediaRemote se da por roto, se reintenta cada 5 minutos;
  mientras tanto se usa Apple Music. El reintento no se ha probado esperando los 5 minutos.
- `Scripts/test.sh` reintenta ante un fallo intermitente de la toolchain al
  cargar el plugin de macros de Swift Testing (no relacionado con el proyecto).
