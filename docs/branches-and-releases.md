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
   `.deb` desde el commit integrado en un entorno limpio y fijo. El objetivo
   es que cada merge a `main` dispare un release; **no está automatizado aún**.
5. Publicar paquetes y releases solo tras el verde de todas las comprobaciones
   y resolver licencia, titular y contacto del mantenedor. Un build fallido no
   puede producir un release público. No reutilizar una versión para binarios
   distintos. El push de fuente en una feature branch como trabajo en desarrollo,
   expresamente autorizado por el usuario, no equivale a integración, aprobación
   HIG o release y no elimina esos requisitos.

## Estado actual

El trabajo actual está en `feat/library-preferences`, base `df0d34d` y cambios
locales sin integrar; también existe `feat/initial-player`. No existe `main` aún.
El empaquetado local tiene versión `0.1.0`, fuente nativa y binarios de enlace
dinámico. El repositorio [gstn-caruso/gtkPlayer](https://github.com/gstn-caruso/gtkPlayer)
es **público**, con `origin` configurado en
`https://github.com/gstn-caruso/gtkPlayer.git`. El usuario autorizó el push de
fuente en la feature branch como trabajo en desarrollo, sin aprobar integración
ni release. No hay workflow, CI, branch protection o release. La integración a
`main` y los releases siguen bloqueados: **HIG NO APROBADO y CI ausente**;
licencia, titular y mantenedor siguen pendientes. La publicación de esa fuente
no implica una licencia open-source ni concede permisos de redistribución a
terceros. El `.deb` local no demuestra ninguna automatización remota.

La guía no ejecuta ni autoriza commits, push, merges, creación de remotos,
publicaciones ni cambios de servicios. Cada operación remota necesita el
encargo y autorización correspondientes.

## Decisiones necesarias para implementar CI

- Confirmar la distribución/arquitecturas de construcción y soporte. El artefacto
  actual usa las bibliotecas de Ubuntu 26.04.1 amd64; no incluye runtime.
- Acordar versionado de integración. Propuesta pendiente: `0.1.0+git<N>.<SHA>`
  con un contador monotónico de integraciones y SHA corto del commit. Es
  compatible con el formato nativo sin guion; hace falta definir una fuente
  estable del contador y cómo convive con versiones estables posteriores.
  CI deberá actualizar `debian/changelog` en su copia de construcción, comprobar
  la versión Debian y usarla en nombre de artefacto/release. No hay scripts que
  implementen todavía esta propuesta.
- Elegir release estable o prerelease por integración, política de retención,
  checksums y firma. Confirmar permisos mínimos del token del servicio sin
  almacenar secretos en Git ni archivos locales.
- Resolver licencia, autor/titular y mantenedor real antes de publicar paquetes
  o releases.
- Autorizar y configurar protección de `main`: PR/MR obligatorio, revisión y
  checks requeridos del pipeline real. Esta documentación sola no lo impone.

## Contrato de aceptación del pipeline futuro

Sobre cada PR/MR: exigir evidencia HIG aplicable (fuente, escenarios, entorno,
resultado y límites) y actualizar la matriz. Bloquear ante desviaciones o
verificaciones pendientes; un caso no aplicable requiere justificación. Compilar
y ejecutar `meson test` con los backends definidos en Meson; construir el Debian
sin privilegios; validar `.desktop`, metadata, contenido y `--help` del binario
extraído. Conservar logs de fallos, no publicar. Los checks de CI no certifican
por sí solos teclado real, nombres accesibles ni accesibilidad integral.

Sobre cada integración a `main`: repetir esas verificaciones sobre el commit
integrado; generar versión única; adjuntar `.deb` y SHA-256 al release del mismo
commit **solo después de todos los checks verdes y aprobación HIG documentada**.
Evitar duplicados en reintentos e impedir publicación si falla cualquier etapa.
Hacer una primera prueba controlada cuando estén resueltos HIG, permisos,
licencia, titular y mantenedor, con CI configurado en el proveedor ya confirmado.
Hasta entonces, usar la receta local del [README](../README.md).
