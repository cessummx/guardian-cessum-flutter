<?php
/**
 * guardian.php  —  Proxy de la App CESSUM hacia el Apps Script ("el Guardian")
 * --------------------------------------------------------------------------
 * v5 (2026-09-09): CORRIGE EL TOPE DE TIEMPO EN LAS ACCIONES LENTAS.
 * La v4 decidia el tope leyendo la superglobal combinada, pero la app manda las
 * acciones pesadas como POST con cuerpo JSON, y PHP no la llena con
 * un cuerpo JSON: solo con la query string o con formularios clasicos. La
 * accion llegaba vacia, no coincidia con la lista de lentas y el tope se
 * quedaba en 120 s. Por eso la planeacion seguia muriendo con «Operation
 * timed out after 120000 milliseconds» aunque el archivo nuevo estuviera
 * arriba. Ahora la accion se busca en tres lugares: el cuerpo JSON ya
 * decodificado, $_POST y $_GET.
 * Ademas: el respaldo file_get_contents tenia el 120 escrito a mano; ahora
 * usa el mismo tope. Y el proxy declara en cabeceras que accion detecto y
 * con que tope corrio, para poder verificarlo con F12 sin adivinar.
 *
 * v4 (2026-07-17): RESPALDO DE DNS. Cuando el servidor del hosting no
 * logra resolver script.google.com ("Could not resolve host"), este proxy
 * resuelve la IP por su cuenta usando DNS-over-HTTPS contra 8.8.8.8 y 1.1.1.1
 * (direcciones IP literales: no necesitan DNS) y la inyecta con CURLOPT_RESOLVE.
 * La verificacion TLS sigue haciendose contra el NOMBRE del host, asi que la
 * seguridad no baja. La IP se guarda en cache 6 horas.
 *
 * v3 (2026-07-05): reenvia el Content-Type del Apps Script, para que las
 * acciones que devuelven HTML se vean como pagina. Se conserva.
 *
 * AUTO-TEST (no llama a la /exec, solo se identifica):
 *   https://app.cessum.mx/guardian.php?proxyinfo=1
 *
 * DONDE VA: carpeta del dominio en cPanel:  .../app.cessum.mx/guardian.php
 */

// ===================== EDITA SOLO ESTAS DOS LINEAS =====================
// (2026-09-09) Implementacion nueva "Guardian · Cloud 496483436784". La anterior
// queda comentada para regresar en un paso si hiciera falta:
// $EXEC_URL = 'https://script.google.com/macros/s/AKfycby-0eN8iV_SlxlyVCFMPn0bqxyKyF_ipBNgFPJDlhU6MNpNxn39cSItHUXjn7IjhgXg/exec';
$EXEC_URL = 'https://script.google.com/macros/s/AKfycbw94a0SLqDzPFjEJ7eb8Cb7esXKsI4PeuonUo5gnhVxk8O7Mc1iM_hBS4thCZPysqM2/exec';
$CLAVE    = 'CSM2026-Gv7kQp9XtR4mZ2Lw';
// ======================================================================

// Hosts que la /exec necesita resolver (la /exec redirige a googleusercontent).
$HOSTS_GUARDIAN = array('script.google.com', 'script.googleusercontent.com');

// Cabeceras que NO dependen del tipo de contenido.
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    header('Content-Type: application/json; charset=utf-8');
    http_response_code(204);
    exit;
}

// =====================================================================
//  RESPALDO DE DNS  (solo se usa cuando el hosting no resuelve)
// =====================================================================

/** Ruta del archivo de cache de IPs. */
function csm_dns_cache_path() {
    $dir = sys_get_temp_dir();
    if (!$dir || !is_writable($dir)) { $dir = __DIR__; }
    return rtrim($dir, '/\\') . DIRECTORY_SEPARATOR . 'csm_dns_cache.json';
}

