# Feature branches e integración con releases .deb

## Política acordada

1. Trabajar en una rama `feat/<tema>` por funcionalidad; no desarrollar directo
   en `main`. Para correcciones se puede usar `fix/<tema>`. Un escritor por
   worktree cuando haya trabajo concurrente.
2. Abrir PR/MR hacia `main` con alcance, pruebas observadas y límites. No mezclar
   cambios estructurales ajenos. Conservar los cambios previos del usuario.
3. Exigir revisión, [cumplimiento HIG comprobado](gnome-hig.md) y CI verde del
   pipeline real **antes** de integrar: compilación, suites core/UI, instalación
   en DESTDIR, construcción Debian e inspección del paquete. Resolver las
   desviaciones y comprobaciones HIG aplicables; los tests no sustituyen la
   auditoría manual. No ignorar fallos ni forzar push o saltar verificaciones.
4. Cada integración a `main` deberá generar una versión única y construir un
   `.deb` desde el commit integrado en un entorno limpio y fijo. El workflow
   descrito abajo implementa el mecanismo; el build remoto en feature branch ya
   pasó, pero el job de publicación desde `main` aún no se ejecutó.
5. Publicar paquetes y releases solo tras el verde de todas las comprobaciones
   y resolver licencia, titular y contacto del mantenedor. Un build fallido no
   puede producir un release público. No reutilizar una versión para binarios
   distintos. El push de fuente en una feature branch como trabajo en desarrollo,
   expresamente autorizado por el usuario, no equivale a integración, aprobación
   HIG o release y no elimina esos requisitos.

## Estado actual

