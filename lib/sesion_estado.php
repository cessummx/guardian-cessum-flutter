<?php
/**
 * sesion_estado.php — ¿Este navegador tiene llave de sesión firmada válida?
 * ---------------------------------------------------------------------
 * (24-sep-2026) La sesión local de la app dura 30 días y se renueva con el
 * uso, así que quien entró ANTES de que existiera la llave firmada nunca
 * vuelve a pasar por Google y nunca la recibe. La app pregunta aquí al
 * arrancar: si la respuesta es firmada=false, le pide a la persona entrar
 * con Google UNA vez, y desde ahí la llave se renueva sola.
 *
 * No cambia nada: solo lee y verifica la cookie csm_sesion con la llave de
 * api/sesion_llave.php (la misma verificación que hace guardian.php).
 *
 * DÓNDE VA: .../app.cessum.mx/api/sesion_estado.php
 *   (queda en https://app.cessum.mx/api/sesion_estado.php)
 */
header('Access-Control-Allow-Origin: https://app.cessum.mx');
header('Vary: Origin');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

$firmada = false;
$correo = '';
try {
    if (isset($_COOKIE['csm_sesion']) && is_string($_COOKIE['csm_sesion'])) {
        $partes = explode('.', $_COOKIE['csm_sesion']);
        $archivo = __DIR__ . DIRECTORY_SEPARATOR . 'sesion_llave.php';
        if (count($partes) === 3 && is_readable($archivo)) {
            $llave = (string) (include $archivo);
            if (strlen($llave) >= 32) {
                $b64 = strtr($partes[0], '-_', '+/');
                $resto = strlen($b64) % 4;
                if ($resto) { $b64 .= str_repeat('=', 4 - $resto); }
                $c = strtolower((string) base64_decode($b64, true));
                $vence = intval($partes[1]);
                $esperada = hash_hmac('sha256', $c . '|' . $vence, $llave);
                if ($c !== '' && $vence >= time() && hash_equals($esperada, (string) $partes[2])
                    && substr($c, -10) === '@cessum.mx') {
                    $firmada = true;
                    $correo = $c;
                }
            }
        }
    }
} catch (Throwable $e) {
    $firmada = false;
}

echo json_encode(['firmada' => $firmada, 'correo' => $correo]);