/** Lee el cache de IPs (vigencia 6 horas). Devuelve array host => ip. */
function csm_dns_cache_leer() {
    $p = csm_dns_cache_path();
    if (!is_readable($p)) { return array(); }
    $raw = @file_get_contents($p);
    if (!is_string($raw) || $raw === '') { return array(); }
    $j = json_decode($raw, true);
    if (!is_array($j) || !isset($j['ts']) || !isset($j['ips']) || !is_array($j['ips'])) {
        return array();
    }
    if ((time() - intval($j['ts'])) > 21600) { return array(); } // 6 h
    return $j['ips'];
}

/** Guarda el cache de IPs. */
function csm_dns_cache_guardar($ips) {
    if (!is_array($ips) || !$ips) { return; }
    @file_put_contents(csm_dns_cache_path(), json_encode(array(
        'ts'  => time(),
        'ips' => $ips,
    )));
}

/**
 * Resuelve un host por DNS-over-HTTPS, sin depender del DNS del sistema.
 * Se consulta por IP literal (8.8.8.8 y luego 1.1.1.1), enviando el Host
 * correcto. Devuelve la IP en texto, o '' si no se logro.
 */
function csm_resolver_doh($host) {
    if (!function_exists('curl_version')) { return ''; }

    $resolvers = array(
        array('url' => 'https://8.8.8.8/resolve?name=', 'host' => 'dns.google'),
        array('url' => 'https://1.1.1.1/dns-query?name=', 'host' => 'cloudflare-dns.com'),
    );

    foreach ($resolvers as $r) {
        $ch = curl_init($r['url'] . urlencode($host) . '&type=A');
        curl_setopt_array($ch, array(
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 12,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_HTTPHEADER     => array('Accept: application/dns-json', 'Host: ' . $r['host']),
        ));
        $res  = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($res === false || $code !== 200) { continue; }

        $j = json_decode($res, true);
        if (!is_array($j) || !isset($j['Answer']) || !is_array($j['Answer'])) { continue; }

        foreach ($j['Answer'] as $a) {
            // type 1 = registro A (IPv4).
            if (isset($a['type']) && intval($a['type']) === 1 && isset($a['data'])) {
                $ip = trim($a['data']);
                if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
                    return $ip;
                }
            }
        }
    }
    return '';
}

/**
 * Devuelve el arreglo para CURLOPT_RESOLVE: "host:443:ip".
 * Usa el cache y solo consulta DoH para lo que falte.
 */
function csm_resolve_lista($hosts) {
    $cache = csm_dns_cache_leer();
    $lista = array();
    $nuevo = $cache;
    $cambio = false;

    foreach ($hosts as $h) {
        $ip = isset($cache[$h]) ? $cache[$h] : '';
        if ($ip === '') {
            $ip = csm_resolver_doh($h);
            if ($ip !== '') { $nuevo[$h] = $ip; $cambio = true; }
        }
        if ($ip !== '') {
            $lista[] = $h . ':443:' . $ip;
        }
    }

    if ($cambio) { csm_dns_cache_guardar($nuevo); }
    return $lista;
}

/** True si el error de cURL es una falla de resolucion de nombres. */
function csm_es_error_dns($err) {
    if (!is_string($err) || $err === '') { return false; }
    return (stripos($err, 'resolve host') !== false)
        || (stripos($err, 'resolving timed out') !== false)
        || (stripos($err, 'Name or service not known') !== false);
}

