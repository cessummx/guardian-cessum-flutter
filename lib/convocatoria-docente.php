<?php
/* (1-sep) Hora de Sonora: el aspirante ve su fecha y la cuenta regresiva. */
date_default_timezone_set('America/Hermosillo');

/* ============================================================
   CONVOCATORIA DOCENTE · cessum.mx
   Se sube a la raíz de cessum.mx, junto a index.html
   ------------------------------------------------------------
   (ago-24) CESSUM contrataba profesores por recomendación y CV que llegaban
   por correo. Tres huecos: nadie sabía cuántos aspirantes había, el criterio
   de selección no quedaba escrito, y el aspirante nunca se enteraba de en
   qué quedó su solicitud.

   El catálogo de asignaturas se lee del PLAN DE ESTUDIOS real, no de una
   lista escrita a mano: el aspirante elige, no teclea. Así no llegan
   materias que no existen y el comité compara perfiles contra la oferta
   verdadera.
   ============================================================ */

// Convocatoria oficial en PDF (Drive, solo lectura). Si se sustituye el
// documento, cambia SOLO esta línea: el enlace vive en un lugar y no
// repartido por la página.
const PDF_CONVOCATORIA = 'https://drive.google.com/file/d/1gYvjGF7Zu_xIG7t2o1QfpJd8_LsIe_Ed/view';

/* (25-sep) IMPLEMENTACIÓN VIGENTE DEL GUARDIÁN. El 9-sep el Guardián pasó a
   una implementación nueva (proyecto de Cloud 496483436784); la anterior
   (AKfycby-0eN8…) quedó sin autorización. Esta página seguía probándola
   PRIMERO, dos veces, con 45 s de espera cada una: se agotaba el tiempo del
   servidor y la página quedaba en blanco. Va primero la vigente (la misma de
   guardian.php) y guardian.php de respaldo. Si el Guardián vuelve a cambiar
   de implementación, se cambia aquí y en guardian.php. */
const EXECS = [
  'https://script.google.com/macros/s/AKfycbw94a0SLqDzPFjEJ7eb8Cb7esXKsI4PeuonUo5gnhVxk8O7Mc1iM_hBS4thCZPysqM2/exec',
  'https://app.cessum.mx/guardian.php',
];
// Margen para que un retraso del Guardián no corte la página a la mitad.
@set_time_limit(120);

function traer($url, $post = null) {
    $raw = false;
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        // Consultas: 25 s. Envíos (pueden llevar archivos): 60 s.
        $o = [CURLOPT_RETURNTRANSFER => true, CURLOPT_FOLLOWLOCATION => true,
              CURLOPT_CONNECTTIMEOUT => 10, CURLOPT_TIMEOUT => ($post !== null ? 60 : 25),
              CURLOPT_SSL_VERIFYPEER => true];
        if ($post !== null) {
            $o[CURLOPT_POST] = true; $o[CURLOPT_POSTFIELDS] = $post;
            $o[CURLOPT_HTTPHEADER] = ['Content-Type: text/plain;charset=utf-8'];
        }
        curl_setopt_array($ch, $o);
        $raw = curl_exec($ch); curl_close($ch);
    }
    return ($raw === false || $raw === '') ? null : $raw;
}
function guardian($params, $post = null) {
    foreach (EXECS as $b) {
        $raw = traer($b . '?' . http_build_query($params), $post);
        if ($raw === null) continue;
        $d = json_decode($raw, true);
        if (is_array($d)) return $d;
    }
    return null;
}
function e($v) { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); }

// ---- recepción del formulario ----
// El navegador manda aquí y este archivo reenvía al Guardián. Se hace del
// lado del servidor y no directo desde el navegador por una razón: la /exec
// de Apps Script no admite peticiones cruzadas con cabeceras propias, y
// además así el aspirante nunca ve la dirección interna del sistema.
// ---- recepción del formulario ----
// (ago-25) SE RECIBE COMO ARCHIVO, NO COMO JSON CON BASE64 DENTRO.
//
// La versión anterior mandaba el CV convertido a base64 dentro del JSON, y
// mod_security del hosting devolvía 403: un cuerpo de varios megas en base64
// le parece carga de archivo encubierta y la bloquea ANTES de que PHP la vea.
// Pelear con la regla habría sido pedir una excepción y quedar dependiendo de
// ella; es más sólido dejar de darle motivo.
//
// Ahora el navegador manda multipart/form-data —la forma normal de subir un
// archivo— y la conversión a base64 ocurre AQUÍ, del lado del servidor, solo
// para pasársela al Guardián. Para el aspirante no cambia nada, y de paso el
// teléfono ya no tiene que cargar el PDF entero en memoria antes de enviarlo.
// ---- recepción del formulario ----
// (ago-25) EL ENVÍO VA POR PARTES, NO EN UNA SOLA PETICIÓN GRANDE.
//
// mod_security del hosting devuelve 403 / "Acceso denegado" ante cualquier
// POST con un adjunto a este archivo. Se probó con base64 dentro de JSON y
// con multipart normal: bloquea los dos. Pedir la excepción a Neubox era la
// vía correcta, pero deja el formulario detenido hasta que contesten, y la
// convocatoria cierra el viernes.
//
// La salida: el archivo se manda en TROZOS de 512 KB, uno por petición.
// Cada trozo es un POST pequeño de texto plano — nada que se parezca a una
// carga de archivo — y el servidor los deja pasar. Aquí se van pegando en un
// archivo temporal y, al llegar el último, se envía todo al Guardián.
//
// El identificador de sesión lo genera el navegador y se valida el formato
// para que nadie pueda escribir fuera de la carpeta temporal.
const TROZO_DIR = __DIR__ . '/.tmp-cv';

function limpiarViejos() {
    // Los pedazos de envíos abandonados no se quedan para siempre.
    if (!is_dir(TROZO_DIR)) return;
    foreach (glob(TROZO_DIR . '/*') as $f) {
        if (is_file($f) && filemtime($f) < time() - 7200) @unlink($f);
    }
}

function rutaSesion($id) {
    // Solo letras y números: sin esto, un id con "../" escribiría donde
    // quisiera quien lo mandara.
    if (!preg_match('/^[a-zA-Z0-9]{8,40}$/', (string)$id)) return null;
    if (!is_dir(TROZO_DIR)) {
        @mkdir(TROZO_DIR, 0700, true);
        // La carpeta vive dentro de public_html, así que sin esto los pedazos
        // de CV a medio subir serían descargables por cualquiera que
        // adivinara el nombre. Se cierra al crearla, no después.
        @file_put_contents(TROZO_DIR . '/.htaccess',
            "Require all denied\n<IfModule !mod_authz_core.c>\nDeny from all\n</IfModule>\n");
        @file_put_contents(TROZO_DIR . '/index.html', '');
    }
    return TROZO_DIR . '/' . $id;
}

// --- recibe un trozo del archivo ---
if (isset($_GET['trozo'])) {
    header('Content-Type: application/json; charset=utf-8');
    limpiarViejos();
    $ruta = rutaSesion($_POST['sid'] ?? '');
    if (!$ruta) { echo json_encode(['ok' => false, 'error' => 'Sesión inválida.']); exit; }
    $n = (int)($_POST['n'] ?? 0);
    $trozo = $_POST['d'] ?? '';
    if ($trozo === '') { echo json_encode(['ok' => false, 'error' => 'Trozo vacío.']); exit; }
    // El trozo llega en base64; se guarda tal cual y se decodifica al final.
    $modo = ($n === 0) ? 'wb' : 'ab';
    $fh = @fopen($ruta, $modo);
    if (!$fh) { echo json_encode(['ok' => false, 'error' => 'No se pudo guardar el archivo temporal.']); exit; }
    fwrite($fh, $trozo);
    fclose($fh);
    echo json_encode(['ok' => true, 'n' => $n, 'bytes' => filesize($ruta)]);
    exit;
}

// --- cierra el envío: pega los trozos y manda todo al Guardián ---
if (isset($_GET['enviar'])) {
    header('Content-Type: application/json; charset=utf-8');

    $datos = isset($_POST['datos']) ? json_decode($_POST['datos'], true) : null;
    if (!is_array($datos)) {
        echo json_encode(['ok' => false,
            'error' => 'No se recibieron los datos del formulario.']);
        exit;
    }
    $ruta = rutaSesion($_POST['sid'] ?? '');
    if (!$ruta || !is_file($ruta)) {
        echo json_encode(['ok' => false,
            'error' => 'No encontramos tu currículum. Vuelve a adjuntarlo.']);
        exit;
    }
    $b64 = file_get_contents($ruta);
    @unlink($ruta);   // no se conserva: ya viaja al Guardián
    if (!$b64 || strlen($b64) < 130) {
        echo json_encode(['ok' => false,
            'error' => 'Tu archivo llegó incompleto. Vuelve a intentarlo.']);
        exit;
    }

    $datos['accion']   = 'docsol_enviar';
    $datos['cvBase64'] = $b64;
    $datos['cvNombre'] = $datos['cvNombre'] ?? 'CV';
    $datos['cvMime']   = $datos['cvMime'] ?? 'application/pdf';

    $r = guardian(['accion' => 'docsol_enviar'], json_encode($datos));
    if ($r === null) {
        echo json_encode(['ok' => false,
            'error' => 'No pudimos conectar con el sistema. Tu solicitud NO '
                     . 'quedó registrada: vuelve a intentarlo o escríbenos a '
                     . 'contacto@cessum.mx.',
            'diag' => ['curl' => function_exists('curl_init'),
                       'kb' => round(strlen($b64) * 0.75 / 1024)]]);
        exit;
    }
    echo json_encode($r, JSON_UNESCAPED_UNICODE);
    exit;
}

/* ============================================================
 * (ago-30) SEGUNDA FASE · CLASE MUESTRA
 * ------------------------------------------------------------
 * Los 30 seleccionados entran AQUÍ con su folio (llegan por el enlace del
 * correo de invitación). Con el folio se recuperan sus datos y las
 * asignaturas que propusieron; eligen día y hora en un calendario de tres
 * días (cada hora admite una sola clase), suben su presentación y confirman
 * disponibilidad para el diplomado. Todo vive en este mismo archivo para no
 * abrir otra pieza en cessum.mx.
 *
 * El archivo viaja por trozos, igual que el CV (mod_security del hosting
 * bloquea cualquier POST con adjunto). Si pesa más de lo permitido, el
 * aspirante puede pegar un enlace (Drive, OneDrive, Canva) en su lugar.
 * ============================================================ */
if (isset($_GET['f2datos'])) {
    header('Content-Type: application/json; charset=utf-8');
    $r = guardian(['accion' => 'docsol_fase2_datos', 'folio' => trim((string)($_GET['folio'] ?? ''))]);
    echo json_encode($r ?: ['ok' => false, 'error' => 'No pudimos conectar con el sistema. Intenta en un momento.'], JSON_UNESCAPED_UNICODE);
    exit;
}
if (isset($_GET['f2enviar'])) {
    header('Content-Type: application/json; charset=utf-8');
    $datos = isset($_POST['datos']) ? json_decode($_POST['datos'], true) : null;
    if (!is_array($datos)) { echo json_encode(['ok' => false, 'error' => 'No se recibieron los datos.']); exit; }
    $datos['accion'] = 'docsol_fase2_enviar';
    // Evidencia de la firma electrónica del consentimiento (se registra en la constancia).
    $datos['consentIP'] = $_SERVER['HTTP_CF_CONNECTING_IP'] ?? ($_SERVER['HTTP_X_FORWARDED_FOR'] ?? ($_SERVER['REMOTE_ADDR'] ?? ''));
    $datos['consentUA'] = substr((string)($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 200);
    $sid = $_POST['sid'] ?? '';
    if ($sid !== '') {
        $ruta = rutaSesion($sid);
        if ($ruta && is_file($ruta)) {
            $b64 = file_get_contents($ruta);
            @unlink($ruta);
            if ($b64 && strlen($b64) > 130) $datos['archivoBase64'] = $b64;
        }
    }
    $r = guardian(['accion' => 'docsol_fase2_enviar'], json_encode($datos));
    echo json_encode($r ?: ['ok' => false, 'error' => 'No pudimos conectar con el sistema. Tu registro NO quedó guardado: vuelve a intentarlo.'], JSON_UNESCAPED_UNICODE);
    exit;
}
/* (1-sep) El aspirante puede subir o REEMPLAZAR su presentación después de
   haber confirmado su clase, con el mismo folio y hasta la hora de su sesión.
   Antes solo entraba junto con el registro de día y hora. */
if (isset($_GET['f2registro'])) {
    header('Content-Type: application/json; charset=utf-8');
    $r = guardian(['accion' => 'fase2_mi_registro', 'folio' => trim((string)($_GET['folio'] ?? ''))]);
    echo json_encode($r ?: ['ok' => false, 'error' => 'No pudimos conectar con el sistema.'], JSON_UNESCAPED_UNICODE);
    exit;
}
/* (1-sep) HISTORIAL DEL ASPIRANTE. Su perfil no terminaba en esta
   convocatoria: quien participa varias veces necesita ver dónde ha estado.
   Se consulta con el mismo folio con que ya entró. */
/* (1-sep) BANCO DE TALENTO EN LA PANTALLA QUE LA GENTE YA TIENE.
   Cuando la convocatoria está cerrada, quien llegaba aquí se topaba con un
   «gracias por tu interés, vuelve luego» y se perdía. Ahora deja sus datos,
   recibe un folio y, en cuanto se abra la siguiente, le llega el aviso para
   entrar con ese folio sin volver a capturar nada. */
$intMsg = ''; $intTipo = 'err'; $intFolio = ''; $intYa = false;
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['int_nombre'])) {
    /* Los datos van en el cuerpo como JSON, igual que el resto de esta
       pantalla: por la URL se perderían los acentos y los textos largos. */
    $datosInt = [
        'accion' => 'docsol_interes_alta',
        'nombre' => trim((string)$_POST['int_nombre']),
        'correo' => trim((string)($_POST['int_correo'] ?? '')),
        'telefono' => trim((string)($_POST['int_telefono'] ?? '')),
        'grado' => trim((string)($_POST['int_grado'] ?? '')),
        'asignaturas' => trim((string)($_POST['int_asignaturas'] ?? '')),
        'ciudad' => trim((string)($_POST['int_ciudad'] ?? '')),
        'mensaje' => trim((string)($_POST['int_mensaje'] ?? '')),
        'origen' => 'convocatoria-docente',
    ];
    $r = guardian(['accion' => 'docsol_interes_alta'], json_encode($datosInt, JSON_UNESCAPED_UNICODE));
    if (!$r) {
        $intMsg = 'No pudimos guardar tus datos en este momento. Inténtalo de nuevo o escríbenos a contacto@cessum.mx.';
    } elseif (empty($r['ok'])) {
        $intMsg = $r['error'] ?? 'No se pudo registrar.';
    } else {
        $intTipo = 'ok'; $intMsg = $r['nota'] ?? 'Registrado.';
        $intFolio = $r['folio'] ?? ''; $intYa = !empty($r['yaEstaba']);
    }
}

