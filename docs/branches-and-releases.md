# Feature branches e integración con releases .deb

## Política acordada

1. Trabajar en una rama `feat/<tema>` por funcionalidad; no desarrollar directo
   en `main`. Para correcciones se puede usar `fix/<tema>`. Un escritor por
   worktree cuando haya trabajo concurrente.
2. Abrir PR/MR hacia `main` con alcance, pruebas observadas y límites. No mezclar
   cambios estructurales ajenos. Conservar los cambios previos del usuario.
3. Exigir revisión y pruebas verdes **antes** de integrar: compilación,
   suites core/UI, instalación en DESTDIR, construcción Debian e inspección
   del paquete. No ignorar fallos ni forzar push o saltar verificaciones.
4. Cada integración a `main` deberá generar una versión única y construir un
   `.deb` desde el commit integrado en un entorno limpio y fijo. El objetivo
   es que cada merge a `main` dispare un release; **no está automatizado aún**.
5. Publicar solo tras el verde de todas las comprobaciones y resolver licencia,
   titular y contacto del mantenedor. Un build fallido no puede producir un
   release público. No reutilizar una versión para binarios distintos.

## Estado actual

El trabajo inicial está en `feat/initial-player`, sin integración a `main`.
El empaquetado local tiene versión `0.1.0`, fuente nativa y binarios de enlace
dinámico. No existe todavía URL de remoto confirmada ni proveedor CI elegido:
no se creó configuración de GitHub Actions, GitLab CI ni otro servicio.
No se configuró branch protection ni se publicó un release. El `.deb` local
no es evidencia de que exista una automatización remota.

La guía no ejecuta ni autoriza commits, push, merges, creación de remotos,
publicaciones ni cambios de servicios. Cada operación remota necesita el
encargo y autorización correspondientes.

## Decisiones necesarias para implementar CI

- Confirmar URL del repositorio y si usa GitHub, GitLab u otro proveedor.
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
- Resolver licencia, autor/titular y mantenedor real antes de publicar.
- Autorizar y configurar protección de `main`: PR/MR obligatorio, revisión y
  checks requeridos del pipeline real. Esta documentación sola no lo impone.

## Contrato de aceptación del pipeline futuro

Sobre cada PR/MR: compilar y ejecutar `meson test` con los backends definidos en
Meson; construir el Debian sin privilegios; validar `.desktop`, metadata,
contenido y `--help` del binario extraído. Conservar logs de fallos, no publicar.

Sobre cada integración a `main`: repetir esas verificaciones sobre el commit
integrado; generar versión única; adjuntar `.deb` y SHA-256 al release del mismo
commit **solo después de todos los checks verdes**. Evitar duplicados en
reintentos e impedir publicación si falla cualquier etapa. Hacer una primera
prueba controlada cuando estén confirmados proveedor, permisos y licencia.
Hasta entonces, usar la receta local del [README](../README.md).