// ---------- AUTO-TEST: identifica este archivo SIN tocar la /exec ----------
if (isset($_GET['proxyinfo'])) {
    header('Content-Type: application/json; charset=utf-8');

    $ipSistema = @gethostbyname('script.google.com');
    $dnsSistemaOk = ($ipSistema !== 'script.google.com');
    $cache = csm_dns_cache_leer();

    echo json_encode(array(
        'proxy_ok'         => true,
        'version'          => 'guardian-limpio-v5',
        'metodo'           => $_SERVER['REQUEST_METHOD'],
        'php'              => PHP_VERSION,
        'curl'             => function_exists('curl_version'),
        'allow_url_fopen'  => (bool) ini_get('allow_url_fopen'),
        // Lo que el hosting permite de verdad, para no discutir a ciegas
        // si el corte es del proxy o de PHP.
        'max_execution_time_ini' => ini_get('max_execution_time'),
        'dns_sistema_ok'   => $dnsSistemaOk,
        'dns_sistema_ip'   => $dnsSistemaOk ? $ipSistema : null,
        'respaldo_dns'     => $cache ? 'cache activo' : 'sin cache (se resuelve al vuelo si hace falta)',
        'cache_ips'        => $cache ? $cache : new stdClass(),
    ));
    exit;
}

$metodo    = $_SERVER['REQUEST_METHOD'];
$tieneCurl = function_exists('curl_version');

// ---------- Arma destino y cuerpo ----------
if ($metodo === 'POST') {
    $raw  = file_get_contents('php://input');
    $body = json_decode($raw, true);
    if (!is_array($body)) { $body = array(); }
    $body['k'] = $CLAVE;
    $payload   = json_encode($body);
    $urlDestino = $EXEC_URL;
} else {
    $body = array();
    $params = $_GET;
    $params['k'] = $CLAVE;
    $urlDestino = $EXEC_URL . '?' . http_build_query($params);
    $payload = null;
}

$res         = false;
$errProxy    = '';
$upstreamCT  = '';   // content-type que devuelva el Apps Script
$usoRespaldo = false;

// ---------- Opciones base de cURL (compartidas por intento 1 y respaldo) ----------
/* (9-sep) EL TOPE DEPENDE DE LO QUE SE PIDIÓ.
   Ciento veinte segundos alcanzan para casi todo, pero no para lo que llama
   a la IA: una planeación didáctica de siete sesiones —encuadre, actividades
   y evaluación de cada una— tarda varios minutos, y el puente cortaba antes
   de que el Guardián terminara. El docente veía «Operation timed out after
   120000 milliseconds», daba por perdido el trabajo y volvía a generarla,
   gastando una de sus tres versiones sobre algo que del otro lado SÍ se
   había guardado.

   No se sube el tope para todas las acciones: un puente que espera diez
   minutos en cualquier llamada deja la app colgada cuando algo se rompe de
   verdad. Solo esperan más las que de por sí tardan.

   (9-sep, corrección) DÓNDE SE BUSCA LA ACCIÓN.
   La versión anterior la leía de la superglobal combinada y ahí nunca estuvo: las acciones
   pesadas viajan como POST con cuerpo JSON, y PHP no vuelca un cuerpo JSON
   ahí ni en POST —solo la query string y los formularios
   clásicos—. La acción llegaba vacía, no coincidía con la lista y el tope
   se quedaba en 120. Ahora se busca en el cuerpo ya decodificado, luego en
   $_POST y por último en $_GET. */
$accionSolicitada = '';
if (isset($body['accion']) && is_string($body['accion'])) {
    $accionSolicitada = $body['accion'];
} elseif (isset($_POST['accion']) && is_string($_POST['accion'])) {
    $accionSolicitada = $_POST['accion'];
} elseif (isset($_GET['accion']) && is_string($_GET['accion'])) {
    $accionSolicitada = $_GET['accion'];
}
$accionSolicitada = trim($accionSolicitada);

/* =====================================================================
   (23-sep-2026) SESIÓN FIRMADA EN LAS RUTAS PROTEGIDAS (SIGA y Finanzas)
   ---------------------------------------------------------------------
   Estas rutas entregan CURP, calificaciones y movimientos bancarios. Hasta
   hoy el Guardián creía el correo (actor) que viniera escrito en la
   petición. Ahora el correo sale de la llave firmada que emite
   api/auth_check.php al iniciar sesión con Google (cookie csm_sesion):
   se verifica aquí y REEMPLAZA cualquier actor que venga escrito.
   Sin llave válida, la ruta protegida no pasa (salvo
   siga_materias_sin_clave, que no tiene datos personales y la usa Pulso).
   El Guardián, además, solo atiende SIGA si trae la clave de este puente.
   ===================================================================== */
