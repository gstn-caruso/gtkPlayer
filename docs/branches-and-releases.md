# Feature branches e integración con releases .deb

## Política acordada

Regla general; la única excepción autorizada para el bootstrap inicial se
registra abajo. No constituye aprobación HIG ni cambia esta política para
integraciones posteriores.

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

## Corte previo a la primera integración — 2026-10-25

Evidencia reportada por el coordinador: el código está publicado en
`feat/ci-hig-readiness`, HEAD `7114a837e47d2e1cb42a4ee5f68481f497304c2b`.
En este corte no existe `main` local/remoto; la rama predeterminada remota es
`feat/library-preferences`. El repositorio
[gstn-caruso/gtkPlayer](https://github.com/gstn-caruso/gtkPlayer) es **público**, con
`origin` en `https://github.com/gstn-caruso/gtkPlayer.git`.

El [workflow](../.github/workflows/ci.yml) tiene **SUCCESS** en el
[run 40239813173](https://github.com/gstn-caruso/gtkPlayer/actions/runs/40239813173)
para ese SHA: build/tests/paquete exitosos sobre Ubuntu 24.04 amd64, 32 tests
(11 core y 21 UI); `release` **SKIPPED** por ser feature branch. La última suite
local reportada también tiene 32 tests verdes. El
[run 40237594338](https://github.com/gstn-caruso/gtkPlayer/actions/runs/40237594338)
para `a9202982ddc49f515aafe257805b27b607f8cdad` (26 tests) es evidencia histórica,
no el CI actual. Su artefacto de prueba fue descargado y contrastado con
`SHA256SUMS` por el coordinador; eso no verifica los assets de un futuro release.
Esta actualización documental no reejecutó tests ni consultó la API remota.

**HIG NO APROBADO:** siguen los dos defectos P2 de estados vacíos, adaptación,
teclado/accesibilidad y decisiones de identidad en la [matriz HIG](gnome-hig.md).
Licencia, titular y contacto del mantenedor siguen pendientes. No hay branch
protection configurada. Publicar fuente o un prerelease no concede licencia
open-source ni permisos de redistribución a terceros, ni aprueba distribución
estable.

## Excepción puntual autorizada y plan pendiente

El usuario confirmó «si» a «¿Confirmás que integre este estado en main y permita
el prerelease automático, como excepción al bloqueo por HIG pendiente? No lo
presentaré como conforme a HIG.», tras pedir «merge comit push».
La autorización abarca **solo la integración inicial de `feat/ci-hig-readiness`:
código `7114a83` más este registro documental, y su prerelease experimental con
metadatos provisionales**. No decide nombre/icono, licencia, copyright/titular ni
contacto, ni levanta globalmente los gates humanos. No se presenta como conforme
a HIG ni como distribución estable.

Plan del coordinador, **aún no ejecutado en este corte**:

1. Hacer commit de este registro documental y push a la feature branch; esperar
   **CI verde de ese SHA exacto**, no reutilizar el verde de `7114a83`.
2. Crear `main` desde ese HEAD ya verde y publicarla. Es un bootstrap puntual:
   al corte no hay `main` ni destino posible de PR; no fabricar un merge commit.
3. El push a `main` disparará build/tests/paquete y, solo con build verde, el
   prerelease automático. Comprobar después el resultado real, tag, SHA objetivo,
   assets y checksums. Publicación e idempotencia remota aún no están verificadas.

CI sigue siendo obligatorio incluso en esta excepción. Las próximas
integraciones vuelven al flujo PR, revisión, HIG y CI de la política general y
requieren encargo; esta autorización no cubre nuevas operaciones ajenas al
bootstrap. Esta guía registra el permiso recibido, no ejecuta las operaciones
ni autoriza instalaciones o cambios de servicios.

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
previos a permitir integrar `main`, no flags que un test pueda inventar, salvo
la excepción puntual de bootstrap registrada arriba, que no los resuelve. La
revisión debe aportar fuentes, escenarios, entorno, resultados y límites,
actualizar la matriz HIG y justificar lo no aplicable. Fuera de esa excepción,
no crear/integrar `main` ni publicar mientras queden desviaciones o comprobaciones
aplicables pendientes.

La protección de `main` (PR obligatorio, revisión y checks requeridos del
pipeline real) sigue sin configurar y requiere autorización específica. Esta
política documentada no la impone técnicamente. Si se omite el gate y se hace
push a `main`, el workflow intentaría publicar tras el build verde: no usar eso
como atajo para decisiones humanas pendientes.

Próxima comprobación del bootstrap autorizado: CI verde del commit documental
y luego el run de `main` y los datos del prerelease según el plan anterior.
Los pendientes HIG y licencia/titular/mantenedor permanecen abiertos para las
siguientes integraciones. La lógica del job `release` fue revisada por lectura,
pero al corte no ejecutada: ni el verde de feature branch ni las comprobaciones
locales demuestran publicación remota o idempotencia real de la API de GitHub;
el reintento sin reemplazos tampoco se da por verificado.
