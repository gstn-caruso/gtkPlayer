# GTK Player

Reproductor nativo para Linux escrito en Vala, GTK 4, libadwaita y GStreamer.
Esta primera versión permite cargar una carpeta local o SMB, agrupar las pistas
por álbum o artista, ver sus datos y reproducir una cola. Tiene panel de
biblioteca a la izquierda, pistas en el centro, pestañas Datos/Cola a la derecha
y controles de reproducción abajo. No es un cliente de Spotify.

## Requisito obligatorio: GNOME HIG

La aplicación debe cumplir las [GNOME Human Interface Guidelines](https://developer.gnome.org/hig/index.html)
según las directrices aplicables a su alcance. El stack Vala + GTK 4 + libadwaita
no demuestra por sí solo ese cumplimiento. **Estado: NO APROBADO**; hay
desviaciones y comprobaciones pendientes en la [matriz HIG](docs/gnome-hig.md).
Merge y release quedan bloqueados hasta resolverlas y contar con CI verde real;
el [workflow](.github/workflows/ci.yml) se añadió localmente, con ejecución remota
pendiente (no se afirma CI verde). Ver también [las instrucciones del proyecto](AGENTS.md).

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

Se recorre la carpeta de forma recursiva sin seguir enlaces simbólicos; la
biblioteca aparece al terminar, no de manera progresiva. Durante el escaneo,
los controles de ubicación se deshabilitan y **Cancelar escaneo** está disponible
solo en Preferencias. Los conteos de pistas cargadas y archivos omitidos, el
estado de carga, la cancelación y el fin de cola se consultan allí: no hay una
fila de estado ni espacio reservado debajo del encabezado principal. El resumen
del álbum o selección y su contador de pistas permanecen en el panel central.
Si la ubicación no está disponible, se conserva la biblioteca anterior. Los
errores de carga, guardado y reproducción muestran un aviso nativo transitorio,
sin rutas ni URI, sobre los paneles y sin tapar los controles inferiores; el
detalle completo queda en Preferencias.
Una ubicación válida queda guardada aunque falle la lectura; una URI inválida
se rechaza sin modificar la configuración ni la biblioteca. Si no se puede
guardar, no se inicia la carga de esa elección. Doble clic en una pista inicia
la cola con las pistas de la selección actual.

SMB utiliza GIO/GVfs y el diálogo de autenticación del sistema. Se necesita
`gvfs-backends` y una sesión de escritorio con sus servicios disponibles.
No incluyas usuario, contraseña ni dominio de autenticación en la URI: se
rechazan URI con `userinfo`. No guardes credenciales en archivos del proyecto,
comandos, variables persistentes ni Git. La aplicación solicita no guardar la
contraseña; los montajes o credenciales previamente gestionados por el sistema
son independientes. Solo se recuerda la ubicación al aplicar Preferencias, en
`$XDG_CONFIG_HOME/gtkplayer/settings.ini` (normalmente
`~/.config/gtkplayer/settings.ini`); no se persiste la biblioteca.

## Ancho de las columnas

Arrastrá cualquiera de los dos separadores nativos para dar más o menos ancho
a Biblioteca, pistas o Datos/Cola. Se pueden estrechar hasta casi colapsarlas:
el límite es el espacio de la ventana y el ancho físico de los separadores,
no un mínimo impuesto por el texto. El contenido que no entra queda recortado
sin invadir la columna vecina; arrastrá el separador de vuelta para recuperarlo.
El ajuste no reordena columnas ni se guarda al cerrar.

## Barra inferior nativa

La barra conserva título/artista e icono genérico a la izquierda (no extrae
carátulas), transporte centrado en una fila, tiempos a ambos lados del progreso
en otra y volumen agrupado a la derecha. Usa controles GTK y clases de estilo de
libadwaita 1.4 (`toolbar`, `circular`, `raised`, `numeric`, `dim-label`), sin CSS
personalizado ni colores Spotify. El texto largo se elide; no hay altura fija
que recorte texto o reduzca los botones.

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
blancos de 34×34 px. Los 15 tests UI
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
GStreamer y GStreamer pbutils. No se usa libgee.
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

Son dos suites: once casos core y quince UI. Cubren lectura de metadata FLAC
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
que los errores transitorios no expongan rutas ni URI. Incluyen geometría real del footer tras layout,
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

- No hay playlists persistentes/importadas, recientes ni carátulas reales.
- Los álbumes se agrupan por álbum **y artista de pista**: las compilaciones se
  separan por artista. No se usa artista de álbum ni número de disco.
- No hay biblioteca incremental ni caché. Cancelar durante discovery puede
  esperar al timeout de hasta 5 segundos del archivo actual.
- Las pruebas de reproducción no validan completamente pausa/seek/volumen.
- Acceso efectivo al NAS y autenticación SMB no comprobados por este empaquetado.
- Hay una advertencia Vala preexistente sobre `Music.Track[]` como propiedad de
  `GLib.Object`; no se cambió el código del reproductor en el empaquetado.
- **Licencia, autor/titular y contacto del mantenedor pendientes de confirmar.**
  `debian/copyright` no concede permisos y `debian/control` usa un contacto
  placeholder explícito. La publicación de fuente en desarrollo autorizada por
  el usuario no implica una licencia open-source ni concede permisos de
  redistribución a terceros. No publicar paquetes ni releases hasta resolverlos.

## Ramas y releases

Ver [la guía de contribución e integración](docs/branches-and-releases.md).
El repositorio [gstn-caruso/gtkPlayer](https://github.com/gstn-caruso/gtkPlayer)
es público y tiene `origin` configurado. La fuente es trabajo en desarrollo:
el usuario autorizó su push en una feature branch, lo que no significa aprobación
HIG ni un release. La integración a `main` y los releases siguen bloqueados por
HIG no aprobado y CI remoto pendiente; licencia, titular y mantenedor siguen
pendientes. El [workflow](.github/workflows/ci.yml) construye y prueba sobre
Ubuntu 24.04 amd64 (GTK 4.14/libadwaita 1.5), sin demostrar las versiones mínimas
absolutas ni compatibilidad universal. En `feat/**`, `fix/**` y PR hacia `main`
solo adjunta `.deb` de prueba y SHA-256 como artefacto CI, no release final.
Tras cerrar los gates humanos, cada push a `main` con build verde está previsto
que publique un prerelease `v0.1.0+git<RUN_NUMBER>.<SHA12>` del SHA integrado, sin
sobrescribir assets en reintentos. Solo se modifica el changelog de la copia CI;
el paquete sigue siendo dinámico, sin runtime incluido. No hay protección de
rama configurada y todavía no se verificó una publicación remota. Los permisos,
reintentos, retención y requisitos de integración están en
[ramas y releases](docs/branches-and-releases.md).