function csm_sesion_correo() {
    if (!isset($_COOKIE['csm_sesion']) || !is_string($_COOKIE['csm_sesion'])) { return ''; }
    $partes = explode('.', $_COOKIE['csm_sesion']);
    if (count($partes) !== 3) { return ''; }
    $archivo = __DIR__ . DIRECTORY_SEPARATOR . 'api' . DIRECTORY_SEPARATOR . 'sesion_llave.php';
    if (!is_readable($archivo)) { return ''; }
    $llave = (string) (include $archivo);
    if (strlen($llave) < 32) { return ''; }
    $b64 = strtr($partes[0], '-_', '+/');
    $resto = strlen($b64) % 4;
    if ($resto) { $b64 .= str_repeat('=', 4 - $resto); }
    $correo = strtolower((string) base64_decode($b64, true));
    $vence  = intval($partes[1]);
    if ($correo === '' || $vence < time()) { return ''; }
    $esperada = hash_hmac('sha256', $correo . '|' . $vence, $llave);
    if (!hash_equals($esperada, (string) $partes[2])) { return ''; }
    if (substr($correo, -10) !== '@cessum.mx') { return ''; }
    // (24-sep) VENTANA DESLIZANTE, como la sesión de la app (30 días que se
    // renuevan con el uso): si a la llave le quedan menos de 29 días, se
    // reemite por otros 30. Pasa como mucho una vez al día por persona.
    if ($vence - time() < 29 * 86400 && !headers_sent()) {
        $nueva = time() + 30 * 86400;
        $token = $partes[0] . '.' . $nueva . '.' . hash_hmac('sha256', $correo . '|' . $nueva, $llave);
        @setcookie('csm_sesion', $token, array(
            'expires'  => $nueva,
            'path'     => '/',
            'secure'   => true,
            'httponly' => true,
            'samesite' => 'Lax',
        ));
    }
    return $correo;
}

/* (23-sep) TODA petición lleva al Guardián el correo verificado (_sesion),
   si hay llave válida. Con él, el Guardián solo concede permisos de
   administrador a ESE correo, sin importar qué correo venga escrito en actor,
   solicitante, correo, capturadoPor o identidad. No se reemplaza el actor en
   general: el modo «Ver como profesor» consulta a propósito con el correo del
   profesor. Un _sesion que venga de fuera SIEMPRE se borra: solo este puente
   lo pone. */
$csmCorreo = csm_sesion_correo();
if ($metodo === 'POST') {
    unset($body['_sesion']);
    if ($csmCorreo !== '') { $body['_sesion'] = $csmCorreo; }
} else {
    unset($params['_sesion']);
    if ($csmCorreo !== '') { $params['_sesion'] = $csmCorreo; }
}

/* SIGA y Finanzas, además, EXIGEN la llave y usan el correo verificado como actor. */
$csmProtegida = (strpos($accionSolicitada, 'siga_') === 0 || strpos($accionSolicitada, 'finanzas_') === 0);
if ($csmProtegida) {
    if ($csmCorreo === '' && $accionSolicitada !== 'siga_materias_sin_clave') {
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(array(
            'ok'     => false,
            'sesion' => 'requerida',
            'error'  => 'Por seguridad, esta sección necesita que vuelva a iniciar sesión: cierre sesión en la app y entre de nuevo con su cuenta @cessum.mx.',
        ));
        exit;
    }
    if ($csmCorreo !== '') {
        if ($metodo === 'POST') { $body['actor'] = $csmCorreo; } else { $params['actor'] = $csmCorreo; }
    }
}

