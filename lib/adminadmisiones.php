<!DOCTYPE html>
<html lang="es">
<head>
<script>
/* (1-oct-2026) localStorage está aislado POR DIRECCIÓN EXACTA: cessum.mx
   y www.cessum.mx son dos orígenes distintos para el navegador, cada uno
   con su propio almacenamiento separado. Si se entra a veces con "www."
   y a veces sin, el registro de "ya enviado" de Impulso CESSUM (y la
   imagen de campaña guardada) parece perderse — en realidad queda en el
   otro, nunca se borra. Esta redirección fuerza siempre la misma forma
   (con www.) antes de que cargue nada más, para que todo quede en el
   mismo lugar sin importar cómo se escriba la dirección. */
(function () {
  if (location.hostname === 'cessum.mx') {
    location.replace('https://www.cessum.mx' + location.pathname + location.search + location.hash);
  }
})();
</script>
<base target="_top">
<meta charset="utf-8">
<style>
/* ═══════════════════════════════════════════════════════════════════════
   PANEL DE ADMISIONES · identidad CESSUM  ·  19-ago-2026

   TRES DECISIONES DE DISEÑO, Y POR QUÉ

   1. ESTO NO ES UN TABLERO DE CONTROL, ES UNA LISTA DE PERSONAS.
      Cada tarjeta lleva el nombre en tipografía de titular, grande, antes
      que cualquier cifra. Quien la abre debe pensar «hay que llamarle a
      Sofía», no «hay 14 registros pendientes». La diferencia entre esas dos
      frases es si alguien se inscribe o no.

   2. EL COLOR SOLO SE USA PARA URGENCIA.
      Todo lo demás vive en hueso, tinta y oro. Si el verde y el rojo
      aparecieran también en botones o encabezados, dejarían de significar
      algo. Aquí el rojo quiere decir una sola cosa: llevan días esperando.

   3. LA JERARQUÍA VA POR TAMAÑO Y AIRE, NO POR CAJAS.
      Menos bordes, más espacio. Un panel con todo enmarcado se lee como un
      formulario, y un formulario invita a llenarlo, no a decidir.
   ═══════════════════════════════════════════════════════════════════════ */

@import url('https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600;9..144,700&family=Inter:wght@400;500;600;700;800&display=swap');

:root{
  /* La paleta institucional, tal cual la del sitio */
  --rojo:#B51F27; --rojo-osc:#79151A; --vino:#3C0A0D;
  --oro:#B16B12; --oro-txt:#95590E; --oro-med:#CBA370; --oro-pal:#E5C7A0;
  --tinta:#282626; --gris:#E8E6E6; --gris-txt:#6B6360;
  --hueso:#F6EBE4; --papel:#FCFAF8;
  --verde:#1E7B34; --verde-pal:#E8F3EA;
  --ambar:#B07D12; --ambar-pal:#FBF3E2;
  --rojo-pal:#FBEAEA;

  --display:'Fraunces',Georgia,serif;
  --texto:'Inter',system-ui,-apple-system,'Segoe UI',sans-serif;
  --sombra:0 1px 2px rgba(40,38,38,.05), 0 4px 16px rgba(40,38,38,.06);
  --sombra-alta:0 8px 34px rgba(40,38,38,.14);
}
*{box-sizing:border-box}
html,body{margin:0;padding:0}
body{
  font-family:var(--texto);background:var(--papel);color:var(--tinta);
  font-size:14px;line-height:1.6;-webkit-font-smoothing:antialiased;
}
::selection{background:var(--oro-pal);color:var(--vino)}

/* ── Cabecera ─────────────────────────────────────────────────────────
   Fondo vino con el venado de marca al fondo, muy tenue. No decora: dice
   de quién es esta herramienta antes de que se lea una palabra. */
.top{
  background:
    radial-gradient(120% 140% at 88% 12%, rgba(203,163,112,.16), transparent 62%),
    var(--vino);
  color:#fff;padding:20px 26px 16px;position:sticky;top:0;z-index:30;
  border-bottom:2px solid var(--oro);
}
.top::after{
  content:"";position:absolute;right:20px;top:-8px;width:132px;height:132px;
  background:url('/assets/img/venado-blanco.webp') center/contain no-repeat;
  opacity:.07;pointer-events:none;
}
.top h1{
  margin:0 0 12px;font-family:var(--display);font-size:23px;font-weight:600;
  letter-spacing:-.01em;position:relative;z-index:1;
}
.top h1::before{
  content:"CENTRO DE ESTUDIOS SUPERIORES DEL MAYO";display:block;
  font-family:var(--texto);font-size:9.5px;font-weight:700;letter-spacing:.2em;
  color:var(--oro-pal);margin-bottom:5px;
}
.top h1 small{
  display:block;font-family:var(--texto);font-size:11.5px;font-weight:400;
  color:rgba(246,235,228,.62);letter-spacing:.01em;margin-top:3px;
  text-transform:capitalize;
}

/* ── Los contadores ───────────────────────────────────────────────────
   Son botones de filtro, no adornos: por eso el cursor cambia y el que
   está activo se invierte por completo. */
.cifras{display:flex;gap:8px;flex-wrap:wrap;position:relative;z-index:1}
.cifra{
  background:rgba(255,255,255,.08);border:1px solid rgba(229,199,160,.22);
  border-radius:11px;padding:9px 15px 8px;cursor:pointer;
  transition:transform .12s ease, background .15s ease, border-color .15s ease;
  min-width:96px;
}
.cifra:hover{background:rgba(255,255,255,.16);transform:translateY(-1px)}
.cifra.on{background:var(--hueso);color:var(--vino);border-color:var(--hueso)}
.cifra b{
  display:block;font-family:var(--display);font-size:26px;line-height:1;
  font-weight:600;letter-spacing:-.02em;
}
.cifra span{
  display:block;font-size:9.5px;letter-spacing:.11em;text-transform:uppercase;
  opacity:.8;margin-top:3px;font-weight:600;
}
.cifra.alerta b{color:#FFB4B4}
.cifra.on.alerta b{color:var(--rojo)}

/* ── Pestañas ── */
.pest{
  background:#fff;border-bottom:1px solid var(--gris);padding:0 26px;
  display:flex;gap:4px;position:sticky;top:0;z-index:20;
}
.pest button{
  background:none;border:0;border-bottom:2.5px solid transparent;
  padding:13px 4px;margin-right:22px;font-size:13.5px;cursor:pointer;
  color:var(--gris-txt);font-family:inherit;font-weight:600;letter-spacing:.01em;
}
.pest button:hover{color:var(--tinta)}
.pest button.on{color:var(--rojo);border-bottom-color:var(--rojo)}

/* ── Barra de filtros ── */
.barra{
  background:#fff;border-bottom:1px solid var(--gris);padding:12px 26px;
  display:flex;gap:9px;flex-wrap:wrap;align-items:center;
}
.barra input[type=search],.barra select{
  padding:9px 12px;border:1px solid var(--gris);border-radius:9px;
  font-size:13px;font-family:inherit;background:#fff;color:var(--tinta);
  transition:border-color .15s ease, box-shadow .15s ease;
}
.barra input[type=search]:focus,.barra select:focus{
  outline:0;border-color:var(--oro-med);box-shadow:0 0 0 3px rgba(203,163,112,.18);
}
.barra input[type=search]{flex:1;min-width:210px}
.cuenta{
  font-size:11.5px;color:var(--gris-txt);margin-left:auto;letter-spacing:.02em;
  font-variant-numeric:tabular-nums;
}

/* ── Las tarjetas ─────────────────────────────────────────────────────
   El borde izquierdo grueso es el semáforo. Es lo único que se ve al
   pasar la vista rápido por la columna, y por eso carga el estado. */
.lista{
  padding:18px 26px 56px;display:grid;gap:14px;
  grid-template-columns:repeat(auto-fill,minmax(430px,1fr));
}
.p{
  background:#fff;border:1px solid var(--gris);border-left:4px solid var(--gris);
  border-radius:13px;padding:15px 17px;box-shadow:var(--sombra);
  transition:box-shadow .16s ease, transform .16s ease;
}
.p:hover{box-shadow:var(--sombra-alta);transform:translateY(-1px)}
.p.grave{border-left-color:var(--rojo);background:linear-gradient(90deg,#FFF9F9,#fff 40%)}
.p.riesgo{border-left-color:var(--ambar)}
.p.ok{border-left-color:var(--verde)}
.p.listo{border-left-color:#0B6E4F;background:linear-gradient(90deg,#F5FBF7,#fff 40%)}
.p.fuera{border-left-color:#C9C4C1;opacity:.58}
.p h3{
  margin:0 0 2px;font-family:var(--display);font-size:17.5px;font-weight:600;
  letter-spacing:-.01em;line-height:1.25;
}
.meta{
  font-size:12px;color:var(--gris-txt);margin:0 0 10px;letter-spacing:.01em;
}
.meta b{color:var(--oro-txt);font-weight:600}

/* ── Etiquetas ── */
.tags{display:flex;gap:5px;flex-wrap:wrap;margin-bottom:10px}
.tag{
  font-size:10px;padding:3px 9px;border-radius:20px;background:#F4F1EF;
  color:#5B5451;letter-spacing:.03em;font-weight:600;white-space:nowrap;
}
.tag.rojo{background:var(--rojo-pal);color:#8E1A20}
.tag.ambar{background:var(--ambar-pal);color:#7E5A0C}
.tag.verde{background:var(--verde-pal);color:#14501F}
.tag.oro{background:#F8F1E6;color:var(--oro-txt)}

/* ── Lo que preguntó, y lo que sugerimos ──────────────────────────────
   Van con marca lateral y no en caja cerrada: se leen como una anotación
   al margen, que es lo que son. */
.preg,.sug{
  font-size:12.5px;line-height:1.55;padding:9px 12px;margin:0 0 10px;
  border-radius:0 9px 9px 0;
}
.preg{background:#FBF7F2;border-left:3px solid var(--oro-med);color:#4A423F}
.sug{background:var(--verde-pal);border-left:3px solid var(--verde);color:#28402C}
.sug b{
  display:block;font-size:9.5px;letter-spacing:.11em;text-transform:uppercase;
  color:var(--verde);margin-bottom:4px;font-weight:800;
}
.hist{
  font-size:11.5px;color:var(--gris-txt);white-space:pre-wrap;margin:0 0 10px;
  max-height:76px;overflow:auto;padding-left:11px;
  border-left:2px solid var(--gris);line-height:1.5;
}

/* ── Botones ── */
.acc{display:flex;gap:7px;flex-wrap:wrap;align-items:center}
button{
  font-family:inherit;font-size:12.5px;font-weight:600;padding:8px 13px;
  border-radius:9px;border:1px solid var(--gris);background:#fff;
  cursor:pointer;color:var(--tinta);letter-spacing:.01em;
  transition:background .14s ease, border-color .14s ease, transform .1s ease;
}
button:hover{background:#FAF7F5;border-color:var(--oro-med)}
button:active{transform:scale(.98)}
button.wa{
  background:var(--verde);color:#fff;border-color:var(--verde);
  box-shadow:0 1px 3px rgba(30,123,52,.28);
}
button.wa:hover{background:#186328;border-color:#186328}
button.pri{background:var(--rojo);color:#fff;border-color:var(--rojo)}
button.pri:hover{background:var(--rojo-osc);border-color:var(--rojo-osc)}
button[disabled]{opacity:.45;cursor:default;transform:none}
select.et{
  padding:7px 10px;border:1px solid var(--gris);border-radius:9px;
  font-size:12.5px;font-family:inherit;background:#fff;cursor:pointer;
  font-weight:600;color:var(--tinta);
}
.vacio{
  grid-column:1/-1;text-align:center;color:var(--gris-txt);padding:64px 20px;
  font-size:14px;
}

/* ── Tablero ── */
.insc-cab{display:flex;align-items:center;justify-content:space-between;gap:16px;
  flex-wrap:wrap;margin-bottom:14px}
.insc-cab b{display:block;font-size:15px}
.insc-cab span{display:block;font-size:12.5px;color:#7a7070;margin-top:2px}
.insc-btns{display:flex;gap:8px;align-items:center}
.insc-btns button,.insc-btns a{font:inherit;font-size:12.5px;font-weight:600;
  padding:8px 14px;border:1px solid #d9d0c2;border-radius:4px;background:#fff;
  color:#7A1426;cursor:pointer;text-decoration:none}
.insc-btns button:hover,.insc-btns a:hover{background:#faf6ee}
#inscMarco,#asistMarco{position:relative;min-height:70vh;border:1px solid #e3d9c7;border-radius:4px;
  overflow:hidden;background:#fff}
#inscMarco iframe,#asistMarco iframe{display:block;width:100%;height:78vh;border:0}
#inscMarco .cargando,#asistMarco .cargando{padding:40px;text-align:center;color:#8a8080;font-size:13.5px}
.tab{padding:22px 26px 56px;display:none}
.tab.on{display:block}
.rej{display:grid;gap:16px;grid-template-columns:repeat(auto-fit,minmax(320px,1fr))}
.caja{
  background:#fff;border:1px solid var(--gris);border-radius:14px;
  padding:18px 20px;box-shadow:var(--sombra);
}
.caja h3{
  margin:0 0 3px;font-family:var(--display);font-size:16.5px;font-weight:600;
}
.caja .sub{font-size:11.5px;color:var(--gris-txt);margin:0 0 14px;line-height:1.5}
.fila{
  display:flex;align-items:center;gap:10px;margin-bottom:8px;font-size:12.5px;
}
.fila .n{
  min-width:32px;text-align:right;font-weight:700;font-variant-numeric:tabular-nums;
  font-family:var(--display);font-size:15px;
}
.fila .b{flex:1;height:8px;background:#F0EDEB;border-radius:5px;overflow:hidden}
.fila .b i{
  display:block;height:100%;border-radius:5px;
  background:linear-gradient(90deg,var(--rojo),var(--oro));
}
.fila .t{min-width:140px;color:var(--gris-txt);font-size:11.5px}

/* ── Hallazgos: lo que hay que decidir hoy ── */
.hallazgo{
  border-left:3px solid var(--ambar);background:var(--ambar-pal);
  padding:12px 14px;border-radius:0 10px 10px 0;margin-bottom:11px;font-size:13px;
}
.hallazgo.malo{border-left-color:var(--rojo);background:var(--rojo-pal)}
.hallazgo.bueno{border-left-color:var(--verde);background:var(--verde-pal)}
.hallazgo b{
  display:block;margin-bottom:3px;font-size:13.5px;line-height:1.35;
  font-weight:700;
}
.hallazgo .q{font-size:12px;color:#5A524F;line-height:1.5}

/* ── Cuadros de diálogo ── */
dialog{
  border:0;border-radius:16px;padding:0;max-width:720px;width:94%;
  box-shadow:0 24px 70px rgba(40,38,38,.34);
}
dialog::backdrop{background:rgba(60,10,13,.55);backdrop-filter:blur(2px)}
.dlg{padding:24px}
.dlg h3{margin:0 0 4px;font-family:var(--display);font-size:19px;font-weight:600}
.dlg p.s{margin:0 0 16px;font-size:12.5px;color:var(--gris-txt);line-height:1.55}
.dlg textarea{
  width:100%;min-height:130px;padding:12px;border:1px solid var(--gris);
  border-radius:10px;font-family:inherit;font-size:13.5px;line-height:1.6;
  resize:vertical;background:var(--papel);
}
.dlg textarea:focus{
  outline:0;border-color:var(--oro-med);background:#fff;
  box-shadow:0 0 0 3px rgba(203,163,112,.18);
}
.dlg .fin{display:flex;gap:9px;justify-content:flex-end;margin-top:16px;flex-wrap:wrap}

#cargando{
  padding:80px 20px;text-align:center;color:var(--gris-txt);font-size:14px;
}

/* ── Acceso ───────────────────────────────────────────────────────────
   La puerta de entrada dice de quién es la casa. Y dice, en una línea,
   POR QUÉ hay contraseña: son datos de personas reales, no un trámite. */
#acceso{
  position:fixed;inset:0;z-index:99;padding:20px;
  align-items:center;justify-content:center;
  background:
    radial-gradient(120% 100% at 78% 10%, rgba(177,107,18,.28), transparent 58%),
    var(--vino);
}
#acceso::before{
  content:"";position:absolute;left:6%;bottom:-40px;width:300px;height:300px;
  background:url('/assets/img/venado-blanco.webp') center/contain no-repeat;
  opacity:.05;pointer-events:none;
}
.tarjeta-acceso{
  background:#fff;border-radius:18px;padding:34px 32px;max-width:392px;
  width:100%;box-shadow:0 30px 80px rgba(0,0,0,.34);position:relative;
  border-top:3px solid var(--oro);
}
.tarjeta-acceso .rotulo{
  font-size:9.5px;letter-spacing:.2em;text-transform:uppercase;
  color:var(--oro-txt);margin:0 0 10px;font-weight:700;
}
.tarjeta-acceso h2{
  margin:0 0 6px;font-family:var(--display);font-size:27px;font-weight:600;
  color:var(--rojo);letter-spacing:-.02em;
}
.tarjeta-acceso .intro{
  margin:0 0 22px;font-size:12.5px;color:var(--gris-txt);line-height:1.6;
}
.tarjeta-acceso input{
  width:100%;padding:12px 14px;border:1px solid var(--gris);border-radius:10px;
  font-size:14px;font-family:inherit;margin-bottom:10px;background:var(--papel);
}
.tarjeta-acceso input:focus{
  outline:0;border-color:var(--oro-med);background:#fff;
  box-shadow:0 0 0 3px rgba(203,163,112,.2);
}
.tarjeta-acceso .pie{
  font-size:10.5px;color:var(--gris-txt);margin:14px 0 0;line-height:1.55;
}
#acError{
  color:var(--rojo);font-size:12.5px;margin:2px 0 0;display:none;
  background:var(--rojo-pal);padding:9px 11px;border-radius:8px;line-height:1.45;
}
#acEntrar{width:100%;margin-top:16px;padding:13px;font-size:14.5px}

@media (max-width:640px){
  .top,.pest,.barra,.lista,.tab{padding-left:16px;padding-right:16px}
  .lista{grid-template-columns:1fr}
  .top::after{display:none}
  .top h1{font-size:20px}
  .cifra{min-width:0;flex:1;padding:8px 11px}
  .cifra b{font-size:22px}
}

/* ── (21-sep) Informe para publicidad ─────────────────────────────── */
#informePub{position:fixed;inset:0;z-index:9999;background:rgba(30,23,23,.55);overflow:auto;padding:28px 12px}
.ip-hoja{max-width:860px;margin:0 auto;background:#fff;border-radius:6px;padding:30px 34px;font-family:Montserrat,'Segoe UI',Arial,sans-serif;color:#1E1717;font-size:13px;line-height:1.55}
.ip-opc{max-width:560px}
.ip-opc h2{margin:0 0 6px;font-size:19px;color:#7A1426}
.ip-opc label{display:block;font-size:12.5px;font-weight:600;margin-top:10px}
.ip-opc select,.ip-opc input{display:block;width:100%;margin-top:4px;font:inherit;padding:8px 10px;border:1px solid #d9d0c2;border-radius:4px;box-sizing:border-box}
.ip-inv{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px}
.ip-btns{display:flex;gap:8px;justify-content:flex-end;margin:16px 0 6px;flex-wrap:wrap}
.ip-btns button{font:inherit;font-size:13px;padding:9px 16px;border:1px solid #d9d0c2;border-radius:4px;background:#fff;color:#7A1426;cursor:pointer}
.ip-btns .ip-pri{background:#7A1426;color:#fff;border-color:#7A1426;font-weight:600}
.ip-sub{color:#6b5f5f;font-size:12.5px}
.ip-cab{border-bottom:3px solid #B18A4A;padding-bottom:12px;margin-bottom:16px}
.ip-ins{font-size:10.5px;letter-spacing:2px;text-transform:uppercase;color:#B18A4A;font-weight:700}
.ip-cab h1{margin:4px 0 2px;font-size:21px;color:#7A1426}
.ip-kpis{display:-webkit-box;display:flex;flex-wrap:wrap;margin:0 -4px 10px}
.ip-kpi{-webkit-box-flex:1;flex:1 1 0;min-width:120px;margin:0 4px 8px;border:1px solid #E3D9C7;border-radius:5px;padding:10px 12px;background:#FBF8F3;box-sizing:border-box}
.ip-kpi b{display:block;font-size:20px;color:#7A1426;line-height:1.2}
.ip-kpi span{font-size:11px;color:#6b5f5f}
.ip-sec{margin-top:18px}
.ip-sec h3{font-size:14px;margin:0 0 8px;color:#1E1717;border-left:4px solid #7A1426;padding-left:8px}
.ip-rec{padding:9px 12px;border-radius:4px;margin-bottom:6px;font-size:12.5px;border-left:4px solid}
.ip-alta{background:#FBECEC;border-color:#98241F}
.ip-buena{background:#EAF6EC;border-color:#1E7F52}
.ip-media{background:#FBF6EC;border-color:#B18A4A}
.ip-info{background:#F2F0F4;border-color:#8a8a9a}
.ip-t{width:100%;border-collapse:collapse;font-size:12.5px}
.ip-t th{text-align:left;background:#7A1426;color:#fff;padding:7px 8px;font-weight:600}
.ip-t td{padding:6px 8px;border-bottom:1px solid #EFE8DC}
.ip-t .n{text-align:right;white-space:nowrap}
.ip-barras td:nth-child(n+2){white-space:nowrap}
.ip-bar{display:inline-block;height:9px;background:#7A1426;border-radius:2px;margin-right:6px;vertical-align:middle;min-width:2px;max-width:150px}
.ip-bar2{background:#B18A4A}
.ip-dos{display:-webkit-box;display:flex;gap:18px}
.ip-dos > div{-webkit-box-flex:1;flex:1 1 0;min-width:0}
.ip-nota{font-size:11.5px;color:#6b5f5f;margin:6px 0 0}
@media (max-width:700px){.ip-kpi{min-width:40%}.ip-dos{display:block}.ip-inv{grid-template-columns:1fr}.ip-hoja{padding:20px}}
@media print{
  body > *:not(#informePub){display:none !important}
  #informePub{position:static !important;background:#fff !important;padding:0 !important;overflow:visible !important}
  .ip-hoja{max-width:none;padding:0;border-radius:0}
  .no-print{display:none !important}
  .ip-sec,.ip-kpis,.ip-rec,tr{break-inside:avoid}
  .ip-t th,.ip-bar,.ip-rec,.ip-kpi{-webkit-print-color-adjust:exact;print-color-adjust:exact}
  @page{size:A4;margin:13mm}
}
/* (25-sep) Centro de mensajes */
.env-caja{background:#fff;border:1px solid #e6ddd0;border-radius:8px;padding:16px 18px;margin-bottom:14px;max-width:860px}
.env-caja h3{margin:0 0 8px;font-size:16px;color:#7A1426}
.env-sub{font-size:13px;color:#5f564a;margin:8px 0 6px}
.env-chips{display:flex;flex-wrap:wrap;gap:6px}
.env-chip{font-size:12.5px;border:1px solid #d9d0c2;border-radius:16px;padding:4px 10px;cursor:pointer;background:#fff}
.env-chip.on{border-color:#7A1426;background:#F7ECEE}
.env-chip input{margin:0 4px 0 0;vertical-align:middle}
.env-total{font-size:14px;margin:10px 0 4px}
.env-lista{max-height:260px;overflow:auto;border:1px solid #eee4d6;border-radius:6px;padding:6px;margin-top:6px}
.env-fila{display:block;font-size:12.5px;padding:3px 2px}
#v-envios textarea{width:100%;box-sizing:border-box;font:inherit;font-size:13.5px;padding:8px;border:1px solid #d9d0c2;border-radius:6px}
.env-btn{font:inherit;padding:9px 16px;border:0;border-radius:5px;background:#7A1426;color:#fff;cursor:pointer}
.env-btn[disabled]{opacity:.5;cursor:default}
.env-btn2{font:inherit;padding:8px 14px;border:1px solid #d9d0c2;border-radius:5px;background:#fff;color:#7A1426;cursor:pointer}
.env-alerta{background:#FBEFEF;border-left:3px solid #B11D29;padding:8px 12px;font-size:12.8px;margin:10px 0;border-radius:3px}
.env-nota{background:#FBF6EC;border-left:3px solid #B18A4A;padding:8px 12px;font-size:12.8px;margin:10px 0;border-radius:3px;color:#5f4a20}
.env-previa{background:#E7F7EE;border:1px solid #cfe9da;border-radius:8px;padding:10px 12px;font-size:13.5px;line-height:1.45;white-space:normal}
.env-barra{height:8px;background:#eee4d6;border-radius:4px;overflow:hidden}
.env-barra div{height:100%;background:#7A1426}

/* ══════════════════════════════════════════════════════════════════════
   (28-sep) CIERRE 26-4 · estilos del tablero. Prefijo ci- para no chocar
   con nada existente; solo usa la paleta del panel.
   ══════════════════════════════════════════════════════════════════════ */
#v-cierre .ci-top{display:flex;flex-wrap:wrap;gap:22px;align-items:flex-end;justify-content:space-between;margin-bottom:14px}
#v-cierre .ci-rot{font-size:9.5px;letter-spacing:.2em;text-transform:uppercase;color:var(--oro-txt);font-weight:700}
#v-cierre .ci-cuenta h2{margin:4px 0 2px;font-family:var(--display);font-size:34px;font-weight:600;color:var(--rojo);letter-spacing:-.02em;line-height:1.1}
#v-cierre .ci-cuenta p{margin:0;color:var(--gris-txt);font-size:13px}
#v-cierre .ci-kpis{display:flex;flex-wrap:wrap;gap:10px}
#v-cierre .ci-kpi{background:#fff;border:1px solid var(--gris);border-radius:12px;padding:10px 16px;min-width:112px;box-shadow:var(--sombra)}
#v-cierre .ci-kpi b{display:block;font-family:var(--display);font-size:28px;line-height:1.1;color:var(--vino)}
#v-cierre .ci-kpi span{font-size:11.5px;color:var(--gris-txt)}
#v-cierre .ci-prog{margin:0 0 16px}
#v-cierre .ci-bar{height:10px;background:var(--gris);border-radius:99px;overflow:hidden}
#v-cierre .ci-bar i{display:block;height:100%;background:linear-gradient(90deg,var(--oro-med),var(--oro));border-radius:99px}
#v-cierre .ci-prog p{margin:7px 0 0;font-size:13px;color:var(--tinta);line-height:1.5}
#v-cierre .ci-peq{font-size:11.5px;color:var(--gris-txt)}
#v-cierre .ci-aviso{background:var(--ambar-pal);border:1px solid var(--oro-pal);border-left:4px solid var(--ambar);border-radius:8px;padding:10px 14px;margin:0 0 10px;font-size:13px;line-height:1.5}
#v-cierre .ci-aviso.ci-ok{background:var(--verde-pal);border-color:#cfe6d4;border-left-color:var(--verde)}
#v-cierre .ci-caja{background:#fff;border:1px solid var(--gris);border-radius:14px;padding:16px 18px;margin:0 0 16px;box-shadow:var(--sombra)}
#v-cierre .ci-caja h3{margin:0 0 8px;font-family:var(--display);font-size:19px;color:var(--vino);font-weight:600}
#v-cierre .ci-cab{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:baseline;gap:6px}
#v-cierre .ci-cab span{font-size:12px;color:var(--gris-txt)}
#v-cierre .ci-grid{display:grid;gap:16px;grid-template-columns:repeat(auto-fit,minmax(310px,1fr))}
#v-cierre .ci-lect{font-size:14.5px;line-height:1.6;margin:0 0 8px}
#v-cierre .ci-acciones{margin:0 0 8px 18px;padding:0;font-size:13.5px;line-height:1.55}
#v-cierre .ci-acciones li{margin-bottom:4px}
#v-cierre .ci-riesgo{background:var(--rojo-pal);border-radius:8px;padding:9px 12px;font-size:13px;margin:8px 0}
#v-cierre .ci-err{color:var(--rojo);font-size:13px}
#v-cierre .ci-fila{border-top:1px solid var(--gris);padding:12px 0}
#v-cierre .ci-fila:first-of-type{border-top:0}
#v-cierre .ci-fila.hecho{opacity:.45}
#v-cierre .ci-fn b{font-family:var(--display);font-size:18px;color:var(--tinta);font-weight:600}
#v-cierre .ci-fn span{display:block;font-size:12px;color:var(--gris-txt)}
#v-cierre .ci-fn em{display:block;font-size:12px;color:var(--oro-txt);font-style:normal;margin-top:2px}
#v-cierre .ci-fn i{display:inline-block;font-style:normal;font-size:10.5px;background:var(--ambar-pal);color:var(--ambar);border-radius:99px;padding:1px 8px;margin:4px 6px 0 0}
#v-cierre .ci-acc{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-top:8px}
#v-cierre .ci-b{font:inherit;font-size:12.5px;font-weight:600;padding:7px 13px;border:1px solid #d9d0c2;border-radius:8px;background:#fff;color:var(--vino);cursor:pointer;text-decoration:none}
#v-cierre .ci-b:hover{background:#faf6ee}
#v-cierre .ci-b.pri{background:var(--rojo);border-color:var(--rojo);color:#fff}
#v-cierre .ci-b.pri:hover{background:var(--rojo-osc)}
#v-cierre .ci-b[disabled]{opacity:.55;cursor:default}
#v-cierre details{font-size:12.5px;color:var(--gris-txt)}
#v-cierre details p{margin:6px 0 0;padding:8px 10px;background:var(--hueso);border-radius:8px;color:var(--tinta);line-height:1.5}
#v-cierre .ci-ta{width:100%;min-height:110px;margin-top:8px;padding:10px;border:1px solid var(--gris);border-radius:8px;font:inherit;font-size:13px;line-height:1.5}
#v-cierre .ci-stat{display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px dashed var(--gris);font-size:13px}
#v-cierre .ci-stat b{color:var(--vino)}
#v-cierre .ci-can{margin:7px 0}
#v-cierre .ci-can div{display:flex;justify-content:space-between;font-size:12.5px}
#v-cierre .ci-can i{display:block;height:7px;border-radius:99px;background:var(--oro-med);margin-top:3px}
#v-cierre .ci-serie{display:flex;align-items:flex-end;gap:5px;height:90px;margin-top:8px}
#v-cierre .ci-serie div{flex:1;background:var(--oro-med);border-radius:4px 4px 0 0;min-height:2px;position:relative}
#v-cierre .ci-serie div.hoy{background:var(--rojo)}
#v-cierre .ci-serie-e{display:flex;gap:5px;font-size:9.5px;color:var(--gris-txt);margin-top:3px}
#v-cierre .ci-serie-e span{flex:1;text-align:center}
#v-cierre .ci-lista{list-style:none;margin:0 0 10px;padding:0;font-size:13px;line-height:1.5}
#v-cierre .ci-lista li{margin-bottom:6px}
#v-cierre .ci-si{color:var(--verde)}
#v-cierre .ci-no{color:var(--rojo)}
#v-cierre .ci-form input{display:block;width:100%;max-width:320px;margin:0 0 8px;padding:9px 11px;border:1px solid var(--gris);border-radius:8px;font:inherit;font-size:13px}
#v-cierre .ci-res{font-size:12.5px;line-height:1.5;margin-top:8px}

/* ══════════════════════════════════════════════════════════════════════
   (28-sep) WHATSAPP CON IA · diálogo, barra de conversaciones por actualizar
   ══════════════════════════════════════════════════════════════════════ */
#waDlg{border:0;padding:0;border-radius:16px;width:min(700px,94vw);max-height:92vh;box-shadow:0 24px 70px rgba(40,38,38,.32);background:#fff;color:var(--tinta);font-family:var(--texto)}
#waDlg::backdrop{background:rgba(40,20,22,.5)}
.wa-cuerpo{display:flex;flex-direction:column;max-height:92vh}
.wa-cab{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;padding:16px 20px 12px;border-bottom:1px solid var(--gris);background:var(--hueso)}
.wa-cab b{display:block;font-family:var(--display);font-size:20px;color:var(--vino);font-weight:600;line-height:1.2}
.wa-cab span{display:block;font-size:12px;color:var(--gris-txt);margin-top:3px}
.wa-cab button{font:inherit;font-size:22px;line-height:1;border:0;background:none;color:var(--gris-txt);cursor:pointer;padding:0 4px}
#waCont{padding:16px 20px 18px;overflow:auto}
.wa-ctx{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 10px}
.wa-chip{font-size:11px;background:var(--hueso);border-radius:99px;padding:2px 10px;color:var(--tinta)}
.wa-conv{border-radius:10px;padding:10px 12px;margin:0 0 12px;font-size:12.5px;line-height:1.5;display:flex;justify-content:space-between;gap:10px;align-items:center;flex-wrap:wrap}
.wa-conv.ok{background:var(--verde-pal);border:1px solid #cfe6d4}
.wa-conv.aviso{background:var(--ambar-pal);border:1px solid var(--oro-pal);border-left:4px solid var(--ambar)}
#waCont label{display:block;font-size:12px;font-weight:600;margin:10px 0 4px;color:var(--tinta)}
#waCont input[type=text],#waCont select,#waCont textarea{width:100%;font:inherit;font-size:13.5px;padding:9px 11px;border:1px solid var(--gris);border-radius:8px;background:#fff;color:var(--tinta)}
#waCont textarea{min-height:130px;line-height:1.55;resize:vertical}
#waCont textarea.wa-peq{min-height:70px}
#waCont textarea.wa-grande{min-height:210px}
.wa-tabs{display:flex;gap:6px;margin:12px 0 6px}
.wa-tabs button,.wa-b{font:inherit;font-size:12.5px;font-weight:600;padding:7px 14px;border:1px solid #d9d0c2;border-radius:8px;background:#fff;color:var(--vino);cursor:pointer}
.wa-tabs button.on{background:var(--vino);color:#fff;border-color:var(--vino)}
.wa-b:hover{background:#faf6ee}
.wa-b.pri{background:var(--rojo);border-color:var(--rojo);color:#fff}
.wa-b.pri:hover{background:var(--rojo-osc)}
.wa-b.verde{background:#1E7B34;border-color:#1E7B34;color:#fff}
.wa-b[disabled]{opacity:.55;cursor:default}
.wa-acc{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px;justify-content:flex-end}
.wa-acc .wa-izq{margin-right:auto}
.wa-meta{font-size:11.5px;color:var(--gris-txt);margin:6px 0 0;line-height:1.5}
.wa-alertas{background:var(--rojo-pal);border:1px solid #f0c9c9;border-left:4px solid var(--rojo);border-radius:8px;padding:9px 12px;margin:10px 0 0;font-size:12.5px;line-height:1.5}
.wa-alertas b{color:var(--rojo)}
.wa-err{color:var(--rojo);font-size:13px;margin:8px 0}
.wa-cargando{padding:26px 10px;text-align:center;color:var(--gris-txt);font-size:13.5px}
.wa-ayuda{font-size:13px;line-height:1.55;margin:0 0 10px}
.wa-guardada{background:var(--hueso);border-radius:8px;padding:9px 12px;font-size:12px;color:var(--gris-txt);margin:0 0 8px;line-height:1.5;white-space:pre-wrap;word-break:break-word}
.wa-chk{display:flex!important;gap:8px;align-items:flex-start;font-weight:500!important;font-size:12.5px!important;margin:8px 0!important}
.wa-chk input{margin-top:3px}
.wa-hint{font-size:12px;color:var(--oro-txt);margin:4px 0 0}
.wa-info{background:var(--hueso);border-radius:8px;padding:9px 12px;font-size:12.5px;line-height:1.55;margin:8px 0}
.wa-info b{color:var(--vino)}
.wa-sug{display:inline-block;font:inherit;font-size:11.5px;border:1px dashed var(--oro);background:var(--ambar-pal);border-radius:99px;padding:2px 10px;margin-left:6px;cursor:pointer;color:var(--oro-txt)}
#waBarra{position:fixed;left:50%;transform:translateX(-50%);bottom:14px;z-index:70;max-width:min(720px,94vw);background:var(--vino);color:#fff;border-radius:14px;padding:11px 14px 11px 18px;box-shadow:0 10px 40px rgba(40,20,22,.4);display:none;align-items:center;gap:12px;flex-wrap:wrap;font-size:13px;line-height:1.4}
#waBarra b{font-weight:700}
#waBarra span{opacity:.85;font-size:12px}
#waBarra button{font:inherit;font-size:12.5px;font-weight:700;border:0;border-radius:8px;padding:7px 13px;cursor:pointer}
#waBarra .si{background:var(--oro-pal);color:var(--vino)}
#waBarra .no{background:transparent;color:#fff;opacity:.7;padding:4px 8px;font-size:18px}
button.wa-pend,.acc button.wa-pend{border-color:var(--ambar)!important;background:var(--ambar-pal)!important;color:var(--oro-txt)!important}
</style>
</head>
<body>


<div id="acceso" style="display:none">
  <div class="tarjeta-acceso">
    <p class="rotulo">Centro de Estudios Superiores del Mayo</p>
    <h2>Admisiones</h2>
    <p class="intro">Aquí están los nombres, teléfonos y correos de quienes
      pidieron informes. Son personas reales que confiaron sus datos: por eso
      esta pantalla pide contraseña.</p>
    <input id="acCorreo" type="email" placeholder="Correo institucional"
      autocomplete="username">
    <input id="acClave" type="password" placeholder="Contraseña"
      autocomplete="current-password">
    <p id="acError"></p>
    <button id="acEntrar" class="pri">Entrar</button>
    <p class="pie">La sesión dura 12 horas y se cierra al cerrar la pestaña.
      Cinco intentos fallidos bloquean el acceso quince minutos.</p>
  </div>
</div>

<div id="cargando">Cargando prospectos…</div>

<div id="app" style="display:none">
  <div class="top">
    <h1>Seguimiento de admisiones<small id="hoy"></small></h1>
    <div class="cifras" id="cifras"></div>
  </div>

  <div class="pest">
    <button data-v="cola" class="on">La cola de hoy</button>
      <button data-v="cierre">Cierre 26-4</button>
      <button data-v="impulso">Impulso CESSUM</button>
    <button data-v="tablero">Tablero de decisión</button>
    <button data-v="ritmo">Ritmo del equipo</button>
    <button data-v="correos">Correos enviados</button>
    <button data-v="inscripciones">Inscripciones</button>
    <button data-v="asistente">Responder WhatsApp</button>
    <button data-v="repetidos">Repetidos</button>
    <button data-v="publicidad">Publicidad y CAC</button>
    <button data-v="prioridad">Prioridad</button>
    <button data-v="bot">Bot de WhatsApp</button>
    <button data-v="envios">Centro de mensajes</button>
  </div>

  <div id="v-repetidos" style="display:none"></div>
  <div id="v-publicidad" style="display:none"></div>
  <div id="v-prioridad" style="display:none"></div>
  <div id="v-bot" style="display:none"></div>
  <div id="v-envios" style="display:none;padding:22px 26px 56px"></div>
  <div id="v-impulso" style="display:none;padding:22px 26px 56px"></div>

  <div id="v-cola">
    <div class="barra">
      <input type="search" id="q" placeholder="Buscar por nombre, correo, teléfono o programa…">
      <select id="fEtapa"><option value="">Todas las etapas</option></select>
      <select id="fPrograma"><option value="">Todos los programas</option></select>
      <select id="fAsesor"><option value="">Todos los asesores</option></select>
      <button id="btnAlta" class="pri" title="Dar de alta a quien escribió por WhatsApp · tecla A">+ Alta manual</button>
      <button id="enfoque" class="pri" title="Trabajar la cola de uno en uno · tecla F">Modo enfoque</button>
      <button id="recargar" title="Actualizar · tecla R">Actualizar</button>
      <button id="cruzar" title="Marca como Inscrito a quien ya aparece en las inscripciones">Cruzar con inscripciones</button>
      <button id="exportar" title="Descargar la lista en CSV">Exportar</button>
      <button id="salir">Salir</button>
      <span class="cuenta" id="cuenta"></span>
      <span style="font-size:10.5px;color:var(--gris-txt);letter-spacing:.02em;
        width:100%;margin-top:2px;">Atajos: <b>/</b> buscar · <b>1</b> te
        esperan · <b>2</b> sin contactar · <b>3</b> todos · <b>T</b> tablero ·
        <b>M</b> ritmo · <b>C</b> correos · <b>A</b> alta manual · <b>F</b> enfoque · <b>R</b> actualizar</span>
    </div>
    <!-- ALTA MANUAL · 8-sep-2026
         Solo entraba quien llenaba el formulario del sitio. A la línea de
         Admisiones le escriben directo por WhatsApp y esa gente no existía
         para el panel. Se captura aquí, en la misma lista: hereda etapa,
         asesor, semáforo de días y sugerencias sin nada extra.
         Va cerrado por omisión para no estorbar la cola, que es lo que se
         viene a trabajar. -->
    <div id="alta" style="display:none;background:var(--papel);
         border:1px solid var(--oro-pal);border-radius:14px;padding:18px;margin-bottom:18px">
      <div style="font-family:var(--display);font-size:19px;margin-bottom:2px">Alta manual</div>
      <div style="font-size:12.5px;color:var(--gris-txt);margin-bottom:14px">
        Para quien escribió por WhatsApp o llamó. Lo más rápido: pega la conversación completa y deja que la IA llene los campos. Con el teléfono basta; lo demás se completa después.</div>

      <!-- (9-sep) PEGAR LA CONVERSACIÓN Y PERFILAR. Teclear campo por campo es
           lento y se olvida lo que la persona dijo. Pegada de un jalón, la IA
           saca nombre, programa, modalidad y qué preguntó, y lo pone en los
           campos para revisarlo. La conversación completa queda guardada en
           la ficha, para que otro asesor pueda retomarla. -->
      <!-- (9-sep) VARIOS PROGRAMAS A LA VEZ. Mucha gente pide informes de dos
           o tres antes de decidir, y con un solo campo había que abrirle una
           ficha por programa —o quedarse con uno y perder el otro interés—.
           El principal manda para las métricas; los demás quedan registrados
           y la sugerencia de mensaje los atiende juntos. -->
      <div id="aOtrosCaja" style="margin:4px 0 12px;display:none">
        <label style="font-size:12px;color:var(--gris-txt)">¿Preguntó por más de uno? Marca los demás</label>
        <div id="aOtros" style="display:flex;flex-wrap:wrap;gap:6px 14px;margin-top:6px"></div>
      </div>

      <label style="font-size:12px;color:var(--gris-txt)">Conversación de WhatsApp (pégala completa, o desde donde la persona escribió)</label>
      <textarea id="aConv" rows="5" style="width:100%"
        placeholder="Pega aquí todo el chat. La IA lo lee y llena los campos de abajo; tú revisas y registras."></textarea>
      <div style="margin:8px 0 14px;display:flex;gap:10px;align-items:center;flex-wrap:wrap">
        <button id="aPerfilar" class="pri">Perfilar con IA</button>
        <span id="aPerfilMsg" style="font-size:12.5px;color:var(--gris-txt)"></span>
      </div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:11px">
        <div><label style="font-size:12px;color:var(--gris-txt)">Teléfono</label>
          <input type="text" id="aTel" inputmode="tel" style="width:100%"></div>
        <div><label style="font-size:12px;color:var(--gris-txt)">Nombre</label>
          <input type="text" id="aNom" style="width:100%"></div>
        <div><label style="font-size:12px;color:var(--gris-txt)">Programa principal</label>
          <select id="aProg" style="width:100%"><option value="">—</option><option value="Preguntó en general">Preguntó en general (no eligió programa)</option></select></div>
        <div><label style="font-size:12px;color:var(--gris-txt)">Origen</label>
          <select id="aOrig" style="width:100%">
            <option>WhatsApp</option><option>Llamada</option><option>Presencial</option>
            <option>Facebook</option><option>Referido</option><option>Otro</option>
          </select></div>
        <div><label style="font-size:12px;color:var(--gris-txt)">Correo (opcional)</label>
          <input type="text" id="aCorreo" style="width:100%"></div>
        <!-- (9-sep) La fecha real en que pidió informes. Se registraba siempre
             la de hoy, así que al capturar conversaciones de días atrás todo
             el mundo quedaba como recién llegado y el semáforo mentía. -->
        <div><label style="font-size:12px;color:var(--gris-txt)">¿Cuándo pidió informes?</label>
          <input type="date" id="aFecha" style="width:100%"></div>
      </div>
      <div style="height:11px"></div>
      <label style="font-size:12px;color:var(--gris-txt)">Qué preguntó · esto alimenta la sugerencia de mensaje</label>
      <textarea id="aCtx" rows="2" style="width:100%"
        placeholder="Preguntó por la maestría en educación, trabaja de mañana, quiere saber si puede con el trabajo…"></textarea>
      <div style="height:13px"></div>
      <button id="aGuardar" class="pri">Registrar</button>
      <button id="aCerrar">Cancelar</button>
      <span id="aMsg" style="margin-left:12px;font-size:13px"></span>
    </div>

    <div class="lista" id="lista"></div>
  </div>

  <div class="tab" id="v-tablero"></div>
  <div class="tab" id="v-ritmo"></div>
  <div class="tab" id="v-correos"></div>
  <!-- (14-sep) INSCRIPCIONES. Vivían en otra ventana, y admisiones es donde
       se pregunta cuántos se inscribieron hoy. Por ahora se trae el panel del
       Guardián dentro de esta pestaña: son dos sistemas —este panel habla con
       admisiones.php y el de inscripciones con guardian.php— y unificarlos de
       verdad es mover las respuestas de los formularios a esta misma base. -->
  <!-- (15-sep) ASISTENTE DE ADMISIONES. Los mensajes oficiales por programa,
       listos para copiar, y una consulta con IA que solo responde con lo que
       dicen las convocatorias. Vive en el Guardián y se abre aquí dentro. -->
  <div class="tab" id="v-asistente">
    <div class="insc-cab">
      <div>
        <b>Respuestas para WhatsApp</b>
        <span>Mensajes oficiales por programa y consulta para preguntas sueltas.</span>
      </div>
      <div class="insc-btns">
        <a id="asistAbrir" href="#" target="_blank" rel="noopener">Abrir en pestaña nueva</a>
      </div>
    </div>
    <div id="asistMarco"></div>
  </div>

  <div class="tab" id="v-inscripciones">
    <div class="insc-cab">
      <div>
        <b>Inscripciones de los formularios oficiales</b>
        <span>Licenciatura, Maestría en Educación y demás programas de posgrado.</span>
      </div>
      <div class="insc-btns">
        <button type="button" id="inscInforme" style="background:#7A1426;color:#fff;border-color:#7A1426">Informe para publicidad (PDF)</button>
        <button type="button" id="inscRecargar">Actualizar</button>
        <a id="inscAbrir" href="https://app.cessum.mx/" target="_blank" rel="noopener">Revisar expedientes en la app</a>
      </div>
    </div>
    <div id="inscMarco"></div>
  </div>

  <div class="tab" id="v-cierre"></div>
</div>

<dialog id="dlg">
  <div class="dlg">
    <h3 id="dlgTit">Registrar</h3>
    <p class="s" id="dlgSub"></p>
    <textarea id="dlgTxt"></textarea>
    <div class="fin" id="dlgFin"></div>
  </div>
</dialog>

<dialog id="waDlg">
  <div class="wa-cuerpo">
    <div class="wa-cab"><div><b id="waTit"></b><span id="waSub"></span></div><button type="button" id="waCerrar" aria-label="Cerrar">×</button></div>
    <div id="waCont"></div>
  </div>
</dialog>
<div id="waBarra" role="status"></div>

<script>
var DATOS = null, FILTRO = '', VISTA = 'cola';

/* ── EL PUENTE ────────────────────────────────────────────────────────
   Todo pasa por admisiones.php, en nuestro propio servidor. La página
   nunca sabe a qué proyecto de Google apunta: esa dirección vive solo en
   el PHP, así que no se puede leer desde el navegador. */
/* (18-sep) LAS CONSULTAS VAN POR GET; LO QUE ESCRIBE, POR POST.
   La misma petición escrita en la barra de direcciones traía los datos, y
   desde aquí fallaba con un 404. La única diferencia era el método: la barra
   manda GET y esto mandaba POST. Se igualan las consultas —leer datos,
   entrar, ver una ficha— a lo que sí funciona.
   Lo que ESCRIBE sigue por POST: guardar, dar de alta o borrar no debe
   viajar en la dirección, donde queda registrado en los accesos del
   servidor. Y la contraseña tampoco. */
var API_ESCRIBEN = ['guardar', 'alta', 'borrar', 'redactar', 'perfilar', 'envio_redactar',
                    'whatsapp', 'sesion_registro', 'sesion_asistio', 'login',
                    /* (28-sep) escriben en la hoja o llevan contraseñas: nunca por la dirección */
                    'alta_inscritos', 'automatizar_instalar', 'automatizar_quitar', 'cambiar_clave',
                    'repetidos_ia', 'repetidos_aplicar', 'conv_leer'];

/* (22-sep) viaGet: el plan B cuando el POST tropieza. Se comprobó que la
   MISMA acción pasa siempre por GET y falla a ratos por POST. Se mantiene
   POST como camino normal —lo que escribe no debe quedar en los registros
   de acceso del servidor— y solo se repite por GET si el POST no llegó.
   La contraseña NUNCA usa este plan B: entrar sigue siendo POST. */
/* (25-sep) «Actualizar» pide la lista FRESCA: se salta la caché del puente
   (2 min) y la del Apps Script (10 min). Al terminar la carga vuelve a false. */
var FRESCO = false;
function api(accion, datos, viaGet) {
  var cuerpo = new URLSearchParams(datos || {});
  cuerpo.append('accion', accion);
  if (FRESCO && accion === 'datos') cuerpo.append('fresco', '1');

  var peticion = (viaGet || API_ESCRIBEN.indexOf(accion) < 0)
    ? fetch('/admisiones.php?' + cuerpo.toString(), { method: 'GET' })
    : fetch('/admisiones.php', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: cuerpo.toString()
      });
  /* (22-sep) SI EL SERVIDOR RESPONDE ALGO QUE NO ES JSON, NO SE ROMPE.
     Cuando Google tarda en despertar, el hosting a veces devuelve su propia
     página de error. r.json() reventaba y el panel caía en «Error de
     conexión», que no se reintentaba: por eso el primer clic fallaba y el
     segundo entraba. Ahora cualquier falla de red o de formato vuelve como
     una respuesta normal con ok:false y red:true, y quien llama decide si
     reintenta. */
  return peticion.then(function (r) { return r.text(); }).then(function (t) {
    try { return JSON.parse(t); }
    catch (e) {
      return { ok: false, red: true,
        error: 'El servidor respondió algo inesperado. Intenta de nuevo.' };
    }
  }, function (e) {
    return { ok: false, red: true,
      error: 'No hubo respuesta del servidor (' + e + ').' };
  });
}

/* (22-sep) DESPERTAR AL SERVIDOR MIENTRAS SE ESCRIBE LA CONTRASEÑA.
   Apps Script se duerme tras un rato sin uso y la primera petición tarda.
   En cuanto aparece la pantalla de acceso se hace una consulta inofensiva
   —pedir datos con un pase que no existe: el servidor solo responde
   «expirado», no lee la hoja y NO cuenta como intento fallido—. Para cuando
   se termina de escribir la contraseña, ya está despierto. */
/* (22-sep) LAS ESCRITURAS TAMBIÉN REINTENTAN.
   El acceso ya reintentaba ante un tropiezo del servidor, pero guardar,
   registrar un WhatsApp o archivar una ficha fallaban al primer intento:
   con Apps Script dormido, la primera petición se cae a menudo. Se reintenta
   hasta dos veces con una pausa creciente, y solo se avisa si de verdad no
   se pudo. Los rechazos con razón —sesión caducada, fila inválida— no se
   reintentan: eso no lo arregla insistir. */
function apiEscribir(accion, datos, intento) {
  intento = intento || 0;
  // El primer intento va por POST; si tropieza, los siguientes por GET.
  return api(accion, datos, intento > 0).then(function (r) {
    var esTropiezo = (!r || (!r.ok && !r.expirado && r.red)) ||
      (r && !r.ok && /inesperado|no se pudo consultar|sin respuesta/i.test(String(r.error || '')));
    if (esTropiezo && intento < 2) {
      return new Promise(function (listo) {
        setTimeout(function () { listo(apiEscribir(accion, datos, intento + 1)); },
          1200 * (intento + 1));
      });
    }
    return r;
  });
}

var DESPIERTO = false;
function despertar() {
  if (DESPIERTO) return;
  DESPIERTO = true;
  api('datos', { pase: 'despertar' });
}


/* ── ACCESO ──────────────────────────────────────────────────────────
   El pase se guarda en sessionStorage, no en localStorage: al cerrar la
   pestaña desaparece. En una computadora compartida esa diferencia importa
   más que la comodidad de no volver a escribir la contraseña. */
var PASE = null;
try { PASE = sessionStorage.getItem('cessum_adm_pase'); } catch (e) {}

function mostrarAcceso(msg) {
  despertar();
  document.getElementById('cargando').style.display = 'none';
  document.getElementById('app').style.display = 'none';
  var a = document.getElementById('acceso');
  a.style.display = 'flex';
  if (msg) {
    var e = document.getElementById('acError');
    e.textContent = msg; e.style.display = 'block';
  }
  document.getElementById('acCorreo').focus();
}

/* (18-sep) EL PRIMER INTENTO SIEMPRE FALLABA Y EL SEGUNDO ENTRABA.
   No era el tamaño, ni el método, ni las cookies: Apps Script tarda en
   despertar cuando lleva un rato sin usarse y esa primera petición se queda
   sin respuesta. Quien entraba veía un error alarmante —«revisa que la
   implementación esté publicada»— escribía la contraseña otra vez y pasaba.
   Ahora se reintenta solo, hasta dos veces, sin pedirle nada a nadie. */
function entrar(intento) {
  intento = intento || 0;
  var b = document.getElementById('acEntrar');
  var err = document.getElementById('acError');
  err.style.display = 'none';
  b.disabled = true;
  b.textContent = intento ? 'Conectando…' : 'Comprobando…';
  api('login', {
    correo: document.getElementById('acCorreo').value.trim(),
    clave: document.getElementById('acClave').value
  }).then(function (r) {
    /* Un fallo del servidor de datos NO es una contraseña equivocada: se
       reintenta en silencio. Solo se muestra el error si el servidor
       responde de verdad que las credenciales no son correctas. */
    /* (22-sep) Solo se reintentaba si el mensaje decía «inesperado»; si el
       puente respondía «No se pudo consultar el servidor de datos», o la
       respuesta no era JSON, el error se mostraba al primer clic. Ahora se
       reintenta todo lo que NO sea un rechazo real: contraseña incorrecta,
       bloqueo por intentos o contraseña sin establecer. */
    var rechazoReal = r && !r.ok && /incorrect|intentos|Bloqueado|establecido/i
      .test(String(r.error || ''));
    var esFalloServidor = (!r || !r.ok) && !(r && r.expirado) && !rechazoReal;
    if (esFalloServidor && intento < 3) {
      b.textContent = 'Conectando con el servidor…';
      setTimeout(function () { entrar(intento + 1); }, 1500 * (intento + 1));
      return;
    }
    b.disabled = false; b.textContent = 'Entrar';
    if (r && r.ok) {
      PASE = r.pase;
      try { sessionStorage.setItem('cessum_adm_pase', PASE); } catch (e) {}
      document.getElementById('acceso').style.display = 'none';
      document.getElementById('acClave').value = '';
      cargar();
    } else {
      err.textContent = (r && r.error) || 'No se pudo entrar.';
      err.style.display = 'block';
    }
  }).catch(function (e) {
    b.disabled = false; b.textContent = 'Entrar';
    err.textContent = 'Error de conexión: ' + e;
    err.style.display = 'block';
  });
}

document.getElementById('acEntrar').onclick = entrar;
['acCorreo', 'acClave'].forEach(function (id) {
  document.getElementById(id).addEventListener('keydown', function (ev) {
    if (ev.key === 'Enter') entrar();
  });
});
document.getElementById('salir').onclick = function () {
  api('salir', { pase: PASE });
  try { sessionStorage.removeItem('cessum_adm_pase'); } catch (e) {}
  PASE = null;
  location.reload();
};


function esc(t) {
  return String(t == null ? '' : t).replace(/&/g, '&amp;')
    .replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
function normal(t) {
  return String(t || '').toLowerCase()
    .replace(/[áà]/g, 'a').replace(/[éè]/g, 'e').replace(/[íì]/g, 'i')
    .replace(/[óò]/g, 'o').replace(/[úù]/g, 'u').replace(/ñ/g, 'n');
}

/* (15-sep) EL AVISO SE QUEDABA PEGADO ARRIBA DE LA PÁGINA.
   cargar() corre al entrar y otra vez después del login. La primera terminaba
   bien y mostraba el panel; la segunda volvía a poner «Cargando prospectos…»
   y ahí se quedaba, encima de todo, aunque los datos ya estuvieran en
   pantalla. Ahora una carga en curso no se relanza, y el aviso se oculta
   pase lo que pase —también si la petición falla. */
var CARGANDO = false;
/* (22-sep) NINGUNA RECARGA SE PIERDE. Si se pedía una recarga mientras otra
   seguía en curso, se descartaba; y la que estaba en curso se había armado
   ANTES del último cambio, así que al terminar pintaba la etapa vieja. Ahora
   se anota y, al terminar la carga en curso, se hace una más. */
var RECARGAR = false;
function _finCarga_() {
  CARGANDO = false;
  FRESCO = false;
  if (RECARGAR) {
    RECARGAR = false;
    setTimeout(cargar, 300);
  }
}

/* (22-sep) EL CAMBIO SE VE AL INSTANTE. La tarjeta esperaba a que terminara
   la recarga completa —varios segundos, sin ninguna señal—, y parecía que el
   WhatsApp o la etapa no se habían guardado. En cuanto el servidor confirma,
   se actualiza la ficha en pantalla; la recarga sigue por detrás y trae lo
   que calcula el servidor (semáforo, días). */
function aplicarLocal(fila, cambios) {
  if (!DATOS || !DATOS.prospectos) return;
  for (var k = 0; k < DATOS.prospectos.length; k++) {
    if (String(DATOS.prospectos[k].fila) === String(fila)) {
      for (var c in cambios) DATOS.prospectos[k][c] = cambios[c];
      try { pintar(); } catch (e) {}
      return;
    }
  }
}
function hoyDMA() {
  var d = new Date();
  return ('0' + d.getDate()).slice(-2) + '/' + ('0' + (d.getMonth() + 1)).slice(-2) +
    '/' + d.getFullYear();
}
/* Lo que el servidor hace al registrar un WhatsApp, reflejado en pantalla. */
function localWhatsapp(p, r) {
  var et = String((p && p.etapa) || '').trim();
  aplicarLocal(p.fila, {
    waEnviado: (r && r.sello) || hoyDMA(),
    ultimo: hoyDMA(), dias: 0,
    etapa: (!et || et === 'Nuevo') ? 'Contactado' : et
  });
}

function cargar() {
  if (CARGANDO) { RECARGAR = true; return; }
  var c = document.getElementById('cargando');
  var yaVisible = document.getElementById('app').style.display === 'block';
  if (!yaVisible) {
    c.style.display = 'block';
    c.textContent = 'Cargando prospectos…';
  }
  if (!PASE) { mostrarAcceso(); return; }
  CARGANDO = true;
  /* (18-sep) LA LISTA SE PIDE POR PÁGINAS.
     Con 267 prospectos la respuesta pesaba 350 KB y Google devolvía un 404
     al intentar entregarla: el script funcionaba, pero el bulto no pasaba.
     Ahora se piden de 50 en 50 y se van juntando. El aviso muestra el avance
     para que no parezca colgado en una cartera grande. */
  cargarPaginas(0, null, 0);
}

/* (18-sep) CADA PÁGINA SE REINTENTA SOLA.
   La carga encadena seis peticiones y el fallo de Google es INTERMITENTE:
   basta que una se caiga para que se pierda toda la carga, aunque las otras
   cinco hayan llegado bien. Por eso funcionaba al probar una página suelta y
   fallaba el panel completo.
   Ahora cada página se reintenta hasta tres veces antes de darla por
   perdida, con una pausa entre intentos. */
/* (21-sep) UNA PÁGINA, CON SUS PROPIOS REINTENTOS. Devuelve una promesa que
   se resuelve con la respuesta —o con null si agotó los intentos—, para
   poder pedir varias a la vez sin que una lenta detenga a las demás. */
function pedirPagina(pagina, intento) {
  intento = intento || 0;
  return api('datos', { pase: PASE, pagina: pagina }).then(function (r) {
    if ((!r || (!r.ok && !r.expirado)) && intento < 3) {
      return new Promise(function (ok) {
        setTimeout(function () { ok(pedirPagina(pagina, intento + 1)); },
          1200 * (intento + 1));
      });
    }
    return r;
  }).catch(function () {
    if (intento < 3) {
      return new Promise(function (ok) {
        setTimeout(function () { ok(pedirPagina(pagina, intento + 1)); },
          1200 * (intento + 1));
      });
    }
    return null;
  });
}

function cargarPaginas(pagina, acumulado, intento, yaListo) {
  intento = intento || 0;
  var c = document.getElementById('cargando');
  var peticion = yaListo ? Promise.resolve(yaListo)
                         : api('datos', { pase: PASE, pagina: pagina });
  peticion.then(function (r) {
    /* Si esta página falló y quedan intentos, se repite solo esta. */
    if ((!r || (!r.ok && !r.expirado)) && intento < 3) {
      if (c && c.style.display === 'block') {
        c.textContent = 'Cargando prospectos… reintentando (' + (intento + 1) + ')';
      }
      /* La primera petición tras un rato de inactividad tarda en despertar
         al script: se espera más en el primer reintento. */
      setTimeout(function () {
        cargarPaginas(pagina, acumulado, intento + 1);
      }, 1500 * (intento + 1));
      return;
    }
    if (r && r.ok && r.prospectos) {
      if (!acumulado) {
        acumulado = r;
      } else {
        acumulado.prospectos = acumulado.prospectos.concat(r.prospectos);
      }
      /* (21-sep) EL RESTO DE LAS PÁGINAS, TODAS A LA VEZ.
         Antes iban en fila —cada una esperando a la anterior— y con varias
         páginas la carga se sentía eterna. Tras la primera ya se sabe el
         total, así que las demás se piden en paralelo: tardan lo que tarda
         la más lenta, no la suma de todas. */
      if (r.hayMas && pagina === 0) {
        var porPag = r.porPagina || 60;
        var totalPag = Math.ceil((r.total || 0) / porPag);
        var listas = 1;
        var pendientes = [];
        for (var pg = 1; pg < totalPag; pg++) {
          pendientes.push(pedirPagina(pg, 0).then(function (x) {
            listas++;
            if (c && c.style.display === 'block') {
              c.textContent = 'Cargando prospectos… ' + listas + ' de ' +
                totalPag + ' partes';
            }
            return x;
          }));
        }
        if (c && c.style.display === 'block') {
          c.textContent = 'Cargando prospectos… 1 de ' + totalPag + ' partes';
        }
        Promise.all(pendientes).then(function (res) {
          var fallaron = 0;
          for (var q = 0; q < res.length; q++) {
            var x = res[q];
            if (x && x.ok && x.prospectos) {
              acumulado.prospectos = acumulado.prospectos.concat(x.prospectos);
            } else {
              fallaron++;
            }
          }
          acumulado.hayMas = false;
          acumulado.partesFallidas = fallaron;
          cargarPaginas(0, null, 0, acumulado);
        });
        return;
      }
      r = acumulado;
    }
    _finCarga_();
    /* (15-sep) UN ERROR DEL SERVIDOR NO ES UNA SESIÓN CADUCADA.
       Aquí cualquier respuesta sin datos —un tiempo agotado del puente, una
       caída momentánea de Google— borraba el pase y devolvía al login. El
       usuario volvía a escribir la contraseña, entraba, y a los pocos
       segundos lo expulsaba otra vez: un bucle en el que parecía que la
       contraseña estaba mal cuando el problema era la carga de los datos.
       Ahora solo se cierra la sesión cuando el servidor dice expressamente
       que expiró; lo demás se informa sin echar a nadie. */
    if (r && r.expirado) {
      PASE = null;
      try { sessionStorage.removeItem('cessum_adm_pase'); } catch (e) {}
      mostrarAcceso('Tu sesión caducó. Vuelve a entrar.');
      return;
    }
    if (!r || r.ok === false || !r.prospectos) {
      _finCarga_();
      /* (16-sep) EL DETALLE SE MUESTRA, NO SE ESCONDE. El puente ya devuelve
         el código HTTP y el principio de lo que contestó Google, pero el
         panel solo pintaba el mensaje genérico —y sin ese detalle no hay
         forma de saber qué está fallando sin abrir las herramientas del
         navegador. */
      var msg = (r && r.error) ? r.error
        : 'No se pudieron traer los prospectos. Puede ser que el servidor de datos ' +
          'tardara demasiado; vuelve a intentarlo con el botón Actualizar.';
      if (r && (r.codigo || r.inicio)) {
        msg += '\n\nDetalle técnico — código ' + (r.codigo || '?') + ': ' +
          String(r.inicio || '(vacío)').substring(0, 300);
      }
      if (document.getElementById('app').style.display === 'block') {
        c.style.display = 'none';
        alert(msg);
        try { console.log('admisiones · detalle:', r); } catch (e) {}
      } else {
        c.style.display = 'block';
        c.innerHTML = msg + '<br><br><button onclick="cargar()" ' +
          'style="font:inherit;padding:9px 18px;border:1px solid #d9d0c2;border-radius:4px;' +
          'background:#fff;color:#7A1426;cursor:pointer">Reintentar</button>';
      }
      return;
    }
    DATOS = r;
    /* (25-sep, noche) EL CRUCE CON INSCRITOS, EN SEGUNDO PLANO. Antes lo hacía
       el servidor dentro de la primera página y la hacía esperar al Guardián.
       Ahora se lanza aquí, ya con la lista en pantalla, como mucho cada 30
       minutos; si marcó a alguien como inscrito, se recarga la lista. */
    try {
      var _ultCruce = Number(localStorage.getItem('cessum_adm_cruce') || 0);
      if (Date.now() - _ultCruce > 30 * 60000) {
        localStorage.setItem('cessum_adm_cruce', String(Date.now()));
        api('cruce_inscritos', { pase: PASE }).then(function (cz) {
          if (cz && cz.ok && Number(cz.marcados || 0) > 0) setTimeout(cargar, 500);
        });
      }
    } catch (eCz) {}
    /* Si alguna parte no llegó tras sus reintentos, se trabaja con lo que sí
       llegó y se avisa: es mejor ver doscientos prospectos que ninguno. */
    if (r.partesFallidas) {
      setTimeout(function () {
        var m = document.getElementById('avisoCarga');
        if (!m) {
          m = document.createElement('div');
          m.id = 'avisoCarga';
          m.style.cssText = 'margin:12px 26px;padding:10px 14px;border-left:3px solid #B18A4A;' +
            'background:#FBF6EC;color:#7A5A20;font-size:13px;border-radius:3px';
          document.getElementById('app').appendChild(m);
        }
        m.textContent = 'Faltó cargar parte de la lista (' + r.partesFallidas +
          ' de ' + Math.ceil((r.total || 0) / (r.porPagina || 60)) +
          ' partes). Pulsa Actualizar para completarla.';
      }, 50);
    }
    calcularDuplicados();
    cargarAltas();
    if (!GASTOS.length) {
      api('gasto_listar', { pase: PASE }).then(function (g) {
        if (g && g.ok) { GASTOS = g.gastos || []; metaMarcarPestana(); }
      });
    }
    c.style.display = 'none';
    document.getElementById('app').style.display = 'block';
    document.getElementById('hoy').textContent =
      new Date().toLocaleDateString('es-MX',
        { weekday: 'long', day: 'numeric', month: 'long' });
    llenarFiltros();
    pintar();
    /* (8-sep) SI HAY GENTE ESPERANDO, SE ABRE TRABAJANDO.
       Una lista de cincuenta y tres tarjetas paraliza: se mira, no se sabe por
       dónde empezar, y se cierra. El modo enfoque ya existía —y el comentario
       de más abajo lo dice bien: «esa decisión, repetida treinta veces, es la
       que hace que la lista no se trabaje»— pero estaba detrás de un botón que
       hay que decidir pulsar.
       Ahora, cuando hay alguien en riesgo, el panel abre en la persona que
       lleva más tiempo esperando. Sale con Escape y no vuelve a saltar en esa
       sesión: es un empujón al entrar, no una jaula. */
    if (!ENFOQUE.yaOfrecido) {
      ENFOQUE.yaOfrecido = true;
      var urgentes = DATOS.prospectos.filter(function (x) {
        return (x.estado === 'grave' || x.estado === 'riesgo') &&
               x.etapa !== 'Inscrito' && x.etapa !== 'No procede' && !x.baja;
      });
      if (urgentes.length) abrirEnfoque();
    }
  }).catch(function (e) {
    _finCarga_();
    /* Si el panel ya está en pantalla, el error no debe taparlo: se avisa
       abajo y se deja seguir trabajando con lo que ya se había cargado. */
    if (document.getElementById('app').style.display === 'block') {
      c.style.display = 'none';
      var m = document.getElementById('avisoCarga');
      if (!m) {
        m = document.createElement('div');
        m.id = 'avisoCarga';
        m.style.cssText = 'margin:12px 26px;padding:10px 14px;border-left:3px solid #98241F;' +
          'background:#FBECEC;color:#98241F;font-size:13px;border-radius:3px';
        document.getElementById('app').appendChild(m);
      }
      m.textContent = 'No se pudo actualizar la lista: ' + e +
        '. Lo que ves es lo último que se cargó.';
    } else {
      c.style.display = 'block';
      c.textContent = 'No se pudieron cargar los prospectos: ' + e;
    }
  });
}

function llenarFiltros() {
  var et = document.getElementById('fEtapa');
  if (et.options.length < 2) {
    (DATOS.etapas || []).forEach(function (x) {
      var o = document.createElement('option');
      o.value = x; o.textContent = x; et.appendChild(o);
    });
  }
  var pr = {}, as = {};
  DATOS.prospectos.forEach(function (p) {
    if (p.programa) pr[p.programa] = 1;
    if (p.asignado) as[p.asignado] = 1;
  });
  /* (17-sep) EL FILTRO SALÍA SOLO DE LOS PROSPECTOS YA REGISTRADOS.
     Un programa recién abierto —la Licenciatura en Pedagogía— no aparecía
     hasta que alguien pidiera informes de él, así que no había forma de
     filtrar por el programa que justo se está promoviendo. Ahora parte de la
     lista OFICIAL que manda el servidor y encima agrega lo que haya en la
     cartera. Y se rehace cada vez: antes se llenaba una sola vez y, si el
     filtro se pintaba antes de llegar los datos, quedaba vacío para siempre. */
  var fp = document.getElementById('fPrograma');
  var oficiales = (DATOS && DATOS.programasOficiales)
    ? DATOS.programasOficiales.slice() : [];
  oficiales.forEach(function (x) { pr[x] = 1; });
  var progsTodos = Object.keys(pr).sort();
  if (fp.options.length - 1 !== progsTodos.length) {
    var elegido = fp.value;
    while (fp.options.length > 1) fp.remove(1);
    progsTodos.forEach(function (x) {
      var o = document.createElement('option');
      o.value = x; o.textContent = x; fp.appendChild(o);
    });
    if (elegido) fp.value = elegido;
  }
  var fa = document.getElementById('fAsesor');
  if (fa.options.length < 2) {
    Object.keys(as).sort().forEach(function (x) {
      var o = document.createElement('option');
      o.value = x; o.textContent = x; fa.appendChild(o);
    });
  }
}

/* ═══════════════ QUÉ DECIRLE A ESTA PERSONA ═══════════════
   No es una plantilla fija: se arma con su etapa, sus días de silencio y lo
   que preguntó al registrarse. Quien abra el panel no debería tener que
   pensar qué escribir, solo revisar y ajustar. */
function sugerencia(p) {
  var n = p.nombre.split(' ')[0];
  var lic = p.programa.indexOf('Licenciatura') > -1;
  var preg = normal(p.pregunta);

  if (p.etapa === 'Nuevo') {
    var extra = '';
    if (preg.indexOf('beca') > -1) {
      extra = 'Sobre becas le adelanto la verdad: solo hay apoyos de ley para ' +
        'personas con discapacidad y estudiantes indígenas. Lo que sí ayuda es ' +
        'que el pago es mensual y sin enganche. ';
    } else if (preg.indexOf('horario') > -1 || preg.indexOf('sabado') > -1) {
      extra = lic
        ? 'Las clases son un solo día, el sábado de 8:00 a 16:00 en Navojoa, y ' +
          'el resto en línea a su ritmo. '
        : 'Hay una sesión en vivo por semana y el resto lo hace a su ritmo. ';
    } else if (preg.indexOf('costo') > -1 || preg.indexOf('precio') > -1 ||
               preg.indexOf('cuanto') > -1) {
      extra = lic
        ? 'Son $1,850 al mes y $450 de inscripción, sin enganche. '
        : 'La colegiatura es mensual, sin enganche, y la inscripción son $450. ';
    }
    return { t: 'Primer contacto · responde su duda antes de vender',
      m: 'Buen día, ' + n + '. Le escribo del CESSUM por su solicitud de informes' +
         (p.programa ? ' de ' + p.programa : '') + '. ' + extra +
         '¿Le resuelvo alguna duda concreta?' };
  }

  if (p.etapa === 'Contactado' && p.dias >= 3) {
    return { t: 'Ya se le escribió y no contestó · dale una salida fácil',
      m: 'Buen día, ' + n + '. Le escribo de nuevo del CESSUM. Sé que quizá anda ' +
         'ocupado(a): si sigue interesado(a) le aparto su lugar sin compromiso, y ' +
         'si ya no le interesa dígamelo con confianza y dejo de insistir.' };
  }

  if (p.etapa === 'Interesado') {
    return { t: 'Está interesado · quítale el siguiente obstáculo',
      m: 'Buen día, ' + n + '. Para apartar su lugar solo hacen falta tres ' +
         'documentos —acta de nacimiento, CURP y certificado— y el pago de ' +
         'inscripción. No hay examen ni entrevista. ¿Se los mando por aquí o ' +
         'prefiere que se los explique en una llamada de cinco minutos?' };
  }

  if (p.etapa === 'Documentos en proceso') {
    return { t: 'Le falta cerrar · pregunta por lo que falta, no por todo',
      m: 'Buen día, ' + n + '. ¿Cómo va con los documentos? Si le falta alguno, ' +
         'dígame cuál y vemos cómo resolverlo: casi siempre hay manera.' };
  }

  if (p.etapa === 'Inscrito') {
    return { t: 'Ya está dentro · no le vendas más',
      m: 'Buen día, ' + n + '. Ya quedó su lugar. Le comparto lo que sigue: sus ' +
         'accesos llegan a su correo antes de iniciar, y cualquier duda me la ' +
         'escribe directo por aquí.' };
  }
  return null;
}

function visibles() {
  var q = normal(document.getElementById('q').value.trim());
  var pal = q ? q.split(/\s+/) : [];
  var fe = document.getElementById('fEtapa').value;
  var fp = document.getElementById('fPrograma').value;
  var fa = document.getElementById('fAsesor').value;
  return DATOS.prospectos.filter(function (p) {
    if (FILTRO === 'riesgo' && p.estado !== 'riesgo' && p.estado !== 'grave') return false;
    if (FILTRO === 'nuevo' && p.etapa !== 'Nuevo') return false;
    if (FILTRO === 'inscrito' && p.etapa !== 'Inscrito') return false;
    if (FILTRO === 'dupe' && !hermanos(p).length) return false;
    if (fe && p.etapa !== fe) return false;
    if (fp && p.programa !== fp) return false;
    if (fa && p.asignado !== fa) return false;
    if (!pal.length) return true;
    var h = normal([p.nombre, p.correo, p.telefono, p.programa, p.notas,
                    p.campana].join(' '));
    for (var i = 0; i < pal.length; i++) if (h.indexOf(pal[i]) < 0) return false;
    return true;
  });
}

/* ═══════════ DUPLICADOS ═══════════
   La misma persona pide informes dos veces —por dos programas, o porque
   volvió a llenar el formulario— y aparece como dos prospectos. Eso hace tres
   daños: infla la cola, reparte la misma persona entre dos asesores, y le
   llegan dos mensajes distintos del mismo lugar.

   La columna «Repetido» de la hoja existía, pero la etiqueta se pintaba tan
   discreta como cualquier otra y no decía CON QUIÉN. Aquí se agrupan por los
   últimos diez dígitos del teléfono —la misma normalización del backend, así
   que «+52 642…» y «642…» son la misma persona— y cada ficha sabe cuántas
   hermanas tiene y dónde están. */
var DUPES = {};

/* (22-sep) Inscripciones y estado de alta, del Guardián. Se traen una vez
   al cargar; si fallan, las tarjetas simplemente no lo muestran. */
var ALTAS = null;
function cargarAltas() {
  if (ALTAS) { return; }
  cargarFeed().then(function (r) {
    if (!r || !r.ok) return;
    ALTAS = r.inscripciones || [];
    CAC_INSC = ALTAS; PRI_INSC = ALTAS;
    try { pintar(); } catch (e) {}
  }).catch(function () {});
}
function altaDe(p) {
  if (!ALTAS || !ALTAS.length) return null;
  var t = telClave(p.telefono), c = String(p.correo || '').trim().toLowerCase();
  for (var i = 0; i < ALTAS.length; i++) {
    var x = ALTAS[i];
    if ((t && x.t === t) || (c && x.c === c)) return x;
  }
  return null;
}

function telClave(t) {
  var d = String(t == null ? '' : t).replace(/\D/g, '');
  if (d.length === 13 && d.indexOf('521') === 0) d = d.slice(3);
  if (d.length === 12 && d.indexOf('52') === 0) d = d.slice(2);
  return d.length < 10 ? '' : d.slice(-10);
}

function calcularDuplicados() {
  DUPES = {};
  var por = {};
  (DATOS.prospectos || []).forEach(function (p) {
    var k = telClave(p.telefono);
    if (!k) return;
    (por[k] = por[k] || []).push(p);
  });
  Object.keys(por).forEach(function (k) {
    if (por[k].length > 1) DUPES[k] = por[k];
  });
}

/* Los hermanos de una ficha, sin contarla a ella misma. */
/* (22-sep) UNA FICHA YA ARCHIVADA NO SIGUE SIENDO UN DUPLICADO VIVO.
   La fusión escribía bien en la hoja, pero aquí se contaban TODAS las fichas
   del mismo teléfono, incluidas las que se acababan de archivar: la que
   sobrevive seguía marcada en rojo como «MISMA PERSONA que otra ficha» y
   volvía a ofrecer el botón de fusionar, así que parecía que no había
   funcionado. Ahora solo cuentan las que siguen en el embudo. */
function hermanos(p) {
  var k = telClave(p.telefono);
  if (!k || !DUPES[k]) return [];
  return DUPES[k].filter(function (o) {
    return o.fila !== p.fila && String(o.etapa || '').trim() !== 'No procede' && !o.baja;
  });
}

/* Cuántas PERSONAS distintas hay, no cuántos renglones. Es la cifra honesta:
   53 renglones pueden ser 47 personas, y sobre 53 se trabaja de más. */
function personasUnicas() {
  var vistos = {}, n = 0;
  (DATOS.prospectos || []).forEach(function (p) {
    var k = telClave(p.telefono);
    if (!k) { n++; return; }
    if (!vistos[k]) { vistos[k] = 1; n++; }
  });
  return n;
}

function pintarCifras() {
  var t = DATOS.prospectos;
  var r = t.filter(function (p) { return p.estado === 'riesgo' || p.estado === 'grave'; }).length;
  var nv = t.filter(function (p) { return p.etapa === 'Nuevo'; }).length;
  var ins = t.filter(function (p) { return p.etapa === 'Inscrito'; }).length;
  var unicas = personasUnicas();
  var conv = unicas ? Math.round(ins / unicas * 100) : 0;
  var dup = 0;
  Object.keys(DUPES).forEach(function (k) { dup += DUPES[k].length; });
  var c = [{ k: 'riesgo', n: r, t: 'Te están esperando', a: 1 },
           { k: 'nuevo', n: nv, t: 'Sin contactar' },
           { k: 'inscrito', n: ins, t: 'Inscritos' },
           { k: '', n: t.length, t: 'Todos' }];
  document.getElementById('cifras').innerHTML = c.map(function (x) {
    return '<div class="cifra' + (FILTRO === x.k ? ' on' : '') +
      (x.a ? ' alerta' : '') + '" data-k="' + x.k + '"><b>' + x.n +
      '</b><span>' + x.t + '</span></div>';
  }).join('') +
    /* La conversión sobre renglones miente cuando hay duplicados: se calcula
       sobre personas. Y si hay repetidos, se dice y se puede filtrar: es lo
       primero que hay que limpiar, porque todo lo demás se mide sobre eso. */
    '<div class="cifra' + (FILTRO === 'dupe' ? ' on' : '') + '" data-k="dupe"><b>' +
    dup + '</b><span>repetidos</span></div>' +
    '<div class="cifra" style="cursor:default"><b>' + conv +
    '%</b><span>conversión</span></div>';
  Array.prototype.forEach.call(document.querySelectorAll('.cifra[data-k]'), function (el) {
    el.onclick = function () { FILTRO = el.getAttribute('data-k'); ver('cola'); };
  });
}

function pintar() {
  pintarCifras();
  if (VISTA === 'tablero') { pintarTablero(); return; }
  if (VISTA === 'repetidos') { pintarRepetidos(); return; }   // (23-sep) al terminar de unificar, la vista se actualiza
  if (VISTA === 'ritmo' || VISTA === 'correos') return;
  var v = visibles();
  document.getElementById('cuenta').textContent =
    v.length + (v.length === 1 ? ' prospecto' : ' prospectos');
  var l = document.getElementById('lista');
  // Un estado vacío puede ser una buena noticia o un problema, y no es lo
  // mismo. Se distingue: sin nadie en riesgo se felicita; sin resultados de
  // búsqueda se dice cómo volver atrás.
  if (!v.length) {
    var msg;
    if (FILTRO === 'riesgo') {
      msg = '<p class="vacio"><b style="font-family:var(--display);font-size:19px;">' +
        'Nadie está esperando.</b><br>Todos los prospectos están dentro de su ' +
        'plazo. Buen momento para trabajar a quienes llevan más tiempo en la ' +
        'misma etapa.</p>';
    } else if (FILTRO === 'nuevo') {
      msg = '<p class="vacio"><b style="font-family:var(--display);font-size:19px;">' +
        'No hay nadie sin contactar.</b><br>Todo el que pidió informes ya ' +
        'recibió al menos un mensaje.</p>';
    } else if (!DATOS.prospectos.length) {
      msg = '<p class="vacio"><b style="font-family:var(--display);font-size:19px;">' +
        'Todavía no hay prospectos.</b><br>En cuanto alguien llene el ' +
        'formulario de cessum.mx aparecerá aquí, y su reloj empieza a correr ' +
        'desde ese momento.</p>';
    } else {
      msg = '<p class="vacio">Nadie coincide con esos filtros. ' +
        'Prueba con «Todos» arriba.</p>';
    }
    l.innerHTML = msg;
    return;
  }
  l.innerHTML = v.map(tarjeta).join('');
  conectar();
}

function tarjeta(p) {
  var tg = [];
  if (p.estado === 'grave') tg.push(['rojo', p.dias + ' días sin moverse']);
  else if (p.estado === 'riesgo') tg.push(['ambar', p.dias + ' días · le toca hoy']);
  else if (p.dias !== null) tg.push(['', 'hace ' + p.dias + ' d']);
  tg.push(['', p.etapa]);
  if (p.paso) tg.push(['oro', 'correo ' + p.paso + ' de 5' +
    (p.fechaCorreo ? ' · ' + p.fechaCorreo : '')]);
  if (p.waEnviado) tg.push(['verde', 'WhatsApp enviado']);
  if (p.respondio) tg.push(['verde', 'respondió ' + p.respondio]);
  if (p.conversacion) tg.push(['verde', 'con conversación']);
  if (p.avisos === 'no') tg.push(['', 'no quiere avisos']);
  if (p.baja) tg.push(['', 'dado de baja']);
  /* (8-sep) El duplicado deja de ser una etiqueta gris entre otras seis.
     Antes decía «repetido» y ya: no decía con quién, ni en qué programa, ni
     en qué fila, así que nadie iba a buscarlo y la ficha se trabajaba dos
     veces. Ahora dice cuántos son y dónde están. */
  /* (9-sep) La ficha sin nombre se marca para que no se quede así: se
     registró en caliente con solo el teléfono, y alguien tiene que
     completarla en cuanto la persona diga cómo se llama. */
  if (p.sinNombre) tg.push(['', 'falta el nombre']);
  /* Quien compara varios programas necesita un trato distinto: no se le
     empuja a uno, se le ayuda a distinguirlos. Se marca para que quien
     atiende lo tenga presente antes de escribir. */
  if (p.otrosProgramas) tg.push(['oro', 'también: ' + p.otrosProgramas]);
  var herm = hermanos(p);
  if (herm.length) {
    tg.push(['rojo', herm.length === 1
      ? 'MISMA PERSONA que otra ficha'
      : 'MISMA PERSONA que otras ' + herm.length + ' fichas']);
  } else if (p.repetido) {
    tg.push(['', 'repetido']);
  }
  if (p.campana) tg.push(['', p.campana]);
  /* (22-sep) LO QUE PASÓ DESPUÉS DE INSCRIBIRSE. El Guardián dice, por
     teléfono o correo, si esta persona ya llenó la inscripción y en qué
     paso va su alta: completa, detenida (y en qué) o en revisión. Así
     admisiones deja de preguntarle a Sistemas y de prometer lo que no
     está listo. */
  var alta = altaDe(p);
  if (alta) {
    if (alta.s === 'completa') tg.push(['verde', 'alumno ' + (alta.mat || '') + ' · alta completa']);
    else if (alta.s === 'detenida') tg.push(['rojo', 'alta detenida: ' + (alta.falta || []).join(', ')]);
    else if (alta.s === 'en revisión') tg.push(['ambar', 'inscripción en revisión']);
    else if (alta.s === 'rechazada') tg.push(['', 'inscripción rechazada']);
    else tg.push(['oro', 'inscripción recibida']);
  }
  var s = sugerencia(p);

  return '<div class="p ' + p.estado + '" data-f="' + p.fila + '">' +
    '<h3 style="cursor:pointer" data-a="ficha" title="Ver su historia completa">' +
      esc(p.nombre) + '</h3>' +
    '<p class="meta"><b>' + esc(p.programa || 'Sin programa') + '</b>' +
      (p.modalidad ? ' · ' + esc(p.modalidad) : '') +
      (p.telefono ? ' · ' + esc(p.telefono) : ' · sin teléfono') +
      (p.alta ? ' · pidió informes el ' + esc(p.alta) : '') + '</p>' +
    '<div class="tags">' + tg.map(function (x) {
      return '<span class="tag ' + x[0] + '">' + esc(x[1]) + '</span>';
    }).join('') + '</div>' +
    (herm.length
      ? '<p class="preg" style="background:#FBEAEA;border-left-color:var(--rojo);">' +
        '<b style="display:block;font-size:9.5px;letter-spacing:.11em;' +
        'text-transform:uppercase;color:var(--rojo-osc);margin-bottom:3px;">' +
        'Ojo · esta persona está repetida</b>' +
        'El mismo teléfono aparece en: ' +
        herm.map(function (o) {
          return esc((o.programa || 'sin programa') + ' · ' + (o.etapa || '') +
                     ' · fila ' + o.fila);
        }).join(' — ') +
        '. Decide cuál ficha conservar antes de escribirle: si dos asesores le ' +
        'contestan por separado, recibe dos mensajes distintos del mismo lugar.</p>'
      : '') +
    (p.pregunta ? '<p class="preg">' + esc(p.pregunta) + '</p>' : '') +
    (s ? '<div class="sug"><b>' + esc(s.t) + '</b>' + esc(s.m) + '</div>' : '') +
    (p.proxima
      ? '<p class="preg" style="background:#FFF8EC;border-left-color:var(--ambar);">' +
        '<b style="display:block;font-size:9.5px;letter-spacing:.11em;' +
        'text-transform:uppercase;color:#7E5A0C;margin-bottom:3px;">' +
        'Lo que sigue</b>' + esc(p.proxima) + '</p>'
      : '') +
    (p.convPendiente ? '<p class="preg" style="background:#FFF8EC;border-left-color:var(--ambar);"><b style="display:block;font-size:9.5px;letter-spacing:.11em;text-transform:uppercase;color:#7E5A0C;margin-bottom:3px;">Le escribieron</b>Falta actualizar la conversación: pegue lo que hablaron para que la ficha y el próximo mensaje lo tengan en cuenta.</p>' : '') +
    (p.notas ? '<p class="hist">' + esc(p.notas) + '</p>' : '') +
    '<div class="acc">' +
      (p.telefono ? '<button class="wa" data-a="wa">WhatsApp</button>'
                  : '<button disabled>Sin teléfono</button>') +
      (herm.length ? '<button data-a="fusion" style="border-color:var(--rojo);' +
        'color:var(--rojo)">Conservar esta y archivar las otras</button>' : '') +
      (s ? '<button data-a="copiar">Copiar mensaje</button>' : '') +
      (p.telefono ? '<button data-a="ia" title="Redacta una respuesta con IA a partir de lo que esta persona preguntó y la información oficial">Redactar con IA</button>' : '') +
      '<button data-a="corregir" title="Cambiar la fecha en que pidió informes y los programas que le interesan">Corregir datos</button>' +
      '<button data-a="borrar" style="border-color:#C9C2B6;color:#8A8378" title="Quitar esta ficha para siempre. Solo para lo que NO es un prospecto: pruebas, vendedores, números equivocados">Borrar</button>' +
      '<button data-a="resp">Contestó</button>' +
      (p.telefono ? '<button data-a="wact"' + (p.convPendiente ? ' class="wa-pend"' : '') + ' title="Pega la conversación de WhatsApp; la IA la lee y propone qué actualizar">Actualizar conversación</button>' : '') +
      '<button data-a="chat">Conversación</button>' +
      '<button data-a="nota">Nota</button>' +
      '<button data-a="prox">Lo que sigue</button>' +
      '<button data-a="fecha" title="Corregir la fecha en que esta persona pidió informes">Fecha</button>' +
      '<select class="et" data-a="etapa">' + (DATOS.etapas || []).map(function (e) {
        return '<option' + (e === p.etapa ? ' selected' : '') + '>' + esc(e) + '</option>';
      }).join('') + '</select>' +
    '</div></div>';
}

function prospecto(f) {
  for (var i = 0; i < DATOS.prospectos.length; i++) {
    if (String(DATOS.prospectos[i].fila) === String(f)) return DATOS.prospectos[i];
  }
  return null;
}

function copiar(txt, aviso) {
  var t = document.createElement('textarea');
  t.value = txt;
  document.body.appendChild(t);
  t.select();
  try { document.execCommand('copy'); alert(aviso || 'Copiado.'); }
  catch (e) { alert('Selecciónalo y cópialo con Ctrl+C.'); }
  document.body.removeChild(t);
}

function conectar() {
  Array.prototype.forEach.call(document.querySelectorAll('.p'), function (c) {
    var f = c.getAttribute('data-f'), p = prospecto(f);

    var w = c.querySelector('[data-a="wa"]');
    /* (28-sep) El botón abre el diálogo de WhatsApp con IA: redacta con la ficha y la conversación, se revisa y solo entonces se abre WhatsApp. */
    if (w) w.onclick = function () { waAbrirIA(p); };

    /* ── FUSIÓN DE DUPLICADOS ──────────────────────────────────────────
       Ver el duplicado no basta: mientras las dos fichas sigan vivas, la cola
       está inflada, el reparto manda la misma persona a dos asesores y ella
       puede recibir dos mensajes distintos del mismo lugar.

       Se conserva la ficha DESDE LA QUE SE PULSA —el asesor decide cuál, que
       casi siempre es la de la etapa más avanzada— y las demás se archivan
       como 'No procede'. NO SE BORRA NADA: la hoja conserva sus renglones, y
       cada uno queda con una nota que dice de cuál ficha es duplicado. Lo que
       esas fichas traían —programa, etapa y lo que preguntó— se copia como
       nota en la que sobrevive, para que no se pierda el interés que expresó
       en el otro programa. */
    var fu = c.querySelector('[data-a="fusion"]');
    if (fu) fu.onclick = function () {
      var detalle = herm.map(function (o) {
        return (o.programa || 'sin programa') + ' · ' + (o.etapa || '') +
               (o.pregunta ? ' · preguntó: ' + o.pregunta : '');
      }).join(' | ');
      dialogo('Fusionar · ' + p.nombre,
        'Se conserva ESTA ficha (' + (p.programa || 'sin programa') + ' · ' +
        p.etapa + ') y ' + (herm.length === 1 ? 'la otra se archiva' :
        'las otras ' + herm.length + ' se archivan') + ' como «No procede». ' +
        'No se borra nada de la hoja. Puedes agregar una nota.',
        'Fusionadas por teléfono repetido. También pidió informes de: ' + detalle,
        [['Fusionar', function (t) {
          /* (22-sep) SE ARCHIVAN UNA POR UNA Y SE ESPERA A CADA UNA.
             Antes se mandaban todas a la vez sin esperar respuesta y la
             recarga salía en paralelo: podía terminar ANTES de que se
             escribieran, y la lista volvía a pintar las duplicadas vivas.
             Además, si alguna fallaba, nadie se enteraba. */
          var cuenta = document.getElementById('cuenta');
          var fallaron = 0, hechas = 0;
          function siguiente(n) {
            if (n >= herm.length) {
              if (fallaron) {
                alert('Se archivaron ' + hechas + ' de ' + herm.length +
                  ' ficha(s). Las demás no se pudieron: vuelve a intentarlo.');
              }
              // La que sobrevive se guarda al final: su guardado es el que
              // recarga la lista, ya con todas las demás archivadas.
              guardar({ fila: Number(p.fila), tocar: true,
                nota: t || ('Fusionadas ' + hechas + ' ficha(s) duplicada(s).') });
              return;
            }
            var o = herm[n];
            if (cuenta) {
              cuenta.textContent = 'Archivando duplicada ' + (n + 1) + ' de ' + herm.length + '…';
            }
            var c = { fila: Number(o.fila), etapa: 'No procede',
              nota: 'Duplicado de la ficha en fila ' + p.fila + ' (' +
                    (p.programa || 'sin programa') + '), que es la que se trabaja.' };
            apiEscribir('guardar', { pase: PASE, cambios: JSON.stringify(c) }).then(function (r) {
              if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
              if (r && r.ok) { hechas++; aplicarLocal(c.fila, cambiosLocales(c)); }
              else { fallaron++; }
              siguiente(n + 1);
            });
          }
          siguiente(0);
        }]]);
    };

    /* ── REDACTAR CON IA ──────────────────────────────────────────────
       La plantilla por etapa sirve cuando la persona no dijo nada. Cuando
       preguntó algo con sus palabras, hace falta contestarle ESO. El
       Guardián de admisiones redacta un borrador con lo que se sabe de la
       ficha y la información oficial de la convocatoria —nunca inventa
       precios, fechas ni becas— y aquí se muestra para LEERLO y ajustarlo.
       No se manda nada solo: quien atiende decide. */
    var ia = c.querySelector('[data-a="ia"]');
    if (ia) ia.onclick = function () { waAbrirIA(p, true); };   // (28-sep) el mismo diálogo, con el cursor en «¿algo en particular?»

    var cp = c.querySelector('[data-a="copiar"]');
    if (cp) cp.onclick = function () {
      var s = sugerencia(p);
      if (s) copiar(s.m, 'Mensaje copiado. Revísalo antes de mandarlo.');
    };

    var r = c.querySelector('[data-a="resp"]');
    if (r) r.onclick = function () {
      dialogo('Contestó · ' + p.nombre,
        'Se registra la respuesta y se reinicia su reloj de seguimiento.', '',
        [['Guardar', function (t) {
          guardar({ fila: Number(f), respondio: true, tocar: true,
            nota: t || 'Contestó.' });
        }]]);
    };

    var wact = c.querySelector('[data-a="wact"]');
    if (wact) wact.onclick = function () { waActualizar(f); };

    var ch = c.querySelector('[data-a="chat"]');
    if (ch) ch.onclick = function () {
      dialogo('Conversación · ' + p.nombre,
        'Pega aquí el hilo de WhatsApp tal cual. Se guarda con el prospecto, y ' +
        'el otro botón te arma el paquete para pedirle consejo a Claude.',
        p.conversacion || '',
        [['Copiar para Claude', function (t) {
            copiar(paquete(p, t), 'Copiado. Pégalo en la conversación con Claude.');
          }, true],
         ['Guardar', function (t) { guardar({ fila: Number(f), conversacion: t }); }]]);
    };

    /* ── BORRAR ─────────────────────────────────────────────────────────
       Para lo que no es un prospecto. Un prospecto real que no se inscribió
       va a «No procede», no aquí: su historia sirve para medir. Se pide
       motivo y confirmación explícita, porque no hay vuelta atrás. */
    var bo = c.querySelector('[data-a="borrar"]');
    if (bo) bo.onclick = function () {
      dialogo('Borrar · ' + (p.nombre || p.telefono),
        'Esto quita la ficha para siempre. Úsalo solo si NO es un prospecto (una prueba, un vendedor, un número equivocado). Si es una persona real que no se inscribió, cámbiala a «No procede» en vez de borrarla. Escribe el motivo:',
        '',
        [['Borrar definitivamente', function (motivo) {
          if (!motivo) { alert('Escribe el motivo: queda en la bitácora.'); return; }
          if (!confirm('¿Borrar la ficha de ' + (p.nombre || p.telefono) + '? No se puede deshacer.')) return;
          document.getElementById('cuenta').textContent = 'Borrando…';
          api('borrar', { pase: PASE, fila: p.fila, motivo: motivo })
            .then(function (r) {
              if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
              if (!r || !r.ok) { alert((r && r.error) || 'No se pudo borrar.'); cargar(); return; }
              cargar();
            })
            .catch(function () { alert('No hubo respuesta.'); cargar(); });
        }]]);
    };

    /* ── CORREGIR DATOS ─────────────────────────────────────────────────
       Dos cosas solo se podían poner al dar de alta: la fecha real en que
       pidió informes y los programas que le interesan. Quien capturó
       conversaciones viejas quedó con todas fechadas el día de la captura
       —su semáforo miente— y a quien pregunta por un segundo programa
       después de registrado no había dónde anotárselo. */
    var co = c.querySelector('[data-a="corregir"]');
    if (co) co.onclick = function () {
      var d = document.getElementById('dlg');
      var vieja = document.getElementById('fichaCuerpo');
      if (vieja) vieja.remove();
      document.getElementById('dlgTit').textContent = 'Corregir · ' + p.nombre;
      document.getElementById('dlgSub').textContent =
        'La fecha es la del día en que la persona pidió informes, no la de captura: de ahí sale el semáforo de días.';
      document.getElementById('dlgTxt').style.display = 'none';

      var lista = (DATOS && DATOS.programasOficiales) ? DATOS.programasOficiales.slice() : [];
      if (p.programa && lista.indexOf(p.programa) < 0) lista.push(p.programa);
      var otrosAct = String(p.otrosProgramas || '').split('|').map(function (x) { return x.trim(); });
      var fechaAct = '';
      if (p.alta) { var pa = p.alta.split('/'); if (pa.length === 3) fechaAct = pa[2] + '-' + pa[1] + '-' + pa[0]; }

      var cuerpo = document.createElement('div');
      cuerpo.id = 'fichaCuerpo';
      cuerpo.innerHTML =
        '<div style="margin-bottom:14px"><label style="font-size:12px;color:var(--gris-txt)">¿Cuándo pidió informes?</label>' +
        '<input type="date" id="cFecha" value="' + fechaAct + '" style="width:100%"></div>' +
        '<div style="margin-bottom:14px"><label style="font-size:12px;color:var(--gris-txt)">Programa principal</label>' +
        '<select id="cProg" style="width:100%"><option value="">—</option>' +
        '<option value="Preguntó en general"' + (p.programa === 'Preguntó en general' ? ' selected' : '') + '>Preguntó en general (no eligió programa)</option>' +
        lista.map(function (x) {
          return '<option value="' + x.replace(/"/g, '&quot;') + '"' + (x === p.programa ? ' selected' : '') + '>' + x + '</option>';
        }).join('') + '</select></div>' +
        '<div><label style="font-size:12px;color:var(--gris-txt)">También le interesan</label>' +
        '<div style="display:flex;flex-wrap:wrap;gap:6px 14px;margin-top:6px">' +
        lista.map(function (x) {
          return '<label style="font-size:12.5px;display:flex;align-items:center;gap:5px;cursor:pointer">' +
            '<input type="checkbox" class="cOtroChk" value="' + x.replace(/"/g, '&quot;') + '"' +
            (otrosAct.indexOf(x) >= 0 ? ' checked' : '') + '> ' + x + '</label>';
        }).join('') + '</div></div>';
      document.getElementById('dlgTxt').parentNode.insertBefore(cuerpo, document.getElementById('dlgFin'));

      var fin = document.getElementById('dlgFin');
      fin.innerHTML = '<button data-cerrar="1">Cancelar</button><button class="pri" data-ok="1">Guardar</button>';
      var cerrar = function () {
        d.close();
        document.getElementById('dlgTxt').style.display = '';
        var v2 = document.getElementById('fichaCuerpo'); if (v2) v2.remove();
      };
      fin.querySelector('[data-cerrar]').onclick = cerrar;
      fin.querySelector('[data-ok]').onclick = function () {
        var pr = document.getElementById('cProg').value;
        var otros = Array.prototype.slice.call(document.querySelectorAll('.cOtroChk:checked'))
          .map(function (x) { return x.value; })
          .filter(function (x) { return x && x !== pr; });
        cerrar();
        guardar({ fila: Number(p.fila),
          fecha: document.getElementById('cFecha').value,
          programa: pr,
          otrosProgramas: otros.join(' | ') });
      };
      d.showModal();
    };

    var nt = c.querySelector('[data-a="nota"]');
    if (nt) nt.onclick = function () {
      dialogo('Nota · ' + p.nombre,
        'Se agrega arriba del historial, con fecha y autor.', '',
        [['Guardar', function (t) { if (t) guardar({ fila: Number(f), nota: t }); }]]);
    };

    var fi = c.querySelector('[data-a="ficha"]');
    if (fi) fi.onclick = function () { verFicha(f, p.nombre); };

    /* (9-sep) CORREGIR LA FECHA. Las fichas capturadas antes de que existiera
       el campo quedaron todas con la fecha del día, y de esa fecha sale el
       «días sin moverse»: quien preguntó hace tres semanas aparecía como
       recién llegado y el modo enfoque lo mandaba al final de la cola. */
    var fe = c.querySelector('[data-a="fecha"]');
    if (fe) fe.onclick = function () {
      var actual = '';
      var m = String(p.alta || '').match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
      if (m) actual = m[3] + '-' + m[2] + '-' + m[1];
      dialogo('¿Cuándo pidió informes? · ' + p.nombre,
        'Escríbela como aaaa-mm-dd (por ejemplo 2026-08-21) o como dd/mm/aaaa. ' +
        'De esta fecha salen los días sin moverse y el orden de la cola: si la ' +
        'ficha se capturó con la fecha de hoy pero la persona escribió hace ' +
        'semanas, corrígela aquí.',
        actual,
        [['Guardar', function (t) {
          if (!t.trim()) { alert('Escribe la fecha.'); return; }
          guardar({ fila: Number(f), fecha: t.trim() });
        }]]);
    };

    var px = c.querySelector('[data-a="prox"]');
    if (px) px.onclick = function () {
      dialogo('Lo que sigue · ' + p.nombre,
        'Escribe qué hay que hacer y cuándo. Aparece en su tarjeta hasta que ' +
        'lo cambies. Ejemplo: «quedó de avisarme el jueves 22; si no escribe, ' +
        'llamarle el viernes».',
        p.proxima || '',
        [['Guardar', function (t) { guardar({ fila: Number(f), proxima: t }); }]]);
    };

    var se = c.querySelector('[data-a="etapa"]');
    if (se) se.onchange = function () {
      guardar({ fila: Number(f), etapa: se.value, tocar: true });
    };
  });
}

/* El paquete para pedir consejo. El teléfono y el correo NO van: para
   aconsejar qué responder no hacen falta, y son datos de una persona real. */
function paquete(p, chat) {
  return 'Ayúdame con este prospecto de CESSUM.\n\n' +
    'Programa: ' + (p.programa || '—') + '\n' +
    'Modalidad: ' + (p.modalidad || '—') + '\n' +
    'Etapa: ' + p.etapa + '\n' +
    'Días desde el último movimiento: ' + (p.dias === null ? '—' : p.dias) + '\n' +
    'Correos de la secuencia que ya recibió: ' + (p.paso || 0) + ' de 5\n' +
    (p.pregunta ? 'Lo que preguntó al registrarse: ' + p.pregunta + '\n' : '') +
    (p.notas ? '\nNotas del seguimiento:\n' + p.notas + '\n' : '') +
    (chat ? '\nConversación de WhatsApp:\n' + chat + '\n' : '') +
    '\n¿Qué le respondo, y qué NO le debería decir?';
}

/* La historia de una persona, en orden. La tarjeta muestra el ESTADO; esto
   muestra el CAMINO. Antes de escribirle a alguien que lleva tres semanas
   dando vueltas hay que ver qué se le dijo y qué contestó — si no, cada
   asesor empieza de cero y la persona lo nota. */
function verFicha(fila, nombre) {
  var d = document.getElementById('dlg');
  // Abrir dos fichas seguidas dejaría la anterior debajo. Se limpia siempre.
  var vieja = document.getElementById('fichaCuerpo');
  if (vieja) vieja.remove();
  document.getElementById('dlgTit').textContent = nombre;
  document.getElementById('dlgSub').textContent = 'Cargando su historia…';
  document.getElementById('dlgTxt').style.display = 'none';
  document.getElementById('dlgFin').innerHTML =
    '<button data-cerrar="1">Cerrar</button>';
  document.getElementById('dlgFin').querySelector('[data-cerrar]').onclick =
    function () { d.close(); document.getElementById('dlgTxt').style.display = ''; };
  d.showModal();

  api('ficha', { pase: PASE, fila: fila }).then(function (r) {
    if (!r || !r.ok) {
      document.getElementById('dlgSub').textContent =
        'No se pudo cargar: ' + ((r && r.error) || 'error');
      return;
    }
    var icono = { alta: '📩', correo: '✉️', error: '⚠️', accion: '✱' };
    var color = { alta: 'var(--oro)', correo: 'var(--verde)',
      error: 'var(--rojo)', accion: 'var(--gris-txt)' };

    var tl = (r.linea || []).map(function (e) {
      return '<div style="display:flex;gap:11px;padding:9px 0;' +
        'border-bottom:1px solid var(--gris);">' +
        '<div style="font-size:15px;line-height:1.3;">' +
        (icono[e.tipo] || '·') + '</div>' +
        '<div style="flex:1;min-width:0;">' +
        '<div style="font-size:13px;font-weight:600;color:' +
        (color[e.tipo] || 'inherit') + ';">' + esc(e.que) + '</div>' +
        (e.detalle ? '<div style="font-size:12px;color:var(--gris-txt);' +
          'line-height:1.5;">' + esc(e.detalle) + '</div>' : '') +
        '</div>' +
        '<div style="font-size:11px;color:var(--gris-txt);white-space:nowrap;">' +
        esc(e.fecha) + '</div></div>';
    }).join('');

    var dup = (r.duplicadosPorCorreo || []).length
      ? '<div class="hallazgo"><b>Este correo aparece en ' +
        r.duplicadosPorCorreo.length + ' registro(s) más</b><span class="q">' +
        r.duplicadosPorCorreo.map(function (x) {
          return esc(x.nombre) + ' · ' + esc(x.programa || 'sin programa') +
            ' · ' + esc(x.etapa);
        }).join('<br>') +
        '<br>Es la misma persona pidiendo informes dos veces. Trabaja uno solo ' +
        'y marca el otro como No procede, o dos asesores le van a escribir.' +
        '</span></div>'
      : '';

    var g = r.ficha;
    var fichaProg = g
      ? '<div style="background:var(--papel);border-radius:10px;padding:12px 14px;' +
        'margin:0 0 14px;font-size:12.5px;line-height:1.7;">' +
        '<b style="color:var(--oro-txt);font-size:10px;letter-spacing:.1em;' +
        'text-transform:uppercase;display:block;margin-bottom:5px;">' +
        esc(r.programa) + '</b>' +
        esc(g.modalidad) + '<br>' + esc(g.duracion) + ' · ' + esc(g.asignaturas) +
        '<br><b>' + esc(g.costo) + '</b> · inscripción $450<br>' +
        'Inicia el ' + esc(g.inicio) + ' · RVOE ' + esc(g.rvoe) +
        '</div>'
      : '';

    document.getElementById('dlgSub').textContent =
      (r.linea || []).length + ' momento(s) registrados · lo más reciente primero';
    document.getElementById('dlgTxt').insertAdjacentHTML('beforebegin',
      '<div id="fichaCuerpo">' + dup + fichaProg +
      (r.conversacion
        ? '<div class="preg" style="white-space:pre-wrap;max-height:150px;' +
          'overflow:auto;"><b style="display:block;font-size:10px;' +
          'letter-spacing:.1em;text-transform:uppercase;color:var(--oro-txt);' +
          'margin-bottom:4px;">Conversación de WhatsApp</b>' +
          esc(r.conversacion) + '</div>'
        : '') +
      (tl || '<p style="color:var(--gris-txt);font-size:13px;">Sin movimientos ' +
        'registrados todavía.</p>') + '</div>');
  }).catch(function (e) {
    document.getElementById('dlgSub').textContent = 'No se pudo cargar: ' + e;
  });
}

function guardar(c) {
  document.getElementById('cuenta').textContent = 'Guardando…';
  apiEscribir('guardar', { pase: PASE, cambios: JSON.stringify(c) })
    .then(function (r) {
      if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
      if (!r || !r.ok) {
        alert('No se pudo guardar: ' + ((r && r.error) || 'sin respuesta del servidor') +
          '. Vuelve a intentarlo.');
        cargar();
        return;
      }
      aplicarLocal(c.fila, cambiosLocales(c));
      cargar();
    });
}

/* Lo que se acaba de guardar, con los nombres que usa la lista. */
function cambiosLocales(c) {
  var l = {};
  if (c.etapa) l.etapa = c.etapa;
  if (c.asignado !== undefined) l.asignado = c.asignado;
  if (c.programa !== undefined) l.programa = c.programa;
  if (c.otrosProgramas !== undefined) l.otrosProgramas = c.otrosProgramas;
  if (c.respondio) l.respondio = hoyDMA();
  if (c.tocar) { l.ultimo = hoyDMA(); l.dias = 0; }
  return l;
}

var _acc = [];
function dialogo(tit, sub, valor, botones) {
  // La ficha inserta su propio cuerpo; si no se quita, el siguiente diálogo
  // saldría con la historia del prospecto anterior encima.
  var vieja = document.getElementById('fichaCuerpo');
  if (vieja) vieja.remove();
  document.getElementById('dlgTxt').style.display = '';
  document.getElementById('dlgTit').textContent = tit;
  document.getElementById('dlgSub').textContent = sub;
  var ta = document.getElementById('dlgTxt');
  ta.value = valor || '';
  var fin = document.getElementById('dlgFin');
  fin.innerHTML = '<button data-cerrar="1">Cerrar</button>' +
    botones.map(function (b, i) {
      return '<button class="' + (b[2] ? '' : 'pri') + '" data-i="' + i + '">' +
        esc(b[0]) + '</button>';
    }).join('');
  _acc = botones;
  fin.querySelector('[data-cerrar]').onclick = function () {
    document.getElementById('dlg').close();
  };
  Array.prototype.forEach.call(fin.querySelectorAll('[data-i]'), function (el) {
    el.onclick = function () {
      var i = Number(el.getAttribute('data-i'));
      var t = ta.value.trim();
      var quedarse = !!_acc[i][2];   // los de "copiar" no cierran el cuadro
      _acc[i][1](t);
      if (!quedarse) document.getElementById('dlg').close();
    };
  });
  document.getElementById('dlg').showModal();
  ta.focus();
}

/* ═══════════════════════ TABLERO DE DECISIÓN ═══════════════════════
   No repite el embudo: busca lo que hay que DECIDIR. Cada hallazgo dice qué
   pasa y qué hacer con eso. */
function pintarTablero() {
  var t = DATOS.prospectos, n = t.length;
  var porEtapa = {}, porProg = {}, porCamp = {};
  t.forEach(function (p) {
    porEtapa[p.etapa] = (porEtapa[p.etapa] || 0) + 1;
    var k = p.programa || 'sin programa';
    if (!porProg[k]) porProg[k] = { n: 0, ins: 0 };
    porProg[k].n++;
    if (p.etapa === 'Inscrito') porProg[k].ins++;
    var c = p.campana || 'sin origen';
    if (!porCamp[c]) porCamp[c] = { n: 0, ins: 0 };
    porCamp[c].n++;
    if (p.etapa === 'Inscrito') porCamp[c].ins++;
  });
  var ins = porEtapa['Inscrito'] || 0;
  var graves = t.filter(function (p) { return p.estado === 'grave'; });
  var sinTel = t.filter(function (p) { return !p.telefono; });
  var sinTocar = t.filter(function (p) { return p.etapa === 'Nuevo' && !p.waEnviado; });
  var noAvisos = t.filter(function (p) { return p.avisos === 'no'; });
  var reps = t.filter(function (p) { return p.repetido; });

  var h = [];
  if (graves.length) {
    h.push(['malo', 'Hay ' + graves.length +
      ' persona(s) que llevan el doble de su plazo sin que nadie las mueva',
      'Son las que ya casi se pierden. Empieza el día por ellas: ' +
      graves.slice(0, 4).map(function (p) { return p.nombre; }).join(', ') +
      (graves.length > 4 ? ' y ' + (graves.length - 4) + ' más.' : '.')]);
  }
  if (sinTocar.length) {
    h.push(['malo', sinTocar.length + ' prospecto(s) nunca han recibido un WhatsApp',
      'Llenaron el formulario y nadie les escribió. Es lo más barato de ' +
      'arreglar y lo que más cuesta dejar así.']);
  }
  if (sinTel.length) {
    h.push(['', 'A ' + sinTel.length + ' no se les puede escribir por WhatsApp',
      'No dejaron teléfono. Si tienen correo, la secuencia sí les llega; si no, ' +
      'conviene sacarlos de la cuenta para no engañarse con el total.']);
  }
  if (reps.length) {
    h.push(['', reps.length + ' registro(s) repetidos por teléfono',
      'La misma persona llenó el formulario dos veces. Si dos asesores le ' +
      'escriben, se nota.']);
  }
  if (noAvisos.length) {
    h.push(['', noAvisos.length + ' pidieron no recibir avisos',
      'Se les puede responder su solicitud, pero quedan fuera de la secuencia ' +
      'automática. Es correcto que así sea.']);
  }

  var mejor = null, peor = null;
  Object.keys(porCamp).forEach(function (c) {
    var v = porCamp[c];
    if (v.n < 8) return;        // con menos de ocho no dice nada
    var r = v.ins / v.n;
    if (!mejor || r > mejor.r) mejor = { c: c, r: r, v: v };
    if (!peor || r < peor.r) peor = { c: c, r: r, v: v };
  });
  if (mejor && peor && mejor.c !== peor.c && mejor.r > peor.r * 2) {
    h.push(['bueno', '«' + mejor.c + '» convierte ' + Math.round(mejor.r * 100) +
      '% y «' + peor.c + '» ' + Math.round(peor.r * 100) + '%',
      'Si estás repartiendo inversión entre los dos, ahí tienes a dónde moverla. ' +
      'Ojo: son ' + mejor.v.n + ' y ' + peor.v.n + ' prospectos; con pocos, ' +
      'léelo como pista y no como prueba.']);
  }
  if (!h.length) {
    h.push(['bueno', 'Nada urgente',
      'Todos están dentro de su plazo. Buen momento para trabajar a quienes ' +
      'llevan más tiempo en la misma etapa.']);
  }

  var etapasHtml = (DATOS.etapas || []).map(function (e) {
    var c = porEtapa[e] || 0;
    return '<div class="fila"><span class="n">' + c + '</span>' +
      '<span class="b"><i style="width:' + (n ? Math.round(c / n * 100) : 0) +
      '%"></i></span><span class="t">' + esc(e) + '</span></div>';
  }).join('');

  var progHtml = Object.keys(porProg).sort(function (a, b) {
    return porProg[b].n - porProg[a].n;
  }).map(function (k) {
    var v = porProg[k];
    return '<div class="fila"><span class="n">' + v.n + '</span>' +
      '<span class="b"><i style="width:' + Math.round(v.n / n * 100) + '%"></i></span>' +
      '<span class="t">' + esc(k) + ' · ' + v.ins + ' inscrito(s)</span></div>';
  }).join('');

  document.getElementById('v-tablero').innerHTML =
    '<div class="rej">' +
      '<div class="caja"><h3>Qué decidir hoy</h3>' +
        '<p class="sub">Lo que el embudo no dice a simple vista.</p>' +
        h.map(function (x) {
          return '<div class="hallazgo ' + x[0] + '"><b>' + esc(x[1]) + '</b>' +
            '<span class="q">' + esc(x[2]) + '</span></div>';
        }).join('') +
      '</div>' +
      '<div class="caja"><h3>El embudo</h3>' +
        '<p class="sub">' + n + ' prospecto(s) · ' + ins + ' inscrito(s) · ' +
        (n ? Math.round(ins / n * 100) : 0) + '% de conversión</p>' + etapasHtml +
        '<p class="sub" style="margin-top:10px">Con menos de veinte prospectos, ' +
        'la conversión es anécdota y no dato.</p></div>' +
      '<div class="caja"><h3>Por programa</h3>' +
        '<p class="sub">Dónde está el interés y dónde se cierra.</p>' + progHtml +
      '</div>' +
    '</div>' +
    '<p style="margin-top:16px"><button class="pri" id="btnTablero">' +
    'Copiar el tablero para Claude</button></p>';
  document.getElementById('btnTablero').onclick = copiarTablero;
}

function copiarTablero() {
  var t = DATOS.prospectos, n = t.length;
  var e = {}, pr = {};
  t.forEach(function (p) {
    e[p.etapa] = (e[p.etapa] || 0) + 1;
    var k = p.programa || 'sin programa';
    if (!pr[k]) pr[k] = { n: 0, i: 0 };
    pr[k].n++;
    if (p.etapa === 'Inscrito') pr[k].i++;
  });
  var s = 'Embudo de admisiones de CESSUM al ' +
    new Date().toLocaleDateString('es-MX') + '\n\nTotal de prospectos: ' + n +
    '\n\nPor etapa:\n';
  Object.keys(e).forEach(function (k) { s += '  ' + k + ': ' + e[k] + '\n'; });
  s += '\nPor programa:\n';
  Object.keys(pr).forEach(function (k) {
    s += '  ' + k + ': ' + pr[k].n + ' → ' + pr[k].i + ' inscrito(s)\n';
  });
  s += '\nEn riesgo (rebasaron su plazo): ' +
    t.filter(function (p) { return p.estado === 'riesgo' || p.estado === 'grave'; }).length +
    '\nNuevos sin contactar: ' +
    t.filter(function (p) { return p.etapa === 'Nuevo' && !p.waEnviado; }).length +
    '\nSin teléfono: ' + t.filter(function (p) { return !p.telefono; }).length +
    '\n\n¿Qué harías esta semana con esto?';
  copiar(s, 'Tablero copiado. Pégalo en la conversación con Claude.');
}

/* ═══════════ RITMO DEL EQUIPO ═══════════
   La conversión depende de mil cosas que no controlas —el precio, la
   competencia, el momento de la persona—. El TIEMPO DE RESPUESTA sí lo
   controlas, y es lo que más pesa. Por eso tiene pestaña propia. */
var METRICAS = null;
function pintarRitmo() {
  var c = document.getElementById('v-ritmo');
  if (!METRICAS) {
    c.innerHTML = '<p class="vacio">Midiendo…</p>';
    api('metricas', { pase: PASE }).then(function (m) {
      if (m && m.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
      METRICAS = m;
      pintarRitmo();
    }).catch(function (e) {
      c.innerHTML = '<p class="vacio">No se pudo medir: ' + esc(String(e)) + '</p>';
    });
    return;
  }
  var m = METRICAS;
  var med = m.primerContactoHorasMediana;
  var prom = m.primerContactoHorasPromedio;

  function horas(h) {
    if (h === null || h === undefined) return '—';
    if (h < 1) return Math.round(h * 60) + ' min';
    if (h < 48) return (Math.round(h * 10) / 10) + ' h';
    return Math.round(h / 24) + ' días';
  }

  // El juicio se dice en palabras, no solo en cifras: un número sin criterio
  // no le sirve a quien tiene que decidir si esto está bien o mal.
  var juicio = med === null
    ? 'Todavía no hay suficientes contactos registrados para medir.'
    : med <= 2
      ? 'Excelente. Contestar en las primeras dos horas es lo que más mueve la ' +
        'inscripción, y lo están logrando.'
      : med <= 12
        ? 'Bien, pero hay margen. El salto grande está en bajar de las dos horas.'
        : med <= 24
          ? 'Se contesta el mismo día, aunque tarde. Quien pidió informes por la ' +
            'mañana ya buscó en otro lado por la tarde.'
          : 'Demasiado. Con más de un día, buena parte de la gente ya decidió en ' +
            'otra escuela o perdió el impulso.';

  var separacion = (med !== null && prom !== null && prom > med * 2)
    ? '<div class="hallazgo"><b>El promedio dobla a la mediana</b>' +
      '<span class="q">La mayoría se atiende en ' + horas(med) + ', pero unos ' +
      'pocos casos abandonados arrastran el promedio a ' + horas(prom) + '. ' +
      'El problema no es el ritmo general: son esos casos. Búscalos en la ' +
      'cola de hoy, ordenada por días.</span></div>'
    : '';

  var ases = (m.asesores || []).map(function (a) {
    return '<div class="fila"><span class="n">' + a.prospectos + '</span>' +
      '<span class="b"><i style="width:' +
      (a.prospectos ? Math.round(a.contactados / a.prospectos * 100) : 0) +
      '%"></i></span><span class="t">' + esc(a.asesor) + ' · ' +
      a.contactados + ' contactados' +
      (a.porContactar ? ' · <b style="color:var(--rojo)">' + a.porContactar +
        ' sin tocar</b>' : '') + '</span></div>';
  }).join('');

  var ors = (m.origenes || []).map(function (o) {
    var tasa = o.prospectos ? Math.round(o.inscritos / o.prospectos * 100) : 0;
    return '<div class="fila"><span class="n">' + o.prospectos + '</span>' +
      '<span class="b"><i style="width:' + tasa + '%"></i></span>' +
      '<span class="t">' + esc(o.origen) + ' · ' + o.inscritos +
      ' inscrito(s)' + (o.prospectos >= 8 ? ' · ' + tasa + '%' : '') + '</span></div>';
  }).join('');

  // Llegadas por día, como barras: dice si la campaña trae gente pareja o
  // en ráfagas, que es otra conversación con quien la administra.
  var maxDia = 1;
  (m.llegadaPorDia || []).forEach(function (d) { if (d.n > maxDia) maxDia = d.n; });
  var barras = (m.llegadaPorDia || []).map(function (d) {
    return '<div title="' + d.dia + ': ' + d.n + '" style="flex:1;display:flex;' +
      'flex-direction:column;justify-content:flex-end;height:70px;">' +
      '<div style="height:' + Math.round(d.n / maxDia * 100) + '%;' +
      'background:linear-gradient(180deg,var(--rojo),var(--oro));' +
      'border-radius:3px 3px 0 0;min-height:2px;"></div></div>';
  }).join('');

  // ── ¿VAMOS A LLEGAR? ──
  // Va primero y ocupa toda la fila. Es la única pregunta que importa cuando
  // hay meta y fecha, y todo lo demás son medios para moverla.
  var mt = m.meta || {};
  var metaHtml = '';
  if (mt.objetivo) {
    var avance = Math.min(100, Math.round(mt.llevamos / mt.objetivo * 100));
    var proy = Math.min(100, Math.round((mt.proyeccion || 0) / mt.objetivo * 100));
    metaHtml =
      '<div class="caja" style="margin-bottom:16px;' +
      (mt.alcanza ? '' : 'border-color:var(--rojo);') + '">' +
      '<h3>¿Vamos a llegar a ' + mt.objetivo + ' inscritos?</h3>' +
      '<p class="sub">Quedan <b>' + mt.diasRestantes + ' día(s)</b> hasta el ' +
      esc(mt.fechaLimite) + '.</p>' +
      // Dos barras superpuestas: lo real y lo proyectado. Ver el hueco entre
      // las dos dice más que cualquier cifra.
      '<div style="position:relative;height:26px;background:#F0EDEB;' +
      'border-radius:8px;overflow:hidden;margin-bottom:8px;">' +
        '<div style="position:absolute;inset:0;width:' + proy + '%;' +
        'background:repeating-linear-gradient(45deg,#E5C7A0,#E5C7A0 6px,' +
        '#F0E3CE 6px,#F0E3CE 12px);"></div>' +
        '<div style="position:absolute;inset:0;width:' + avance + '%;' +
        'background:linear-gradient(90deg,var(--rojo),var(--oro));' +
        'border-radius:8px 0 0 8px;"></div>' +
      '</div>' +
      '<div style="display:flex;gap:26px;flex-wrap:wrap;margin-bottom:12px;">' +
        '<div><div style="font-family:var(--display);font-size:32px;' +
        'font-weight:600;line-height:1;color:var(--rojo);">' + mt.llevamos +
        '</div><div style="font-size:10px;letter-spacing:.1em;' +
        'text-transform:uppercase;color:var(--gris-txt);">inscritos hoy</div></div>' +
        '<div><div style="font-family:var(--display);font-size:32px;' +
        'font-weight:600;line-height:1;color:var(--oro-txt);">' +
        (mt.proyeccion || 0) + '</div><div style="font-size:10px;' +
        'letter-spacing:.1em;text-transform:uppercase;color:var(--gris-txt);">' +
        'proyectados</div></div>' +
        '<div><div style="font-family:var(--display);font-size:32px;' +
        'font-weight:600;line-height:1;">' + (mt.ritmoPorSemana || 0) +
        '</div><div style="font-size:10px;letter-spacing:.1em;' +
        'text-transform:uppercase;color:var(--gris-txt);">por semana ahora</div></div>' +
        '<div><div style="font-family:var(--display);font-size:32px;' +
        'font-weight:600;line-height:1;color:' +
        (mt.alcanza ? 'var(--verde)' : 'var(--rojo)') + ';">' +
        (mt.necesarioPorSemana || 0) + '</div><div style="font-size:10px;' +
        'letter-spacing:.1em;text-transform:uppercase;color:var(--gris-txt);">' +
        'necesarias por semana</div></div>' +
      '</div>' +
      (mt.alcanza
        ? '<div class="hallazgo bueno"><b>Al ritmo actual sí se llega</b>' +
          '<span class="q">Con ' + mt.ritmoPorSemana + ' inscrito(s) por ' +
          'semana y ' + mt.diasRestantes + ' días, la proyección da ' +
          mt.proyeccion + '. Sostener el ritmo es suficiente; no hace falta ' +
          'nada heroico.</span></div>'
        : '<div class="hallazgo malo"><b>Al ritmo actual no se llega</b>' +
          '<span class="q">Van ' + mt.ritmoPorSemana + ' por semana y harían ' +
          'falta ' + mt.necesarioPorSemana + '. La diferencia no se cierra ' +
          'contestando más rápido: hace falta más gente entrando. Los ' +
          'referidos de los alumnos actuales y la sesión informativa son los ' +
          'dos canales que pueden moverlo en semanas, no en meses.</span></div>') +
      '<p style="font-size:11.5px;color:var(--gris-txt);margin:8px 0 0;">' +
      'La proyección usa el ritmo de las últimas dos semanas, no el ' +
      'histórico: lo que pasó en junio no dice nada sobre septiembre. Con ' +
      mt.inscritosUltimas2Semanas + ' inscrito(s) y ' +
      mt.llegadasUltimas2Semanas + ' llegada(s) en ese periodo, tómala como ' +
      'una tendencia, no como una promesa.</p>' +
      '</div>';
  }

  // ── DÓNDE SE CAE LA GENTE ──
  var emb = (m.embudo || []).map(function (e, k) {
    var ancho = (m.embudo[0] && m.embudo[0].llegaron)
      ? Math.round(e.llegaron / m.embudo[0].llegaron * 100) : 0;
    var caida = e.tasaDesdeAnterior !== null && e.tasaDesdeAnterior < 50;
    return '<div style="margin-bottom:9px;">' +
      '<div style="display:flex;align-items:center;gap:10px;font-size:12.5px;">' +
      '<span class="n" style="min-width:34px;text-align:right;font-weight:700;' +
      'font-family:var(--display);font-size:15px;">' + e.llegaron + '</span>' +
      '<span class="b" style="flex:1;height:12px;background:#F0EDEB;' +
      'border-radius:6px;overflow:hidden;"><i style="display:block;height:100%;' +
      'width:' + ancho + '%;background:linear-gradient(90deg,var(--rojo),' +
      'var(--oro));border-radius:6px;"></i></span>' +
      '<span style="min-width:150px;color:var(--gris-txt);font-size:11.5px;">' +
      esc(e.etapa) +
      (e.tasaDesdeAnterior !== null
        ? ' · <b style="color:' + (caida ? 'var(--rojo)' : 'inherit') + '">' +
          e.tasaDesdeAnterior + '%</b> pasa'
        : '') + '</span></div></div>';
  }).join('');

  var peor = null;
  (m.embudo || []).forEach(function (e) {
    if (e.tasaDesdeAnterior === null) return;
    if (!peor || e.tasaDesdeAnterior < peor.tasaDesdeAnterior) peor = e;
  });

  c.innerHTML = metaHtml +
    '<div class="caja" style="margin-bottom:16px"><h3>Dónde se cae la gente</h3>' +
      '<p class="sub">El total por etapa dice dónde ESTÁ la gente; el ' +
      'porcentaje dice cuánta PASA. Son preguntas distintas, y solo la ' +
      'segunda se puede arreglar.</p>' + emb +
      (peor && peor.tasaDesdeAnterior < 50
        ? '<div class="hallazgo"><b>El punto más flojo es «' +
          esc(peor.etapa) + '»</b><span class="q">Solo ' +
          peor.tasaDesdeAnterior + ' de cada 100 llegan ahí desde la etapa ' +
          'anterior. Ahí está el cuello, y arreglarlo vale más que traer más ' +
          'gente al principio del embudo.</span></div>'
        : '') +
      (m.noProcede
        ? '<p style="font-size:11.5px;color:var(--gris-txt);margin:8px 0 0;">' +
          m.noProcede + ' marcados como «No procede» quedan fuera de este ' +
          'cálculo: no son una caída, son gente que no aplicaba.</p>'
        : '') +
    '</div>' +
    '<div class="rej">' +
      '<div class="caja"><h3>Cuánto tardamos en contestar</h3>' +
        '<p class="sub">Medido desde que pidió informes hasta el primer ' +
        'WhatsApp registrado. ' + m.medidosPrimerContacto + ' caso(s) medidos.</p>' +
        '<div style="display:flex;gap:24px;margin-bottom:12px;">' +
          '<div><div style="font-family:var(--display);font-size:34px;' +
          'font-weight:600;color:var(--rojo);line-height:1;">' + horas(med) +
          '</div><div style="font-size:10px;letter-spacing:.1em;' +
          'text-transform:uppercase;color:var(--gris-txt);margin-top:4px;">' +
          'caso típico</div></div>' +
          '<div><div style="font-family:var(--display);font-size:34px;' +
          'font-weight:600;color:var(--oro-txt);line-height:1;">' + horas(prom) +
          '</div><div style="font-size:10px;letter-spacing:.1em;' +
          'text-transform:uppercase;color:var(--gris-txt);margin-top:4px;">' +
          'promedio</div></div>' +
        '</div>' +
        '<p style="font-size:12.5px;line-height:1.55;margin:0 0 10px;">' +
        esc(juicio) + '</p>' + separacion +
        (m.sinContactarMasDeUnDia
          ? '<div class="hallazgo malo"><b>' + m.sinContactarMasDeUnDia +
            ' llevan más de un día sin recibir nada</b><span class="q">Ni un ' +
            'WhatsApp. Es lo más barato de arreglar hoy.</span></div>'
          : '') +
      '</div>' +
      '<div class="caja"><h3>Por asesor</h3>' +
        '<p class="sub">Cuántos lleva cada quien y a cuántos ya escribió. ' +
        'Sirve para repartir, no para comparar.</p>' + ases + '</div>' +
      '<div class="caja"><h3>Por origen</h3>' +
        '<p class="sub">De dónde llega la gente y cuánta se inscribe. El ' +
        'porcentaje solo se muestra con ocho o más: debajo de eso no dice nada.</p>' +
        ors + '</div>' +
    '</div>' +
    '<div class="caja" style="margin-top:16px"><h3>Cuándo llegan</h3>' +
      '<p class="sub">Las tres últimas semanas. Si la campaña trae gente en ' +
      'ráfagas, conviene saberlo: los picos son cuando más se cae la atención.</p>' +
      '<div style="display:flex;gap:3px;align-items:flex-end;">' + barras + '</div>' +
    '</div>';
}

/* ═══════════ REGISTRO DE CORREOS ═══════════
   Qué se le mandó a quién y cuándo. Sirve para dos momentos concretos: el
   prospecto que reclama que le escribieron de más, y el que jura que nunca
   recibió nada. Sin este registro, en ambos casos es la palabra de uno
   contra la de otro. */
function pintarCorreos() {
  var c = document.getElementById('v-correos');
  c.innerHTML = '<p class="vacio">Cargando el registro…</p>';
  api('correos', { pase: PASE, limite: 150 }).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) {
      c.innerHTML = '<p class="vacio">No se pudo leer el registro.</p>';
      return;
    }
    if (!r.entradas.length) {
      c.innerHTML = '<p class="vacio"><b style="font-family:var(--display);' +
        'font-size:19px;">Todavía no ha salido ningún correo.</b><br>' +
        'La secuencia se corre desde el menú CESSUM de la hoja, y siempre ' +
        'conviene usar primero la opción de PRUEBA.</p>';
      return;
    }
    var pasos = r.porPaso || {};
    var resumen = Object.keys(pasos).sort().map(function (k) {
      return '<div class="fila"><span class="n">' + pasos[k] + '</span>' +
        '<span class="b"><i style="width:' +
        Math.round(pasos[k] / r.total * 100) + '%"></i></span>' +
        '<span class="t">paso ' + esc(k) + ' de 5</span></div>';
    }).join('');

    var filas = r.entradas.map(function (e) {
      var mal = e.estado !== 'Enviado';
      return '<tr style="border-bottom:1px solid var(--gris);' +
        (mal ? 'background:var(--rojo-pal);' : '') + '">' +
        '<td style="padding:8px 10px 8px 0;white-space:nowrap;color:var(--gris-txt);' +
        'font-size:11.5px;">' + esc(e.fecha) + '</td>' +
        '<td style="padding:8px 10px 8px 0;font-weight:600;">' +
        esc(e.prospecto) + '</td>' +
        '<td style="padding:8px 10px 8px 0;font-size:12px;color:var(--gris-txt);">' +
        esc(e.programa) + '</td>' +
        '<td style="padding:8px 10px 8px 0;text-align:center;">' +
        '<span class="tag oro">' + esc(e.paso) + '</span></td>' +
        '<td style="padding:8px 0;font-size:12.5px;">' + esc(e.asunto) +
        (mal ? '<br><span style="color:var(--rojo);font-size:11px;">' +
          esc(e.estado) + '</span>' : '') + '</td></tr>';
    }).join('');

    c.innerHTML =
      '<div class="rej" style="grid-template-columns:1fr">' +
        '<div class="caja"><h3>Qué ha salido</h3>' +
          '<p class="sub">' + r.total + ' correo(s) en total' +
          (r.fallidos ? ' · <b style="color:var(--rojo)">' + r.fallidos +
            ' no pudieron enviarse</b>' : ' · todos salieron bien') + '</p>' +
          resumen +
        '</div>' +
      '</div>' +
      '<div class="caja" style="margin-top:16px"><h3>Los últimos ' +
        r.entradas.length + '</h3>' +
        '<p class="sub">Lo más reciente primero. Antes de escribirle a ' +
        'alguien, mira qué le dijimos ya.</p>' +
        '<div style="overflow-x:auto"><table style="width:100%;' +
        'border-collapse:collapse;font-size:13px;">' + filas + '</table></div>' +
      '</div>';
  }).catch(function (e) {
    c.innerHTML = '<p class="vacio">No se pudo leer: ' + esc(String(e)) + '</p>';
  });
}

/* ═══════════ MODO ENFOQUE ═══════════
   Una lista de treinta personas paraliza: no se sabe por dónde empezar y se
   acaba mirando sin llamar a nadie. Aquí se ve UNA sola, la más urgente, con
   todo lo que hace falta para actuar y nada más. Al resolverla aparece la
   siguiente.

   Es el mismo trabajo, pero sin la decisión de a quién le toca — y esa
   decisión, repetida treinta veces, es la que hace que la lista no se
   trabaje. */
var ENFOQUE = { activo: false, cola: [], i: 0, yaOfrecido: false };

/* (8-sep) LA COLA DEL ENFOQUE, DEPURADA Y ORDENADA.
   Tres cosas la ensuciaban:

   1. Entraban los DUPLICADOS. Con dos fichas de la misma persona, el enfoque
      la presentaba dos veces y quien la trabajaba le escribía dos veces, o
      peor, dos asesores distintos lo hacían.
   2. Entraban los archivados como 'No procede' cuando había urgentes, porque
      el primer filtro solo miraba el estado y no la etapa.
   3. NO ESTABA ORDENADA. La cola salía en el orden de la hoja, así que quien
      llevaba 31 días esperando podía aparecer al final. El enfoque existe
      para quitar la decisión de por dónde empezar, y sin orden la devolvía. */
function abrirEnfoque() {
  var vistos = {};
  var base = DATOS.prospectos.filter(function (p) {
    if (p.etapa === 'Inscrito' || p.etapa === 'No procede') return false;
    if (p.baja) return false;
    // Una sola ficha por persona: la primera que se encuentre de cada teléfono.
    var k = telClave(p.telefono);
    if (k) { if (vistos[k]) return false; vistos[k] = 1; }
    return true;
  });

  var v = base.filter(function (p) {
    return p.estado === 'grave' || p.estado === 'riesgo';
  });
  if (!v.length) v = base;

  if (!v.length) {
    alert('No hay nadie pendiente. Todos están inscritos o cerrados.');
    return;
  }

  // El que lleva más tiempo esperando, primero. Es el que está más cerca de
  // perderse, y el que peor se siente si le contestan al mes.
  v.sort(function (a, b) { return (b.dias || 0) - (a.dias || 0); });

  ENFOQUE = { activo: true, cola: v, i: 0, yaOfrecido: true };
  pintarEnfoque();
}

function pintarEnfoque() {
  var e = document.getElementById('enfoqueCapa');
  if (!ENFOQUE.activo) { if (e) e.remove(); return; }
  if (ENFOQUE.i >= ENFOQUE.cola.length) {
    if (e) e.remove();
    ENFOQUE.activo = false;
    alert('Terminaste la cola. ' + ENFOQUE.cola.length +
          ' persona(s) atendidas.');
    cargar();
    return;
  }
  var p = ENFOQUE.cola[ENFOQUE.i];
  var s = sugerencia(p);

  if (!e) {
    e = document.createElement('div');
    e.id = 'enfoqueCapa';
    e.style.cssText = 'position:fixed;inset:0;z-index:80;background:var(--vino);' +
      'overflow:auto;padding:26px 20px;';
    document.body.appendChild(e);
  }

  e.innerHTML =
    '<div style="max-width:620px;margin:0 auto;">' +
      '<div style="display:flex;justify-content:space-between;align-items:center;' +
      'margin-bottom:18px;color:var(--oro-pal);font-size:12px;' +
      'letter-spacing:.12em;text-transform:uppercase;font-weight:700;">' +
        '<span>' + (ENFOQUE.i + 1) + ' de ' + ENFOQUE.cola.length + '</span>' +
        '<button id="salirEnfoque" style="background:transparent;' +
        'border:1px solid rgba(229,199,160,.4);color:var(--oro-pal);">' +
        'Salir · Esc</button>' +
      '</div>' +
      '<div style="background:#fff;border-radius:16px;padding:24px;' +
      'box-shadow:0 20px 60px rgba(0,0,0,.3);">' +
        '<h2 style="font-family:var(--display);font-size:26px;margin:0 0 3px;' +
        'font-weight:600;">' + esc(p.nombre) + '</h2>' +
        '<p class="meta" style="margin:0 0 14px;"><b>' +
        esc(p.programa || 'Sin programa') + '</b>' +
        (p.telefono ? ' · ' + esc(p.telefono) : ' · sin teléfono') +
        (p.dias !== null ? ' · <b style="color:var(--rojo)">' + p.dias +
          ' día(s) esperando</b>' : '') + '</p>' +
        (p.pregunta ? '<p class="preg">' + esc(p.pregunta) + '</p>' : '') +
        (p.proxima ? '<p class="preg" style="background:#FFF8EC;' +
          'border-left-color:var(--ambar);"><b style="display:block;' +
          'font-size:9.5px;letter-spacing:.11em;text-transform:uppercase;' +
          'color:#7E5A0C;margin-bottom:3px;">Lo que sigue</b>' +
          esc(p.proxima) + '</p>' : '') +
        (s ? '<div class="sug"><b>' + esc(s.t) + '</b>' + esc(s.m) + '</div>' : '') +
        (p.notas ? '<p class="hist">' + esc(p.notas) + '</p>' : '') +
        '<div class="acc" style="margin-top:16px;">' +
          (p.telefono
            ? '<button class="wa" id="eWa">Escribirle · W</button>'
            : '<button disabled>Sin teléfono</button>') +
          '<button id="eNota">Anotar algo</button>' +
          '<button id="eNo">No procede</button>' +
          '<button id="eSig" class="pri">Siguiente · →</button>' +
        '</div>' +
      '</div>' +
      '<p style="text-align:center;color:rgba(246,235,228,.5);font-size:11px;' +
      'margin-top:16px;">W escribir · N anotar · → siguiente · Esc salir</p>' +
    '</div>';

  document.getElementById('salirEnfoque').onclick = cerrarEnfoque;
  document.getElementById('eSig').onclick = siguienteEnfoque;
  var w = document.getElementById('eWa');
  if (w) w.onclick = function () { waAbrirIA(p); };   // (28-sep) mismo diálogo con IA
  document.getElementById('eNota').onclick = function () {
    var t = prompt('¿Qué anotas de ' + p.nombre + '?');
    if (t) guardarSilencioso({ fila: p.fila, nota: t });
  };
  document.getElementById('eNo').onclick = function () {
    if (!confirm('¿Marcar a ' + p.nombre + ' como «No procede»? Sale del ' +
                 'embudo y deja de recibir correos.')) return;
    guardarSilencioso({ fila: p.fila, etapa: 'No procede', tocar: true });
    siguienteEnfoque();
  };
}

// Guarda sin recargar toda la pantalla: recargar en medio del enfoque
// borraría la cola y devolvería al principio.
function guardarSilencioso(c) {
  apiEscribir('guardar', { pase: PASE, cambios: JSON.stringify(c) }).then(function (r) {
    if (r && r.ok) aplicarLocal(c.fila, cambiosLocales(c));
    else alert('No se pudo guardar: ' + ((r && r.error) || 'sin respuesta del servidor') + '.');
  });
}

function siguienteEnfoque() { ENFOQUE.i++; pintarEnfoque(); }

function cerrarEnfoque() {
  ENFOQUE.activo = false;
  var e = document.getElementById('enfoqueCapa');
  if (e) e.remove();
  cargar();
}

/* ══════════════════════════════════════════════════════════════════════
   (25-sep) CENTRO DE MENSAJES — envío asistido por segmento, con IA
   ----------------------------------------------------------------------
   Sin la API de WhatsApp Business no hay forma segura de que una página
   envíe sola: un navegador no puede pulsar «Enviar» en WhatsApp, y las
   herramientas que lo simulan violan sus reglas (el espaciado no evita el
   bloqueo; lo que lo provoca es escribir en masa a quien no escribió y lo
   reporta). Por eso aquí el sistema hace TODO lo demás —elige a quién,
   redacta con IA, personaliza, rota variantes, copia la imagen y registra
   el contacto— y la persona solo pulsa Enviar en WhatsApp. Un ritmo mínimo
   entre envíos mantiene un paso prudente.
   Cuando se conecte la API del bot, este mismo centro enviará solo con
   plantillas aprobadas por Meta.
   ══════════════════════════════════════════════════════════════════════ */
var ENV = {
  programas: {}, etapas: { 'Nuevo': 1, 'Contactado': 1, 'Interesado': 1, 'Documentos en proceso': 1 },
  diasSinContacto: 3, excluidos: {}, mensaje: '', variantes: [], rotar: true, alertas: [], consejos: [],
  imagen: null, cola: [], i: 0, enviados: 0, omitidos: 0, ritmo: 40, proximo: 0, activo: false, reloj: null
};

function _envDias_(fecha) {
  var m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})/.exec(String(fecha || ''));
  if (!m) return null;
  var d = new Date(+m[3], +m[2] - 1, +m[1]);
  return Math.floor((Date.now() - d.getTime()) / 86400000);
}
function _envTel_(p) {
  var d = String(p.telefono || '').replace(/\D/g, '');
  if (d.length === 12 && d.indexOf('52') === 0) d = d.slice(2);
  if (d.length === 13 && d.indexOf('521') === 0) d = d.slice(3);
  return d.length === 10 ? d : '';
}
function envDestinatarios() {
  var todos = (DATOS && DATOS.prospectos) || [], vistos = {}, out = [];
  var progSel = Object.keys(ENV.programas);
  todos.forEach(function (p) {
    var tel = _envTel_(p);
    if (!tel) return;
    if (progSel.length && !ENV.programas[p.programa]) return;
    if (!ENV.etapas[p.etapa]) return;
    var dias = _envDias_(p.ultimo);
    if (ENV.diasSinContacto > 0 && dias !== null && dias < ENV.diasSinContacto) return;
    if (vistos[tel]) return;
    vistos[tel] = 1;
    out.push(p);
  });
  return out;
}
function _envNombre_(p) {
  if (p.sinNombre) return '';
  var n = String(p.nombre || '').trim().split(/\s+/)[0] || '';
  return n ? n.charAt(0).toUpperCase() + n.slice(1).toLowerCase() : '';
}
function envPersonalizar(texto, p) {
  var nom = _envNombre_(p);
  var t = String(texto || '');
  t = nom ? t.replace(/\{nombre\}/g, nom) : t.replace(/Hola\s*\{nombre\}\s*,?/g, 'Hola,').replace(/\{nombre\}/g, '');
  return t.replace(/\{programa\}/g, p.programa || 'nuestros programas');
}
function envTextos() {
  var t = [ENV.mensaje].concat(ENV.rotar ? ENV.variantes : []);
  return t.filter(function (x) { return String(x || '').trim(); });
}

function pintarEnvios() {
  var c = document.getElementById('v-envios');
  if (!c) return;
  if (!DATOS || !DATOS.prospectos) { c.innerHTML = '<p style="color:#8a7f70">Cargando prospectos…</p>'; return; }
  if (ENV.activo) { pintarEnvioActivo(); return; }
  var progs = {};
  DATOS.prospectos.forEach(function (p) { if (p.programa) progs[p.programa] = (progs[p.programa] || 0) + 1; });
  var dest = envDestinatarios().filter(function (p) { return !ENV.excluidos[p.fila]; });
  var textos = envTextos();
  var ej = dest[0];
  var h = '';
  h += '<div class="env-caja"><h3>1 · A quién</h3>';
  h += '<p class="env-sub">Programas (sin marcar ninguno = todos):</p><div class="env-chips">';
  Object.keys(progs).sort().forEach(function (k) {
    h += '<label class="env-chip' + (ENV.programas[k] ? ' on' : '') + '"><input type="checkbox" data-prog="' + esc(k) + '"' +
      (ENV.programas[k] ? ' checked' : '') + '> ' + esc(k) + ' <b>' + progs[k] + '</b></label>';
  });
  h += '</div><p class="env-sub">Etapas:</p><div class="env-chips">';
  ['Nuevo', 'Contactado', 'Interesado', 'Documentos en proceso', 'Inscrito', 'No procede'].forEach(function (e) {
    h += '<label class="env-chip' + (ENV.etapas[e] ? ' on' : '') + '"><input type="checkbox" data-etapa="' + esc(e) + '"' +
      (ENV.etapas[e] ? ' checked' : '') + '> ' + esc(e) + '</label>';
  });
  h += '</div><p class="env-sub">No escribir a quien se contactó hace menos de <input id="envDias" type="number" min="0" max="60" value="' +
    ENV.diasSinContacto + '" style="width:56px"> días. Los teléfonos repetidos se cuentan una sola vez.</p>';
  h += '<p class="env-total"><b>' + dest.length + '</b> destinatario(s)' +
    (Object.keys(ENV.excluidos).length ? ' · ' + Object.keys(ENV.excluidos).length + ' quitado(s) a mano' : '') + '</p>';
  if (dest.length > 50) h += '<p class="env-alerta">Son más de 50. Para cuidar el número, conviene repartir el envío en varios días, empezando por quienes escribieron más recientemente.</p>';
  h += '<details><summary>Ver la lista y quitar personas</summary><div class="env-lista">';
  envDestinatarios().forEach(function (p) {
    var fuera = !!ENV.excluidos[p.fila];
    h += '<label class="env-fila"><input type="checkbox" data-excl="' + p.fila + '"' + (fuera ? '' : ' checked') + '> ' +
      esc(p.nombre) + ' · <span style="color:#8a7f70">' + esc(p.programa || '') + ' · ' + esc(p.etapa) +
      (p.ultimo ? ' · último contacto ' + esc(p.ultimo) : ' · sin contacto') + '</span></label>';
  });
  h += '</div></details></div>';

  h += '<div class="env-caja"><h3>2 · Qué decir</h3>';
  h += '<p class="env-sub">Cuéntale a la IA qué quieres comunicar. Ella redacta con la información oficial de la convocatoria, sin inventar fechas ni precios.</p>';
  h += '<textarea id="envIndicacion" rows="3" placeholder="Ej.: Recordarles que la Maestría en Educación inicia el 2 de octubre y que todavía pueden inscribirse; invitarlos a pedir su ficha de inscripción."></textarea>';
  h += '<p><button id="envRedactar" class="env-btn">Redactar con IA</button></p>';
  h += '<p class="env-sub">Mensaje (usa {nombre} y {programa}; se sustituyen para cada persona):</p>';
  h += '<textarea id="envMensaje" rows="7">' + esc(ENV.mensaje) + '</textarea>';
  if (ENV.variantes.length) {
    h += '<label class="env-sub"><input type="checkbox" id="envRotar"' + (ENV.rotar ? ' checked' : '') +
      '> Rotar con ' + ENV.variantes.length + ' variante(s) para que no a todos les llegue el mismo texto</label>';
    ENV.variantes.forEach(function (v, i) {
      h += '<textarea class="envVar" data-i="' + i + '" rows="4" style="margin-top:6px">' + esc(v) + '</textarea>';
    });
  }
  if (ENV.alertas.length) h += '<div class="env-alerta"><b>Revisa:</b><br>' + ENV.alertas.map(esc).join('<br>') + '</div>';
  if (ENV.consejos.length) h += '<div class="env-nota"><b>Consejos:</b><br>' + ENV.consejos.map(esc).join('<br>') + '</div>';
  if (ej && textos.length) {
    h += '<p class="env-sub" style="margin-top:12px">Así le llegaría a <b>' + esc(ej.nombre) + '</b>:</p>' +
      '<div class="env-previa">' + esc(envPersonalizar(textos[0], ej)).replace(/\n/g, '<br>') + '</div>';
  }
  h += '</div>';

  h += '<div class="env-caja"><h3>3 · Imagen (opcional)</h3>';
  h += '<p class="env-sub">WhatsApp no permite adjuntar imágenes desde un enlace. La imagen se copia sola en cada envío: al abrirse el chat, pulse <b>Ctrl+V</b> (o mantenga presionado y «Pegar» en el celular) y luego Enviar.</p>';
  h += '<input type="file" id="envImagen" accept="image/png,image/jpeg,image/webp">';
  if (ENV.imagen) h += '<div style="margin-top:8px"><img src="' + ENV.imagen.url + '" style="max-width:220px;max-height:220px;border:1px solid #d9d0c2;border-radius:6px"><br>' +
    '<button id="envQuitarImg" class="env-btn2">Quitar imagen</button></div>';
  h += '</div>';

  h += '<div class="env-caja"><h3>4 · Enviar</h3>';
  h += '<p class="env-sub">Ritmo mínimo entre envíos: <select id="envRitmo">' +
    [[25, '25 segundos'], [40, '40 segundos (recomendado)'], [60, '1 minuto'], [90, '1 minuto y medio']].map(function (o) {
      return '<option value="' + o[0] + '"' + (ENV.ritmo === o[0] ? ' selected' : '') + '>' + o[1] + '</option>';
    }).join('') + '</select> (varía un poco en cada envío para que no sea mecánico).</p>';
  h += '<p><button id="envIniciar" class="env-btn"' + (dest.length && textos.length ? '' : ' disabled') + '>Preparar envío a ' + dest.length + ' persona(s)</button></p>';
  h += '<div class="env-nota"><b>Envío automático con la API:</b> cuando se conecte WhatsApp Business (el bot), este mismo centro enviará solo, con plantillas aprobadas por Meta e imagen incluida, sin abrir chats uno por uno.</div>';
  h += '</div>';
  c.innerHTML = h;

  Array.prototype.forEach.call(c.querySelectorAll('[data-prog]'), function (el) {
    el.onchange = function () { var k = el.getAttribute('data-prog'); if (el.checked) ENV.programas[k] = 1; else delete ENV.programas[k]; ENV.excluidos = {}; pintarEnvios(); };
  });
  Array.prototype.forEach.call(c.querySelectorAll('[data-etapa]'), function (el) {
    el.onchange = function () { var k = el.getAttribute('data-etapa'); if (el.checked) ENV.etapas[k] = 1; else delete ENV.etapas[k]; pintarEnvios(); };
  });
  Array.prototype.forEach.call(c.querySelectorAll('[data-excl]'), function (el) {
    el.onchange = function () { var f = el.getAttribute('data-excl'); if (el.checked) delete ENV.excluidos[f]; else ENV.excluidos[f] = 1; pintarEnvios(); };
  });
  document.getElementById('envDias').onchange = function () { ENV.diasSinContacto = Math.max(0, parseInt(this.value, 10) || 0); pintarEnvios(); };
  document.getElementById('envMensaje').oninput = function () { ENV.mensaje = this.value; };
  document.getElementById('envMensaje').onchange = function () { pintarEnvios(); };
  Array.prototype.forEach.call(c.querySelectorAll('.envVar'), function (el) {
    el.oninput = function () { ENV.variantes[+el.getAttribute('data-i')] = el.value; };
  });
  var rot = document.getElementById('envRotar'); if (rot) rot.onchange = function () { ENV.rotar = rot.checked; pintarEnvios(); };
  document.getElementById('envRitmo').onchange = function () { ENV.ritmo = parseInt(this.value, 10) || 40; };
  document.getElementById('envRedactar').onclick = function () {
    var b = this, ind = document.getElementById('envIndicacion').value.trim();
    if (!ind) { alert('Escribe qué quieres comunicar.'); return; }
    b.disabled = true; b.textContent = 'Redactando…';
    apiEscribir('envio_redactar', { pase: PASE, indicacion: ind, programas: Object.keys(ENV.programas).join(', '),
      etapas: Object.keys(ENV.etapas).join(', '), destinatarios: dest.length }).then(function (r) {
      b.disabled = false; b.textContent = 'Redactar con IA';
      if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
      if (!r || !r.ok) { alert((r && r.error) || 'No se pudo redactar.'); return; }
      ENV.mensaje = r.mensaje || ''; ENV.variantes = r.variantes || []; ENV.alertas = r.alertas || []; ENV.consejos = r.consejos || [];
      ENV.rotar = ENV.variantes.length > 0;
      var ind2 = ind; pintarEnvios(); document.getElementById('envIndicacion').value = ind2;
    });
  };
  document.getElementById('envImagen').onchange = function () {
    var f = this.files && this.files[0]; if (!f) return;
    /* Se convierte a PNG: es el único formato que el portapapeles acepta en todos los navegadores. */
    var img = new Image(), url = URL.createObjectURL(f);
    img.onload = function () {
      var cv = document.createElement('canvas'), max = 1600, k = Math.min(1, max / Math.max(img.width, img.height));
      cv.width = Math.round(img.width * k); cv.height = Math.round(img.height * k);
      cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
      cv.toBlob(function (blob) { ENV.imagen = { blob: blob, url: URL.createObjectURL(blob) }; URL.revokeObjectURL(url); pintarEnvios(); }, 'image/png');
    };
    img.src = url;
  };
  var qi = document.getElementById('envQuitarImg'); if (qi) qi.onclick = function () { ENV.imagen = null; pintarEnvios(); };
  document.getElementById('envIniciar').onclick = function () {
    var cola = envDestinatarios().filter(function (p) { return !ENV.excluidos[p.fila]; });
    if (!cola.length || !envTextos().length) return;
    if (!confirm('Se preparará el envío a ' + cola.length + ' persona(s). En cada una se abrirá su chat de WhatsApp con el mensaje escrito' +
      (ENV.imagen ? ' y la imagen copiada para pegarla' : '') + '; usted pulsa Enviar. Cada envío queda anotado en la ficha. ¿Comenzar?')) return;
    ENV.cola = cola; ENV.i = 0; ENV.enviados = 0; ENV.omitidos = 0; ENV.proximo = 0; ENV.activo = true;
    pintarEnvios();
  };
}

function pintarEnvioActivo() {
  var c = document.getElementById('v-envios');
  if (ENV.reloj) { clearInterval(ENV.reloj); ENV.reloj = null; }
  if (ENV.i >= ENV.cola.length) {
    ENV.activo = false;
    c.innerHTML = '<div class="env-caja"><h3>Envío terminado</h3><p><b>' + ENV.enviados + '</b> enviado(s) · ' + ENV.omitidos +
      ' omitido(s). Cada envío quedó anotado en la ficha del prospecto.</p><p><button class="env-btn" id="envOtro">Preparar otro envío</button></p></div>';
    document.getElementById('envOtro').onclick = function () { ENV.excluidos = {}; pintarEnvios(); };
    cargar();
    return;
  }
  var p = ENV.cola[ENV.i], textos = envTextos(), texto = envPersonalizar(textos[ENV.i % textos.length], p);
  var h = '<div class="env-caja"><h3>Enviando · ' + (ENV.i + 1) + ' de ' + ENV.cola.length + '</h3>';
  h += '<div class="env-barra"><div style="width:' + Math.round(ENV.i / ENV.cola.length * 100) + '%"></div></div>';
  h += '<p style="font-size:16px;margin:12px 0 2px"><b>' + esc(p.nombre) + '</b></p><p class="env-sub">' + esc(p.programa || '') + ' · ' + esc(p.etapa) +
    ' · ' + esc(p.telefono || '') + '</p>';
  h += '<div class="env-previa">' + esc(texto).replace(/\n/g, '<br>') + '</div>';
  if (ENV.imagen) h += '<p class="env-sub">La imagen se copiará al abrir el chat: péguela con <b>Ctrl+V</b> antes de Enviar.</p>';
  h += '<p><button id="envAbrir" class="env-btn">Abrir WhatsApp y registrar</button> <button id="envOmitir" class="env-btn2">Omitir</button> ' +
    '<button id="envParar" class="env-btn2">Terminar aquí</button></p>';
  h += '<p class="env-sub">' + ENV.enviados + ' enviado(s) · ' + ENV.omitidos + ' omitido(s)</p></div>';
  c.innerHTML = h;
  var b = document.getElementById('envAbrir');
  function tic() {
    var falta = Math.ceil((ENV.proximo - Date.now()) / 1000);
    if (falta > 0) { b.disabled = true; b.textContent = 'Siguiente en ' + falta + ' s'; }
    else { b.disabled = false; b.textContent = 'Abrir WhatsApp y registrar'; if (ENV.reloj) { clearInterval(ENV.reloj); ENV.reloj = null; } }
  }
  tic(); if (ENV.proximo > Date.now()) ENV.reloj = setInterval(tic, 500);
  b.onclick = function () {
    if (ENV.imagen && navigator.clipboard && window.ClipboardItem) {
      try { navigator.clipboard.write([new ClipboardItem({ 'image/png': ENV.imagen.blob })]); } catch (e) {}
    }
    var tel = _envTel_(p);
    window.open('https://wa.me/52' + tel + '?text=' + encodeURIComponent(texto), 'cessum_wa');
    apiEscribir('whatsapp', { pase: PASE, fila: p.fila }).then(function (r) { if (r && r.ok) localWhatsapp(p, r); });
    ENV.enviados++; ENV.i++;
    var base = ENV.ritmo * 1000, varia = base * 0.3;
    ENV.proximo = Date.now() + base + Math.round((Math.random() * 2 - 1) * varia);
    pintarEnvioActivo();
  };
  document.getElementById('envOmitir').onclick = function () { ENV.omitidos++; ENV.i++; pintarEnvioActivo(); };
  document.getElementById('envParar').onclick = function () {
    ENV.omitidos += ENV.cola.length - ENV.i; ENV.i = ENV.cola.length; pintarEnvioActivo();
  };
}

function ver(v) {
  VISTA = v;
  document.getElementById('v-cola').style.display = (v === 'cola') ? 'block' : 'none';
  document.getElementById('v-repetidos').style.display = (v === 'repetidos') ? 'block' : 'none';
  document.getElementById('v-publicidad').style.display = (v === 'publicidad') ? 'block' : 'none';
  document.getElementById('v-prioridad').style.display = (v === 'prioridad') ? 'block' : 'none';
  document.getElementById('v-bot').style.display = (v === 'bot') ? 'block' : 'none';
  document.getElementById('v-envios').style.display = (v === 'envios') ? 'block' : 'none';
  document.getElementById('v-impulso').style.display = (v === 'impulso') ? 'block' : 'none';
  document.getElementById('v-tablero').className = 'tab' + (v === 'tablero' ? ' on' : '');
  document.getElementById('v-ritmo').className = 'tab' + (v === 'ritmo' ? ' on' : '');
  document.getElementById('v-correos').className = 'tab' + (v === 'correos' ? ' on' : '');
  document.getElementById('v-inscripciones').className =
    'tab' + (v === 'inscripciones' ? ' on' : '');
  document.getElementById('v-cierre').className = 'tab' + (v === 'cierre' ? ' on' : '');
  document.getElementById('v-asistente').className =
    'tab' + (v === 'asistente' ? ' on' : '');
  if (v === 'inscripciones') pintarInscripciones();
  if (v === 'cierre') pintarCierre();
  if (v === 'asistente') pintarAsistente();
  if (v === 'ritmo') pintarRitmo();
  if (v === 'correos') pintarCorreos();
  if (v === 'repetidos') pintarRepetidos();
  if (v === 'publicidad') pintarPublicidad();
  if (v === 'prioridad') pintarPrioridad();
  if (v === 'bot') pintarBot();
  if (v === 'envios') pintarEnvios();
  if (v === 'impulso') pintarImpulso();
  Array.prototype.forEach.call(document.querySelectorAll('.pest button'), function (b) {
    b.className = (b.getAttribute('data-v') === v) ? 'on' : '';
  });
  pintar();
}
Array.prototype.forEach.call(document.querySelectorAll('.pest button'), function (b) {
  b.onclick = function () { ver(b.getAttribute('data-v')); };
});


/* ══════════════════════════════════════════════════════════════════════
   (1-oct-2026) IMPULSO CESSUM · envío uno por uno a prospectos de
   Maestría en Educación
   ──────────────────────────────────────────────────────────────────────
   Solo prospectos de Maestría en Educación, con teléfono. El mensaje es
   SIEMPRE el mismo texto fijo (el mismo para todos, sin nombre) — no pasa
   por IA, a propósito: es una campaña con un solo copy ya aprobado. El
   botón arma el link de WhatsApp con el texto ya listo y lo abre; lo que
   se envía lo envía una persona, con un clic por contacto.
   WhatsApp NO permite adjuntar una imagen desde el link — por eso aquí se
   ofrece el menú nativo de "Compartir" del dispositivo (texto + imagen
   juntos, usted elige WhatsApp ahí) cuando el navegador lo soporta, con
   el link de siempre como respaldo automático cuando no.
   "Ya enviado" se recuerda en este navegador (localStorage), solo como
   ayuda visual para no mandarlo dos veces sin querer; no es un registro
   del servidor. La imagen cargada TAMBIÉN se guarda solo en este
   navegador — si otra persona del equipo usa el panel desde otra
   computadora, tiene que cargarla ahí también.
   ══════════════════════════════════════════════════════════════════════ */
function impulsoMensaje(nombreCompleto) {
  // (2-oct-2026, copy nuevo) Texto definitivo del usuario, exacto, y SIN nombre
  // de pila: ya no arranca con "Nombre, ..." sino con el titular. El parametro
  // se conserva para no tocar a quienes llaman a esta funcion (el boton de
  // WhatsApp, el de copiar y el cuadro "Texto de la campana").
  // El regalo se escribe como escape Unicode (\u{1F381}) y NO como el
  // caracter pegado: el archivo queda en ASCII puro en ese punto, sin
  // depender de la codificacion con que se guarde o suba. Es el mismo tipo
  // de escape que ya usan los botones de este panel (\u{1F4CB}).
  return '\u{1F381} Tu inscripción a la Maestría en Educación puede salir GRATIS.\n\n' +
    'Con el Impulso CESSUM descubres cuánto pagas de inscripción: $225, $175, $125 o gratis, en lugar de $450. ' +
    'Una sola participación por persona, y cada día que pasa es menor la probabilidad de que salga gratis, ' +
    'así que conviene abrirlo hoy:\n' +
    'https://www.cessum.mx/impulso-cessum.php\n\n' +
    'Al abrirlo tienes 30 minutos para confirmar tu lugar por WhatsApp con tu código. ' +
    'Vigente hasta el domingo 4 de octubre; las clases empiezan la semana que entra. ' +
    'El Impulso aplica a la inscripción; la colegiatura de $2,850 al mes sigue igual.\n\n' +
    'WhatsApp 642 137 6117 · Porque en CESSUM somos más que una universidad, una familia.';
}
function impulsoEnviadosKey() { return 'impulso_cessum_enviados'; }
// (1-oct-2026) La clave es el TELÉFONO, no la fila — la fila es la
// posición del prospecto en la hoja de Admisiones, que puede cambiar
// entre una carga y otra si se agregan o quitan prospectos (aunque sea
// el mismo, puede aterrizar en otra fila). Con la fila como clave, el
// candado de "ya enviado" se perdía al recargar porque la fila ya no
// coincidía. El teléfono no cambia.
function impulsoYaEnviado(clave) {
  try {
    var m = JSON.parse(localStorage.getItem(impulsoEnviadosKey()) || '{}');
    return !!m[clave];
  } catch (e) { return false; }
}
function impulsoMarcarEnviado(clave) {
  try {
    var m = JSON.parse(localStorage.getItem(impulsoEnviadosKey()) || '{}');
    m[clave] = Date.now();
    localStorage.setItem(impulsoEnviadosKey(), JSON.stringify(m));
  } catch (e) {}
}
function impulsoFechaEnvio(clave) {
  try {
    var m = JSON.parse(localStorage.getItem(impulsoEnviadosKey()) || '{}');
    var ts = m[clave];
    if (!ts) return '';
    var d = new Date(ts);
    var pad = function (n) { return (n < 10 ? '0' : '') + n; };
    return pad(d.getDate()) + '/' + pad(d.getMonth() + 1) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  } catch (e) { return ''; }
}
function impulsoImagenKey() { return 'impulso_cessum_imagen'; }
function impulsoImagenGuardada() {
  try { return localStorage.getItem(impulsoImagenKey()) || ''; } catch (e) { return ''; }
}
function impulsoGuardarImagen(dataUrl) {
  try { localStorage.setItem(impulsoImagenKey(), dataUrl); } catch (e) {
    alert('No se pudo guardar la imagen en este navegador (puede ser muy pesada). Prueba con una más ligera.');
  }
}
function impulsoQuitarImagen() {
  try { localStorage.removeItem(impulsoImagenKey()); } catch (e) {}
  pintarImpulso();
}
// Copia la imagen al portapapeles en PNG (tamaño y calidad originales,
// sin recomprimir) para pegarla con Ctrl+V directo en el chat de
// WhatsApp que se abrió — más rápido que descargar y volver a adjuntar.
function impulsoCopiarImagen(btn) {
  var dataUrl = impulsoImagenGuardada();
  if (!dataUrl) return;
  if (!navigator.clipboard || !window.ClipboardItem) {
    alert('Este navegador no permite copiar imágenes al portapapeles. Usa "Descargar" y adjúntala desde ahí.');
    return;
  }
  var textoOrig = btn.textContent;
  btn.disabled = true; btn.textContent = 'Copiando…';
  var img = new Image();
  img.onload = function () {
    var cv = document.createElement('canvas');
    cv.width = img.naturalWidth; cv.height = img.naturalHeight;
    cv.getContext('2d').drawImage(img, 0, 0);
    cv.toBlob(function (blob) {
      if (!blob) { btn.disabled = false; btn.textContent = textoOrig; alert('No se pudo preparar la imagen.'); return; }
      navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })])
        .then(function () { btn.textContent = '✓ Copiada'; setTimeout(function () { btn.disabled = false; btn.textContent = textoOrig; }, 1800); })
        .catch(function () { btn.disabled = false; btn.textContent = textoOrig; alert('No se pudo copiar. Usa "Descargar" y adjúntala desde ahí.'); });
    }, 'image/png', 1);
  };
  img.onerror = function () { btn.disabled = false; btn.textContent = textoOrig; alert('No se pudo leer la imagen guardada.'); };
  img.src = dataUrl;
}
// (1-oct-2026, corregido) El menú nativo de "Compartir" NO permite elegir
// a qué contacto va el mensaje — WhatsApp se abría sin el número
// preseleccionado, obligando a buscarlo a mano cada vez, que es
// justo lo que este botón debía evitar. Por eso siempre va por el link
// directo (wa.me), que sí abre el chat con el número correcto ya puesto,
// con el texto listo. La imagen, si se cargó, sigue disponible arriba
// para copiarla o descargarla y pegarla a mano en ese mismo chat.
function impulsoEnviarA(p) {
  var mensaje = impulsoMensaje(p.nombre);
  window.open(waLink(p, mensaje), 'cessum_wa');
  impulsoMarcarEnviado(waTel(p));
  pintarImpulso();
}
var IMPULSO_FILTRO = 'todos'; // todos | pendientes | enviados_sin_participar | participaron
var IMPULSO_BUSQUEDA = '';
var IMPULSO_PARTICIPANTES = null; // null = aún no cargado
function impulsoCargarParticipantes() {
  api('impulso_cessum_participantes', {}, true).then(function (data) {
    IMPULSO_PARTICIPANTES = (data && data.ok) ? data.participantes : [];
    pintarImpulso();
  }).catch(function () { IMPULSO_PARTICIPANTES = []; pintarImpulso(); });
}
function impulsoNorm(s) {
  return String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\s+/g, ' ').trim();
}
// Busca si este prospecto ya participó de verdad (dato real del
// servidor), por correo exacto o nombre igual normalizado.
function impulsoParticipacionDe(p) {
  if (!IMPULSO_PARTICIPANTES) return null;
  var correoN = impulsoNorm((p.correo || '').replace(/\s+/g, ''));
  var nombreN = impulsoNorm(p.nombre);
  for (var i = 0; i < IMPULSO_PARTICIPANTES.length; i++) {
    var q = IMPULSO_PARTICIPANTES[i];
    if (correoN && q.correoNorm === correoN) return q;
    if (nombreN && q.nombreNorm === nombreN) return q;
  }
  return null;
}
function impulsoFechaCorta(fechaIso) {
  // 'yyyy-MM-dd HH:mm:ss' -> 'dd/mm hh:mm'
  var m = String(fechaIso || '').match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})/);
  if (!m) return '';
  return m[3] + '/' + m[2] + ' ' + m[4] + ':' + m[5];
}
function impulsoExportarCsv(filas) {
  var enc = ['Nombre', 'Telefono', 'Enviado', 'FechaEnvio', 'Participo', 'Monto', 'Codigo'];
  var lineas = [enc.join(',')];
  filas.forEach(function (f) {
    lineas.push([
      '"' + String(f.nombre || '').replace(/"/g, '""') + '"', f.telefono,
      f.enviado ? 'SI' : 'NO', f.fechaEnvio || '',
      f.participacion ? 'SI' : 'NO', f.participacion ? f.participacion.monto : '',
      f.participacion ? f.participacion.codigo : ''
    ].join(','));
  });
  var blob = new Blob(['\ufeff' + lineas.join('\n')], { type: 'text/csv;charset=utf-8' });
  var a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'impulso-cessum-' + new Date().toISOString().slice(0, 10) + '.csv';
  a.click();
}
function pintarImpulso() {
  var c = document.getElementById('v-impulso');
  if (!DATOS || !DATOS.prospectos) { c.innerHTML = '<p style="color:#8a7f70">Cargando prospectos…</p>'; return; }
  if (IMPULSO_PARTICIPANTES === null) { impulsoCargarParticipantes(); c.innerHTML = '<p style="color:#8a7f70">Cargando…</p>'; return; }
  var lista = DATOS.prospectos.filter(function (p) {
    return progNorm(p.programa) === 'Maestría en Educación' && p.etapa !== 'Inscrito';
  });
  var conTel = lista.filter(function (p) { return waTel(p); });
  // Se arma el estado de cada uno UNA vez (enviado, fecha, participación real).
  var filas = conTel.map(function (p) {
    var tel = waTel(p);
    return {
      p: p, nombre: p.nombre, telefono: tel, fila: p.fila,
      enviado: impulsoYaEnviado(tel),
      fechaEnvio: impulsoFechaEnvio(tel),
      participacion: impulsoParticipacionDe(p)
    };
  });
  var totalEnviados = filas.filter(function (f) { return f.enviado; }).length;
  var totalParticiparon = filas.filter(function (f) { return f.participacion; }).length;
  var totalPendientes = filas.length - totalEnviados;
  var pct = filas.length ? Math.round(totalEnviados * 100 / filas.length) : 0;

  // Filtro activo + búsqueda.
  var vista = filas.filter(function (f) {
    if (IMPULSO_FILTRO === 'pendientes' && f.enviado) return false;
    if (IMPULSO_FILTRO === 'enviados_sin_participar' && (!f.enviado || f.participacion)) return false;
    if (IMPULSO_FILTRO === 'participaron' && !f.participacion) return false;
    if (IMPULSO_BUSQUEDA && impulsoNorm(f.nombre).indexOf(impulsoNorm(IMPULSO_BUSQUEDA)) < 0) return false;
    return true;
  });

  var img = impulsoImagenGuardada();
  function kpi(valor, etiqueta, color) {
    return '<div style="background:#fff;border:1px solid var(--gris);border-radius:10px;padding:10px 16px;min-width:100px">' +
      '<b style="display:block;font-family:var(--display);font-size:24px;color:' + (color || 'var(--vino)') + '">' + valor + '</b>' +
      '<span style="font-size:11px;color:var(--gris-txt)">' + etiqueta + '</span></div>';
  }
  function filtroBtn(valor, texto) {
    var on = IMPULSO_FILTRO === valor;
    return '<button type="button" data-impulso-filtro="' + valor + '" style="padding:6px 12px;font-size:12.5px;' +
      'border-radius:20px;border:1.5px solid ' + (on ? 'var(--rojo)' : 'var(--gris)') + ';' +
      'background:' + (on ? 'var(--rojo)' : '#fff') + ';color:' + (on ? '#fff' : 'var(--tinta)') + '">' + texto + '</button>';
  }

  var h = '<div style="max-width:980px">' +
    '<div style="display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:10px;margin-bottom:14px">' +
    '<h2 style="font-family:var(--display);color:var(--vino);margin:0">Impulso CESSUM · Maestría en Educación</h2>' +
    '<button type="button" id="impulsoExportar" style="padding:7px 14px;font-size:12.5px">⬇️ Exportar CSV</button>' +
    '</div>' +

    '<div style="display:flex;gap:10px;flex-wrap:wrap;margin-bottom:16px">' +
    kpi(filas.length, 'Prospectos con teléfono') +
    kpi(totalEnviados, 'Enviados') +
    kpi(totalPendientes, 'Pendientes', 'var(--oro)') +
    kpi(pct + '%', 'Avance') +
    kpi(totalParticiparon, 'Ya participaron', 'var(--verde,#1E7B34)') +
    '</div>' +

    '<div style="background:#fff;border:1px solid var(--gris);border-radius:12px;padding:14px 16px;margin-bottom:18px">' +
    '<b style="font-size:13.5px;color:var(--tinta)">Texto de la campaña</b>' +
    '<p style="font-size:12px;color:var(--gris-txt);margin:4px 0 10px">' +
      'Este es el mensaje que se usa para todos, tal cual. ' +
      'Selecciónelo y cópielo de aquí si lo prefiere, en vez del botón "Copiar texto" de cada fila.</p>' +
    '<textarea readonly id="impulsoTextoBase" rows="9" ' +
    'style="width:100%;font:inherit;font-size:12.5px;padding:10px;border:1px solid var(--gris);' +
    'border-radius:8px;resize:vertical;background:#faf9f7;color:var(--tinta)">' +
    esc(impulsoMensaje('')) + '</textarea>' +
    '<div style="margin-top:8px">' +
    '<button type="button" id="impulsoCopiarTextoBase" style="padding:7px 14px;font-size:12.5px">\u{1F4CB} Copiar este texto</button>' +
    '</div>' +
    '</div>' +

    '<div style="background:#fff;border:1px solid var(--gris);border-radius:12px;padding:14px 16px;margin-bottom:18px">' +
    '<b style="font-size:13.5px;color:var(--tinta)">Imagen de la campaña</b>' +
    '<p style="font-size:12px;color:var(--gris-txt);margin:4px 0 10px">' +
      'WhatsApp no permite abrir el chat de un contacto específico CON una imagen ya adjunta — por eso ' +
      'el botón "Enviar por WhatsApp" siempre abre el chat del número correcto con el texto listo. Si ' +
      'cargas la imagen aquí, la tienes a la mano para pegarla o copiarla en ese mismo chat antes de enviar. ' +
      'Solo se guarda en este navegador.</p>' +
    (img
      ? '<div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap">' +
        '<img src="' + img + '" alt="Imagen de la campaña" style="max-width:160px;max-height:160px;border-radius:8px;border:1px solid var(--gris)">' +
        '<a href="' + img + '" download="impulso-cessum.jpg" style="font-size:12.5px">Descargar</a>' +
        '<button type="button" id="impulsoCopiarImg" style="padding:6px 12px;font-size:12.5px">\u{1F4CB} Copiar imagen</button>' +
        '<button type="button" id="impulsoQuitarImg" style="padding:6px 12px;font-size:12.5px">Quitar imagen</button>' +
        '</div>'
      : '<label for="impulsoImgInput" style="display:inline-block;padding:10px 16px;border:1.5px dashed var(--gris-txt);' +
        'border-radius:8px;font-size:13px;color:var(--tinta);cursor:pointer;background:#faf9f7">' +
        '\u{1F4CE} Elegir imagen de la campaña' +
        '<input type="file" id="impulsoImgInput" accept="image/*" style="display:block;margin-top:8px;font-size:12.5px">' +
        '</label>') +
    '</div>' +

    '<div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-bottom:12px">' +
    '<input type="search" id="impulsoBuscar" placeholder="Buscar por nombre…" value="' + esc(IMPULSO_BUSQUEDA) + '" ' +
    'style="padding:7px 10px;font-size:13px;border:1px solid var(--gris);border-radius:8px;min-width:200px">' +
    filtroBtn('todos', 'Todos (' + filas.length + ')') +
    filtroBtn('pendientes', 'Pendientes (' + totalPendientes + ')') +
    filtroBtn('enviados_sin_participar', 'Enviados sin participar') +
    filtroBtn('participaron', 'Ya participaron (' + totalParticiparon + ')') +
    '</div>';

  if (!vista.length) {
    h += '<p style="color:var(--gris-txt)">Nadie coincide con este filtro/búsqueda.</p>';
  } else {
    h += '<table style="width:100%;border-collapse:collapse;font-size:13.5px">' +
      '<tr style="text-align:left;color:var(--gris-txt);border-bottom:1px solid var(--gris)">' +
      '<th style="padding:8px 10px">Nombre</th><th style="padding:8px 10px">Teléfono</th>' +
      '<th style="padding:8px 10px">Estado</th><th style="padding:8px 10px"></th></tr>';
    vista.forEach(function (f) {
      var estadoTxt = f.participacion
        ? ('<span style="color:var(--verde,#1E7B34);font-weight:700">✅ Participó</span> · $' + f.participacion.monto + ' · ' + esc(f.participacion.codigo))
        : (f.enviado
          ? ('<span style="color:var(--oro)">✓ Enviado' + (f.fechaEnvio ? ' · ' + esc(f.fechaEnvio) : '') + '</span>')
          : '<span style="color:var(--gris-txt)">Pendiente</span>');
      h += '<tr style="border-bottom:1px solid var(--gris)">' +
        '<td style="padding:8px 10px">' + esc(f.nombre || '(sin nombre)') + '</td>' +
        '<td style="padding:8px 10px">' + esc(f.telefono) + '</td>' +
        '<td style="padding:8px 10px;font-size:12px">' + estadoTxt + '</td>' +
        '<td style="padding:8px 10px;text-align:right;white-space:nowrap">' +
        '<button type="button" data-impulso-copiar="' + esc(String(f.fila)) + '" ' +
        'style="padding:6px 10px;font-size:12.5px;margin-right:6px">\u{1F4CB} Texto</button>' +
        '<button type="button" class="pri" data-impulso-fila="' + esc(String(f.fila)) + '" ' +
        'style="padding:6px 14px;font-size:12.5px">' + (f.enviado ? 'Enviar otra vez' : 'Enviar por WhatsApp') + '</button>' +
        '</td></tr>';
    });
    h += '</table>';
  }
  h += '</div>';
  c.innerHTML = h;

  document.getElementById('impulsoExportar').onclick = function () { impulsoExportarCsv(vista); };
  var buscarInput = document.getElementById('impulsoBuscar');
  if (buscarInput) {
    buscarInput.oninput = function () { IMPULSO_BUSQUEDA = buscarInput.value; pintarImpulso(); };
    // El foco se pierde al repintar; se regresa si se estaba escribiendo.
    if (document.activeElement !== buscarInput && IMPULSO_BUSQUEDA) {
      buscarInput.focus();
      buscarInput.selectionStart = buscarInput.selectionEnd = buscarInput.value.length;
    }
  }
  Array.prototype.forEach.call(c.querySelectorAll('[data-impulso-filtro]'), function (btn) {
    btn.onclick = function () { IMPULSO_FILTRO = btn.getAttribute('data-impulso-filtro'); pintarImpulso(); };
  });
  var imgInput = document.getElementById('impulsoImgInput');
  if (imgInput) {
    imgInput.onchange = function () {
      var f = imgInput.files && imgInput.files[0];
      if (!f) return;
      var fr = new FileReader();
      fr.onload = function () { impulsoGuardarImagen(fr.result); pintarImpulso(); };
      fr.readAsDataURL(f);
    };
  }
  var quitarBtn = document.getElementById('impulsoQuitarImg');
  if (quitarBtn) quitarBtn.onclick = impulsoQuitarImagen;
  var copiarBtn = document.getElementById('impulsoCopiarImg');
  if (copiarBtn) copiarBtn.onclick = function () { impulsoCopiarImagen(copiarBtn); };
  var copiarTextoBaseBtn = document.getElementById('impulsoCopiarTextoBase');
  if (copiarTextoBaseBtn) {
    copiarTextoBaseBtn.onclick = function () {
      var area = document.getElementById('impulsoTextoBase');
      var hacerSeleccion = function () { area.focus(); area.select(); };
      var listo = function () {
        var orig = copiarTextoBaseBtn.textContent;
        copiarTextoBaseBtn.textContent = '✓ Copiado';
        setTimeout(function () { copiarTextoBaseBtn.textContent = orig; }, 1800);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(area.value).then(listo).catch(hacerSeleccion);
      } else {
        hacerSeleccion();
      }
    };
  }
  Array.prototype.forEach.call(c.querySelectorAll('[data-impulso-fila]'), function (btn) {
    btn.onclick = function () {
      var fila = btn.getAttribute('data-impulso-fila');
      var p = waProsp(fila);
      if (!p || !waTel(p)) { alert('Este prospecto ya no tiene teléfono.'); return; }
      impulsoEnviarA(p);
    };
  });
  // Copiar el texto del mensaje al portapapeles — alternativa confiable
  // si el prellenado automático de WhatsApp no aparece en su navegador
  // (a veces WhatsApp Web no respeta el texto si ya había un chat
  // abierto con esa persona).
  Array.prototype.forEach.call(c.querySelectorAll('[data-impulso-copiar]'), function (btn) {
    btn.onclick = function () {
      var fila = btn.getAttribute('data-impulso-copiar');
      var p = waProsp(fila);
      if (!p) return;
      var texto = impulsoMensaje(p.nombre);
      var listo = function () {
        var orig = btn.textContent;
        btn.textContent = '✓ Copiado';
        setTimeout(function () { btn.textContent = orig; }, 1800);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(texto).then(listo).catch(function () {
          alert('No se pudo copiar automáticamente. Seleccione el mensaje manualmente.');
        });
      } else {
        alert('Este navegador no permite copiar automáticamente.');
      }
    };
  });
}


/* ══════════════════════════════════════════════════════════════════════
   (28-sep) CIERRE 26-4 · TABLERO DE LA SEMANA DE CIERRE
   ──────────────────────────────────────────────────────────────────────
   Una pantalla para la semana en que se decide la generación: cuenta
   regresiva, cuántos van, cuántos harían falta, y sobre todo a QUIÉN
   escribirle hoy, con el mensaje ya armado y un clic para abrir WhatsApp.
   Las cifras salen de las inscripciones reales (no del panel), porque solo
   3 de 17 inscritos habían pasado por él.
   La IA solo LEE las cifras de esta pantalla: no puede afirmar nada más, y
   no envía nada. Lo que se manda a una persona lo manda una persona.
   ══════════════════════════════════════════════════════════════════════ */
var CIERRE = null, CIERRE_HECHOS = {}, CIERRE_FECHA = Date.UTC(2026, 9, 4);   // domingo 4 de octubre de 2026

function cierreDiasLocal() {
  var h = new Date();
  return Math.round((CIERRE_FECHA - Date.UTC(h.getFullYear(), h.getMonth(), h.getDate())) / 86400000);
}
function cierreEtiqueta() {
  var b = document.querySelector('.pest button[data-v="cierre"]');
  if (!b) return;
  var d = cierreDiasLocal();
  b.textContent = (d >= 0 && d <= 10) ? ('Cierre 26-4 · ' + (d === 0 ? 'hoy' : d + (d === 1 ? ' día' : ' días'))) : 'Cierre 26-4';
}
cierreEtiqueta();

function cierreWa(tel, msg) {
  return 'https://wa.me/52' + String(tel || '').replace(/\D/g, '').slice(-10) + '?text=' + encodeURIComponent(msg || '');
}
function cierreKpi(n, t) { return '<div class="ci-kpi"><b>' + esc(String(n)) + '</b><span>' + esc(t) + '</span></div>'; }
function cierreEstado(b) { return b ? '<b class="ci-si">Activo</b>' : '<b class="ci-no">Apagado</b>'; }

function cierreFilaHtml(r) {
  var nombre = r.sinNombre ? ('Sin nombre · ' + r.tel) : r.nombre;
  var h = '<div class="ci-fila' + (CIERRE_HECHOS[r.fila] ? ' hecho' : '') + '" id="cif-' + esc(String(r.fila)) + '">';
  h += '<div class="ci-fn"><b>' + esc(nombre) + '</b>';
  h += '<span>' + esc(r.programa || 'Programa sin definir') + (r.dudoso ? ' · ¿es de Maestría en Educación?' : '') +
       ' · ' + esc(r.etapa) + ' · ' + (r.dias === null || r.dias === undefined ? '?' : esc(String(r.dias))) + ' d sin moverse</span>';
  if (r.porQue) h += '<em>' + esc(r.porQue) + '</em>';
  if (r.sinNombre) h += '<i>falta nombre</i>';
  if (!r.correo) h += '<i>falta correo</i>';
  h += '</div><div class="ci-acc">';
  h += '<a class="ci-b pri" target="_blank" rel="noopener" data-acc="wa" data-fila="' + esc(String(r.fila)) + '" href="' + esc(cierreWa(r.tel, r.mensaje)) + '">WhatsApp con IA</a>';
  h += '<button type="button" class="ci-b" data-acc="ia" data-fila="' + esc(String(r.fila)) + '">Redactar con IA</button>';
  h += '<button type="button" class="ci-b" data-acc="reg" data-fila="' + esc(String(r.fila)) + '">Ya se lo envié</button>';
  h += '</div><details><summary>Ver el mensaje</summary><p>' + esc(r.mensaje) + '</p></details>';
  h += '<div id="ciia-' + esc(String(r.fila)) + '"></div></div>';
  return h;
}

function cierreHtml(d) {
  var ins = d.inscritos, cz = d.cierre, emb = d.embudo, aut = d.automatizacion || {}, h = '';
  var dias = cz.dias;
  var cuenta = dias < 0 ? 'La inscripción ya cerró' : dias === 0 ? 'Hoy cierra la inscripción' :
    dias === 1 ? 'Mañana cierra la inscripción' : 'Faltan ' + dias + ' días para el cierre';
  var pct = ins.referencia ? Math.min(100, Math.round(ins.total * 100 / ins.referencia)) : 0;

  (d.avisos || []).forEach(function (a) { h += '<div class="ci-aviso">' + esc(a) + '</div>'; });

  h += '<div class="ci-top"><div class="ci-cuenta"><span class="ci-rot">' + esc(cz.etiqueta) + '</span><h2>' + esc(cuenta) + '</h2>' +
    '<p>Cierra el ' + esc(cz.cierre) + ' · la generación inicia el ' + esc(cz.inicio) + '</p></div>' +
    '<div class="ci-kpis">' + cierreKpi(ins.total, 'inscritos hasta hoy') + cierreKpi(ins.ultimos7, 'en los últimos 7 días') +
    cierreKpi(ins.ritmoDia, 'por día (últimos 14)') + cierreKpi('~' + ins.proyeccion, 'proyección lineal') + '</div></div>';

  var frase;
  if (ins.falta <= 0) frase = 'Ya se alcanzó la referencia.';
  else if (dias > 0) frase = 'Para llegar a la referencia harían falta ' + ins.necesarioPorDia + ' por día; al ritmo de los últimos 14 días la proyección es de ' + ins.proyeccion + '.';
  else frase = 'Faltaron ' + ins.falta + ' para la referencia.';
  h += '<div class="ci-prog"><div class="ci-bar"><i style="width:' + pct + '%"></i></div><p>' + esc(String(ins.total)) + ' de ' + esc(String(ins.referencia)) +
    ' de referencia (' + pct + ' %). ' + esc(frase) + ' <span class="ci-peq">La referencia (~60 por periodo) es la base histórica de la Maestría en Educación; la proyección es lineal, no una promesa.</span></p></div>';

  if (ins.sinRegistroEnPanel > 0) {
    h += '<div class="ci-aviso ci-ok"><b>' + esc(String(ins.sinRegistroEnPanel)) + ' inscrito(s) no están en el panel.</b> Sin ellos, el cruce y las métricas del cierre no cuentan toda la historia. ' +
      'Se dan de alta solos cada hora cuando el ciclo automático está activo; también puede hacerlo ahora. <button type="button" class="ci-b" data-acc="alta">Ver y dar de alta</button></div>';
  }

  h += '<div class="ci-caja"><div class="ci-cab"><h3>Lectura del día</h3><button type="button" class="ci-b" data-acc="actualizar">Actualizar tablero</button></div><div id="ciLectCuerpo"><p class="vacio">La IA está leyendo las cifras…</p></div></div>';

  h += '<div class="ci-caja"><div class="ci-cab"><h3>A quién escribirle hoy</h3><span>' + esc(String(d.colaTotal)) + ' en la cola · se muestran los ' + esc(String(d.cola.length)) + ' de mayor prioridad</span></div>';
  if (!d.cola.length) h += '<p class="vacio">No hay nadie en la cola.</p>';
  d.cola.forEach(function (r) { h += cierreFilaHtml(r); });
  h += '<p class="ci-peq">Los mensajes usan solo los datos oficiales de la convocatoria. El botón abre WhatsApp con el texto escrito: se envía a mano, desde el teléfono de Admisiones.</p></div>';

  h += '<div class="ci-grid">';
  h += '<div class="ci-caja"><h3>Cómo está el embudo</h3>' +
    '<div class="ci-stat"><span>Prospectos activos de la Maestría</span><b>' + esc(String(emb.activos)) + '</b></div>' +
    '<div class="ci-stat"><span>Sin ningún contacto (más de 24 h)</span><b>' + esc(String(emb.sinContacto24h)) + '</b></div>' +
    '<div class="ci-stat"><span>En riesgo por días sin respuesta</span><b>' + esc(String(emb.enRiesgo)) + '</b></div>' +
    '<div class="ci-stat"><span>Sin nombre registrado</span><b>' + esc(String(emb.sinNombre)) + '</b></div>' +
    '<div class="ci-stat"><span>Sin correo registrado</span><b>' + esc(String(emb.sinCorreo)) + '</b></div></div>';

  var can = d.canales || {}, cn = Object.keys(can).sort(function (a, b) { return can[b] - can[a]; }), totC = 0;
  cn.forEach(function (k) { totC += can[k]; });
  h += '<div class="ci-caja"><h3>Por dónde llegaron los inscritos</h3>';
  if (!cn.length) h += '<p class="vacio">Aún no hay datos.</p>';
  cn.forEach(function (k) {
    var p = totC ? Math.round(can[k] * 100 / totC) : 0;
    h += '<div class="ci-can"><div><span>' + esc(k) + '</span><b>' + esc(String(can[k])) + ' (' + p + ' %)</b></div><i style="width:' + p + '%"></i></div>';
  });
  h += '<p class="ci-peq">Es lo que el propio inscrito contestó en el formulario.</p></div>';

  var serie = d.serie || [], mx = 1;
  serie.forEach(function (s) { if (s.n > mx) mx = s.n; });
  h += '<div class="ci-caja"><h3>Inscripciones por día · últimos 14</h3><div class="ci-serie">';
  serie.forEach(function (s, i) {
    h += '<div' + (i === serie.length - 1 ? ' class="hoy"' : '') + ' title="' + esc(s.f) + ': ' + esc(String(s.n)) + '" style="height:' + Math.round(s.n * 100 / mx) + '%"></div>';
  });
  h += '</div><div class="ci-serie-e">';
  serie.forEach(function (s) { h += '<span>' + esc(String(s.f).slice(8, 10)) + '</span>'; });
  h += '</div></div></div>';

  var t = aut.disparadores || {}, u = aut.ultimoCiclo, hace = '';
  if (u && u.t) { var mn = Math.round((Date.now() - u.t) / 60000); hace = 'Último ciclo: hace ' + (mn < 90 ? mn + ' min' : Math.round(mn / 60) + ' h') + ' · ' + (u.altas || 0) + ' alta(s) · ' + (u.marcados || 0) + ' marcado(s) como inscrito' + (u.ok ? '' : ' · <b class="ci-no">con error: ' + esc(u.error || '') + '</b>'); }
  h += '<div class="ci-grid"><div class="ci-caja"><h3>Automatizaciones</h3><ul class="ci-lista">' +
    '<li>' + cierreEstado(t.ciclo) + ' <b>Ciclo cada hora:</b> da de alta a los inscritos que no están en el panel y los marca como inscritos. No escribe a nadie.</li>' +
    '<li>' + cierreEstado(t.resumen) + ' <b>Resumen diario</b> a las 8:00 por correo a contacto@cessum.mx, con la cuenta regresiva del cierre. Solo llega a su equipo.</li>' +
    '<li>' + cierreEstado(t.secuencia) + ' <b>Secuencia de correos a prospectos.</b> Esta sí escribe a personas ajenas, por eso no se activa desde aquí: primero se ve a quién le llegaría.</li></ul>' +
    (hace ? '<p class="ci-peq">' + hace + '</p>' : '') +
    '<div class="ci-acc">' + ((t.ciclo && t.resumen) ? '<button type="button" class="ci-b" data-acc="auto-off">Desactivar ciclo y resumen</button>' : '<button type="button" class="ci-b pri" data-acc="auto-on">Activar ciclo y resumen</button>') +
    '<button type="button" class="ci-b" data-acc="sec">Ver a quién le llegaría la secuencia</button></div><div class="ci-res" id="ciAutoRes"></div></div>';

  h += '<div class="ci-caja ci-form"><h3>Seguridad</h3><p class="ci-peq">Cambie la contraseña del panel. Al cambiarla se cierran las demás sesiones abiertas. Mínimo 12 caracteres.</p>' +
    '<input type="password" id="ciClaveAct" placeholder="Contraseña actual" autocomplete="current-password">' +
    '<input type="password" id="ciClaveNue" placeholder="Contraseña nueva" autocomplete="new-password">' +
    '<input type="password" id="ciClaveRep" placeholder="Repita la nueva" autocomplete="new-password">' +
    '<button type="button" class="ci-b pri" data-acc="clave">Cambiar contraseña</button><div class="ci-res" id="ciClaveRes"></div></div></div>';
  return h;
}

function pintarCierre(fresco) {
  var c = document.getElementById('v-cierre');
  if (!CIERRE || fresco) {
    c.innerHTML = '<p class="vacio">Armando el tablero de cierre… la primera vez puede tardar unos segundos.</p>';
    api('cierre_datos', { pase: PASE, fresco: fresco ? '1' : '' }).then(function (d) {
      if (d && d.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
      if (!d || !d.ok) { c.innerHTML = '<p class="vacio">No se pudo armar el tablero: ' + esc((d && d.error) || 'sin respuesta') + '</p>'; return; }
      CIERRE = d;
      pintarCierre(false);
      cierreLectura(false);
    });
    return;
  }
  c.innerHTML = cierreHtml(CIERRE);
  c.onclick = cierreClic;
  cierreLectura(false);
}

function cierreLectura(forzar) {
  var box = document.getElementById('ciLectCuerpo');
  if (!box) return;
  box.innerHTML = '<p class="vacio">La IA está leyendo las cifras…</p>';
  api('cierre_lectura', { pase: PASE, forzar: forzar ? '1' : '' }).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    var b2 = document.getElementById('ciLectCuerpo');
    if (!b2) return;
    if (!r || !r.ok) { b2.innerHTML = '<p class="ci-err">' + esc((r && r.error) || 'No se pudo generar la lectura.') + '</p>'; return; }
    var h = '<p class="ci-lect">' + esc(r.lectura) + '</p>';
    if (r.acciones && r.acciones.length) h += '<ol class="ci-acciones">' + r.acciones.map(function (a) { return '<li>' + esc(a) + '</li>'; }).join('') + '</ol>';
    if (r.riesgo) h += '<p class="ci-riesgo"><b>Lo que más puede salir mal:</b> ' + esc(r.riesgo) + '</p>';
    h += '<p class="ci-peq">' + (r.generado ? 'Generado el ' + esc(r.generado) + '. ' : '') + 'La IA solo usa las cifras de este tablero y no puede afirmar nada más. <button type="button" class="ci-b" data-acc="lectura">Volver a leer</button></p>';
    b2.innerHTML = h;
  });
}

function cierreClic(ev) {
  var b = ev.target.closest ? ev.target.closest('[data-acc]') : null;
  if (!b) return;
  var acc = b.getAttribute('data-acc'), fila = Number(b.getAttribute('data-fila') || 0);
  if (acc === 'wa') { var pw = waProsp(fila); if (pw) { ev.preventDefault(); waAbrirIA(pw); } return; }   // (28-sep) con IA; sin la ficha cargada, el enlace con la plantilla sigue funcionando
  if (acc === 'ia') { var pi = waProsp(fila); if (pi) return waAbrirIA(pi, true); return cierreRedactar(fila, b); }
  if (acc === 'reg') return cierreRegistrar(fila, b);
  if (acc === 'lectura') return cierreLectura(true);
  if (acc === 'actualizar') { CIERRE = null; return pintarCierre(true); }
  if (acc === 'alta') return cierreAlta();
  if (acc === 'auto-on') return cierreAutomatizar('automatizar_instalar');
  if (acc === 'auto-off') return cierreAutomatizar('automatizar_quitar');
  if (acc === 'sec') return cierreSecuencia();
  if (acc === 'clave') return cierreClave();
}

function cierreFilaDe(fila) {
  var r = null;
  ((CIERRE && CIERRE.cola) || []).forEach(function (x) { if (Number(x.fila) === Number(fila)) r = x; });
  return r;
}
function cierreRedactar(fila, btn) {
  var box = document.getElementById('ciia-' + fila), r0 = cierreFilaDe(fila);
  if (!box || !r0) return;
  btn.disabled = true; btn.textContent = 'Redactando…';
  api('redactar', { pase: PASE, fila: String(fila),
    indicacion: 'Semana de cierre: la inscripción a la Maestría en Educación cierra el domingo 4 de octubre y la generación inicia el lunes 5. Menciónalo como fecha límite, con naturalidad y sin presionar.' })
    .then(function (r) {
      btn.disabled = false; btn.textContent = 'Redactar con IA';
      if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
      if (!r || !r.ok) { box.innerHTML = '<p class="ci-err">' + esc((r && r.error) || 'No se pudo redactar.') + '</p>'; return; }
      box.innerHTML = '<textarea class="ci-ta" id="ciTa-' + esc(String(fila)) + '">' + esc(r.mensaje || '') + '</textarea>' +
        '<div class="ci-acc"><a class="ci-b pri" target="_blank" rel="noopener" id="ciTaWa-' + esc(String(fila)) + '" href="' + esc(cierreWa(r0.tel, r.mensaje || '')) + '">Abrir WhatsApp con este texto</a>' +
        '<span class="ci-peq">Es un borrador: léalo y ajústelo. Lo que se envía es lo que quede en la caja.</span></div>';
      var ta = document.getElementById('ciTa-' + fila), wa = document.getElementById('ciTaWa-' + fila);
      ta.addEventListener('input', function () { wa.href = cierreWa(r0.tel, ta.value); });
    });
}
function cierreRegistrar(fila, btn) {
  btn.disabled = true;
  api('whatsapp', { pase: PASE, fila: String(fila) }).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) { btn.disabled = false; alert((r && r.error) || 'No se pudo registrar.'); return; }
    CIERRE_HECHOS[fila] = true;
    var f = document.getElementById('cif-' + fila);
    if (f) f.className += ' hecho';
    btn.textContent = 'Registrado ✓';
  });
}
function cierreAlta() {
  api('alta_inscritos', { pase: PASE, prueba: '1' }).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) { alert((r && r.error) || 'No se pudo revisar.'); return; }
    if (!r.faltaban) { alert('Todos los inscritos ya están en el panel.'); return; }
    var lista = (r.quienes || []).map(function (q) { return '• ' + (q.nombre || q.tel || q.correo); }).join('\n');
    if (!confirm('Se darán de alta ' + r.faltaban + ' inscrito(s) que no están en el panel:\n\n' + lista +
      '\n\nQuedarán como «Inscrito», con el canal por el que dijeron haberse enterado. No se les escribe. ¿Continuar?')) return;
    api('alta_inscritos', { pase: PASE }).then(function (r2) {
      if (!r2 || !r2.ok) { alert((r2 && r2.error) || 'No se pudo dar de alta.'); return; }
      alert('Listo: ' + (r2.creados || 0) + ' alta(s)' + (r2.marcados ? ' y ' + r2.marcados + ' marcado(s) como inscrito' : '') + '.' +
        ((r2.fallos && r2.fallos.length) ? '\n\nNo se pudieron dar de alta:\n' + r2.fallos.join('\n') : ''));
      CIERRE = null; pintarCierre(true);
    });
  });
}
function cierreAutomatizar(accion) {
  var res = document.getElementById('ciAutoRes');
  res.textContent = 'Un momento…';
  api(accion, { pase: PASE }).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) { res.innerHTML = '<span class="ci-no">' + esc((r && r.error) || 'No se pudo.') + '</span>'; return; }
    CIERRE = null; pintarCierre(true);
  });
}
function cierreSecuencia() {
  var res = document.getElementById('ciAutoRes');
  res.textContent = 'Calculando a quién le llegaría…';
  api('secuencia_vista', { pase: PASE }).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) { res.innerHTML = '<span class="ci-no">' + esc((r && r.error) || 'No se pudo calcular.') + '</span>'; return; }
    var h = '<b>Vista previa: no se envió nada.</b><br>Saldrían <b>' + esc(String(r.saldrian)) + '</b> correo(s) a prospectos con correo válido que no pidieron baja.';
    (r.detalle || []).slice(0, 10).forEach(function (x) {
      h += '<br>· ' + esc(x.nombre || '(sin nombre)') + ' — ' + esc(x.programa || '') + ' — paso ' + esc(String(x.paso)) + ' («' + esc(x.asunto || '') + '»)';
    });
    if ((r.detalle || []).length < r.saldrian) h += '<br>… y ' + (r.saldrian - (r.detalle || []).length) + ' más.';
    h += '<br><span class="ci-peq">La secuencia ' + (r.instalada ? 'YA está instalada: se envía sola cada día.' : 'no está instalada. Para activarla, en el editor de Apps Script: instalarSecuencia().') + '</span>';
    res.innerHTML = h;
  });
}
function cierreClave() {
  var a = document.getElementById('ciClaveAct').value, n = document.getElementById('ciClaveNue').value, r2 = document.getElementById('ciClaveRep').value;
  var res = document.getElementById('ciClaveRes');
  if (n !== r2) { res.innerHTML = '<span class="ci-no">La contraseña nueva y su repetición no coinciden.</span>'; return; }
  if (n.length < 12) { res.innerHTML = '<span class="ci-no">La nueva debe tener al menos 12 caracteres.</span>'; return; }
  res.textContent = 'Cambiando…';
  api('cambiar_clave', { pase: PASE, actual: a, nueva: n }).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) { res.innerHTML = '<span class="ci-no">' + esc((r && r.error) || 'No se pudo cambiar.') + '</span>'; return; }
    ['ciClaveAct', 'ciClaveNue', 'ciClaveRep'].forEach(function (id) { document.getElementById(id).value = ''; });
    res.innerHTML = '<span class="ci-si"><b>Contraseña cambiada.</b> Se cerraron ' + esc(String(r.sesionesCerradas || 0)) + ' sesión(es) más. Use la nueva la próxima vez que entre.</span>';
  });
}

/* ── Inscripciones: ahora la lista se dibuja aquí, con los datos que llegan por el pase ──
   Antes era un iframe del Guardián que cargaba con la clave del Vicerrector escrita en
   este archivo. Revisar expedientes y dar de alta matrículas sigue en la app. */
var INSC_LISTA = null;
function cargarFeed(fresco) { return api('insc_feed', { pase: PASE, fresco: fresco ? '1' : '' }); }
function pintarInscripciones(forzar) {
  var caja = document.getElementById('inscMarco');
  caja.style.overflow = 'auto';
  if (INSC_LISTA && !forzar) { inscDibujar(''); return; }
  caja.innerHTML = '<div class="cargando">Leyendo los formularios…</div>';
  cargarFeed(!!forzar).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) { caja.innerHTML = '<div class="cargando">No se pudo leer la lista de inscripciones: ' + esc((r && r.error) || 'sin respuesta') + '</div>'; return; }
    INSC_LISTA = (r.inscripciones || []).slice().sort(function (a, b) { return String(b.f || '').localeCompare(String(a.f || '')); });
    inscDibujar('');
  });
}
function inscDibujar(q) {
  var caja = document.getElementById('inscMarco'), n = String(q || '').toLowerCase().trim();
  var filas = INSC_LISTA.filter(function (x) {
    return !n || [x.n, x.p, x.m, x.c, x.t, x.mat, x.o, x.s].join(' ').toLowerCase().indexOf(n) >= 0;
  });
  var porProg = {};
  INSC_LISTA.forEach(function (x) { var k = x.p || '(sin programa)'; porProg[k] = (porProg[k] || 0) + 1; });
  var resumen = Object.keys(porProg).sort(function (a, b) { return porProg[b] - porProg[a]; }).map(function (k) { return esc(k) + ': <b>' + porProg[k] + '</b>'; }).join(' · ');
  var h = '<div style="padding:14px 16px;font-size:13px;line-height:1.6"><b>' + INSC_LISTA.length + ' inscripciones</b> · ' + resumen + '</div>' +
    '<div style="padding:0 16px 10px"><input id="inscBuscar" type="search" value="' + esc(q || '') + '" placeholder="Buscar por nombre, programa, correo, teléfono, matrícula…" style="width:100%;max-width:460px;padding:9px 12px;border:1px solid #e3d9c7;border-radius:8px;font:inherit;font-size:13px"></div>' +
    '<div style="overflow:auto"><table style="width:100%;border-collapse:collapse;font-size:12.5px"><thead><tr style="text-align:left;background:#faf6ee">' +
    ['Fecha', 'Nombre', 'Programa', 'Modalidad', 'Se enteró por', 'Situación', 'Matrícula', 'Falta'].map(function (t) { return '<th style="padding:8px 10px;border-bottom:1px solid #e3d9c7;white-space:nowrap">' + t + '</th>'; }).join('') + '</tr></thead><tbody>';
  filas.forEach(function (x) {
    var celdas = [x.f, x.n || '(sin nombre)', x.p, x.m, x.o, x.s, x.mat, (x.falta || []).join(', ')];
    h += '<tr>' + celdas.map(function (v) { return '<td style="padding:7px 10px;border-bottom:1px solid #f0ebe3;vertical-align:top">' + esc(String(v == null ? '' : v)) + '</td>'; }).join('') + '</tr>';
  });
  if (!filas.length) h += '<tr><td colspan="8" style="padding:24px;text-align:center;color:#8a8080">Nada coincide con la búsqueda.</td></tr>';
  h += '</tbody></table></div>';
  caja.innerHTML = h;
  var inp = document.getElementById('inscBuscar');
  inp.addEventListener('input', function () { var pos = inp.selectionStart; inscDibujar(inp.value); var i2 = document.getElementById('inscBuscar'); i2.focus(); try { i2.setSelectionRange(pos, pos); } catch (e) {} });
}
document.getElementById('inscRecargar').onclick = function () { INSC_LISTA = null; pintarInscripciones(true); };

/* ── Asistente de admisiones: se abre con un token de 6 horas, no con una clave fija ── */
var asistCargado = false, asistHora = 0;
function pintarAsistente() {
  var caja = document.getElementById('asistMarco');
  if (asistCargado && (Date.now() - asistHora) < 5 * 3600000) return;
  asistCargado = false;
  caja.innerHTML = '<div class="cargando">Abriendo el asistente…</div>';
  api('asistente_enlace', { pase: PASE }).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) { caja.innerHTML = '<div class="cargando">No se pudo abrir el asistente: ' + esc((r && r.error) || 'sin respuesta') + '</div>'; return; }
    document.getElementById('asistAbrir').href = r.url;
    var f = document.createElement('iframe');
    f.src = r.url;
    f.onload = function () { var aviso = caja.querySelector('.cargando'); if (aviso) aviso.parentNode.removeChild(aviso); };
    caja.appendChild(f);
    asistCargado = true; asistHora = Date.now();
  });
}

/* ══════════════════════════════════════════════════════════════════════
   (21-sep) INFORME PARA DECIDIR PUBLICIDAD
   ──────────────────────────────────────────────────────────────────────
   La pregunta que tiene que contestar es una: dónde conviene poner el
   dinero. Para eso no basta contar prospectos por canal —un canal puede
   traer muchos que nunca se inscriben—; hace falta saber cuáles de ellos
   SÍ se inscribieron.
   La etapa de cada prospecto no sirve para eso: casi nunca se actualiza y
   diría 0 % en todo. Lo que sí es confiable son los formularios de
   inscripción, que viven en el Guardián. Se traen y se cruzan con los
   prospectos por teléfono y por correo: así cada inscripción queda
   atribuida al canal por el que llegó esa persona.
   El informe se arma aquí mismo y se guarda en PDF con el diálogo de
   impresión del navegador: no depende de ningún servicio externo ni viaja
   a ningún lado con los datos.
   ══════════════════════════════════════════════════════════════════════ */
/* (28-sep) Antes: CONV_URL con la clave del Vicerrector escrita AQUÍ, en un archivo público, y el
   navegador pedía la lista directo al Guardián. Ahora todo pasa por cargarFeed(): el Apps Script de
   Admisiones —que exige contraseña— trae la lista con una clave de solo lectura. */

function ipEsc(t) {
  return String(t == null ? '' : t).replace(/&/g, '&amp;')
    .replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
function ipFecha(dmy) {
  var m = String(dmy || '').match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/);
  if (!m) return null;
  return new Date(Number(m[3]), Number(m[2]) - 1, Number(m[1]));
}
function ipIso(iso) {
  var m = String(iso || '').match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null;
}
function ipTel(t) {
  var d = String(t || '').replace(/\D/g, '');
  return d.length >= 10 ? d.slice(-10) : '';
}
function ipPct(a, b) { return b ? Math.round(a * 1000 / b) / 10 : 0; }
function ipMoney(n) {
  return '$' + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/* El origen llega en formatos mezclados —«WhatsApp», «/preinscripcion ·
   red:facebook | entro por /admisiones», «/campana-… · facebook · …»—. Se
   traduce a canales que sirvan para decidir inversión. Las campañas con
   enlace etiquetado se separan de lo orgánico: son las únicas cuyo
   resultado se puede atribuir a un gasto concreto. */
function canalDe(origen) {
  var o = String(origen || '').toLowerCase();
  if (!o) return 'Sin dato';
  if (o.indexOf('/campana') === 0 || o.indexOf('campana-') >= 0) {
    if (/facebook|instagram|meta/.test(o)) return 'Campaña pagada en Meta';
    if (o.indexOf('google') >= 0) return 'Campaña pagada en Google';
    return 'Campaña (sin plataforma)';
  }
  if (o.indexOf('whatsapp') >= 0) return 'WhatsApp directo';
  if (/chatgpt|perplexity|gemini|copilot|claude/.test(o)) return 'Buscadores con IA';
  if (o.indexOf('google') >= 0) return 'Google (búsqueda)';
  if (/bing|brave|duckduckgo|yahoo|ecosia/.test(o)) return 'Otros buscadores';
  if (o.indexOf('instagram') >= 0) return 'Instagram (orgánico)';
  if (o.indexOf('facebook') >= 0) return 'Facebook (orgánico)';
  if (o.indexOf('referid') >= 0 || o.indexOf('ref:') >= 0) return 'Referidos';
  if (o.indexOf('directo') >= 0) return 'Sitio web (directo)';
  // Un formulario llenado desde una página del sitio, sin más rastro.
  if (o.charAt(0) === '/') return 'Sitio web (directo)';
  return 'Otro';
}
function paginaDe(origen) {
  var m = String(origen || '').match(/entro por (\S+)/i);
  return m ? m[1] : '';
}
function progNorm(p) {
  var t = String(p || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  if (t.indexOf('licenciatura') >= 0) return 'Licenciatura en Pedagogía';
  if (t.indexOf('inclusiva') >= 0) return 'Maestría en Educación Inclusiva';
  if (t.indexOf('psicopedagog') >= 0) return 'Maestría en Psicopedagogía';
  if (t.indexOf('ciencias') >= 0) return 'Doctorado en Ciencias de la Educación';
  if (t.indexOf('investigacion') >= 0 || t.indexOf('enfasis') >= 0)
    return 'Doctorado en Educación con Énfasis en Investigación';
  if (t.indexOf('pedagog') >= 0) return 'Maestría en Pedagogía';
  if (t.indexOf('educacion') >= 0) return 'Maestría en Educación';
  if (t.indexOf('general') >= 0) return 'Preguntó en general';
  return p ? String(p) : 'Sin programa';
}

/* ── Ventana de opciones ── */
function abrirInformePub() {
  if (!DATOS || !DATOS.prospectos) {
    alert('Espera a que termine de cargar la lista de prospectos.');
    return;
  }
  var cont = document.getElementById('informePub');
  cont.style.display = 'block';
  cont.innerHTML =
    '<div class="ip-hoja ip-opc">' +
    '<h2>Informe para decidir publicidad</h2>' +
    '<p class="ip-sub">Cruza los prospectos con los formularios de inscripción ' +
    'para saber qué canal trae gente que <b>sí</b> se inscribe.</p>' +
    '<label>Periodo<select id="ipDias">' +
    '<option value="30">Últimos 30 días</option>' +
    '<option value="60">Últimos 60 días</option>' +
    '<option value="90" selected>Últimos 90 días</option>' +
    '<option value="0">Todo el registro</option></select></label>' +
    '<p class="ip-sub" style="margin-top:14px"><b>Lo invertido en ese periodo</b> ' +
    '(opcional). Con esto el informe calcula cuánto cuesta cada prospecto y ' +
    'cada inscripción.</p>' +
    '<div class="ip-inv">' +
    '<label>Meta (Facebook e Instagram)<input id="ipMeta" type="number" min="0" placeholder="0"></label>' +
    '<label>Google<input id="ipGoogle" type="number" min="0" placeholder="0"></label>' +
    '<label>Otra publicidad<input id="ipOtra" type="number" min="0" placeholder="0"></label>' +
    '</div>' +
    '<div class="ip-btns no-print">' +
    '<button type="button" onclick="cerrarInformePub()">Cancelar</button>' +
    '<button type="button" class="ip-pri" onclick="generarInformePub()">Generar informe</button>' +
    '</div><div id="ipEstado" class="ip-sub"></div></div>';
}
function cerrarInformePub() {
  var c = document.getElementById('informePub');
  c.style.display = 'none';
  c.innerHTML = '';
}

function generarInformePub() {
  var dias = Number(document.getElementById('ipDias').value) || 0;
  var inv = {
    meta: Number(document.getElementById('ipMeta').value) || 0,
    google: Number(document.getElementById('ipGoogle').value) || 0,
    otra: Number(document.getElementById('ipOtra').value) || 0
  };
  var est = document.getElementById('ipEstado');
  est.textContent = 'Leyendo los formularios de inscripción…';
  cargarFeed(true)
    .then(function (j) {
      if (!j || !j.ok) throw new Error((j && j.error) || 'sin respuesta');
      pintarInformePub(dias, inv, j.inscripciones || []);
    })
    .catch(function (e) {
      est.innerHTML = 'No se pudieron leer los formularios (' + ipEsc(e.message || e) +
        '). Vuelve a intentarlo en un momento.';
    });
}

function pintarInformePub(dias, inv, formularios) {
  var P = DATOS.prospectos || [];
  var hoy = new Date(); hoy.setHours(0, 0, 0, 0);
  var desde = dias ? new Date(hoy.getTime() - dias * 86400000) : null;
  var enPer = function (d) { return d && (!desde || d >= desde); };

  /* Índices de los formularios para cruzar. */
  var porTel = {}, porCor = {};
  formularios.forEach(function (f) {
    if (f.t) porTel[f.t] = f;
    if (f.c) porCor[f.c] = f;
  });
  var usados = {};
  function inscripcionDe(x) {
    var t = ipTel(x.telefono), c = String(x.correo || '').trim().toLowerCase();
    var f = (t && porTel[t]) || (c && porCor[c]) || null;
    if (f) usados[(f.t || '') + '|' + (f.c || '') + '|' + f.f] = true;
    return f;
  }

  /* Una persona, un prospecto. El campo «repetido» no se marca y hay
     registros duplicados con el mismo teléfono: sin esto una sola
     inscripción contaría dos o tres veces. Se conserva el primer registro. */
  var vistos = {};
  var pros = P.filter(function (x) {
    if (!enPer(ipFecha(x.alta))) return false;
    var k = ipTel(x.telefono) || String(x.correo || '').trim().toLowerCase() || ('fila' + x.fila);
    if (vistos[k]) return false;
    vistos[k] = true;
    return true;
  });
  var tot = pros.length;
  var canales = {}, programas = {}, paginas = {}, diasSem = [0, 0, 0, 0, 0, 0, 0];
  var inscritos = 0, sinSeguimiento = 0, diasEspera = [];
  pros.forEach(function (x) {
    var cn = canalDe(x.origen);
    var pg = progNorm(x.programa);
    var f = inscripcionDe(x);
    canales[cn] = canales[cn] || { p: 0, i: 0 };
    canales[cn].p++;
    programas[pg] = programas[pg] || { p: 0, i: 0, f: 0 };
    programas[pg].p++;
    if (f) { canales[cn].i++; programas[pg].i++; inscritos++; }
    var pag = paginaDe(x.origen);
    if (pag) paginas[pag] = (paginas[pag] || 0) + 1;
    var d = ipFecha(x.alta);
    if (d) diasSem[d.getDay()]++;
    if (!f && (x.etapa === 'Nuevo' || !x.etapa)) {
      sinSeguimiento++;
      if (typeof x.dias === 'number') diasEspera.push(x.dias);
    }
  });

  /* Formularios del periodo y los que llegaron sin haber sido prospecto. */
  var formPer = formularios.filter(function (f) { return enPer(ipIso(f.f)); });
  // Se recorren TODOS los prospectos para saber qué formularios tienen
  // antecedente, aunque el prospecto sea de antes del periodo.
  P.forEach(function (x) { inscripcionDe(x); });
  var sinAntecedente = formPer.filter(function (f) {
    return !usados[(f.t || '') + '|' + (f.c || '') + '|' + f.f];
  }).length;
  formPer.forEach(function (f) {
    var pg = progNorm(f.p);
    programas[pg] = programas[pg] || { p: 0, i: 0, f: 0 };
    programas[pg].f++;
  });

  /* Semanas: últimas 12, prospectos e inscripciones. */
  var semanas = [];
  var lunes = new Date(hoy); lunes.setDate(lunes.getDate() - ((lunes.getDay() + 6) % 7));
  for (var w = 11; w >= 0; w--) {
    var ini = new Date(lunes.getTime() - w * 7 * 86400000);
    var fin = new Date(ini.getTime() + 7 * 86400000);
    var vs = {};
    var np = P.filter(function (x) {
      var d = ipFecha(x.alta);
      if (!(d && d >= ini && d < fin)) return false;
      var k = ipTel(x.telefono) || String(x.correo || '').trim().toLowerCase() || ('fila' + x.fila);
      if (vs[k]) return false;
      vs[k] = true;
      return true;
    }).length;
    var ni = formularios.filter(function (f) { var d = ipIso(f.f); return d && d >= ini && d < fin; }).length;
    semanas.push({ ini: ini, p: np, i: ni });
  }

  var invTotal = inv.meta + inv.google + inv.otra;
  var listaCan = Object.keys(canales).map(function (k) {
    return { n: k, p: canales[k].p, i: canales[k].i };
  }).sort(function (a, b) { return b.p - a.p; });
  var listaProg = Object.keys(programas).map(function (k) {
    return { n: k, p: programas[k].p, i: programas[k].i, f: programas[k].f };
  }).sort(function (a, b) { return b.p - a.p; });
  var listaPag = Object.keys(paginas).map(function (k) { return { n: k, c: paginas[k] }; })
    .sort(function (a, b) { return b.c - a.c; }).slice(0, 6);

  /* ── Recomendaciones: solo las que los datos sostienen ── */
  var rec = [];
  var pctSin = ipPct(sinSeguimiento, tot);
  if (tot && pctSin >= 40) {
    rec.push(['alta', 'Antes de subir la inversión, atender el seguimiento: el ' + pctSin +
      ' % de los prospectos del periodo (' + sinSeguimiento + ') sigue sin avanzar de «Nuevo». ' +
      'Pagar por más contactos que no se atienden no se traduce en inscripciones.']);
  }
  var confiables = listaCan.filter(function (c) { return c.p >= 8; });
  if (confiables.length >= 2) {
    var mejor = confiables.slice().sort(function (a, b) { return (b.i / b.p) - (a.i / a.p); })[0];
    if (mejor.i > 0) {
      rec.push(['buena', '«' + mejor.n + '» es el canal que mejor convierte con volumen suficiente: ' +
        ipPct(mejor.i, mejor.p) + ' % de sus prospectos se inscribió (' + mejor.i + ' de ' + mejor.p + ').']);
    }
    confiables.forEach(function (c) {
      if (c.i === 0 && c.p >= 15) {
        rec.push(['media', '«' + c.n + '» trajo ' + c.p + ' prospectos y ninguno se ha inscrito todavía. ' +
          'Conviene revisar qué se le responde a esa gente antes de seguir invirtiendo ahí.']);
      }
    });
  }
  var wa = canales['WhatsApp directo'];
  if (wa && tot && wa.p / tot >= 0.5) {
    rec.push(['media', 'El ' + ipPct(wa.p, tot) + ' % llega por WhatsApp directo, y ahí no se sabe ' +
      'qué anuncio lo trajo. Si las publicaciones promocionadas mandan a WhatsApp, usar un mensaje ' +
      'precargado distinto por campaña (por ejemplo «Hola, vi el anuncio de Licenciatura») permite ' +
      'atribuir cada contacto a su anuncio.']);
  }
  var etiquetadas = (canales['Campaña pagada en Meta'] || { p: 0 }).p + (canales['Campaña pagada en Google'] || { p: 0 }).p;
  if (invTotal > 0 && tot && etiquetadas / tot < 0.2) {
    rec.push(['media', 'Solo ' + etiquetadas + ' prospectos llegaron por un enlace de campaña etiquetado. ' +
      'Con tan pocos, el costo por canal no se puede medir con precisión: el costo global es la cifra confiable.']);
  }
  if (sinAntecedente > 0 && formPer.length) {
    rec.push(['info', sinAntecedente + ' de ' + formPer.length + ' inscripciones del periodo llegaron sin ' +
      'haber quedado registradas como prospecto. Esas personas se inscribieron sin pasar por el ' +
      'seguimiento: suele ser recomendación directa o el sitio web.']);
  }
  var demanda = listaProg.filter(function (x) { return x.n !== 'Preguntó en general'; })[0];
  if (demanda) {
    rec.push(['info', 'El programa con más interés es ' + demanda.n + ' (' + demanda.p +
      ' prospectos, ' + ipPct(demanda.p, tot) + ' % del total).']);
  }

  /* ── HTML del informe ── */
  var hoyTxt = new Date().toLocaleDateString('es-MX', { day: 'numeric', month: 'long', year: 'numeric' });
  var perTxt = dias ? ('Últimos ' + dias + ' días') : 'Todo el registro';
  var maxSem = Math.max.apply(null, semanas.map(function (s) { return Math.max(s.p, s.i); }).concat([1]));
  var nomDia = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
  var maxDia = Math.max.apply(null, diasSem.concat([1]));
  var colInv = invTotal > 0;

  var h = '<div class="ip-hoja">' +
    '<div class="ip-btns no-print">' +
    '<button type="button" onclick="abrirInformePub()">Cambiar opciones</button>' +
    '<button type="button" onclick="cerrarInformePub()">Cerrar</button>' +
    '<button type="button" class="ip-pri" onclick="imprimirInformePub()">Descargar PDF</button></div>' +
    '<div class="ip-cab"><div><div class="ip-ins">Centro de Estudios Superiores del Mayo</div>' +
    '<h1>Informe de admisiones para decidir publicidad</h1>' +
    '<div class="ip-sub">' + perTxt + ' · generado el ' + hoyTxt + '</div></div></div>' +

    '<div class="ip-kpis">' +
    ipKpi(tot, 'Prospectos') +
    ipKpi(inscritos, 'De ellos se inscribieron') +
    ipKpi(ipPct(inscritos, tot) + ' %', 'Conversión') +
    ipKpi(formPer.length, 'Inscripciones en el periodo') +
    (colInv ? ipKpi(ipMoney(invTotal), 'Invertido') : ipKpi(pctSin + ' %', 'Sin seguimiento')) +
    '</div>';

  if (colInv) {
    h += '<div class="ip-kpis ip-kpis2">' +
      ipKpi(tot ? ipMoney(invTotal / tot) : '—', 'Costo por prospecto') +
      ipKpi(formPer.length ? ipMoney(invTotal / formPer.length) : '—', 'Costo por inscripción') +
      ipKpi(pctSin + ' %', 'Prospectos sin seguimiento') + '</div>';
  }

  h += '<div class="ip-sec"><h3>Recomendaciones</h3>';
  if (!rec.length) h += '<p class="ip-sub">No hay volumen suficiente en este periodo para sacar conclusiones firmes.</p>';
  rec.forEach(function (r) { h += '<div class="ip-rec ip-' + r[0] + '">' + ipEsc(r[1]) + '</div>'; });
  h += '</div>';

  h += '<div class="ip-sec"><h3>Por canal de llegada</h3><table class="ip-t"><tr>' +
    '<th>Canal</th><th class="n">Prospectos</th><th class="n">% del total</th>' +
    '<th class="n">Se inscribieron</th><th class="n">Conversión</th></tr>';
  listaCan.forEach(function (c) {
    h += '<tr><td>' + ipEsc(c.n) + '</td><td class="n">' + c.p + '</td><td class="n">' +
      ipPct(c.p, tot) + ' %</td><td class="n">' + c.i + '</td><td class="n"><b>' +
      ipPct(c.i, c.p) + ' %</b></td></tr>';
  });
  h += '</table>';
  if (colInv) {
    var cm = canales['Campaña pagada en Meta'] || { p: 0, i: 0 };
    var cg = canales['Campaña pagada en Google'] || { p: 0, i: 0 };
    h += '<table class="ip-t" style="margin-top:10px"><tr><th>Plataforma</th><th class="n">Invertido</th>' +
      '<th class="n">Prospectos con enlace de campaña</th><th class="n">Costo por prospecto</th></tr>';
    if (inv.meta) h += '<tr><td>Meta</td><td class="n">' + ipMoney(inv.meta) + '</td><td class="n">' + cm.p +
      '</td><td class="n">' + (cm.p ? ipMoney(inv.meta / cm.p) : '—') + '</td></tr>';
    if (inv.google) h += '<tr><td>Google</td><td class="n">' + ipMoney(inv.google) + '</td><td class="n">' + cg.p +
      '</td><td class="n">' + (cg.p ? ipMoney(inv.google / cg.p) : '—') + '</td></tr>';
    if (inv.otra) h += '<tr><td>Otra</td><td class="n">' + ipMoney(inv.otra) + '</td><td class="n">—</td><td class="n">—</td></tr>';
    h += '</table><p class="ip-nota">El costo por plataforma solo cuenta a quien llegó por un enlace ' +
      'de campaña etiquetado. Quien vio el anuncio y escribió directo por WhatsApp cae en «WhatsApp ' +
      'directo», así que ese costo por plataforma sale más alto de lo real.</p>';
  }
  h += '</div>';

  h += '<div class="ip-sec"><h3>Por programa</h3><table class="ip-t"><tr><th>Programa</th>' +
    '<th class="n">Prospectos</th><th class="n">Prospectos inscritos</th>' +
    '<th class="n">Inscripciones en el periodo</th></tr>';
  listaProg.forEach(function (x) {
    h += '<tr><td>' + ipEsc(x.n) + '</td><td class="n">' + x.p + '</td><td class="n">' + x.i +
      '</td><td class="n">' + x.f + '</td></tr>';
  });
  h += '</table></div>';

  h += '<div class="ip-sec"><h3>Últimas 12 semanas</h3><table class="ip-t ip-barras"><tr>' +
    '<th>Semana del</th><th>Prospectos</th><th>Inscripciones</th></tr>';
  semanas.forEach(function (s) {
    h += '<tr><td>' + s.ini.toLocaleDateString('es-MX', { day: 'numeric', month: 'short' }) + '</td>' +
      '<td><span class="ip-bar" style="width:' + Math.round(s.p * 100 / maxSem) + '%"></span>' + s.p + '</td>' +
      '<td><span class="ip-bar ip-bar2" style="width:' + Math.round(s.i * 100 / maxSem) + '%"></span>' + s.i + '</td></tr>';
  });
  h += '</table><p class="ip-nota">Sirve para ver si las semanas con publicidad activa ' +
    'coinciden con más prospectos y, sobre todo, con más inscripciones.</p></div>';

  h += '<div class="ip-sec ip-dos"><div><h3>Día en que escriben</h3><table class="ip-t ip-barras">';
  [1, 2, 3, 4, 5, 6, 0].forEach(function (k) {
    h += '<tr><td>' + nomDia[k] + '</td><td><span class="ip-bar" style="width:' +
      Math.round(diasSem[k] * 100 / maxDia) + '%"></span>' + diasSem[k] + '</td></tr>';
  });
  h += '</table><p class="ip-nota">Los días con más contactos son los mejores para tener ' +
    'anuncios activos y a alguien respondiendo.</p></div>';
  h += '<div><h3>Páginas de entrada del sitio</h3>';
  if (listaPag.length) {
    h += '<table class="ip-t">';
    listaPag.forEach(function (p) { h += '<tr><td>' + ipEsc(p.n) + '</td><td class="n">' + p.c + '</td></tr>'; });
    h += '</table><p class="ip-nota">Por dónde entró al sitio quien llenó la preinscripción.</p>';
  } else {
    h += '<p class="ip-sub">Sin datos de navegación en este periodo.</p>';
  }
  h += '</div></div>';

  h += '<div class="ip-sec"><h3>Cómo se calculó</h3><p class="ip-nota">' +
    'Una persona cuenta como inscrita si su teléfono o su correo aparecen en algún formulario ' +
    'oficial de inscripción; no se usa la etapa marcada a mano, que no siempre se actualiza. ' +
    'Los prospectos repetidos se cuentan una sola vez. «Sin seguimiento» son prospectos que no ' +
    'se han inscrito y siguen en etapa «Nuevo». Las cifras de un periodo reciente pueden subir: ' +
    'hay quien se inscribe semanas después de su primer contacto.</p></div>' +
    '</div>';

  var cont = document.getElementById('informePub');
  cont.innerHTML = h;
  cont.scrollTop = 0;
}
function ipKpi(v, t) {
  return '<div class="ip-kpi"><b>' + ipEsc(v) + '</b><span>' + ipEsc(t) + '</span></div>';
}
function imprimirInformePub() {
  var antes = document.title;
  var d = new Date();
  document.title = 'Informe de publicidad CESSUM ' + d.getFullYear() + '-' +
    String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  window.print();
  setTimeout(function () { document.title = antes; }, 800);
}
document.getElementById('inscInforme').onclick = abrirInformePub;


/* (28-sep) El asistente de admisiones se abre ahora con un token de 6 horas (pintarAsistente, arriba): antes llevaba una clave fija escrita en este archivo público. */

['q', 'fEtapa', 'fPrograma', 'fAsesor'].forEach(function (id) {
  var el = document.getElementById(id);
  el.addEventListener('input', pintar);
  el.addEventListener('change', pintar);
});
/* ══════════════════════════════════════════════════════════════════════
   (22-sep) REPETIDOS: DETECTARLOS, ELEGIR CON CRITERIO Y UNIFICAR
   ──────────────────────────────────────────────────────────────────────
   Antes se detectaban solo por teléfono y se resolvían de uno en uno desde
   la tarjeta, decidiendo a ojo cuál conservar. Sobre renglones repetidos
   toda medición miente: la conversión, el conteo por programa y la cola.
   Aquí se agrupan por teléfono Y por correo, se propone cuál conservar con
   un criterio explícito, y al unificar NO se pierde nada: la que se queda
   hereda la etapa más avanzada, el programa, los otros programas, la fecha
   de alta más antigua —que es la que sostiene la atribución por campaña— y
   una nota con lo que traían las demás. Las otras quedan «No procede».
   Lo que puede cambiar el sentido de los datos —dos programas específicos
   distintos, dos etapas avanzadas en conflicto— NO se toca solo: se marca
   para revisarlo a mano.
   ══════════════════════════════════════════════════════════════════════ */
var GRUPOS_REP = [];
var ETAPA_PESO = { 'Inscrito': 5, 'Documentos en proceso': 4, 'Interesado': 3,
  'Contactado': 2, 'Nuevo': 1, 'No procede': 0 };

function repCorreo(c) {
  var t = String(c == null ? '' : c).trim().toLowerCase();
  return t.indexOf('@') > 0 ? t : '';
}
function repPeso(p) { return ETAPA_PESO[String(p.etapa || 'Nuevo').trim()] || 0; }
function repProgEspecifico(p) {
  var t = String(p.programa || '').trim();
  if (!t) return '';
  return /general/i.test(t) ? '' : t;
}
/* Cuántos datos trae la ficha: decide cuando dos van igual de avanzadas. */
function repRiqueza(p) {
  var n = 0;
  if (repCorreo(p.correo)) n += 2;
  if (repProgEspecifico(p)) n += 2;
  if (String(p.notas || '').trim()) n += 1;
  if (String(p.asignado || '').trim()) n += 1;
  if (String(p.waEnviado || '').trim()) n += 1;
  if (String(p.respondio || '').trim()) n += 1;
  return n;
}
function repFecha(v) {
  var d = ipFecha(v) || ipIso(v);
  return d ? d.getTime() : 0;
}

/* Agrupa por teléfono Y por correo: dos fichas con el mismo correo y
   distinto teléfono también son la misma persona. */
function calcularGruposRepetidos() {
  var vivos = (DATOS.prospectos || []).filter(function (p) {
    var e = String(p.etapa || '').trim();
    return e !== 'No procede' && !p.baja;
  });
  var deTel = {}, deCorreo = {}, padre = {};
  function raiz(x) { while (padre[x] !== x) { padre[x] = padre[padre[x]]; x = padre[x]; } return x; }
  function unir(a, b) { a = raiz(a); b = raiz(b); if (a !== b) padre[a] = b; }
  vivos.forEach(function (p) { padre[p.fila] = p.fila; });
  vivos.forEach(function (p) {
    var t = telClave(p.telefono), c = repCorreo(p.correo);
    if (t) { if (deTel[t] !== undefined) unir(p.fila, deTel[t]); else deTel[t] = p.fila; }
    if (c) { if (deCorreo[c] !== undefined) unir(p.fila, deCorreo[c]); else deCorreo[c] = p.fila; }
  });
  var bolsas = {};
  vivos.forEach(function (p) {
    var r = raiz(p.fila);
    (bolsas[r] = bolsas[r] || []).push(p);
  });
  GRUPOS_REP = [];
  Object.keys(bolsas).forEach(function (r) {
    var g = bolsas[r];
    if (g.length < 2) return;
    // Cuál se conserva: etapa más avanzada → más datos → contacto más reciente.
    var orden = g.slice().sort(function (a, b) {
      var d = repPeso(b) - repPeso(a);
      if (d) return d;
      d = repRiqueza(b) - repRiqueza(a);
      if (d) return d;
      return repFecha(b.ultimo) - repFecha(a.ultimo);
    });
    var queda = orden[0], otras = orden.slice(1);
    // Conflictos: lo que NO se decide solo.
    var conflictos = [];
    var progs = {};
    g.forEach(function (p) { var x = repProgEspecifico(p); if (x) progs[progNorm(x)] = x; });
    if (Object.keys(progs).length > 1) {
      conflictos.push('Preguntó por programas distintos: ' +
        Object.keys(progs).map(function (k) { return progs[k]; }).join(' y ') +
        '. Hay que decidir cuál es el suyo.');
    }
    var avanzadas = g.filter(function (p) { return repPeso(p) >= 3; });
    if (avanzadas.length > 1) {
      conflictos.push('Dos fichas avanzadas (' +
        avanzadas.map(function (p) { return p.etapa; }).join(' y ') +
        '): revisar cuál refleja la realidad.');
    }
    // Lo que heredaría la que se conserva.
    var etapaAlta = g.slice().sort(function (a, b) { return repPeso(b) - repPeso(a); })[0].etapa;
    var fechas = g.map(function (p) { return repFecha(p.alta) || repFecha(p.ultimo); })
      .filter(function (x) { return x; });
    var masVieja = fechas.length ? Math.min.apply(null, fechas) : 0;
    var otrosProg = [];
    Object.keys(progs).forEach(function (k) {
      if (progNorm(repProgEspecifico(queda)) !== k) otrosProg.push(progs[k]);
    });
    var asesor = '';
    g.forEach(function (p) { if (!asesor && String(p.asignado || '').trim()) asesor = p.asignado; });
    GRUPOS_REP.push({ fichas: g, queda: queda, otras: otras, conflictos: conflictos,
      etapaAlta: etapaAlta, masVieja: masVieja, otrosProg: otrosProg, asesor: asesor });
  });
  // Primero los que se pueden unificar sin pensar; al final los que exigen decisión.
  GRUPOS_REP.sort(function (a, b) {
    if (!a.conflictos.length !== !b.conflictos.length) return a.conflictos.length ? 1 : -1;
    return b.fichas.length - a.fichas.length;
  });
}

function porQueQueda(gr) {
  var q = gr.queda, razones = [];
  var otras = gr.otras;
  if (otras.length && repPeso(q) > repPeso(otras[0])) razones.push('va más avanzada (' + q.etapa + ')');
  if (otras.length && repRiqueza(q) > repRiqueza(otras[0])) razones.push('tiene más datos');
  if (!razones.length) razones.push('es la del contacto más reciente');
  return 'Se conserva porque ' + razones.join(' y ') + '.';
}

/* (23-sep) UNIFICAR CON CONFIRMACIÓN Y CON AVANCE A LA VISTA.
   Antes, «Unificar los N sin conflicto» empezaba a archivar sin preguntar,
   el avance se escribía en el rótulo de la barra de la lista (que no se ve
   desde Repetidos) y al terminar la vista no se repintaba: los ya unificados
   seguían en pantalla y un segundo clic los procesaba otra vez.
   Ahora: se pide confirmación diciendo qué se conserva y qué se archiva; el
   avance se ve aquí mismo; los botones se desactivan mientras corre; y al
   final queda el resultado en pantalla y la vista se vuelve a pintar. */
var REP_CORRIENDO = false, REP_RESUMEN = '';

function pintarRepetidos() {
  calcularGruposRepetidos();
  /* (28-sep) Con una revisión de IA lista, esta vista muestra sus decisiones; «Ver el modo manual» vuelve a la lista de siempre. */
  if (REP_IA.listo && REP_IA.vista === 'ia' && !REP_IA.corriendo) { repIAPintar(); return; }
  var c = document.getElementById('v-repetidos');
  var resumen = REP_RESUMEN ? '<div class="tarjeta" style="margin-bottom:10px;border-left:4px solid var(--rojo)">' + REP_RESUMEN + '</div>' : '';
  if (!GRUPOS_REP.length) {
    /* (28-sep) Puede no haber repetidos por teléfono o correo y sí por nombre parecido: la IA los busca. */
    var _porNombre = calcularPosiblesPorNombre().length;
    c.innerHTML = resumen + (_porNombre ? repIACajaHtml() : '') + '<div class="tarjeta"><b>No hay fichas repetidas por teléfono ni por correo.</b><div class="sub">' +
      'Se buscan entre las fichas vivas.' + (_porNombre ? ' Sí hay ' + _porNombre + ' posible(s) por nombre parecido: use «Decidir con IA».' : '') + '</div></div>';
    var _bIA0 = document.getElementById('repIABtn'); if (_bIA0) _bIA0.onclick = repIAAnalizar;
    return;
  }
  var limpios = GRUPOS_REP.filter(function (g) { return !g.conflictos.length; }).length;
  var html = resumen + repIACajaHtml() + '<div class="tarjeta"><b>' + GRUPOS_REP.length + ' persona(s) con ficha repetida</b>' +
    '<div class="sub">Se conserva una y las demás quedan en «No procede», con la nota de a cuál ' +
    'se fusionaron. La que se queda hereda la etapa más avanzada, el programa, la fecha de alta ' +
    'más antigua y las notas de las otras. El teléfono y el correo no se pueden cambiar desde ' +
    'aquí, así que se conservan los de esa ficha. Nada se borra.</div>' +
    (limpios ? '<div style="margin-top:10px"><button id="repTodos" class="pri">Unificar ' +
      'los ' + limpios + ' sin conflicto</button></div>' : '') +
    '<div id="repProgreso" style="margin-top:10px;font-weight:700;display:none"></div></div>';
  GRUPOS_REP.forEach(function (gr, n) {
    html += '<div class="tarjeta" style="margin-top:10px">' +
      '<b>' + ipEsc(gr.queda.nombre || '(sin nombre)') + '</b> · ' +
      gr.fichas.length + ' fichas' +
      (gr.conflictos.length
        ? '<div class="sub" style="color:var(--rojo)"><b>Revisar a mano:</b> ' +
          gr.conflictos.map(ipEsc).join(' ') + '</div>'
        : '<div class="sub">' + ipEsc(porQueQueda(gr)) + '</div>');
    gr.fichas.forEach(function (p) {
      var esQueda = p.fila === gr.queda.fila;
      html += '<div style="display:flex;gap:8px;align-items:flex-start;margin-top:8px;' +
        'padding:8px;border-radius:8px;border:1px solid ' +
        (esQueda ? 'var(--rojo)' : 'rgba(0,0,0,.12)') + '">' +
        '<div style="font-size:11px;font-weight:700;color:' +
        (esQueda ? 'var(--rojo)' : '#888') + ';min-width:74px">' +
        (esQueda ? 'SE CONSERVA' : 'Se archiva') + '</div>' +
        '<div style="flex:1;font-size:12px;line-height:1.5">' + repDescribir(p) + '</div></div>';
    });
    html += '<div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap">' +
      '<button class="pri" data-rep="' + n + '">Unificar en la que se conserva</button>' +
      '<button data-repcambiar="' + n + '">Conservar otra</button></div></div>';
  });
  c.innerHTML = html;
  var bIA = document.getElementById('repIABtn'); if (bIA) bIA.onclick = repIAAnalizar;
  var bVIA = document.getElementById('repIAVolver'); if (bVIA) bVIA.onclick = function () { REP_IA.vista = 'ia'; pintarRepetidos(); };
  var bt = document.getElementById('repTodos');
  if (bt) bt.onclick = function () {
    var gs = GRUPOS_REP.filter(function (g) { return !g.conflictos.length; });
    if (confirmarUnificar(gs)) unificarVarios(gs);
  };
  Array.prototype.forEach.call(c.querySelectorAll('[data-rep]'), function (b) {
    b.onclick = function () {
      var g = GRUPOS_REP[Number(b.getAttribute('data-rep'))];
      if (confirmarUnificar([g])) unificarVarios([g]);
    };
  });
  Array.prototype.forEach.call(c.querySelectorAll('[data-repcambiar]'), function (b) {
    b.onclick = function () { elegirOtra(GRUPOS_REP[Number(b.getAttribute('data-repcambiar'))]); };
  });
}

/* Cómo se describe una ficha: igual en la tarjeta y en la confirmación. */
function repDescribir(p, plano) {
  var t = (p.etapa || 'Nuevo') + ' · ' + (p.programa || 'sin programa') +
    (p.correo ? ' · ' + p.correo : ' · sin correo') +
    (p.telefono ? ' · ' + p.telefono : '') +
    (p.alta ? ' · alta ' + p.alta : '') +
    (p.ultimo ? ' · último contacto ' + p.ultimo : '');
  if (plano) return t;
  return ipEsc(t) + (p.origen ? '<br><span style="color:#888">' + ipEsc(p.origen) + '</span>' : '');
}

/* La confirmación dice exactamente qué va a pasar. */
function confirmarUnificar(grupos) {
  if (REP_CORRIENDO) { alert('Ya hay una unificación en curso. Espera a que termine.'); return false; }
  if (!grupos || !grupos.length) return false;
  var msg;
  if (grupos.length === 1) {
    var g = grupos[0];
    msg = '¿Unificar las fichas de ' + (g.queda.nombre || 'esta persona') + '?\n\n' +
      'SE CONSERVA:\n  ' + repDescribir(g.queda, true) + '\n\n' +
      'SE ARCHIVA' + (g.otras.length > 1 ? 'N' : '') + ' (queda' + (g.otras.length > 1 ? 'n' : '') + ' en «No procede», con nota):\n' +
      g.otras.map(function (o) { return '  · ' + repDescribir(o, true); }).join('\n') +
      '\n\nNada se borra.';
  } else {
    var fichas = grupos.reduce(function (a, g) { return a + g.otras.length; }, 0);
    var nombres = grupos.slice(0, 6).map(function (g) { return '  · ' + (g.queda.nombre || '(sin nombre)'); }).join('\n');
    msg = '¿Unificar ' + grupos.length + ' personas?\n\n' +
      '· Se conserva una ficha de cada persona (la marcada «SE CONSERVA»).\n' +
      '· Se archivan ' + fichas + ' ficha(s) repetida(s): quedan en «No procede», con la nota de a cuál se unieron.\n' +
      '· Nada se borra.\n\n' + nombres + (grupos.length > 6 ? '\n  · … y ' + (grupos.length - 6) + ' más' : '') +
      '\n\nTarda unos segundos por persona. No cierres la página.';
  }
  return confirm(msg);
}

/* Cambiar a mano cuál se conserva: el criterio propone, no impone. */
function elegirOtra(gr) {
  if (REP_CORRIENDO) { alert('Ya hay una unificación en curso. Espera a que termine.'); return; }
  var opciones = gr.fichas.map(function (p, i) {
    return (i + 1) + ') ' + (p.nombre || '(sin nombre)') + ' · ' + repDescribir(p, true);
  }).join('\n');
  var r = prompt('¿Cuál se conserva?\n\n' + opciones + '\n\nEscribe el número:');
  var n = Number(r);
  if (!n || n < 1 || n > gr.fichas.length) return;
  var nueva = gr.fichas[n - 1];
  var copia = { queda: nueva, fichas: gr.fichas, conflictos: gr.conflictos,
    otras: gr.fichas.filter(function (p) { return p.fila !== nueva.fila; }),
    etapaAlta: gr.etapaAlta, otrosProg: gr.otrosProg, asesor: gr.asesor, masVieja: gr.masVieja };
  if (confirmarUnificar([copia])) unificarVarios([copia]);
}

/* Se unifica grupo por grupo y ficha por ficha, esperando cada respuesta:
   si algo falla, se sabe exactamente qué quedó a medias. */
function unificarVarios(grupos) {
  if (!grupos.length || REP_CORRIENDO) return;
  REP_CORRIENDO = true;
  var vista = document.getElementById('v-repetidos');
  Array.prototype.forEach.call(vista.querySelectorAll('button'), function (b) { b.disabled = true; });
  var prog = document.getElementById('repProgreso');
  if (prog) { prog.style.display = 'block'; window.scrollTo(0, 0); }
  var cuenta = document.getElementById('cuenta');
  var hechos = 0, fallaron = 0, gi = 0, listos = [], conFalla = [];
  function avisar(t) { if (prog) prog.textContent = t; if (cuenta) cuenta.textContent = t; }
  function terminar(cortado) {
    REP_CORRIENDO = false;
    REP_RESUMEN = '<b>' + (cortado ? 'Unificación interrumpida' : 'Unificación terminada') + '</b>' +
      '<div class="sub">' + listos.length + ' persona(s) unificada(s) · ' + hechos + ' ficha(s) archivada(s)' +
      (fallaron ? ' · <span style="color:var(--rojo)">' + fallaron + ' escritura(s) no se pudieron: vuelve a intentarlo con esas personas.</span>' : '') + '</div>' +
      (listos.length ? '<div class="sub" style="margin-top:6px">Unificadas: ' + listos.map(ipEsc).join(' · ') + '</div>' : '') +
      (conFalla.length ? '<div class="sub" style="margin-top:6px;color:var(--rojo)">Con falla: ' + conFalla.map(ipEsc).join(' · ') + '</div>' : '');
    avisar('');
    alert((cortado ? 'Se interrumpió. ' : 'Listo. ') + listos.length + ' persona(s) unificada(s), ' +
      hechos + ' ficha(s) archivada(s)' + (fallaron ? '; ' + fallaron + ' no se pudieron: vuelve a intentarlo.' : '.'));
    cargar();   // al llegar los datos, pintar() vuelve a pintar esta vista
  }
  function siguienteGrupo() {
    if (gi >= grupos.length) { terminar(false); return; }
    var gr = grupos[gi], q = gr.queda, i = 0, fallasGrupo = 0;
    avisar('Unificando ' + (gi + 1) + ' de ' + grupos.length + ': ' + (q.nombre || '(sin nombre)') + '…');
    function siguienteFicha() {
      if (i >= gr.otras.length) {
        // Al final, lo que hereda la que se conserva.
        /* (28-sep) Ya NO se marca «tocar»: dejaba el último contacto en HOY y escondía de la cola a quien lleva semanas esperando. */
        var c = { fila: Number(q.fila),
          nota: 'Se unificaron ' + gr.otras.length + ' ficha(s) repetida(s) de esta persona.' };
        if (gr.etapaAlta && ETAPA_PESO[gr.etapaAlta] > repPeso(q)) c.etapa = gr.etapaAlta;
        if (!repProgEspecifico(q) && gr.otrosProg.length) c.programa = gr.otrosProg[0];
        if (gr.otrosProg.length) {
          c.otrosProgramas = gr.otrosProg.filter(function (x) {
            return progNorm(x) !== progNorm(c.programa || q.programa || '');
          }).join(', ');
        }
        if (!String(q.asignado || '').trim() && gr.asesor) c.asignado = gr.asesor;
        if (gr.masVieja) {
          var d = new Date(gr.masVieja);
          c.fecha = ('0' + d.getDate()).slice(-2) + '/' + ('0' + (d.getMonth() + 1)).slice(-2) +
            '/' + d.getFullYear();
        }
        apiEscribir('guardar', { pase: PASE, cambios: JSON.stringify(c) }).then(function (r) {
          if (r && r.expirado) { REP_CORRIENDO = false; mostrarAcceso('Tu sesión caducó. Vuelve a entrar y repite la unificación: lo ya hecho se conserva.'); return; }
          if (r && r.ok) aplicarLocal(c.fila, cambiosLocales(c)); else { fallaron++; fallasGrupo++; }
          if (fallasGrupo) conFalla.push(q.nombre || '(sin nombre)'); else listos.push(q.nombre || '(sin nombre)');
          gi++;
          siguienteGrupo();
        });
        return;
      }
      var o = gr.otras[i];
      var cc = { fila: Number(o.fila), etapa: 'No procede',
        nota: 'Ficha repetida de ' + (q.nombre || 'la misma persona') + '. Se unificó en la ficha ' +
          'de la fila ' + q.fila + ', que es la que se trabaja.' };
      apiEscribir('guardar', { pase: PASE, cambios: JSON.stringify(cc) }).then(function (r) {
        if (r && r.expirado) { REP_CORRIENDO = false; mostrarAcceso('Tu sesión caducó. Vuelve a entrar y repite la unificación: lo ya hecho se conserva.'); return; }
        if (r && r.ok) { hechos++; aplicarLocal(cc.fila, cambiosLocales(cc)); } else { fallaron++; fallasGrupo++; }
        i++;
        siguienteFicha();
      });
    }
    siguienteFicha();
  }
  siguienteGrupo();
}


/* ══════════════════════════════════════════════════════════════════════
   (28-sep) REPETIDOS: DECISIÓN CON IA
   ──────────────────────────────────────────────────────────────────────
   La IA revisa TODOS los grupos —también los que traen conflicto, que eran
   el trabajo pesado— y propone: ¿es la misma persona?, ¿cuál ficha se
   conserva?, ¿qué programa es el suyo? Además busca repetidos que la lista
   no ve porque no comparten teléfono ni correo (mismo nombre, otros datos).
   Nada se escribe hasta que usted aplica. Al aplicar, el servidor verifica
   cada fila contra la hoja antes de tocarla.
   Por omisión se ARCHIVA («No procede», con nota): no se pierde nada. Borrar
   es una opción aparte, con confirmación escrita.
   ══════════════════════════════════════════════════════════════════════ */
var REP_LOTE_IA = 8, REP_LOTE_APLICAR = 6;
function repIAInicial() { return { corriendo: false, listo: false, vista: 'ia', items: [], filtro: 'todas', modo: 'archivar', omitidas: {}, aviso: '' }; }
var REP_IA = repIAInicial();

function repFichaIA(p) {
  return { fila: p.fila, nombre: p.nombre || '', sinNombre: !!p.sinNombre, telefono: telClave(p.telefono), correo: repCorreo(p.correo),
    etapa: p.etapa || 'Nuevo', programa: p.programa || '', otrosProgramas: p.otrosProgramas || '', alta: p.alta || '', ultimo: p.ultimo || '',
    origen: p.origen || '', campana: p.campana || '', respondio: !!String(p.respondio || '').trim(),
    pregunta: String(p.pregunta || '').slice(0, 220), notas: String(p.notas || '').slice(0, 220), conversacion: String(p.conversacion || '').slice(0, 200) };
}

/* Fichas que se parecen solo por el NOMBRE (sin teléfono ni correo en común). Solo entre fichas que
   no están ya en un grupo por contacto: así ninguna ficha queda en dos grupos a la vez. */
function calcularPosiblesPorNombre() {
  var enGrupo = {};
  GRUPOS_REP.forEach(function (g) { g.fichas.forEach(function (p) { enGrupo[p.fila] = 1; }); });
  var solas = (DATOS.prospectos || []).filter(function (p) {
    return !enGrupo[p.fila] && !p.baja && String(p.etapa || '').trim() !== 'No procede' && !p.sinNombre;
  });
  var vacias = ['de', 'del', 'la', 'las', 'los', 'y', 'e'];
  var tokens = solas.map(function (p) {
    var t = String(p.nombre || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z ]/g, ' ')
      .split(/\s+/).filter(function (x) { return x.length > 1 && vacias.indexOf(x) < 0; });
    var uniq = []; t.forEach(function (x) { if (uniq.indexOf(x) < 0) uniq.push(x); });
    return uniq;
  });
  function contenido(a, b) { return a.every(function (x) { return b.indexOf(x) >= 0; }); }
  var padre = solas.map(function (_, k) { return k; });
  function raiz(x) { while (padre[x] !== x) { padre[x] = padre[padre[x]]; x = padre[x]; } return x; }
  for (var a = 0; a < solas.length; a++) {
    for (var b = a + 1; b < solas.length; b++) {
      var menor = tokens[a].length <= tokens[b].length ? tokens[a] : tokens[b], mayor = menor === tokens[a] ? tokens[b] : tokens[a];
      if (menor.length < 2 || menor.join(' ').length < 9) continue;
      if (contenido(menor, mayor)) { var ra = raiz(a), rb = raiz(b); if (ra !== rb) padre[ra] = rb; }
    }
  }
  var bolsas = {};
  solas.forEach(function (p, k) { (bolsas[raiz(k)] = bolsas[raiz(k)] || []).push(p); });
  var out = [];
  Object.keys(bolsas).forEach(function (r) {
    var g = bolsas[r];
    if (g.length < 2 || g.length > 4) return;   // cadenas largas: casi seguro homónimos, no se proponen
    var orden = g.slice().sort(function (x, y) { return (repPeso(y) - repPeso(x)) || (repRiqueza(y) - repRiqueza(x)) || (repFecha(y.ultimo) - repFecha(x.ultimo)); });
    out.push({ via: 'nombre', fichas: g, queda: orden[0] });
  });
  return out;
}

function repIAGrupos() {
  var lista = [];
  GRUPOS_REP.forEach(function (g) { lista.push({ via: 'contacto', fichas: g.fichas, queda: g.queda }); });
  calcularPosiblesPorNombre().forEach(function (g) { lista.push(g); });
  return lista.map(function (g, id) { return { id: id, via: g.via, fichas: g.fichas.map(repFichaIA), sugerida: g.queda.fila }; });
}

/* La lista que ve el panel puede venir de una copia de hasta 12 horas. Antes de analizar se trae la hoja tal como está AHORA. */
function repRecargarFresco() {
  return new Promise(function (listo) {
    FRESCO = true; cargar();
    var t0 = Date.now();
    (function espera() { if (!CARGANDO || Date.now() - t0 > 150000) { listo(); return; } setTimeout(espera, 300); })();
  });
}
function repIAAnalizar() {
  if (REP_IA.corriendo) return;
  if (REP_CORRIENDO) { alert('Hay una unificación en curso. Espere a que termine.'); return; }
  REP_IA = repIAInicial(); REP_IA.corriendo = true;
  pintarRepetidos();
  var p0 = document.getElementById('repIAProg'); if (p0) { p0.style.display = 'block'; p0.textContent = 'Trayendo la lista actual de la hoja…'; }
  repRecargarFresco().then(repIAAnalizarYa);
}
function repIAAnalizarYa() {
  calcularGruposRepetidos();
  var grupos = repIAGrupos();
  if (!grupos.length) { REP_IA = repIAInicial(); alert('No hay fichas repetidas que revisar.'); pintarRepetidos(); return; }
  REP_IA = repIAInicial(); REP_IA.corriendo = true;
  var items = grupos.map(function (g) { return { id: g.id, via: g.via, fichas: g.fichas, sugerida: g.sugerida, dec: null, sel: false, hecho: false }; });
  var lotes = [], k;
  for (k = 0; k < items.length; k += REP_LOTE_IA) lotes.push(items.slice(k, k + REP_LOTE_IA));
  var hechos = 0, fallidos = 0, li = 0;
  var prog = document.getElementById('repIAProg'), btn = document.getElementById('repIABtn');
  if (btn) btn.disabled = true;
  function avisar(t) { var p2 = document.getElementById('repIAProg'); if (p2) { p2.style.display = 'block'; p2.textContent = t; } }
  function sinAnalisis(lote) {
    lote.forEach(function (it) { it.dec = { id: it.id, misma_persona: 'dudosa', conservar: it.sugerida, programa: '', otrosProgramas: [], confianza: 'baja', razon: 'La IA no pudo revisar este grupo; decídalo a mano.' }; });
  }
  function terminar() {
    items.forEach(function (it) { it.sel = !!(it.dec && it.dec.misma_persona === 'si' && it.dec.confianza === 'alta' && it.via === 'contacto'); });
    REP_IA.items = items; REP_IA.corriendo = false; REP_IA.listo = true; REP_IA.vista = 'ia';
    REP_IA.aviso = fallidos ? fallidos + ' grupo(s) no se pudieron revisar (quedan como «dudosa»).' : '';
    pintarRepetidos();
  }
  function siguiente(reintento) {
    if (li >= lotes.length) { terminar(); return; }
    var lote = lotes[li];
    avisar('La IA está revisando los grupos ' + (li * REP_LOTE_IA + 1) + ' a ' + (li * REP_LOTE_IA + lote.length) + ' de ' + items.length + '…');
    api('repetidos_ia', { pase: PASE, grupos: JSON.stringify(lote.map(function (it) { return { id: it.id, via: it.via, sugerida: it.sugerida, fichas: it.fichas }; })) }).then(function (r) {
      if (r && r.expirado) { REP_IA.corriendo = false; mostrarAcceso('Tu sesión caducó. Vuelve a entrar y repite el análisis.'); return; }
      if (!r || !r.ok) {
        if (!reintento) { setTimeout(function () { siguiente(true); }, 1500); return; }
        if (r && /ANTHROPIC_API_KEY/.test(String(r.error || ''))) { REP_IA.corriendo = false; REP_IA = repIAInicial(); alert(r.error); pintarRepetidos(); return; }
        fallidos += lote.length; sinAnalisis(lote); li++; siguiente(false); return;
      }
      var porId = {}; (r.decisiones || []).forEach(function (d) { porId[String(d.id)] = d; });
      lote.forEach(function (it) { it.dec = porId[String(it.id)] || null; });
      lote.forEach(function (it) { if (!it.dec) { fallidos++; sinAnalisis([it]); } });
      hechos += lote.length; li++; siguiente(false);
    });
  }
  siguiente(false);
}

function repIAFicha(it, fila) { var r = null; it.fichas.forEach(function (f) { if (Number(f.fila) === Number(fila)) r = f; }); return r; }
function repIAEtiqueta(d) {
  if (d.misma_persona === 'no') return ['Personas distintas', '#6B6360'];
  if (d.misma_persona === 'dudosa') return ['Dudosa', '#B07D12'];
  return d.confianza === 'alta' ? ['Misma persona · confianza alta', '#1E7B34'] : d.confianza === 'media' ? ['Misma persona · confianza media', '#B07D12'] : ['Misma persona · confianza baja', '#B51F27'];
}
function repIAVisible(it) {
  if (it.hecho || REP_IA.omitidas[it.id]) return false;
  var d = it.dec, f = REP_IA.filtro;
  if (f === 'todas') return true;
  if (f === 'alta') return d.misma_persona === 'si' && d.confianza === 'alta';
  if (f === 'media') return d.misma_persona === 'si' && d.confianza === 'media';
  if (f === 'revisar') return d.misma_persona === 'dudosa' || (d.misma_persona === 'si' && d.confianza === 'baja');
  if (f === 'no') return d.misma_persona === 'no';
  if (f === 'nombre') return it.via === 'nombre';
  return true;
}
function repIACuentas() {
  var c = { alta: 0, media: 0, revisar: 0, no: 0, nombre: 0, sel: 0, selFichas: 0, total: 0 };
  REP_IA.items.forEach(function (it) {
    if (it.hecho || REP_IA.omitidas[it.id]) return;
    c.total++;
    var d = it.dec;
    if (d.misma_persona === 'si' && d.confianza === 'alta') c.alta++;
    else if (d.misma_persona === 'si' && d.confianza === 'media') c.media++;
    else if (d.misma_persona === 'no') c.no++;
    else c.revisar++;
    if (it.via === 'nombre') c.nombre++;
    if (it.sel && d.misma_persona === 'si') { c.sel++; c.selFichas += it.fichas.length - 1; }
  });
  return c;
}

function repIATarjeta(it) {
  var d = it.dec, q = repIAFicha(it, d.conservar) || it.fichas[0], et = repIAEtiqueta(d), unir = d.misma_persona === 'si';
  var h = '<div class="tarjeta" style="margin-top:10px;border-left:4px solid ' + et[1] + '" data-repia="' + it.id + '">';
  h += '<div style="display:flex;gap:10px;align-items:flex-start">';
  if (unir) h += '<input type="checkbox" data-repiasel="' + it.id + '"' + (it.sel ? ' checked' : '') + ' style="margin-top:5px;transform:scale(1.25)" aria-label="Aplicar">';
  h += '<div style="flex:1"><b>' + ipEsc(q.sinNombre ? ('Sin nombre · ' + q.telefono) : q.nombre) + '</b> · ' + it.fichas.length + ' fichas' +
    (it.via === 'nombre' ? ' · <span style="color:#B07D12">nombre parecido, otro teléfono</span>' : '') +
    ' <span style="display:inline-block;margin-left:6px;font-size:11px;font-weight:700;color:#fff;background:' + et[1] + ';border-radius:99px;padding:1px 9px">' + ipEsc(et[0]) + '</span>';
  h += '<div class="sub" style="margin-top:4px">' + ipEsc(d.razon || '') + '</div>';
  if (unir && (d.programa || (d.otrosProgramas && d.otrosProgramas.length))) {
    h += '<div class="sub"><b>Programa:</b> ' + ipEsc(d.programa || '(sin definir)') + (d.otrosProgramas && d.otrosProgramas.length ? ' · también preguntó por: ' + ipEsc(d.otrosProgramas.join(', ')) : '') + '</div>';
  }
  h += '</div></div>';
  it.fichas.forEach(function (p) {
    var esQ = Number(p.fila) === Number(d.conservar);
    var etq = !unir ? 'Se queda tal cual' : (esQ ? 'SE CONSERVA' : 'Se archiva');
    h += '<div style="display:flex;gap:8px;align-items:flex-start;margin-top:8px;padding:8px;border-radius:8px;border:1px solid ' + (unir && esQ ? 'var(--rojo)' : 'rgba(0,0,0,.12)') + '">' +
      '<div style="font-size:11px;font-weight:700;color:' + (unir && esQ ? 'var(--rojo)' : '#888') + ';min-width:98px">' + etq + '</div>' +
      '<div style="flex:1;font-size:12px;line-height:1.5">' + ipEsc(p.sinNombre ? '(sin nombre)' : p.nombre) + ' · ' + ipEsc(repDescribir({ etapa: p.etapa, programa: p.programa, correo: p.correo, telefono: p.telefono, alta: p.alta, ultimo: p.ultimo }, true)) +
      (p.origen ? '<br><span style="color:#888">' + ipEsc(p.origen) + '</span>' : '') + '</div></div>';
  });
  h += '<div style="margin-top:10px;display:flex;gap:10px;flex-wrap:wrap;align-items:center">';
  if (unir && it.fichas.length > 1) {
    h += '<label style="font-size:12px;color:#6B6360">Conservar otra: <select data-repiaquedar="' + it.id + '" style="font:inherit;font-size:12px;padding:3px 6px">' +
      it.fichas.map(function (p) { return '<option value="' + ipEsc(String(p.fila)) + '"' + (Number(p.fila) === Number(d.conservar) ? ' selected' : '') + '>' + ipEsc((p.sinNombre ? 'Sin nombre' : p.nombre) + ' · ' + (p.etapa || 'Nuevo')) + '</option>'; }).join('') + '</select></label>';
  }
  h += '<button type="button" data-repiaomitir="' + it.id + '">' + (unir ? 'No unir, dejar así' : 'Entendido') + '</button></div></div>';
  return h;
}

function repIAPintar() {
  var c = document.getElementById('v-repetidos'), cu = repIACuentas();
  var resumen = REP_RESUMEN ? '<div class="tarjeta" style="margin-bottom:10px;border-left:4px solid var(--rojo)">' + REP_RESUMEN + '</div>' : '';
  var chips = [['todas', 'Todas (' + cu.total + ')'], ['alta', 'Confianza alta (' + cu.alta + ')'], ['media', 'Confianza media (' + cu.media + ')'], ['revisar', 'Dudosas (' + cu.revisar + ')'], ['no', 'Personas distintas (' + cu.no + ')'], ['nombre', 'Por nombre (' + cu.nombre + ')']];
  var h = resumen + '<div class="tarjeta"><b>La IA revisó ' + cu.total + ' grupo(s)</b>' +
    '<div class="sub">Marcados quedaron los de confianza alta que comparten teléfono o correo. Los de confianza media o baja y los de nombre parecido <b>no</b> vienen marcados: revíselos y márquelos usted. Nada cambia hasta que presione «Aplicar».' +
    (REP_IA.aviso ? '<br><span style="color:var(--rojo)">' + ipEsc(REP_IA.aviso) + '</span>' : '') + '</div>' +
    '<div style="margin-top:10px;display:flex;gap:6px;flex-wrap:wrap">' + chips.map(function (x) { return '<button type="button" class="' + (REP_IA.filtro === x[0] ? 'pri' : '') + '" data-repiafiltro="' + x[0] + '">' + ipEsc(x[1]) + '</button>'; }).join('') + '</div>' +
    '<div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap">' +
    '<button type="button" data-repiaacc="todasalta">Marcar todas las de confianza alta</button>' +
    '<button type="button" data-repiaacc="ninguna">Quitar todas las marcas</button>' +
    '<button type="button" data-repiaacc="manual">Ver el modo manual</button>' +
    '<button type="button" data-repiaacc="reanalizar">Volver a analizar</button></div>' +
    '<div style="margin-top:14px;padding:12px;border-radius:10px;background:var(--hueso)">' +
    '<div style="font-weight:700;margin-bottom:6px">Qué hacer con las fichas repetidas que sobran</div>' +
    '<label style="display:block;font-size:13px;margin-bottom:4px"><input type="radio" name="repModo" value="archivar"' + (REP_IA.modo === 'archivar' ? ' checked' : '') + '> <b>Archivarlas</b> en «No procede», con nota de a cuál se fusionaron. <span style="color:#1E7B34">Recomendado: no se pierde nada</span> y se conserva el origen y la campaña de cada una para medir.</label>' +
    '<label style="display:block;font-size:13px"><input type="radio" name="repModo" value="borrar"' + (REP_IA.modo === 'borrar' ? ' checked' : '') + '> <b>Borrarlas de la hoja</b>. <span style="color:var(--rojo)">Irreversible.</span> Se pide confirmación escrita, dejan constancia en la bitácora y sus teléfonos y correos quedan anotados en la ficha que se conserva. Las «Inscrito», las «Documentos en proceso» y las de nombre parecido nunca se borran: se archivan.</label></div>' +
    '<div style="margin-top:12px"><button type="button" class="pri" id="repIAAplicar"' + (cu.sel ? '' : ' disabled') + '>Aplicar las ' + cu.sel + ' marcadas (' + cu.selFichas + ' ficha(s) sobrante(s))</button></div>' +
    '<div id="repIAAvance" style="margin-top:10px;font-weight:700;display:none"></div></div>';
  var vis = REP_IA.items.filter(repIAVisible);
  if (!vis.length) h += '<div class="tarjeta" style="margin-top:10px">No hay grupos con este filtro.</div>';
  vis.forEach(function (it) { h += repIATarjeta(it); });
  c.innerHTML = h;
  repIAEnlazar(c);
}

function repIAEnlazar(c) {
  Array.prototype.forEach.call(c.querySelectorAll('[data-repiafiltro]'), function (b) { b.onclick = function () { REP_IA.filtro = b.getAttribute('data-repiafiltro'); repIAPintar(); }; });
  Array.prototype.forEach.call(c.querySelectorAll('[data-repiasel]'), function (b) { b.onchange = function () { REP_IA.items[Number(b.getAttribute('data-repiasel'))].sel = b.checked; repIARefrescarBoton(); }; });
  Array.prototype.forEach.call(c.querySelectorAll('[data-repiaquedar]'), function (b) {
    b.onchange = function () { var it = REP_IA.items[Number(b.getAttribute('data-repiaquedar'))]; it.dec.conservar = Number(b.value); it.dec.razon = (it.dec.razon || '') + ' (Usted eligió cuál conservar.)'; repIAPintar(); };
  });
  Array.prototype.forEach.call(c.querySelectorAll('[data-repiaomitir]'), function (b) { b.onclick = function () { var id = Number(b.getAttribute('data-repiaomitir')); REP_IA.omitidas[id] = true; REP_IA.items[id].sel = false; repIAPintar(); }; });
  Array.prototype.forEach.call(c.querySelectorAll('input[name="repModo"]'), function (b) { b.onchange = function () { REP_IA.modo = b.value; }; });
  Array.prototype.forEach.call(c.querySelectorAll('[data-repiaacc]'), function (b) {
    b.onclick = function () {
      var a = b.getAttribute('data-repiaacc');
      if (a === 'todasalta') { REP_IA.items.forEach(function (it) { if (!it.hecho && it.dec.misma_persona === 'si' && it.dec.confianza === 'alta' && it.via === 'contacto') it.sel = true; }); repIAPintar(); }
      else if (a === 'ninguna') { REP_IA.items.forEach(function (it) { it.sel = false; }); repIAPintar(); }
      else if (a === 'manual') { REP_IA.vista = 'manual'; pintarRepetidos(); }
      else if (a === 'reanalizar') { if (confirm('Se descartan las decisiones actuales y la IA vuelve a revisar todo. ¿Continuar?')) { REP_IA = repIAInicial(); pintarRepetidos(); repIAAnalizar(); } }
    };
  });
  var ap = document.getElementById('repIAAplicar'); if (ap) ap.onclick = repIAAplicar;
}
function repIARefrescarBoton() {
  var cu = repIACuentas(), ap = document.getElementById('repIAAplicar');
  if (!ap) return;
  ap.disabled = !cu.sel;
  ap.textContent = 'Aplicar las ' + cu.sel + ' marcadas (' + cu.selFichas + ' ficha(s) sobrante(s))';
}

/* La fila es solo una PISTA (la lista puede tener horas de antigüedad y la hoja puede haber cambiado de orden): el servidor localiza
   cada ficha por su teléfono, correo y nombre, y desempata por fecha de alta y origen. */
function repIAIdent(f) { return { fila: Number(f.fila), tel: f.telefono || '', correo: f.correo || '', nombre: f.sinNombre ? '' : (f.nombre || ''), alta: f.alta || '', origen: f.origen || '' }; }
function repIAPayload(it) {
  var d = it.dec, q = repIAFicha(it, d.conservar);
  return { id: it.id, via: it.via, nombre: q.sinNombre ? '' : q.nombre, confianza: d.confianza, razon: String(d.razon || '').slice(0, 160),
    programa: d.programa || '', otrosProgramas: d.otrosProgramas || [],
    conservar: repIAIdent(q), archivar: it.fichas.filter(function (f) { return Number(f.fila) !== Number(d.conservar); }).map(repIAIdent) };
}

function repIAAplicar() {
  if (REP_CORRIENDO || REP_IA.corriendo) { alert('Hay una operación en curso. Espere a que termine.'); return; }
  /* Una omitida NUNCA se aplica, aunque siguiera marcada. */
  var elegidas = REP_IA.items.filter(function (it) { return it.sel && !it.hecho && !REP_IA.omitidas[it.id] && it.dec.misma_persona === 'si'; });
  if (!elegidas.length) return;
  var sobran = elegidas.reduce(function (a, it) { return a + it.fichas.length - 1; }, 0), modo = REP_IA.modo, confirmar = '';
  var nombres = elegidas.slice(0, 5).map(function (it) { var q = repIAFicha(it, it.dec.conservar); return '  · ' + (q.sinNombre ? 'Sin nombre · ' + q.telefono : q.nombre); }).join('\n');
  if (modo === 'borrar') {
    var borrables = elegidas.filter(function (it) { return it.via === 'contacto'; }).length;
    var t = prompt('VA A BORRAR DE LA HOJA fichas repetidas de ' + elegidas.length + ' persona(s) (hasta ' + sobran + ' ficha(s)).\n\n' + nombres +
      (elegidas.length > 5 ? '\n  · y ' + (elegidas.length - 5) + ' más' : '') +
      '\n\nEsto NO se puede deshacer. Se perderá el origen y la campaña de cada ficha borrada (sus teléfonos y correos quedan anotados en la que se conserva). ' +
      'Las «Inscrito», «Documentos en proceso» y las de nombre parecido se archivan en vez de borrarse.\n\nPara continuar escriba BORRAR:', '');
    if (t !== 'BORRAR') { if (t !== null) alert('No se escribió BORRAR: no se hizo nada.'); return; }
    confirmar = 'BORRAR';
  } else if (!confirm('¿Unificar ' + elegidas.length + ' persona(s)?\n\n' + nombres + (elegidas.length > 5 ? '\n  · y ' + (elegidas.length - 5) + ' más' : '') +
    '\n\nSe conserva una ficha por persona y las otras ' + sobran + ' quedan en «No procede», con nota. Nada se borra.')) return;

  REP_CORRIENDO = true;
  var vista = document.getElementById('v-repetidos');
  Array.prototype.forEach.call(vista.querySelectorAll('button, input, select'), function (b) { b.disabled = true; });
  var av = document.getElementById('repIAAvance'); if (av) av.style.display = 'block';
  function avisar(t) { var a2 = document.getElementById('repIAAvance'); if (a2) a2.textContent = t; var cuenta = document.getElementById('cuenta'); if (cuenta) cuenta.textContent = t; }
  var lotes = [], k;
  for (k = 0; k < elegidas.length; k += REP_LOTE_APLICAR) lotes.push(elegidas.slice(k, k + REP_LOTE_APLICAR));
  var li = 0, ok = 0, arch = 0, borr = 0, mov = 0, saltadas = [], notas = [];
  function fin(cortado) {
    REP_CORRIENDO = false;
    REP_RESUMEN = '<b>' + (cortado ? 'Se interrumpió' : 'Unificación con IA terminada') + '</b><div class="sub">' + ok + ' persona(s) unificada(s) · ' + arch + ' ficha(s) archivada(s)' + (borr ? ' · ' + borr + ' ficha(s) borrada(s)' : '') +
      (saltadas.length ? ' · <span style="color:var(--rojo)">' + saltadas.length + ' no se aplicaron</span>' : '') + '</div>' +
      (notas.length ? '<div class="sub" style="margin-top:6px">' + notas.map(ipEsc).join('<br>') + '</div>' : '') +
      (mov ? '<div class="sub" style="margin-top:6px">La hoja había cambiado de orden desde que se cargó la lista: <b>' + mov + '</b> persona(s) se localizaron por sus datos y se aplicaron bien.</div>' : '') +
      (saltadas.length ? '<div class="sub" style="margin-top:6px;color:var(--rojo)"><b>No se aplicaron ' + saltadas.length + '</b> (nada se tocó en esas; cada una dice por qué). Pulse «Analizar» otra vez: ahora trae la lista fresca de la hoja antes de revisar.<br>' + saltadas.map(ipEsc).join('<br>') + '</div>' : '');
    if (modo === 'borrar') { REP_IA = repIAInicial(); }   // al borrar filas, los números de fila cambian: hay que volver a analizar
    else { REP_IA.items.forEach(function (it) { if (it._ok) it.hecho = true; }); }
    alert((cortado ? 'Se interrumpió. ' : 'Listo. ') + ok + ' persona(s) unificada(s), ' + arch + ' archivada(s)' + (borr ? ', ' + borr + ' borrada(s)' : '') + (saltadas.length ? '; ' + saltadas.length + ' no se aplicaron.' : '.'));
    FRESCO = true; cargar();
  }
  function siguiente() {
    if (li >= lotes.length) { fin(false); return; }
    var lote = lotes[li];
    avisar('Aplicando ' + (li * REP_LOTE_APLICAR + 1) + ' a ' + (li * REP_LOTE_APLICAR + lote.length) + ' de ' + elegidas.length + '…');
    apiEscribir('repetidos_aplicar', { pase: PASE, modo: modo, confirmar: confirmar, decisiones: JSON.stringify(lote.map(repIAPayload)) }).then(function (r) {
      if (r && r.expirado) { REP_CORRIENDO = false; mostrarAcceso('Tu sesión caducó. Vuelve a entrar: lo ya aplicado se conserva y el análisis puede repetirse.'); return; }
      if (!r || !r.ok) { saltadas = saltadas.concat(lote.map(function (it) { return repIAFicha(it, it.dec.conservar).nombre || '(sin nombre)'; })); notas.push((r && r.error) || 'La petición falló.'); li++; siguiente(); return; }
      (r.resultados || []).forEach(function (x, n) {
        var it = lote[n];
        if (x.ok) { ok++; it._ok = true; if (x.movida) mov++; }
        else saltadas.push((x.nombre || '(sin nombre)') + ' — ' + (x.motivo || 'sin detalle'));
        if (x.ok && x.motivo && x.motivo !== 'Ya estaba unificada.') notas.push((x.nombre || '(sin nombre)') + ': ' + x.motivo);
      });
      arch += r.archivadas || 0; borr += r.borradas || 0;
      li++; siguiente();
    });
  }
  siguiente();
}

/* La tarjeta de arriba, en el modo manual: ahí vive el botón que arranca el análisis. */
function repIACajaHtml() {
  var n = repIAGrupos().length;
  if (REP_IA.corriendo) return '<div class="tarjeta" style="border-left:4px solid var(--oro)"><b>La IA está revisando…</b><div id="repIAProg" style="margin-top:8px;font-weight:700"></div></div>';
  var h = '<div class="tarjeta" style="border-left:4px solid var(--oro)"><b>Decidir con IA</b>' +
    '<div class="sub">La IA revisa los ' + n + ' grupo(s), <b>también los que traen conflicto</b>, y propone: si de verdad son la misma persona (un teléfono compartido por una pareja o por madre e hija <b>no</b> lo son), cuál ficha conservar y qué programa es el suyo. ' +
    'Además busca repetidos que la lista no ve porque no comparten teléfono ni correo. No cambia nada hasta que usted aplique, y al aplicar se verifica cada fila contra la hoja.</div>' +
    '<div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap"><button type="button" class="pri" id="repIABtn">Analizar los ' + n + ' grupo(s) con IA</button>' +
    (REP_IA.listo ? '<button type="button" id="repIAVolver">Volver a la revisión con IA</button>' : '') + '</div>' +
    '<div id="repIAProg" style="margin-top:8px;font-weight:700;display:none"></div></div>';
  return h;
}


/* ══════════════════════════════════════════════════════════════════════
   (28-sep) WHATSAPP CON IA Y CONVERSACIÓN AL DÍA
   ──────────────────────────────────────────────────────────────────────
   1. Todos los botones de WhatsApp abren UN mismo diálogo: la IA redacta el
      mensaje leyendo la ficha y lo MÁS RECIENTE de la conversación; queda
      editable; muestra alertas si menciona una cifra o fecha que no está en
      la información oficial; y solo entonces abre WhatsApp.
   2. Al abrir WhatsApp, la persona queda «por actualizar». Cuando usted vuelve
      al panel, el panel le pide pegar la conversación: la IA la lee y propone
      qué cambiar (resumen, si contestó, etapa, programa, lo que sigue). Usted
      revisa y guarda. Con eso, el siguiente mensaje ya sabe qué se dijo.
   3. Una barra al pie recuerda a quién le falta, aunque cierre el panel: la
      hoja sabe a quién se le escribió y cuándo se actualizó su conversación.
   La IA solo propone; lo que se envía y lo que se guarda lo decide una persona.
   ══════════════════════════════════════════════════════════════════════ */
var WA = null, WA2 = null, WA_ESPERA = [], WA_PREGUNTADO = {}, WA_OCULTA = false, WA_ULTIMO = 0, WA_YA = {};
try { WA_ESPERA = JSON.parse(sessionStorage.getItem('cessum_wa_espera') || '[]'); if (!Array.isArray(WA_ESPERA)) WA_ESPERA = []; } catch (eE) { WA_ESPERA = []; }
function waGuardarEspera() { try { sessionStorage.setItem('cessum_wa_espera', JSON.stringify(WA_ESPERA)); } catch (e) {} }
function waProsp(fila) { var r = null; ((DATOS && DATOS.prospectos) || []).forEach(function (p) { if (String(p.fila) === String(fila)) r = p; }); return r; }
function waTel(p) { return String((p && p.telefono) || '').replace(/\D/g, '').slice(-10); }
function waLink(p, msg) { return 'https://wa.me/52' + waTel(p) + (msg ? '?text=' + encodeURIComponent(msg) : ''); }
function waDlg() { return document.getElementById('waDlg'); }
function waAbierto() { var d = waDlg(); return !!(d && d.hasAttribute('open')); }
function waMostrar(tit, sub) {
  /* Se vacía el contenido anterior: si no, la caja de pegar conservaba lo de la persona ANTERIOR y podía guardarse en la ficha equivocada. */
  document.getElementById('waCont').innerHTML = '';
  document.getElementById('waTit').textContent = tit; document.getElementById('waSub').textContent = sub || '';
  var d = waDlg(); if (!d.hasAttribute('open')) d.showModal();
}
function waCerrar() { var d = waDlg(); if (d && d.hasAttribute('open')) d.close(); }
function waPeso(e) { return ({ 'Inscrito': 5, 'Documentos en proceso': 4, 'Interesado': 3, 'Contactado': 2, 'Nuevo': 1, 'No procede': 0 })[String(e || 'Nuevo')] || 0; }
function waExpirada(r) { if (r && r.expirado) { waCerrar(); mostrarAcceso('Tu sesión caducó.'); return true; } return false; }

/* ───────────── 1. ESCRIBIR ───────────── */
function waAbrirIA(p, enfocar) {
  if (!p || !waTel(p)) { alert('Esta ficha no tiene teléfono.'); return; }
  WA = { p: p, fila: p.fila, cargando: true, error: '', borrador: '', breve: '', vista: 'completo', objetivo: '', porque: '', alertas: [], conv: null, indicacion: '', plantilla: false };
  waMostrar('WhatsApp · ' + (p.sinNombre ? ('Sin nombre · ' + waTel(p)) : p.nombre), 'La IA lee la ficha y la conversación y redacta el mensaje. Usted lo revisa antes de enviarlo.');
  waPintarEscribir();
  waRedactar();
  if (enfocar) setTimeout(function () { var i = document.getElementById('waInd'); if (i) i.focus(); }, 30);
}
function waEstadoConv() {
  var p = WA.p, c = WA.conv, hay = c ? c.hay : !!String(p.conversacion || '').trim();
  var pend = c ? c.pendiente : !!p.convPendiente, act = (c && c.actualizada) || p.convAct || '';
  if (!hay) return { clase: 'aviso', txt: 'No hay conversación guardada: el mensaje será más general. Si ya habló con esta persona, pegue la conversación primero.', btn: 'Pegar conversación' };
  if (pend) return { clase: 'aviso', txt: 'Ya se le escribió y la conversación no se ha actualizado desde entonces: el mensaje podría repetir algo que ya se dijo.', btn: 'Actualizarla primero' };
  return { clase: 'ok', txt: 'Conversación guardada' + (act ? ' · actualizada el ' + act : '') + '. La IA leyó lo más reciente.', btn: 'Actualizar' };
}
function waPintarEscribir() {
  var p = WA.p, c = document.getElementById('waCont'), e = waEstadoConv();
  var indPrev = document.getElementById('waInd') ? document.getElementById('waInd').value : WA.indicacion;
  var h = '<div class="wa-ctx"><span class="wa-chip">' + esc(p.etapa || 'Nuevo') + '</span><span class="wa-chip">' + esc(p.programa || 'programa sin definir') + '</span>' +
    '<span class="wa-chip">' + (p.dias === null || p.dias === undefined ? '?' : esc(String(p.dias))) + ' d sin moverse</span>' + (p.respondio ? '<span class="wa-chip">ya contestó</span>' : '<span class="wa-chip">sin respuesta</span>') + '</div>' +
    '<div class="wa-conv ' + e.clase + '"><span>' + esc(e.txt) + '</span><button type="button" class="wa-b" data-wa="actualizar">' + esc(e.btn) + '</button></div>' +
    '<label for="waInd">¿Quiere pedirle algo en particular a la IA? (opcional)</label>' +
    '<input type="text" id="waInd" placeholder="Ej.: pregúntele si ya tiene sus documentos" maxlength="300">';
  if (WA.cargando) h += '<div class="wa-cargando">La IA está redactando…</div>';
  else {
    if (WA.error) h += '<p class="wa-err">' + esc(WA.error) + '</p>';
    if (WA.borrador || WA.breve) {
      h += '<div class="wa-tabs"><button type="button" data-wa="vista" data-v="completo" class="' + (WA.vista === 'completo' ? 'on' : '') + '">Completo</button>' +
        (WA.breve ? '<button type="button" data-wa="vista" data-v="breve" class="' + (WA.vista === 'breve' ? 'on' : '') + '">Breve</button>' : '') + '</div>' +
        '<textarea id="waTxt" aria-label="Mensaje"></textarea>';
      if (WA.plantilla) h += '<p class="wa-meta">Es la plantilla de siempre. Puede editarla.</p>';
      else if (WA.objetivo || WA.porque) h += '<p class="wa-meta"><b>Objetivo:</b> ' + esc(WA.objetivo || '—') + (WA.porque ? ' · <b>Por qué:</b> ' + esc(WA.porque) : '') + '</p>';
      if (WA.alertas && WA.alertas.length) h += '<div class="wa-alertas"><b>Revise antes de enviar:</b><br>' + WA.alertas.map(esc).join('<br>') + '</div>';
      h += '<p class="wa-meta">Es un borrador: lo que se envía es lo que quede en la caja.</p>';
    }
  }
  h += '<div class="wa-acc"><button type="button" class="wa-b wa-izq" data-wa="plantilla"' + (p.mensaje ? '' : ' disabled') + '>Usar la plantilla de siempre</button>' +
    '<button type="button" class="wa-b" data-wa="regenerar"' + (WA.cargando ? ' disabled' : '') + '>Volver a redactar</button>' +
    '<button type="button" class="wa-b" data-wa="copiar"' + (WA.borrador || WA.breve ? '' : ' disabled') + '>Copiar</button>' +
    '<button type="button" class="wa-b verde" data-wa="enviar"' + (WA.borrador || WA.breve ? '' : ' disabled') + '>Abrir WhatsApp con este texto</button></div>';
  c.innerHTML = h;
  document.getElementById('waInd').value = indPrev || '';
  var ta = document.getElementById('waTxt'); if (ta) ta.value = WA.vista === 'breve' ? WA.breve : WA.borrador;
  if (ta) ta.addEventListener('input', function () { if (WA.vista === 'breve') WA.breve = ta.value; else WA.borrador = ta.value; });
  Array.prototype.forEach.call(c.querySelectorAll('[data-wa]'), function (b) { b.onclick = waClicEscribir; });
}
function waRedactar() {
  WA.cargando = true; WA.error = '';
  var ind = document.getElementById('waInd'); WA.indicacion = ind ? ind.value.trim() : WA.indicacion;
  waPintarEscribir();
  var fila = WA.fila;
  api('redactar', { pase: PASE, fila: String(fila), indicacion: WA.indicacion || '' }).then(function (r) {
    if (!WA || WA.fila !== fila) return;
    if (waExpirada(r)) return;
    WA.cargando = false;
    if (!r || !r.ok) { WA.error = (r && r.error) || 'No se pudo redactar. Puede usar la plantilla de siempre.'; waPintarEscribir(); return; }
    WA.borrador = r.mensaje || ''; WA.breve = r.breve || ''; WA.objetivo = r.objetivo || ''; WA.porque = r.porque || '';
    WA.alertas = r.alertas || []; WA.conv = r.conversacion || null; WA.vista = 'completo'; WA.plantilla = false;
    waPintarEscribir();
  });
}
function waClicEscribir(ev) {
  var b = ev.currentTarget, a = b.getAttribute('data-wa');
  if (a === 'vista') { WA.vista = b.getAttribute('data-v'); waPintarEscribir(); }
  else if (a === 'regenerar') waRedactar();
  else if (a === 'plantilla') { WA.borrador = WA.p.mensaje || ''; WA.breve = ''; WA.vista = 'completo'; WA.alertas = []; WA.plantilla = true; waPintarEscribir(); }
  else if (a === 'copiar') { var t = document.getElementById('waTxt'); if (t) copiar(t.value, 'Copiado. Pégalo en WhatsApp.'); }
  else if (a === 'actualizar') { var f = WA.fila; waActualizar(f); }
  else if (a === 'enviar') waEnviar();
}
function waEnviar() {
  var p = WA.p, ta = document.getElementById('waTxt'), txt = ta ? ta.value.trim() : '';
  if (!txt) { alert('El mensaje está vacío.'); return; }
  /* Se abre en el mismo clic (los bloqueadores de ventanas lo permiten) y se anota el envío sin esperar. */
  window.open(waLink(p, txt), '_blank');
  WA_ULTIMO = Date.now();
  apiEscribir('whatsapp', { pase: PASE, fila: p.fila }).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) { alert('Se abrió WhatsApp, pero no se pudo anotar el envío en la ficha: ' + ((r && r.error) || 'sin respuesta del servidor') + '. Vuelva a abrirlo desde la ficha para dejarlo registrado.'); return; }
    localWhatsapp(p, r); cargar();
  });
  waEsperar(p.fila);
  waCerrar();
}
function waEsperar(fila) {
  if (WA_ESPERA.indexOf(String(fila)) < 0) WA_ESPERA.push(String(fila));
  WA_PREGUNTADO[fila] = false; WA_OCULTA = false; delete WA_YA[fila];
  waGuardarEspera(); waBarraPintar();
}

/* ───────────── 2. ACTUALIZAR LA CONVERSACIÓN ───────────── */
function waActualizar(fila, alRegresar) {
  var p = waProsp(fila);
  if (!p) return;
  WA2 = { p: p, fila: p.fila, guardada: '', cargada: false, texto: '', agregar: false, propuesta: null, cargando: false, error: '', alRegresar: !!alRegresar };
  waMostrar('Actualizar la conversación · ' + (p.sinNombre ? ('Sin nombre · ' + waTel(p)) : p.nombre),
    alRegresar ? 'Acaba de escribirle. Pegue lo que hablaron para que la ficha y el próximo mensaje lo tengan en cuenta.' : 'Con esto la ficha y el próximo mensaje saben qué se dijo.');
  waPintarPegar();
  var f = p.fila;
  api('chat', { pase: PASE, fila: String(f) }).then(function (r) {
    if (!WA2 || WA2.fila !== f) return;
    if (waExpirada(r)) return;
    WA2.guardada = (r && r.ok) ? String(r.conversacion || '') : ''; WA2.cargada = true;
    if (!WA2.propuesta) waPintarPegar();
  });
}
function waPintarPegar() {
  var p = WA2.p, c = document.getElementById('waCont'), prev = document.getElementById('waPeg') ? document.getElementById('waPeg').value : WA2.texto;
  var g = WA2.guardada, h = '<p class="wa-ayuda">Abra el chat con <b>' + esc(p.sinNombre ? 'esta persona' : p.nombre) + '</b> en WhatsApp, seleccione la conversación, cópiela y péguela aquí.</p>';
  if (!WA2.cargada) h += '<div class="wa-guardada">Buscando lo que hay guardado…</div>';
  else if (g) h += '<div class="wa-guardada">Lo último que tengo guardado (' + g.length + ' letras' + (p.convAct ? ', actualizada el ' + esc(p.convAct) : '') + '):\n…' + esc(g.slice(-260)) + '</div>';
  else h += '<div class="wa-guardada">Todavía no hay conversación guardada de esta persona.</div>';
  h += '<textarea id="waPeg" class="wa-grande" placeholder="Pegue aquí la conversación de WhatsApp…"></textarea>';
  if (g) h += '<label class="wa-chk"><input type="checkbox" id="waAgregar"' + (WA2.agregar ? ' checked' : '') + '> Pegué solo lo nuevo: agregarlo al final de lo que ya está guardado</label><p class="wa-hint" id="waHint"></p>';
  if (WA2.error) h += '<p class="wa-err">' + esc(WA2.error) + '</p>';
  h += '<div class="wa-acc"><button type="button" class="wa-b wa-izq" data-wa2="mastarde">Más tarde</button>' +
    '<button type="button" class="wa-b" data-wa2="sinia"' + (WA2.cargando ? ' disabled' : '') + '>Guardar sin IA</button>' +
    '<button type="button" class="wa-b pri" data-wa2="leer"' + (WA2.cargando ? ' disabled' : '') + '>' + (WA2.cargando ? 'Leyendo…' : 'Leer con IA') + '</button></div>';
  c.innerHTML = h;
  var ta = document.getElementById('waPeg'); ta.value = prev || '';
  ta.addEventListener('input', function () { WA2.texto = ta.value; waSugerirAgregar(); });
  var ag = document.getElementById('waAgregar'); if (ag) ag.addEventListener('change', function () { WA2.agregar = ag.checked; });
  Array.prototype.forEach.call(c.querySelectorAll('[data-wa2]'), function (b) { b.onclick = waClicPegar; });
  waSugerirAgregar();
}
/* ¿Pegó todo el hilo o solo lo nuevo? Si lo pegado ya contiene el final de lo guardado, es el hilo completo (se reemplaza);
   si es bastante más corto y no lo contiene, probablemente es solo lo nuevo (se agrega). */
function waSugerirAgregar() {
  var ag = document.getElementById('waAgregar'), hint = document.getElementById('waHint'), g = WA2.guardada, t = (document.getElementById('waPeg') || {}).value || '';
  if (!ag || !g || t.length < 20) { if (hint) hint.textContent = ''; return; }
  var g2 = g.trim(), cola = g2.slice(-80).trim(), contiene = g2.length >= 5 && t.indexOf(cola) >= 0;   // con lo guardado muy corto, se busca el texto completo
  if (contiene) { ag.checked = false; WA2.agregar = false; hint.textContent = 'Parece el hilo completo: reemplazará lo guardado.'; }
  else { ag.checked = true; WA2.agregar = true; hint.textContent = 'No encuentro el final de lo guardado en lo que pegó: se agregará al final, sin borrar nada. Si pegó el hilo completo, desmarque la casilla.'; }
}
function waClicPegar(ev) {
  var a = ev.currentTarget.getAttribute('data-wa2'), t = (document.getElementById('waPeg') || {}).value || '';
  WA2.texto = t;
  if (a === 'mastarde') { WA_PREGUNTADO[WA2.fila] = true; waCerrar(); waBarraPintar(); return; }
  if (a === 'sinia') { if (t.trim().length < 20) { WA2.error = 'Pegue la conversación (está vacía o es muy corta).'; waPintarPegar(); return; } waGuardarConv(null); return; }
  if (a === 'leer') {
    if (t.trim().length < 20) { WA2.error = 'Pegue la conversación (está vacía o es muy corta).'; waPintarPegar(); return; }
    WA2.error = ''; WA2.cargando = true; waPintarPegar();
    var f = WA2.fila;
    api('conv_leer', { pase: PASE, fila: String(f), texto: t }).then(function (r) {
      if (!WA2 || WA2.fila !== f) return;
      if (waExpirada(r)) return;
      WA2.cargando = false;
      if (!r || !r.ok) { WA2.error = (r && r.error) || 'La IA no pudo leerla. Puede guardarla sin IA.'; waPintarPegar(); return; }
      WA2.propuesta = r.propuesta; WA2.actual = r.actual; waPintarRevisar();
    });
  }
}
var WA_ETAPAS_LISTA = ['Nuevo', 'Contactado', 'Interesado', 'Documentos en proceso', 'Inscrito', 'No procede'];
function waPintarRevisar() {
  var p = WA2.p, pr = WA2.propuesta, act = WA2.actual || { etapa: p.etapa, programa: p.programa }, c = document.getElementById('waCont');
  var etapaActual = String(act.etapa || p.etapa || 'Nuevo');
  var sug = pr.etapa && pr.etapa !== etapaActual ? pr.etapa : '';
  var pre = (sug && waPeso(sug) > waPeso(etapaActual) && sug !== 'Inscrito' && sug !== 'No procede') ? sug : etapaActual;
  var yaResp = (act.respondio !== undefined) ? !!act.respondio : !!p.respondio;   // lo que dice la hoja EN VIVO, no la copia del panel
  var progCambia = pr.programa && pr.programa !== (act.programa || '');
  var progPre = progCambia && (!act.programa || /general/i.test(act.programa));
  var h = '<p class="wa-ayuda">La IA leyó la conversación y propone esto. <b>Revise y corrija</b>: solo se guarda lo que usted deje aquí.</p>' +
    '<div class="wa-info">' + (pr.ultimoMensajeDe === 'persona' ? '<b>El último mensaje es de la persona: está esperando respuesta.</b>' : pr.ultimoMensajeDe === 'cessum' ? 'El último mensaje es de CESSUM: se espera su respuesta.' : 'No se distingue de quién es el último mensaje.') +
    (pr.preguntaPendiente ? '<br><b>Pregunta pendiente:</b> ' + esc(pr.preguntaPendiente) : '') + (pr.objecion && pr.objecion !== 'ninguna' ? '<br><b>Lo que la frena:</b> ' + esc(pr.objecion) : '') +
    (pr.nombre && p.sinNombre ? '<br><b>Su nombre parece ser:</b> ' + esc(pr.nombre) : '') + '</div>' +
    '<label for="waResumen">Resumen (se guarda como nota de la ficha)</label><textarea id="waResumen" class="wa-peq"></textarea>' +
    '<label class="wa-chk"><input type="checkbox" id="waContesto"' + ((pr.contesto && !yaResp) ? ' checked' : '') + (yaResp ? ' disabled' : '') + '> La persona contestó' + (yaResp ? ' (ya estaba registrado)' : '') + '</label>' +
    '<label for="waEtapa">Etapa' + (sug ? '<button type="button" class="wa-sug" data-wa3="usaretapa" data-e="' + esc(sug) + '" title="' + esc(pr.motivoEtapa || '') + '">La IA sugiere «' + esc(sug) + '»</button>' : '') + '</label>' +
    '<select id="waEtapa">' + WA_ETAPAS_LISTA.map(function (e) { return '<option' + (e === pre ? ' selected' : '') + '>' + esc(e) + '</option>'; }).join('') + '</select>' +
    (sug && pre === sug ? '<p class="wa-hint">La IA propone pasarla a «' + esc(sug) + '»' + (pr.motivoEtapa ? ': ' + esc(pr.motivoEtapa) : '.') + ' Puede cambiarla.</p>' : '') +
    (sug && pre !== sug ? '<p class="wa-hint">' + esc(pr.motivoEtapa || '') + ' Un cambio a «' + esc(sug) + '» afecta las cifras: confírmelo usted.</p>' : '') +
    (progCambia ? '<label class="wa-chk"><input type="checkbox" id="waProg"' + (progPre ? ' checked' : '') + '> Cambiar el programa de «' + esc(act.programa || 'sin definir') + '» a «' + esc(pr.programa) + '»</label>' : '') +
    '<label for="waProx">Lo que sigue</label><textarea id="waProx" class="wa-peq" placeholder="Qué hay que hacer y cuándo"></textarea>' +
    '<div class="wa-acc"><button type="button" class="wa-b wa-izq" data-wa3="volver">Volver</button><button type="button" class="wa-b pri" data-wa3="guardar">Guardar todo</button></div>';
  c.innerHTML = h;
  document.getElementById('waResumen').value = pr.resumen || '';
  document.getElementById('waProx').value = pr.siguientePaso || p.proxima || '';
  Array.prototype.forEach.call(c.querySelectorAll('[data-wa3]'), function (b) {
    b.onclick = function () {
      var a = b.getAttribute('data-wa3');
      if (a === 'volver') { WA2.propuesta = null; waPintarPegar(); }
      else if (a === 'usaretapa') { document.getElementById('waEtapa').value = b.getAttribute('data-e'); }
      else if (a === 'guardar') waGuardarConv(true);
    };
  });
}
function waGuardarConv(conIA) {
  var p = WA2.p, fila = WA2.fila, t = WA2.texto.trim(), c = { fila: Number(fila) };
  if (WA2.agregar && WA2.guardada) c.conversacionAgregar = t; else c.conversacion = t;
  var loc = { convAct: hoyDMA(), convPendiente: false };
  if (conIA) {
    var resumen = document.getElementById('waResumen').value.trim(), et = document.getElementById('waEtapa').value, prox = document.getElementById('waProx').value.trim();
    var cont = document.getElementById('waContesto'), prog = document.getElementById('waProg');
    if (resumen) c.nota = 'Conversación actualizada: ' + resumen;
    if (cont && cont.checked && !cont.disabled) c.respondio = true;
    if (et && et !== (WA2.actual ? WA2.actual.etapa : p.etapa)) c.etapa = et;
    if (prog && prog.checked && WA2.propuesta.programa) c.programa = WA2.propuesta.programa;
    if (prox !== String(p.proxima || '')) { c.proxima = prox; loc.proxima = prox; }
  }
  var btns = document.querySelectorAll('#waCont button'); Array.prototype.forEach.call(btns, function (b) { b.disabled = true; });
  apiEscribir('guardar', { pase: PASE, cambios: JSON.stringify(c) }).then(function (r) {
    if (waExpirada(r)) return;
    if (!r || !r.ok) { Array.prototype.forEach.call(btns, function (b) { b.disabled = false; }); alert('No se pudo guardar: ' + ((r && r.error) || 'sin respuesta del servidor') + '. Vuelva a intentarlo.'); return; }
    var l = cambiosLocales(c); for (var k in loc) l[k] = loc[k];
    aplicarLocal(c.fila, l);
    WA_ESPERA = WA_ESPERA.filter(function (x) { return x !== String(fila); }); WA_YA[fila] = true; waGuardarEspera();
    var sig = waPendientes().filter(function (x) { return String(x.fila) !== String(fila); })[0];
    waCerrar(); waBarraPintar(); cargar();
    if (sig) setTimeout(function () { waActualizar(sig.fila, false); }, 250);
  });
}

/* ───────────── 3. LA BARRA Y EL AVISO AL REGRESAR ───────────── */
function waPendientes() {
  var vistos = {}, out = [];
  WA_ESPERA.forEach(function (f) { var p = waProsp(f); if (p && !vistos[f] && !WA_YA[f]) { vistos[f] = 1; out.push(p); } });
  ((DATOS && DATOS.prospectos) || []).forEach(function (p) { if (p.convPendiente && !vistos[p.fila] && !WA_YA[p.fila]) { vistos[p.fila] = 1; out.push(p); } });
  return out;
}
function waBarraPintar() {
  var b = document.getElementById('waBarra'); if (!b) return;
  var pend = waPendientes();
  if (!pend.length || WA_OCULTA) { b.style.display = 'none'; b.innerHTML = ''; return; }
  var nombres = pend.slice(0, 3).map(function (p) { return p.sinNombre ? waTel(p) : String(p.nombre).split(' ').slice(0, 2).join(' '); }).join(', ') + (pend.length > 3 ? ' y ' + (pend.length - 3) + ' más' : '');
  b.innerHTML = '<div><b>' + pend.length + (pend.length === 1 ? ' conversación por actualizar' : ' conversaciones por actualizar') + '</b><br><span>' + esc(nombres) + '</span></div>' +
    '<button type="button" class="si" id="waBarraAct">Actualizar ahora</button><button type="button" class="no" id="waBarraNo" title="Ocultar por ahora" aria-label="Ocultar">×</button>';
  b.style.display = 'flex';
  document.getElementById('waBarraAct').onclick = function () { var p = waPendientes()[0]; if (p) waActualizar(p.fila, false); };
  document.getElementById('waBarraNo').onclick = function () { WA_OCULTA = true; waBarraPintar(); };
}
document.addEventListener('visibilitychange', function () {
  if (document.visibilityState !== 'visible' || !PASE) return;
  var otro = document.getElementById('dlg');
  if (waAbierto() || (otro && otro.hasAttribute('open'))) return;
  if (Date.now() - WA_ULTIMO < 8000) return;   // acaba de abrirse WhatsApp: no interrumpir el mismo clic
  var p = null;
  WA_ESPERA.forEach(function (f) { var x = waProsp(f); if (x && !p && !WA_PREGUNTADO[f] && !WA_YA[f]) p = x; });
  if (!p) { waBarraPintar(); return; }
  WA_PREGUNTADO[p.fila] = true;
  waActualizar(p.fila, true);
});
/* La barra se actualiza sola cada vez que el panel vuelve a dibujarse con datos nuevos. */
(function () { var original = pintar; pintar = function () { original.apply(this, arguments); try { waBarraPintar(); } catch (e) {} }; })();
document.getElementById('waCerrar').onclick = function () {
  if (WA2 && !WA_YA[WA2.fila]) WA_PREGUNTADO[WA2.fila] = true;
  waCerrar(); waBarraPintar();
};

/* ══════════════════════════════════════════════════════════════════════
   (22-sep) PUBLICIDAD Y CAC
   ──────────────────────────────────────────────────────────────────────
   El informe ya atribuía cada inscripción al canal por el que llegó esa
   persona. Faltaba lo que cuesta: sin gasto no hay decisión, solo opinión.
   Aquí se captura el gasto por canal y periodo y se calculan tres cosas:
     · Costo por prospecto: se mueve en días. Es la señal temprana.
     · CAC: gasto entre inscritos atribuidos a ese canal en el periodo.
     · Conversión del canal: qué tan bien aprovecha lo que trae.
   El CAC de un canal con pocos inscritos es ruidoso: se avisa cuando hay
   menos de tres, para no cerrar una campaña por un dato de uno.
   ══════════════════════════════════════════════════════════════════════ */
var GASTOS = [], CAC_INSC = null, CAC_DESDE = '', CAC_HASTA = '';

function cacIso(d) {
  return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' +
    ('0' + d.getDate()).slice(-2);
}
function cacHoy() { return cacIso(new Date()); }
function cacHace(dias) {
  var d = new Date(); d.setDate(d.getDate() - dias); return cacIso(d);
}
function cacEnRango(iso, desde, hasta) {
  return !!iso && iso >= desde && iso <= hasta;
}
/* La fecha en que la persona pidió informes, en formato comparable. */
function cacAltaIso(p) {
  var d = ipFecha(p.alta) || ipIso(p.alta) || ipFecha(p.ultimo) || ipIso(p.ultimo);
  return d ? cacIso(d) : '';
}

function pintarPublicidad() {
  var c = document.getElementById('v-publicidad');
  if (!CAC_DESDE) { CAC_DESDE = cacHace(30); CAC_HASTA = cacHoy(); }
  c.innerHTML = '<div class="tarjeta">Cargando gasto e inscripciones…</div>';
  var pend = [api('gasto_listar', { pase: PASE })];
  pend.push(CAC_INSC ? Promise.resolve(null) : cargarFeed()
    .catch(function () { return null; }));
  Promise.all(pend).then(function (res) {
    var g = res[0];
    if (g && g.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    GASTOS = (g && g.gastos) || [];
    if (res[1] && res[1].ok) CAC_INSC = res[1].inscripciones || [];
    dibujarPublicidad();
  });
}

/* Inscripciones del periodo, atribuidas al canal del prospecto que coincide
   por teléfono o correo. Las que no coinciden con ningún prospecto se
   cuentan aparte: llegaron sin pasar por admisiones. */
function cacInscritosPorCanal(desde, hasta) {
  var porTel = {}, porCorreo = {};
  (DATOS.prospectos || []).forEach(function (p) {
    var t = ipTel(p.telefono), co = repCorreo(p.correo);
    if (t && !porTel[t]) porTel[t] = p;
    if (co && !porCorreo[co]) porCorreo[co] = p;
  });
  var porCanal = {}, sinOrigen = 0, total = 0;
  (CAC_INSC || []).forEach(function (x) {
    if (!cacEnRango(String(x.f || '').slice(0, 10), desde, hasta)) return;
    total++;
    var p = (x.t && porTel[x.t]) || (x.c && porCorreo[x.c]) || null;
    if (!p) { sinOrigen++; return; }
    var k = canalDe(p.origen);
    porCanal[k] = (porCanal[k] || 0) + 1;
  });
  return { porCanal: porCanal, sinOrigen: sinOrigen, total: total };
}

function dibujarPublicidad() {
  var desde = CAC_DESDE, hasta = CAC_HASTA;
  var prospectos = {}, totalProsp = 0;
  (DATOS.prospectos || []).forEach(function (p) {
    if (!cacEnRango(cacAltaIso(p), desde, hasta)) return;
    var k = canalDe(p.origen);
    prospectos[k] = (prospectos[k] || 0) + 1;
    totalProsp++;
  });
  var ins = cacInscritosPorCanal(desde, hasta);
  var gastoCanal = {}, totalGasto = 0;
  GASTOS.forEach(function (x) {
    // Se cuenta el gasto cuyo periodo cae dentro del rango elegido.
    if (!(x.desde >= desde && x.desde <= hasta)) return;
    gastoCanal[x.canal] = (gastoCanal[x.canal] || 0) + x.monto;
    totalGasto += x.monto;
  });
  var canales = {};
  Object.keys(prospectos).forEach(function (k) { canales[k] = 1; });
  Object.keys(ins.porCanal).forEach(function (k) { canales[k] = 1; });
  Object.keys(gastoCanal).forEach(function (k) { canales[k] = 1; });
  var filas = Object.keys(canales).map(function (k) {
    var gp = gastoCanal[k] || 0, pr = prospectos[k] || 0, iq = ins.porCanal[k] || 0;
    return { canal: k, gasto: gp, prospectos: pr, inscritos: iq,
      cpl: pr ? gp / pr : 0, cac: iq ? gp / iq : 0, conv: pr ? iq * 100 / pr : 0 };
  }).sort(function (a, b) { return b.gasto - a.gasto || b.inscritos - a.inscritos; });

  var h = metaAvisoSemanal() + '<div class="tarjeta">' +
    '<b>Publicidad y costo de adquisición</b>' +
    '<div class="sub">Del <input type="date" id="cacD" value="' + desde + '"> al ' +
    '<input type="date" id="cacH" value="' + hasta + '"> ' +
    '<button id="cacVer">Ver</button> ' +
    '<button id="cac30">Últimos 30 días</button> <button id="cac90">90 días</button></div>' +
    '<div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:12px">' +
    cacCifra('Gasto del periodo', ipMoney(totalGasto)) +
    cacCifra('Prospectos', totalProsp) +
    cacCifra('Inscritos', ins.total) +
    cacCifra('Costo por prospecto', totalProsp ? ipMoney(totalGasto / totalProsp) : '—') +
    cacCifra('CAC', ins.total ? ipMoney(totalGasto / ins.total) : '—') +
    '</div>' +
    (ins.sinOrigen ? '<div class="sub" style="margin-top:8px">' + ins.sinOrigen +
      ' inscripción(es) del periodo no coinciden con ningún prospecto: llegaron sin pasar ' +
      'por admisiones, así que no se le atribuyen a ningún canal.</div>' : '') +
    '</div>';

  h += '<div class="tarjeta" style="margin-top:10px"><b>Por canal</b>' +
    '<div style="overflow-x:auto;margin-top:8px"><table style="width:100%;border-collapse:collapse;' +
    'font-size:12.5px"><tr style="text-align:left;color:#888">' +
    '<th style="padding:6px 8px">Canal</th><th>Gasto</th><th>Prospectos</th>' +
    '<th>Costo por prospecto</th><th>Inscritos</th><th>CAC</th><th>Conversión</th></tr>';
  filas.forEach(function (f) {
    var flojo = f.inscritos > 0 && f.inscritos < 3;
    h += '<tr style="border-top:1px solid rgba(0,0,0,.08)">' +
      '<td style="padding:6px 8px">' + ipEsc(f.canal) + '</td>' +
      '<td>' + (f.gasto ? ipMoney(f.gasto) : '—') + '</td>' +
      '<td>' + f.prospectos + '</td>' +
      '<td>' + (f.cpl ? ipMoney(f.cpl) : '—') + '</td>' +
      '<td>' + f.inscritos + '</td>' +
      '<td>' + (f.cac ? ipMoney(f.cac) + (flojo ? ' *' : '') : (f.gasto ? 'sin inscritos' : '—')) + '</td>' +
      '<td>' + (f.prospectos ? ipPct(f.inscritos, f.prospectos) + '%' : '—') + '</td></tr>';
  });
  h += '</table></div>' +
    '<div class="sub" style="margin-top:8px">* Con menos de tres inscritos el CAC es ruidoso: ' +
    'sirve de indicio, no para cerrar o abrir una campaña. El costo por prospecto sí se mueve ' +
    'en días y es la señal temprana. Un canal con gasto y sin inscritos merece revisión, ' +
    'pero antes hay que descartar que sus prospectos simplemente no se hayan contactado.</div></div>';

  h += metaBloqueCacPrograma(desde, hasta);
  h += metaBloqueImportar();

  // ── Capturar gasto ──
  h += '<div class="tarjeta" style="margin-top:10px"><b>Registrar gasto</b>' +
    '<div class="sub">Lo que se pagó a Meta, Google o donde sea, por periodo. ' +
    'Si la campaña corrió varios días, se pone el periodo completo.</div>' +
    '<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:10px;align-items:center">' +
    '<label>Del <input type="date" id="gD" value="' + cacHace(7) + '"></label>' +
    '<label>al <input type="date" id="gH" value="' + cacHoy() + '"></label>' +
    '<select id="gCanal">' +
    ['Campaña pagada en Meta', 'Campaña pagada en Google', 'Campaña (sin plataforma)',
     'WhatsApp directo', 'Instagram (orgánico)', 'Facebook (orgánico)', 'Referidos',
     'Sitio web (directo)', 'Otro'].map(function (x) {
      return '<option>' + x + '</option>';
    }).join('') + '</select>' +
    '<input id="gCampana" placeholder="Campaña o publicación" style="min-width:180px">' +
    '<input id="gPrograma" placeholder="Programa (opcional)" style="min-width:160px">' +
    '<input id="gMonto" placeholder="Monto en pesos" style="width:130px">' +
    '<input id="gNota" placeholder="Nota (opcional)" style="min-width:160px">' +
    '<button id="gGuardar" class="pri">Registrar</button></div></div>';

  // ── Lo ya registrado ──
  if (GASTOS.length) {
    h += '<div class="tarjeta" style="margin-top:10px"><b>Gasto registrado</b>' +
      '<div style="overflow-x:auto;margin-top:8px"><table style="width:100%;border-collapse:collapse;' +
      'font-size:12.5px"><tr style="text-align:left;color:#888"><th style="padding:6px 8px">Periodo</th>' +
      '<th>Canal</th><th>Campaña</th><th>Programa</th><th>Monto</th><th></th></tr>';
    GASTOS.forEach(function (x) {
      h += '<tr style="border-top:1px solid rgba(0,0,0,.08)">' +
        '<td style="padding:6px 8px">' + ipEsc(x.desde) + (x.hasta && x.hasta !== x.desde ? ' al ' + ipEsc(x.hasta) : '') + '</td>' +
        '<td>' + ipEsc(x.canal) + '</td><td>' + ipEsc(x.campana || '—') + '</td>' +
        '<td>' + ipEsc(x.programa || '—') + '</td><td>' + ipMoney(x.monto) + '</td>' +
        '<td><button data-gasto="' + ipEsc(x.id) + '" style="font-size:11px">Borrar</button></td></tr>';
    });
    h += '</table></div></div>';
  }

  var c = document.getElementById('v-publicidad');
  c.innerHTML = h;
  metaEnlazar();
  metaMarcarPestana();
  document.getElementById('cacVer').onclick = function () {
    CAC_DESDE = document.getElementById('cacD').value || CAC_DESDE;
    CAC_HASTA = document.getElementById('cacH').value || CAC_HASTA;
    dibujarPublicidad();
  };
  document.getElementById('cac30').onclick = function () {
    CAC_DESDE = cacHace(30); CAC_HASTA = cacHoy(); dibujarPublicidad();
  };
  document.getElementById('cac90').onclick = function () {
    CAC_DESDE = cacHace(90); CAC_HASTA = cacHoy(); dibujarPublicidad();
  };
  document.getElementById('gGuardar').onclick = function () {
    var b = this;
    var datos = { pase: PASE,
      desde: document.getElementById('gD').value,
      hasta: document.getElementById('gH').value,
      canal: document.getElementById('gCanal').value,
      campana: document.getElementById('gCampana').value,
      programa: document.getElementById('gPrograma').value,
      monto: document.getElementById('gMonto').value,
      nota: document.getElementById('gNota').value };
    if (!datos.monto) { alert('Falta el monto.'); return; }
    b.disabled = true; b.textContent = 'Registrando…';
    apiEscribir('gasto_agregar', datos).then(function (r) {
      b.disabled = false; b.textContent = 'Registrar';
      if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
      if (!r || !r.ok) { alert('No se pudo registrar: ' + ((r && r.error) || 'sin respuesta') + '.'); return; }
      pintarPublicidad();
    });
  };
  Array.prototype.forEach.call(c.querySelectorAll('[data-gasto]'), function (b) {
    b.onclick = function () {
      if (!confirm('¿Borrar este gasto registrado?')) return;
      apiEscribir('gasto_borrar', { pase: PASE, id: b.getAttribute('data-gasto') })
        .then(function (r) {
          if (!r || !r.ok) { alert('No se pudo borrar.'); return; }
          pintarPublicidad();
        });
    };
  });
}

function cacCifra(t, v) {
  return '<div style="flex:1;min-width:130px;padding:10px;border-radius:10px;' +
    'border:1px solid rgba(0,0,0,.12)"><div style="font-size:11px;color:#888">' + t +
    '</div><div style="font-size:19px;font-weight:800">' + v + '</div></div>';
}

/* ══════════════════════════════════════════════════════════════════════
   (22-sep) PRIORIDAD: A QUIÉN ESCRIBIRLE PRIMERO, Y POR QUÉ
   ──────────────────────────────────────────────────────────────────────
   La cola se trabajaba por antigüedad. Con lo que el panel ya guarda
   —canal, programa, si respondió y qué tan pronto, intentos, días sin
   moverse— se ordena por probabilidad de inscribirse, y cada ficha trae
   las razones. Además se mira dónde se pierden (etapa, canal, programa,
   asesor y, sobre todo, cuánto tardó la primera respuesta) y se contrasta
   el puntaje con quienes SÍ se inscribieron: si no separa, se dice.
   Estima y ordena; la decisión la toma la asesora.
   ══════════════════════════════════════════════════════════════════════ */
var PRI_INSC = null;

function priDias(desde, hasta) {
  var a = ipFecha(desde) || ipIso(desde), b = ipFecha(hasta) || ipIso(hasta);
  if (!a || !b) return null;
  return Math.round((b.getTime() - a.getTime()) / 86400000);
}
function priHoyDias(v) {
  var a = ipFecha(v) || ipIso(v);
  return a ? Math.round((Date.now() - a.getTime()) / 86400000) : null;
}

/* Puntaje por señales de conducta. sinEtapa=true deja fuera la etapa: así
   se contrasta con los inscritos sin hacer trampa, porque su etapa ya dice
   «Inscrito». */
function priPuntaje(p, sinEtapa) {
  var pts = 0, razones = [];
  var etapa = String(p.etapa || 'Nuevo').trim();
  var canal = canalDe(p.origen);
  var progEsp = repProgEspecifico(p);
  var edad = priHoyDias(p.alta), respondio = String(p.respondio || '').trim();
  var wa = String(p.waEnviado || '').trim();
  if (respondio) {
    pts += 3; razones.push('Respondió');
    var lag = wa ? priDias(wa, respondio) : null;
    if (lag !== null && lag <= 1) { pts += 1; razones.push('el mismo día que se le escribió'); }
  }
  if (progEsp) { pts += 2; razones.push('Preguntó por ' + progEsp); }
  if (String(p.pregunta || '').trim()) { pts += 1; razones.push('Hizo una pregunta concreta'); }
  if (canal === 'Referidos') { pts += 2; razones.push('Llegó por referido'); }
  else if (canal === 'WhatsApp directo') { pts += 1; razones.push('Escribió directo por WhatsApp'); }
  if (edad !== null) {
    if (edad <= 7) { pts += 2; razones.push('Pidió informes hace ' + edad + ' día(s)'); }
    else if (edad <= 30) { pts += 1; razones.push('Pidió informes hace ' + edad + ' días'); }
    else if (edad > 60) { pts -= 1; razones.push('Lleva ' + edad + ' días desde que pidió informes'); }
  }
  if (wa && !respondio && (priHoyDias(wa) || 0) > 7) { pts -= 1; razones.push('Se le escribió y no ha respondido'); }
  if (String(p.notas || '').trim()) { pts += 1; razones.push('Hay conversación anotada'); }
  if (!sinEtapa) {
    if (etapa === 'Documentos en proceso') { pts += 4; razones.push('Ya está en documentos'); }
    else if (etapa === 'Interesado') { pts += 2; razones.push('Marcado como interesado'); }
    else if (etapa === 'Contactado') { pts += 1; }
  }
  var nivel = pts >= 6 ? 'alta' : (pts >= 3 ? 'media' : 'baja');
  return { puntos: pts, nivel: nivel, razones: razones };
}

function priInscritosSet() {
  var s = {};
  (PRI_INSC || []).forEach(function (x) { if (x.t) s['t:' + x.t] = 1; if (x.c) s['c:' + x.c] = 1; });
  return s;
}
function priEsInscrito(p, set) {
  if (String(p.etapa || '') === 'Inscrito') return true;
  var t = ipTel(p.telefono), c = repCorreo(p.correo);
  return !!((t && set['t:' + t]) || (c && set['c:' + c]));
}

function pintarPrioridad() {
  var c = document.getElementById('v-prioridad');
  c.innerHTML = '<div class="tarjeta">Calculando prioridad…</div>';
  var pend = PRI_INSC ? Promise.resolve(null)
    : cargarFeed().catch(function () { return null; });
  pend.then(function (r) {
    if (r && r.ok) PRI_INSC = r.inscripciones || [];
    if (!PRI_INSC) PRI_INSC = [];
    dibujarPrioridad();
  });
}

function priPct(a, b) { return b ? Math.round(a * 100 / b) + '%' : '—'; }

function dibujarPrioridad() {
  var set = priInscritosSet();
  var todos = (DATOS.prospectos || []).filter(function (p) { return !p.baja; });
  var vivos = [], inscritos = [], perdidos = [];
  todos.forEach(function (p) {
    var ins = priEsInscrito(p, set);
    var et = String(p.etapa || '').trim();
    if (ins) inscritos.push(p);
    else if (et === 'No procede') perdidos.push(p);
    else vivos.push(p);
  });
  var cola = vivos.map(function (p) { var s = priPuntaje(p, false); return { p: p, s: s }; })
    .sort(function (a, b) { return b.s.puntos - a.s.puntos || (priHoyDias(b.p.alta) || 0) - (priHoyDias(a.p.alta) || 0); });

  /* ── Contraste: ¿el puntaje separa a los que sí se inscribieron? ── */
  var nivelIns = { alta: 0, media: 0, baja: 0 }, nivelNo = { alta: 0, media: 0, baja: 0 };
  inscritos.forEach(function (p) { nivelIns[priPuntaje(p, true).nivel]++; });
  vivos.concat(perdidos).forEach(function (p) { nivelNo[priPuntaje(p, true).nivel]++; });
  var nIns = inscritos.length, nNo = vivos.length + perdidos.length;

  /* ── Tiempo de primera respuesta vs inscripción ── */
  var cubetas = [
    { k: 'mismo día', min: 0, max: 0 }, { k: '1 a 3 días', min: 1, max: 3 },
    { k: '4 a 7 días', min: 4, max: 7 }, { k: 'más de 7 días', min: 8, max: 99999 },
    { k: 'sin contactar', min: null }];
  cubetas.forEach(function (b) { b.n = 0; b.ins = 0; });
  todos.forEach(function (p) {
    var wa = String(p.waEnviado || '').trim(), lag = wa ? priDias(p.alta, wa) : null;
    var b = cubetas[4];
    if (lag !== null) {
      for (var i = 0; i < 4; i++) if (lag >= cubetas[i].min && lag <= cubetas[i].max) { b = cubetas[i]; break; }
      if (lag < 0) b = cubetas[0];
    }
    b.n++; if (priEsInscrito(p, set)) b.ins++;
  });

  /* ── Dónde se pierden: por canal, programa y asesor ── */
  function agrupar(f) {
    var o = {};
    todos.forEach(function (p) {
      var k = f(p) || 'Sin dato';
      var g = o[k] = o[k] || { n: 0, resp: 0, ins: 0, dias: 0, nd: 0 };
      g.n++;
      if (String(p.respondio || '').trim()) g.resp++;
      if (priEsInscrito(p, set)) g.ins++;
      if (typeof p.dias === 'number') { g.dias += p.dias; g.nd++; }
    });
    return Object.keys(o).map(function (k) { var g = o[k]; g.k = k; return g; })
      .sort(function (a, b) { return b.n - a.n; });
  }
  var porCanal = agrupar(function (p) { return canalDe(p.origen); });
  var porPrograma = agrupar(function (p) { return progNorm(p.programa); });
  var porAsesor = agrupar(function (p) { return String(p.asignado || '').trim() || 'Sin asesor'; });
  var etapas = {};
  todos.forEach(function (p) { var e = String(p.etapa || 'Nuevo').trim(); etapas[e] = (etapas[e] || 0) + 1; });

  var h = '<div class="tarjeta"><b>Prioridad de la cola</b>' +
    '<div class="sub">' + vivos.length + ' fichas vivas, ordenadas por probabilidad de inscribirse. ' +
    'Cada una trae sus razones. El orden propone; la asesora decide.</div>' +
    '<div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:10px">' +
    cacCifra('Alta', cola.filter(function (x) { return x.s.nivel === 'alta'; }).length) +
    cacCifra('Media', cola.filter(function (x) { return x.s.nivel === 'media'; }).length) +
    cacCifra('Baja', cola.filter(function (x) { return x.s.nivel === 'baja'; }).length) +
    cacCifra('Inscritos (histórico)', nIns) + '</div></div>';

  /* Contraste */
  var sepIns = nIns ? (nivelIns.alta + nivelIns.media) * 100 / nIns : 0;
  var sepNo = nNo ? (nivelNo.alta + nivelNo.media) * 100 / nNo : 0;
  h += '<div class="tarjeta" style="margin-top:10px"><b>¿El puntaje separa?</b>' +
    '<div class="sub">Se aplican las mismas señales de conducta —sin mirar la etapa— a quienes sí se ' +
    'inscribieron y a quienes no.</div>' +
    '<div style="margin-top:8px;font-size:12.5px;line-height:1.5">' +
    'De <b>' + nIns + '</b> inscritos, el <b>' + Math.round(sepIns) + '%</b> habría salido en alta o media ' +
    '(' + priPct(nivelIns.alta, nIns) + ' en alta). De <b>' + nNo + '</b> que no se han inscrito, el <b>' +
    Math.round(sepNo) + '%</b> sale en alta o media (' + priPct(nivelNo.alta, nNo) + ' en alta).<br>' +
    (nIns < 10 ? '<b>Con menos de diez inscritos el contraste todavía no dice nada: tómelo solo como orden de trabajo.</b>'
      : (sepIns - sepNo >= 25 ? '<b>Separa bien:</b> se puede confiar en el orden.'
        : (sepIns - sepNo >= 10 ? 'Separa algo: sirve como orientación, no como regla.'
          : '<b>No separa:</b> el orden vale lo mismo que el azar; hay que revisar las señales.'))) +
    '</div></div>';

  /* Primera respuesta */
  h += '<div class="tarjeta" style="margin-top:10px"><b>Cuánto tardó la primera respuesta, y qué pasó</b>' +
    '<div class="sub">Días entre que pidió informes y el primer WhatsApp. Es el indicador que más pesa.</div>' +
    '<table style="width:100%;border-collapse:collapse;font-size:12.5px;margin-top:8px">' +
    '<tr style="text-align:left;color:#888"><th style="padding:6px 8px">Primera respuesta</th><th>Prospectos</th><th>Inscritos</th><th>Conversión</th></tr>';
  cubetas.forEach(function (b) {
    h += '<tr style="border-top:1px solid rgba(0,0,0,.08)"><td style="padding:6px 8px">' + b.k + '</td><td>' + b.n +
      '</td><td>' + b.ins + '</td><td><b>' + priPct(b.ins, b.n) + '</b></td></tr>';
  });
  h += '</table></div>';

  /* Dónde se pierden */
  function tabla(titulo, filas) {
    var t = '<div class="tarjeta" style="margin-top:10px"><b>' + titulo + '</b>' +
      '<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:12.5px;margin-top:8px">' +
      '<tr style="text-align:left;color:#888"><th style="padding:6px 8px"></th><th>Prospectos</th><th>Respondieron</th><th>Inscritos</th><th>Días sin moverse</th></tr>';
    filas.slice(0, 12).forEach(function (g) {
      t += '<tr style="border-top:1px solid rgba(0,0,0,.08)"><td style="padding:6px 8px">' + ipEsc(g.k) + '</td><td>' + g.n +
        '</td><td>' + priPct(g.resp, g.n) + '</td><td>' + g.ins + ' (' + priPct(g.ins, g.n) + ')</td><td>' +
        (g.nd ? Math.round(g.dias / g.nd) : '—') + '</td></tr>';
    });
    return t + '</table></div></div>';
  }
  h += '<div class="tarjeta" style="margin-top:10px"><b>Dónde están</b><div class="sub">' +
    Object.keys(etapas).map(function (e) { return ipEsc(e) + ': <b>' + etapas[e] + '</b>'; }).join(' · ') + '</div></div>';
  h += tabla('Por canal', porCanal) + tabla('Por programa', porPrograma) + tabla('Por asesor', porAsesor);

  /* La cola priorizada */
  h += '<div class="tarjeta" style="margin-top:10px"><b>Trabajar en este orden</b>' +
    '<div class="sub">Las 60 primeras. WhatsApp abre el mensaje y anota el envío, como en la cola.</div>';
  cola.slice(0, 60).forEach(function (x, i) {
    var p = x.p, s = x.s;
    var color = s.nivel === 'alta' ? 'var(--rojo)' : (s.nivel === 'media' ? '#B8860B' : '#888');
    h += '<div style="display:flex;gap:10px;align-items:flex-start;margin-top:8px;padding:8px;' +
      'border-radius:8px;border:1px solid rgba(0,0,0,.12)">' +
      '<div style="min-width:34px;font-weight:800;color:' + color + '">' + (i + 1) + '</div>' +
      '<div style="flex:1;font-size:12.5px;line-height:1.45"><b>' + ipEsc(p.nombre || '(sin nombre)') + '</b>' +
      ' <span style="font-size:10.5px;font-weight:800;color:' + color + '">' + s.nivel.toUpperCase() + '</span>' +
      ' · ' + ipEsc(p.programa || 'sin programa') + ' · ' + ipEsc(p.etapa || 'Nuevo') +
      (p.asignado ? ' · ' + ipEsc(p.asignado) : '') +
      '<br><span style="color:#666">' + ipEsc(s.razones.join(' · ') || 'Sin señales todavía') + '</span></div>' +
      '<div style="display:flex;gap:6px;flex-wrap:wrap">' +
      '<button data-priver="' + p.fila + '">Ficha</button>' +
      (p.wa ? '<button data-priwa="' + p.fila + '" class="pri">WhatsApp</button>' : '') +
      '</div></div>';
  });
  h += '</div>';

  var c = document.getElementById('v-prioridad');
  c.innerHTML = h;
  var porFila = {};
  cola.forEach(function (x) { porFila[x.p.fila] = x.p; });
  Array.prototype.forEach.call(c.querySelectorAll('[data-priver]'), function (b) {
    b.onclick = function () {
      var p = porFila[Number(b.getAttribute('data-priver'))];
      if (p) verFicha(p.fila, p.nombre);
    };
  });
  Array.prototype.forEach.call(c.querySelectorAll('[data-priwa]'), function (b) {
    b.onclick = function () {
      var p = porFila[Number(b.getAttribute('data-priwa'))];
      if (!p) return;
      waAbrirIA(p);   // (28-sep) mismo diálogo con IA
    };
  });
}

/* ══════════════════════════════════════════════════════════════════════
   (22-sep) IMPORTAR EL INFORME DE META Y AFINAR EL CAC
   ──────────────────────────────────────────────────────────────────────
   El informe de anuncios de Meta («Raw Data Report») trae por publicación
   el gasto, el alcance, los clics y las conversaciones iniciadas, y en el
   nombre del anuncio se ve a qué programa apuntó. Se importa tal cual
   —archivo .xlsx o filas pegadas desde Excel—, sin capturar nada a mano,
   y con eso el CAC se calcula también POR PROGRAMA y se ve cuántas
   conversaciones pagadas nunca se registraron como prospecto.
   Semana sin gasto registrado → aviso en el panel: el recordatorio vive
   aquí, no en la memoria de nadie.
   ══════════════════════════════════════════════════════════════════════ */
var META_COLS = {
  campana: ['nombre de la campana', 'campaign name'],
  conjunto: ['nombre del conjunto de anuncios', 'ad set name'],
  gasto: ['importe gastado', 'amount spent'],
  alcance: ['alcance', 'reach'],
  clics: ['clics en el enlace', 'link clicks'],
  conversaciones: ['conversaciones con mensajes iniciadas', 'messaging conversations started'],
  inicio: ['inicio del informe', 'reporting starts'],
  fin: ['fin del informe', 'reporting ends']
};
function metaNorm(t) {
  return String(t == null ? '' : t).toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
}
function metaCol(cabeceras, claves) {
  for (var i = 0; i < cabeceras.length; i++) {
    var h = metaNorm(cabeceras[i]);
    for (var k = 0; k < claves.length; k++) if (h.indexOf(claves[k]) === 0) return i;
  }
  return -1;
}
/* El programa al que apuntó el anuncio, leído de su texto. */
function metaPrograma(txt) {
  var t = metaNorm(txt);
  if (!t) return '';
  if (t.indexOf('licenciatura') >= 0) return 'Licenciatura en Pedagogía';
  if (t.indexOf('inclusiva') >= 0) return 'Maestría en Educación Inclusiva';
  if (t.indexOf('psicopedagog') >= 0) return 'Maestría en Psicopedagogía';
  if (t.indexOf('doctorado') >= 0) return t.indexOf('ciencias') >= 0
    ? 'Doctorado en Ciencias de la Educación' : 'Doctorado en Educación con Énfasis en Investigación';
  if (t.indexOf('maestria en pedagogia') >= 0) return 'Maestría en Pedagogía';
  if (t.indexOf('maestria en educacion') >= 0 || t.indexOf('maestria') >= 0) return 'Maestría en Educación';
  return '';
}
function metaFechaIso(v) {
  if (v instanceof Date) return cacIso(v);
  var t = String(v == null ? '' : v).trim();
  var m = t.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return m[1] + '-' + m[2] + '-' + m[3];
  m = t.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/);
  if (m) return m[3] + '-' + ('0' + m[2]).slice(-2) + '-' + ('0' + m[1]).slice(-2);
  return '';
}
/* De una tabla (matriz de celdas) a filas de gasto listas para registrar. */
function metaFilas(tabla) {
  if (!tabla || tabla.length < 2) return { error: 'No se encontraron filas.' };
  var cab = tabla[0], ix = {};
  for (var k in META_COLS) ix[k] = metaCol(cab, META_COLS[k]);
  if (ix.gasto < 0) return { error: 'No encuentro la columna «Importe gastado». ¿Es el informe de Meta?' };
  var out = [];
  for (var r = 1; r < tabla.length; r++) {
    var f = tabla[r];
    var nombre = String((ix.conjunto >= 0 && f[ix.conjunto]) || (ix.campana >= 0 && f[ix.campana]) || '').trim();
    if (!nombre) continue;   // la primera fila es el total de la cuenta
    var monto = Number(String(f[ix.gasto] || '').replace(/[^\d.]/g, '')) || 0;
    if (monto <= 0) continue;
    out.push({
      desde: ix.inicio >= 0 ? metaFechaIso(f[ix.inicio]) : '',
      hasta: ix.fin >= 0 ? metaFechaIso(f[ix.fin]) : '',
      canal: 'Campaña pagada en Meta',
      campana: nombre.replace(/^Publicaci[oó]n:\s*/i, '').replace(/^"|"$/g, '').substring(0, 120),
      // Primero el anuncio; solo si no dice programa, la campaña que lo agrupa.
      programa: metaPrograma(nombre) || metaPrograma(ix.campana >= 0 ? f[ix.campana] : ''),
      monto: Math.round(monto * 100) / 100,
      alcance: ix.alcance >= 0 ? Number(f[ix.alcance]) || 0 : 0,
      clics: ix.clics >= 0 ? Number(f[ix.clics]) || 0 : 0,
      conversaciones: ix.conversaciones >= 0 ? Number(f[ix.conversaciones]) || 0 : 0
    });
  }
  if (!out.length) return { error: 'No hay filas con gasto.' };
  return { filas: out };
}
function metaDesdePegado(txt) {
  var lineas = String(txt || '').split(/\r?\n/).filter(function (l) { return l.trim(); });
  return lineas.map(function (l) { return l.split('\t'); });
}
function metaCargarSheetJS() {
  if (window.XLSX) return Promise.resolve();
  return new Promise(function (ok, no) {
    var s = document.createElement('script');
    s.src = 'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js';
    s.onload = ok; s.onerror = function () { no(new Error('No se pudo cargar el lector de Excel.')); };
    document.head.appendChild(s);
  });
}
function metaDesdeArchivo(file) {
  return metaCargarSheetJS().then(function () {
    return new Promise(function (ok, no) {
      var fr = new FileReader();
      fr.onload = function () {
        try {
          var wb = XLSX.read(new Uint8Array(fr.result), { type: 'array', cellDates: true });
          var ws = wb.Sheets[wb.SheetNames[0]];
          ok(XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: '' }));
        } catch (e) { no(e); }
      };
      fr.onerror = function () { no(new Error('No se pudo leer el archivo.')); };
      fr.readAsArrayBuffer(file);
    });
  });
}
var META_PREVIA = null;
function metaMostrarPrevia(res) {
  var c = document.getElementById('metaPrevia');
  if (!c) return;
  if (res.error) { c.innerHTML = '<div class="sub" style="color:var(--rojo)">' + ipEsc(res.error) + '</div>'; META_PREVIA = null; return; }
  META_PREVIA = res.filas;
  var total = res.filas.reduce(function (s, f) { return s + f.monto; }, 0);
  var h = '<table style="width:100%;border-collapse:collapse;font-size:12px;margin-top:8px">' +
    '<tr style="text-align:left;color:#888"><th style="padding:5px 6px">Periodo</th><th>Anuncio</th><th>Programa</th><th>Gasto</th><th>Conv.</th></tr>';
  var PROGS = ['', 'Maestría en Educación', 'Maestría en Pedagogía', 'Maestría en Psicopedagogía',
    'Maestría en Educación Inclusiva', 'Doctorado en Educación con Énfasis en Investigación',
    'Doctorado en Ciencias de la Educación', 'Licenciatura en Pedagogía'];
  res.filas.forEach(function (f, i) {
    // El programa se propone leído del anuncio; si el texto no lo dice, se elige aquí.
    var sel = '<select data-metaprog="' + i + '" style="font-size:11.5px;max-width:200px">' +
      PROGS.map(function (p) { return '<option' + (p === f.programa ? ' selected' : '') + '>' + (p || '— sin programa —') + '</option>'; }).join('') + '</select>';
    h += '<tr style="border-top:1px solid rgba(0,0,0,.08)"><td style="padding:5px 6px">' + ipEsc(f.desde) +
      (f.hasta && f.hasta !== f.desde ? ' al ' + ipEsc(f.hasta) : '') + '</td><td>' + ipEsc(f.campana) + '</td><td>' +
      sel + '</td><td>' + ipMoney(f.monto) + '</td><td>' + f.conversaciones + '</td></tr>';
  });
  h += '</table><div style="margin-top:10px"><b>' + res.filas.length + ' anuncios · ' + ipMoney(total) + '</b> ' +
    '<button id="metaRegistrar" class="pri" style="margin-left:10px">Registrar en el gasto</button></div>';
  c.innerHTML = h;
  Array.prototype.forEach.call(c.querySelectorAll('[data-metaprog]'), function (sel) {
    sel.onchange = function () {
      var v = sel.value === '— sin programa —' ? '' : sel.value;
      META_PREVIA[Number(sel.getAttribute('data-metaprog'))].programa = v;
    };
  });
  document.getElementById('metaRegistrar').onclick = function () {
    var b = this; b.disabled = true; b.textContent = 'Registrando…';
    apiEscribir('gasto_importar', { pase: PASE, filas: JSON.stringify(META_PREVIA) }).then(function (r) {
      b.disabled = false; b.textContent = 'Registrar en el gasto';
      if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
      if (!r || !r.ok) { alert('No se pudo importar: ' + ((r && r.error) || 'sin respuesta') + '.'); return; }
      alert(r.agregados + ' anuncio(s) registrados' + (r.omitidos ? ' · ' + r.omitidos + ' ya estaban y no se repitieron' : '') + '.');
      META_PREVIA = null;
      pintarPublicidad();
    });
  };
}
function metaBloqueImportar() {
  return '<div class="tarjeta" style="margin-top:10px"><b>Importar el informe de Meta</b>' +
    '<div class="sub">Cada semana: en el administrador de anuncios, exporte el informe («Raw Data Report», .xlsx) ' +
    'y súbalo aquí; o copie las filas desde Excel y péguelas. Se registra un gasto por anuncio, con su ' +
    'periodo, programa, alcance, clics y conversaciones. Lo repetido no se duplica.</div>' +
    '<div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-top:10px">' +
    '<input type="file" id="metaArchivo" accept=".xlsx,.xls,.csv">' +
    '<span class="sub">o</span>' +
    '<textarea id="metaPegado" rows="3" placeholder="Pegue aquí las filas copiadas de Excel (con encabezados)" ' +
    'style="flex:1;min-width:260px;font-size:12px"></textarea>' +
    '<button id="metaLeer">Leer</button></div>' +
    '<div id="metaPrevia"></div></div>';
}
function metaEnlazar() {
  var a = document.getElementById('metaArchivo'), b = document.getElementById('metaLeer');
  if (a) a.onchange = function () {
    if (!a.files || !a.files[0]) return;
    metaDesdeArchivo(a.files[0]).then(function (tabla) { metaMostrarPrevia(metaFilas(tabla)); })
      .catch(function (e) { metaMostrarPrevia({ error: String(e.message || e) }); });
  };
  if (b) b.onclick = function () {
    metaMostrarPrevia(metaFilas(metaDesdePegado(document.getElementById('metaPegado').value)));
  };
}

/* ── CAC por programa y fuga de conversaciones ── */
function metaBloqueCacPrograma(desde, hasta) {
  var gastoProg = {}, convProg = {}, totalConv = 0, totalGastoMeta = 0;
  GASTOS.forEach(function (x) {
    if (!(x.desde >= desde && x.desde <= hasta)) return;
    var k = x.programa || 'Sin programa en el anuncio';
    gastoProg[k] = (gastoProg[k] || 0) + x.monto;
    if (/meta/i.test(x.canal)) { totalGastoMeta += x.monto; totalConv += (x.conversaciones || 0); convProg[k] = (convProg[k] || 0) + (x.conversaciones || 0); }
  });
  var prosProg = {}, prosMeta = 0, insProg = {};
  (DATOS.prospectos || []).forEach(function (p) {
    if (!cacEnRango(cacAltaIso(p), desde, hasta)) return;
    var k = progNorm(p.programa);
    prosProg[k] = (prosProg[k] || 0) + 1;
    if (canalDe(p.origen) === 'Campaña pagada en Meta' || /facebook|instagram|meta/i.test(String(p.origen || ''))) prosMeta++;
  });
  (CAC_INSC || []).forEach(function (x) {
    if (!cacEnRango(String(x.f || '').slice(0, 10), desde, hasta)) return;
    var k = progNorm(x.p);
    insProg[k] = (insProg[k] || 0) + 1;
  });
  var progs = {};
  Object.keys(gastoProg).forEach(function (k) { progs[k] = 1; });
  Object.keys(insProg).forEach(function (k) { progs[k] = 1; });
  var h = '<div class="tarjeta" style="margin-top:10px"><b>CAC por programa</b>' +
    '<div class="sub">El gasto se atribuye al programa que anuncia cada publicación; los inscritos, al programa ' +
    'de su inscripción. Sirve para decidir en qué programa conviene seguir invirtiendo.</div>' +
    '<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:12.5px;margin-top:8px">' +
    '<tr style="text-align:left;color:#888"><th style="padding:6px 8px">Programa</th><th>Gasto</th><th>Prospectos</th>' +
    '<th>Costo por prospecto</th><th>Inscritos</th><th>CAC</th></tr>';
  Object.keys(progs).sort(function (a, b) { return (gastoProg[b] || 0) - (gastoProg[a] || 0); }).forEach(function (k) {
    var g = gastoProg[k] || 0, pr = prosProg[k] || 0, ins = insProg[k] || 0;
    h += '<tr style="border-top:1px solid rgba(0,0,0,.08)"><td style="padding:6px 8px">' + ipEsc(k) + '</td>' +
      '<td>' + (g ? ipMoney(g) : '—') + '</td><td>' + pr + '</td><td>' + (g && pr ? ipMoney(g / pr) : '—') + '</td>' +
      '<td>' + ins + '</td><td>' + (g && ins ? ipMoney(g / ins) + (ins < 3 ? ' *' : '') : (g ? 'sin inscritos' : '—')) + '</td></tr>';
  });
  h += '</table></div></div>';
  if (totalConv) {
    var pct = prosMeta ? Math.round(prosMeta * 100 / totalConv) : 0;
    h += '<div class="tarjeta" style="margin-top:10px"><b>Conversaciones pagadas frente a prospectos registrados</b>' +
      '<div style="margin-top:8px;font-size:12.5px;line-height:1.5">Meta cobró <b>' + totalConv + '</b> conversaciones iniciadas por ' +
      ipMoney(totalGastoMeta) + ' (' + ipMoney(totalGastoMeta / totalConv) + ' cada una). En el panel hay <b>' + prosMeta +
      '</b> prospectos de Meta en el mismo periodo: <b>' + pct + '%</b>.' +
      (pct < 50 ? '<br><b>La mayoría de las conversaciones pagadas no se registran como prospecto.</b> Antes de gastar más, ' +
        'conviene que cada conversación de WhatsApp quede en el panel (alta manual o registro automático): sin eso, ' +
        'el CAC real es más bajo de lo que parece y la cola más grande de lo que se ve.' : '') + '</div></div>';
  }
  return h;
}

/* ── Aviso semanal: ¿ya se registró el gasto de esta semana? ── */
function metaAvisoSemanal() {
  var ultimo = '';
  GASTOS.forEach(function (x) { if (x.hasta > ultimo) ultimo = x.hasta; });
  var dias = ultimo ? Math.round((Date.now() - new Date(ultimo + 'T12:00:00').getTime()) / 86400000) : null;
  if (dias !== null && dias <= 7) return '';
  return '<div class="tarjeta" style="border-color:var(--rojo);margin-bottom:10px"><b style="color:var(--rojo)">' +
    (dias === null ? 'Todavía no se ha registrado gasto de publicidad.' :
      'Han pasado ' + dias + ' días desde el último gasto registrado (' + ipEsc(ultimo) + ').') +
    '</b><div class="sub">Exporte el informe de Meta de la semana e impórtelo abajo: sin el gasto, el CAC de esta semana no existe.</div></div>';
}
function metaMarcarPestana() {
  var b = document.querySelector('.pest button[data-v="publicidad"]');
  if (!b) return;
  var ultimo = '';
  GASTOS.forEach(function (x) { if (x.hasta > ultimo) ultimo = x.hasta; });
  var dias = ultimo ? Math.round((Date.now() - new Date(ultimo + 'T12:00:00').getTime()) / 86400000) : 99;
  b.textContent = 'Publicidad y CAC' + (dias > 7 ? ' ●' : '');
  b.title = dias > 7 ? 'Falta registrar el gasto de publicidad de la semana' : '';
}

/* ══════════════════════════════════════════════════════════════════════
   (22-sep) EL BOT DE WHATSAPP, EN EL PANEL
   ──────────────────────────────────────────────────────────────────────
   Lo que el bot hace queda en la hoja BotWhatsApp y aquí se ve: el feed en
   vivo, el embudo del bot, a quién dejó fuera (alumnos, otros asuntos),
   las preguntas que la base no cubrió —la lista de lo que hay que agregar—,
   qué variante de cierre rinde, las horas pico y el tiempo de respuesta.
   Y un análisis con IA de lo que la gente pide y qué frena la decisión.
   ══════════════════════════════════════════════════════════════════════ */
var BOT_DIAS = 7, BOT_TIMER = null;
function pintarBot() {
  var c = document.getElementById('v-bot');
  c.innerHTML = '<div class="tarjeta">Leyendo la bitácora del bot…</div>';
  api('bot_eventos', { pase: PASE, dias: BOT_DIAS }).then(function (r) {
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) { c.innerHTML = '<div class="tarjeta">No se pudo leer la bitácora: ' + ipEsc((r && r.error) || 'sin respuesta') + '</div>'; return; }
    dibujarBot(r);
    // Mientras la pestaña esté abierta, se refresca sola cada minuto.
    clearTimeout(BOT_TIMER);
    BOT_TIMER = setTimeout(function () { if (VISTA === 'bot') pintarBot(); }, 60000);
  });
}
function botHace(iso) {
  var m = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
  if (m < 1) return 'ahora'; if (m < 60) return 'hace ' + m + ' min';
  var h = Math.round(m / 60); if (h < 24) return 'hace ' + h + ' h';
  return 'hace ' + Math.round(h / 24) + ' d';
}
function dibujarBot(r) {
  var e = r.embudo, pct = function (a, b) { return b ? Math.round(a * 100 / b) + '%' : '—'; };
  var h = '<div class="tarjeta"><b>Bot de WhatsApp · últimos ' + r.dias + ' días</b> ' +
    '<span class="sub"> · <a href="#" id="botD7">7 días</a> · <a href="#" id="botD30">30 días</a> · ' +
    '<a href="#" id="botRefrescar">actualizar</a></span>' +
    '<div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:10px">' +
    cacCifra('Conversaciones', e.conversaciones) +
    cacCifra('De admisión', e.admision + ' (' + pct(e.admision, e.conversaciones) + ')') +
    cacCifra('Eligieron programa', e.programa + ' (' + pct(e.programa, e.admision) + ')') +
    cacCifra('Dijeron cuándo', e.cuando + ' (' + pct(e.cuando, e.programa) + ')') +
    cacCifra('Respondieron tras el cierre', e.respondio + ' (' + pct(e.respondio, e.cierre) + ')') +
    cacCifra('Inscritos', e.inscrito) +
    cacCifra('Tiempo de respuesta', r.msPromedio !== null ? (r.msPromedio / 1000).toFixed(1) + ' s' : '—') +
    cacCifra('Desde el sitio web', (e.web || 0) + (e.webSinRespuesta ? ' (' + e.webSinRespuesta + ' sin respuesta)' : '')) +
    '</div>' +
    '<div class="sub" style="margin-top:8px">Quedaron fuera del bot: ' +
    Object.keys(r.temas).filter(function (t) { return t !== 'admision'; }).map(function (t) { return ipEsc(t) + ' <b>' + r.temas[t] + '</b>'; }).join(' · ') +
    ' · Entregadas a una persona: <b>' + e.humano + '</b></div></div>';

  // Preguntas sin respuesta: la lista de lo que hay que agregar a la base.
  h += '<div class="tarjeta" style="margin-top:10px"><b>Preguntas que la base no cubrió</b> <span class="sub">(' + r.sinRespuesta.length + ')</span>' +
    '<div class="sub">Cada una es un hecho que falta en wa_base.php. Se archivan aquí para que nadie tenga que buscarlas.</div>';
  if (!r.sinRespuesta.length) h += '<div class="sub" style="margin-top:6px">Ninguna en el periodo.</div>';
  r.sinRespuesta.forEach(function (q) {
    h += '<div style="margin-top:6px;padding:6px 8px;border-radius:8px;border:1px solid rgba(0,0,0,.1);font-size:12.5px">' +
      ipEsc(q.texto) + ' <span class="sub">· ' + botHace(q.fecha) + ' · …' + ipEsc(q.tel) + '</span></div>';
  });
  h += '</div>';

  // Qué variante cierra mejor.
  if (r.variantes.length) {
    h += '<div class="tarjeta" style="margin-top:10px"><b>Qué cierre rinde más</b>' +
      '<div class="sub">Puntos: respondió en 48 h = 1, se inscribió = 3. Con menos de 20 intentos por variante es ruido.</div>' +
      '<table style="width:100%;border-collapse:collapse;font-size:12.5px;margin-top:8px"><tr style="text-align:left;color:#888">' +
      '<th style="padding:5px 8px">Momento</th><th>Variante</th><th>Intentos</th><th>Puntos</th><th>Puntos por intento</th></tr>';
    r.variantes.sort(function (a, b) { return a.momento.localeCompare(b.momento) || a.variante.localeCompare(b.variante); }).forEach(function (v) {
      h += '<tr style="border-top:1px solid rgba(0,0,0,.08)"><td style="padding:5px 8px">' + ipEsc(v.momento) + '</td><td>' + ipEsc(v.variante) +
        '</td><td>' + v.intentos + '</td><td>' + v.puntos + '</td><td><b>' + (v.intentos ? (v.puntos / v.intentos).toFixed(2) : '—') + '</b>' +
        (v.intentos < 20 ? ' *' : '') + '</td></tr>';
    });
    h += '</table></div>';
  }

  // Horas pico y programas.
  var horas = []; for (var i = 0; i < 24; i++) horas.push(r.horas[i] || 0);
  var maxH = Math.max.apply(null, horas.concat([1]));
  h += '<div class="tarjeta" style="margin-top:10px"><b>A qué hora escriben</b><div class="sub">Mensajes por hora del día. Sirve para saber cuándo debe estar Janeth.</div>' +
    '<div style="display:flex;align-items:flex-end;gap:2px;height:70px;margin-top:8px">' +
    horas.map(function (n, i) { return '<div title="' + i + ':00 · ' + n + '" style="flex:1;background:var(--rojo);opacity:' + (0.25 + 0.75 * n / maxH) + ';height:' + Math.max(2, Math.round(n * 66 / maxH)) + 'px"></div>'; }).join('') +
    '</div><div style="display:flex;font-size:9px;color:#888;justify-content:space-between"><span>0h</span><span>6h</span><span>12h</span><span>18h</span><span>23h</span></div></div>';
  var progs = Object.keys(r.programas).sort(function (a, b) { return r.programas[b] - r.programas[a]; });
  if (progs.length) {
    h += '<div class="tarjeta" style="margin-top:10px"><b>Programas que eligen en el bot</b><div class="sub" style="margin-top:6px">' +
      progs.map(function (p) { return ipEsc(p) + ' <b>' + r.programas[p] + '</b>'; }).join(' · ') + '</div></div>';
  }

  // Análisis con IA.
  h += '<div class="tarjeta" style="margin-top:10px"><b>Análisis con IA</b><div class="sub">Lee los mensajes reales de los últimos 14 días y dice qué pide la gente, ' +
    'qué frena la decisión y qué hechos faltan en la base. No inventa cifras.</div>' +
    '<div style="margin-top:8px"><button id="botIa" class="pri">Analizar</button></div><div id="botIaOut" style="margin-top:10px;font-size:13px;line-height:1.5;white-space:pre-wrap"></div></div>';

  // Feed en vivo.
  h += '<div class="tarjeta" style="margin-top:10px"><b>Últimos movimientos</b><div class="sub">Lo más reciente arriba. Se actualiza solo cada minuto mientras esta pestaña esté abierta.</div>';
  var colorEv = { mensaje: '#333', bot: '#888', triaje: '#B8860B', menu: '#1E7F52', programa: '#1E7F52', cuando: '#1E7F52', cierre: 'var(--rojo)',
    sin_respuesta: 'var(--rojo)', humano: '#B8860B', nudge: '#3B6EA5', respondio: '#1E7F52', inscrito: '#1E7F52' };
  r.feed.forEach(function (f) {
    h += '<div style="display:flex;gap:8px;margin-top:6px;font-size:12.5px;line-height:1.4;border-top:1px solid rgba(0,0,0,.06);padding-top:6px">' +
      '<div style="min-width:64px;color:#888">' + botHace(f.fecha) + '</div>' +
      '<div style="min-width:90px;font-weight:700;color:' + (colorEv[f.evento] || '#333') + '">' + ipEsc(f.evento) + '</div>' +
      '<div style="flex:1">' + (f.nombre ? '<b>' + ipEsc(f.nombre) + '</b> · ' : '') + '…' + ipEsc(String(f.tel).slice(-4)) + ' · ' + ipEsc(f.detalle) +
      (f.programa ? ' <span style="color:#888">· ' + ipEsc(f.programa) + '</span>' : '') + (f.variante ? ' <span style="color:#888">· variante ' + ipEsc(f.variante) + '</span>' : '') + '</div></div>';
  });
  h += '</div>';

  var c = document.getElementById('v-bot');
  c.innerHTML = h;
  document.getElementById('botD7').onclick = function (ev) { ev.preventDefault(); BOT_DIAS = 7; pintarBot(); };
  document.getElementById('botD30').onclick = function (ev) { ev.preventDefault(); BOT_DIAS = 30; pintarBot(); };
  document.getElementById('botRefrescar').onclick = function (ev) { ev.preventDefault(); pintarBot(); };
  document.getElementById('botIa').onclick = function () {
    var b = this, out = document.getElementById('botIaOut');
    b.disabled = true; b.textContent = 'Analizando…'; out.textContent = '';
    api('bot_insights', { pase: PASE, dias: 14 }).then(function (r2) {
      b.disabled = false; b.textContent = 'Analizar';
      if (!r2 || !r2.ok) { out.textContent = 'No se pudo analizar: ' + ((r2 && r2.error) || 'sin respuesta'); return; }
      out.textContent = r2.resumen + (r2.mensajes ? '\n\n(' + r2.mensajes + ' mensajes analizados' + (r2.sinRespuesta ? ', ' + r2.sinRespuesta + ' sin respuesta' : '') + ')' : '');
    });
  };
}

document.getElementById('recargar').onclick = function () { FRESCO = true; cargar(); };

/* (22-sep) CRUCE CON INSCRIPCIONES.
   La etapa la movía alguien a mano, así que la conversión del panel salía
   muy por debajo de la real y quien ya era alumno seguía en la cola. El
   Guardián sabe quién llenó el formulario de inscripción: se cruza por
   teléfono y correo y a quien coincide se le pone «Inscrito». El panel lo
   hace solo al abrir —como mucho cada media hora— y este botón lo fuerza. */
document.getElementById('cruzar').onclick = function () {
  var b = this;
  b.disabled = true; b.textContent = 'Cruzando…';
  api('cruce_inscritos', { pase: PASE }).then(function (r) {
    b.disabled = false; b.textContent = 'Cruzar con inscripciones';
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) {
      alert('No se pudo cruzar con inscripciones: ' +
        ((r && r.error) || 'sin respuesta del servidor') + '.');
      return;
    }
    alert(r.marcados
      ? (r.marcados + ' prospecto(s) quedaron como «Inscrito»:\n\n' +
         (r.quienes || []).join('\n'))
      : ('Ninguno nuevo. Se revisaron ' + r.revisados + ' fichas contra ' +
         r.inscripciones + ' inscripciones: los que ya se inscribieron ' +
         'estaban marcados.'));
    cargar();
  });
};
document.getElementById('enfoque').onclick = abrirEnfoque;

/* ── ALTA MANUAL ──────────────────────────────────────────────────────
   Quien escribe directo al WhatsApp de Admisiones no entraba a ninguna
   parte: su conversación se quedaba en la bandeja, sin etapa, sin asesor y
   sin contar en las métricas. Se captura aquí y cae en la MISMA lista, así
   que hereda la sugerencia por etapa y el semáforo de días sin tocar nada
   más. El único campo obligatorio es el teléfono: si capturar tarda, nadie
   captura mientras la persona sigue escribiendo. */
function altaMostrar(ver) {
  var caja = document.getElementById('alta');
  caja.style.display = ver ? 'block' : 'none';
  if (ver) {
    // Los programas salen de los que ya existen en la base, no de una lista
    // aparte que se quedaría vieja en cuanto se abra un programa nuevo.
    /* (9-sep) La lista salía de los prospectos ya registrados, así que con
       la base vacía —o antes de cargarla— el desplegable quedaba en blanco.
       Ahora la base es la lista OFICIAL que manda el servidor, y encima se
       agregan los nombres que aparezcan en la cartera y no estén ahí. */
    /* (17-sep) Se llenaba UNA sola vez. Si el diálogo se abrió antes de que
       llegaran los datos, el desplegable se quedaba con su opción vacía y ya
       no se recuperaba nunca. Ahora se rehace cuando la lista cambió. */
    var sel = document.getElementById('aProg');
    var listaOf = (DATOS && DATOS.programasOficiales) ? DATOS.programasOficiales.length : 0;
    if (sel.options.length <= 1 || sel.options.length - 1 < listaOf) {
      while (sel.options.length > 1) sel.remove(1);
      var lista = (DATOS && DATOS.programasOficiales) ? DATOS.programasOficiales.slice() : [];
      var vistos = {};
      lista.forEach(function (x) { vistos[x] = 1; });
      if (DATOS && DATOS.prospectos) {
        DATOS.prospectos.forEach(function (p) {
          if (p.programa && !vistos[p.programa]) { vistos[p.programa] = 1; lista.push(p.programa); }
        });
      }
      lista.forEach(function (x) {
        var o = document.createElement('option'); o.textContent = x; o.value = x; sel.appendChild(o);
      });
      document.getElementById('aOtros').innerHTML = lista.map(function (x) {
        return '<label style="font-size:12.5px;display:flex;align-items:center;gap:5px;cursor:pointer">' +
          '<input type="checkbox" class="aOtroChk" value="' + x.replace(/"/g, '&quot;') + '"> ' + x + '</label>';
      }).join('');
      document.getElementById('aOtrosCaja').style.display = lista.length ? 'block' : 'none';
    }
    document.getElementById('aMsg').textContent = '';
    // Hoy por omisión: es el caso normal, y así solo se cambia cuando la
    // conversación es de días atrás.
    var fh = document.getElementById('aFecha');
    if (!fh.value) fh.value = new Date().toISOString().slice(0, 10);
    document.getElementById('aTel').focus();
  }
}
document.getElementById('aPerfilar').onclick = function () {
  var txt = document.getElementById('aConv').value.trim();
  var msg = document.getElementById('aPerfilMsg');
  var b = document.getElementById('aPerfilar');
  if (txt.length < 20) { msg.style.color = 'var(--rojo)'; msg.textContent = 'Pega primero la conversación.'; return; }
  b.disabled = true; b.textContent = 'Leyendo…'; msg.style.color = 'var(--gris-txt)'; msg.textContent = '';
  api('perfilar', { pase: PASE, texto: txt }).then(function (r) {
    b.disabled = false; b.textContent = 'Perfilar con IA';
    if (r && r.expirado) { mostrarAcceso('Tu sesión caducó.'); return; }
    if (!r || !r.ok) { msg.style.color = 'var(--rojo)'; msg.textContent = (r && r.error) || 'No se pudo perfilar.'; return; }
    var f = r.perfil || {};
    var pon = function (id, v) { var el = document.getElementById(id); if (el && v && !el.value) el.value = v; };
    pon('aTel', f.telefono); pon('aNom', f.nombre); pon('aCorreo', '');
    // Si la conversación traía fechas, se usa la del primer mensaje.
    if (f.fecha) document.getElementById('aFecha').value = f.fecha;
    if (f.programa) {
      var sel = document.getElementById('aProg');
      for (var i = 0; i < sel.options.length; i++) { if (sel.options[i].value === f.programa) { sel.selectedIndex = i; break; } }
    }
    // Los otros programas que detectó quedan marcados para revisarlos.
    if (f.otrosProgramas) {
      var otrosDet = f.otrosProgramas.split('|').map(function (x) { return x.trim(); });
      Array.prototype.forEach.call(document.querySelectorAll('.aOtroChk'), function (c) {
        if (otrosDet.indexOf(c.value) >= 0) c.checked = true;
      });
    }
    /* «Qué preguntó» lleva la pregunta con sus palabras y, debajo, el resumen
       de en qué va: es lo que alimenta la sugerencia de mensaje después. */
    var partes = [];
    if (f.pregunta) partes.push(f.pregunta);
    if (f.resumen) partes.push('Resumen: ' + f.resumen);
    if (f.siguientePaso) partes.push('Sugerido: ' + f.siguientePaso);
    var ctx = document.getElementById('aCtx');
    if (partes.length && !ctx.value) ctx.value = partes.join('\n');
    msg.style.color = 'var(--verde)';
    msg.textContent = 'Campos llenados' + (f.etapaSugerida ? ' · etapa sugerida: ' + f.etapaSugerida : '') + '. Revísalos y registra.';
  }).catch(function () {
    b.disabled = false; b.textContent = 'Perfilar con IA';
    msg.style.color = 'var(--rojo)'; msg.textContent = 'No hubo respuesta. Intenta de nuevo.';
  });
};

document.getElementById('btnAlta').onclick = function () {
  altaMostrar(document.getElementById('alta').style.display === 'none');
};
document.getElementById('aCerrar').onclick = function () { altaMostrar(false); };

document.getElementById('aGuardar').onclick = function () {
  var b = document.getElementById('aGuardar');
  var msg = document.getElementById('aMsg');
  var tel = document.getElementById('aTel').value.trim();
  var nom = document.getElementById('aNom').value.trim();
  if (!tel && !nom) {
    msg.style.color = 'var(--rojo)';
    msg.textContent = 'Pon al menos el teléfono o el nombre.';
    return;
  }
  b.disabled = true; b.textContent = 'Registrando…';
  msg.textContent = '';
  api('alta', {
    pase: PASE,
    datos: JSON.stringify({
      telefono: tel,
      nombre:   nom,
      correo:   document.getElementById('aCorreo').value.trim(),
      /* El principal primero y luego los marcados, sin repetirlo: el orden
         importa porque el primero es el que cuenta en las métricas. */
      programas: (function () {
        var pr = document.getElementById('aProg').value;
        var otros = Array.prototype.slice.call(document.querySelectorAll('.aOtroChk:checked'))
          .map(function (c) { return c.value; })
          .filter(function (x) { return x && x !== pr; });
        return [pr].concat(otros).filter(function (x) { return x; }).join(' | ');
      })(),
      origen:   document.getElementById('aOrig').value,
      fecha:    document.getElementById('aFecha').value,
      contexto: document.getElementById('aCtx').value.trim(),
      conversacion: document.getElementById('aConv').value.trim()
    })
  }).then(function (r) {
    b.disabled = false; b.textContent = 'Registrar';
    if (r && r.ok) {
      ['aTel', 'aNom', 'aCorreo', 'aCtx', 'aConv'].forEach(function (id) {
        document.getElementById(id).value = '';
      });
      Array.prototype.forEach.call(document.querySelectorAll('.aOtroChk'), function (c) { c.checked = false; });
      document.getElementById('aFecha').value = new Date().toISOString().slice(0, 10);
      msg.style.color = 'var(--verde)';
      msg.textContent = 'Registrado y asignado a ' + (r.asignado || '') + '.';
      document.getElementById('aTel').focus();
      cargar();   // que aparezca en la cola de inmediato
    } else if (r && r.expirado) {
      PASE = null;
      try { sessionStorage.removeItem('cessum_adm_pase'); } catch (e) {}
      mostrarAcceso('Tu sesión caducó. Vuelve a entrar.');
    } else {
      msg.style.color = 'var(--rojo)';
      msg.textContent = (r && r.error) || 'No se pudo registrar.';
      // Si ya existía, se busca sola: es más útil que decir «duplicado».
      if (r && r.yaExiste) {
        document.getElementById('q').value = tel;
        altaMostrar(false);
        pintar();
      }
    }
  }).catch(function () {
    b.disabled = false; b.textContent = 'Registrar';
    msg.style.color = 'var(--rojo)';
    msg.textContent = 'No hubo respuesta. Intenta de nuevo.';
  });
};

document.getElementById('exportar').onclick = function () {
  var b = document.getElementById('exportar');
  b.disabled = true; b.textContent = 'Preparando…';
  api('exportar', { pase: PASE }).then(function (r) {
    b.disabled = false; b.textContent = 'Exportar';
    if (!r || !r.csv) { alert('No se pudo exportar.'); return; }
    // El BOM inicial es lo que hace que Excel abra los acentos bien. Sin él,
    // «Sofía» sale como «SofÃ­a» y alguien acaba corrigiendo a mano.
    var blob = new Blob(['\ufeff' + r.csv], { type: 'text/csv;charset=utf-8;' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'prospectos-cessum-' +
      new Date().toISOString().slice(0, 10) + '.csv';
    a.click();
    URL.revokeObjectURL(a.href);
  }).catch(function (e) {
    b.disabled = false; b.textContent = 'Exportar';
    alert('No se pudo exportar: ' + e);
  });
};

/* Atajos. Quien usa esto todos los días no debería tener que apuntar con el
   ratón para buscar. No se activan mientras se escribe en un campo. */
document.addEventListener('keydown', function (ev) {
  // Dentro del enfoque manda su propio juego de teclas.
  if (ENFOQUE.activo) {
    if (ev.key === 'Escape') { cerrarEnfoque(); return; }
    if (ev.target.tagName === 'INPUT' || ev.target.tagName === 'TEXTAREA') return;
    var kk = ev.key.toLowerCase();
    if (kk === 'arrowright' || ev.key === 'ArrowRight') { siguienteEnfoque(); return; }
    if (kk === 'w') { var b = document.getElementById('eWa'); if (b) b.click(); return; }
    if (kk === 'n') { document.getElementById('eNota').click(); return; }
    return;
  }
  var t = ev.target.tagName;
  if (t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT') {
    if (ev.key === 'Escape') ev.target.blur();
    return;
  }
  if (ev.ctrlKey || ev.metaKey || ev.altKey) return;
  var k = ev.key.toLowerCase();
  if (k === '/') { ev.preventDefault(); document.getElementById('q').focus(); }
  else if (k === 'r') cargar();
  else if (k === '1') { FILTRO = 'riesgo'; ver('cola'); }
  else if (k === '2') { FILTRO = 'nuevo'; ver('cola'); }
  else if (k === '3') { FILTRO = ''; ver('cola'); }
  else if (k === 't') ver('tablero');
  else if (k === 'm') ver('ritmo');
  else if (k === 'c') ver('correos');
  else if (k === 'f') abrirEnfoque();
  else if (k === 'a') { ver('cola'); altaMostrar(true); }
});

cargar();
</script>
<div id="informePub" style="display:none"></div>
</body>
</html>
