<?php
/**
 * banner.php · CESSUM · Aula CESSUM
 * ---------------------------------------------------------------
 * Compone los BANNERS SEMANALES en el servidor, con el mismo diseño que
 * el generador de la app: cintillo guinda con corte diagonal, chevron
 * oscuro a la izquierda, franja clara, y el texto en Montserrat sobre
 * el área blanca.
 *
 * Existe porque el generador de la app dibuja el banner en el navegador
 * del docente y lo descarga a su computadora: eso no sirve para poner el
 * encabezado de cada sección al CREAR el aula, que ocurre del lado del
 * Guardián. Mismo caso y misma solución que portada.php.
 *
 * Uso:
 *   banner.php?clave=...&texto=Semana%201.%20Del%207%20al%2013%20de%20septiembre&formato=base64
 *   banner.php?clave=...&texto=Bienvenida&bienvenida=1        (PNG directo)
 *   banner.php?diag=1                                          (qué encuentra)
 *
 * Requiere Montserrat-Bold.ttf en la misma carpeta (el mismo archivo que
 * ya usa portada.php).
 */

$CLAVE = 'REEMPLAZAR_CON_CLAVE_PUENTE';   // debe coincidir con CLAVE_PUENTE del Guardián

$W = 2000; $H = 480;                       // proporción del generador de la app
$ROJO      = [0xB1, 0x1D, 0x29];
$ROJO_OSC  = [0x8E, 0x12, 0x1C];
$ROJO_CLA  = [0xD9, 0x3A, 0x47];
$FUENTE    = __DIR__ . '/Montserrat-Bold.ttf';

if (isset($_GET['diag'])) {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'ok' => true,
        'gd' => function_exists('imagecreatetruecolor'),
        'freetype' => function_exists('imagettftext'),
        'fuente' => file_exists($FUENTE) ? 'encontrada' : 'FALTA Montserrat-Bold.ttf',
        'carpeta' => __DIR__,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

if (($_GET['clave'] ?? '') !== $CLAVE) {
    http_response_code(403);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => false, 'error' => 'Clave incorrecta.']);
    exit;
}

$texto      = trim((string)($_GET['texto'] ?? ''));
$bienvenida = ($_GET['bienvenida'] ?? '') === '1';
$formato    = (string)($_GET['formato'] ?? 'png');

if ($texto === '') {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => false, 'error' => 'Falta el texto del banner.']);
    exit;
}
if (!file_exists($FUENTE)) {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => false, 'error' => 'Falta Montserrat-Bold.ttf junto a banner.php.']);
    exit;
}

$im = imagecreatetruecolor($W, $H);
imagealphablending($im, true);
$blanco = imagecolorallocate($im, 255, 255, 255);
imagefilledrectangle($im, 0, 0, $W, $H, $blanco);

$cRojo = imagecolorallocate($im, $ROJO[0], $ROJO[1], $ROJO[2]);
$cOsc  = imagecolorallocate($im, $ROJO_OSC[0], $ROJO_OSC[1], $ROJO_OSC[2]);
$cCla  = imagecolorallocate($im, $ROJO_CLA[0], $ROJO_CLA[1], $ROJO_CLA[2]);
$negro = imagecolorallocate($im, 0, 0, 0);

/* Las mismas proporciones del _BannerFondoPainter de la app. */
imagefilledpolygon($im, [
    0, 0,  $W, 0,  $W, (int)($H * 0.30),  0, (int)($H * 0.44),
], 4, $cRojo);

imagefilledpolygon($im, [
    (int)($W * 0.30), (int)($H * 0.40),
    $W,               (int)($H * 0.26),
    $W,               (int)($H * 0.36),
    (int)($W * 0.32), (int)($H * 0.50),
], 4, $cCla);

imagefilledpolygon($im, [
    0, 0,  (int)($W * 0.27), 0,  (int)($W * 0.135), (int)($H * 0.66),
], 3, $cOsc);

/* Texto centrado en el área blanca, con ajuste automático: los rangos de
   fecha largos («Del 28 de septiembre al 4 de octubre de 2026») no caben a
   tamaño fijo, y cortarlos sería peor que reducirlos. */
$tam   = $bienvenida ? 122 : 60;
$izq   = 130; $der = 130;
$anchoUtil = $W - $izq - $der;
$topArea   = (int)($H * 0.47);

do {
    $bb = imagettfbbox($tam, 0, $FUENTE, $texto);
    $ancho = abs($bb[4] - $bb[0]);
    if ($ancho <= $anchoUtil || $tam <= 26) break;
    $tam -= 2;
} while (true);

$bb = imagettfbbox($tam, 0, $FUENTE, $texto);
$ancho = abs($bb[4] - $bb[0]);
$alto  = abs($bb[5] - $bb[1]);
$x = (int)(($W - $ancho) / 2);
$y = (int)($topArea + (($H - $topArea) + $alto) / 2) - 10;

imagettftext($im, $tam, 0, $x, $y, $negro, $FUENTE, $texto);

if ($formato === 'base64') {
    ob_start(); imagepng($im); $bin = ob_get_clean();
    imagedestroy($im);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => true, 'base64' => base64_encode($bin),
        'ancho' => $W, 'alto' => $H, 'tamTexto' => $tam], JSON_UNESCAPED_UNICODE);
    exit;
}

header('Content-Type: image/png');
imagepng($im);
imagedestroy($im);