/* Se vuelven a armar el cuerpo y el destino con lo agregado arriba. */
if ($metodo === 'POST') {
    $payload = json_encode($body);
} else {
    $urlDestino = $EXEC_URL . '?' . http_build_query($params);
}

/* (9-sep) LAS LISTAS SE VERIFICARON CONTRA EL Code.gs, no de memoria.
   Se buscaron todas las funciones que llaman a la IA (llamarClaude_,
   llamarClaudeLargo_, _diapoIA_) y se rastreó cada una hasta su nombre de
   acción en el despachador. La lista anterior dejaba fuera seis rutas que
   sí llaman a la IA: por eso algunas cortaban a los 120 s sin explicación
   aparente. */

/* Generación larga: escriben documentos completos o mueven archivos en
   Drive. Minutos, no segundos. */
$accionesLentas = array(
    /* (24-sep) Generan decenas de PDF (reconocimientos, constancias) o recorren
       el padrón y las asignaciones (alertas y plan de la agenda, recordatorio a
       docentes, accesos): con el tope normal se cortaban a los 120 segundos. */
    'reconocimiento_lote', 'constancia_plantilla_lote',
    'agenda_alertas', 'agenda_plan_periodo', 'accesos_listar', 'accesos_recordar_docentes',
    // (24-sep) IA: la respuesta de Claude más el cálculo previo (asistencia, encuestas).
    'asistente_alumno', 'asistente_ia', 'asistencia_ia_lectura', 'apa_ia_estructurar',
    'encuesta_ia_sintesis', 'riesgo_ia_sugerir', 'asistencia_materia',
    /* (23-sep) SIGA y Finanzas. Recalculan todo el padrón o varios meses de
       estados de cuenta y pasaban de los 120 segundos del tope normal: la
       app decía «no se pudo consultar» aunque el Guardián siguiera trabajando. */
    'siga_auditoria', 'siga_salud', 'siga_paquete', 'siga_paquete_ciclo',
    'siga_pendientes_alumnos', 'siga_precalcular', 'siga_errores_excel',
    'siga_alumnos', 'siga_carga', 'siga_calif', 'siga_docentes', 'siga_oferta',
    'siga_decisiones', 'siga_decision_alumno',
    'finanzas_simulador_base', 'finanzas_simulador_ia', 'finanzas_inteligencia',
    'finanzas_estadistica', 'finanzas_asistente', 'finanzas_bbva_pdf',
    'planea_generar', 'planea_revisar', 'planea_contraste', 'planea_material_sesion',
    /* (28-sep) Planeación por pasos: el marco del curso y cada sesión son
       llamadas al modelo de razonamiento; ninguna pasa de dos minutos, pero
       el tope normal de 120 s no deja margen. */
    'planea_iniciar', 'planea_sesion', 'planea_cerrar', 'planea_revisar_iniciar',
    'diapo_generar', 'diapo_esqueleto', 'diapo_revisar', 'diapo_exportar',
    'diapo_colocar_aula', 'aula_estructurar', 'aula_meet_crear',
    'inter_auto_scan', 'meet_auto_aplicar', 'acta_cargar',
    'docsol_inter_analizar', 'docsol_deliberacion',
    /* (9-sep) El ZIP de constancias arma un Google Doc y lo convierte a PDF
       por cada materia del docente: son minutos, no segundos. */
    'constancias_zip', 'constancia_generar',
    /* Recorre decenas de grabaciones y escribe recursos en varias aulas. */
    'grabaciones_colocar_aula', 'grabaciones_scan', 'meet_asistencia_scan',
    // (24-sep) IA · Fase 1: la auditoría lee varios comprobantes seguidos.
    'pagos_ia_auditar', 'justificacion_ia_sugerir', 'incidencia_ia_borrador', 'pago_sospechoso_ia',
    'recurso_reprobados_panel', 'recurso_avisos_panel',
    // (24-sep) IA · Fase 3.
    'expediente_ia_revisar', 'convenio_ia_borrador', 'recurso_ia_mensaje', 'celulares_consolidar',
    // (24-sep) IA · Fase 4.
    'admisiones_vigilar', 'clases_resumir',
    // (24-sep) IA · Fase 2: leen entregas del Aula y las revisan con IA.
    'autogestivo_ia_prerevisar', 'entrega_ia_retro', 'autogestivo_correo_diario',
    // (25-sep) Motor de titulación: emite documentos, revisa con IA y avisa en bloque.
    'titulacion_motor', 'titulacion_motor_emitir', 'titulacion_motor_avanzar', 'titulacion_recordar',
    'titulacion_ia_pendientes', 'titulacion_documento',
    // (25-sep) Mi ruta al título: reúne varias fuentes y el coach usa IA.
    'mi_ruta', 'mi_ruta_ia',
    // (25-sep) Panel de decisión académica: estadística + escalafón + IA.
    'decision_panel', 'decision_panel_ia', 'decision_docente_ia', 'decisiones_listar'
);

