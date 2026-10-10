<?php
/**
 * auth_check.php  —  Portón de acceso de la app web CESSUM
 * ---------------------------------------------------------
 * v2 (2026-07-17): AGREGA RESPALDO DE DNS. Cuando el servidor del hosting no
 * logra resolver oauth2.googleapis.com ("Could not resolve host"), este script
 * resuelve la IP por su cuenta usando DNS-over-HTTPS contra 8.8.8.8 y 1.1.1.1
 * (direcciones IP literales: no necesitan DNS) y la inyecta con CURLOPT_RESOLVE.
 * La verificación TLS sigue haciéndose contra el NOMBRE del host, así que la
 * seguridad NO baja: un atacante que devolviera una IP falsa no podría
 * presentar un certificado válido para oauth2.googleapis.com.
 *
 * El camino normal es IDÉNTICO al original: el respaldo sólo entra si la
 * resolución normal falla. Si el DNS del hosting funciona, nada cambia.
 * Todas las validaciones de seguridad se conservan intactas.
 *
 * Verifica el inicio de sesión con Google y autoriza ÚNICAMENTE
 * a correos del dominio institucional @cessum.mx.
 *
 * DÓNDE VA ESTE ARCHIVO:
 *   En tu cPanel, dentro de la carpeta del subdominio de la app:
 *   .../app.cessum.mx/api/auth_check.php
 *   (queda accesible en https://app.cessum.mx/api/auth_check.php)
 *
 * REQUISITOS DEL HOSTING (Neubox los cumple): PHP 7.4+ y la extensión cURL.
 *
 * SEGURIDAD: este script es el único juez real del acceso. Aunque alguien
 * manipule el navegador, sin un token válido de Google emitido para ESTA app
 * y con correo @cessum.mx verificado, la respuesta será "authorized: false".
 */

// =====================================================================
//  CONFIGURACIÓN  —  EDITA SOLO ESTAS DOS LÍNEAS
// =====================================================================
$CLIENT_ID         = '496483436784-e7ueiqi3216tlgnenar5fncc8q42vtvh.apps.googleusercontent.com';
$DOMINIO_PERMITIDO = 'cessum.mx';

// Origen permitido (la dirección de tu app). Cámbialo si usas otro subdominio.
$ALLOWED_ORIGIN = 'https://app.cessum.mx';
// =====================================================================


// ---- Cabeceras CORS y de respuesta ----
header('Access-Control-Allow-Origin: ' . $ALLOWED_ORIGIN);
header('Vary: Origin');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Content-Type: application/json; charset=utf-8');

// Respuesta a la verificación previa del navegador (preflight)
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['authorized' => false, 'reason' => 'Método no permitido']);
    exit;
}

// =====================================================================
//  RESPALDO DE DNS  (sólo se usa cuando el hosting no resuelve)
// =====================================================================

/** Ruta del archivo de caché de IPs. */
function csm_dns_cache_path() {
    $dir = sys_get_temp_dir();
    if (!$dir || !is_writable($dir)) { $dir = __DIR__; }
    return rtrim($dir, '/\\') . DIRECTORY_SEPARATOR . 'csm_dns_cache.json';
}

/** Lee la caché de IPs (vigencia 6 horas). Devuelve array host => ip. */
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

/** Guarda la caché de IPs, conservando lo que ya hubiera. */
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
 * correcto. Devuelve la IP en texto, o '' si no se logró.
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
            CURLOPT_TIMEOUT        => 8,
            CURLOPT_CONNECTTIMEOUT => 5,
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

/** Devuelve el arreglo para CURLOPT_RESOLVE: "host:443:ip". Usa caché. */
function csm_resolve_lista($hosts) {
    $cache  = csm_dns_cache_leer();
    $lista  = array();
    $nuevo  = $cache;
    $cambio = false;

    foreach ($hosts as $h) {
        $ip = isset($cache[$h]) ? $cache[$h] : '';
        if ($ip === '') {
            $ip = csm_resolver_doh($h);
            if ($ip !== '') { $nuevo[$h] = $ip; $cambio = true; }
        }
        if ($ip !== '') { $lista[] = $h . ':443:' . $ip; }
    }

    if ($cambio) { csm_dns_cache_guardar($nuevo); }
    return $lista;
}

