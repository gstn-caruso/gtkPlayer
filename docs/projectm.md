# Motor del visualizador

El visualizador usa **projectM 4.1.8**; no es MilkDrop 3 ni ejecuta su binario
Windows. La selección de projectM nativo fue confirmada por el usuario.
Se ofrece abrir/cerrar, flechas anterior/siguiente y alternar ventana/pantalla completa.
Cinco efectos originales, integrados en `src/visualizer-renderer.c`, cambian
aleatoriamente, sin repetir el anterior, con transiciones suaves de 3 segundos.
El intervalo nominal entre efectos es 20 segundos, sin la variación aleatoria
de duración que projectM activa por defecto. Al reanudar una pausa larga puede
corresponder una transición inmediata.
Las ondas y el movimiento responden al PCM y a graves/medios/agudos.
No se clasifica el género musical ni se afirma selección semántica de efectos.
Las flechas recorren los cinco efectos en orden circular y mantienen el cambio
automático aleatorio. En reproducción usan transición suave; en pausa cambian
la imagen sin reanudar audio ni animación. La carga se difiere al callback GL
para conservar el contexto correcto, también ante pulsaciones rápidas.
No hay editor, carga de archivos, descarga de presets ni preferencias expuestas.

El motor se compila como biblioteca compartida privada `libgtkplayer_projectM.so.4`.
Meson descarga el archivo oficial fijado en `subprojects/projectm.wrap`, verifica
su SHA-256 y aplica `subprojects/packagefiles/projectm/gtk-framebuffer.patch`.
El parche conserva el framebuffer de GtkGLArea al terminar las pasadas internas;
la API publicada 4.1 no permite especificarlo. También adapta los generadores de
shaders y el enlace del evaluador a la importación CMake de Meson y renombra el
target privado para evitar colisiones con las bibliotecas del sistema.
No se modifica la biblioteca instalada del usuario ni se instala software durante
el desarrollo. La compilación inicial necesita red (o el archivo verificado en
`subprojects/packagecache/`); no se descarga nada al usar la aplicación.

Fuentes oficiales:

- [Release 4.1.8](https://github.com/projectM-visualizer/projectm/releases/tag/v4.1.8).
- [API de projectM](https://github.com/projectM-visualizer/projectm/tree/v4.1.8/src/api/include/projectM-4).
- [GtkGLArea](https://docs.gtk.org/gtk4/class.GLArea.html).
- [GstAudioConverter](https://gstreamer.freedesktop.org/documentation/audio/audio-converter.html).

El tap GStreamer usa un filtro `identity` que conserva el audio original. Su
handoff convierte una copia a F32LE estéreo/44,1 kHz mediante GstAudioConverter;
un buzón de 8192 bytes conserva solo la muestra reciente. La salida audible
conserva su negociación. No hay segundo sink, cola de reproducción ni cambios
a las consultas de posición/duración. Con el visualizador cerrado o pausado,
el callback sale sin convertir. GTK lee una copia acotada bajo mutex; el motor
OpenGL nunca se ejecuta en el hilo de audio. La clausura del handoff conserva
el tap hasta que termine cualquier callback en vuelo.
El renderizado se limita a aproximadamente 30 fps y se suspende en pausa y
cuando la ventana no está mapeada. No se captura el micrófono ni audio del sistema.

## Fuentes y avisos de terceros

projectM está bajo LGPL-2.1-or-later según los archivos `COPYING`/`LICENSE.txt`
del release. El archivo fuente completo, que contiene también los componentes
vendorizados y sus avisos, se instala con el parche, la receta y esta guía en
`share/doc/gtkplayer/projectm/`. Se conservan además los avisos MIT de
hlslparser y projectm-eval. Para reconstruir el motor modificado, descargar el
repositorio de GTK Player con esa misma receta/parche y ejecutar los comandos
Meson documentados en el README; o extraer el archivo fuente, aplicar el parche
con `patch -p1` y compilar con CMake 3.21+, `ENABLE_PLAYLIST=OFF`,
`ENABLE_SDL_UI=OFF` y `ENABLE_SYSTEM_PROJECTM_EVAL=OFF`.
El enlace dinámico permite reemplazar la biblioteca por una compilación
compatible. Esto registra licencias ajenas existentes y no elige licencia,
titular, identidad ni contacto para la aplicación. Su publicación sigue sujeta
a las decisiones y revisión pendientes del proyecto.