La configuración está publicada en `feat/ci-hig-readiness`, HEAD `a920298`, sin
integrar las ramas de desarrollo a `main`. No existe `main` aún. El repositorio
[gstn-caruso/gtkPlayer](https://github.com/gstn-caruso/gtkPlayer) es **público**, con
`origin` en `https://github.com/gstn-caruso/gtkPlayer.git`. El usuario autorizó el
push de fuente en feature branches como trabajo en desarrollo, sin aprobar HIG
ni resolver las decisiones de identidad y licencia.

El [workflow](../.github/workflows/ci.yml) tiene un run remoto **SUCCESS**:
[40237594338](https://github.com/gstn-caruso/gtkPlayer/actions/runs/40237594338),
SHA `a9202982ddc49f515aafe257805b27b607f8cdad`, Ubuntu 24.04 amd64, 26 tests
(11 core y 15 UI). El job `release` quedó **SKIPPED** por ser feature branch.
Evidencia del coordinador al 2026-10-25: artefacto `ubuntu-24.04-amd64-deb`
(ZIP de 30096 bytes), descargado y verificado contra `SHA256SUMS`; paquete
`gtkplayer`, versión `0.1.0+git1.a9202982ddc4`, arquitectura `amd64`.
La copia temporal está en
`/tmp/gtkplayer-ci-artifact.9rOsKB/gtkplayer_0.1.0+git1.a9202982ddc4_amd64.deb`;
no es un enlace permanente de release. No se instaló el paquete ni se publicaron
releases o tags. El enlace al run es la referencia oficial.

Los cambios UI locales posteriores, sin commit sobre ese SHA, tienen 32 tests
verdes reportados (11 core y 21 UI), pero **no CI remoto** y dos defectos de
estados vacíos pendientes en la [matriz HIG](gnome-hig.md). No se configuró branch
protection. La integración y publicación siguen bloqueadas:
**HIG NO APROBADO, CI del árbol futuro pendiente, licencia/titular/mantenedor pendientes**.
La publicación de fuente no implica licencia open-source ni concede permisos
de redistribución. Los artefactos CI son paquetes de prueba, no paquetes finales
aprobados para distribución.

Esta guía no ejecuta ni autoriza commits, push, merges, creación de remotos,
publicaciones ni cambios de servicios. Cada operación remota necesita el
encargo y autorización correspondientes.

## Workflow de build y paquete

- Eventos: `push` a `feat/**`, `fix/**` y `main`; `pull_request` hacia `main`.
  No usa `pull_request_target` ni interpola títulos o refs de PR en shell.
- Runner fijo `ubuntu-24.04`, amd64: GTK 4.14/libadwaita 1.5. Es la baseline
  de construcción, no una prueba de las mínimas declaradas GTK 4.10/Adwaita 1.4.
  Las actualizaciones de paquetes del runner pueden variar; no se promete
  reproducibilidad bit a bit ni una imagen congelada por digest.
- Instala dependencias solo en el runner desechable, con
  `apt-get --no-install-recommends`; valida `Build-Depends` mediante
  `dpkg-checkbuilddeps`. No instala el `.deb` construido.
- Ejecuta Meson, tests core/UI (Xvfb, fakesink y entorno aislado definido en
  Meson), instalación en DESTDIR y `desktop-file-validate`/`--help`.
- Copia la fuente sin `.git`, `build`, `build-*`, `obj-*` ni `dist` a un árbol
  temporal; allí ejecuta `dpkg-buildpackage -us -uc -b`. Debhelper vuelve a
  ejecutar los tests; las dependencias enlazadas las calcula `dpkg-shlibdeps`.
  Plugins GStreamer y GVfs SMB siguen siendo dependencias explícitas de control.
- Inspecciona metadata y contenido del `.deb`, exige Package/Version/Architecture
  esperados, extrae y valida `.desktop` y `--help`. Esto no prueba instalación,
  reproducción real, SMB ni accesibilidad integral.
- Sube exclusivamente `.deb` principal y `SHA256SUMS`, como artefacto
  `ubuntu-24.04-amd64-deb`, retenido 14 días. No sube dbgsym, logs Meson (pueden
  contener entorno heredado), credenciales ni metadata Git.

El paquete es **dinámico para Ubuntu 24.04 amd64**, sin runtime universal. Una
construcción local en otra distribución no verifica ese destino; el run remoto
citado sí construyó para ese destino, sin probar instalación. Los avisos de licencia y mantenedor pendientes se
conservan en el paquete.

## Versionado y publicación de integraciones

La base actual en Meson y `debian/changelog` es `0.1.0`. Cada run calcula
`0.1.0+git<github.run_number>.<SHA12>` a partir del changelog y del commit
checkout; `dpkg --validate-version` comprueba el formato Debian nativo. El
contador corresponde a este workflow (incluye feature branches y PR), no al
número de merges. Es estable en reintentos y crece entre runs; no renombrar ni
recrear el workflow suponiendo que su contador se conservará. Una futura
versión estable requiere subir la base deliberadamente en Meson/changelog.
Solo la copia temporal recibe una nueva entrada de changelog; su fecha y
`SOURCE_DATE_EPOCH` provienen del commit. La fuente versionada no se altera.

En feature branches/PR solo se construye y adjunta el artefacto de prueba.
El job `release` requiere `build` exitoso y exclusivamente un `push` a
`refs/heads/main`. No usa `always`, `continue-on-error` ni grupos concurrency
que descarten pushes pendientes. Cada push a `main` tiene oportunidad de
producir su **prerelease de integración**, tag `v<VERSION>`, con `.deb` y
SHA-256; no se presenta como release estable.

Los permisos globales son `contents: read`; solo `release` recibe
`contents: write`. Checkout no persiste credenciales. `GITHUB_TOKEN` automático
solo se entrega a gh en el paso de publicación, sin secretos nuevos ni
credenciales manuales. Las actions oficiales están fijadas por SHA (v4).

El tag apunta al SHA completo del push. Si existe, se resuelve hasta el commit
y se exige coincidencia antes de reutilizarlo; un draft sin tag también debe
apuntar a ese SHA. La publicación crea primero un draft, carga assets faltantes
y luego lo publica. En reintentos descarga y compara assets existentes: no usa
`--clobber` ni reemplaza binarios ya publicados. Si difieren, falla y exige
revisión; una compilación no bit-idéntica no autoriza a sobrescribir el release.
No se firman paquetes ni se promete firma de checksums.

## Gate humano y primera comprobación remota

**El workflow no certifica ni aprueba HIG, licencia o identidad.** Son requisitos
previos a permitir integrar `main`, no flags que un test pueda inventar. La
revisión debe aportar fuentes, escenarios, entorno, resultados y límites,
actualizar la matriz HIG y justificar lo no aplicable. No crear/integrar `main`
ni publicar mientras queden desviaciones o comprobaciones aplicables pendientes.

La protección de `main` (PR obligatorio, revisión y checks requeridos del
pipeline real) sigue sin configurar y requiere autorización específica. Esta
política documentada no la impone técnicamente. Si se omite el gate y se hace
push a `main`, el workflow intentaría publicar tras el build verde: no usar eso
como atajo para decisiones humanas pendientes.

Próxima comprobación: resolver los pendientes HIG y probar el árbol posterior
en CI mediante un push expresamente autorizado. El primer run ya confirmó
build/tests/metadata/artefacto y ausencia de release para `a920298`, no para los
cambios locales. Solo después de cerrar HIG, licencia/titular/mantenedor y
permisos, realizar una integración controlada y comprobar tag, SHA objetivo,
assets/checksums y reintento sin reemplazos. La lógica del job `release` fue
revisada por lectura, pero no ejecutada: ni el verde de feature branch ni las
comprobaciones locales demuestran publicación remota o idempotencia real de
la API de GitHub.