/** True si el error de cURL es una falla de resolución de nombres. */
function csm_es_error_dns($err) {
    if (!is_string($err) || $err === '') { return false; }
    return (stripos($err, 'resolve host') !== false)
        || (stripos($err, 'resolving timed out') !== false)
        || (stripos($err, 'Name or service not known') !== false);
}

// ---- Leer el id_token enviado por la app (acepta JSON o formulario) ----
$raw  = file_get_contents('php://input');
$body = json_decode($raw, true);
$idToken = '';
if (is_array($body) && isset($body['id_token'])) {
    $idToken = $body['id_token'];
} elseif (isset($_POST['id_token'])) {
    $idToken = $_POST['id_token'];
}

if (!$idToken) {
    echo json_encode(['authorized' => false, 'reason' => 'Falta el token']);
    exit;
}

// ---- Validar el token directamente con Google ----
// Google nos devuelve los datos firmados del usuario (a quién pertenece,
// para qué app se emitió, si el correo está verificado, el dominio, etc.).
$url = 'https://oauth2.googleapis.com/tokeninfo?id_token=' . urlencode($idToken);

$optsBase = array(
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT        => 10,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
);

// ---- INTENTO 1: cURL normal (camino de siempre) ----
$ch = curl_init($url);
curl_setopt_array($ch, $optsBase);
$res  = curl_exec($ch);
$http = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$err  = curl_error($ch);
curl_close($ch);

// ---- INTENTO 2: RESPALDO DNS (sólo si falló por no resolver el nombre) ----
if (($res === false || $http !== 200) && csm_es_error_dns($err)) {
    $resolve = csm_resolve_lista(array('oauth2.googleapis.com'));
    if ($resolve) {
        $opts2 = $optsBase;
        $opts2[CURLOPT_RESOLVE] = $resolve;

        $ch = curl_init($url);
        curl_setopt_array($ch, $opts2);
        $res  = curl_exec($ch);
        $http = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err  = curl_error($ch);
        curl_close($ch);
    }
}

if ($res === false || $http !== 200) {
    echo json_encode(['authorized' => false, 'reason' => 'No se pudo validar con Google']);
    exit;
}

$claims = json_decode($res, true);
if (!is_array($claims)) {
    echo json_encode(['authorized' => false, 'reason' => 'Respuesta inválida de Google']);
    exit;
}

// ---- Datos firmados que entrega Google ----
$aud           = isset($claims['aud'])  ? $claims['aud']  : '';
$email         = isset($claims['email']) ? strtolower($claims['email']) : '';
$hd            = isset($claims['hd'])    ? strtolower($claims['hd'])     : '';
$exp           = isset($claims['exp'])   ? intval($claims['exp'])        : 0;
$name          = isset($claims['name'])  ? $claims['name']               : '';
$picture       = isset($claims['picture']) ? $claims['picture']          : '';
$ev            = isset($claims['email_verified']) ? $claims['email_verified'] : 'false';
$emailVerified = ($ev === true || $ev === 'true' || $ev === 1 || $ev === '1');

// =====================================================================
//  VALIDACIONES DE SEGURIDAD (todas deben cumplirse)
// =====================================================================

// 1) El token debe haber sido emitido para NUESTRA app (anti-suplantación).
if ($aud !== $CLIENT_ID) {
    echo json_encode(['authorized' => false, 'reason' => 'Token de otra aplicación']);
    exit;
}

// 2) El token no debe estar vencido.
if ($exp < time()) {
    echo json_encode(['authorized' => false, 'reason' => 'La sesión expiró, vuelve a entrar']);
    exit;
}