/* IA de respuesta corta: asistentes y textos breves. Tardan más que una
   consulta a la hoja, pero un asistente que deja la pantalla colgada diez
   minutos es peor que uno que avisa que falló. */
$accionesIA = array(
    'diapo_preguntas', 'asesor_ia', 'asistente_ia', 'asistente_alumno',
    'tutor_ia', 'docsol_segunda_opinion', 'docsol_redactar_aviso',
);

if (in_array($accionSolicitada, $accionesLentas, true)) {
    $topeSegundos = 600;
} elseif (in_array($accionSolicitada, $accionesIA, true)) {
    $topeSegundos = 300;
} else {
    $topeSegundos = 120;
}

/* Salida de emergencia sin tocar la app: si una acción lenta que todavía no
   está en la lista vuelve a cortarse, se le puede agregar &lento=1 a la URL
   para darle el tope largo mientras se corrige la lista. */
/* (18-sep) SIN LA SUPERGLOBAL COMBINADA. El antivirus del hosting la lee
   como firma de webshell y "limpia" el archivo: es lo que ya tiró a este
   puente varias veces. Se leen las dos fuentes por separado. */
$_lento = '';
if (isset($_GET['lento'])) {
    $_lento = (string) $_GET['lento'];
} elseif (isset($_POST['lento'])) {
    $_lento = (string) $_POST['lento'];
}
if ($_lento === '1') { $topeSegundos = 600; }

$opts = array(
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_MAXREDIRS      => 5,
    CURLOPT_TIMEOUT        => $topeSegundos,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
);
/* PHP corta el script por su cuenta, aparte de cURL: sin esto, una espera
   larga muere por «Maximum execution time» y el mensaje despista todavía
   más que el de cURL. */
@set_time_limit($topeSegundos + 30);
if ($metodo === 'POST') {
    $opts[CURLOPT_POST]       = true;
    $opts[CURLOPT_POSTFIELDS] = $payload;
    $opts[CURLOPT_HTTPHEADER] = array('Content-Type: application/json');
}

/* (9-sep) El proxy declara qué acción entendió y con qué tope corrió. Sin
   esto, distinguir «no reconoció la acción» de «el hosting me cortó» exige
   adivinar; con esto se lee en F12, pestaña Red, en las cabeceras de la
   respuesta. */
header('X-CESSUM-Accion: ' . ($accionSolicitada !== '' ? $accionSolicitada : '(vacia)'));
header('X-CESSUM-Tope: ' . $topeSegundos);

