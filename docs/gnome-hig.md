# Cumplimiento obligatorio de GNOME HIG

**Estado: NO APROBADO.** Cumplir las [GNOME Human Interface Guidelines][hig]
es requisito del proyecto, no una aspiración estética. La aplicación es nativa:
**Vala + GTK 4 + libadwaita** (GStreamer para audio). Usar ese stack o tener tests
verdes no certifica HIG. Merge y release quedan bloqueados mientras haya
desviaciones aplicables o verificaciones HIG pendientes, salvo la
[excepción puntual autorizada para el bootstrap inicial y su prerelease](branches-and-releases.md#excepción-puntual-autorizada-y-plan-pendiente).
No cambia este estado ni los requisitos de las siguientes integraciones.
Al corte del **2026-10-25, previo a la primera integración**, el
[run CI 40239813173](https://github.com/gstn-caruso/gtkPlayer/actions/runs/40239813173)
terminó **SUCCESS** para `7114a837e47d2e1cb42a4ee5f68481f497304c2b`, ya publicado
(32 tests: 11 core y 21 UI; build/paquete exitoso, release omitido).
No aprueba HIG ni cubre el futuro commit documental; `main` y el prerelease
siguen pendientes en ese corte.

## Alcance y evidencia

Revisión documental del **2026-10-25**, sobre `feat/library-preferences`, base
`df0d34d` y cambios locales aún sin integrar. Se contrastaron las fuentes
oficiales enlazadas con código y tests; no se ejecutaron pruebas interactivas ni
se reejecutó la suite en esta revisión. No es una auditoría completa.

Incremento acotado posterior, al **2026-10-25**, en `feat/ci-hig-readiness`,
cambios inicialmente locales sobre `a920298`, ahora publicados en `7114a83`:
el coordinador reportó compilación y
32 tests verdes (11 core y 21 UI) con GTK 4.22.4/libadwaita 1.9.1, fixtures
locales, GIO local, Xvfb y `fakesink`; los 21 UI también pasaron en claro y oscuro.
Evidencia local ignorada en `build/hig-trace.md` y `build/hig-*.log`, con baseline
de 26 casos y cuatro rojos de comportamiento observados. La revisión independiente
por lectura, sin ejecutar tests, detectó los dos defectos P2 consignados en la
fila de estados vacíos: las tres brechas intervenidas no están plenamente cerradas.
Los 32 tests no cubren esos dos escenarios. El CI remoto citado ya cubre ese
código; falta auditoría interactiva: **NO APROBADO** permanece. Esta actualización
documental no reejecutó las pruebas, consultó la API remota ni reanudó la
implementación detenida.

Aplicar cada directriz con sus cuantificadores: «todas las apps», «la mayoría»,
«si existe este patrón» no son equivalentes. No hay que incorporar todos los
patrones del catálogo. Un caso **no aplicable** debe tener motivo explícito;
una duda de alcance sigue **pendiente**. Documentar una desviación no la aprueba.

Estados: **cubierto por código** = evidencia de implementación por lectura;
**cubierto por test** = existe una aserción concreta, con alcance limitado (no
implica ejecución nueva); **desviación observada** = contradicción identificada;
**pendiente** = falta comprobar o decidir; **no aplicable** = condición ausente.
Los estados cubiertos son parciales, nunca un aprobado global.

## Incremento local: panel proporcional y carátulas

En `fix/proportional-library-panel`, con cambios locales sin integrar, la
proporción inicial de biblioteca es **258/1280 ≈ 20 %** (decisión de producto,
no medida HIG). El ajuste manual conserva la proporción al redimensionar y
los nombres largos no ensanchan el panel. La selección de álbum muestra
carátula incrustada o `cover.jpg` regular; la ausencia o imagen inválida
restablece el icono genérico. Se omite `cover.jpg` si es enlace simbólico,
sin descartar el audio: se consulta tipo y atributo de enlace con
`NOFOLLOW_SYMLINKS` antes de leer.

Evidencia ejecutada localmente: compilación de `ui-tests`, rojo del escenario
de enlace (una pista conservada, textura indebidamente presente; fallo en
`tests/ui-tests.vala:479`), luego el mismo caso verde y **27/27 UI verdes**.
Entorno: X11 sobre Xvfb 1920×1080×24, GSettings en memoria, GIO local,
renderizador Cairo, audio `fakesink` y `GTK_A11Y=none`. Los tests observaron
256/1270 → 320/1590 para la proporción inicial y 384/1270 → 481/1590 para
la elegida; las carátulas incrustada y JPEG regular se mostraron a 96×96.
Esto no verifica accesibilidad ni aprueba HIG; la suite completa queda para
la comprobación final del coordinador y no hay nueva evidencia de CI remoto.

Próxima verificación manual, conforme a [adaptación][adaptive],
[paneles][panes], [teclado][keyboard] y [accesibilidad][a11y-tests]:
1024×600, arrastre real de separadores, recorrido de teclado, texto grande
y lector de pantalla; registrar resultado y límites antes de cerrar esas
brechas. El corte histórico del bootstrap no se modifica. **NO APROBADO**.

## Incremento local: árbol artista/banda → álbum

En `fix/proportional-library-panel`, el incremento sustituye el `DropDown`
de agrupación y la lista plana por artistas/bandas desplegables con álbumes
hijos mediante `Gtk.Expander`, conservando «Todas las pistas». La selección
identifica artista y álbum conjuntamente para no mezclar álbumes homónimos;
se mantienen carátulas, proporciones y ajuste manual de paneles.

El principal consultó la pauta oficial de
[listas y vistas de columnas](https://developer.gnome.org/hig/patterns/containers/list-column-views.html):
filas simples, orden útil y anchos acotados orientan esta revisión parcial.
El uso de un expansor nativo por sí solo no demuestra cumplimiento.

Evidencia ejecutada para esta limpieza estructural: **29/29 UI verdes antes
y 29/29 después**, incluida la regresión de álbumes homónimos, con el mismo
comando en ambas ejecuciones:

```sh
meson compile -C build ui-tests && env GDK_BACKEND=x11 GSETTINGS_BACKEND=memory GTK_A11Y=none GSK_RENDERER=cairo GIO_USE_VFS=local xvfb-run -a -s '-screen 0 1920x1080x24' ./build/ui-tests
```

Se retiró únicamente el fallback temporal de navegación plana en el helper
`select_album`, sin cambiar aserciones de escenarios ni producción. Se
conservó el reconocimiento de expansores nativos alternativos en los tests.
Ambas ejecuciones observaron carátulas de 96×96 y proporciones
256/1270 → 320/1590 y 384/1270 → 481/1590. La recompilación terminó con
advertencias de deprecación y del C generado; Xvfb emitió avisos EGL/DRI3,
sin fallos de tests. La suite completa queda a cargo del coordinador;
no se ejecutó aquí ni se comprobó CI remoto.

Próxima verificación manual: navegar y expandir/contraer con flechas y espacio,
comprobar con lector los nombres y el estado expandido, y revisar 1024×600
con texto grande. `GTK_A11Y=none` impide usar estos resultados como evidencia
de lector de pantalla. No se reescriben los cortes previos ni se certifica HIG:
el estado sigue **NO APROBADO**.

Corrección posterior del orden Unicode: el caso NFC/NFD reprodujo dos ramas
para un artista exacto (`branches == 1`, salida 134); tras desempatar por
identidad exacta después de cada `collate` de artista y álbum, pasó el caso
focalizado y **30/30 UI** con el entorno anterior. No se normalizan ni fusionan
identidades; se conserva el orden lingüístico salvo empate, acorde con la pauta
oficial de listas consultada sobre un orden útil. Recuento de referencia:
**41 = 11 core históricos + 30 UI ejecutados ahora**; no se reejecutó core ni
se afirma comprobación final completa. Sigue pendiente la verificación manual
de navegación y accesibilidad indicada arriba; HIG permanece **NO APROBADO**.

## Previsualización local: degradado cromático continuo

En `fix/proportional-library-panel`, el ajuste visual de `src/window.vala`
extrae un color de la carátula seleccionada (muestra de 16×16 ponderada por
croma y transparencia) y lo desvanece desde la barra nativa hasta el fondo
del tema a 420 px. Conserva composición, textos, controles, carátula de
96 px y paneles ajustables. La opacidad es 22 % en claro y 36 % en oscuro;
son decisiones visuales de producto, no valores exigidos por HIG.

Se siguen las pautas oficiales de [estilo][style] y [barras de cabecera][header]
consultadas por el principal: CSS decorativo mínimo, colores de texto/foco y
controles del tema, sin sustituir la barra ni su área nativa de arrastre.
El proveedor se aplica solo a los contextos del fondo y la cabecera de esta
ventana, no al display ni a Preferencias. Las señales de oscuro/alto contraste
actualizan el estilo; al cerrar se desconectan y se vacía el proveedor.
Alto contraste, ausencia de imagen válida y «Todas las pistas» usan fondo
neutro. No se fuerza tema ni se añade selector a la aplicación.

Evidencia ejecutada: `meson compile -C build` correcto y **30/30 UI verdes**
con X11/Xvfb, GSettings en memoria, Cairo, GIO local, `fakesink` y
`GTK_A11Y=none`, mediante el comando UI documentado arriba. Se mantienen
advertencias de deprecación/C generado y avisos EGL/DRI3 del entorno.
No se fabricó un rojo ni un test textual de CSS para una decisión estética.

Un driver visual temporal en `build/gradient-preview.vala` seleccionó el
álbum mediante `Gtk.Expander`/`Gtk.ListBox` y cambió claro → oscuro en la misma
ventana; solo el driver fuerza esos temas. Con audio y JPEG artificiales
locales se observaron `build/gradient-light.png` y `build/gradient-dark.png`:
tinte continuo, fondo final neutro y controles legibles, sin cambio de tamaño.
`build/gradient-neutral.png` muestra el retorno neutro al seleccionar todas
las pistas. Con `ADW_DEBUG_HIGH_CONTRAST=1`, libadwaita informó
`high-contrast=true`; se observó `build/gradient-contrast-dark.png` sin tinte
con el álbum aún seleccionado. Capturas sobre Xvfb 1440×900, ventana 1280×800.

Pendientes: aprobación visual del usuario con carátulas reales variadas,
comprobación del cambio de tema desde una sesión de escritorio real,
Preferencias y varias ventanas simultáneas, teclado/foco, texto grande,
arrastre real, lector y accesibilidad integral. El título largo de la muestra
queda recortado por el panel existente; no se modifica ese layout en este
incremento decorativo. La suite completa y revisión independiente corresponden
al cierre del coordinador; no se ejecutó CI remoto. **HIG NO APROBADO**.

## Incremento local: retrato público del artista en Datos

La tarjeta nativa «Sobre el artista» del panel Datos separa el retrato de la
carátula central y de la información de reproducción. Usa imagen acotada a
192 px, etiquetas sin markup remoto y enlaces GTK de licencia/fuente validados
por el proveedor. Mantiene tema, controles, degradado y separadores manuales;
el usuario pidió inspiración Spotify y se usaron sus capturas como referencia
visual, no como pauta normativa ni copia de sus controles. Los enlaces de
documentación Spotify que devolvieron 404 no cuentan como fuentes consultadas
válidas. No se atribuyen estas decisiones de producto a HIG. Se consultó la
pauta oficial de [estilo][style]: clases nativas y personalización
mínima; usar estos widgets no aprueba accesibilidad.

Evidencia local ejecutada: el rojo compilaba con un único error por el cuarto
argumento ausente en `Window`; tras integrar el proveedor explícito, pasó el
caso focal de retrato y **31/31 UI**, más **2/2 del servicio**, con servidor
loopback, sin acceso a fotos públicas reales. Se compiló también la aplicación
mediante `meson compile -C build ui-tests artist-photos-tests gtkplayer`.
Entorno UI: X11/Xvfb 1920×1080×24, GSettings en memoria, Cairo, GIO local,
`fakesink` y `GTK_A11Y=none`; persisten advertencias de deprecación/C generado
y EGL/DRI3. El nuevo caso verifica textura 16×16 mapeada, autor en texto plano,
enlaces y conservación de carátula 320×320 acotada en el centro, además de
los datos al iniciar reproducción. No se ejecutó la suite completa ni CI.

Evidencia posterior, separada de aquel corte: el smoke público previo registrado
en `build/artist-live-fetch.log` obtuvo Charly García (36031 bytes, dandrez,
CC BY-SA 2.0), Divididos (25352 bytes, Elemaki, CC BY 3.0) y Amy Winehouse
(41503 bytes, Rama, CC BY-SA 2.0 fr con jurisdicción y enlace `deed.en`).
Son respuestas públicas puntuales, no fixtures ni garantía de disponibilidad
futura. La captura existente `build/artist-live-preview.png`, observada en esta
revisión, muestra el retrato real de Charly, autor y enlaces de licencia/fuente
en Datos, con carátula ficticia central separada, árbol, separadores y footer
nativos conservados. Su registro indica selección nativa y una pista ficticia;
no prueba reproducción real ni accesibilidad, y se aprecia recorte del título
central. No se repitió aquí ese smoke público ni se generó otra captura.

Corrección posterior del falso positivo de identidad: se reprodujo el rojo de
Boston en `tests/artist-photos-tests.vala:207` (`photo should be NULL`, salida
134). El proveedor ahora exige, además del resumen estándar y título exacto,
una descripción inglesa con ocupación musical o tipo explícito de conjunto
cerca del inicio. Sin descripción o evidencia reconocida devuelve ausencia;
«music» genérico y heurísticas del archivo no bastan. Es un filtro conservador,
no prueba de identidad MusicBrainz ni cobertura universal. No se fuerzan
consultas de homónimos ni se añade arquitectura Wikidata; una categoría nueva
necesita adjudicación y evidencia. Se mantienen todos los controles remotos y
créditos existentes.

Evidencia ejecutada de esta corrección: caso focal Boston verde, **6/6 servicio
y 32/32 UI verdes**, mediante compilación de ambos ejecutables, ejecución focal
y `meson test -C build artist-photos ui --print-errorlogs`. Incluye cambio de
artista durante consulta fallida sin restaurar foto/créditos obsoletos. No se
editaron pruebas. Entorno UI igual al anterior, con avisos EGL/DRI3; logs en
`build/meson-logs/testlog.txt`. No se ejecutó core, suite completa ni CI remoto.

La consulta se dispara al seleccionar álbum o expandir artista y envía solo su
nombre a Wikipedia/Commons, no la biblioteca. La implementación cancela al
cambiar artista/cerrar, descarta respuestas obsoletas y conserva hasta doce
retratos en memoria por ventana, sin caché de disco. Próxima verificación:
cierre durante descarga, límites/reutilización de caché, otros fallos de red,
1024×600, texto grande, foco/activación de enlaces y lector en sesión real.
El filtro musical también requiere más escenarios antes de ampliar categorías;
el smoke anterior no certifica el filtro nuevo. No hay nueva evidencia
interactiva de tema o accesibilidad. **HIG NO APROBADO**.

## Incremento local: biblioteca conocida al reabrir sin fuente

En `fix/proportional-library-panel`, `Window` lee y guarda la caché de biblioteca
fuera del hilo GTK, incluidas carátulas y serialización. Muestra la instantánea
antes del escaneo y conserva navegación y reproducción mientras actualiza.
Los antecedentes incrementales corresponden exclusivamente a la misma URI;
la instantánea mostrada y los objetos mutados por Scanner son independientes.
Caché ausente/corrupta permite escanear; fallar al guardar no descarta pistas.
Con pistas conocidas, `NOT_MOUNTED` no dispara un diálogo de montaje automático;
el fallo conserva el aviso «No se pudo cargar la biblioteca. Revisá Preferencias.».
No se cambia composición, controles nativos, castellano ni separadores manuales.

Se consultó mediante HTTP la pauta oficial de
[progreso](https://developer.gnome.org/hig/patterns/feedback/progress-bars.html):
feedback inline y cancelación para tareas intensivas, sin ventanas nuevas de
progreso. Se conserva spinner y cancelación en Preferencias, sin porcentaje
inventado. Esto no demuestra adecuación para cargas largas no medidas.

Evidencia ejecutada: rojo de `meson test -C build ui --print-errorlogs`
con dos errores de compilación por el quinto argumento ausente de `Window`;
posteriormente caso focal de reapertura offline verde y **33/33 UI verdes**
con ese comando. El caso confirma persistencia, renombra solo el directorio
de audio y observa una pista conocida más el aviso existente al reabrir.
Entorno Meson: X11/Xvfb 1920×1080×24, Cairo, GSettings en memoria, GIO local,
`fakesink`, `GTK_A11Y=none`. Persisten advertencias de deprecación/C generado.
No se editaron tests ni `library.vala`; no se ejecutó core, suite completa o CI.

Próxima verificación: fuente SMB offline real sin montaje automático, latencia
con biblioteca y carátulas grandes, navegación/lectura durante actualización,
cancelación/cierre durante E/S de caché, fallo de escritura y caché corrupta,
además de teclado, lector, texto grande y 1024×600 en sesión real. La prueba
local offline no verifica autenticación ni accesibilidad; no se añaden monitores.
**HIG NO APROBADO**; las brechas previas permanecen pendientes.

## Incremento local: vigilancia automática de biblioteca

En `fix/proportional-library-panel`, los eventos GIO solicitan una reconciliación
incremental tras **1500 ms de quietud**, con una sola carga en vuelo y cambios
pendientes conservados. Scanner informa los directorios de su recorrido, también
los vacíos; Window instala en GTK un `GFileMonitor` por directorio, no por pista.
La raíz se vigila antes de leer caché/escaneo. Al instalar nuevas vigilancias se
hace otra pasada diferida para cubrir el intervalo sin monitor; una instantánea
visible idéntica no reconstruye la vista ni publica otra señal. Cada instantánea
aplicada emite `library_updated` desde GTK, después de actualizar la vista.

No cambia la composición ni los controles nativos/castellano/separadores. Se
intentan conservar álbum/artista, ramas abiertas y pista seleccionada por URI,
con su foco cuando sobreviven. No se cambia la cola ni se roba foco a Cancelar
en actualizaciones automáticas. El escaneo y la E/S de caché siguen en workers;
ordenar/reconstruir las listas modificadas sigue en GTK y no se ha medido para
bibliotecas grandes. Un fallo/cancelación del escaneo no guarda caché y la
escritura recibe cancelación; no revierte escrituras ya terminadas.

Se consultaron por HTTP las pautas oficiales de [progreso][monitor-progress]
y [teclado][keyboard]: se conserva el feedback/cancelación inline existente,
sin porcentaje inventado ni nuevas ventanas de progreso. La continuidad de
navegación y foco requiere prueba con teclado real; usar controles nativos y
restaurar selección por código no la certifica. No se añaden barras de progreso
ni notificaciones por cada evento: este incremento no introduce esos patrones.

Las fuentes no nativas, el fallo al crear monitores o la desaparición de un
directorio vigilado habilitan un fallback de **900 segundos**, más el debounce.
No es una garantía de latencia en SMB. Se cancelan los monitores y timers al
cerrar/cambiar de ubicación; el cierre cancela el escaneo. Los reintentos de
fondo no piden montaje interactivo. El coste estable es un monitor por directorio;
cada reconciliación enumera todas las entradas y lee/decodifica la caché completa,
pero reutiliza metadatos para no abrir audios intactos. La comparación de todos
los datos persistidos, incluidas huellas de audio/portada, ocurre en un worker:
si son idénticos, evita serialización INI/Base64 y escritura. Las copias ligeras
del escáner conservan la base sin mutaciones y comparten carátulas inmutables.
Una caché ausente/corrupta se reconstruye incluso para una biblioteca vacía;
una válida vacía puede conservarse. No hay sondeo rápido continuo con la
topología estable.

Evidencia local ejecutada: el rojo de compilación de `ui-tests` fue la ausencia
de `Window.library_updated` en `tests/ui-tests.vala:335`. Tras producción, pasó
`/ui/givenFileChangesInNewSubfolder_whenEventsSettle_thenLibraryRefreshesAutomatically`
y `meson test -C build ui core --print-errorlogs`: **34/34 UI y 15/15 core**.
El caso crea una carpeta/subcarpeta y copia dos WAV reales: observa 1 → 3 pistas
con una publicación; después elimina el WAV de la subcarpeta y observa 2 pistas
con la segunda publicación y sin filas duplicadas/obsoletas. Entorno: X11/Xvfb
1920×1080×24, Cairo, GSettings en memoria, GIO local, `fakesink`,
`GTK_A11Y=none`. Persisten advertencias de deprecación/C generado y avisos EGL/DRI3.
No se editaron tests ni se ejecutó la suite global o CI remoto.

Próxima verificación: SMB real y backend sin eventos, fallback transcurridos
15 minutos, ráfagas durante un escaneo lento, cancelación/cierre/cambio de
ubicación con eventos pendientes, raíz eliminada y recreada, directorios vacíos,
límites del sistema de watches y carga con bibliotecas/carátulas grandes.
Comprobar también foco/álbum/pista durante actualizaciones, reproducción y
navegación con teclado real, texto grande, lector y 1024×600. El caso automatizado
no garantiza esos escenarios, el hilo emisor mediante una aserción explícita ni
accesibilidad; las brechas previas siguen abiertas. **HIG NO APROBADO**.

Evidencia posterior del ahorro de escritura: el nuevo caso de `notes.txt`
reprodujo un ciclo de carga completo y cero publicaciones, pero cambió la fecha
de caché de `946684800` a `1794343949`. Tras producción, el caso focal pasó y
`meson test -C build ui core --print-errorlogs` terminó con **37/37 UI y 15/15
core**; el mismo ciclo conservó `946684800`. No se modificaron tests ni se
alteraron controles o composición visual; no hay nueva aprobación HIG ni
medición de rendimiento con bibliotecas grandes. Próxima verificación: caché
vacía ausente/corrupta, cambios solo de huellas con metadatos/imagen idénticos,
cachés antiguas y cancelación durante comparación/escritura. Estos casos
específicos no tienen evidencia nueva automatizada en este incremento.

## Corrección local: montaje solo por acción explícita

Actualización posterior al corte de biblioteca offline: el constructor inicia
una carga automática, igual que la vigilancia. Ninguna solicita montaje; solo
`NOT_MOUNTED` automático con pistas en caché omite además el toast y deja
«Ubicación sin montar. Se conserva la biblioteca anterior.» en Preferencias.
`NOT_FOUND` sigue mostrando el aviso existente. **Recargar** y **Aplicar y
cargar** permiten montaje aunque haya caché; las pistas permanecen visibles
mientras conecta. Se conserva `Gtk.MountOperation` con `PasswordSave.NEVER`.
Los fallos no llegan a aplicar resultados ni escribir caché, conservando
metadatos y carátulas conocidos. No cambia la composición ni los controles.

Se consultaron por HTTP las pautas oficiales de [toasts][toasts] y
[progreso][monitor-progress]: los primeros son transitorios, normalmente
responden a acciones y no representan estados persistentes. Se conserva
el feedback inline y Cancelar en Preferencias, sin porcentaje inventado ni
nuevas ventanas de progreso; esto no aprueba su accesibilidad.

Evidencia ejecutada en `fix/proportional-library-panel`: el rojo inicial de
`meson compile -C build ui-tests` tuvo dos errores por ausencia de los métodos
virtuales `scan_source` y `mount_source`. Al introducir las fronteras delegadas,
el caso nuevo falló en `tests/ui-tests.vala:316` por toast inesperado; al
silenciar solo el caso automático conocido, falló en la línea 321 por
`mount_calls == 0` frente a `1`. Tras habilitar el montaje manual pasó
`/ui/givenKnownUnmountedLibrary_whenAutomaticallyLoadedThenManuallyReloaded_thenOnlyManualLoadMountsWithoutHidingTracks`
con el ejecutable UI y el entorno Meson documentado arriba. Luego
`meson test -C build ui --print-errorlogs` terminó **38/38 UI verdes** (25,36 s),
incluida la reapertura con carpeta renombrada (`NOT_FOUND`) y su aviso. Los tests
permanecieron intactos. No se ejecutó core, la suite global ni CI remoto;
persisten advertencias de deprecación/C generado y EGL/DRI3 en Xvfb.

La prueba usa caché real y fronteras controladas de escaneo/montaje: observa
cero montajes automáticos, uno manual y una pista visible antes, durante y tras
el montaje. **No verifica SMB/GVfs real ni autenticación.** Próxima comprobación:
abrir una fuente SMB conocida sin montar y reconectar desde Recargar en una
sesión real, incluyendo cancelar/cerrar durante el diálogo, teclado y lector.
La semántica del arranque está cubierta por código, no por un escenario nuevo
que fuerce `NOT_MOUNTED` desde el constructor. El fallback anidado queda fuera
de este incremento, pendiente de su propio rojo. **HIG NO APROBADO**.

## Corrección local: recuperación de descendientes sin eventos raíz

Incremento posterior al corte anterior, en la misma rama: un error de carga
no cancelado habilita el fallback cuando hay ubicación vigilada, para no dejar
sin recuperación los descendientes que no alcanzaron a recibir monitores.
Los ticks no reinician un debounce pendiente ni agregan trabajo durante una
carga; se conservan la reconciliación única y el trabajo pendiente de eventos.
La cancelación mantiene su manejo separado, sin habilitar el fallback por sí
misma. No se modifican controles, composición, textos ni ajuste de columnas;
no hay nuevo patrón visual que evaluar ni se cierran pendientes HIG previos.

Evidencia ejecutada: tras `meson compile -C build ui-tests`, el caso
`/ui/givenCachedLibraryWithUnreadableNestedAlbum_whenAlbumRecoversWithoutRootEvents_thenFallbackRefreshesToTwoTracks`
reprodujo la espera agotada en `wait_until` (salida 134), después del log
`loading=false, tracks=1, cached=1, root events=0; waiting for nested recovery`.
El fixture prueba y drena un monitor raíz real antes de construir la ventana;
un álbum anidado sin permisos provoca el error conservando vista y caché.
Tras producción, el mismo caso pasó en **2,83 s** (3,02 s de proceso), restauró
permisos y descubrió/persistió una segunda pista sin Recargar ni eventos raíz.
Solo el intervalo virtual se configura a un segundo; producción conserva 900.
Los tests recibidos no se editaron ni se debilitaron aserciones.

Luego `meson test -C build ui --print-errorlogs` terminó **39/39 UI verdes**
(**28,67 s**), incluido cierre con cambios pendientes y cancelación de escaneo.
Entorno: X11/Xvfb 1920×1080×24, Cairo, GIO local, GSettings en memoria,
`fakesink` y `GTK_A11Y=none`; continúan los avisos de deprecación/C generado
y EGL/DRI3. Registro de la suite en `build/meson-logs/testlog.txt`.
No se ejecutó core, suite global ni CI remoto. No se añadió un escenario de
cancelación durante una recuperación con fallback ya activo: su semántica se
conserva por código, sin atribuirle cobertura nueva.

Próxima verificación: recuperación equivalente con SMB/GVfs real, cancelación
y cierre durante el reintento; revisar percepción del estado y del aviso con
teclado y lector en sesión real según [progreso][monitor-progress] y
[avisos][toasts]. Este caso local no demuestra autenticación, eventos remotos
ni accesibilidad; no aprueba HIG. **HIG NO APROBADO**.

[monitor-progress]: https://developer.gnome.org/hig/patterns/feedback/progress-bars.html

## Matriz inicial

Las rutas son relativas a la raíz. Cada próxima comprobación debe registrar
commit, entorno, resultado y límites; si falla, conservar el escenario como
regresión cuando sea automatizable.

| Área y pauta oficial | Estado y evidencia actual | Próxima verificación / condición de cierre |
| --- | --- | --- |
| Controles nativos y estilo: [header bars][header], [UI styling][style] | **Cubierto por código/test, parcial.** `src/window.vala`: `Adw.HeaderBar`, controles GTK, clases libadwaita y tooltips. `tests/ui-tests.vala`: `/ui/compact-footer-layout`, `/ui/footer-volume-group`. | Revisar ventana y Preferencias con tema claro/oscuro y accesibilidad; comprobar versiones mínimas GTK 4.10/libadwaita 1.4. La geometría del footer no valida toda la UI. |
| Activar una pista: [puntero/touch][pointer] aconseja evitar doble clic | **Cubierto por código/test, parcial.** `src/window.vala`: activación nativa con `activate_on_single_click = true` en pistas/cola, sin instrucción de doble clic. `/ui/single-activation-specific-track-and-queue` verifica la propiedad, activa la segunda pista mediante `Gtk.Widget.activate`, comprueba título/estado/selección/cola y activa otra entrada de cola. | Comprobar clic y toque físicos y activación con teclado real; el test de activación programática verifica el mapeo de filas, no inyecta eventos físicos ni prueba lector de pantalla. |
| Acciones inválidas: [botones][buttons] insensibles | **Cubierto por código/test, parcial.** `src/window.vala`, `update_player`/`show_tracks`: Play habilitado con pista actual o visible; Anterior/Siguiente según límites de la cola actual. `/ui/transport-empty-and-load-transitions`, `/ui/footer-keyboard-playback`, `/ui/current-track-survives-group-and-location-changes`, `/ui/transport-eos-queue-boundaries` y `/ui/playback-error-detail-in-preferences` verifican vacío/carga, foco que omite controles inválidos, navegación, filtro, cambio a ubicación vacía conservando pausa/retomar, EOS y fallo/reintento. Volumen sigue siendo ajustable sin música. | Repetir las transiciones con teclado y audio reales, contrastar foco visible y anuncios accesibles. Las aserciones de foco/activación son programáticas y el audio usa `fakesink`; no prueban accesibilidad integral. |
| Tamaños y paneles: [adaptación][adaptive], [utility panes][panes] | **Pendiente**, con recorte sin adaptación automática observado en `src/window.vala`, `panel_viewport` y `Gtk.Paned`. `tests/ui-tests.vala` prueba separadores a 1000×800/1280×800 y footer a 1280×800/1600×800, no 1024×600. | Probar escritorio **1024×600**, redimensionado ordinario y Preferencias: controles esenciales utilizables sin reparar manualmente separadores. Evaluar superposición del panel auxiliar con poco ancho. Mantener el ajuste manual no es infracción por sí mismo. **360×294** solo aplica si la app es apropiada para teléfono: alcance aún pendiente, no mandato automático. |
| [Teclado][keyboard] y [ventanas][windows] | **Pendiente**, con cobertura parcial: `/ui/footer-keyboard-playback` en `tests/ui-tests.vala` comprueba foco/activación programáticos del footer. No demuestra recorrido completo. | Usar solo teclado: biblioteca, pistas, Datos/Cola, separadores, Preferencias, selector de carpeta y errores; comprobar orden/visibilidad de foco, Ctrl+W y Esc en modal. Pueden ser heredados: no asumir ausencia por falta de código explícito. |
| [Nombres accesibles][names] | **Pendiente.** Hay etiquetas/tooltips en `src/window.vala`; GTK aporta algunos nombres por defecto. La ausencia de asignaciones explícitas no prueba que todos falten. | Inspeccionar árbol de accesibilidad y usar lector: nombres descriptivos de todos los elementos, listas, escalas y estados Play/Pausa. No certificar con `GTK_A11Y=none`. |
| [Pruebas de accesibilidad][a11y-tests] | **Pendiente.** `meson.build` usa Xvfb y `GTK_A11Y=none`; `tests/ui-tests.vala` usa `fakesink`. Claro/oscuro no cubre accesibilidad integral. | Sesión real con alto contraste, texto grande, teclado, lector y teclado en pantalla para todas las entradas. Registrar tareas completables y cualquier recorte, foco perdido o control sin anunciar. |
| [Redacción][writing] y [estados vacíos][empty] | **Cubierto por código/test, parcial.** `load_library`/`show_tracks`: singular/plural castellano para carga, omisión y selección. `/ui/no-status-row-summary-in-preferences`, `/ui/plural-library-and-selection-summary` y `/ui/empty-library-queue-and-load-failure-guidance` cubren 0/1/2, álbum/selección, resumen central vacío con guía a Preferencias y placeholder simbólico nativo de cola con guía contextual. El test distingue inicialmente vacío válido y fallo; `/ui/unavailable-location-and-recovery` conserva la biblioteca previa y el aviso genérico con detalle en Preferencias. Sin fila de estado superior. **Dos defectos P2 pendientes**, detectados por revisión independiente por lectura el 2026-10-25 sobre los cambios basados en `a920298`, ahora publicados en `7114a83`: (1) cancelar la carga automática inicial sin biblioteca detiene el spinner, pero deja «Leyendo biblioteca…» y la promesa de contenido; (2) tras fallar esa carga sin biblioteca, cambiar la agrupación llama a `show_tracks` vacío y reemplaza el error por «Biblioteca vacía» sin haber cargado con éxito; durante la carga también anuncia vacío prematuramente. | Añadir regresiones: (1) iniciar sin biblioteca, cancelar la carga automática y comprobar estado de cancelación coherente, sin promesa de carga activa; (2) fallar la carga inicial, cambiar la agrupación y comprobar que persiste el estado de error, no un vacío válido; cambiarla también durante la carga y comprobar que conserva el estado de carga hasta concluir. Resolver ambos antes de cerrar esta brecha; los 32 tests verdes actuales no los cubren. Revisar legibilidad, adaptación y anuncio de las guías con texto grande/lector y comprobar las tareas en una sesión real. No se cambió toda la redacción ni se afirma cobertura completa de mensajes; HIG no obliga a cambiar la app a inglés. |
| [Nombre][naming] e [icono de app][icons] | **Desviación observada / decisión pendiente.** «GTK Player» usa el nombre de otro proyecto, que HIG recomienda evitar; no es una prohibición genérica de términos técnicos. `data/io.github.gtkplayer.Player.desktop` usa `audio-x-generic`; `meson.build` no instala iconos propios. | Usuario elige nombre visible e identidad; luego verificar icono propio y versión simbólica instalados. No cambiar por esto el repositorio `gtkPlayer`. La carátula genérica interna no es el icono de identidad y puede permanecer. |
| [Menú principal][menus] | **Pendiente** decidir aplicabilidad: HIG dice que la mayoría de apps lo tienen. **No aplicable hoy:** reglas del icono de menú al botón engranaje actual, que abre Preferencias directamente en `src/window.vala`, no un menú. | Resolver convención sin inventar obligación universal. Si se incorpora menú principal, comprobar icono, etiqueta y elementos estándar, incluido Acerca de. |
| [Avisos][toasts] y [actividad][spinners] | **Cubierto por código/test, parcial; pendiente uso real.** `src/window.vala`: aviso genérico y detalle en Preferencias, spinner detenido en `finally`. `tests/ui-tests.vala`: recuperación de carga y `/ui/playback-error-detail-in-preferences`. | Verificar que el aviso sea percibido con Preferencias modal, teclado y lector; repetir error tras expirar el aviso. Widget mapeado no prueba visibilidad. Medir carga lenta: no exigir porcentaje sin conocer progreso. |

## Decisiones de producto y cierre

El objetivo de footer **≤96 px lógicos**, los **92 px observados** en el entorno
de prueba y los botones **34×34 px** descritos en el [README](../README.md) no
son medidas obligatorias de HIG ni garantías para texto grande/touch. No forzar
esas medidas si perjudican legibilidad o accesibilidad. Tampoco hace falta
implementar ahora persistencia del tamaño de ventana sin resolver si aplica
la recomendación condicional de restaurar una vista o contenido.

Regla general antes de integrar: resolver las desviaciones, completar las
comprobaciones aplicables y justificar las no aplicables; ampliar esta matriz
si aparecen otras pautas relevantes. La revisión debe contrastar comportamiento,
no marcar «usa GTK». Adjuntar evidencia automatizada y manual, sin sustituir
una por otra. Además se exige CI verde según
[ramas y releases](branches-and-releases.md): hay verde remoto de `7114a83`,
pero el futuro commit documental deberá obtener el suyo antes del bootstrap.

La excepción autorizada abarca solo la integración inicial de ese código más
este registro documental y su prerelease experimental con metadatos
provisionales. No cierra los dos P2 ni los pendientes de adaptación,
teclado/accesibilidad, identidad o licencia. Nombre/icono, titular y contacto
requieren decisión del usuario; publicar no concede permisos de redistribución.
Los artefactos CI no certifican HIG ni son paquetes finales aprobados para
distribución estable. Este documento registra la excepción, no ejecuta
operaciones remotas ni declara aprobación HIG; las próximas integraciones
conservan los gates generales.

[hig]: https://developer.gnome.org/hig/index.html
[header]: https://developer.gnome.org/hig/patterns/containers/header-bars.html
[style]: https://developer.gnome.org/hig/guidelines/ui-styling.html
[pointer]: https://developer.gnome.org/hig/guidelines/pointer-touch.html#general-guidelines
[buttons]: https://developer.gnome.org/hig/patterns/controls/buttons.html#general-guidelines
[adaptive]: https://developer.gnome.org/hig/guidelines/adaptive.html#small-size-handling
[panes]: https://developer.gnome.org/hig/patterns/containers/utility-panes.html#guidelines
[keyboard]: https://developer.gnome.org/hig/guidelines/keyboard.html#keyboard-navigation
[windows]: https://developer.gnome.org/hig/patterns/containers/windows.html#general-guidelines
[names]: https://developer.gnome.org/hig/guidelines/accessibility.html#accessible-names
[a11y-tests]: https://developer.gnome.org/hig/guidelines/accessibility.html#testing-for-accessibility
[writing]: https://developer.gnome.org/hig/guidelines/writing-style.html
[empty]: https://developer.gnome.org/hig/patterns/feedback/placeholders.html#guidelines
[naming]: https://developer.gnome.org/hig/guidelines/app-naming.html#what-to-aim-for
[icons]: https://developer.gnome.org/hig/guidelines/app-icons.html
[menus]: https://developer.gnome.org/hig/patterns/controls/menus.html#primary-menus
[toasts]: https://developer.gnome.org/hig/patterns/feedback/toasts.html
[spinners]: https://developer.gnome.org/hig/patterns/feedback/spinners.html

## Biblioteca visual y cola editable — 2026-11-10

Implementación local en `feat/visual-library-editable-queue`, sobre el árbol de
trabajo de `fix/proportional-library-panel`. Se conservaron los cambios previos
de biblioteca, caché, retratos y empaquetado. Este registro actualiza la evidencia
para esta rama; los cortes del código publicado y la excepción de bootstrap son
históricos y no cambian. **HIG NO APROBADO**.

| Incremento y pauta | Evidencia en esta rama | Próxima comprobación |
| --- | --- | --- |
| Cola y sesión: [listas][visual-lists], [botones][buttons], [avisos][toasts], [teclado][keyboard] | `src/queue.vala` separa identidad y URI, distingue la actual con texto y conserva anteriores. `src/session.vala` escribe la sesión atómica en un hilo, sin carátulas ni credenciales. `src/player.vala` conserva audio al editar otras entradas y recupera posición tras preparar el flujo. Los casos `/queue/edit-identity-clear-undo`, `/session/roundtrip-corruption-coalesced-writes`, `/player/queue-edit-preserves-audio`, `/player/remove-current-preserves-paused-state`, `/player/restored-position-after-preroll` y `/ui/queue-session-reopen-no-autoplay` pasaron. Vaciar conserva la actual y ofrece Deshacer en el aviso y en la cola. | Usar solo teclado y lector para activar entradas duplicadas, moverlas, quitarlas, vaciar y deshacer. Comprobar anuncio de la actual y del aviso; reabrir una sesión desde un dispositivo de audio real. |
| Arrastre, importación y fin de pista: [puntero/touch][pointer], [teclado][keyboard], [actividad][spinners], [avisos][toasts] | `Gtk.DragSource` y `Gtk.DropTarget` copian de la biblioteca, mueven por identidad y aceptan `Gdk.FileList`. Hay indicador de inserción y desplazamiento en el borde. `Scanner` prepara el lote fuera del hilo GTK, sin montaje y sin seguir enlaces. Pasaron `/import/ordered-cancellable-atomic-batch`, `/ui/queue-import-drop-and-cancel` y `/player/stop-after-current`. El caso opcional `/ui/native-pointer-drag-copy-move-files-escape` usó eventos X11 con `xdotool`: copió un álbum a cola vacía, importó desde otra ventana GTK con `Gdk.FileList`, movió la entrada y canceló con Escape sin insertarla. También verificó el foco de búsqueda con Ctrl+F. | Probar un gestor de archivos real en GNOME, carpetas, toque si está disponible y arrastre largo con desplazamiento e indicador antes/después. Confirmar menús, Alt+↑/↓, Supr, cancelación y resumen con teclado/lector. En un SMB de prueba: importar, reproducir, desconectar y reconectar; comprobar conservación de biblioteca/cola y ausencia de montaje automático. La segunda ventana GTK no reproduce todos los gestores ni Wayland. |
| Biblioteca visual: [grillas][visual-grid], [listas][visual-lists], [búsqueda][visual-search], [estilo][style], [nombres][names] | `src/browser.vala` y `src/window.vala` usan modelos con filas reutilizables. Álbumes es inicial; Artistas abre sus álbumes y la vista de detalle permite volver. Búsqueda visible para explorar bibliotecas grandes, con resultados al escribir y estado Sin resultados. Título, artista, duración y estado de cola tienen texto. Controles de icono y escalas tienen nombres accesibles explícitos. `/ui/visual-album-queue-actions-search-artwork`, los casos de álbumes homónimos y carátulas y la suite de retratos pasaron. | Medir latencia de búsqueda y desplazamiento con una biblioteca grande. Revisar tolerancia de búsqueda, foco al volver y al actualizar el contenido, anuncios accesibles y nombres de las filas y del estado Reproducir/Pausar. Las reglas de encabezados ordenables de ColumnView no aplican: las vistas muestran filas y portadas sin encabezados de ordenación. |
| Adaptación y estados: [paneles][panes], [adaptación][adaptive], [accesibilidad][a11y-tests], [vacíos][empty] | Dos separadores manuales en ancho amplio; por debajo de 1100 px lógicos se muestran paneles superpuestos. `/ui/adaptive-overlays-restore-proportions` verificó 1024×600, paneles y controles dentro de ventana y recuperación de ambas proporciones. Repitió geometría con Sans 18 y alto contraste forzado. `/ui/initial-empty-states-survive-navigation` observó cancelación inicial, cambio de vista durante carga y persistencia del error al navegar: corrige en esta rama los dos defectos P2 históricos de la matriz. | Revisar las tareas completas en escritorio real de 1024×600 con ajuste de texto del sistema, alto contraste, lector, teclado en pantalla y navegación sin puntero. Comprobar 1100 px alrededor del umbral, foco de paneles y arrastre de ambos separadores. No se certifica el alcance para teléfono ni se cambia la decisión de identidad. |

Verificación ejecutada en Ubuntu 26.04.1 amd64, GTK 4.22.4, libadwaita 1.9.1,
GStreamer 1.28.2, Vala 0.56.18. `meson compile -C build` y
`GTKPLAYER_TEST_POINTER=1 GTKPLAYER_TEST_COLOR_SCHEME=light GIO_USE_VFS=local dbus-run-session -- meson test -C build --print-errorlogs`:
**74/74 casos** (23 core, 45 UI y 6 retratos). Los **45 UI** pasaron también con
`GTKPLAYER_TEST_COLOR_SCHEME=dark`. Se ejecutó aparte el caso de adaptación con
`ADW_DEBUG_HIGH_CONTRAST=1` y se inspeccionaron las capturas de 1024×600 con texto
normal y grande. Los ensayos UI usan Xvfb, Cairo, GSettings en memoria,
`GTK_A11Y=none` y `fakesink`. La evidencia local está en
`build/verification-{light,dark,high-contrast}.log` y
`build/hig-preview-1024*.png`. La revisión de geometría no verifica un lector
ni una sesión GNOME interactiva; la prueba de retratos usa un servidor local.

`dpkg-checkbuilddeps`, la preparación de archivos en DESTDIR y
`dpkg-buildpackage -us -uc -b` en una copia temporal terminaron correctamente.
El empaquetado volvió a pasar los 74 casos con la prueba X11 habilitada. Se
comprobaron Package/Version/Architecture (`gtkplayer`, `0.1.0`, `amd64`), el
contenido del `.deb`, `desktop-file-validate` y `--help` de los binarios preparado
y extraído. Artefacto y SHA-256 locales en `build/package-check.cJalBk/`; logs
`build/verification-{stage,deb-build,deb-inspection}.log`. No se instaló el
paquete; el build local no sustituye CI remoto ni prueba Ubuntu 24.04.

Se comprobó además una muestra de SMB **real** sobre el montaje GVfs existente:
una pista importada por GIO, URI `smb://` conservada y más de 200 ms de avance
con decodificación a `fakesink` (`build/verification-smb.log`). Se usó el
escáner y el reproductor de esta rama en un ejecutable temporal, en lectura.
No se cambió el montaje ni la configuración del NAS. Quedan pendientes la
interrupción y reconexión de un recurso SMB de prueba, la salida de audio física
y las comprobaciones interactivas de accesibilidad. No hay aprobación HIG,
integración, push ni release de este incremento.

[visual-grid]: https://developer.gnome.org/hig/patterns/containers/grid-views.html
[visual-lists]: https://developer.gnome.org/hig/patterns/containers/list-column-views.html
[visual-search]: https://developer.gnome.org/hig/patterns/nav/search.html
