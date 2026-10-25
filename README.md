# GTK Player

Reproductor nativo para Linux escrito en Vala, GTK 4, libadwaita y GStreamer.
Esta primera versión permite cargar una carpeta local o SMB, agrupar las pistas
por álbum o artista, ver sus datos y reproducir una cola. Tiene panel de
biblioteca a la izquierda, pistas en el centro, pestañas Datos/Cola a la derecha
y controles de reproducción abajo. No es un cliente de Spotify.

## Usar la biblioteca

La ubicación inicial editable es `smb://nas.local/public/multimedia/Música`.
También se admiten rutas locales y URI `file://`. Para NFS, usá una ruta ya
montada por el sistema: la aplicación no monta NFS ni admite URI `nfs://`.
Pulsá **Cargar**: no hay autoescaneo ni acceso al NAS al iniciar. Se recorre la
carpeta de forma recursiva sin seguir enlaces simbólicos; la biblioteca aparece
al terminar, no de manera progresiva. Doble clic en una pista inicia la cola
con las pistas de la selección actual.

SMB utiliza GIO/GVfs y el diálogo de autenticación del sistema. Se necesita
`gvfs-backends` y una sesión de escritorio con sus servicios disponibles.
No incluyas usuario, contraseña ni dominio de autenticación en la URI: se
rechazan URI con `userinfo`. No guardes credenciales en archivos del proyecto,
comandos, variables persistentes ni Git. La aplicación solicita no guardar la
contraseña; los montajes o credenciales previamente gestionados por el sistema
son independientes. Solo se recuerda la ubicación, tras una carga exitosa, en
`$XDG_CONFIG_HOME/gtkplayer/settings.ini` (normalmente
`~/.config/gtkplayer/settings.ini`); no se persiste la biblioteca.

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

Son dos suites: siete casos core y dos UI. Cubren lectura de metadata FLAC
local, recursión y enlaces, errores y cancelación inicial, límites de cola,
fin de pista/avance, controles básicos, activación de la ventana, carga local
explícita y recuerdo de la ubicación. No se prueba la cancelación desde la UI.
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
  placeholder explícito. No publicar ni redistribuir hasta resolverlos.

## Ramas y releases

Ver [la guía de contribución e integración](docs/branches-and-releases.md).
La construcción local está disponible; la publicación automática queda
pendiente de URL del remoto, proveedor CI y autorizaciones. No hay un pipeline
configurado ni se afirma que un merge produzca ya un release.