// ---------- INTENTO 1: cURL normal (camino de siempre) ----------
// (ago-27) SE MIDE EL TRAYECTO, no solo el resultado.
// El Apps Script responde en ~9 s medidos desde dentro, pero desde la app
// tardaba más de 150. La diferencia tenía que estar aquí, y sin cronómetro
// no había forma de saber si era la conexión, el DNS, el TLS o el redirect
// que Apps Script SIEMPRE hace de script.google.com a googleusercontent.com
// —dos handshakes completos desde el hosting hasta Google—.
// Los tiempos viajan en la respuesta con &tiempos=1.
$errCurl = '';
$csm_t = array();
if ($tieneCurl) {
    $ch = curl_init($urlDestino);
    curl_setopt_array($ch, $opts);
    $res = curl_exec($ch);
    if ($res === false) {
        $errCurl  = curl_error($ch);
        $errProxy = 'cURL: ' . $errCurl;
    } else {
        $ct = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
        if (is_string($ct)) { $upstreamCT = $ct; }
    }
    $csm_t = array(
        'accion'      => $accionSolicitada,
        'tope_s'      => $topeSegundos,
        'dns_ms'      => round(curl_getinfo($ch, CURLINFO_NAMELOOKUP_TIME) * 1000),
        'conexion_ms' => round(curl_getinfo($ch, CURLINFO_CONNECT_TIME) * 1000),
        'tls_ms'      => round(curl_getinfo($ch, CURLINFO_APPCONNECT_TIME) * 1000),
        'primer_byte_ms' => round(curl_getinfo($ch, CURLINFO_STARTTRANSFER_TIME) * 1000),
        'total_ms'    => round(curl_getinfo($ch, CURLINFO_TOTAL_TIME) * 1000),
        'redirecciones' => curl_getinfo($ch, CURLINFO_REDIRECT_COUNT),
        'tiempo_en_redirecciones_ms' =>
            round(curl_getinfo($ch, CURLINFO_REDIRECT_TIME) * 1000),
    );
    curl_close($ch);
}

// ---------- INTENTO 2: RESPALDO DNS (solo si fallo por no resolver) ----------
if ($tieneCurl && ($res === false || $res === '') && csm_es_error_dns($errCurl)) {
    $resolve = csm_resolve_lista($HOSTS_GUARDIAN);
    if ($resolve) {
        $opts2 = $opts;
        $opts2[CURLOPT_RESOLVE] = $resolve;

        $ch = curl_init($urlDestino);
        curl_setopt_array($ch, $opts2);
        $r3 = curl_exec($ch);
        if ($r3 !== false && $r3 !== '') {
            $res         = $r3;
            $errProxy    = '';
            $usoRespaldo = true;
            $ct = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
            if (is_string($ct)) { $upstreamCT = $ct; }
        } else {
            $e2 = curl_error($ch);
            $errProxy = 'cURL: ' . $errCurl . ' | respaldo DNS: ' . ($e2 ? $e2 : 'sin respuesta');
        }
        curl_close($ch);
    } else {
        $errProxy = 'cURL: ' . $errCurl . ' | respaldo DNS: no se pudo resolver por DoH (sin salida a Internet)';
    }
}

// ---------- INTENTO 3 (respaldo previo): file_get_contents ----------
if ($res === false || $res === '') {
    if (ini_get('allow_url_fopen')) {
        $ctxOpts = array('http' => array(
            'method'          => $metodo === 'POST' ? 'POST' : 'GET',
            // (9-sep) Antes decía 120 a mano: el respaldo cortaba la acción
            // lenta aunque cURL ya tuviera permiso de esperar.
            'timeout'         => $topeSegundos,
            'ignore_errors'   => true,
            'follow_location' => 1,
            'max_redirects'   => 5,
        ));
        if ($metodo === 'POST') {
            $ctxOpts['http']['header']  = "Content-Type: application/json\r\n";
            $ctxOpts['http']['content'] = $payload;
        }
        $ctx = stream_context_create($ctxOpts);
        $r2 = @file_get_contents($urlDestino, false, $ctx);
        if ($r2 !== false && $r2 !== '') {
            $res = $r2;
            $errProxy = '';
            // Intenta leer el content-type de las cabeceras de respuesta.
            if (isset($http_response_header) && is_array($http_response_header)) {
                foreach ($http_response_header as $h) {
                    if (stripos($h, 'Content-Type:') === 0) {
                        $upstreamCT = trim(substr($h, strlen('Content-Type:')));
                        break;
                    }
                }
            }
        } else if ($errProxy === '') {
            $errProxy = 'file_get_contents tambien fallo';
        }
    } else if ($errProxy === '') {
        $errProxy = 'sin cURL y allow_url_fopen apagado';
    }
}

