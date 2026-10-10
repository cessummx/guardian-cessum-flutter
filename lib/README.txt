CESSUM · Salud de datos · Fase 1 (Hardening P0)

ORDEN DE DESPLIEGUE OBLIGATORIO:
1) Primero reemplazar Code.gs completo con Code_Guardian_166608_SaludFase1.zip y publicar NUEVA versión del Web App.
2) Después reemplazar C:\cessum_app\lib\salud_datos_screen.dart por lib\salud_datos_screen.dart de este paquete.
3) Recompilar Flutter web y desplegar build/web.
4) Hacer recarga forzada del navegador.

No despliegues el Flutter nuevo contra el backend anterior: la nueva interfaz hace una prueba en seco antes de aplicar y el backend anterior no respetaba ese contrato de forma uniforme.

Cambios Fase 1:
- Toda acción salud_accion usa aplicar=0 para prueba y aplicar=1 para escritura.
- Calificaciones fuera de rango: borrado automático bloqueado.
- Respaldo Salud usa ancho real completo de Calificaciones, no 15 columnas fijas.
- Normalización de generaciones también respalda Tramites.
- Restauración usa metadatos de filas/columnas y restaura Tramites cuando corresponde.
- Tras aplicar se vuelve a ejecutar la comprobación y se informa si quedan pendientes.