// 3) El correo debe estar verificado por Google.
if (!$emailVerified) {
    echo json_encode(['authorized' => false, 'reason' => 'Tu correo no está verificado']);
    exit;
}

// 4) Debe ser una cuenta del dominio institucional.
//    Se exige por dos vías: el dominio "hd" de Google Workspace y el sufijo del correo.
$sufijo        = '@' . $DOMINIO_PERMITIDO;
$emailDominioOk = (substr($email, -strlen($sufijo)) === $sufijo);
$hdOk           = ($hd === $DOMINIO_PERMITIDO);

if (!$emailDominioOk || !$hdOk) {
    echo json_encode([
        'authorized' => false,
        'reason'     => 'Debes ingresar con tu correo institucional ' . $sufijo,
    ]);
    exit;
}

// =====================================================================
//  (23-sep-2026) LLAVE DE SESIÓN FIRMADA
// ---------------------------------------------------------------------
//  Hasta hoy la app solo guardaba el correo, y el Guardián creía el correo
//  que viniera en cada petición: quien conociera el de un administrador
//  podía hacerse pasar por él. Ahora, con el acceso ya verificado arriba por
//  Google, se emite una llave: correo + vencimiento + firma HMAC-SHA256. Va
//  en una cookie HttpOnly (JavaScript no la puede leer ni fabricar) que el
//  navegador manda sola a guardian.php, mismo dominio. guardian.php la
//  verifica y pone el correo VERIFICADO en las rutas protegidas.
//
//  La llave secreta la genera el servidor la primera vez, en
//  api/sesion_llave.php (un PHP que no imprime nada si alguien lo abre).
//  Nunca pasa por el chat ni por la app.
//
//  SI ALGO DE ESTO FALLA, EL ACCESO NO SE ROMPE: la persona entra igual y
//  solo las rutas protegidas le pedirán volver a iniciar sesión.
// =====================================================================
$sesionFirmada = false;
try {
    $archivoLlave = __DIR__ . DIRECTORY_SEPARATOR . 'sesion_llave.php';
    $llave = '';
    if (is_readable($archivoLlave)) {
        $llave = (string) (include $archivoLlave);
    }
    if (strlen($llave) < 32 && function_exists('random_bytes')) {
        $nueva = bin2hex(random_bytes(32));
        $contenido = "<?php\n// Llave de las sesiones firmadas de la app CESSUM. Generada por auth_check.php.\n"
                   . "// NO la comparta ni la copie a otro lado. Si se borra, se genera otra y todos vuelven a iniciar sesión.\n"
                   . "return '" . $nueva . "';\n";
        if (@file_put_contents($archivoLlave, $contenido, LOCK_EX) !== false) {
            @chmod($archivoLlave, 0600);
            $llave = $nueva;
        }
    }
    if (strlen($llave) >= 32) {
        // (24-sep) 30 días, como la sesión que guarda la app (que además se renueva
        // con el uso). guardian.php renueva también esta llave con el uso, una vez
        // al día. Con 12 horas, la app seguía dentro pero la llave vencía cada día.
        $vence = time() + 30 * 86400;
        $correoB64 = rtrim(strtr(base64_encode($email), '+/', '-_'), '=');
        $firma = hash_hmac('sha256', $email . '|' . $vence, $llave);
        $token = $correoB64 . '.' . $vence . '.' . $firma;
        $sesionFirmada = setcookie('csm_sesion', $token, array(
            'expires'  => $vence,
            'path'     => '/',
            'secure'   => true,
            'httponly' => true,
            'samesite' => 'Lax',
        ));
    }
} catch (Throwable $eLlave) {
    $sesionFirmada = false;
}

// =====================================================================
//  ACCESO AUTORIZADO
// =====================================================================
echo json_encode([
    'authorized' => true,
    'email'      => $email,
    'name'       => $name,
    'picture'    => $picture,
    'sesionFirmada' => $sesionFirmada,
]);