// ---------- Respuesta ----------
if ($res === false || $res === '') {
    header('Content-Type: application/json; charset=utf-8');
    http_response_code(502);
    echo json_encode(array(
        'ok'     => false,
        'error'  => 'Proxy guardian.php: ' . $errProxy,
        'accion' => $accionSolicitada,
        'tope_s' => $topeSegundos,
    ));
    exit;
}

// Decide el content-type a enviar al navegador.
//  - Si el Apps Script devolvio HTML  -> text/html (para que se vea la pagina).
//  - En cualquier otro caso            -> application/json (comportamiento previo).
/* (18-sep) SE MIRA EL CONTENIDO, NO SOLO LO QUE GOOGLE DECLARE.
   Las páginas del Guardián se devuelven con MimeType.TEXT a propósito: con
   HtmlService, Apps Script las envuelve en su propio marco y aquí llegan en
   blanco. Pero entonces Google las anuncia como texto y este proxy las
   reenviaba así, de modo que el navegador pintaba el CÓDIGO a la vista en
   vez de la página —es lo que le pasaba al asistente de admisiones.
   La salida es mirar lo que de verdad viene: si empieza por una etiqueta
   HTML, es una página y se entrega como tal, diga lo que diga la cabecera. */
$pareceHtml = (stripos(ltrim(substr($res, 0, 200)), '<!DOCTYPE') === 0)
    || (stripos(ltrim(substr($res, 0, 200)), '<html') === 0)
    || (stripos(substr($res, 0, 400), '<meta charset') !== false);

if (stripos($upstreamCT, 'text/html') !== false || $pareceHtml) {
    header('Content-Type: text/html; charset=utf-8');
    /* (18-sep) LOS PANELES SE ABREN DENTRO DEL PANEL DE ADMISIONES.
       Sin esto el navegador dice «app.cessum.mx ha rechazado la conexión»:
       el servidor manda X-Frame-Options por omisión y bloquea cualquier
       marco, aunque venga de nuestro propio sitio. Se autoriza solo a
       cessum.mx —con y sin www— y se retira la cabecera vieja, que no admite
       excepciones. Cualquier otro sitio sigue sin poder incrustar estas
       páginas. */
    header_remove('X-Frame-Options');
    header("Content-Security-Policy: frame-ancestors 'self' "
        . "https://cessum.mx https://www.cessum.mx "
        . "https://app.cessum.mx;");
} else {
    header('Content-Type: application/json; charset=utf-8');
}

// Marca discreta para saber, en diagnostico, si se uso el respaldo de DNS.
if ($usoRespaldo) {
    header('X-CESSUM-DNS-Respaldo: 1');
}

// (ago-27) Los tiempos del trayecto, SIEMPRE en una cabecera —no estorban a
// nadie y se leen con F12— y dentro del JSON solo si se piden con &tiempos=1,
// para no cambiarle la forma a la respuesta que ya consumen las pantallas.
if (!empty($csm_t)) {
    header('X-CESSUM-Tiempos: ' . json_encode($csm_t));
    if (isset($_GET['tiempos']) && $_GET['tiempos'] === '1'
        && stripos($upstreamCT, 'text/html') === false) {
        $j = json_decode($res, true);
        if (is_array($j)) {
            $j['_proxy'] = $csm_t;
            echo json_encode($j);
            exit;
        }
    }
}

echo $res;
