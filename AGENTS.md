# Instrucciones del proyecto

- Es obligatorio cumplir las [GNOME Human Interface Guidelines](https://developer.gnome.org/hig/index.html)
  en las partes aplicables a esta aplicación nativa **Vala + GTK 4 + libadwaita**.
  Usar esos widgets no demuestra cumplimiento por sí solo.
- Antes de cambiar UI, consultar [la matriz HIG](docs/gnome-hig.md) y las pautas
  oficiales pertinentes. Respetar su alcance y condiciones: no todos los patrones
  corresponden a todas las apps. Registrar evidencia y próxima verificación para
  cada cambio; justificar los casos no aplicables. No convertir decisiones de
  producto en reglas HIG ni dar una desviación por resuelta solo por documentarla.
- Conservar controles nativos, castellano y redimensionado manual de columnas,
  comprobando también adaptación, teclado y accesibilidad. Si un pedido concreto
  entra en conflicto con HIG, explicitarlo antes de implementar. Nombre visible,
  icono propio y licencia requieren decisión del usuario; no inventarlos.
- Trabajar en feature branches y seguir [la política de integración](docs/branches-and-releases.md).
  No integrar a `main` ni publicar releases con desviaciones HIG aplicables o
  comprobaciones pendientes: se requieren revisión HIG documentada y CI verde
  del pipeline real. El push de fuente en una feature branch como trabajo en
  desarrollo, expresamente autorizado por el usuario, no implica aprobación HIG
  ni habilita integración o release por sí solo. El cumplimiento HIG **no está
  aprobado**. Al corte del 2026-10-25, previo a la primera integración, el código
  `7114a837e47d2e1cb42a4ee5f68481f497304c2b` ya está publicado y tiene
  [CI SUCCESS 40239813173](https://github.com/gstn-caruso/gtkPlayer/actions/runs/40239813173)
  (32 tests: 11 core y 21 UI; build/paquete exitoso, release omitido).
- **Excepción puntual autorizada por el usuario:** integrar inicialmente
  `feat/ci-hig-readiness` (ese código más este registro documental) y permitir su
  prerelease experimental con metadatos provisionales, sin aprobar HIG ni decidir
  identidad, licencia, titular o contacto. Según el [registro y plan](docs/branches-and-releases.md),
  primero se exige CI verde del commit documental; después se creará `main`
  desde ese HEAD, sin fabricar un merge commit, porque al corte no existe `main`
  local/remoto ni destino posible de PR. Integración y release siguen pendientes
  al corte. La excepción no cambia los requisitos de las próximas integraciones.
- Estas instrucciones complementan las globales; salvo el encargo puntual
  registrado, no autorizan operaciones Git, publicaciones, instalaciones ni
  cambios de servicios automáticos.
