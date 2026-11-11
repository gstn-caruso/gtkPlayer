# GTK Player

Reproductor nativo para Linux escrito en Vala, GTK 4, libadwaita y GStreamer.
Carga música de una carpeta local o SMB. La columna izquierda alterna entre
Álbumes, con carátulas, y Artistas, con retratos. El centro muestra la grilla
de álbumes o las canciones del álbum abierto. La cola editable queda a la
derecha y los controles de reproducción abajo.

## Requisito obligatorio: GNOME HIG

La aplicación debe cumplir las [GNOME Human Interface Guidelines](https://developer.gnome.org/hig/index.html)
según las directrices aplicables a su alcance. El stack Vala + GTK 4 + libadwaita
no demuestra por sí solo ese cumplimiento. **Estado: NO APROBADO**; hay
desviaciones y comprobaciones pendientes en la [matriz HIG](docs/gnome-hig.md).
La regla general bloquea merge y release hasta resolverlas y contar con CI
verde del árbol a integrar. El usuario autorizó una
[excepción puntual de bootstrap y prerelease experimental](docs/branches-and-releases.md#excepción-puntual-autorizada-y-plan-pendiente),
no una aprobación HIG. Al corte del **2026-10-25, previo a la primera integración**,
el [run CI 40239813173](https://github.com/gstn-caruso/gtkPlayer/actions/runs/40239813173)
terminó **SUCCESS** para el código ya publicado
`7114a837e47d2e1cb42a4ee5f68481f497304c2b` (32 tests: 11 core y 21 UI;
build/paquete exitoso, release omitido). El futuro commit documental aún necesita
su propio CI verde; integración y prerelease no están ejecutados en ese corte.
Ver también [las instrucciones del proyecto](AGENTS.md).

## Usar la biblioteca

La ubicación inicial editable es `smb://nas.local/public/multimedia/Música`.
También se admiten rutas locales y URI `file://`. Para NFS, usá una ruta ya
montada por el sistema: la aplicación no monta NFS ni admite URI `nfs://`.
Al abrir la aplicación se carga automáticamente la ubicación recordada (o la
inicial si todavía no hay configuración). Esto puede acceder al NAS, pero nunca
inicia la reproducción por sí solo. La ventana principal no muestra la URI ni
controles de carga: abrí **Preferencias** con el botón del encabezado para editar
la ubicación o elegir una carpeta. **Aplicar y cargar** guarda la elección y
carga su contenido; **Recargar** vuelve a leer la ubicación guardada. Cerrar
Preferencias sin aplicar descarta la edición.

Se recorre la carpeta de forma recursiva sin seguir enlaces simbólicos. Si hay
una caché para esa ubicación, aparece antes de iniciar el escaneo; el resultado
actualizado reemplaza esa instantánea al terminar, no de manera progresiva.
La lectura y escritura de caché (incluidas carátulas) se realizan fuera del hilo
GTK. Se puede seguir navegando y reproduciendo las pistas conocidas durante
la actualización; una fuente offline conserva la instantánea. La carga al abrir
y los reintentos automáticos no solicitan montaje. Si reciben `NOT_MOUNTED` con
pistas en caché, tampoco muestran un aviso transitorio: el estado queda en
Preferencias. **Recargar** y **Aplicar y cargar** sí pueden solicitar montaje,
aunque existan pistas conocidas, que siguen visibles mientras se conecta.
Otros errores, como `NOT_FOUND`, conservan el aviso de carga existente.
Durante el escaneo,
los controles de ubicación se deshabilitan y **Cancelar escaneo** está disponible
solo en Preferencias. Los conteos de pistas cargadas y archivos omitidos, el
estado de carga, la cancelación y el fin de cola se consultan allí: no hay una
fila de estado ni espacio reservado debajo del encabezado principal. El resumen
del álbum o selección y su contador de pistas permanecen en el panel central.
Si la ubicación no está disponible, se conserva la biblioteca anterior. Los
demás errores de carga, guardado y reproducción muestran un aviso nativo transitorio,
sin rutas ni URI, sobre los paneles y sin tapar los controles inferiores; el
detalle completo queda en Preferencias.
Una ubicación válida queda guardada aunque falle la lectura; una URI inválida
se rechaza sin modificar la configuración ni la biblioteca. Si no se puede
guardar, no se inicia la carga de esa elección. La biblioteca vacía orienta a
Preferencias. La carga, la cancelación, el error y la ausencia de resultados
conservan mensajes distintos al cambiar entre Álbumes y Artistas.
Los conteos distinguen singular y plural, por ejemplo «1 pista cargada · 1 archivo de audio omitido».

SMB utiliza GIO/GVfs y el diálogo de autenticación del sistema. Se necesita
`gvfs-backends` y una sesión de escritorio con sus servicios disponibles.
No incluyas usuario, contraseña ni dominio de autenticación en la URI: se
rechazan URI con `userinfo`. No guardes credenciales en archivos del proyecto,
comandos, variables persistentes ni Git. La aplicación solicita no guardar la
contraseña; los montajes o credenciales previamente gestionados por el sistema
son independientes. Solo se recuerda la ubicación al aplicar Preferencias, en
`$XDG_CONFIG_HOME/gtkplayer/settings.ini` (normalmente
`~/.config/gtkplayer/settings.ini`). La biblioteca se persiste por URI en
`$XDG_CACHE_HOME/gtkplayer` (normalmente `~/.cache/gtkplayer`), en archivos INI
nombrados con SHA-256 de la URI. Incluye metadatos, huellas de tamaño/fecha y
carátulas, no el audio. Al guardar, las carátulas idénticas se almacenan una sola
vez por contenido, con referencias a su identificador SHA-256 desde las pistas;
al cargar, cada imagen referenciada se decodifica una vez y comparte sus `Bytes`
inmutables, sin transformar los bytes originales. Esto ahorra espacio y memoria
cuando varias pistas usan la misma portada. Se siguen leyendo las cachés anteriores
con portada inline; si los datos no cambian, no se fuerza su migración.
`Window` permite inyectar otro directorio de caché con
su quinto argumento opcional `cache_path`. La caché ausente o corrupta no
impide escanear y un fallo al guardarla no descarta la biblioteca cargada.
El escáner recibe solo antecedentes de la misma URI y reutiliza metadatos sin
cambios según sus huellas.

La biblioteca se actualiza automáticamente mediante `GFileMonitor`: un monitor
por directorio descubierto, incluidas carpetas vacías, no por pista. La raíz se
vigila antes de escanear; los demás directorios proceden del mismo recorrido del
escáner, sin otro recorrido dedicado a descubrir monitores. Se instalan en el
hilo GTK al finalizar el escaneo y se retiran los directorios desaparecidos.
Los eventos se agrupan tras **1500 ms de quietud**. Solo hay una reconciliación
en vuelo; los cambios recibidos durante ella quedan pendientes para otra pasada.
Al instalar monitores nuevos se programa una pasada adicional para cubrir el
intervalo entre enumeración e instalación; si la instantánea visible no cambia,
no se reconstruye la vista ni se emite `library_updated`. La señal se emite en
GTK después de aplicar una instantánea, nunca por evento bruto.

En fuentes no nativas (como SMB), si falla crear un monitor, desaparece un
directorio vigilado o falla la carga antes de completar la vigilancia de sus
descendientes, se habilita además un fallback de **900 segundos** mientras
esa ubicación esté activa. Cada tick solicita la misma reconciliación con
debounce solo si no hay carga en vuelo ni trabajo pendiente: no reinicia la
espera ya programada, incluso con un intervalo menor que los 1500 ms. No es un
plazo exacto de actualización ni una garantía de eventos de red. Cancelar no
habilita por sí mismo el fallback. Los reintentos automáticos no abren diálogos de montaje. Cerrar la ventana
o cambiar de ubicación cancela monitores y temporizadores anteriores; cerrar
cancela también el escaneo. **Recargar** sigue disponible como recuperación manual.

Cada reconciliación enumera el árbol completo y consulta huellas, pero evita
abrir audios intactos. Lee la caché completa (incluida la decodificación de
carátulas) una vez en un worker; compara por URI todos los datos persistidos,
incluidas huellas de audio y portada, en otro worker. Si no cambian, evita la
serialización INI, codificación Base64 y escritura completas, aunque cambie el
orden de enumeración. El escáner usa copias ligeras de las pistas y comparte
solo los bytes inmutables de carátulas, sin alterar la base de comparación.
Con cambios, incluso solo de huellas, se guarda la caché completa; una caché
ausente o corrupta se reconstruye tras un escaneo correcto, también si queda
vacía. Las cachés antiguas sin huellas se reanalizan y actualizan al obtenerlas.
El coste de monitores escala con directorios y el de enumeración con entradas,
no hay sondeo rápido continuo. Un fallo o cancelación del escaneo no guarda
caché; la comparación y escritura reciben la misma cancelación, que no revierte
una escritura ya terminada. Durante una actualización
automática se intenta restaurar artista, álbum abierto y pista seleccionada
por URI si aún existen; la cola y reproducción no se reemplazan. Queda por
verificar el foco durante la reconciliación en una sesión de escritorio.
No se roba foco hacia Cancelar por una carga automática. No es actualización
fila a fila: ordenar/reconstruir una vista modificada todavía ocurre en GTK.

Evidencia local de recuperación anidada: el caso
`/ui/givenCachedLibraryWithUnreadableNestedAlbum_whenAlbumRecoversWithoutRootEvents_thenFallbackRefreshesToTwoTracks`
reprodujo el timeout conservando una pista en vista/caché y cero eventos raíz;
tras la corrección pasó en 2,83 s (3,02 s incluido el proceso). Usa archivos y
permisos locales reales, prueba y drena el monitor raíz antes de abrir la ventana
y sobrescribe solo el intervalo de fallback a un segundo. Al recuperar permisos,
observa dos pistas visibles y persistidas sin Recargar ni eventos raíz.
`meson test -C build ui --print-errorlogs`: **39/39 UI verdes**, 28,67 s,
con X11/Xvfb, Cairo, GIO local, GSettings en memoria, `fakesink` y
`GTK_A11Y=none`. No se ejecutó la suite global ni se verificó SMB real,
autenticación o accesibilidad; **HIG NO APROBADO**.

## Explorar y editar la cola

Buscá por título, artista o álbum con **Ctrl+F**. En la columna izquierda,
desplegá un álbum para ver sus canciones debajo o un artista para ver sus
álbumes. También podés desplegar esos álbumes hasta llegar a las canciones.
Activar el nombre de un álbum abre sus pistas en el centro y activar el
nombre de un artista muestra su grilla de álbumes. La flecha permite plegar
o desplegar la rama. El menú central incluye **Ver todas las pistas**. Al
activar una canción, se inserta después de la actual y empieza a sonar.
Las entradas previas y pendientes quedan disponibles. Al activar una entrada
de la cola se reproduce esa misma entrada.

El menú de cada canción o álbum ofrece **Agregar a la cola**, **Reproducir a
continuación** y **Reproducir ahora**. Agregar mantiene el orden de las pistas
y deja la reproducción detenida si todavía no empezó. La misma canción puede
aparecer varias veces. Usá el menú de una entrada para moverla arriba, abajo o
quitarla. Con el foco en la cola también podés usar **Alt+↑**, **Alt+↓** o
**Supr**. Quitar la actual pasa a la siguiente si existe y conserva el estado de
reproducción o pausa. **Vaciar cola** conserva la actual; **Deshacer** o
**Ctrl+Z** recuperan el orden anterior hasta que vuelvas a editarla.

Arrastrá canciones o álbumes a la cola para copiarlos, o arrastrá una entrada
para cambiar su posición. **Escape** cancela el arrastre interno. También podés
soltar archivos o carpetas accesibles desde el gestor de archivos, o agregarlos
con los botones de la cola. Se respeta el orden de las fuentes recibidas; cada
carpeta se recorre sin seguir enlaces simbólicos y se ordena por artista, álbum,
número de pista, título y URI. La importación muestra actividad y el total de
archivos omitidos. Cancelar descarta todo el lote; si una fuente es inaccesible,
se informa el error sin solicitar montaje ni cambiar la ubicación configurada.

En el menú del reproductor podés elegir **Detener al terminar esta canción**.
Pausar conserva esa opción; detener o cambiar de canción la desactiva. Los
errores detienen la reproducción y se detallan en Preferencias.

La cola, la entrada actual y el tiempo transcurrido se guardan en
`$XDG_CONFIG_HOME/gtkplayer/session.ini`, separado de Preferencias y de la
caché de biblioteca. El guardado es atómico y se hace fuera del hilo GTK.
No incluye audio, carátulas ni credenciales. La sesión se abre sin reproducir
ni montar la fuente; al darle a Reproducir se busca la posición guardada.
Una sesión ilegible abre con la cola vacía.

## Retratos públicos de artistas

La pestaña **Artistas** consulta Wikipedia y Wikimedia Commons para obtener
retratos de los nombres visibles en la lista, de a uno. Las consultas envían
nombres de artistas. Al activar la miniatura se muestran el autor y los
enlaces a la licencia y a Wikimedia Commons. Cuando falta un retrato válido
se muestra un avatar genérico y la navegación sigue disponible.

La caché guarda solo en memoria hasta doce retratos por ventana; no escribe
fotos en disco ni persiste entre sesiones. Se cancelan las consultas al
cerrar la vista de Artistas o la ventana. Las filas reutilizadas descartan
respuestas que pertenecen a otro artista.

El proveedor exige resumen Wikipedia estándar, título coincidente y una
descripción con ocupación musical explícita (por ejemplo singer, songwriter,
musician, composer o rapper) o tipo de conjunto (rock band, jazz band,
musical group u orchestra). Es un filtro conservador de la descripción inglesa,
no una prueba de identidad MusicBrainz ni cobertura universal: sin descripción,
con ambigüedad o sin esa evidencia se omite el retrato. La palabra genérica
«music», el nombre del archivo o una licencia libre no bastan. No se fuerzan
consultas alternativas de homónimos; nuevas categorías requieren adjudicación
con evidencia antes de ampliar el filtro. Se conservan además los controles de
HTTPS/dominios, redirecciones, tamaño, formato, archivo Commons y licencia.

## Ancho de las columnas

Arrastrá cualquiera de los dos separadores nativos para dar más o menos ancho
a Biblioteca, pistas o Cola. Se pueden estrechar hasta casi colapsarlas:
el límite es el espacio de la ventana y el ancho físico de los separadores,
no un mínimo impuesto por el texto. El contenido que no entra queda recortado
sin invadir la columna vecina; arrastrá el separador de vuelta para recuperarlo.
En ventanas de menos de 1100 px lógicos, Biblioteca y Cola se abren como
paneles superpuestos desde el encabezado. **F9** abre y cierra la cola en
ese modo. Al volver a una ventana amplia,
se recupera la proporción elegida para ambos separadores. El ajuste no se
guarda al cerrar.

## Barra inferior nativa

La barra muestra la carátula, el título y el artista de la pista actual, con
transporte centrado, tiempos a ambos lados del progreso y volumen a la derecha.
Si no hay carátula válida se muestra el icono genérico. El texto largo se elide.
Anterior y Siguiente se habilitan según la posición en la cola. Podés reanudar
aunque haya cambiado la ubicación o la vista de biblioteca. Con biblioteca y
cola vacías, el volumen sigue disponible.

Para el footer se consultaron las guías oficiales de GNOME sobre
[botones](https://developer.gnome.org/hig/patterns/controls/buttons.html),
[puntero/touch](https://developer.gnome.org/hig/guidelines/pointer-touch.html),
[teclado](https://developer.gnome.org/hig/guidelines/keyboard.html),
[tooltips](https://developer.gnome.org/hig/patterns/feedback/tooltips.html) y
[estilo adaptable](https://developer.gnome.org/hig/guidelines/ui-styling.html).
Esto no equivale a aprobación HIG: la [matriz](docs/gnome-hig.md) registra
las desviaciones y la cobertura limitada.
La compatibilidad de las clases se contrastó con la
[fuente etiquetada 1.4.0](https://gitlab.gnome.org/GNOME/libadwaita/-/raw/1.4.0/doc/style-classes.md).
**96 px lógicos es nuestro objetivo de producto, no una regla HIG.** En Xvfb,
con fuentes estándar, la ocupación bajó de 127 a 92 px a 1280×800, incluidos
los márgenes. También se verificaron 92 px a 1600×800; los botones mantienen
blancos de 34×34 px. Los 21 tests UI
pasan en claro y oscuro. La ejecución se realizó con GTK 4.22/libadwaita 1.9;
no se ejecutó con las versiones mínimas. No se certifican fuentes grandes,
alto contraste, lector de pantalla ni una auditoría completa de accesibilidad.

Se pueden repetir las capturas de la ventana de **test local**, con `fakesink`,
sin abrir la aplicación real ni tocar el tema/configuración del escritorio:

```sh
GDK_BACKEND=x11 GSETTINGS_BACKEND=memory GTK_A11Y=none GSK_RENDERER=cairo \
GIO_USE_VFS=local GTKPLAYER_TEST_COLOR_SCHEME=light \
GTKPLAYER_TEST_CAPTURE="$PWD/build/footer-light.png" \
xvfb-run -a -s '-screen 0 1920x1080x24' ./build/ui-tests
```

Para oscuro, usar `GTKPLAYER_TEST_COLOR_SCHEME=dark` y otra ruta de captura.
`build/` está ignorado; las capturas no son la pantalla real del usuario.

## Compilar, probar y ejecutar

Herramientas: compilador C, Vala, Meson >= 1.0, Ninja y pkgconf.
Bibliotecas de desarrollo: GLib/GIO, GTK 4 >= 4.10, libadwaita >= 1.4,
GStreamer, GStreamer pbutils, libsoup 3 y JSON-GLib. No se usa libgee.
En Debian/Ubuntu, los nombres exactos de paquetes requeridos están en
[`debian/control`](debian/control), sección `Build-Depends`.
Los tests además necesitan FFmpeg, plugins GStreamer base/good, Xvfb y xauth;
el empaquetado usa debhelper 13 y `dbus-run-session` de `dbus-daemon`.
Las comprobaciones de instalación y paquete necesitan además
`desktop-file-utils` (para `desktop-file-validate`) y `lintian`.
No se descargan ni instalan dependencias con los siguientes comandos:

```sh
meson setup build --prefix=/usr
meson compile -C build
meson test -C build --print-errorlogs
./build/gtkplayer
```

Si `build` ya existe, usá `meson setup --reconfigure build --prefix=/usr`.
El test UI inicia Xvfb y define `GDK_BACKEND=x11` desde Meson, sin necesitar
exportarlo manualmente. Para una sesión D-Bus aislada, sin backends de red en
los tests:

```sh
GIO_USE_VFS=local dbus-run-session -- meson test -C build --print-errorlogs
```

La comprobación opcional de arrastre usa `xdotool` bajo Xvfb. Si ya está
disponible, ejecutala con `GTKPLAYER_TEST_POINTER=1 meson test -C build ui
--print-errorlogs`. La [matriz HIG](docs/gnome-hig.md#biblioteca-visual-y-cola-editable--2026-11-10)
registra los resultados de esta rama y las comprobaciones que faltan en una
sesión de escritorio.

Además de las suites core y UI, `meson test -C build artist-photos --print-errorlogs`
ejecuta **seis casos offline** con servidor loopback controlado: bytes y
atribución, título canónico de archivo, licencia sin barra final, licencia con
jurisdicción, rechazo de redirecciones y rechazo de la ciudad Boston pese a
título exacto e imagen libre. La suite UI tiene **45 casos** (uno de arrastre X11 opcional), incluida la actualización automática local de
1 → 3 → 2 pistas al crear carpetas anidadas y copiar/eliminar WAV reales, con
una publicación para la ráfaga y otra para la eliminación, y la reapertura con
fuente offline y persistencia real en un directorio de caché aislado, además de
los créditos de la miniatura, la carátula del álbum y el filtrado de artistas
durante una descarga sin recuperar la foto anterior. Estas suites no
consultan Wikimedia real. El smoke público de Charly García, Divididos y Amy
Winehouse y la captura de Charly se registran por separado en la
[matriz HIG](docs/gnome-hig.md); no sustituyen regresiones offline ni certifican
identidades futuras, caché, cierre durante descarga o accesibilidad.
En el incremento de monitores se ejecutaron el caso focal, **34/34 UI y
15/15 core**; no la suite global ni CI remoto. Ese caso no mide recursos con
bibliotecas grandes ni verifica fallback de 15 minutos, SMB, eventos durante
escaneo, cancelación de monitores o conservación de foco/álbum bajo actualización.
La suite core contiene 23 casos. Las suites cubren lectura de metadata FLAC
local, metadata sintética sin atributo opcional de enlace, recursión y enlaces,
errores y cancelación inicial, límites de cola,
fin de pista/avance, controles básicos, activación de la ventana con cuatro
zonas y sin entrada de URI, carga automática local sin reproducción, aplicación
y persistencia desde Preferencias, reapertura, rechazo de URI inválida y
credenciales, cierre sin aplicar, recuperación ante ubicación indisponible,
fallo de guardado, error de reproducción con detalle en Preferencias y reintento,
cancelación de escaneo y cierre durante una carga o reproducción sin actualizar
los controles al cerrar. Verifican que no haya fila de estado ni hueco entre
encabezado y paneles, que los conteos de carga/omisión estén en Preferencias y
que los errores transitorios no expongan rutas ni URI. Cubren los conteos 0/1/2,
la guía de biblioteca y cola vacías y su diferencia con un fallo de carga.
Comprueban la propiedad nativa de activación con un clic y el resultado de activar
programáticamente una pista no inicial y otra entrada de cola, no un clic/toque
físico. También cubren sensibilidad del transporte al cargar/vaciar, límites de
cola, omisión de controles inválidos en el foco, filtro de grupos, conservación
de pausa/retomar al cambiar a una ubicación vacía, EOS y error/reintento.
Incluyen geometría real del footer tras layout,
centrado, texto largo sin solapamientos, agrupación de volumen, orden de foco,
activación de transporte, actualización de título/tiempos y seeking con fakesink.
También prueban la asignación geométrica de ambos separadores a 1280×800 y
1000×800, paneles de 4–5 px, extremos completos y restauración conservando los
datos, sin ensanchar la ventana. No simulan arrastre físico con el ratón.
Cada ventana de test recibe una configuración local preparada antes de crearse;
no se usa la configuración personal ni se accede al NAS.
El test pausa/seek/volumen **no prueba completamente las transiciones** de
reproducción ni la salida de audio real: usa `fakesink`. No certifican acceso
SMB, autenticación, todos los codecs ni comportamiento en una máquina limpia.

## Instalación de prueba sin tocar el sistema

```sh
stage=$(mktemp -d /tmp/gtkplayer-install.XXXXXX)
meson install -C build --destdir "$stage"
test -x "$stage/usr/bin/gtkplayer"
desktop-file-validate "$stage/usr/share/applications/io.github.gtkplayer.Player.desktop"
"$stage/usr/bin/gtkplayer" --help
```

Se instalan `/usr/bin/gtkplayer` y el lanzador
`/usr/share/applications/io.github.gtkplayer.Player.desktop`, coherente con el
app ID `io.github.gtkplayer.Player`. Usa el icono genérico del tema
`audio-x-generic`.

## Construir el paquete Debian local

Formato fuente nativo `3.0 (native)`, versión inicial `0.1.0`.
El siguiente procedimiento construye en un directorio temporal: los archivos
que `dpkg-buildpackage` crea en el directorio padre no contaminan `~/Code`.
Requiere `rsync` y las dependencias de construcción ya disponibles.
Ejecutar desde la raíz del proyecto:

```sh
dpkg-checkbuilddeps
work=$(mktemp -d /tmp/gtkplayer-package.XXXXXX)
mkdir "$work/gtkplayer"
rsync -a --exclude=/.git/ --exclude=/build/ --exclude='/build-*/' \
  --exclude=/dist/ --exclude='/obj-*/' ./ "$work/gtkplayer/"
(cd "$work/gtkplayer" && dpkg-buildpackage -us -uc)
mkdir -p dist
cp "$work"/*.deb dist/
sha256sum dist/*.deb
printf 'Árbol temporal y diagnóstico: %s\n' "$work"
```

No se instala el paquete ni se firma/publica. `dist/` está ignorado por Git.
Puede producirse también un paquete de símbolos `gtkplayer-dbgsym`.
Las dependencias enlazadas se calculan mediante `${shlibs:Depends}`; se añaden
plugins GStreamer base/good y GVfs SMB que no se detectan por enlace dinámico.
`gstreamer1.0-libav` es recomendado para más codecs. La selección de archivos
admite FLAC, MP3, Ogg, Opus, WAV, M4A, AAC, WMA y AIFF, pero su decodificación
depende de los plugins instalados: no se garantiza cada formato.

**El .deb es de enlace dinámico y para la distribución donde se construye;
no incluye un runtime ni es universal para Debian/Ubuntu.** En este entorno
se comprobó la construcción sobre Ubuntu 26.04.1 amd64. GTK >= 4.10 y
libadwaita >= 1.4 también limitan las distribuciones de destino.
No se comprobó instalar el paquete en el sistema ni en otra distribución.

Para inspeccionar y comprobar el ejecutable extraído (sin instalación):

```sh
package=dist/gtkplayer_0.1.0_amd64.deb # ajustar versión/arquitectura si cambia
# Inspección de metadata y contenido
dpkg-deb --info "$package"
dpkg-deb --contents "$package"
lintian "$package"
unpack=$(mktemp -d /tmp/gtkplayer-unpack.XXXXXX)
dpkg-deb --extract "$package" "$unpack"
test -x "$unpack/usr/bin/gtkplayer"
desktop-file-validate "$unpack/usr/share/applications/io.github.gtkplayer.Player.desktop"
"$unpack/usr/bin/gtkplayer" --help
```

`--help` comprueba el arranque del ejecutable con el loader y las bibliotecas
del host, no reproducción, integración de escritorio ni instalación.
Lintian informó `copyright-without-copyright-notice` (titular pendiente) y
`no-manual-page`; no se afirma que el paquete esté libre de advertencias.

## Límites y pendientes

- La sesión recuerda una sola cola. No hay gestión de playlists ni recientes. Las carátulas locales
  se leen de metadata incrustada o `cover.jpg`; los retratos públicos son independientes.
- Los álbumes se agrupan por álbum **y artista de pista**: las compilaciones se
  separan por artista. No se usa artista de álbum ni número de disco.
- No hay caché persistente de retratos públicos. Los monitores dependen del
  backend GIO y de los límites de watches del sistema; el fallback remoto no
  garantiza inmediatez. Falta medir bibliotecas grandes, pérdidas de eventos,
  cambios concurrentes, foco/selección y recuperación de red en sesión real.
  Cancelar durante discovery puede esperar al timeout de hasta 5 segundos del
  archivo actual; la serialización de caché en curso termina en su hilo, aunque
  la sustitución del archivo recibe la cancelación. No se puede deshacer una
  escritura que ya terminó antes de cancelar.
- Las pruebas de reproducción no validan completamente pausa/seek/volumen.
- Acceso efectivo al NAS y autenticación SMB no comprobados por este empaquetado.
- Hay una advertencia Vala preexistente sobre `Music.Track[]` como propiedad de
  `GLib.Object`; no se cambió el código del reproductor en el empaquetado.
- **Licencia, autor/titular y contacto del mantenedor pendientes de confirmar.**
  `debian/copyright` no concede permisos y `debian/control` usa un contacto
  placeholder explícito. La publicación de fuente en desarrollo autorizada por
  el usuario no implica una licencia open-source ni concede permisos de
  redistribución a terceros. La excepción puntual permite solo el prerelease
  experimental autorizado con metadatos provisionales, sin resolver estos datos
  ni aprobar distribución estable; fuera de ella no publicar hasta resolverlos.

## Ramas y releases

Ver [la guía de contribución e integración](docs/branches-and-releases.md).
El repositorio [gstn-caruso/gtkPlayer](https://github.com/gstn-caruso/gtkPlayer)
es público y tiene `origin` configurado. Al corte previo a la primera integración
(2026-10-25), `feat/ci-hig-readiness` tiene publicado `7114a83`, con el CI verde
citado arriba y 32 tests locales verdes reportados; no cubren los dos defectos P2.
El [run anterior de 26 tests](https://github.com/gstn-caruso/gtkPlayer/actions/runs/40237594338)
para `a920298` es evidencia histórica, no el CI actual. No se instaló el paquete.

El usuario autorizó **solo la integración inicial de `7114a83` más este registro
documental y su prerelease experimental con metadatos provisionales**, manteniendo
HIG no aprobado e identidad/licencia/titular/contacto pendientes. El plan aún no
ejecutado al corte es hacer commit/push documental, esperar CI verde de ese SHA
y crear/publicar `main` desde ese HEAD: no existe `main` local/remoto en ese corte,
por lo que es un bootstrap sin PR de destino ni merge commit fabricado. Las
siguientes integraciones requieren encargo y el flujo normal PR/revisión/HIG/CI.

El [workflow](.github/workflows/ci.yml) construye y prueba sobre Ubuntu 24.04 amd64
(GTK 4.14/libadwaita 1.5), sin demostrar las versiones mínimas absolutas ni
compatibilidad universal. En `feat/**`, `fix/**` y PR hacia `main` solo adjunta
`.deb` de prueba y SHA-256 como artefacto CI. El push autorizado a `main` deberá
pasar build/tests/paquete antes de publicar su prerelease
`v0.1.0+git<RUN_NUMBER>.<SHA12>` del SHA integrado. Después se comprobarán tag,
SHA, assets y checksums; al corte no hay integración ni release ejecutados, ni
publicación o idempotencia remota verificadas. El mecanismo prevé no sobrescribir
assets en reintentos, pero eso no demuestra su ejecución real. Solo se modifica
el changelog de la copia CI; el paquete sigue siendo dinámico, sin runtime
incluido. No hay protección de rama configurada. Los permisos, reintentos,
retención, excepción y requisitos de integración están en
[ramas y releases](docs/branches-and-releases.md).
