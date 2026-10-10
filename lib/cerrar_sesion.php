<?php
/**
 * cerrar_sesion.php — Cierra la llave de sesión firmada de la app CESSUM
 * ---------------------------------------------------------------------
 * (24-sep-2026) Al iniciar sesión con Google, api/auth_check.php deja la
 * cookie «csm_sesion» (correo verificado + vencimiento de 12 horas + firma).
 * Cerrar sesión en la app borraba solo la sesión local: la cookie seguía
 * valiendo hasta 12 horas, y en una computadora compartida quien llegara
 * después conservaba los permisos del administrador anterior.
 * Este archivo la expira. La app lo llama al pulsar «Cerrar sesión».
 *
 * DÓNDE VA: en la misma carpeta que auth_check.php
 *   .../app.cessum.mx/api/cerrar_sesion.php
 *   (queda en https://app.cessum.mx/api/cerrar_sesion.php)
 *
 * Solo acepta POST: un enlace o una imagen no pueden cerrarle la sesión a nadie.
 */
$ALLOWED_ORIGIN = 'https://app.cessum.mx';

header('Access-Control-Allow-Origin: ' . $ALLOWED_ORIGIN);
header('Vary: Origin');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'reason' => 'Método no permitido']);
    exit;
}

// Mismos atributos con los que se creó (path, secure, httponly, samesite):
// si no coinciden, el navegador no la reemplaza.
$ok = setcookie('csm_sesion', '', array(
    'expires'  => time() - 3600,
    'path'     => '/',
    'secure'   => true,
    'httponly' => true,
    'samesite' => 'Lax',
));

echo json_encode(['ok' => (bool) $ok]);
