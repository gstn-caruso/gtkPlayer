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
  ni habilita integración o release. Hoy el cumplimiento HIG **no está aprobado**
  y no existe CI configurado.
- Estas instrucciones complementan las globales; no autorizan operaciones Git,
  publicaciones, instalaciones ni cambios de servicios automáticos.
