# Cumplimiento obligatorio de GNOME HIG

**Estado: NO APROBADO.** Cumplir las [GNOME Human Interface Guidelines][hig]
es requisito del proyecto, no una aspiración estética. La aplicación es nativa:
**Vala + GTK 4 + libadwaita** (GStreamer para audio). Usar ese stack o tener tests
verdes no certifica HIG. Merge y release quedan bloqueados mientras haya
desviaciones aplicables o verificaciones HIG pendientes; el workflow de CI se
ha añadido localmente, pero su ejecución remota y verde real siguen pendientes.

## Alcance y evidencia

Revisión documental del **2026-10-25**, sobre `feat/library-preferences`, base
`df0d34d` y cambios locales aún sin integrar. Se contrastaron las fuentes
oficiales enlazadas con código y tests; no se ejecutaron pruebas interactivas ni
se reejecutó la suite en esta revisión. No es una auditoría completa.

Aplicar cada directriz con sus cuantificadores: «todas las apps», «la mayoría»,
«si existe este patrón» no son equivalentes. No hay que incorporar todos los
patrones del catálogo. Un caso **no aplicable** debe tener motivo explícito;
una duda de alcance sigue **pendiente**. Documentar una desviación no la aprueba.

Estados: **cubierto por código** = evidencia de implementación por lectura;
**cubierto por test** = existe una aserción concreta, con alcance limitado (no
implica ejecución nueva); **desviación observada** = contradicción identificada;
**pendiente** = falta comprobar o decidir; **no aplicable** = condición ausente.
Los estados cubiertos son parciales, nunca un aprobado global.

## Matriz inicial

Las rutas son relativas a la raíz. Cada próxima comprobación debe registrar
commit, entorno, resultado y límites; si falla, conservar el escenario como
regresión cuando sea automatizable.

| Área y pauta oficial | Estado y evidencia actual | Próxima verificación / condición de cierre |
| --- | --- | --- |
| Controles nativos y estilo: [header bars][header], [UI styling][style] | **Cubierto por código/test, parcial.** `src/window.vala`: `Adw.HeaderBar`, controles GTK, clases libadwaita y tooltips. `tests/ui-tests.vala`: `/ui/compact-footer-layout`, `/ui/footer-volume-group`. | Revisar ventana y Preferencias con tema claro/oscuro y accesibilidad; comprobar versiones mínimas GTK 4.10/libadwaita 1.4. La geometría del footer no valida toda la UI. |
| Activar una pista: [puntero/touch][pointer] aconseja evitar doble clic | **Desviación observada por lectura.** `src/window.vala`, `build_ui`: instrucción «Doble clic» y `activate_on_single_click = false` en pistas y cola. Existe Play general, pero no resuelve la elección de cualquier pista con puntero sin doble clic. | Probar y cubrir una alternativa descubrible para iniciar una pista específica sin doble clic, conservando selección y acceso por teclado. |
| Acciones inválidas: [botones][buttons] insensibles | **Desviación observada por lectura.** `src/window.vala`, `build_controls`/`update_player`: Anterior/Play/Siguiente no ajustan sensibilidad por estado. `src/player.vala`: acciones sin efecto cuando no hay pista o avance posible. | Regresión de sensibilidad en biblioteca/cola vacías y extremos; habilitar Play cuando sí puede iniciar la selección. Probar también las transiciones. |
| Tamaños y paneles: [adaptación][adaptive], [utility panes][panes] | **Pendiente**, con recorte sin adaptación automática observado en `src/window.vala`, `panel_viewport` y `Gtk.Paned`. `tests/ui-tests.vala` prueba separadores a 1000×800/1280×800 y footer a 1280×800/1600×800, no 1024×600. | Probar escritorio **1024×600**, redimensionado ordinario y Preferencias: controles esenciales utilizables sin reparar manualmente separadores. Evaluar superposición del panel auxiliar con poco ancho. Mantener el ajuste manual no es infracción por sí mismo. **360×294** solo aplica si la app es apropiada para teléfono: alcance aún pendiente, no mandato automático. |
| [Teclado][keyboard] y [ventanas][windows] | **Pendiente**, con cobertura parcial: `/ui/footer-keyboard-playback` en `tests/ui-tests.vala` comprueba foco/activación programáticos del footer. No demuestra recorrido completo. | Usar solo teclado: biblioteca, pistas, Datos/Cola, separadores, Preferencias, selector de carpeta y errores; comprobar orden/visibilidad de foco, Ctrl+W y Esc en modal. Pueden ser heredados: no asumir ausencia por falta de código explícito. |
| [Nombres accesibles][names] | **Pendiente.** Hay etiquetas/tooltips en `src/window.vala`; GTK aporta algunos nombres por defecto. La ausencia de asignaciones explícitas no prueba que todos falten. | Inspeccionar árbol de accesibilidad y usar lector: nombres descriptivos de todos los elementos, listas, escalas y estados Play/Pausa. No certificar con `GTK_A11Y=none`. |
| [Pruebas de accesibilidad][a11y-tests] | **Pendiente.** `meson.build` usa Xvfb y `GTK_A11Y=none`; `tests/ui-tests.vala` usa `fakesink`. Claro/oscuro no cubre accesibilidad integral. | Sesión real con alto contraste, texto grande, teclado, lector y teclado en pantalla para todas las entradas. Registrar tareas completables y cualquier recorte, foco perdido o control sin anunciar. |
| [Redacción][writing] y [estados vacíos][empty] | **Desviación observada.** `src/window.vala`, `load_library`/`show_tracks`: plurales fijos y resumen «Todas las pistas · 0 pistas» con instrucción de selección inútil. `/ui/no-status-row-summary-in-preferences` incluso fija «1 pistas»/«1 archivos». | Casos 0/1/varios: plural correcto y guía útil. Distinguir biblioteca vacía, cola vacía y fallo de carga sin perder biblioteca anterior. Mantener castellano; HIG no obliga a cambiar toda app a inglés. |
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

Antes de integrar: resolver las desviaciones, completar las comprobaciones
aplicables y justificar las no aplicables; ampliar esta matriz si aparecen
otras pautas relevantes. La revisión debe contrastar comportamiento, no marcar
«usa GTK». Adjuntar evidencia automatizada y manual, sin sustituir una por otra.
Además se exige CI verde según [ramas y releases](branches-and-releases.md),
con workflow añadido localmente y ejecución remota pendiente. Los artefactos CI
no certifican HIG ni son paquetes finales aprobados para distribución. El push
de fuente en una feature branch como trabajo en
desarrollo, expresamente autorizado por el usuario, no significa aprobación
HIG ni habilita integración o release. Nombre/icono requieren al usuario;
licencia, titular y mantenedor siguen pendientes antes de publicar paquetes o
releases. Este documento no autoriza operaciones remotas ni declara aprobación
HIG.

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