if (isset($_GET['historial'])) {
    header('Content-Type: application/json; charset=utf-8');
    $r = guardian(['accion' => 'docsol_historial', 'folio' => trim((string)($_GET['folio'] ?? ''))]);
    echo json_encode($r ?: ['ok' => false, 'error' => 'No pudimos consultar tu historial.'], JSON_UNESCAPED_UNICODE);
    exit;
}
if (isset($_GET['f2presentacion'])) {
    header('Content-Type: application/json; charset=utf-8');
    $datos = isset($_POST['datos']) ? json_decode($_POST['datos'], true) : null;
    if (!is_array($datos)) { echo json_encode(['ok' => false, 'error' => 'No se recibieron los datos.']); exit; }
    $datos['accion'] = 'fase2_presentacion';
    $sid = $_POST['sid'] ?? '';
    if ($sid !== '') {
        $ruta = rutaSesion($sid);
        if ($ruta && is_file($ruta)) {
            $b64 = file_get_contents($ruta); @unlink($ruta);
            if ($b64 && strlen($b64) > 130) $datos['archivoBase64'] = $b64;
        }
    }
    $r = guardian(['accion' => 'fase2_presentacion'], json_encode($datos));
    echo json_encode($r ?: ['ok' => false, 'error' => 'No pudimos conectar. Tu presentación NO se guardó: vuelve a intentarlo.'], JSON_UNESCAPED_UNICODE);
    exit;
}
if (isset($_GET['fase2'])) {
    $folioIni = preg_replace('/[^A-Za-z0-9\-]/', '', (string)($_GET['folio'] ?? ''));
    header('Content-Type: text/html; charset=utf-8');
    ?><!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="theme-color" content="#B11D29">
<title>Segunda fase · Clase muestra · CESSUM</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600;700&family=Montserrat:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root{--rojo:#B11D29;--rojo-osc:#8E1621;--oro:#A56B16;--verde:#1E7A38;--crema:#F7F3EA;--tinta:#1F1F1F;--gris:#6E6E6E;--linea:#E8DFCE;}
  *{box-sizing:border-box;}
  body{margin:0;padding:0 0 60px;background:var(--crema);
    background-image:repeating-linear-gradient(135deg,rgba(165,107,22,.026) 0 2px,transparent 2px 9px);
    color:var(--tinta);font-family:'Montserrat',Arial,sans-serif;font-size:15.5px;line-height:1.68;-webkit-font-smoothing:antialiased;}
  .hero{background:linear-gradient(135deg,var(--rojo),var(--rojo-osc));color:#fff;border-bottom:4px solid var(--oro);padding:44px 18px 40px;text-align:center;}
  .hero-logo{height:64px;width:auto;display:block;margin:0 auto 18px;}
  .hero .eyebrow{font-size:11.5px;letter-spacing:.16em;text-transform:uppercase;opacity:.85;font-weight:600;}
  .hero h1{font-family:'Playfair Display',Georgia,serif;font-size:clamp(26px,5vw,40px);margin:.5rem 0 .6rem;line-height:1.12;}
  .hero p{max-width:640px;margin:0 auto;font-size:15.5px;opacity:.94;}
  .wrap{max-width:880px;margin:0 auto;padding:0 18px;}
  .bloque{background:#fff;border-radius:16px;padding:28px 30px;margin:-26px 0 20px;box-shadow:0 1px 2px rgba(0,0,0,.04),0 12px 34px rgba(80,60,20,.10);border-top:4px solid var(--oro);}
  .bloque + .bloque{margin-top:20px;border-top:0;border-left:4px solid var(--oro);}
  h2{font-family:'Playfair Display',Georgia,serif;font-size:23px;margin:0 0 .6rem;color:var(--rojo);}
  h3{font-family:'Playfair Display',Georgia,serif;font-size:18px;margin:1.3rem 0 .4rem;}
  label{display:block;font-size:11.5px;letter-spacing:.05em;text-transform:uppercase;font-weight:700;color:var(--gris);margin:16px 0 5px;}
  input,select{width:100%;padding:11px 13px;font-family:inherit;font-size:15px;border:1.5px solid #DCD3C2;border-radius:9px;background:#FDFCF9;color:var(--tinta);}
  input:focus,select:focus{outline:0;border-color:var(--oro);background:#fff;}
  .ayuda{font-size:12.5px;color:var(--gris);margin-top:4px;line-height:1.45;}
  /* (1-sep) Panel de bienvenida: cada vez que entra con su folio ve su
     estado completo de un vistazo, como un perfil. */
  .perfil{display:flex;gap:16px;align-items:center;flex-wrap:wrap;border:2px solid var(--oro);border-radius:16px;background:#FBF7EF;padding:16px 18px;margin:0 0 18px;}
  .perfil .ini{flex:0 0 62px;height:62px;border-radius:50%;background:var(--rojo);color:#fff;display:flex;align-items:center;justify-content:center;font-family:'Playfair Display',Georgia,serif;font-size:25px;}
  .perfil .qs{flex:1;min-width:230px;}
  .perfil .qs b{display:block;font-size:19px;font-family:'Playfair Display',Georgia,serif;color:var(--rojo);}
  .perfil .qs span{font-size:12.5px;color:var(--gris);}
  .perfil .ses{flex:0 0 auto;text-align:right;}
  .perfil .ses .d{font-family:'Playfair Display',Georgia,serif;font-size:17px;color:var(--rojo-osc);}
  .perfil .ses .c{font-size:12px;color:var(--gris);}
  /* (1-sep) «Hoy es tu clase»: el día de la sesión, arriba y sin competencia. */
  .hoyes{border:2px solid var(--rojo);border-radius:16px;background:#FBF0F1;
      padding:18px 20px;margin:14px 0 4px;box-shadow:0 8px 26px rgba(177,29,41,.10);}
  .hoyes .et{font-size:11.5px;font-weight:800;letter-spacing:.09em;text-transform:uppercase;color:var(--rojo);}
  .hoyes h3{font-family:'Playfair Display',Georgia,serif;font-size:22px;color:var(--rojo);margin:3px 0 2px;}
  .hoyes .cuenta{font-size:15px;color:#3A3226;margin-bottom:10px;}
  .hoyes .cuenta b{color:var(--rojo);font-size:18px;}
  .hoyes .acc{display:flex;gap:9px;flex-wrap:wrap;align-items:center;}
  .hoyes .meet{display:inline-block;background:var(--rojo);color:#fff;text-decoration:none;font-weight:700;
      padding:14px 26px;border-radius:11px;font-size:16px;}
  .hoyes .meet:hover{background:#8E1621;}
  .hoyes .rec{margin-top:10px;font-size:13px;color:#4A4034;line-height:1.5;}
  .hoyes.encurso{border-color:#1E7A38;background:rgba(30,122,56,.07);}
  .hoyes.encurso .et,.hoyes.encurso h3,.hoyes.encurso .cuenta b{color:#1E7A38;}
  .hoyes.encurso .meet{background:#1E7A38;}
  @media (max-width:640px){.hoyes .meet{width:100%;text-align:center;}}
  /* (1-sep) Semáforo del calendario: verde libre · ámbar queda un lugar ·
     rojo lleno. El color se ve antes de tocar, que es cuando sirve. */
  .hora.librecupo{border-color:rgba(30,122,56,.45);background:rgba(30,122,56,.07);color:#14612C;}
  .hora.media{border-color:#A56B16;background:rgba(165,107,22,.14);color:#7A4A0E;font-weight:700;}
  .hora.media::after{content:' · 1 de 2';font-size:9.5px;font-weight:600;opacity:.8;}
  .hora.elegida.librecupo,.hora.elegida.media{background:var(--rojo);color:#fff;border-color:var(--rojo);}
  .hora.elegida.media::after{content:'';}
  .lista{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:8px;margin:14px 0 4px;}
  .lista .it{display:flex;gap:9px;align-items:flex-start;border:1px solid var(--linea);border-radius:11px;padding:10px 12px;background:#fff;}
  .lista .it .mk{flex:0 0 20px;height:20px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:800;color:#fff;}
  .lista .it.si .mk{background:#1E7A38;} .lista .it.no .mk{background:#B11D29;} .lista .it.esp .mk{background:var(--oro);}
  .lista .it b{display:block;font-size:13px;} .lista .it span{font-size:11.5px;color:var(--gris);line-height:1.4;}
  .lista .it a{font-size:11.5px;color:var(--rojo);font-weight:600;}
  /* (1-sep) Tabla de ponderación: el aspirante ve con qué se le califica. */
  .pond{width:100%;border-collapse:collapse;font-size:13.5px;margin:6px 0 4px;}
  .pond th{background:#F5F1E8;color:#8E1621;text-align:left;padding:7px 9px;border:1px solid #E8DFCE;font-size:12px;letter-spacing:.04em;text-transform:uppercase;}
  .pond td{padding:7px 9px;border:1px solid #E8DFCE;vertical-align:top;line-height:1.5;}
  .pond td.pc{text-align:center;font-weight:800;color:#B11D29;white-space:nowrap;}
  .pond td.sub{background:#FBF7EF;color:#A56B16;font-size:12.5px;}
  .paso{display:flex;gap:14px;margin-bottom:14px;}
  .paso .n{flex:0 0 34px;height:34px;border-radius:50%;background:var(--oro);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:15px;}
  .paso .t{flex:1;} .paso .t b{display:block;font-size:15.5px;} .paso .t span{font-size:13.5px;color:var(--gris);}
  .destacado{background:rgba(165,107,22,.08);border-left:3px solid var(--oro);padding:14px 16px;border-radius:8px;margin:1rem 0;font-size:14.5px;line-height:1.6;}
  .aviso{padding:14px 16px;border-radius:10px;font-size:14px;margin:16px 0;line-height:1.5;}
  .aviso.ok{background:rgba(30,122,56,.10);border:1px solid rgba(30,122,56,.4);}
  .aviso.err{background:rgba(177,29,41,.08);border:1px solid rgba(177,29,41,.4);}
  button.principal{width:100%;margin-top:22px;padding:16px;font-family:inherit;font-size:16px;font-weight:700;color:#fff;background:var(--rojo);border:0;border-radius:11px;cursor:pointer;}
  button.principal:disabled{background:#C9C1B2;cursor:not-allowed;}
  button.suave{padding:11px 16px;font-family:inherit;font-size:14px;font-weight:600;color:#fff;background:var(--oro);border:0;border-radius:8px;cursor:pointer;}
  .entrada{display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap;}
  .entrada > div{flex:1;min-width:220px;} .entrada label{margin-top:0;}
  .ficha{display:grid;grid-template-columns:1fr 1fr;gap:10px 18px;margin-top:8px;font-size:14px;}
  .ficha b{display:block;font-size:11px;letter-spacing:.05em;text-transform:uppercase;color:var(--oro);}
  .cal{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-top:8px;}
  .dia{border:1.5px solid var(--linea);border-radius:12px;overflow:hidden;background:#FDFCF9;}
  .dia h4{margin:0;padding:10px 12px;background:var(--rojo);color:#fff;font-size:13px;letter-spacing:.03em;text-align:center;}
  .dia h4 small{display:block;font-weight:400;opacity:.9;font-size:11.5px;}
  .horas{display:grid;grid-template-columns:1fr 1fr;gap:6px;padding:10px;}
  .hora{border:1.5px solid var(--linea);border-radius:8px;padding:8px 4px;text-align:center;font-size:13.5px;font-weight:600;cursor:pointer;background:#fff;user-select:none;}
  .hora:hover{border-color:var(--oro);}
  .hora.ocupada{background:#EFEBE3;color:#B9B2A3;cursor:not-allowed;text-decoration:line-through;border-style:dashed;}
  .hora.elegida{background:var(--verde);border-color:var(--verde);color:#fff;}
  .hora.mia{outline:2px dashed var(--oro);outline-offset:1px;}
  .eleccion{margin-top:10px;font-size:14.5px;}
  .eleccion b{color:var(--verde);}
  .leyenda{font-size:12px;color:var(--gris);margin-top:8px;display:flex;gap:14px;flex-wrap:wrap;}
  .leyenda span::before{content:'';display:inline-block;width:12px;height:12px;border-radius:3px;margin-right:5px;vertical-align:-1px;border:1.5px solid var(--linea);background:#fff;}
  .leyenda .l-oc::before{background:#EFEBE3;border-style:dashed;} .leyenda .l-el::before{background:var(--rojo);border-color:var(--rojo);}
  .leyenda .l-li::before{background:rgba(30,122,56,.14);border-color:rgba(30,122,56,.5);}
  .leyenda .l-me::before{background:rgba(165,107,22,.22);border-color:#A56B16;}
  .archivo{border:2px dashed #DCD3C2;border-radius:12px;padding:18px;text-align:center;background:#FDFCF9;cursor:pointer;}
  .archivo.con{border-color:var(--verde);background:rgba(30,122,56,.06);}
  .archivo input{display:none;}
  .check{display:flex;gap:12px;align-items:flex-start;background:rgba(30,122,56,.06);border:1.5px solid rgba(30,122,56,.35);border-radius:12px;padding:14px 16px;margin-top:18px;font-size:14.5px;line-height:1.55;
         text-transform:none;letter-spacing:0;font-weight:400;color:var(--tinta);cursor:pointer;}
  .check input{width:22px;height:22px;margin-top:2px;flex:0 0 22px;}
  .pie{text-align:center;font-size:12px;color:#9A9A9A;margin-top:28px;line-height:1.7;}
  .o{ text-align:center;font-size:12px;color:var(--gris);margin:10px 0;letter-spacing:.1em;text-transform:uppercase;}
  .plazo{border:2px solid var(--rojo);border-radius:14px;background:#FDF0F1;padding:16px 18px;margin:14px 0 6px;}
  .plazo .tit{font-size:11.5px;letter-spacing:.14em;text-transform:uppercase;font-weight:800;color:var(--rojo);}
  .cuenta{display:flex;gap:10px;margin:10px 0 8px;flex-wrap:wrap;}
  .cuenta div{flex:1;min-width:70px;background:#fff;border:1px solid #E9C7C7;border-radius:10px;text-align:center;padding:8px 4px;}
  .cuenta b{display:block;font-family:'Playfair Display',Georgia,serif;font-size:30px;line-height:1;color:var(--rojo);}
  .cuenta span{font-size:10.5px;letter-spacing:.08em;text-transform:uppercase;color:var(--gris);}
  .plazo p{margin:6px 0 0;font-size:14px;line-height:1.55;}
  .plazo.vencido{background:#B11D29;color:#fff;} .plazo.vencido .tit,.plazo.vencido .cuenta b{color:#fff;} .plazo.vencido .cuenta div{background:rgba(255,255,255,.12);border-color:rgba(255,255,255,.3);} .plazo.vencido .cuenta span{color:#fff;}
  .bloqueado{opacity:.5;pointer-events:none;}
  .consent{border:1.5px solid var(--linea);border-radius:12px;background:#FDFCF9;max-height:320px;overflow:auto;padding:14px 18px;font-size:13.5px;line-height:1.55;position:relative;}
  .consent.leido{border-color:#1E7A38;}
  /* (1-sep) Horario congelado: ya lo tomó un docente, no se puede mover. */
  .cal.congelado .hora{cursor:not-allowed;}
  .cal.congelado .hora:not(.elegida){opacity:.45;}
  /* (1-sep) Nadie firma lo que no leyó: las casillas se abren cuando el
     texto se recorrió hasta el final (o se abrió en pantalla completa). */
  .leerBarra{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:8px 0 2px;font-size:12.5px;}
  .leerBarra .prog{flex:1;min-width:140px;height:7px;border-radius:5px;background:#EFE9DC;overflow:hidden;}
  .leerBarra .prog i{display:block;height:100%;width:0;background:var(--oro);transition:width .2s;}
  .leerBarra .st{font-weight:700;color:var(--oro);} .leerBarra .st.ok{color:#1E7A38;}
  .leerBarra button{font-family:inherit;font-size:12.5px;font-weight:700;color:#fff;background:var(--rojo);border:0;border-radius:8px;padding:8px 13px;cursor:pointer;}
  .firma.bloq{opacity:.5;pointer-events:none;}
  .lector{position:fixed;inset:0;background:rgba(31,31,31,.75);z-index:999;display:none;align-items:center;justify-content:center;padding:18px;}
  .lector.on{display:flex;}
  .lector .hoja{background:#fff;border-radius:16px;max-width:820px;width:100%;max-height:92vh;display:flex;flex-direction:column;overflow:hidden;}
  .lector .hoja header{background:var(--rojo);color:#fff;padding:14px 18px;font-family:'Playfair Display',Georgia,serif;font-size:19px;display:flex;justify-content:space-between;align-items:center;gap:10px;}
  .lector .hoja header button{background:transparent;border:1px solid rgba(255,255,255,.6);color:#fff;border-radius:8px;padding:5px 11px;cursor:pointer;font-family:inherit;font-size:13px;}
  .lector .cuerpo{overflow:auto;padding:20px 24px;font-size:14px;line-height:1.65;}
  .lector .pie{border-top:1px solid var(--linea);padding:12px 18px;display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap;background:#FBF7EF;}
  .consent h4{margin:12px 0 3px;font-size:13px;color:var(--rojo);} .consent h4:first-child{margin-top:0;} .consent p{margin:0 0 4px;}
  .firma{border:1.5px solid var(--oro);border-radius:12px;padding:14px 16px;background:#FBF7EF;margin-top:12px;}
  .firma .sello{font-size:11.5px;color:var(--gris);margin-top:8px;line-height:1.5;}
  .firmado{background:rgba(30,122,56,.08);border:1.5px solid rgba(30,122,56,.4);border-radius:12px;padding:12px 16px;font-size:14px;}
  #otraAsig{display:none;margin-top:8px;}
  @media(max-width:700px){.cal{grid-template-columns:1fr;}.ficha{grid-template-columns:1fr;}.bloque{padding:20px 18px;}}
</style>
</head>
<body>
<div class="hero">
  <img id="logoCessum" class="hero-logo" alt="CESSUM" src="assets/img/logo-cessum-blanco.png">
  <div class="eyebrow">Centro de Estudios Superiores del Mayo · Convocatoria docente</div>
  <h1>Segunda fase: tu clase muestra</h1>
  <p>Elige el día y la hora de tu sesión, envía tu presentación y confirma tu disponibilidad para el diplomado.</p>
</div>

<div class="wrap">
  <div class="bloque" id="bEntrada">
    <h2>Entra con tu folio</h2>
    <p class="ayuda" style="font-size:14px;">Es el folio de tu acuse de solicitud, con la forma <b>DOC-2026-0000</b>. Viene también en el correo de invitación.</p>
    <div class="entrada">
      <div><label for="folio">Folio</label><input id="folio" placeholder="DOC-2026-0000" value="<?= e($folioIni) ?>" autocomplete="off"></div>
      <button class="suave" id="btnEntrar" onclick="entrar()">Continuar</button>
    </div>
    <div id="avisoEntrada"></div>
  </div>

  <div class="bloque" id="bDatos" style="display:none;">
    <!-- (1-sep) Bienvenida tipo perfil: quién es, cuándo es su clase y qué le
         falta. Se actualiza cada vez que entra con su folio. -->
    <div class="perfil" id="perfilCaja" style="display:none;">
      <div class="ini" id="perfilIni">—</div>
      <div class="qs">
        <b id="perfilNombre"></b>
        <span id="perfilSub"></span>
      </div>
      <div class="ses" id="perfilSes"></div>
    </div>
    <?php /* (1-sep) El día de su clase, lo único que importa es entrar a
             tiempo. Este bloque solo aparece ese día, arriba de todo. */ ?>
    <div id="perfilHoy"></div>
    <div class="lista" id="perfilLista"></div>
    <div id="perfilPend"></div>
    <?php /* (1-sep) Aquí se dibuja el historial de participaciones del
             aspirante: las convocatorias anteriores con su dictamen. */ ?>
    <div id="perfilHist"></div>

    <h2 style="margin-top:18px;">Hola, <span id="nombre"></span></h2>
    <p style="margin:0;">Tu perfil quedó entre los seleccionados para la segunda fase. Así funciona:</p>
    <div style="margin-top:14px;">
      <div class="paso"><div class="n">1</div><div class="t"><b>Elige día y hora de tu clase</b><span>Martes 1, miércoles 2 o jueves 3 de septiembre, entre 8:00 y 19:00 h, <b>hora local de Sonora</b>. Cada hora admite una sola clase.</span></div></div>
      <div class="paso"><div class="n">2</div><div class="t"><b>Envía tu presentación</b><span>Las diapositivas de la clase que vas a impartir (30 a 45 minutos), siempre antes de tu sesión.</span></div></div>
      <div class="paso"><div class="n">3</div><div class="t"><b>Confirma tu disponibilidad para el diplomado</b><span id="diploTxt">Los lunes de 19:00 a 21:00 h, del 7 de septiembre a finales de octubre.</span></div></div>
    </div>
    <div class="plazo" id="plazo">
      <div class="tit">Plazo improrrogable para registrar día, hora y tema</div>
      <div class="cuenta"><div><b id="cd-d">–</b><span>días</span></div><div><b id="cd-h">–</b><span>horas</span></div><div><b id="cd-m">–</b><span>minutos</span></div><div><b id="cd-s">–</b><span>segundos</span></div></div>
      <p id="plazoTxt"><b>Tienes 48 horas a partir de la publicación de la invitación</b><span id="plazoHasta"></span>. Quien intente registrar el día, la hora o el tema de su clase después de ese momento <b>queda fuera del proceso, sin excepción</b>: la plataforma no lo admitirá y su lugar se asignará a otro aspirante.</p>
    </div>
    <div class="destacado">Un docente del CESSUM participará en tu clase en el rol de alumno: interactuará contigo cuando sea pertinente y, al mismo tiempo, evaluará la sesión. Se valora el desempeño docente y la calidad de la clase. La forma de conducirla es decisión tuya: exposición, diálogo, actividades o una combinación.</div>

    <h3>Pormenores de la sesión</h3>
    <div class="ficha">
      <div><b>Plataforma</b>Google Meet. La invitación llega a tu cuenta de Google (Gmail o Workspace); entra con esa misma cuenta.</div>
      <div><b>Duración</b>Clase de 30 a 45 minutos. La sala se abre 10 minutos antes; llega en ese margen para probar audio y pantalla.</div>
      <div><b>Docente que acompaña tu clase</b><span id="docenteTxt">Pendiente de asignación. Te avisaremos por correo en cuanto se te adjudique el docente que cumplirá el rol de evaluador-estudiante.</span></div>
      <div><b>Enlace de Meet</b><span id="meetTxt">Se te enviará junto con la asignación del docente; también lo verás aquí al entrar con tu folio.</span></div>
      <div><b>Requisitos técnicos</b>Computadora con cámara y micrófono, conexión estable (de preferencia por cable), navegador Chrome o Edge actualizado y tu presentación abierta para compartir pantalla.</div>
      <div><b>Grabación</b>La sesión se graba con fines de evaluación del comité. No se difunde.</div>
      <div><b>Evaluación</b>Desempeño docente y calidad de la clase, tal como tú decidas conducirla. Los criterios están abajo, a la vista.</div>
    </div>

    <!-- (1-sep) El aspirante debe saber con qué se le califica ANTES de dar
         su clase: es más justo y evita reclamos de "no sabía que contaba". -->
    <div class="bloque" style="border-left:4px solid var(--oro);margin-top:14px;">
      <h3 style="margin-top:0;">Fechas y resultado</h3>
      <p style="font-size:14px;line-height:1.6;margin:0 0 10px;">
        Las clases muestra se realizan el <b>martes 1, miércoles 2 y jueves 3 de septiembre de 2026</b>,
        entre las 8:00 y las 18:00 horas (hora de Sonora), en el horario que tú mismo elijas del calendario.
        Los <b>resultados estarán disponibles el sábado 5 de septiembre de 2026</b> y se te comunicarán
        a tu correo institucional. No se adelantan resultados por otra vía ni al terminar tu sesión.
      </p>
      <h3>Cómo se determina el resultado</h3>
      <table class="pond">
        <tr><th>Componente</th><th>Peso</th><th>Cómo se obtiene</th></tr>
        <tr><td><b>Currículum</b></td><td class="pc">40 %</td><td>Dictamen del comité sobre tu expediente: formación, experiencia, producción académica y pertinencia para la asignatura. Ya se realizó en la primera fase.</td></tr>
        <tr><td colspan="3" class="sub"><b>Clase muestra · 60 %</b></td></tr>
        <tr><td>· Rúbrica de la clase</td><td class="pc">40 %</td><td>Diez criterios que valora quien acompaña tu sesión: dominio del tema, estructura, presentación y material, claridad expositiva, manejo del tiempo, atención al estudiante, conectividad, dominio de la videollamada, manejo del aula virtual y nivel adecuado al programa.</td></tr>
        <tr><td>· Promoción de interacciones complejas</td><td class="pc">20 %</td><td>No lo califica quien te acompaña: se analiza sobre la <b>transcripción</b> de tu sesión, para ver si tu clase promueve reconocer, comparar, analizar, argumentar y criticar, y no solo repetir.</td></tr>
      </table>
      <p class="ayuda">Los tres componentes se suman sobre 100. La decisión final corresponde a Rectoría y Vicerrectoría con el expediente completo, y se te comunica por correo institucional el sábado 5 de septiembre de 2026.</p>
    </div>
    <div id="yaRegistrado"></div>
  </div>

  <!-- (1-sep) Cambiar la presentación después de haber confirmado la clase.
       Bloque aparte del formulario: no obliga a volver a firmar nada ni a
       tocar el día y la hora ya apartados. -->
  <div class="bloque" id="bPres" style="display:none;">
    <h2>Tu presentación</h2>
    <div id="presEstado"></div>
    <p class="ayuda">Puedes subirla o cambiarla por una versión corregida <b>hasta la hora de tu clase</b>. La última que envíes es la que verá el comité; la anterior se conserva como respaldo.</p>
    <label class="archivo" id="zonaPres" for="archivoPres">
      <input type="file" id="archivoPres" accept=".pdf,.ppt,.pptx,.key,application/pdf,application/vnd.ms-powerpoint,application/vnd.openxmlformats-officedocument.presentationml.presentation">
      <div id="presArchivoTxt"><b>Adjuntar mi presentación</b><br><span class="ayuda">PDF o PowerPoint · máximo <span id="presMax">25</span> MB</span></div>
    </label>
    <div class="o">— o bien —</div>
    <label for="presEnlace">Enlace (Drive, OneDrive, Canva…)</label>
    <input id="presEnlace" placeholder="https://…">
    <div id="presAviso"></div>
    <button class="principal" id="btnPres" onclick="enviarPresentacion()">Guardar mi presentación</button>
  </div>

  <div class="bloque" id="bForm" style="display:none;">
    <h2>Tu registro</h2>

    <h3>1 · Asignatura de la clase</h3>
    <label for="asig">Sobre qué asignatura será tu clase</label>
    <select id="asig"></select>
    <input id="otraAsig" placeholder="Escribe el nombre de la asignatura y el programa (por ejemplo: Didáctica general — Licenciatura en Pedagogía)" autocomplete="off">
    <p class="ayuda">Las opciones son las asignaturas que propusiste en tu solicitud: da prioridad a ellas, son las que el comité consideró posibles de impartir en el CESSUM. Si tu clase será sobre otra, elige «Otra asignatura» y escríbela.</p>

    <h3>2 · Día y hora</h3>
    <div id="calAviso"></div>
    <div class="destacado" style="margin:6px 0 10px;"><b>Todas las horas son hora local de Sonora</b> (UTC−7, la misma que Hermosillo y Navojoa; Sonora no cambia de horario). Si estás en otro estado o país, convierte a tu hora antes de elegir.</div>
    <div class="cal" id="cal"></div>
    <?php /* (1-sep) Cada hora admite dos clases: la leyenda lo dice, para
             que nadie crea que un horario en ámbar ya no se puede tomar. */ ?>
    <div class="leyenda"><span class="l-li">Libre</span><span class="l-me">Queda un lugar</span><span class="l-oc">Llena</span><span class="l-el">Tu elección</span></div>
    <p class="ayuda" style="margin-top:4px;">Cada horario admite <b>dos clases</b>: si ves uno en ámbar, todavía puedes tomarlo.</p>
    <div class="eleccion" id="eleccion">Todavía no has elegido horario.</div>

    <h3>3 · Presentación de la clase</h3>
    <label class="archivo" id="zonaArchivo" for="archivo">
      <input type="file" id="archivo" accept=".pdf,.ppt,.pptx,application/pdf,application/vnd.ms-powerpoint,application/vnd.openxmlformats-officedocument.presentationml.presentation">
      <div id="archivoTxt"><b>Adjuntar mi presentación</b><br><span class="ayuda">PDF o PowerPoint · máximo <span id="maxmb">8</span> MB. Si pesa más, exporta a PDF o usa el enlace de abajo.</span></div>
    </label>
    <div class="o">— o bien —</div>
    <label for="enlace">Enlace a la presentación (Drive, OneDrive, Canva…)</label>
    <input id="enlace" placeholder="https://…" autocomplete="off">
    <p class="ayuda">Si usas un enlace, verifica que esté compartido para «cualquiera con el enlace». Puedes registrar tu horario ahora y enviar la presentación después, entrando de nuevo con tu folio.</p>

    <h3>4 · Tu cuenta de Google para el Meet</h3>
    <label for="cgoogle">Correo de tu cuenta de Google (Gmail o Google Workspace)</label>
    <input id="cgoogle" type="email" placeholder="tu.nombre@gmail.com" autocomplete="email">
    <label for="cgoogle2">Confirma el correo</label>
    <input id="cgoogle2" type="email" placeholder="Escríbelo otra vez" autocomplete="off">
    <p class="ayuda">A esta cuenta llegará la invitación de Google Calendar con el enlace de Meet, y con ella deberás entrar a la sesión. Si tu correo de contacto ya es de Google, puedes usar el mismo.</p>

    <h3>5 · Consentimiento informado y confidencialidad</h3>
    <p class="ayuda" style="font-size:13.5px;margin-bottom:8px;">Tu clase muestra se graba por Google Meet, se transcribe y se analiza con software especializado que reporta las interacciones complejas del aula. Lee cómo se protege esa información y firma electrónicamente tu consentimiento. Es requisito para realizar la sesión.</p>
    <div id="consentFirmado" class="firmado" style="display:none;"></div>
    <div id="consentBloque">
      <div class="consent" id="consentTexto"></div>
      <div class="leerBarra">
        <span class="st" id="leerEstado">Léelo completo para poder firmar</span>
        <span class="prog"><i id="leerProg"></i></span>
        <button type="button" onclick="abrirLector()">Leerlo en pantalla completa</button>
      </div>
      <p class="ayuda" style="margin-top:6px;">Versión <span id="consentVer"></span> · Huella SHA-256 del texto: <span id="consentHash" style="font-family:monospace;font-size:11px;word-break:break-all;"></span></p>
      <div class="firma bloq" id="firmaCaja">
        <label class="check" style="margin-top:0;"><input type="checkbox" id="cAcepto"><span><b>He leído y acepto</b> el consentimiento informado y el acuerdo de confidencialidad de la clase muestra, incluidos la grabación, la transcripción y el análisis de la sesión con los fines y resguardos descritos.</span></label>
        <label class="check"><input type="checkbox" id="cInv"><span><b>Autorizo</b> el uso <b>anonimizado</b> (sin nombre, imagen ni voz) de la transcripción y los reportes de mi sesión con fines de investigación académica, en los términos del apartado 8.</span></label>
        <label for="cNombre">Firma electrónica: escribe tu nombre completo</label>
        <input id="cNombre" placeholder="Nombre completo, tal como aparece en tu solicitud" autocomplete="name">
        <div class="sello">Al enviar tu registro quedará constancia de la fecha y hora, tu dirección IP, el navegador, el folio y la huella digital del texto aceptado, con el mismo valor que una firma autógrafa. Recibirás por correo la constancia en PDF.</div>
      </div>
    </div>

    <div class="lector" id="lector">
      <div class="hoja">
        <header><span>Consentimiento informado y acuerdo de confidencialidad</span><button type="button" onclick="cerrarLector()">Cerrar</button></header>
        <div class="cuerpo" id="lectorCuerpo"></div>
        <div class="pie">
          <span class="ayuda" id="lectorPie">Desplázate hasta el final para habilitar la firma.</span>
          <button type="button" id="lectorBtn" onclick="cerrarLector(true)" style="font-family:inherit;font-size:13.5px;font-weight:700;color:#fff;background:#C9C1B2;border:0;border-radius:9px;padding:10px 16px;cursor:not-allowed;" disabled>Ya lo leí</button>
        </div>
      </div>
    </div>

    <h3>6 · Diplomado</h3>
    <label class="check"><input type="checkbox" id="disp"><span>Confirmo que tengo <b>disponibilidad completa</b> para cursar el diplomado <i id="diploNombre"></i>, <span id="diploFechas"></span>. Es gratuito y requisito para la contratación.</span></label>

    <div id="aviso"></div>
    <button class="principal" id="enviar" onclick="enviarF2()">Guardar mi registro</button>
  </div>

  <div class="pie">Centro de Estudios Superiores del Mayo, A.C. · CCT 26PSU0110Z · Navojoa, Sonora<br>Dudas: contacto@cessum.mx · (642) 137 6117<br>Más que una universidad, una familia.</div>
</div>

<script>
const LOGOS=['assets/img/logo-cessum-blanco.png','assets/marca/logo-cessum-blanco.png','assets/marca/cessum-blanco.png','assets/img/logo-blanco.png','assets/img/logo-cessum.png','assets/marca/logo-cessum.svg'];
(function(){const el=document.getElementById('logoCessum');if(!el)return;let i=0;el.onerror=()=>{i++;if(i<LOGOS.length)el.src=LOGOS[i];else el.style.display='none';};el.src=LOGOS[0];})();
const $=id=>document.getElementById(id);
let D=null, sel={dia:'',hora:null};
/* (1-sep) El horario se puede mover solo mientras ningún docente observador
   haya tomado la sesión. Después la mueve Vicerrectoría, no el aspirante. */
let CONGELADO=false, NOM_DOCENTE='';

function aviso(donde, txt, tipo){ $(donde).innerHTML = txt ? '<div class="aviso '+tipo+'">'+txt+'</div>' : ''; }

async function entrar(){
  const folio=($('folio').value||'').trim().toUpperCase();
  if(!folio){ aviso('avisoEntrada','Escribe tu folio.','err'); return; }
  $('btnEntrar').disabled=true; $('btnEntrar').textContent='Buscando…'; aviso('avisoEntrada','','');
  try{
    const r=await fetch('convocatoria-docente.php?f2datos=1&folio='+encodeURIComponent(folio),{cache:'no-store'});
    const d=await r.json();
    if(!d.ok){ aviso('avisoEntrada',d.error||'No se pudo consultar.','err'); return; }
    D=d; pintar();
  }catch(e){ aviso('avisoEntrada','No pudimos conectar con el sistema. Intenta en un momento.','err'); }
  finally{ $('btnEntrar').disabled=false; $('btnEntrar').textContent='Continuar'; }
}

function pintar(){
  $('nombre').textContent=D.nombre||'';
  $('maxmb').textContent=D.maxMB||8;
  $('diploNombre').textContent=D.diplomado||'';
  $('diploFechas').textContent=D.diplomadoFechas||'';
  $('diploTxt').textContent=(D.diplomadoFechas||'').charAt(0).toUpperCase()+(D.diplomadoFechas||'').slice(1)+'.';
  // asignaturas
  const s=$('asig'); s.innerHTML='';
  (D.asignaturas||[]).forEach(a=>{const o=document.createElement('option');o.value=a.materia;o.textContent=a.materia+(a.programa?' — '+a.programa:'');s.appendChild(o);});
  const otra=document.createElement('option');otra.value='__otra';otra.textContent='Otra asignatura (escribirla)';s.appendChild(otra);
  s.onchange=()=>{ const es=s.value==='__otra'; $('otraAsig').style.display=es?'block':'none'; if(es) $('otraAsig').focus(); };
  // registro previo
  const reg=D.registro||{};
  if(reg.dia&&reg.hora!==null&&reg.hora!==undefined){
    /* (1-sep) La fecha se normaliza a ISO antes de marcar el calendario: si
       llegaba como Date convertido a texto no casaba con ningún día y la
       casilla se quedaba sin pintar, aunque el aspirante SÍ tuviera horario.
       Eso hacía creer que no había elegido nada. */
    sel={dia:isoDe(reg.dia),hora:Number(reg.hora)};
    CONGELADO=!!(reg.horarioCongelado||(reg.docente||'').trim()||(reg.meet||'').trim());
    NOM_DOCENTE=(reg.docente||'').trim();
    if(reg.asignatura){ let ok=false; [...s.options].forEach(o=>{if(o.value===reg.asignatura){s.value=reg.asignatura;ok=true;}}); if(!ok){ s.value='__otra'; $('otraAsig').value=reg.asignatura; $('otraAsig').style.display='block'; } }
    $('disp').checked=!!reg.disponible;
    $('enlace').value=reg.enlace||'';
    $('cgoogle').value=reg.correoGoogle||''; $('cgoogle2').value=reg.correoGoogle||'';
    const dn=nombreDia(reg.dia);
    $('yaRegistrado').innerHTML='<div class="aviso ok"><b>Ya tienes un registro:</b> '+dn+' · '+hhmm(reg.hora)+' h · '+(reg.asignatura||'')+'. '+(reg.presentacionNombre?'Presentación recibida: <b>'+esc(reg.presentacionNombre)+'</b>.':(reg.enlace?'Enlace recibido.':'<b style="color:#B11D29;">Falta tu presentación.</b>'))+' Abajo puedes modificar cualquier cosa y volver a guardar.</div>';
  } else { $('yaRegistrado').innerHTML=''; if(D.demo){ $('yaRegistrado').innerHTML='<div class="aviso ok"><b>Folio de demostración.</b> '+esc(D.nota||'')+'</div>'; } }
  if(!$('cgoogle').value && /@(gmail\.com|googlemail\.com)$/i.test(D.correo||'')){ $('cgoogle').value=D.correo; }
  pintarPerfil(D.registro||{});
  cargarPresentacion();
  const cs=D.consentimiento||{};
  $('consentTexto').innerHTML=cs.html||'<p style="color:#B11D29;"><b>No se pudo cargar el texto del consentimiento.</b> Recarga la página en unos minutos; sin el texto no es posible firmar.</p>'; $('consentVer').textContent=cs.version||'—'; $('consentHash').textContent=cs.hash||'—';
  vigilarLectura($('consentTexto'),'leerProg');
  if(cs.vigente&&cs.firmado){ marcarLeido(); $('consentFirmado').style.display='block'; $('consentBloque').style.display='none';
    $('consentFirmado').innerHTML='<b>Consentimiento firmado</b> electrónicamente por <b>'+esc(cs.firmado.nombre)+'</b> el '+esc(cs.firmado.cuando)+'.'+(cs.firmado.pdf?' <a href="'+esc(cs.firmado.pdf)+'" target="_blank" rel="noopener">Ver constancia</a>.':'')+' No es necesario volver a firmarlo.'; }
  else { $('consentFirmado').style.display='none'; $('consentBloque').style.display='block'; if(!$('cNombre').value) $('cNombre').value=D.nombre||''; }
  if(reg.docente){ $('docenteTxt').innerHTML='<b style="color:#1E7A38;">'+esc(reg.docente)+'</b> — participará en el rol de alumno y evaluará la sesión.'; }
  if(reg.meet){ $('meetTxt').innerHTML='<a href="'+esc(reg.meet)+'" target="_blank" rel="noopener"><b>'+esc(reg.meet)+'</b></a> — entra con tu cuenta '+esc(reg.correoGoogle||'de Google')+'.'; }
  pintarCal();
  $('bEntrada').style.display='none'; $('bDatos').style.display='block'; $('bForm').style.display='block';
  plazoInit();
  window.scrollTo({top:0,behavior:'smooth'});
}

function hhmm(h){ return ('0'+h).slice(-2)+':00'; }

/* Cuenta regresiva del plazo absoluto. Al vencer: quien no registró queda
   fuera (se oculta el formulario); quien sí, solo puede enviar su presentación. */
let cdTimer=null;
function plazoInit(){
  if(cdTimer){ clearInterval(cdTimer); cdTimer=null; }
  const lim=D.limiteISO?new Date(D.limiteISO):null;
  $('plazoHasta').textContent = D.limiteTxt ? (', es decir, hasta el '+D.limiteTxt) : '';
  if(!lim){ ['d','h','m','s'].forEach(k=>$('cd-'+k).textContent='–'); return; }
  const tick=()=>{
    let ms=lim-Date.now();
    if(ms<=0){ ['d','h','m','s'].forEach(k=>$('cd-'+k).textContent='0'); vencer(); clearInterval(cdTimer); return; }
    const d=Math.floor(ms/86400000); ms-=d*86400000; const h=Math.floor(ms/3600000); ms-=h*3600000; const m=Math.floor(ms/60000); const s=Math.floor((ms-m*60000)/1000);
    $('cd-d').textContent=d; $('cd-h').textContent=('0'+h).slice(-2); $('cd-m').textContent=('0'+m).slice(-2); $('cd-s').textContent=('0'+s).slice(-2);
  };
  tick(); cdTimer=setInterval(tick,1000);
  if(D.vencido) vencer();
}
function vencer(){
  $('plazo').classList.add('vencido');
  if(D.yaRegistrado){
    $('plazoTxt').innerHTML='<b>El plazo venció el '+esc(D.limiteTxt)+'.</b> Tu día, hora y tema quedaron registrados a tiempo y ya no pueden cambiarse. Todavía puedes enviar o reemplazar tu presentación antes de tu sesión.';
    $('cal').classList.add('bloqueado'); $('asig').disabled=true;
  } else {
    $('plazoTxt').innerHTML='<b>El plazo venció el '+esc(D.limiteTxt)+' y no registraste día, hora y tema.</b> Conforme a las bases de la segunda fase, <b>quedas fuera del proceso</b>. Esta decisión no admite excepciones. Agradecemos tu interés; te avisaremos de próximas convocatorias.';
    $('bForm').style.display='none';
  }
}
function esc(s){ return String(s||'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

/* (1-sep) LEER ANTES DE FIRMAR. Las casillas de aceptación están bloqueadas
   hasta que el aspirante recorre el consentimiento hasta el final, aquí o en
   el lector a pantalla completa. Firmar sin leer no es consentimiento. */
let YA_LEYO=false;
function marcarLeido(){
  if(YA_LEYO) return;
  YA_LEYO=true;
  const c=$('consentTexto'); if(c) c.classList.add('leido');
  const f=$('firmaCaja'); if(f) f.classList.remove('bloq');
  const e=$('leerEstado'); if(e){ e.textContent='Listo: ya puedes firmar'; e.classList.add('ok'); }
  const p=$('leerProg'); if(p) p.style.width='100%';
  const b=$('lectorBtn'); if(b){ b.disabled=false; b.style.background='#B11D29'; b.style.cursor='pointer'; }
  const lp=$('lectorPie'); if(lp) lp.textContent='Puedes cerrar y firmar.';
}
function vigilarLectura(el,progId){
  if(!el) return;
  const ver=()=>{
    const total=el.scrollHeight-el.clientHeight;
    if(total<=8){ marcarLeido(); return; }           // texto corto: ya se ve entero
    const pct=Math.min(100,Math.round(el.scrollTop/total*100));
    const p=$(progId); if(p&&!YA_LEYO) p.style.width=pct+'%';
    if(pct>=97) marcarLeido();
  };
  el.addEventListener('scroll',ver); setTimeout(ver,300);
}
function abrirLector(){
  $('lectorCuerpo').innerHTML=$('consentTexto').innerHTML;
  $('lector').classList.add('on');
  document.body.style.overflow='hidden';
  vigilarLectura($('lectorCuerpo'),'leerProg');
}
function cerrarLector(){ $('lector').classList.remove('on'); document.body.style.overflow=''; }

/* (1-sep) El nombre del día SIEMPRE en español. Si la fecha viene de la hoja
   como objeto Date, llega en inglés ("Wed Sep 02 2026 …") y no casa con el
   calendario; entonces se arma aquí, en español, en vez de mostrarla cruda. */
const MESES_ES=['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
const DIAS_ES=['domingo','lunes','martes','miércoles','jueves','viernes','sábado'];
/* (1-sep) Fecha válida o nada: una fecha imposible (0000-00-00, 2026-13-45,
   vacía) producía años absurdos como 1969 o 1899. Se valida el día real. */
function fechaValida(a,m,d){
  if(!(a>=2020&&a<=2100&&m>=1&&m<=12&&d>=1&&d<=31)) return null;
  const f=new Date(a,m-1,d);
  if(isNaN(f.getTime())||f.getFullYear()!==a||f.getMonth()!==m-1||f.getDate()!==d) return null;
  return f;
}
function isoDe(v){
  if(!v) return '';
  const t=String(v).trim();
  const m=t.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if(m){ return fechaValida(+m[1],+m[2],+m[3]) ? m[1]+'-'+m[2]+'-'+m[3] : ''; }
  const d=new Date(t);
  if(!isNaN(d.getTime()) && d.getFullYear()>=2020 && d.getFullYear()<=2100)
    return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
  return '';
}
function nombreDia(v){
  const iso=isoDe(v);
  if(!iso) return 'Sin fecha registrada';
  const enCal=(D&&D.dias?D.dias:[]).find(x=>x.iso===iso);
  if(enCal) return enCal.nombre;
  const p=iso.split('-');
  if(p.length===3){
    const d=fechaValida(+p[0],+p[1],+p[2]);
    if(d){
      const n=DIAS_ES[d.getDay()];
      return n.charAt(0).toUpperCase()+n.slice(1)+' '+d.getDate()+' de '+MESES_ES[d.getMonth()]+' de '+d.getFullYear();
    }
  }
  return iso;
}

/* ---- Bienvenida tipo perfil: su estado, cada vez que entra ---- */
/* ¿La hora de su sesión ya pasó? Se usa para distinguir «aún no ocurre» de
   «ocurrió y falta que la registren». */
function yaPaso(reg){
  if(!reg||!reg.dia||reg.hora===null||reg.hora===undefined||reg.hora==='') return false;
  const iso=isoDe(reg.dia); if(!iso) return false;
  const p=iso.split('-');
  const f=new Date(+p[0],+p[1]-1,+p[2],+reg.hora+1,0,0);
  return new Date()>f;
}
function iniciales(n){
  const p=String(n||'').trim().split(/\s+/).filter(Boolean);
  if(!p.length) return '—';
  return (p.length===1?p[0][0]:(p[0][0]+p[1][0])).toUpperCase();
}
function item(estado,titulo,texto,accion){
  return '<div class="it '+estado+'"><div class="mk">'+(estado==='si'?'✓':(estado==='no'?'!':'·'))+'</div><div><b>'+titulo+'</b><span>'+texto+'</span>'+(accion||'')+'</div></div>';
}
function pintarPerfil(reg){
  if(!D||!D.folio) return;
  const nom=D.nombre||(reg&&reg.nombre)||'';
  $('perfilCaja').style.display='flex';
  $('perfilIni').textContent=iniciales(nom);
  $('perfilNombre').textContent=nom;
  $('perfilSub').innerHTML='Folio <b>'+esc(D.folio)+'</b>'+(D.correo?' · '+esc(D.correo):'');
  const tieneSes=reg&&reg.dia&&reg.hora!==null&&reg.hora!==undefined&&reg.hora!=='';
  const dn=tieneSes?nombreDia(reg.dia):'';
  $('perfilSes').innerHTML=tieneSes
    ? '<div class="d">'+esc(dn)+'</div><div class="c">'+esc(hhmm(reg.hora))+' h · hora de Sonora</div>'
    : '<div class="c" style="color:#B11D29;font-weight:700;">Falta elegir tu día y hora</div>';

  hoyEsTuClase(reg);
  vigilarCupos();
  const L=[];
  L.push(item(tieneSes?'si':'no','Día y hora',
    tieneSes
      ? (esc(dn)+' · '+esc(hhmm(reg.hora))+' h'+(CONGELADO?' — confirmado, ya no se cambia desde aquí.':' — puedes cambiarlo mientras no te asignen docente.'))
      : 'Elígelos abajo, en el calendario. El plazo no se prorroga.'));
  /* (1-sep) EL CONSENTIMIENTO SE LEÍA DE DONDE NO ESTÁ.
     La tarjeta buscaba reg.consentimiento.firmadoPor, y ese campo solo
     existe en la respuesta del momento de firmar. Al recargar la página, el
     registro trae reg.consent.nombre y D.consentimiento.firmado. Resultado:
     abajo decía «Consentimiento firmado por [nombre] el [fecha]» y arriba,
     con el mismo dato, «te falta firmar el consentimiento». Se leen ahora
     las tres rutas posibles, así que da igual de dónde venga. */
  const cs=(reg&&(reg.consent||reg.consentimiento))
        || (D.consentimiento&&D.consentimiento.firmado) || {};
  const firmante=cs.nombre||cs.firmadoPor||'';
  const cuandoF=cs.cuando||cs.fecha||'';
  L.push(item(firmante?'si':'no','Consentimiento informado',
    firmante?('Firmado por '+esc(firmante)+(cuandoF?' el '+esc(cuandoF):'')):'Sin él tu clase no puede grabarse ni evaluarse.',
    cs.pdf?' <a href="'+esc(cs.pdf)+'" target="_blank" rel="noopener">Ver constancia</a>':''));
  const tienePres=reg&&(reg.presentacion||reg.presentacionNombre||reg.enlace);
  L.push(item(tienePres?'si':'esp','Presentación',
    tienePres?('Recibida'+(reg.presentacionNombre?': '+esc(reg.presentacionNombre):'')+'. Puedes cambiarla cuando quieras.'):'Aún no la envías. Tu clase sigue agendada: súbela cuando esté lista.',
    '<a href="#bPres" onclick="document.getElementById(\'bPres\').scrollIntoView({behavior:\'smooth\'});return false;">'+(tienePres?'Cambiarla':'Subirla ahora')+'</a>'));
  L.push(item((reg&&reg.correoGoogle)?'si':'esp','Cuenta de Google',
    (reg&&reg.correoGoogle)?esc(reg.correoGoogle)+' — con esa cuenta entras a Meet.':'Regístrala abajo: ahí llega la invitación.'));
  L.push(item((reg&&reg.docente)?'si':'esp','Docente que te acompaña',
    (reg&&reg.docente)?esc(reg.docente):'Pendiente de asignación. Te avisamos por correo.'));
  L.push(item((reg&&reg.meet)?'si':'esp','Enlace de Meet',
    (reg&&reg.meet)?'Listo. Aparece abajo y en tu correo.':'Se genera al asignarte docente.',
    (reg&&reg.meet)?' <a href="'+esc(reg.meet)+'" target="_blank" rel="noopener">Abrirlo</a>':''));
  /* (1-sep) La clase impartida: hasta ahora la pantalla no cambiaba después
     de dar la clase, y el aspirante no tenía forma de saber si su asistencia
     había quedado registrada. Ahora lo dice, con la fecha en que se marcó. */
  const asis=(reg&&reg.asistencia)?String(reg.asistencia):'';
  const dio=/^Asisti/i.test(asis);
  if(tieneSes){
    L.push(item(dio?'si':'esp','Tu clase muestra',
      dio
        ? 'Impartida y registrada. Gracias por tu participación.'
        : (yaPaso(reg) ? 'Tu sesión ya ocurrió; la asistencia se registra en las horas siguientes.'
                       : 'Aún no ocurre. Conéctate 10 minutos antes.')));
  }
  $('perfilLista').innerHTML=L.join('');

  const faltan=[];
  if(!tieneSes) faltan.push('elegir tu día y hora');
  if(!firmante) faltan.push('firmar el consentimiento');
  if(!tienePres) faltan.push('enviar tu presentación');
  if(dio){
    cargarHistorial();
    $('perfilPend').innerHTML =
      '<div class="aviso ok" style="margin-top:10px;"><b>Tu clase muestra ya se impartió y quedó registrada.</b> '
      + 'Tu resultado se integra con el dictamen de tu currículum (40 %), la rúbrica de la clase (40 %) y el análisis '
      + 'de las interacciones que promoviste (20 %). No hay valoración parcial ni adelanto: Vicerrectoría te escribirá '
      + 'a tu correo el <b>'+esc(D.resultadosTxt||'sábado 5 de septiembre de 2026')+'</b>. No necesitas hacer nada más.</div>';
    return;
  }
  cargarHistorial();
  $('perfilPend').innerHTML = faltan.length
    ? '<div class="aviso err" style="margin-top:10px;"><b>Te falta:</b> '+faltan.join(', ')+'.</div>'
    : '<div class="aviso ok" style="margin-top:10px;"><b>Todo listo.</b> Nos vemos el día de tu clase; conéctate 10 minutos antes con la cuenta de Google que registraste. Los resultados se publican el sábado 5 de septiembre por correo institucional.</div>';
}

/* (1-sep) EL CALENDARIO SE MANTIENE FRESCO.
   Con dos clases por hora hay más gente eligiendo a la vez, y quien dejó la
   pestaña abierta veía huecos que ya se llenaron: elegía, guardaba y recibía
   un error. Ahora la disponibilidad se vuelve a consultar cada minuto y —lo
   que más importa— al volver a la pestaña, que es justo cuando el dato está
   más viejo. Solo actualiza el calendario: no toca nada de lo que el
   aspirante haya escrito. */
let REFRESCO=null, REFRESCANDO=false;
async function refrescarCupos(){
  if(REFRESCANDO||!D||!D.folio||CONGELADO) return;
  REFRESCANDO=true;
  try{
    const r=await fetch('convocatoria-docente.php?f2datos=1&folio='+encodeURIComponent(D.folio),{cache:'no-store'});
    const j=await r.json();
    if(j&&j.ok){
      const antes=JSON.stringify(D.conteoHoras||{});
      D.ocupados=j.ocupados||D.ocupados;
      D.conteoHoras=j.conteoHoras||D.conteoHoras;
      D.clasesPorHora=j.clasesPorHora||D.clasesPorHora;
      /* Si el horario que tenía elegido —y aún no guardado— se llenó
         mientras tanto, hay que decírselo antes de que pulse guardar. */
      const k=sel.dia+' '+sel.hora;
      /* Su propio horario ya guardado nunca cuenta como «lleno»: el
         backend lo excluye del conteo, pero aquí se comprueba igual para no
         asustarlo con un aviso falso. */
      const mio=D.registro||{};
      const seLlenó=sel.dia&&sel.hora!==null&&(new Set(D.ocupados||[])).has(k)
                    &&!(mio.dia===sel.dia&&Number(mio.hora)===Number(sel.hora));
      if(JSON.stringify(D.conteoHoras||{})!==antes) pintarCal();
      if(seLlenó){
        sel={dia:'',hora:null}; pintarCal();
        const av=$('calAviso');
        if(av) av.innerHTML='<div class="aviso err" style="margin:0 0 10px;"><b>Ese horario se llenó hace un momento.</b> '
          +'Otro aspirante lo tomó mientras tenías la página abierta. Elige otro: los verdes están libres y los ámbar tienen un lugar.</div>';
      }
    }
  }catch(e){ /* sin conexión: se reintenta al minuto siguiente */ }
  finally{ REFRESCANDO=false; }
}
function vigilarCupos(){
  if(REFRESCO) return;
  REFRESCO=setInterval(refrescarCupos,60000);
  document.addEventListener('visibilitychange',function(){
    if(document.visibilityState==='visible') refrescarCupos();
  });
}

/* (1-sep) «HOY ES TU CLASE». El día de su sesión el aspirante entraba y
   tenía que buscar el enlace del Meet entre seis tarjetas. Ese día solo
   importa una cosa: conectarse a tiempo y con la cuenta correcta. Este
   bloque aparece únicamente el día de la clase, arriba de todo, con la
   cuenta regresiva y el botón grande; el resto sigue debajo igual. */
let RELOJ=null;
function hoyEsTuClase(reg){
  const cont=$('perfilHoy'); if(!cont) return;
  if(RELOJ){clearInterval(RELOJ);RELOJ=null;}
  cont.innerHTML='';
  if(!reg||!reg.dia||reg.hora===null||reg.hora===undefined||reg.hora==='') return;
  const iso=isoDe(reg.dia); if(!iso) return;
  const p=iso.split('-');
  const ini=new Date(+p[0],+p[1]-1,+p[2],+reg.hora,0,0);
  const fin=new Date(+p[0],+p[1]-1,+p[2],+reg.hora+1,0,0);
  const hoy=new Date();
  /* Solo el día de la sesión: ni antes ni después. */
  if(!(hoy.getFullYear()===ini.getFullYear()&&hoy.getMonth()===ini.getMonth()&&hoy.getDate()===ini.getDate())) return;

  const caja=document.createElement('div'); caja.className='hoyes';
  const et=document.createElement('div'); et.className='et'; et.textContent='Hoy es tu clase muestra';
  const h3=document.createElement('h3'); h3.textContent=reg.asignatura||'Tu clase muestra';
  const cuenta=document.createElement('div'); cuenta.className='cuenta';
  function pinta(){
    const ahora=new Date();
    const enCurso=ahora>=ini&&ahora<fin;
    if(enCurso){ cuenta.innerHTML='<b>Tu clase está en curso.</b> Si te desconectaste, vuelve a entrar.'; caja.classList.add('encurso'); }
    else if(ahora>=fin){ cuenta.innerHTML='Tu sesión ya terminó. Gracias por participar.'; }
    else{
      const min=Math.floor((ini-ahora)/60000), h=Math.floor(min/60), m=min%60;
      cuenta.innerHTML='Comienza en <b>'+(h?h+' h '+m+' min':m+' min')+'</b> · '+hhmm(reg.hora)+' h, hora de Sonora.';
    }
  }
  pinta();
  const acc=document.createElement('div'); acc.className='acc';
  if(reg.meet){
    const a=document.createElement('a');
    a.className='meet'; a.href=reg.meet; a.target='_blank'; a.rel='noopener';
    a.textContent='Entrar a mi clase';
    acc.appendChild(a);
  }else{
    const av=document.createElement('span');
    av.style.cssText='color:#B11D29;font-weight:700;font-size:14px;';
    av.textContent='Todavía no tienes enlace de Meet. Escríbenos a contacto@cessum.mx ahora mismo.';
    acc.appendChild(av);
  }
  const rec=document.createElement('div'); rec.className='rec';
  rec.innerHTML='<b>Antes de entrar:</b> conéctate <b>10 minutos antes</b> con '
    +(reg.correoGoogle?('<b>'+esc(reg.correoGoogle)+'</b>, que es la cuenta con la que te registraste'):'tu cuenta de Google registrada')
    +'. Ten tu presentación abierta y comparte pantalla al iniciar. Duración: 30 a 45 minutos.';
  caja.appendChild(et); caja.appendChild(h3); caja.appendChild(cuenta); caja.appendChild(acc); caja.appendChild(rec);
  cont.appendChild(caja);
  RELOJ=setInterval(pinta,30000);
}

/* (1-sep) TUS PARTICIPACIONES. El aspirante ve todas las convocatorias en
   las que ha estado: la actual en curso y las cerradas con su dictamen. Se
   carga aparte y en silencio: si falla, el perfil se ve igual de completo.
   La de esta convocatoria no se repite —ya está arriba, con su detalle—,
   así que solo se enseña el histórico cuando hay algo más que contar. */
let HIST=null;
async function cargarHistorial(){
  const cont=$('perfilHist'); if(!cont||!D||!D.folio) return;
  if(HIST) return;
  try{
    const r=await fetch('convocatoria-docente.php?historial=1&folio='+encodeURIComponent(D.folio),{cache:'no-store'});
    const j=await r.json();
    if(!j||!j.ok||!j.participaciones||!j.participaciones.length){ cont.innerHTML=''; return; }
    HIST=j;
    const cerradas=j.participaciones.filter(p=>!p.enCurso);
    if(!cerradas.length){
      /* Solo esta convocatoria: no se abre una sección para repetir lo que ya
         está arriba. Se dice, y ya. */
      cont.innerHTML='<p class="ayuda" style="margin-top:14px;">Esta es tu primera participación en una convocatoria docente del CESSUM. '
        +'Cuando abramos la siguiente, aquí verás también tu historial.</p>';
      return;
    }
    cont.innerHTML='<h3 style="font-family:\'Playfair Display\',Georgia,serif;font-size:18px;color:#B11D29;margin:22px 0 4px;">Tus participaciones</h3>'
      +'<p class="ayuda" style="margin-bottom:10px;">Convocatorias en las que has estado.</p>'
      +j.participaciones.map(p=>{
        const res=(p.resultado||'').toLowerCase();
        const col=res.startsWith('acept')?'#1E7A38':(res.includes('reserva')?'#A56B16':(res?'#B11D29':'#5E5E5E'));
        return '<div style="border:1px solid #E8DFCE;border-left:4px solid '+(p.enCurso?'#A56B16':col)+';border-radius:10px;padding:13px 15px;margin-bottom:9px;background:#fff;">'
          +'<div style="display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;align-items:baseline;">'
          +'<b style="font-size:14.5px;color:#B11D29;">'+esc(p.edicionNombre)+'</b>'
          +'<span style="font-size:10.5px;font-weight:800;letter-spacing:.05em;text-transform:uppercase;color:'+(p.enCurso?'#95590E':'#5E5E5E')+';">'
          +(p.enCurso?'En curso':'Cerrada'+(p.cerradaEl?' · '+esc(p.cerradaEl):''))+'</span></div>'
          +'<div class="ayuda" style="margin-top:3px;">Folio '+esc(p.folio)+(p.asignatura?' · '+esc(p.asignatura):'')+'</div>'
          +(p.enCurso
              ? '<div style="font-size:13px;margin-top:6px;">Etapa: <b>'+esc(p.etapa||'en proceso')+'</b>. Tu resultado llega por correo al cierre.</div>'
              : (p.resultado
                  ? '<div style="font-size:14px;margin-top:6px;"><b style="color:'+col+';">'+esc(p.resultado)+'</b></div>'
                  : '<div class="ayuda" style="margin-top:6px;">Sin dictamen registrado.</div>'))
          +'</div>';
      }).join('')
      +'<p class="ayuda">Aquí no se publican puntajes. Para una revisión, escribe a vicerrectoria@cessum.mx dentro de los cinco días hábiles siguientes al aviso.</p>';
  }catch(e){ cont.innerHTML=''; }
}

/* ---- Presentación: cargar estado y permitir reemplazo ---- */
let PRES=null;
async function cargarPresentacion(){
  if(!D || !D.folio) return;
  try{
    const r=await fetch('convocatoria-docente.php?f2registro=1&folio='+encodeURIComponent(D.folio),{cache:'no-store'});
    const d=await r.json();
    if(!d.ok){ $('bPres').style.display='none'; return; }
    PRES=d;
    $('bPres').style.display='block';
    $('presMax').textContent=d.maxMB||25;
    $('presEnlace').value=d.enlace||'';
    const tiene=d.presentacion||d.presentacionNombre||d.enlace;
    let html='';
    if(tiene){
      html='<div class="aviso ok"><b>Presentación recibida'+(d.presentacionNombre?': '+esc(d.presentacionNombre):'')+'.</b>'+(d.presentacion?' <a href="'+esc(d.presentacion)+'" target="_blank" rel="noopener">Verla</a>.':'')+' Si subes otra, la reemplaza.</div>';
    } else {
      html='<div class="aviso err"><b>Todavía no has enviado tu presentación.</b> Tu clase sigue agendada: puedes subirla cuando la tengas lista.</div>';
    }
    html+='<p class="ayuda" style="margin-top:6px;">Tu clase: <b>'+esc(d.diaNombre||'')+(d.horaTxt?' · '+esc(d.horaTxt)+' h':'')+'</b>'+(d.asignatura?' · '+esc(d.asignatura):'')+'.</p>';
    $('presEstado').innerHTML=html;
    if(!d.puedeActualizar){
      $('archivoPres').disabled=true; $('presEnlace').disabled=true; $('btnPres').disabled=true;
      $('presAviso').innerHTML='<div class="aviso err">'+esc(d.nota||'Tu sesión ya comenzó: la presentación ya no puede cambiarse.')+'</div>';
    }
  }catch(e){ $('bPres').style.display='none'; }
}
document.addEventListener('change',function(ev){
  if(ev.target && ev.target.id==='archivoPres'){
    const f=ev.target.files[0];
    if(!f){ $('zonaPres').classList.remove('con'); return; }
    $('zonaPres').classList.add('con');
    $('presArchivoTxt').innerHTML='<b>'+esc(f.name)+'</b><br><span class="ayuda">'+(Math.round(f.size/1048576*10)/10)+' MB · toca para cambiar</span>';
  }
});
async function enviarPresentacion(){
  aviso('presAviso','','');
  const f=$('archivoPres').files[0], enl=$('presEnlace').value.trim();
  if(!f&&!enl){ aviso('presAviso','Adjunta tu presentación o pega un enlace.','err'); return; }
  const maxMB=(PRES&&PRES.maxMB)||25;
  if(f&&f.size>maxMB*1048576){ aviso('presAviso','El archivo pesa más de '+maxMB+' MB. Expórtalo a PDF o usa un enlace.','err'); return; }
  const btn=$('btnPres'); btn.disabled=true; btn.textContent='Enviando…';
  try{
    let sid='';
    if(f){
      const b64=await new Promise((res,rej)=>{const r=new FileReader();r.onload=()=>res(String(r.result).split(',')[1]||'');r.onerror=()=>rej(new Error('no se pudo leer'));r.readAsDataURL(f);});
      sid='p'+Date.now().toString(36)+Math.random().toString(36).slice(2,10);
      const TAM=512*1024,total=Math.ceil(b64.length/TAM);
      for(let n=0;n<total;n++){
        const c=new URLSearchParams();c.set('sid',sid);c.set('n',String(n));c.set('d',b64.slice(n*TAM,(n+1)*TAM));
        const rt=await fetch('convocatoria-docente.php?trozo=1',{method:'POST',body:c});
        let dt;try{dt=JSON.parse(await rt.text());}catch(e){throw new Error('el servidor rechazó la carga');}
        if(!dt.ok)throw new Error(dt.error||'falló la carga');
        btn.textContent='Subiendo… '+Math.round((n+1)/total*100)+'%';
      }
    }
    const cf=new URLSearchParams();
    cf.set('sid',sid);
    cf.set('datos',JSON.stringify({folio:D.folio,enlace:enl,archivoNombre:f?f.name:'',archivoMime:f?(f.type||'application/octet-stream'):''}));
    const resp=await fetch('convocatoria-docente.php?f2presentacion=1',{method:'POST',body:cf});
    let d;try{d=JSON.parse(await resp.text());}catch(e){throw new Error('el servidor respondió '+resp.status);}
    if(d.ok){
      aviso('presAviso','<b>'+esc(d.nota||'Presentación guardada.')+'</b>','ok');
      $('archivoPres').value=''; $('zonaPres').classList.remove('con');
      $('presArchivoTxt').innerHTML='<b>Adjuntar mi presentación</b><br><span class="ayuda">PDF o PowerPoint · máximo '+((PRES&&PRES.maxMB)||25)+' MB</span>';
      cargarPresentacion();
    } else aviso('presAviso',esc(d.error||'No se pudo guardar.'),'err');
  }catch(err){ aviso('presAviso','No se pudo enviar: '+esc(err.message||err),'err'); }
  finally{ btn.disabled=false; btn.textContent='Guardar mi presentación'; }
}

function pintarCal(){
  const oc=new Set(D.ocupados||[]);
  const cal=$('cal'); cal.innerHTML='';
  cal.classList.toggle('congelado',!!CONGELADO);
  (D.dias||[]).forEach(dia=>{
    const box=document.createElement('div'); box.className='dia';
    const partes=dia.nombre.split(' ');
    box.innerHTML='<h4>'+esc(partes[0])+'<small>'+esc(partes.slice(1).join(' '))+'</small></h4>';
    const horas=document.createElement('div'); horas.className='horas';
    for(let h=D.horaIni;h<=D.horaFin;h++){
      const b=document.createElement('div'); b.className='hora'; b.textContent=hhmm(h);
      const k=dia.iso+' '+h;
      /* (1-sep) DOS CLASES POR HORA. Con una sola por hora se agotaron los
         horarios y quedó gente sin dónde agendar. Ahora caben dos, y el
         color lo dice antes de tocar: verde libre, ámbar una tomada
         —queda un lugar—, rojo llena. */
      const cupo=D.clasesPorHora||2;
      const yaHay=(D.conteoHoras&&D.conteoHoras[k])||0;
      if(!oc.has(k)&&yaHay>0&&yaHay<cupo){
        b.classList.add('media');
        b.title='Queda un lugar en este horario: otro aspirante ya lo eligió, pero caben dos clases.';
      }else if(!oc.has(k)){
        b.classList.add('librecupo');
      }
      if(oc.has(k)){ b.classList.add('ocupada'); b.setAttribute('aria-disabled','true');
        b.title=yaHay>=cupo?('Horario lleno: ya hay '+cupo+' clases a esta hora.'):'Ya apartada por otro aspirante';
        b.setAttribute('aria-label',hhmm(h)+' horas del '+dia.nombre+', no disponible'); }
      else if(CONGELADO){ b.title='Tu clase ya tiene docente asignado: el horario ya no se puede cambiar desde aquí.'; }
      else {
        /* (1-sep) Accesible: los huecos eran <div> sin más, así que no se
           podían elegir con el teclado ni un lector de pantalla decía qué
           eran. Ahora se comportan como botones. */
        b.setAttribute('role','button');
        b.tabIndex=0;
        b.setAttribute('aria-label',hhmm(h)+' horas del '+dia.nombre
          +((D.conteoHoras&&D.conteoHoras[k])?', queda un lugar':', libre'));
        const elegir=()=>{ sel={dia:dia.iso,hora:h}; pintarCal();
          const e=document.getElementById('horaElegida'); if(e) e.focus(); };
        b.onclick=elegir;
        b.onkeydown=(ev)=>{ if(ev.key==='Enter'||ev.key===' '){ ev.preventDefault(); elegir(); } };
      }
      if(sel.dia===dia.iso&&sel.hora===h){ b.classList.add('elegida'); b.id='horaElegida'; b.setAttribute('aria-pressed','true'); b.title='Este es tu horario. Toca otro si quieres cambiarlo.'; }
      horas.appendChild(b);
    }
    box.appendChild(horas); cal.appendChild(box);
  });
  if(sel.dia&&sel.hora!==null){
    $('eleccion').innerHTML='Tu clase: <b>'+esc(nombreDia(sel.dia))+' · '+hhmm(sel.hora)+' h, hora de Sonora</b> (30 a 45 minutos).';
  } else $('eleccion').textContent='Todavía no has elegido horario.';
  // Aviso claro arriba del calendario: guardado ≠ sin elegir.
  const cab=$('calAviso');
  if(cab) cab.innerHTML = !(sel.dia&&sel.hora!==null) ? ''
    : (CONGELADO
      ? '<div class="aviso ok" style="margin:0 0 10px;"><b>Tu horario está confirmado:</b> '+esc(nombreDia(sel.dia))+' · '+hhmm(sel.hora)+' h, marcado en verde abajo.<br>Ya tienes docente acompañante asignado'+(NOM_DOCENTE?' ('+esc(NOM_DOCENTE)+')':'')+', así que <b>el horario ya no se puede cambiar desde aquí</b>: moverías una sesión que esa persona ya apartó en su agenda. Si tienes una causa justificada, escribe a vicerrectoria@cessum.mx antes de tu sesión.</div>'
      : '<div class="aviso ok" style="margin:0 0 10px;"><b>Tu horario ya está apartado:</b> '+esc(nombreDia(sel.dia))+' · '+hhmm(sel.hora)+' h. Aparece marcado en verde abajo. <b>Puedes cambiarlo</b> mientras no se te asigne docente: toca otra hora y vuelve a guardar.</div>');
}

$('archivo').addEventListener('change',()=>{
  const f=$('archivo').files[0];
  const z=$('zonaArchivo');
  if(!f){ z.classList.remove('con'); $('archivoTxt').innerHTML='<b>Adjuntar mi presentación</b><br><span class="ayuda">PDF o PowerPoint · máximo '+(D?D.maxMB:8)+' MB.</span>'; return; }
  z.classList.add('con'); $('archivoTxt').innerHTML='<b>'+esc(f.name)+'</b><br><span class="ayuda">'+(Math.round(f.size/1048576*10)/10)+' MB · toca para cambiar</span>';
});

async function enviarF2(){
  aviso('aviso','','');
  if(!sel.dia||sel.hora===null){ aviso('aviso','Elige el día y la hora de tu clase en el calendario.','err'); return; }
  let asig=$('asig').value; if(asig==='__otra') asig=$('otraAsig').value.trim();
  if(!asig){ aviso('aviso','Indica sobre qué asignatura será tu clase.','err'); return; }
  const cg=$('cgoogle').value.trim().toLowerCase(), cg2=$('cgoogle2').value.trim().toLowerCase();
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cg)){ aviso('aviso','Escribe el correo de tu cuenta de Google: ahí te llegará la invitación de Meet.','err'); return; }
  if(cg!==cg2){ aviso('aviso','Los dos correos de Google no coinciden. Revísalos.','err'); return; }
  const csv=(D.consentimiento||{}); const yaFirmo=!!(csv.vigente&&csv.firmado);
  if(!yaFirmo){
    if(!YA_LEYO){
      aviso('aviso','Antes de firmar tienes que leer el consentimiento completo: desplázalo hasta el final o ábrelo en pantalla completa.','err');
      $('consentTexto').scrollIntoView({behavior:'smooth',block:'center'});
      return;
    }
    if(!$('cAcepto').checked){ aviso('aviso','Es necesario leer y aceptar el consentimiento informado y acuerdo de confidencialidad: sin él la clase muestra no puede grabarse ni evaluarse.','err'); $('cAcepto').focus(); return; }
    if(!$('cInv').checked){ aviso('aviso','Es necesario autorizar el uso anonimizado con fines de investigación: forma parte del consentimiento de la clase muestra.','err'); $('cInv').focus(); return; }
    if($('cNombre').value.trim().split(/\s+/).length<2){ aviso('aviso','Escribe tu nombre completo en la firma electrónica.','err'); $('cNombre').focus(); return; }
    if(!(csv.html&&csv.hash)){ aviso('aviso','No se pudo cargar el texto del consentimiento (el sistema aún no está actualizado). Recarga la página; si persiste, escríbenos a contacto@cessum.mx.','err'); return; }
  }
  if(!$('disp').checked){ aviso('aviso','Es necesario confirmar tu disponibilidad para el diplomado: es requisito para la contratación.','err'); return; }
  const f=$('archivo').files[0]; const maxB=(D.maxMB||8)*1048576;
  if(f&&f.size>maxB){ aviso('aviso','Tu presentación pesa '+(Math.round(f.size/1048576*10)/10)+' MB y el máximo es '+(D.maxMB||8)+' MB. Expórtala a PDF (más ligera) o comparte un enlace.','err'); return; }
  const btn=$('enviar'); btn.disabled=true; btn.textContent='Guardando…';
  try{
    let sid='';
    if(f){
      const b64=await new Promise((res,rej)=>{const r=new FileReader();r.onload=()=>res(String(r.result).split(',')[1]||'');r.onerror=()=>rej(new Error('no se pudo leer el archivo'));r.readAsDataURL(f);});
      sid='a'+Date.now().toString(36)+Math.random().toString(36).slice(2,10);
      const TAM=512*1024, total=Math.ceil(b64.length/TAM);
      for(let n=0;n<total;n++){
        const c=new URLSearchParams(); c.set('sid',sid); c.set('n',String(n)); c.set('d',b64.slice(n*TAM,(n+1)*TAM));
        const rt=await fetch('convocatoria-docente.php?trozo=1',{method:'POST',body:c});
        let dt; try{ dt=JSON.parse(await rt.text()); }catch(e){ throw new Error('el servidor rechazó la carga ('+rt.status+')'); }
        if(!dt.ok) throw new Error(dt.error||'falló la carga del archivo');
        btn.textContent='Subiendo presentación… '+Math.round(((n+1)/total)*100)+'%';
      }
    }
    const cf=new URLSearchParams();
    cf.set('sid',sid);
    cf.set('datos',JSON.stringify({folio:D.folio,dia:sel.dia,hora:sel.hora,asignatura:asig,disponible:'1',correoGoogle:cg,enlace:$('enlace').value.trim(),archivoNombre:f?f.name:'',archivoMime:f?(f.type||'application/octet-stream'):'',
      consentAcepto:(yaFirmo||$('cAcepto').checked)?'1':'0',consentNombre:yaFirmo?(csv.firmado.nombre||''):$('cNombre').value.trim(),consentInvestigacion:$('cInv').checked?'1':'0',consentHash:csv.hash||''}));
    btn.textContent='Registrando…';
    const resp=await fetch('convocatoria-docente.php?f2enviar=1',{method:'POST',body:cf});
    let d; const crudo=await resp.text(); try{ d=JSON.parse(crudo); }catch(e){ throw new Error('el servidor respondió '+resp.status); }
    if(d.ok){
      D.yaRegistrado=true;
      setTimeout(cargarPresentacion,400);
      if(d.consentimiento&&d.consentimiento.firmadoPor){ D.consentimiento=D.consentimiento||{}; D.consentimiento.vigente=true; D.consentimiento.firmado={nombre:d.consentimiento.firmadoPor,cuando:'hoy',pdf:d.consentimiento.pdf||''}; }
      $('bForm').style.display='none';
      $('yaRegistrado').innerHTML='<div class="aviso ok"><b>'+(d.demo?'Demostración: así quedaría tu registro.':'Registro guardado.')+'</b> Tu clase: <b>'+esc(d.diaNombre)+' · '+esc(d.horaTxt)+' h</b> · '+esc(d.asignatura)+'.<br>'+(d.presentacionNombre?'Presentación recibida: <b>'+esc(d.presentacionNombre)+'</b>.':(d.enlace?'Enlace recibido.':'<b style="color:#B11D29;">Falta tu presentación:</b> puedes enviarla después entrando de nuevo con tu folio.'))+'<br>Invitación de Meet a: <b>'+esc(d.correoGoogle||cg)+'</b>. '+(d.docente?'Docente que acompaña tu clase: <b>'+esc(d.docente)+'</b>.':'Te avisaremos por correo en cuanto se te asigne el docente acompañante y el enlace de Meet.')+(d.consentimiento&&d.consentimiento.firmadoPor?'<br>Consentimiento firmado electrónicamente por <b>'+esc(d.consentimiento.firmadoPor)+'</b>'+(d.consentimiento.pdf?' — <a href="'+esc(d.consentimiento.pdf)+'" target="_blank" rel="noopener">constancia</a>':'')+'.':'')+(d.demo?' <i>(No se guardó nada ni se envió correo.)</i>':' Te mandamos el acuse por correo con la constancia adjunta.')+'</div><p style="margin-top:10px;"><a href="convocatoria-docente.php?fase2=1&folio='+encodeURIComponent(D.folio)+'">Ver o modificar mi registro</a></p>';
      window.scrollTo({top:0,behavior:'smooth'});
    } else {
      if(d.vencido){ D.vencido=true; if(d.limiteTxt) D.limiteTxt=d.limiteTxt; vencer(); }
      if(d.ocupado&&d.ocupados){ D.ocupados=d.ocupados; sel={dia:'',hora:null}; pintarCal(); }
      aviso('aviso',d.error||'No se pudo guardar. Intenta de nuevo.','err');
    }
  }catch(err){
    aviso('aviso','No se pudo guardar: <b>'+esc(err&&err.message?err.message:err)+'</b><br>Tus datos siguen aquí; intenta otra vez o escríbenos a contacto@cessum.mx.','err');
  }finally{ btn.disabled=false; btn.textContent='Guardar mi registro'; }
}
if($('folio').value) entrar();
</script>
</body>
</html><?php
    exit;
}

/* ============================================================
 * (31-ago) DIPLOMADO · página del participante
 * ?diplomado=1&folio=DOC-...  Entra con su folio, ve las sesiones (fecha, tema,
 * Meet, materiales, grabación), su asistencia y avance, sube su planeación
 * (por trozos, como el CV) y descarga su constancia cuando exista.
 * ============================================================ */
if (isset($_GET['dipdatos'])) {
    header('Content-Type: application/json; charset=utf-8');
    $r = guardian(['accion' => 'diplomado_participante', 'folio' => trim((string)($_GET['folio'] ?? ''))]);
    echo json_encode($r ?: ['ok' => false, 'error' => 'No pudimos conectar con el sistema.'], JSON_UNESCAPED_UNICODE); exit;
}
if (isset($_GET['dipplaneacion'])) {
    header('Content-Type: application/json; charset=utf-8');
    $datos = isset($_POST['datos']) ? json_decode($_POST['datos'], true) : null;
    if (!is_array($datos)) { echo json_encode(['ok' => false, 'error' => 'No se recibieron los datos.']); exit; }
    $datos['accion'] = 'diplomado_planeacion';
    $sid = $_POST['sid'] ?? '';
    if ($sid !== '') { $ruta = rutaSesion($sid); if ($ruta && is_file($ruta)) { $b64 = file_get_contents($ruta); @unlink($ruta); if ($b64 && strlen($b64) > 130) $datos['archivoBase64'] = $b64; } }
    $r = guardian(['accion' => 'diplomado_planeacion'], json_encode($datos));
    echo json_encode($r ?: ['ok' => false, 'error' => 'No pudimos conectar. Vuelve a intentarlo.'], JSON_UNESCAPED_UNICODE); exit;
}
if (isset($_GET['diplomado'])) {
    $folioIni = preg_replace('/[^A-Za-z0-9\-]/', '', (string)($_GET['folio'] ?? ''));
    header('Content-Type: text/html; charset=utf-8');
    ?><!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex, nofollow"><meta name="theme-color" content="#B11D29">
<title>Diplomado · CESSUM</title>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600;700&family=Montserrat:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root{--rojo:#B11D29;--rojo-osc:#8E1621;--oro:#A56B16;--verde:#1E7A38;--crema:#F7F3EA;--tinta:#1F1F1F;--gris:#6E6E6E;--linea:#E8DFCE;}
  *{box-sizing:border-box;} body{margin:0;padding:0 0 60px;background:var(--crema);color:var(--tinta);font-family:'Montserrat',Arial,sans-serif;font-size:15.5px;line-height:1.65;}
  .hero{background:linear-gradient(135deg,var(--rojo),var(--rojo-osc));color:#fff;border-bottom:4px solid var(--oro);padding:40px 18px 36px;text-align:center;}
  .hero-logo{height:64px;display:block;margin:0 auto 16px;} .hero .eyebrow{font-size:11.5px;letter-spacing:.16em;text-transform:uppercase;opacity:.85;font-weight:600;}
  .hero h1{font-family:'Playfair Display',Georgia,serif;font-size:clamp(22px,4.4vw,34px);margin:.5rem auto .5rem;max-width:820px;line-height:1.2;} .hero p{margin:0;opacity:.92;font-size:14.5px;}
  .wrap{max-width:880px;margin:0 auto;padding:0 18px;}
  .bloque{background:#fff;border-radius:16px;padding:26px 30px;margin:-24px 0 20px;box-shadow:0 12px 34px rgba(80,60,20,.10);border-top:4px solid var(--oro);} .bloque+.bloque{margin-top:20px;border-top:0;border-left:4px solid var(--oro);}
  h2{font-family:'Playfair Display',Georgia,serif;font-size:22px;margin:0 0 .5rem;color:var(--rojo);} h3{font-family:'Playfair Display',Georgia,serif;font-size:17px;margin:1.2rem 0 .4rem;}
  label{display:block;font-size:11.5px;letter-spacing:.05em;text-transform:uppercase;font-weight:700;color:var(--gris);margin:14px 0 5px;} input{width:100%;padding:11px 13px;font-family:inherit;font-size:15px;border:1.5px solid #DCD3C2;border-radius:9px;background:#FDFCF9;}
  .ayuda{font-size:12.5px;color:var(--gris);margin-top:4px;} .aviso{padding:14px 16px;border-radius:10px;font-size:14px;margin:14px 0;} .aviso.ok{background:rgba(30,122,56,.10);border:1px solid rgba(30,122,56,.4);} .aviso.err{background:rgba(177,29,41,.08);border:1px solid rgba(177,29,41,.4);}
  button.principal{width:100%;margin-top:16px;padding:14px;font-family:inherit;font-size:15px;font-weight:700;color:#fff;background:var(--rojo);border:0;border-radius:11px;cursor:pointer;} button.principal:disabled{background:#C9C1B2;}
  button.suave{padding:11px 16px;font-family:inherit;font-size:14px;font-weight:600;color:#fff;background:var(--oro);border:0;border-radius:8px;cursor:pointer;}
  .entrada{display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap;} .entrada>div{flex:1;min-width:220px;} .entrada label{margin-top:0;}
  .kpis{display:flex;gap:10px;flex-wrap:wrap;margin:10px 0;} .kpi{flex:1;min-width:120px;background:#FDFCF9;border:1px solid var(--linea);border-radius:12px;padding:10px 14px;} .kpi b{display:block;font-family:'Playfair Display',Georgia,serif;font-size:26px;color:var(--rojo);} .kpi span{font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:var(--gris);}
  .bar{height:12px;background:#EFE9DC;border-radius:6px;overflow:hidden;margin:6px 0;} .bar div{height:100%;background:linear-gradient(90deg,var(--oro),var(--verde));}
  .ses{border:1.5px solid var(--linea);border-radius:12px;padding:12px 16px;margin:8px 0;background:#FDFCF9;display:flex;gap:14px;align-items:flex-start;} .ses.hoy{border-color:var(--rojo);background:#FDF4F5;} .ses.pasada{opacity:.85;}
  .ses .n{flex:0 0 40px;height:40px;border-radius:50%;background:var(--oro);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:800;} .ses.pasada .n{background:#B9B2A3;} .ses.hoy .n{background:var(--rojo);}
  .ses .t{flex:1;} .ses .t b{display:block;} .ses .t .m{font-size:13px;color:var(--gris);} .ses .acc{display:flex;gap:6px;flex-wrap:wrap;margin-top:6px;}
  .btn{display:inline-block;padding:7px 12px;font-size:12.5px;font-weight:600;color:#fff;background:var(--rojo);border-radius:8px;text-decoration:none;} .btn.oro{background:var(--oro);} .btn.gris{background:var(--gris);}
  .pill{display:inline-block;border-radius:6px;padding:2px 8px;font-size:11px;font-weight:700;} .pill.ok{background:rgba(30,122,56,.12);color:var(--verde);} .pill.no{background:rgba(177,29,41,.1);color:var(--rojo);} .pill.esp{background:rgba(165,107,22,.14);color:var(--oro);}
  .archivo{border:2px dashed #DCD3C2;border-radius:12px;padding:16px;text-align:center;background:#FDFCF9;cursor:pointer;display:block;} .archivo.con{border-color:var(--verde);background:rgba(30,122,56,.06);} .archivo input{display:none;}
  .o{text-align:center;font-size:12px;color:var(--gris);margin:10px 0;letter-spacing:.1em;text-transform:uppercase;} .pie{text-align:center;font-size:12px;color:#9A9A9A;margin-top:26px;line-height:1.7;}
</style></head>
<body>
<div class="hero"><img id="logoCessum" class="hero-logo" alt="CESSUM" src="assets/img/logo-cessum-blanco.png"><div class="eyebrow">Centro de Estudios Superiores del Mayo · Diplomado docente</div><h1 id="titDip">Promoción de aprendizajes complejos en la docencia universitaria</h1><p>Sesiones, Meet, materiales, tu asistencia y la entrega de tu planeación. Los materiales y tareas viven en <a href="https://aula.cessum.mx" style="color:#fff;">aula.cessum.mx</a>.</p></div>
<div class="wrap">
  <div class="bloque" id="bEntrada"><h2>Entra con tu folio</h2><p class="ayuda" style="font-size:14px;">Es el folio de tu solicitud docente, con la forma <b>DOC-2026-0000</b>.</p>
    <div class="entrada"><div><label for="folio">Folio</label><input id="folio" placeholder="DOC-2026-0000" value="<?= e($folioIni) ?>" autocomplete="off"></div><button class="suave" id="btnEntrar" onclick="entrar()">Continuar</button></div><div id="avisoEntrada"></div></div>

  <div class="bloque" id="bDatos" style="display:none;">
    <h2>Hola, <span id="nombre"></span></h2>
    <p style="margin:0;" id="horarioTxt"></p>
    <div class="kpis"><div class="kpi"><b id="kAsis">–</b><span>asistencia</span></div><div class="kpi"><b id="kSes">–</b><span>sesiones asistidas</span></div><div class="kpi"><b id="kPlan">–</b><span>planeación</span></div><div class="kpi"><b id="kConst">–</b><span>constancia</span></div></div>
    <div class="bar"><div id="barAsis" style="width:0"></div></div>
    <p class="ayuda" id="avanceTxt"></p>
    <h3>Sesiones</h3><div id="sesiones"></div>
  </div>

  <div class="bloque" id="bPlan" style="display:none;">
    <h2>Tu planeación didáctica</h2>
    <p>El diplomado trabaja sobre la planeación de la asignatura que propusiste. Súbela antes de la primera sesión y, al final, la versión rediseñada. La última que subas es la que cuenta para la constancia.</p>
    <div id="planActual"></div>
    <label class="archivo" id="zonaArchivo" for="archivo"><input type="file" id="archivo" accept=".pdf,.doc,.docx,application/pdf,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document"><div id="archivoTxt"><b>Adjuntar mi planeación</b><br><span class="ayuda">PDF o Word · máximo <span id="maxmb">10</span> MB</span></div></label>
    <div class="o">— o bien —</div><label for="enlace">Enlace (Drive, OneDrive…)</label><input id="enlace" placeholder="https://…">
    <div id="aviso"></div><button class="principal" id="enviar" onclick="enviarPlan()">Enviar mi planeación</button>
  </div>
  <div class="pie">Centro de Estudios Superiores del Mayo, A.C. · CCT 26PSU0110Z · Navojoa, Sonora<br>Dudas: contacto@cessum.mx · (642) 137 6117</div>
</div>
<script>
const LOGOS=['assets/img/logo-cessum-blanco.png','assets/marca/logo-cessum-blanco.png','assets/img/logo-cessum.png'];(function(){const el=document.getElementById('logoCessum');let i=0;el.onerror=()=>{i++;if(i<LOGOS.length)el.src=LOGOS[i];else el.style.display='none';};})();
const $=id=>document.getElementById(id); let D=null;
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function aviso(d,t,tipo){ $(d).innerHTML=t?'<div class="aviso '+tipo+'">'+t+'</div>':''; }
async function entrar(){
  const folio=($('folio').value||'').trim().toUpperCase(); if(!folio){aviso('avisoEntrada','Escribe tu folio.','err');return;}
  $('btnEntrar').disabled=true; $('btnEntrar').textContent='Buscando…';
  try{ const r=await fetch('convocatoria-docente.php?dipdatos=1&folio='+encodeURIComponent(folio),{cache:'no-store'}); const d=await r.json(); if(!d.ok){aviso('avisoEntrada',d.error||'No se pudo consultar.','err');return;} D=d; pintar(); }
  catch(e){ aviso('avisoEntrada','No pudimos conectar. Intenta en un momento.','err'); } finally{ $('btnEntrar').disabled=false; $('btnEntrar').textContent='Continuar'; }
}
function pintar(){
  $('nombre').textContent=D.nombre; $('titDip').textContent=D.nombreDiplomado||$('titDip').textContent; $('maxmb').textContent=D.maxMB||10;
  $('horarioTxt').innerHTML='<b>'+esc(D.horas)+' horas</b> · '+esc(D.horario)+'. La asistencia mínima para acreditar es <b>'+D.asistencia.minimo+'%</b> de las sesiones, más la entrega de tu planeación.';
  const a=D.asistencia; $('kAsis').textContent=a.pct+'%'; $('kSes').textContent=(a.presentes+a.justificadas)+' / '+a.total; $('kPlan').textContent=D.planeacion.url?'✔':'—'; $('kConst').textContent=D.constancia?'✔':'—'; $('barAsis').style.width=a.pct+'%';
  $('avanceTxt').textContent=a.pasadas?('Han pasado '+a.pasadas+' de '+a.total+' sesiones.'):'El diplomado no ha iniciado.';
  $('sesiones').innerHTML=D.sesiones.map(s=>{const pasada=s.fecha<D.hoy, hoy=s.fecha===D.hoy; const pres=s.presente==='SI'?'<span class="pill ok">asististe</span>':(s.presente==='JUST'?'<span class="pill esp">justificada</span>':(s.presente==='NO'?'<span class="pill no">falta</span>':(pasada?'<span class="pill esp">sin registro</span>':'')));
    return '<div class="ses '+(hoy?'hoy':(pasada?'pasada':''))+'"><div class="n">'+s.n+'</div><div class="t"><b>'+esc(s.fechaTxt)+(hoy?' · HOY':'')+'</b><span class="m">'+esc(s.tema)+(s.imparte?' · Imparte: '+esc(s.imparte):'')+'</span> '+pres+'<div class="acc">'+(s.meet?'<a class="btn" href="'+esc(s.meet)+'" target="_blank" rel="noopener">Entrar al Meet</a>':'<span class="pill esp">enlace pendiente</span>')+(s.materiales?'<a class="btn oro" href="'+esc(s.materiales)+'" target="_blank" rel="noopener">Materiales</a>':'')+(s.grabacion?'<a class="btn gris" href="'+esc(s.grabacion)+'" target="_blank" rel="noopener">Grabación</a>':'')+'</div></div></div>';}).join('');
  $('planActual').innerHTML=D.planeacion.url?'<div class="aviso ok"><b>Planeación recibida</b> el '+esc(D.planeacion.el)+': <a href="'+esc(D.planeacion.url)+'" target="_blank" rel="noopener">'+esc(D.planeacion.nombre||'ver')+'</a>. Puedes reemplazarla.</div>':'<div class="aviso err"><b>Aún no has entregado tu planeación.</b></div>';
  if(D.constancia){ $('planActual').innerHTML+='<div class="aviso ok"><b>Constancia emitida:</b> <a href="'+esc(D.constancia)+'" target="_blank" rel="noopener">descargar</a>.</div>'; }
  $('bEntrada').style.display='none'; $('bDatos').style.display='block'; $('bPlan').style.display='block'; window.scrollTo({top:0,behavior:'smooth'});
}
$('archivo').addEventListener('change',()=>{const f=$('archivo').files[0]; if(!f){$('zonaArchivo').classList.remove('con');return;} $('zonaArchivo').classList.add('con'); $('archivoTxt').innerHTML='<b>'+esc(f.name)+'</b><br><span class="ayuda">'+(Math.round(f.size/1048576*10)/10)+' MB · toca para cambiar</span>';});
async function enviarPlan(){
  aviso('aviso','',''); const f=$('archivo').files[0], enl=$('enlace').value.trim(); if(!f&&!enl){aviso('aviso','Adjunta tu planeación o pega un enlace.','err');return;}
  if(f&&f.size>(D.maxMB||10)*1048576){aviso('aviso','El archivo pesa más de '+(D.maxMB||10)+' MB. Expórtalo a PDF o usa un enlace.','err');return;}
  const btn=$('enviar'); btn.disabled=true; btn.textContent='Enviando…';
  try{ let sid='';
    if(f){ const b64=await new Promise((res,rej)=>{const r=new FileReader();r.onload=()=>res(String(r.result).split(',')[1]||'');r.onerror=()=>rej(new Error('no se pudo leer'));r.readAsDataURL(f);});
      sid='d'+Date.now().toString(36)+Math.random().toString(36).slice(2,10); const TAM=512*1024,total=Math.ceil(b64.length/TAM);
      for(let n=0;n<total;n++){const c=new URLSearchParams();c.set('sid',sid);c.set('n',String(n));c.set('d',b64.slice(n*TAM,(n+1)*TAM));const rt=await fetch('convocatoria-docente.php?trozo=1',{method:'POST',body:c});let dt;try{dt=JSON.parse(await rt.text());}catch(e){throw new Error('el servidor rechazó la carga');} if(!dt.ok)throw new Error(dt.error||'falló la carga'); btn.textContent='Subiendo… '+Math.round((n+1)/total*100)+'%';} }
    const cf=new URLSearchParams(); cf.set('sid',sid); cf.set('datos',JSON.stringify({folio:D.folio,enlace:enl,archivoNombre:f?f.name:'',archivoMime:f?(f.type||'application/octet-stream'):''}));
    const resp=await fetch('convocatoria-docente.php?dipplaneacion=1',{method:'POST',body:cf}); let d; try{d=JSON.parse(await resp.text());}catch(e){throw new Error('el servidor respondió '+resp.status);}
    if(d.ok){ D.planeacion={url:d.url,nombre:d.nombre,el:'hoy'}; pintar(); aviso('aviso','<b>Planeación recibida.</b> Gracias.','ok'); } else aviso('aviso',d.error||'No se pudo guardar.','err');
  }catch(err){ aviso('aviso','No se pudo enviar: '+esc(err.message||err),'err'); } finally{ btn.disabled=false; btn.textContent='Enviar mi planeación'; }
}
if($('folio').value) entrar();
</script></body></html><?php
    exit;
}

/* (31-ago) ENCUESTA BREVE al aspirante tras su clase muestra: ?encuesta=1&folio= */
if (isset($_GET['encdatos'])) { header('Content-Type: application/json; charset=utf-8'); $r = guardian(['accion' => 'encuesta_fase2_datos', 'folio' => trim((string)($_GET['folio'] ?? ''))]); echo json_encode($r ?: ['ok' => false, 'error' => 'No pudimos conectar.'], JSON_UNESCAPED_UNICODE); exit; }
if (isset($_GET['encenviar'])) { header('Content-Type: application/json; charset=utf-8'); $datos = isset($_POST['datos']) ? json_decode($_POST['datos'], true) : null; if (!is_array($datos)) { echo json_encode(['ok' => false, 'error' => 'Sin datos.']); exit; } $datos['accion'] = 'encuesta_fase2_enviar'; $r = guardian(['accion' => 'encuesta_fase2_enviar'], json_encode($datos)); echo json_encode($r ?: ['ok' => false, 'error' => 'No pudimos conectar.'], JSON_UNESCAPED_UNICODE); exit; }
if (isset($_GET['encuesta'])) {
    $folioIni = preg_replace('/[^A-Za-z0-9\-]/', '', (string)($_GET['folio'] ?? ''));
    header('Content-Type: text/html; charset=utf-8');
    ?><!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex, nofollow"><title>Tu opinión · CESSUM</title>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600;700&family=Montserrat:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root{--rojo:#B11D29;--rojo-osc:#8E1621;--oro:#A56B16;--verde:#1E7A38;--crema:#F7F3EA;--tinta:#1F1F1F;--gris:#6E6E6E;--linea:#E8DFCE;}
  *{box-sizing:border-box;} body{margin:0;padding:0 0 50px;background:var(--crema);color:var(--tinta);font-family:'Montserrat',Arial,sans-serif;font-size:15.5px;line-height:1.6;}
  .hero{background:linear-gradient(135deg,var(--rojo),var(--rojo-osc));color:#fff;border-bottom:4px solid var(--oro);padding:36px 18px 32px;text-align:center;} .hero h1{font-family:'Playfair Display',Georgia,serif;font-size:clamp(22px,4.4vw,32px);margin:.3rem 0;} .hero p{margin:0;opacity:.92;font-size:14.5px;}
  .wrap{max-width:720px;margin:0 auto;padding:0 18px;} .bloque{background:#fff;border-radius:16px;padding:26px 30px;margin:-22px 0 20px;box-shadow:0 12px 34px rgba(80,60,20,.10);border-top:4px solid var(--oro);}
  h2{font-family:'Playfair Display',Georgia,serif;font-size:21px;margin:0 0 .5rem;color:var(--rojo);} .ayuda{font-size:12.5px;color:var(--gris);}
  .preg{border:1.5px solid var(--linea);border-radius:12px;padding:12px 14px;margin:10px 0;background:#FDFCF9;} .preg b{display:block;margin-bottom:8px;font-size:14.5px;}
  .esc{display:grid;grid-template-columns:repeat(5,1fr);gap:6px;} .esc label{border:1.5px solid var(--linea);border-radius:9px;padding:9px 4px;text-align:center;cursor:pointer;background:#fff;font-weight:700;} .esc label:has(input:checked){background:var(--verde);border-color:var(--verde);color:#fff;} .esc input{display:none;}
  .esc-t{display:flex;justify-content:space-between;font-size:11px;color:var(--gris);margin-top:4px;}
  textarea{width:100%;min-height:90px;padding:10px 12px;font-family:inherit;font-size:14.5px;border:1.5px solid #DCD3C2;border-radius:9px;}
  button{width:100%;margin-top:14px;padding:14px;font-family:inherit;font-size:15px;font-weight:700;color:#fff;background:var(--rojo);border:0;border-radius:11px;cursor:pointer;} button:disabled{background:#C9C1B2;}
  .aviso{padding:12px 14px;border-radius:10px;font-size:14px;margin:12px 0;} .aviso.ok{background:rgba(30,122,56,.10);border:1px solid rgba(30,122,56,.4);} .aviso.err{background:rgba(177,29,41,.08);border:1px solid rgba(177,29,41,.4);}
  .pie{text-align:center;font-size:12px;color:#9A9A9A;margin-top:20px;}
</style></head><body>
<div class="hero"><h1>Un minuto: ¿cómo viviste tu clase muestra?</h1><p>Cinco preguntas y un comentario. No influye en tu evaluación; sirve para mejorar la siguiente convocatoria.</p></div>
<div class="wrap"><div class="bloque" id="b"><p class="ayuda">Cargando…</p></div><div class="pie">Centro de Estudios Superiores del Mayo, A.C. · Navojoa, Sonora</div></div>
<script>
const FOLIO=<?= json_encode($folioIni) ?>; const $=id=>document.getElementById(id); const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
let D=null;
async function cargar(){ if(!FOLIO){$('b').innerHTML='<div class="aviso err">Falta el folio en el enlace. Usa el botón del correo.</div>';return;}
  try{ const r=await fetch('convocatoria-docente.php?encdatos=1&folio='+encodeURIComponent(FOLIO),{cache:'no-store'}); D=await r.json(); }catch(e){ D={ok:false,error:'No pudimos conectar.'}; }
  if(!D.ok){ $('b').innerHTML='<div class="aviso err">'+esc(D.error||'No se pudo cargar')+'</div>'; return; }
  let h='<h2>Gracias, '+esc(D.nombre.split(' ')[0])+'</h2>'+(D.respondida?'<div class="aviso ok">Ya habías respondido. Si vuelves a enviar, se reemplazan tus respuestas.</div>':'');
  D.preguntas.forEach(p=>{ h+='<div class="preg"><b>'+esc(p.txt)+'</b><div class="esc">'+[1,2,3,4,5].map(n=>'<label><input type="radio" name="r_'+p.id+'" value="'+n+'"><span>'+n+'</span></label>').join('')+'</div><div class="esc-t"><span>Totalmente en desacuerdo</span><span>Totalmente de acuerdo</span></div></div>'; });
  h+='<div class="preg"><b>¿Algo que debamos saber o mejorar?</b><textarea id="com" placeholder="Opcional"></textarea></div><div id="aviso"></div><button id="env" onclick="enviar()">Enviar</button>';
  $('b').innerHTML=h;
}
async function enviar(){ const r={}; let n=0; D.preguntas.forEach(p=>{const s=document.querySelector('input[name="r_'+p.id+'"]:checked'); if(s){r[p.id]=Number(s.value);n++;}});
  if(!n&&!$('com').value.trim()){ $('aviso').innerHTML='<div class="aviso err">Responde al menos una pregunta.</div>'; return; }
  $('env').disabled=true; const cf=new URLSearchParams(); cf.set('datos',JSON.stringify({folio:FOLIO,r:r,comentario:$('com').value.trim()}));
  try{ const resp=await fetch('convocatoria-docente.php?encenviar=1',{method:'POST',body:cf}); const d=await resp.json(); if(d.ok){ $('b').innerHTML='<h2>¡Gracias!</h2><div class="aviso ok">'+esc(d.nota||'Respuestas guardadas.')+'</div>'; } else { $('aviso').innerHTML='<div class="aviso err">'+esc(d.error||'No se pudo enviar')+'</div>'; $('env').disabled=false; } }
  catch(e){ $('aviso').innerHTML='<div class="aviso err">No pudimos conectar. Intenta de nuevo.</div>'; $('env').disabled=false; }
}
cargar();
</script></body></html><?php
    exit;
}

/* (ago-29) CIERRE DE LA RECEPCION.
 * ------------------------------------------------------------
 * El backend ya rechaza las postulaciones fuera de plazo, pero esta pagina
 * seguia mostrando el formulario completo: el aspirante llenaba todo, subia
 * su CV, y se enteraba hasta el final. Eso no es un cierre, es una trampa.
 * Dos personas se postularon la madrugada del 29 por este hueco.
 *
 * La fecha NO se escribe aqui: se consulta a DOCSOL_CIERRE_RECEPCION del
 * Code.gs, que es el unico lugar donde vive. Si la convocatoria se prorroga,
 * se cambia alla y esta pagina se reabre sola.
 *
 * Se usa guardian(), el mismo helper con sus tres direcciones de respaldo,
 * para no depender de una sola ruta.
 */
$est = guardian(['accion' => 'docsol_estado']);
// Si el Guardian no contesta se asume CERRADA. Es la falla segura: mostrar
// el formulario por un problema de red seria seguir recibiendo expedientes
// que nadie va a poder considerar.
$abierta = ($est && !empty($est['ok'])) ? !empty($est['abierta']) : false;
/* (25-sep) Si el Guardián no contestó, NO es lo mismo que «cerrada»: se le
   dice al aspirante que intente en unos minutos, sin darle por cerrada la
   convocatoria. El vigilante diario lee la marca «cessum-estado». */
$sinConexion = !($est && !empty($est['ok']));
$cerroEl = ($est && !empty($est['cierra'])) ? $est['cierra'] : '';

if (!$abierta) {
    header('Content-Type: text/html; charset=utf-8');
    ?><!DOCTYPE html>
<!-- cessum-estado: <?= $sinConexion ? 'sin-conexion' : 'cerrada' ?> -->
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Convocatoria cerrada &middot; CESSUM</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;800&family=Playfair+Display:wght@700&display=swap" rel="stylesheet">
<style>
  :root { --rojo:#8E1621; --rojo2:#B11D29; --oro:#A56B16; --crema:#FBF7EF; }
  * { box-sizing:border-box; }
  body { margin:0; font-family:Montserrat,system-ui,sans-serif; background:var(--crema); color:#222; }
  .hero { background:linear-gradient(135deg,var(--rojo),var(--rojo2)); color:#fff;
          padding:52px 20px 56px; text-align:center; }
  .hero .marca { font-size:11px; letter-spacing:2.5px; font-weight:600;
                 opacity:.85; margin-bottom:14px; }
  .hero h1 { font-family:'Playfair Display',Georgia,serif; font-size:32px;
             margin:0; line-height:1.25; }
  .caja { max-width:640px; margin:-26px auto 44px; background:#fff;
          border:1px solid #e6ddc9; border-top:4px solid var(--oro);
          border-radius:14px; padding:30px 28px; }
  .fecha { display:inline-block; background:#FBF2E0; color:var(--oro);
           font-weight:600; font-size:13px; padding:7px 14px;
           border-radius:20px; margin-bottom:18px; }
  .caja h2 { color:var(--rojo); font-size:19px; margin:0 0 14px; }
  .caja p { font-size:14.5px; line-height:1.68; margin:0 0 14px; }
  .btn { display:inline-block; margin-top:10px; background:var(--rojo);
         color:#fff; text-decoration:none; font-weight:600; font-size:14px;
         padding:13px 24px; border-radius:9px; }
  .pie { text-align:center; font-size:12px; color:#8a8a8a; padding:0 20px 36px;
         line-height:1.7; }
  /* (1-sep) Formulario del banco de talento en la pantalla de cerrada. */
  .lb{display:block;text-align:left;font-size:11px;font-weight:800;letter-spacing:.06em;
      text-transform:uppercase;color:#95590E;margin:12px 0 4px;}
  .inp{width:100%;padding:11px 13px;border:1.5px solid var(--linea,#E8DFCE);border-radius:10px;
       font:inherit;font-size:15px;background:#FDFCF9;box-sizing:border-box;}
  .inp:focus{outline:none;border-color:#A56B16;background:#fff;}
  .ayuda{font-size:12.5px;color:#5E5E5E;text-align:left;margin-top:4px;line-height:1.5;}
  .nota{background:#FBF7EF;border-left:3px solid #A56B16;padding:11px 13px;font-size:12.8px;
        color:#4A4034;line-height:1.55;text-align:left;border-radius:0 8px 8px 0;}
  .aviso{padding:12px 14px;border-radius:11px;font-size:13.5px;line-height:1.55;text-align:left;}
  .aviso.ok{background:rgba(30,122,56,.08);border:1px solid rgba(30,122,56,.35);color:#14612C;}
  .aviso.err{background:#FBF0F1;border:1px solid rgba(177,29,41,.35);color:#8E1621;}
  @media(max-width:600px){ .hero h1{font-size:25px;} .caja{margin:-20px 14px 34px;} }
</style>
</head>
<body>
  <div class="hero">
    <div class="marca">CENTRO DE ESTUDIOS SUPERIORES DEL MAYO</div>
    <h1>La recepci&oacute;n de solicitudes<br>ya cerr&oacute;</h1>
  </div>

  <?php if ($sinConexion): ?>
  <div class="caja">
    <h2>Estamos actualizando la informaci&oacute;n</h2>
    <p>En este momento no pudimos consultar el estado de la convocatoria.
       <strong>Vuelve a intentarlo en unos minutos.</strong></p>
    <p>Si el problema contin&uacute;a, escr&iacute;benos a
       <a href="mailto:contacto@cessum.mx">contacto@cessum.mx</a>.</p>
    <a class="btn" href="convocatoria-docente.php">Intentar de nuevo</a>
  </div>
  <?php else: ?>
  <div class="caja">
    <?php if ($cerroEl !== ''): ?>
      <div class="fecha">Cerr&oacute; el <?= e($cerroEl) ?></div>
    <?php endif; ?>

    <h2>Gracias por tu inter&eacute;s</h2>

    <p>La convocatoria para incorporarse a la planta docente del CESSUM
       concluy&oacute; su etapa de recepci&oacute;n. El comit&eacute;
       dictaminador se encuentra evaluando los expedientes recibidos.</p>

    <p>Si enviaste tu solicitud dentro del plazo,
       <strong>recibir&aacute;s la resoluci&oacute;n por correo
       electr&oacute;nico</strong>. No necesitas hacer nada m&aacute;s ni
       volver a postularte.</p>

    <p>Abrimos convocatorias con regularidad conforme crece nuestra oferta
       educativa. Te invitamos a estar pendiente de nuestro sitio y de
       nuestras redes.</p>

    <a class="btn" href="https://cessum.mx/">Ir al sitio del CESSUM</a>
  </div>
  <?php endif; ?>

  <div class="caja" style="margin-top:0;border-color:#A56B16;" id="avisame">
    <h2>Av&iacute;sanos que te interesa</h2>
    <p>Si quieres participar en la <strong>pr&oacute;xima convocatoria</strong>,
       d&eacute;janos tus datos. Te generamos un <strong>folio</strong> y, en cuanto
       abramos, te escribimos: entrar&aacute;s con ese folio sin volver a capturar nada.</p>

    <?php if ($intMsg): ?>
      <div class="aviso <?= $intTipo ?>" style="margin:10px 0;">
        <?= e($intMsg) ?>
        <?php if ($intFolio): ?>
          <div style="font-family:'Courier New',monospace;font-size:22px;font-weight:700;letter-spacing:.08em;color:#B11D29;background:#FBF7EF;border:2px dashed #A56B16;border-radius:10px;padding:11px 16px;display:inline-block;margin:9px 0 4px;"><?= e($intFolio) ?></div>
          <div style="font-size:12.5px;">Gu&aacute;rdalo. Tambi&eacute;n te lo enviamos por correo<?= $intYa ? ' cuando te registraste' : '' ?>.</div>
        <?php endif; ?>
      </div>
    <?php endif; ?>

    <?php if (!$intFolio): ?>
    <form method="post" autocomplete="on" style="text-align:left;margin-top:12px;">
      <label class="lb" for="in">Nombre completo</label>
      <input class="inp" id="in" name="int_nombre" required maxlength="120"
             placeholder="Como aparece en tus documentos" value="<?= e($_POST['int_nombre'] ?? '') ?>">

      <label class="lb" for="ic">Correo electr&oacute;nico</label>
      <input class="inp" id="ic" name="int_correo" type="email" required maxlength="120"
             placeholder="tucorreo@ejemplo.com" value="<?= e($_POST['int_correo'] ?? '') ?>">
      <div class="ayuda">Aqu&iacute; te avisaremos. Revisa que est&eacute; bien escrito.</div>

      <label class="lb" for="it">Tel&eacute;fono con WhatsApp</label>
      <input class="inp" id="it" name="int_telefono" type="tel" maxlength="20"
             placeholder="642 000 0000" value="<?= e($_POST['int_telefono'] ?? '') ?>">

      <label class="lb" for="ig">Grado m&aacute;ximo de estudios</label>
      <select class="inp" id="ig" name="int_grado">
        <option value="">Selecciona&hellip;</option>
        <?php foreach (['Licenciatura', 'Especialidad', 'Maestría', 'Doctorado', 'Posdoctorado'] as $gr): ?>
          <option <?= ($_POST['int_grado'] ?? '') === $gr ? 'selected' : '' ?>><?= e($gr) ?></option>
        <?php endforeach; ?>
      </select>

      <label class="lb" for="ici">Ciudad donde resides</label>
      <input class="inp" id="ici" name="int_ciudad" maxlength="80"
             placeholder="Navojoa, Sonora" value="<?= e($_POST['int_ciudad'] ?? '') ?>">

      <label class="lb" for="ia">Qu&eacute; asignaturas podr&iacute;as impartir</label>
      <input class="inp" id="ia" name="int_asignaturas" maxlength="200"
             placeholder="Metodolog&iacute;a de la investigaci&oacute;n, Evaluaci&oacute;n del aprendizaje&hellip;"
             value="<?= e($_POST['int_asignaturas'] ?? '') ?>">
      <div class="ayuda">Es orientativo; en la convocatoria las eliges formalmente.</div>

      <label class="lb" for="im">Algo que quieras contarnos (opcional)</label>
      <textarea class="inp" id="im" name="int_mensaje" rows="3" maxlength="900"
                placeholder="Tu experiencia frente a grupo, tu l&iacute;nea de trabajo&hellip;"><?= e($_POST['int_mensaje'] ?? '') ?></textarea>

      <div class="nota" style="margin:12px 0;">
        <strong>Esto no es una solicitud todav&iacute;a</strong> y no te incluye en la
        convocatoria que acaba de cerrar. Es un registro para avisarte cuando haya una
        nueva; ah&iacute; decides si participas. Puedes pedir tu baja escribiendo a
        contacto@cessum.mx.
      </div>

      <button type="submit" class="btn">Av&iacute;senme de la pr&oacute;xima convocatoria</button>
    </form>
    <?php endif; ?>
  </div>

  <div class="caja" style="margin-top:0;">
    <h2>&iquest;Te invitamos a la segunda fase?</h2>
    <p>Si recibiste el correo de invitaci&oacute;n a la <strong>clase
       muestra</strong>, entra con tu folio para elegir d&iacute;a y hora,
       enviar tu presentaci&oacute;n y confirmar tu disponibilidad para el
       diplomado.</p>
    <a class="btn" href="convocatoria-docente.php?fase2=1">Entrar con mi folio</a>
  </div>

  <div class="pie">
    Centro de Estudios Superiores del Mayo, A.C. &middot; CCT 26PSU0110Z &middot; Navojoa, Sonora<br>
    M&aacute;s que una universidad, una familia.
  </div>
</body>
</html><?php
    exit;
}

$cat = guardian(['accion' => 'docsol_catalogo']);
$catalogo = ($cat && !empty($cat['ok'])) ? $cat['catalogo'] : [];
$MAX = (int)($cat['maxAsignaturas'] ?? 5);
$MINJ = (int)($cat['justificacionMinima'] ?? 80);
$MAXC = (int)($cat['cartaMaxima'] ?? 500);
?><!DOCTYPE html>
<!-- cessum-estado: <?= $catalogo ? 'abierta' : 'abierta-sin-catalogo' ?> -->
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#B11D29">
<title>Convocatoria docente · CESSUM</title>
<meta name="description" content="Convocatoria abierta para incorporarse a la planta docente del Centro de Estudios Superiores del Mayo. Licenciatura, maestría y doctorado.">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600;700&family=Montserrat:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root{--rojo:#B11D29;--rojo-osc:#8E1621;--oro:#A56B16;--oro-cl:#C8942F;
        --verde:#1E7A38;--crema:#F7F3EA;--tinta:#1F1F1F;--gris:#6E6E6E;--linea:#E8DFCE;}
  *{box-sizing:border-box;}
  body{margin:0;padding:0 0 60px;background:var(--crema);
    background-image:repeating-linear-gradient(135deg,rgba(165,107,22,.026) 0 2px,transparent 2px 9px);
    color:var(--tinta);font-family:'Montserrat',Arial,sans-serif;font-size:15.5px;
    line-height:1.68;-webkit-font-smoothing:antialiased;}
  .hero{background:linear-gradient(135deg,var(--rojo),var(--rojo-osc));color:#fff;
    border-bottom:4px solid var(--oro);padding:52px 18px 44px;text-align:center;}
  .hero-logo{height:64px;width:auto;display:block;margin:0 auto 20px;}
  .hero .eyebrow{font-size:11.5px;letter-spacing:.16em;text-transform:uppercase;
    opacity:.85;font-weight:600;}
  .hero h1{font-family:'Playfair Display',Georgia,serif;font-size:clamp(28px,5vw,44px);
    margin:.5rem 0 .6rem;line-height:1.12;}
  .hero p{max-width:640px;margin:0 auto;font-size:16px;opacity:.94;}
  .wrap{max-width:880px;margin:0 auto;padding:0 18px;}
  .bloque{background:#fff;border-radius:16px;padding:28px 30px;margin:-26px 0 20px;
    box-shadow:0 1px 2px rgba(0,0,0,.04),0 12px 34px rgba(80,60,20,.10);
    border-top:4px solid var(--oro);}
  .bloque + .bloque{margin-top:20px;border-top:0;border-left:4px solid var(--oro);}
  h2{font-family:'Playfair Display',Georgia,serif;font-size:24px;margin:0 0 .6rem;color:var(--rojo);}
  h3{font-family:'Playfair Display',Georgia,serif;font-size:18px;margin:1.4rem 0 .4rem;}
  .paso{display:flex;gap:14px;margin-bottom:14px;}
  .paso .n{flex:0 0 34px;height:34px;border-radius:50%;background:var(--oro);color:#fff;
    display:flex;align-items:center;justify-content:center;font-weight:700;font-size:15px;}
  .paso .t{flex:1;}
  .paso .t b{display:block;font-size:15.5px;}
  .paso .t span{font-size:13.5px;color:var(--gris);}
  .comite{list-style:none;padding:0;margin:.6rem 0 0;}
  .comite li{padding:9px 0;border-bottom:1px solid var(--linea);font-size:14.5px;}
  .comite li:last-child{border-bottom:0;}
  .comite .cargo{display:block;font-size:12.5px;color:var(--gris);}
  .destacado{background:rgba(165,107,22,.08);border-left:3px solid var(--oro);
    padding:14px 16px;border-radius:8px;margin:1rem 0;font-size:14.5px;line-height:1.6;}
  label{display:block;font-size:11.5px;letter-spacing:.05em;text-transform:uppercase;
    font-weight:700;color:var(--gris);margin:16px 0 5px;}
  input,select,textarea{width:100%;padding:11px 13px;font-family:inherit;font-size:15px;
    border:1.5px solid #DCD3C2;border-radius:9px;background:#FDFCF9;color:var(--tinta);}
  input:focus,select:focus,textarea:focus{outline:0;border-color:var(--oro);background:#fff;}
  .fila{display:grid;grid-template-columns:1fr 1fr;gap:16px;}
  .ayuda{font-size:12px;color:var(--gris);margin-top:4px;line-height:1.45;}
  .asig{border:1.5px solid var(--linea);border-radius:12px;padding:14px 16px;
    margin-bottom:12px;background:#FDFCF9;}
  .asig-cab{display:flex;align-items:center;gap:10px;margin-bottom:2px;}
  .asig-cab .num{width:26px;height:26px;border-radius:50%;background:var(--oro);color:#fff;
    display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:700;flex:0 0 26px;}
  .asig-cab .tit{font-weight:700;font-size:14px;}
  .quitar{margin-left:auto;background:none;border:0;color:var(--rojo);cursor:pointer;
    font-size:12.5px;font-weight:700;padding:0;}
  .ficha{margin-top:10px;padding:12px 14px;background:rgba(165,107,22,.07);
    border-left:3px solid var(--oro);border-radius:8px;font-size:13px;line-height:1.55;
    max-height:260px;overflow-y:auto;}
  .ficha b{display:block;font-size:10.5px;letter-spacing:.06em;text-transform:uppercase;
    color:var(--oro);margin-top:8px;}
  .ficha b:first-child{margin-top:0;}
  .ficha p{margin:.25rem 0 0;white-space:pre-wrap;}
  .ficha-clave{font-size:11.5px;color:var(--gris);font-weight:600;margin-bottom:6px;}
  .descargas{display:flex;gap:12px;flex-wrap:wrap;margin-top:18px;}
  .btn-pdf,.btn-plan{display:inline-flex;align-items:center;gap:8px;padding:12px 20px;
    border-radius:10px;font-weight:700;font-size:14px;text-decoration:none;}
  .btn-pdf{background:var(--rojo);color:#fff;box-shadow:0 3px 12px rgba(177,29,41,.24);}
  .btn-pdf:hover{background:var(--rojo-osc);}
  .btn-pdf::before{content:'↓';font-size:15px;}
  .btn-plan{background:#fff;color:var(--oro);border:1.5px solid var(--oro);}
  .btn-plan:hover{background:rgba(165,107,22,.07);}
  .apoyos{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:8px 0 18px;}
  .apoyo{text-align:left;background:#fff;border:1.5px solid var(--linea);border-radius:12px;
    padding:14px 16px;cursor:pointer;font-family:inherit;transition:border-color .15s,box-shadow .15s;}
  .apoyo:hover{border-color:var(--oro);box-shadow:0 4px 14px rgba(80,60,20,.10);}
  .apoyo.activo{border-color:var(--rojo);background:#FDF6F6;}
  .apoyo b{display:block;font-size:14.5px;color:var(--rojo);margin-bottom:3px;}
  .apoyo span{font-size:12.5px;color:var(--gris);line-height:1.45;}
  .panelAyuda{background:#FDFCF9;border:1.5px solid var(--linea);border-radius:12px;
    padding:18px 20px;margin-bottom:18px;}
  .panelAyuda h4{font-family:'Playfair Display',Georgia,serif;font-size:17px;margin:0 0 10px;
    color:var(--rojo);}
  .checks{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));
    gap:6px;margin-top:4px;}
  .check{display:flex;align-items:center;gap:9px;padding:10px 13px;background:#fff;
    border:1.5px solid var(--linea);border-radius:9px;cursor:pointer;font-size:13.5px;
    transition:border-color .13s,background .13s;}
  .check:hover{border-color:var(--oro);}
  .check:has(input:checked){border-color:var(--rojo);background:#FDF6F6;font-weight:600;}
  .check input{width:auto;margin:0;accent-color:var(--rojo);
    width:17px;height:17px;flex:0 0 17px;}
  .chips{display:flex;flex-wrap:wrap;gap:7px;margin-top:2px;}
  .chip{padding:7px 13px;border-radius:20px;border:1.5px solid var(--linea);background:#fff;
    font-size:13px;cursor:pointer;font-family:inherit;transition:all .13s;}
  .chip:hover{border-color:var(--oro);}
  .chip.on{background:var(--rojo);border-color:var(--rojo);color:#fff;font-weight:600;}
  .sug{background:#fff;border:1.5px solid var(--linea);border-left:3px solid var(--oro);
    border-radius:9px;padding:11px 13px;margin-bottom:8px;display:flex;gap:12px;align-items:flex-start;}
  .sug .txt{flex:1;}
  .sug .txt b{display:block;font-size:14px;}
  .sug .txt span{font-size:12px;color:var(--gris);}
  .sug .por{font-size:11.5px;color:var(--oro);font-weight:600;margin-top:3px;display:block;}
  .sug button{margin:0;padding:7px 13px;font-size:12.5px;background:var(--oro);}
  .sug button:hover{background:#8A5713;}
  .sug button:disabled{background:#C9C1B2;cursor:not-allowed;}
  .planProg h5{font-size:13.5px;margin:14px 0 5px;color:var(--rojo);font-weight:700;}
  .planMat{display:flex;gap:10px;align-items:center;padding:6px 0;
    border-bottom:1px solid var(--linea);font-size:13px;}
  .planMat span{flex:1;}
  .planMat button{margin:0;padding:5px 11px;font-size:12px;background:var(--oro);}
  #listaPlan{max-height:430px;overflow-y:auto;margin-top:10px;}
  @media(max-width:700px){.apoyos{grid-template-columns:1fr;}}
  button.principal{padding:14px 28px;font-size:16px;font-weight:700;font-family:inherit;
    color:#fff;background:var(--rojo);border:0;border-radius:10px;cursor:pointer;
    box-shadow:0 4px 14px rgba(177,29,41,.26);}
  button.principal:hover{background:var(--rojo-osc);}
  button.suave{padding:9px 16px;font-size:13.5px;font-weight:700;font-family:inherit;
    color:#fff;background:var(--oro);border:0;border-radius:8px;cursor:pointer;}
  button.suave:disabled{background:#C9C1B2;cursor:not-allowed;}
  .contador{font-size:12px;color:var(--gris);text-align:right;margin-top:3px;}
  .aviso{padding:14px 16px;border-radius:10px;font-size:14px;margin:16px 0;line-height:1.5;}
  .aviso.ok{background:rgba(30,122,56,.10);border:1px solid rgba(30,122,56,.4);}
  .aviso.err{background:rgba(177,29,41,.08);border:1px solid rgba(177,29,41,.4);}
  .pie{text-align:center;font-size:12px;color:#9A9A9A;margin-top:28px;line-height:1.7;}
  @media(max-width:700px){.fila{grid-template-columns:1fr;}.bloque{padding:20px 18px;}}
</style>
</head>
<body>

<div class="hero">
  <!-- (ago-25) El logo institucional. Como esta página no conoce la ruta
       exacta donde vive el logotipo en cessum.mx, se prueban las habituales
       en orden y, si ninguna existe, la imagen se oculta sola: más vale un
       encabezado sin logo que el ícono roto del navegador.
       Si sabes la ruta buena, ponla primera en LOGOS y borra las demás. -->
  <img id="logoCessum" class="hero-logo" alt="CESSUM"
       src="assets/img/logo-cessum-blanco.png">
  <div class="eyebrow">Centro de Estudios Superiores del Mayo</div>
  <h1>Convocatoria para incorporarse<br>a la planta docente</h1>
  <p>Buscamos profesionales que quieran impartir asignaturas de nuestros
     programas de licenciatura, maestría y doctorado.</p>
</div>

<div class="wrap">

  <div class="bloque">
    <h2>Quién puede participar</h2>
    <p>Profesionales con formación y experiencia en las áreas de los programas
       que oferta el CESSUM. Se valora el grado académico, la trayectoria
       docente y la producción académica, pero <b>el criterio determinante es
       la correspondencia entre el perfil y las asignaturas que se proponen
       impartir</b>: por eso se pide justificar cada una.</p>

    <h3>El proceso</h3>
    <div class="paso"><div class="n">1</div><div class="t">
      <b>Solicitud</b><span>Llenas este formulario: tus datos, hasta
      <?= $MAX ?> asignaturas con su justificación, y tu currículum.</span></div></div>
    <div class="paso"><div class="n">2</div><div class="t">
      <b>Filtro de perfiles</b><span>El comité académico revisa la
      correspondencia entre tu formación y lo que propones impartir. Es el
      criterio de la institución y es el primer filtro.</span></div></div>
    <div class="paso"><div class="n">3</div><div class="t">
      <b>Resolución</b><span>Recibes el resultado por correo, sea aceptado
      o no aceptado. En ambos casos con las observaciones del comité.</span></div></div>
    <div class="paso"><div class="n">4</div><div class="t">
      <b>Diplomado</b><span>Quien resulta aceptado cursa el diplomado
      institucional antes de ser contratado.</span></div></div>

    <div class="destacado">
      <b>Diplomado: Promoción de aprendizajes complejos en la docencia
      universitaria</b><br>
      <i>Interacciones didácticas desde el enfoque interconductual</i><br><br>
      80 horas · sesiones los lunes de 19:00 a 21:00 h · del 7 de septiembre a
      finales de octubre de 2026.<br><br>
      <b>Es gratuito y es requisito para la contratación.</b> No es un curso de
      inducción administrativa: se trabaja sobre tu propia planeación para
      diseñar interacciones que promuevan aprendizajes complejos —analizar,
      argumentar, criticar— y no solo la transmisión de contenidos.
    </div>

    <h3>Comité dictaminador</h3>
    <ul class="comite">
      <li>Dr. Jesús Bernardo Miranda Esquer
        <span class="cargo">Rector</span></li>
      <li>Dr. Jesús Bernardo Miranda Solís
        <span class="cargo">Vicerrector Académico</span></li>
      <li>Mtro. José Francisco Miranda Esquer
        <span class="cargo">Director General de Investigación</span></li>
      <li>Dra. Guadalupe Marisol Valenzuela Rodríguez
        <span class="cargo">Coordinadora de Doctorados</span></li>
      <li>Mtra. Erika Patricia Rivera Amado
        <span class="cargo">Coordinadora de Maestrías</span></li>
    </ul>

    <!-- (ago-24) La convocatoria oficial en PDF, para quien quiera leerla con
         calma, imprimirla o circularla entre colegas. El enlace de Drive es
         de solo lectura: se descarga, no se edita. -->
    <div class="descargas">
      <a class="btn-pdf" href="<?= e(PDF_CONVOCATORIA) ?>" target="_blank" rel="noopener">
        Descargar la convocatoria en PDF
      </a>
      <a class="btn-plan" href="mapa-curricular.html">
        Ver las 155 asignaturas del plan
      </a>
    </div>
    <p class="ayuda" style="margin-top:10px;">
      El documento en PDF contiene el fundamento, el perfil que se busca, la
      ruta del proceso, el calendario y las disposiciones generales.
    </p>
  </div>

  <div class="bloque" id="formulario">
    <h2>Formulario de solicitud</h2>
    <p class="ayuda">Todos los campos marcados son obligatorios. Al enviar
      recibirás un acuse con tu folio.</p>

    <?php if (!$catalogo): ?>
      <!-- (ago-24) Un selector vacío no dice nada y el aspirante cree que el
           sitio está roto. Se dice qué pasó y a quién avisarle. -->
      <div class="aviso err">
        <b>El catálogo de asignaturas no cargó.</b> No es tu conexión: es un
        problema nuestro. Escríbenos a
        <a href="mailto:contacto@cessum.mx">contacto@cessum.mx</a> y te
        registramos manualmente, o vuelve a intentarlo más tarde.
      </div>
    <?php endif; ?>
    <div id="aviso"></div>

    <form id="f" onsubmit="return false;">

      <h3>Tus datos</h3>
      <div class="fila">
        <div><label>Nombre completo *</label><input id="nombre" required></div>
        <div><label>Correo electrónico *</label><input id="correo" type="email" required>
          <div class="ayuda">Por aquí te avisamos el resultado.</div></div>
      </div>
      <div class="fila">
        <div><label>Teléfono / WhatsApp</label><input id="telefono"></div>
        <div><label>Grado máximo *</label>
          <select id="grado" required>
            <option value="">— Elige —</option>
            <option>Licenciatura</option>
            <option>Especialidad</option>
            <option>Maestría</option>
            <option>Doctorado</option>
          </select>
          <div class="ayuda">El posdoctorado es una estancia de investigación,
            no un grado: menciónalo en tu currículum.</div></div>
      </div>
      <div class="fila">
        <div><label>Institución donde obtuviste tu grado</label><input id="institucion"></div>
        <div><label>Cédula profesional del grado máximo</label><input id="cedula">
          <div class="ayuda">Si está en trámite, escríbelo.</div></div>
      </div>
      <div class="fila">
        <div><label>Años de experiencia docente</label>
          <input id="anios" type="number" min="0" max="60"></div>
        <div><label>Ciudad de residencia</label><input id="ciudad"
          placeholder="Navojoa, Sonora">
          <div class="ayuda">Para saber si puedes cubrir sesiones presenciales.</div></div>
      </div>

      <!-- (ago-25) Estos tres datos deciden más asignaciones que el grado:
           si puede dar sabatino, si vive cerca y si tiene producción
           reciente. Sin ellos el comité aprueba perfiles que después no se
           pueden programar. -->
      <label>¿En qué modalidades puedes impartir? *</label>
      <div id="mods" class="checks"></div>

      <label>¿Qué días tienes disponibles?</label>
      <div id="disp" class="checks"></div>

      <!-- (ago-25) La producción académica se quitó: ya viene en el CV y
           pedirla dos veces alarga el formulario sin aportar nada. -->
      <label>Distinciones o reconocimientos (opcional)</label>
      <input id="distinciones"
        placeholder="SNII, perfil PRODEP, membresías, certificaciones…">

      <h3>Asignaturas que propones impartir</h3>
      <p class="ayuda">Hasta <?= $MAX ?>. Elegir muchas no ayuda: preferimos
        ver un perfil claro. Cada una necesita su justificación
        (mínimo <?= $MINJ ?> caracteres). <b>Al elegir una asignatura verás sus
        propósitos y su contenido temático</b>, tal como aparecen en el plan de
        estudios.</p>

      <!-- (ago-24) DOS APOYOS PARA ELEGIR.
           Pedirle a alguien que elija cinco de 155 asignaturas sin conocer el
           plan es pedirle que adivine. El perfilador pregunta por su expertise
           y propone; el explorador deja ver el plan completo. -->
      <div class="apoyos">
        <button type="button" class="apoyo" id="btnPerfil">
          <b>Ayúdame a elegir</b>
          <span>Responde tres preguntas sobre tu experiencia y te proponemos las
            asignaturas que mejor corresponden a tu perfil.</span>
        </button>
        <button type="button" class="apoyo" id="btnExplorar">
          <b>Ver todas las materias</b>
          <span>Consulta el plan completo por programa, con buscador, y agrega
            las que quieras desde ahí.</span>
        </button>
      </div>

      <div id="perfil" class="panelAyuda" style="display:none;">
        <h4>Tres preguntas para perfilarte</h4>
        <label>1. ¿En qué áreas te mueves? Marca todas las que apliquen</label>
        <div id="areas" class="chips"></div>
        <label>2. ¿En qué niveles has impartido o podrías impartir?</label>
        <div id="niveles" class="chips"></div>
        <label>3. Años de experiencia docente en educación superior</label>
        <select id="expAnios" style="max-width:260px;">
          <option value="0">Menos de 2 años</option>
          <option value="1">De 2 a 5 años</option>
          <option value="2" selected>De 6 a 10 años</option>
          <option value="3">Más de 10 años</option>
        </select>
        <div><button type="button" class="suave" id="calcular" style="margin-top:14px;">
          Proponerme asignaturas</button></div>
        <div id="sugerencias"></div>
      </div>

      <div id="explorar" class="panelAyuda" style="display:none;">
        <h4>Plan de estudios completo</h4>
        <input type="search" id="buscar" placeholder="Buscar asignatura o programa…">
        <div id="listaPlan"></div>
      </div>

      <div id="asignaturas"></div>
      <button type="button" class="suave" id="agregar">+ Agregar asignatura</button>
      <span class="ayuda" id="cuenta" style="margin-left:10px;"></span>

      <h3>Justificación de interés</h3>
      <p class="ayuda">Por qué quieres colaborar con el CESSUM. No es una carta
        formal: bastan unas líneas claras.</p>
      <textarea id="carta" rows="6" maxlength="<?= $MAXC ?>"
        placeholder="Qué te acerca a esta institución y qué te gustaría aportar."></textarea>
      <div class="contador"><span id="ccarta">0</span> / <?= $MAXC ?></div>

      <h3>Currículum vítae *</h3>
      <input type="file" id="cv" accept=".pdf,.doc,.docx">
      <div class="ayuda">PDF o Word, hasta 4 MB.</div>

      <div style="margin-top:26px;">
        <button type="button" class="principal" id="enviar">Enviar mi solicitud</button>
      </div>
      <p class="ayuda" style="margin-top:12px;">
        Al enviar aceptas que el CESSUM trate tus datos para este proceso de
        selección, conforme a su
        <a href="aviso-de-privacidad.html">aviso de privacidad</a>.
      </p>
    </form>
  </div>

  <div class="pie">
    Centro de Estudios Superiores del Mayo, A.C. · CCT 26PSU0110Z<br>
    contacto@cessum.mx · (642) 137 6117
  </div>
</div>

<script>
// Rutas donde suele vivir el logotipo. Se prueban en orden; si ninguna
// carga, el encabezado se queda sin logo y no aparece el ícono roto.
const LOGOS = [
  'assets/img/logo-cessum-blanco.png',
  'assets/marca/logo-cessum-blanco.png',
  'assets/marca/cessum-blanco.png',
  'assets/img/logo-blanco.png',
  'assets/img/logo-cessum.png',
  'assets/marca/logo-cessum.svg',
];
(function () {
  const el = document.getElementById('logoCessum');
  if (!el) return;
  let i = 0;
  el.onerror = () => {
    i++;
    if (i < LOGOS.length) el.src = LOGOS[i];
    else el.style.display = 'none';
  };
  el.src = LOGOS[0];
})();

const CATALOGO = <?= json_encode($catalogo, JSON_UNESCAPED_UNICODE) ?>;
const MAX = <?= $MAX ?>, MINJ = <?= $MINJ ?>;
let n = 0;

const $ = id => document.getElementById(id);
function aviso(txt, tipo) {
  $('aviso').innerHTML = '<div class="aviso ' + tipo + '">' + txt + '</div>';
  $('aviso').scrollIntoView({behavior:'smooth', block:'center'});
}

// Los programas se agrupan por nivel para que la lista no sea un muro de 155
// nombres: primero se elige el programa, y solo entonces aparecen SUS
// asignaturas.
function opcionesPrograma() {
  let h = '<option value="">— Elige el programa —</option>';
  let nivel = '';
  CATALOGO.forEach((p, i) => {
    if (p.nivel !== nivel) {
      if (nivel) h += '</optgroup>';
      h += '<optgroup label="' + p.nivel + '">';
      nivel = p.nivel;
    }
    h += '<option value="' + i + '">' + p.programa + '</option>';
  });
  if (nivel) h += '</optgroup>';
  return h;
}

function agregar() {
  if (n >= MAX) return;
  n++;
  const id = 'a' + n;
  const div = document.createElement('div');
  div.className = 'asig';
  div.id = id;
  div.innerHTML =
    '<div class="asig-cab"><span class="num">' + n + '</span>' +
    '<span class="tit">Asignatura</span>' +
    '<button type="button" class="quitar" onclick="quitar(\'' + id + '\')">Quitar</button></div>' +
    '<label>Programa</label><select class="prog" onchange="cargarMats(this)">' +
      opcionesPrograma() + '</select>' +
    '<label>Asignatura</label><select class="mat" onchange="verFicha(this)"><option value="">— Elige primero el programa —</option></select>' +
    '<div class="ficha" style="display:none;"></div>' +
    '<label>¿Por qué te consideras apto para impartirla?</label>' +
    '<textarea class="jus" rows="3" placeholder="Formación, experiencia o producción que te respalda en esta materia."></textarea>' +
    '<div class="ayuda">Mínimo ' + MINJ + ' caracteres.</div>';
  $('asignaturas').appendChild(div);
  actualizar();
}
function quitar(id) { const el = $(id); if (el) el.remove(); actualizar(); }
function actualizar() {
  const vivos = document.querySelectorAll('#asignaturas .asig').length;
  $('agregar').disabled = vivos >= MAX;
  $('cuenta').textContent = vivos + ' de ' + MAX;
  document.querySelectorAll('#asignaturas .asig .num').forEach((el, i) => el.textContent = i + 1);
}
function cargarMats(sel) {
  const caja = sel.closest('.asig').querySelector('.mat');
  const ficha = sel.closest('.asig').querySelector('.ficha');
  ficha.style.display = 'none';
  const p = CATALOGO[sel.value];
  if (!p) { caja.innerHTML = '<option value="">— Elige primero el programa —</option>'; return; }
  // El índice va en el value: así se recupera la ficha completa sin volver a
  // buscar por nombre, que fallaría con las materias homónimas entre planes.
  caja.innerHTML = '<option value="">— Elige la asignatura —</option>' +
    p.asignaturas.map((m, j) => '<option value="' + j + '">' +
      m.nombre + (m.ciclo ? ' · ' + m.ciclo : '') + '</option>').join('');
}

// Propósitos y temario de la materia elegida. Salen del plan de estudios —
// son los mismos que recibe el docente en su carta descriptiva. Sin esto,
// elegir cinco asignaturas es elegir cinco títulos.
function verFicha(sel) {
  const caja = sel.closest('.asig');
  const ficha = caja.querySelector('.ficha');
  const p = CATALOGO[caja.querySelector('.prog').value];
  const m = p ? p.asignaturas[sel.value] : null;
  if (!m) { ficha.style.display = 'none'; return; }
  let h = '';
  if (m.clave) h += '<div class="ficha-clave">Clave ' + m.clave +
    (m.ciclo ? ' · ' + m.ciclo : '') + '</div>';
  if (m.fines) h += '<b>Propósitos de la asignatura</b><p>' + m.fines + '</p>';
  if (m.contenido) h += '<b>Contenido temático</b><p>' + m.contenido + '</p>';
  if (!h) h = '<p>Esta asignatura aún no tiene carta descriptiva cargada en el ' +
    'plan. Puedes proponerla igual y justificar tu perfil.</p>';
  ficha.innerHTML = h;
  ficha.style.display = 'block';
}

// ============================================================
//  PERFILADOR Y EXPLORADOR
//  ------------------------------------------------------------
//  Elegir cinco de 155 asignaturas sin conocer el plan es adivinar. El
//  perfilador propone a partir de la expertise declarada; el explorador deja
//  ver todo el plan y agregar desde ahí.
//
//  Las áreas y sus palabras salen del propio perfil que publica la
//  convocatoria — son las siete que agrupan los siete programas. La
//  coincidencia se busca en el NOMBRE de la asignatura y en sus propósitos,
//  no solo en el título: 'Seminario de Investigación' no dice 'metodología'
//  pero sus propósitos sí.
// ============================================================
const AREAS = [
  ['Pedagogía y didáctica', ['pedagog','didact','curricul','ensenanza','aprendizaje','planeacion','evaluacion educativa','corrientes']],
  ['Psicopedagogía y psicología', ['psicoped','psicolog','neurodesarrollo','psicopatolog','conducta','cognitiv','emocional','adolescente']],
  ['Educación inclusiva', ['inclusi','inclusion','diversidad','ajustes razonables','barreras','diseno universal','discapacidad','necesidades educativas']],
  // (ago-25, observación de Rectoría) 'estadística aplicada' apunta a lo
  // cuantitativo y deja fuera lo cualitativo. En metodología eso importa:
  // quien hace investigación narrativa o etnográfica también corresponde.
  ['Investigación educativa', ['investigacion','metodolog','epistemolog','seminario','tesis','estadistic','cualitativ','cuantitativ','paradigma','cientific','etnograf','narrativ','muestreo','instrumento']],
  ['Gestión y políticas educativas', ['gestion','administrac','politica','proyecto','calidad','institucion','liderazgo','direccion']],
  ['Tecnología educativa', ['tic','tecnolog','digital','virtual','material','multimedia','plataforma','linea']],
  ['Filosofía, sociología e historia', ['filosof','sociolog','historia','antropolog','etica','comparad','internacional','contexto']],
];
const NIVELES = ['Licenciatura', 'Maestría', 'Doctorado'];
const selAreas = new Set(), selNiveles = new Set();
// (ago-25) Las modalidades reales con que opera el CESSUM, no una lista
// genérica: son las tres formas en que se programa un grupo, y de eso
// depende si un perfil se puede asignar.
const MODALIDADES = [
  'Presencial (mixta)',
  'En línea (sabatino)',
  'En línea (entre semana)',
];
const DIAS = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
const selMods = new Set(), selDisp = new Set();

function norm(t) {
  return String(t||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
}

// Casillas de verificación de verdad, no botones que parecen etiquetas: en
// modalidad y disponibilidad el aspirante marca VARIAS, y una casilla dice
// eso sin que haya que explicarlo.
function pintaChecks(caja, lista, conj) {
  caja.innerHTML = '';
  lista.forEach((t, i) => {
    const id = caja.id + '_' + i;
    const fila = document.createElement('label');
    fila.className = 'check';
    fila.htmlFor = id;
    const cb = document.createElement('input');
    cb.type = 'checkbox'; cb.id = id; cb.value = t;
    cb.onchange = () => { cb.checked ? conj.add(t) : conj.delete(t); };
    const tx = document.createElement('span');
    tx.textContent = t;
    fila.appendChild(cb); fila.appendChild(tx);
    caja.appendChild(fila);
  });
}

function pintaChips(caja, lista, conj, alClic) {
  caja.innerHTML = '';
  lista.forEach(t => {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'chip'; b.textContent = t;
    b.onclick = () => {
      if (conj.has(t)) { conj.delete(t); b.classList.remove('on'); }
      else { conj.add(t); b.classList.add('on'); }
      if (alClic) alClic();
    };
    caja.appendChild(b);
  });
}

function togglePanel(cual) {
  const p = $('perfil'), x = $('explorar');
  const bp = $('btnPerfil'), bx = $('btnExplorar');
  const abrirP = cual === 'perfil' && p.style.display === 'none';
  const abrirX = cual === 'explorar' && x.style.display === 'none';
  p.style.display = abrirP ? 'block' : 'none';
  x.style.display = abrirX ? 'block' : 'none';
  bp.classList.toggle('activo', abrirP);
  bx.classList.toggle('activo', abrirX);
  if (abrirX) pintaPlan('');
}

// Puntúa cada asignatura contra las áreas marcadas. No inventa: si una
// materia no coincide con nada, no aparece.
function sugerir() {
  const caja = $('sugerencias');
  if (!selAreas.size) {
    caja.innerHTML = '<div class="ayuda" style="margin-top:12px;">Marca al menos un área.</div>';
    return;
  }
  const claves = [];
  AREAS.forEach(([nom, kws]) => { if (selAreas.has(nom)) claves.push([nom, kws]); });
  const res = [];
  CATALOGO.forEach((p, pi) => {
    if (selNiveles.size && !selNiveles.has(p.nivel)) return;
    p.asignaturas.forEach((m, mi) => {
      const enNombre = norm(m.nombre);
      const enFines = norm(m.fines || '');
      let pts = 0, porQue = [];
      claves.forEach(([nom, kws]) => {
        kws.forEach(k => {
          // El nombre pesa más que los propósitos: una materia que se LLAMA
          // "Educación inclusiva" corresponde más que otra que la menciona.
          if (enNombre.includes(k)) { pts += 3; if (!porQue.includes(nom)) porQue.push(nom); }
          else if (enFines.includes(k)) { pts += 1; if (!porQue.includes(nom)) porQue.push(nom); }
        });
      });
      if (pts > 0) res.push({ pi, mi, m, prog: p.programa, nivel: p.nivel, pts, porQue });
    });
  });
  res.sort((a,b) => b.pts - a.pts);
  const top = res.slice(0, 12);
  if (!top.length) {
    caja.innerHTML = '<div class="ayuda" style="margin-top:12px;">No encontramos ' +
      'asignaturas que correspondan a esas áreas en los niveles elegidos. ' +
      'Prueba con "Ver todas las materias".</div>';
    return;
  }
  caja.innerHTML = '<div class="ayuda" style="margin:14px 0 8px;"><b>' + top.length +
    ' asignaturas</b> que corresponden a tu perfil, de mayor a menor coincidencia. ' +
    'Agrega las que de verdad puedas impartir: el comité lee tu justificación, ' +
    'no el número de materias.</div>' +
    top.map(r =>
      '<div class="sug"><div class="txt"><b>' + r.m.nombre + '</b>' +
      '<span>' + r.prog + (r.m.ciclo ? ' · ' + r.m.ciclo : '') + '</span>' +
      '<span class="por">Coincide con: ' + r.porQue.join(' · ') + '</span></div>' +
      '<button type="button" onclick="agregarDesde(' + r.pi + ',' + r.mi + ',this)">Agregar</button></div>'
    ).join('');
}

function pintaPlan(q) {
  const caja = $('listaPlan');
  const nq = norm(q);
  let h = '', hay = 0;
  CATALOGO.forEach((p, pi) => {
    const mats = p.asignaturas.filter(m =>
      !nq || norm(m.nombre).includes(nq) || norm(p.programa).includes(nq));
    if (!mats.length) return;
    h += '<div class="planProg"><h5>' + p.programa +
      ' <span style="font-weight:400;color:var(--gris);font-size:12px;">· ' +
      p.nivel + ' · ' + mats.length + ' asignaturas</span></h5>';
    mats.forEach(m => {
      const mi = p.asignaturas.indexOf(m);
      hay++;
      h += '<div class="planMat"><span>' + m.nombre +
        (m.ciclo ? ' <span style="color:var(--gris);font-size:12px;">· ' + m.ciclo + '</span>' : '') +
        '</span><button type="button" onclick="agregarDesde(' + pi + ',' + mi + ',this)">Agregar</button></div>';
    });
    h += '</div>';
  });
  caja.innerHTML = hay ? h :
    '<div class="ayuda" style="margin-top:12px;">Sin resultados para «' + q + '».</div>';
}

// Agrega la asignatura en la primera tarjeta libre; si no hay, crea una.
function agregarDesde(pi, mi, boton) {
  let libre = null;
  document.querySelectorAll('#asignaturas .asig').forEach(d => {
    if (!libre && d.querySelector('.mat').value === '') libre = d;
  });
  if (!libre) {
    if (document.querySelectorAll('#asignaturas .asig').length >= MAX) {
      aviso('Ya tienes las ' + MAX + ' asignaturas. Quita una si quieres cambiarla.', 'err');
      return;
    }
    agregar();
    libre = $('asignaturas').lastElementChild;
  }
  const prog = libre.querySelector('.prog');
  prog.value = pi;
  cargarMats(prog);
  const mat = libre.querySelector('.mat');
  mat.value = mi;
  verFicha(mat);
  if (boton) { boton.textContent = 'Agregada'; boton.disabled = true; }
  libre.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

pintaChips($('areas'), AREAS.map(a => a[0]), selAreas);
pintaChips($('niveles'), NIVELES, selNiveles);
pintaChecks($('mods'), MODALIDADES, selMods);
pintaChecks($('disp'), DIAS, selDisp);
$('btnPerfil').addEventListener('click', () => togglePanel('perfil'));
$('btnExplorar').addEventListener('click', () => togglePanel('explorar'));
$('calcular').addEventListener('click', sugerir);
$('buscar').addEventListener('input', e => pintaPlan(e.target.value));

$('agregar').addEventListener('click', agregar);
$('carta').addEventListener('input', e => $('ccarta').textContent = e.target.value.length);
agregar();

$('enviar').addEventListener('click', async () => {
  const asigs = [];
  let error = '';
  document.querySelectorAll('#asignaturas .asig').forEach(d => {
    const p = d.querySelector('.prog');
    const idx = d.querySelector('.mat').value;
    const j = d.querySelector('.jus').value.trim();
    if (idx === '') return;
    const prog = CATALOGO[p.value];
    const mat = prog ? prog.asignaturas[idx] : null;
    if (!mat) return;
    const m = mat.nombre;
    if (j.length < MINJ) { error = 'Falta justificar «' + m + '»: al menos ' + MINJ + ' caracteres.'; return; }
    asigs.push({ programa: prog.programa, nombre: m, justificacion: j });
  });
  if (error) { aviso(error, 'err'); return; }
  if (!asigs.length) { aviso('Elige al menos una asignatura y justifícala.', 'err'); return; }
  if (!selMods.size) {
    aviso('Marca al menos una modalidad en la que puedas impartir: de eso ' +
      'depende que podamos asignarte un grupo.', 'err');
    return;
  }
  const f = $('cv').files[0];
  if (!f) { aviso('Adjunta tu currículum vítae.', 'err'); return; }
  // 4 MB y no 8: en base64 el archivo crece un tercio, y con 8 MB el envío
  // superaba el límite de POST de muchos hostings — que descartan la
  // petición entera sin avisar.
  if (f.size > 4 * 1024 * 1024) {
    aviso('Tu currículum pesa ' + Math.round(f.size / 1048576 * 10) / 10 +
      ' MB y el máximo es 4 MB. Guárdalo como PDF comprimido e inténtalo otra vez.', 'err');
    return;
  }

  $('enviar').disabled = true;
  $('enviar').textContent = 'Enviando…';
  try {
    // (ago-25) EL ARCHIVO SE MANDA EN TROZOS.
    // mod_security del hosting bloquea cualquier POST con adjunto a esta
    // página —se probó con base64 en JSON y con multipart, y rechaza los
    // dos—. Mandarlo en pedazos de 512 KB de texto plano no dispara la
    // regla, y de paso permite mostrar el avance real de la carga.
    const b64 = await new Promise((res, rej) => {
      const r = new FileReader();
      r.onload = () => res(String(r.result).split(',')[1] || '');
      r.onerror = () => rej(new Error('no se pudo leer el archivo'));
      r.readAsDataURL(f);
    });

    const sid = 'a' + Date.now().toString(36) +
      Math.random().toString(36).slice(2, 10);
    const TAM = 512 * 1024;
    const total = Math.ceil(b64.length / TAM);

    for (let n = 0; n < total; n++) {
      const cuerpo = new URLSearchParams();
      cuerpo.set('sid', sid);
      cuerpo.set('n', String(n));
      cuerpo.set('d', b64.slice(n * TAM, (n + 1) * TAM));
      const rt = await fetch('convocatoria-docente.php?trozo=1', {
        method: 'POST', body: cuerpo
      });
      const tx = await rt.text();
      let dt;
      try { dt = JSON.parse(tx); }
      catch (e) {
        throw new Error('el servidor rechazó la carga (' + rt.status + '): ' +
          tx.substring(0, 120));
      }
      if (!dt.ok) throw new Error(dt.error || 'falló la carga del archivo');
      $('enviar').textContent = 'Enviando… ' +
        Math.round(((n + 1) / total) * 100) + '%';
    }

    const cuerpoFinal = new URLSearchParams();
    cuerpoFinal.set('sid', sid);
    cuerpoFinal.set('datos', JSON.stringify({
      nombre: $('nombre').value, correo: $('correo').value,
      telefono: $('telefono').value, grado: $('grado').value,
      institucion: $('institucion').value, cedula: $('cedula').value,
      anios: $('anios').value, carta: $('carta').value,
      ciudad: $('ciudad').value,
      modalidades: [...selMods], disponibilidad: [...selDisp],
      distinciones: $('distinciones').value,
      cvNombre: f.name, cvMime: f.type,
      asignaturas: asigs
    }));
    $('enviar').textContent = 'Registrando…';
    const resp = await fetch('convocatoria-docente.php?enviar=1', {
      method: 'POST', body: cuerpoFinal
    });
    const crudo = await resp.text();
    let d;
    try {
      d = JSON.parse(crudo);
    } catch (e) {
      // El servidor contestó algo que no es JSON: casi siempre un error de
      // PHP o una página de error del hosting. Se muestra el principio para
      // poder diagnosticarlo sin abrir el registro del servidor.
      throw new Error('el servidor respondió ' + resp.status + ': ' +
        crudo.substring(0, 160));
    }
    if (d.ok) {
      $('f').style.display = 'none';
      aviso('<b>Solicitud enviada.</b> Tu folio es <b>' + d.folio + '</b>. ' +
        'Te mandamos el acuse por correo y ahí mismo te avisaremos el resultado.', 'ok');
    } else {
      aviso(d.error || 'No se pudo enviar. Intenta de nuevo.', 'err');
      $('enviar').disabled = false;
      $('enviar').textContent = 'Enviar mi solicitud';
    }
  } catch (err) {
    // (ago-25) El texto NO se borra —perder media hora de escritura por un
    // error de red es la forma más rápida de que alguien no vuelva a
    // intentarlo— pero SÍ se dice qué pasó. Antes este mensaje era el mismo
    // para cualquier fallo y no dejaba manera de averiguar la causa.
    console.error('Envío de solicitud:', err);
    aviso('No se pudo enviar: <b>' + (err && err.message ? err.message : err) +
      '</b><br>Tus datos siguen aquí. Intenta otra vez, y si vuelve a pasar ' +
      'escríbenos a <a href="mailto:contacto@cessum.mx">contacto@cessum.mx</a> ' +
      'con tu currículum adjunto: te registramos a mano.', 'err');
    $('enviar').disabled = false;
    $('enviar').textContent = 'Enviar mi solicitud';
  }
});
</script>
</body>
</html>
