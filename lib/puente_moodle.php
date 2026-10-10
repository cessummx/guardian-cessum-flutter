<?php
/**
 * puente_moodle.php  —  Puente de lectura entre Moodle (aula.cessum.mx) y
 * el Guardián de Aula CESSUM.
 * ---------------------------------------------------------------------------
 * QUÉ HACE: expone, en formato JSON y protegido por una clave, información
 * útil de Moodle (cursos, inscripciones, calificaciones, actividad, tareas,
 * progreso) para que el Guardián la cruce con los datos de la app por correo
 * institucional. LEE Y TAMBIÉN ESCRIBE (matricular, suspender, crear cursos, y desde el
 * 4-oct-2026 las operaciones del Centro de aulas). Toda escritura exige confirmar=1.
 *
 * DÓNDE VA: en la MISMA carpeta donde vive tu Moodle (la raíz, donde está
 * "config.php" y donde ya está "conexiones.php"). Queda accesible en:
 *   https://aula.cessum.mx/puente_moodle.php
 *
 * CÓMO PROBARLO (una vez subido): abre en el navegador:
 *   https://aula.cessum.mx/puente_moodle.php?clave=CSM2026-Gv7kQp9XtR4mZ2Lw&accion=ping
 * Si ves un JSON con la versión de Moodle y conteos, ¡conectó!
 *
 * SEGURIDAD: exige la clave compartida con el Guardián. Sin ella responde
 * "acceso denegado". No reemplaza ni toca conexiones.php.
 *
 * COMPATIBILIDAD: usa el acceso a base de datos propio de Moodle ($DB) con
 * los marcadores {tabla}, por lo que funciona con cualquier prefijo de tablas
 * y en Moodle 3.5 a 4.x sin configurar credenciales.
 */

// ===== CONFIGURACIÓN (solo esta línea) =====
$CLAVE = 'CSM2026-Gv7kQp9XtR4mZ2Lw';
// ===========================================

// No queremos que Moodle haga ningún login ni redirección al cargar.
define('NO_MOODLE_COOKIES', true);
define('NO_UPGRADE_CHECK', true);

// Arranque de Moodle (carga $CFG y $DB sin pedir credenciales).
require(__DIR__ . '/config.php');

@error_reporting(0);
@ini_set('display_errors', '0');

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

function salir_($obj) {
    echo json_encode($obj);
    exit;
}

// --- Validación de la clave ---
$clave = isset($_GET['clave']) ? $_GET['clave'] : (isset($_POST['clave']) ? $_POST['clave'] : '');
if ((string)$clave !== (string)$CLAVE) {
    http_response_code(403);
    salir_(array('ok' => false, 'error' => 'Acceso denegado'));
}

$accion = isset($_GET['accion']) ? $_GET['accion'] : 'ping';
$email  = isset($_GET['email']) ? strtolower(trim($_GET['email'])) : '';
$dias   = isset($_GET['dias']) ? intval($_GET['dias']) : 30;
if ($dias < 1) { $dias = 30; }
if ($dias > 365) { $dias = 365; }

global $DB, $CFG;

// (3-oct-2026) El detalle de una excepción de Moodle: no solo el mensaje («Error escribiendo a la base de datos») sino lo que explica
// POR QUÉ —el debuginfo trae el SQL y el error real del motor—, el código y dónde ocurrió.
function detalle_excepcion_($e) {
    $o = array('clase' => get_class($e), 'mensaje' => $e->getMessage(),
        'linea' => $e->getLine(), 'archivo' => basename($e->getFile()));
    if (isset($e->errorcode) && $e->errorcode) { $o['codigo'] = (string)$e->errorcode; }
    if (isset($e->debuginfo) && $e->debuginfo) { $o['detalle'] = substr((string)$e->debuginfo, 0, 1500); }
    $traza = array();
    foreach (array_slice($e->getTrace(), 0, 6) as $f) {
        $traza[] = (isset($f['file']) ? basename($f['file']) : '?') . ':' . (isset($f['line']) ? $f['line'] : '?') .
            ' ' . (isset($f['function']) ? $f['function'] : '');
    }
    $o['traza'] = $traza;
    return $o;
}

// Ayudante: ejecuta una consulta y regresa arreglo plano de objetos->arrays.
function filas_($sql, $params = array()) {
    global $DB;
    $rs = $DB->get_records_sql($sql, $params);
    $out = array();
    foreach ($rs as $r) { $out[] = (array)$r; }
    return $out;
}

try {

    // =====================================================================
    //  PING — versión de Moodle y conteos rápidos (para probar conexión)
    // =====================================================================
    if ($accion === 'ping') {
        $nUsuarios = $DB->count_records_sql(
            "SELECT COUNT(*) FROM {user} WHERE deleted = 0 AND id > 2");
        $nCursos = $DB->count_records_sql(
            "SELECT COUNT(*) FROM {course} WHERE id > 1");
        salir_(array(
            'ok' => true,
            'moodle' => isset($CFG->release) ? $CFG->release : '',
            'version' => isset($CFG->version) ? $CFG->version : '',
            'wwwroot' => isset($CFG->wwwroot) ? $CFG->wwwroot : '',
            'hora' => date('d/m/Y H:i:s'),
            'usuarios' => (int)$nUsuarios,
            'cursos' => (int)$nCursos
        ));
    }

    // =====================================================================
    //  USUARIOS — todos, con última conexión (compatible con el semáforo)
    //  Devuelve también 'diasSinConexion' y 'ultimaConexion' como conexiones.php
    // =====================================================================
    if ($accion === 'usuarios') {
        $rows = filas_(
            "SELECT id, username, email, firstname, lastname,
                    lastaccess, lastlogin, suspended
             FROM {user}
             WHERE deleted = 0 AND id > 2
             ORDER BY lastname, firstname");
        $ahora = time();
        $usuarios = array();
        foreach ($rows as $u) {
            $la = (int)$u['lastaccess'];
            $diasSin = $la > 0 ? (int)floor(($ahora - $la) / 86400) : 99999;
            $usuarios[] = array(
                'correo' => strtolower($u['email']),
                'nombre' => trim($u['firstname'] . ' ' . $u['lastname']),
                'username' => $u['username'],
                'suspendido' => ((int)$u['suspended'] === 1),
                'ultimaConexion' => $la > 0 ? date('d/m/Y H:i', $la) : '',
                'diasSinConexion' => $diasSin
            );
        }
        salir_(array('ok' => true, 'usuarios' => $usuarios,
            'total' => count($usuarios)));
    }

    // =====================================================================
    //  CURSOS — id, nombre, categoría, visible, inscritos
    // =====================================================================
    if ($accion === 'cursos') {
        $rows = filas_(
            "SELECT c.id, c.shortname, c.fullname, c.visible, c.startdate, c.timecreated,
                    cat.name AS categoria,
                    (SELECT COUNT(DISTINCT ue.userid)
                       FROM {user_enrolments} ue
                       JOIN {enrol} e ON e.id = ue.enrolid
                      WHERE e.courseid = c.id AND ue.status = 0) AS inscritos
             FROM {course} c
             LEFT JOIN {course_categories} cat ON cat.id = c.category
             WHERE c.id > 1
             ORDER BY c.fullname");
        $cursos = array();
        foreach ($rows as $c) {
            $cursos[] = array(
                'id' => (int)$c['id'],
                'shortname' => $c['shortname'],
                'nombre' => $c['fullname'],
                'categoria' => isset($c['categoria']) ? $c['categoria'] : '',
                'visible' => ((int)$c['visible'] === 1),
                'inscritos' => (int)$c['inscritos'],
                // (4-oct-2026, Centro de aulas M3) fechas para detectar aulas recientes sin asignación
                'inicio' => !empty($c['startdate']) ? date('Y-m-d', (int)$c['startdate']) : '',
                'creado' => !empty($c['timecreated']) ? date('Y-m-d', (int)$c['timecreated']) : ''
            );
        }
        salir_(array('ok' => true, 'cursos' => $cursos,
            'total' => count($cursos)));
    }

    // =====================================================================
    //  (5-oct-2026) COMPLETITUD DE CURSOS — solo lectura. Para sugerir el curso más completo al asignar un recursamiento.
    //  GET cursos_completitud&ids=12,34,56 (hasta 20) → por curso: tareas, cuestionarios, foros, materiales, otras
    //  actividades visibles, secciones con contenido, y la fecha de su última modificación.
    // =====================================================================
    if ($accion === 'cursos_completitud') {
        $ids = array_values(array_filter(array_map('intval', explode(',', (string)(isset($_GET['ids']) ? $_GET['ids'] : '')))));
        $ids = array_slice(array_unique($ids), 0, 20);
        if (!count($ids)) { salir_(array('ok' => false, 'error' => 'Faltan los ids de los cursos.')); }
        list($in, $par) = $DB->get_in_or_equal($ids);
        $out = array();
        foreach ($ids as $id) { $out[$id] = array('id' => $id, 'tareas' => 0, 'cuestionarios' => 0, 'foros' => 0, 'materiales' => 0, 'otras' => 0, 'secciones' => 0, 'modificado' => ''); }
        $mods = $DB->get_recordset_sql("SELECT cm.id, cm.course, m.name FROM {course_modules} cm JOIN {modules} m ON m.id = cm.module
             WHERE cm.course $in AND cm.visible = 1 AND cm.deletioninprogress = 0", $par);
        $MAT = array('resource' => 1, 'page' => 1, 'url' => 1, 'folder' => 1, 'book' => 1, 'imscp' => 1);
        foreach ($mods as $r) {
            $c = (int)$r->course; if (!isset($out[$c])) { continue; }
            if ($r->name === 'assign') { $out[$c]['tareas']++; }
            else if ($r->name === 'quiz') { $out[$c]['cuestionarios']++; }
            else if ($r->name === 'forum') { $out[$c]['foros']++; }
            else if (isset($MAT[$r->name])) { $out[$c]['materiales']++; }
            else if ($r->name !== 'label') { $out[$c]['otras']++; }
        }
        $mods->close();
        $secs = $DB->get_recordset_sql("SELECT id, course, sequence FROM {course_sections} WHERE course $in AND section > 0", $par);
        foreach ($secs as $s) { $c = (int)$s->course; if (isset($out[$c]) && trim((string)$s->sequence) !== '') { $out[$c]['secciones']++; } }
        $secs->close();
        foreach ($DB->get_records_sql("SELECT id, timemodified FROM {course} WHERE id $in", $par) as $c) {
            if (isset($out[(int)$c->id]) && !empty($c->timemodified)) { $out[(int)$c->id]['modificado'] = date('Y-m-d', (int)$c->timemodified); }
        }
        salir_(array('ok' => true, 'cursos' => array_values($out)));
    }

    // =====================================================================
    //  INSCRIPCIONES — cursos de un usuario (por email) con último acceso
    //  al curso y su calificación final (total del curso).
    // =====================================================================
    if ($accion === 'inscripciones') {
        if (!$email) { salir_(array('ok' => false, 'error' => 'Falta email.')); }
        $u = $DB->get_record('user', array('email' => $email, 'deleted' => 0));
        if (!$u) {
            salir_(array('ok' => true, 'encontrado' => false,
                'inscripciones' => array()));
        }
        $rows = filas_(
            "SELECT c.id AS courseid, c.fullname, c.shortname,
                    la.timeaccess AS ultimoacceso,
                    gg.finalgrade AS calif, gi.grademax AS califmax
             FROM {user_enrolments} ue
             JOIN {enrol} e ON e.id = ue.enrolid
             JOIN {course} c ON c.id = e.courseid
             LEFT JOIN {user_lastaccess} la
                    ON la.userid = ue.userid AND la.courseid = c.id
             LEFT JOIN {grade_items} gi
                    ON gi.courseid = c.id AND gi.itemtype = 'course'
             LEFT JOIN {grade_grades} gg
                    ON gg.itemid = gi.id AND gg.userid = ue.userid
             WHERE ue.userid = ? AND ue.status = 0 AND c.id > 1
             ORDER BY c.fullname",
            array($u->id));
        $insc = array();
        foreach ($rows as $r) {
            $ta = (int)$r['ultimoacceso'];
            $calif = ($r['calif'] === null || $r['calif'] === '') ? null
                     : round((float)$r['calif'], 2);
            $insc[] = array(
                'courseid' => (int)$r['courseid'],
                'curso' => $r['fullname'],
                'shortname' => $r['shortname'],
                'ultimoAcceso' => $ta > 0 ? date('d/m/Y H:i', $ta) : '',
                'diasSinEntrar' => $ta > 0 ? (int)floor((time() - $ta) / 86400) : null,
                'calificacion' => $calif,
                'calificacionMax' => $r['califmax'] !== null ? round((float)$r['califmax'], 1) : null
            );
        }
        salir_(array('ok' => true, 'encontrado' => true,
            'nombre' => trim($u->firstname . ' ' . $u->lastname),
            'inscripciones' => $insc));
    }

    // =====================================================================
    //  ACTIVIDAD — eventos en los últimos N días de un usuario (engagement)
    // =====================================================================
    if ($accion === 'actividad') {
        if (!$email) { salir_(array('ok' => false, 'error' => 'Falta email.')); }
        $u = $DB->get_record('user', array('email' => $email, 'deleted' => 0));
        if (!$u) { salir_(array('ok' => true, 'encontrado' => false)); }
        $desde = time() - ($dias * 86400);
        $eventos = 0; $ultimo = 0;
        try {
            $eventos = (int)$DB->count_records_sql(
                "SELECT COUNT(*) FROM {logstore_standard_log}
                 WHERE userid = ? AND timecreated >= ?",
                array($u->id, $desde));
            $ultimo = (int)$DB->get_field_sql(
                "SELECT MAX(timecreated) FROM {logstore_standard_log}
                 WHERE userid = ?", array($u->id));
        } catch (Exception $eL) { /* logstore puede no estar disponible */ }
        salir_(array('ok' => true, 'encontrado' => true,
            'dias' => $dias, 'eventos' => $eventos,
            'ultimoEvento' => $ultimo > 0 ? date('d/m/Y H:i', $ultimo) : ''));
    }

    // =====================================================================
    //  PROGRESO — % de actividades con seguimiento de finalización
    //  completadas por el usuario, por curso.
    // =====================================================================

    // =====================================================================
    //  (16-ago-2026) DE DÓNDE SALIÓ MI CALIFICACIÓN.
    //  `progreso` recorre TODOS los cursos del Aula y solo cuenta actividades
    //  completadas: ni las notas ni los comentarios del docente. Con eso no se
    //  puede explicarle a un alumno cómo se formó su calificación, que es de
    //  donde nace casi toda inconformidad.
    //  Esto devuelve, solo de los cursos donde el alumno ESTÁ INSCRITO, cada
    //  tarea con su nota, el comentario del docente y si entregó.
    //    ?accion=alumno_actividades&email=...[&curso=ID]
    // =====================================================================
    if ($accion === 'alumno_actividades') {
        if (!$email) { salir_(array('ok' => false, 'error' => 'Falta email.')); }
        $u = $DB->get_record('user', array('email' => $email, 'deleted' => 0));
        if (!$u) {
            salir_(array('ok' => true, 'encontrado' => false, 'cursos' => array()));
        }
        $filtroCurso = isset($_GET['curso']) ? intval($_GET['curso']) : 0;

        // Cursos donde está inscrito y activo. Sin esto se devolvería el
        // catálogo entero, que es lo que hacía inservible la consulta.
        $sqlCursos = "SELECT DISTINCT c.id, c.fullname, c.shortname
                        FROM {course} c
                        JOIN {context} ctx ON ctx.instanceid = c.id AND ctx.contextlevel = 50
                        JOIN {role_assignments} ra ON ra.contextid = ctx.id
                        JOIN {user_enrolments} ue ON ue.userid = ra.userid
                        JOIN {enrol} e ON e.id = ue.enrolid AND e.courseid = c.id
                       WHERE ra.userid = ? AND ue.status = 0 AND c.visible = 1";
        $params = array($u->id);
        if ($filtroCurso) { $sqlCursos .= " AND c.id = ?"; $params[] = $filtroCurso; }
        $cursos = filas_($sqlCursos, $params);

        $salida = array();
        foreach ($cursos as $c) {
            $cid = (int)$c['id'];

            // Tareas del curso con la entrega y la calificación de ESTE alumno.
            $acts = array();
            try {
                $acts = filas_(
                    "SELECT a.id AS k, a.name, a.duedate, a.grade AS sobre,
                            sub.status AS entrega, sub.timemodified AS entregado,
                            g.grade AS nota, g.timemodified AS calificado,
                            g.grader AS quien
                       FROM {assign} a
                  LEFT JOIN {assign_submission} sub
                         ON sub.assignment = a.id AND sub.userid = ?
                        AND sub.latest = 1
                  LEFT JOIN {assign_grades} g
                         ON g.assignment = a.id AND g.userid = ?
                        AND g.attemptnumber = (SELECT MAX(g2.attemptnumber)
                                                 FROM {assign_grades} g2
                                                WHERE g2.assignment = a.id
                                                  AND g2.userid = ?)
                      WHERE a.course = ?
                      ORDER BY a.duedate ASC, a.id ASC",
                    array($u->id, $u->id, $u->id, $cid));
            } catch (Exception $eA) { $acts = array(); }

            $lista = array();
            foreach ($acts as $a) {
                // El comentario del docente vive en otra tabla y puede no
                // existir: se busca aparte para que su ausencia no tumbe la
                // consulta entera.
                $retro = '';
                try {
                    $c2 = $DB->get_record_sql(
                        "SELECT afc.commenttext
                           FROM {assignfeedback_comments} afc
                           JOIN {assign_grades} g ON g.id = afc.grade
                          WHERE g.assignment = ? AND g.userid = ?
                          ORDER BY g.timemodified DESC LIMIT 1",
                        array((int)$a['id'], $u->id));
                    if ($c2 && isset($c2->commenttext)) {
                        $retro = trim(strip_tags($c2->commenttext));
                    }
                } catch (Exception $eC) { $retro = ''; }

                $nota = ($a['nota'] === null || $a['nota'] < 0) ? null : round((float)$a['nota'], 2);
                $lista[] = array(
                    'actividad' => $a['name'],
                    'calificacion' => $nota,
                    'sobre' => (float)$a['sobre'],
                    'entregado' => ($a['entrega'] === 'submitted'),
                    'fechaEntrega' => $a['entregado'] ? (int)$a['entregado'] : 0,
                    'cierre' => (int)$a['duedate'],
                    'calificado' => $a['calificado'] ? (int)$a['calificado'] : 0,
                    'retro' => $retro
                );
            }

            $salida[] = array(
                'courseid' => $cid,
                'curso' => $c['fullname'],
                'clave' => $c['shortname'],
                'actividades' => $lista
            );
        }
        salir_(array('ok' => true, 'encontrado' => true,
            'alumno' => $u->firstname . ' ' . $u->lastname,
            'cursos' => $salida));
    }

    if ($accion === 'progreso') {
        if (!$email) { salir_(array('ok' => false, 'error' => 'Falta email.')); }
        $u = $DB->get_record('user', array('email' => $email, 'deleted' => 0));
        if (!$u) { salir_(array('ok' => true, 'encontrado' => false,
            'progreso' => array())); }
        // total de actividades con completion por curso
        $tot = array();
        foreach (filas_(
            "SELECT cm.course, COUNT(*) AS total
               FROM {course_modules} cm
              WHERE cm.completion > 0 AND cm.deletioninprogress = 0
              GROUP BY cm.course") as $t) {
            $tot[(int)$t['course']] = (int)$t['total'];
        }
        // completadas por el usuario por curso
        $hechas = array();
        try {
            foreach (filas_(
                "SELECT cm.course, COUNT(*) AS hechas
                   FROM {course_modules_completion} cmc
                   JOIN {course_modules} cm ON cm.id = cmc.coursemoduleid
                  WHERE cmc.userid = ? AND cmc.completionstate > 0
                  GROUP BY cm.course", array($u->id)) as $h) {
                $hechas[(int)$h['course']] = (int)$h['hechas'];
            }
        } catch (Exception $eP) { /* sin completion */ }
        $prog = array();
        foreach ($tot as $cid => $total) {
            if ($total <= 0) { continue; }
            $he = isset($hechas[$cid]) ? $hechas[$cid] : 0;
            $nombre = $DB->get_field('course', 'fullname', array('id' => $cid));
            $prog[] = array(
                'courseid' => $cid,
                'curso' => $nombre ? $nombre : ('Curso ' . $cid),
                'total' => $total, 'completadas' => $he,
                'porcentaje' => (int)round($he / $total * 100)
            );
        }
        salir_(array('ok' => true, 'encontrado' => true, 'progreso' => $prog));
    }

    // =====================================================================
    //  TAREAS — assign de los cursos del usuario, con fecha límite y si
    //  el alumno ya entregó.
    // =====================================================================
    if ($accion === 'tareas') {
        if (!$email) { salir_(array('ok' => false, 'error' => 'Falta email.')); }
        $u = $DB->get_record('user', array('email' => $email, 'deleted' => 0));
        if (!$u) { salir_(array('ok' => true, 'encontrado' => false,
            'tareas' => array())); }
        $rows = array();
        try {
            $rows = filas_(
                "SELECT a.id, a.name, a.duedate, c.fullname AS curso,
                        (SELECT s.status FROM {assign_submission} s
                          WHERE s.assignment = a.id AND s.userid = ?
                            AND s.latest = 1 LIMIT 1) AS estado
                 FROM {assign} a
                 JOIN {course} c ON c.id = a.course
                 JOIN {course_modules} cm ON cm.instance = a.id
                 JOIN {modules} md ON md.id = cm.module AND md.name = 'assign'
                 WHERE a.course IN (
                       SELECT e.courseid FROM {user_enrolments} ue
                       JOIN {enrol} e ON e.id = ue.enrolid
                       WHERE ue.userid = ? AND ue.status = 0)
                   AND cm.deletioninprogress = 0
                   AND cm.visible = 1
                 ORDER BY a.duedate DESC",
                array($u->id, $u->id));
        } catch (Exception $eT) { /* módulo assign ausente */ }
        $tareas = array();
        foreach ($rows as $t) {
            $dd = (int)$t['duedate'];
            $entregado = ($t['estado'] === 'submitted');
            $tareas[] = array(
                'curso' => $t['curso'],
                'tarea' => $t['name'],
                'fechaLimite' => $dd > 0 ? date('d/m/Y H:i', $dd) : '',
                'vencida' => ($dd > 0 && $dd < time() && !$entregado),
                'entregado' => $entregado
            );
        }
        salir_(array('ok' => true, 'encontrado' => true, 'tareas' => $tareas));
    }

    // =====================================================================
    //  PANORAMA — por curso: inscritos, activos (entraron en N días),
    //  inactivos y promedio de calificación del curso. Para el tablero admin.
    // =====================================================================
    if ($accion === 'panorama') {
        $desde = time() - ($dias * 86400);
        $rows = filas_(
            "SELECT c.id, c.fullname,
                    (SELECT COUNT(DISTINCT ue.userid)
                       FROM {user_enrolments} ue
                       JOIN {enrol} e ON e.id = ue.enrolid
                      WHERE e.courseid = c.id AND ue.status = 0) AS inscritos,
                    (SELECT COUNT(*) FROM {user_lastaccess} la
                      WHERE la.courseid = c.id AND la.timeaccess >= ?) AS activos
             FROM {course} c
             WHERE c.id > 1
             ORDER BY c.fullname",
            array($desde));
        $cursos = array();
        $totInscritos = 0; $totActivos = 0;
        foreach ($rows as $c) {
            $cid = (int)$c['id'];
            $insc = (int)$c['inscritos'];
            $act = (int)$c['activos'];
            // promedio de calificación del curso
            $prom = null;
            try {
                $p = $DB->get_field_sql(
                    "SELECT AVG(gg.finalgrade)
                       FROM {grade_items} gi
                       JOIN {grade_grades} gg ON gg.itemid = gi.id
                      WHERE gi.courseid = ? AND gi.itemtype = 'course'
                        AND gg.finalgrade IS NOT NULL",
                    array($cid));
                if ($p !== null && $p !== false) { $prom = round((float)$p, 1); }
            } catch (Exception $eG) {}
            $totInscritos += $insc; $totActivos += $act;
            $cursos[] = array(
                'courseid' => $cid,
                'curso' => $c['fullname'],
                'inscritos' => $insc,
                'activos' => $act,
                'inactivos' => max(0, $insc - $act),
                'promedio' => $prom
            );
        }
        salir_(array('ok' => true, 'dias' => $dias, 'cursos' => $cursos,
            'resumen' => array(
                'cursos' => count($cursos),
                'inscritos' => $totInscritos,
                'activos' => $totActivos)));
    }

    // =====================================================================
    //  SUSPENDER / REACTIVAR (escritura) — cambia el estado de la cuenta de
    //  un usuario en el Aula. Reversible. Usa la API oficial de Moodle
    //  (user_update_user), no toca las tablas directamente.
    //  Requiere ademas del clave: confirmar=1.
    // =====================================================================
    if ($accion === 'suspender' || $accion === 'reactivar') {
        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        if ((string)$confirmar !== '1') {
            salir_(array('ok' => false, 'error' => 'Falta confirmacion (confirmar=1).'));
        }
        if (!$email) { salir_(array('ok' => false, 'error' => 'Falta email.')); }
        $u = $DB->get_record('user', array('email' => $email, 'deleted' => 0));
        if (!$u) {
            salir_(array('ok' => false,
                'error' => 'No existe un usuario con ese correo en el Aula.'));
        }
        // No tocar cuentas de administrador por seguridad.
        if (function_exists('is_siteadmin') && is_siteadmin($u->id)) {
            salir_(array('ok' => false,
                'error' => 'No se permite modificar una cuenta de administrador.'));
        }
        $nuevoEstado = ($accion === 'suspender') ? 1 : 0;
        if ((int)$u->suspended === $nuevoEstado) {
            salir_(array('ok' => true, 'sinCambio' => true,
                'email' => $email, 'suspendido' => ($nuevoEstado === 1)));
        }
        require_once($CFG->dirroot . '/user/lib.php');
        $u->suspended = $nuevoEstado;
        user_update_user($u, false, true);
        salir_(array('ok' => true, 'accion' => $accion, 'email' => $email,
            'suspendido' => ($nuevoEstado === 1)));
    }

    // =====================================================================
    //  CATEGORIAS (lectura) — para saber en que categoria crear las Aulas.
    // =====================================================================
    if ($accion === 'categorias') {
        $cats = filas_("SELECT id, name, parent, coursecount
                        FROM {course_categories} WHERE visible = 1 ORDER BY sortorder ASC");
        salir_(array('ok' => true, 'categorias' => $cats));
    }

    // =====================================================================
    //  CREAR CURSO (escritura) — crea un Aula en Moodle. Idempotente por
    //  shortname: si ya existe un curso con ese shortname, lo devuelve y no
    //  duplica. Usa la API oficial create_course().
    //  Requiere: confirmar=1, fullname. Opcional: shortname, categoryid.
    // =====================================================================
    if ($accion === 'crear_curso') {
        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        if ((string)$confirmar !== '1') {
            salir_(array('ok' => false, 'error' => 'Falta confirmacion (confirmar=1).'));
        }
        $fullname = isset($_GET['fullname']) ? trim($_GET['fullname'])
            : (isset($_POST['fullname']) ? trim($_POST['fullname']) : '');
        $shortname = isset($_GET['shortname']) ? trim($_GET['shortname'])
            : (isset($_POST['shortname']) ? trim($_POST['shortname']) : '');
        $categoryid = isset($_GET['categoryid']) ? intval($_GET['categoryid'])
            : (isset($_POST['categoryid']) ? intval($_POST['categoryid']) : 0);
        if ($fullname === '') { salir_(array('ok' => false, 'error' => 'Falta fullname.')); }
        if ($shortname === '') {
            $shortname = substr(preg_replace('/\s+/', '_', $fullname), 0, 90);
        }
        // Idempotente: si ya existe un curso con ese shortname, se devuelve.
        $exist = $DB->get_record('course', array('shortname' => $shortname));
        if ($exist) {
            salir_(array('ok' => true, 'yaExistia' => true, 'courseid' => (int)$exist->id,
                'shortname' => $shortname,
                'url' => $CFG->wwwroot . '/course/view.php?id=' . $exist->id));
        }
        if ($categoryid <= 0) {
            $cats = $DB->get_records_sql(
                "SELECT id FROM {course_categories} WHERE visible = 1 ORDER BY sortorder ASC",
                null, 0, 1);
            if (!empty($cats)) { $first = reset($cats); $categoryid = (int)$first->id; }
            else { $categoryid = 1; }
        }
        require_once($CFG->dirroot . '/course/lib.php');
        $data = new stdClass();
        $data->fullname  = $fullname;
        $data->shortname = $shortname;
        $data->category  = $categoryid;
        $data->visible   = 1;
        $data->format    = 'topics';
        $course = create_course($data);
        salir_(array('ok' => true, 'courseid' => (int)$course->id, 'shortname' => $shortname,
            'categoryid' => $categoryid,
            'url' => $CFG->wwwroot . '/course/view.php?id=' . $course->id));
    }

    // =====================================================================
    //  MATRICULAR (escritura) — inscribe a un usuario (por email) en un curso
    //  (por courseid o shortname) con rol de estudiante, via matriculacion
    //  MANUAL. Crea la instancia manual si el curso no la tiene. Idempotente.
    //  Requiere: confirmar=1, email, y (courseid o shortname).
    // =====================================================================
    // =====================================================================
    //  CURSO_BORRAR (escritura, 3-oct-2026) — elimina un curso completo de
    //  Moodle (secciones, recursos, matrículas, calificaciones). Sin
    //  confirmar=1 solo describe el curso: nombre, alumnos matriculados,
    //  entregas que hay en sus tareas y recursos. El Guardián se encarga de
    //  negarse cuando el aula sigue ligada a una asignación; aquí solo se
    //  exige la confirmación. No se puede deshacer.
    // =====================================================================
    if ($accion === 'curso_borrar') {
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid']) : 0;
        $confirmar = isset($_GET['confirmar']) ? (string)$_GET['confirmar'] : '';
        if ($courseid <= 0) { salir_(array('ok' => false, 'error' => 'Falta courseid.')); }
        if ($courseid == SITEID) { salir_(array('ok' => false, 'error' => 'Ese es el sitio, no un curso.')); }
        $curso = $DB->get_record('course', array('id' => $courseid));
        if (!$curso) { salir_(array('ok' => false, 'error' => 'No existe el curso ' . $courseid . '.')); }
        $ctx = context_course::instance($courseid);
        $alumnos = (int)$DB->count_records_sql(
            "SELECT COUNT(DISTINCT ue.userid) FROM {user_enrolments} ue JOIN {enrol} e ON e.id = ue.enrolid WHERE e.courseid = ?", array($courseid));
        $entregas = (int)$DB->count_records_sql(
            "SELECT COUNT(s.id) FROM {assign_submission} s JOIN {assign} a ON a.id = s.assignment WHERE a.course = ? AND s.status = 'submitted'", array($courseid));
        $recursos = (int)$DB->count_records_sql(
            "SELECT COUNT(cm.id) FROM {course_modules} cm WHERE cm.course = ? AND cm.deletioninprogress = 0", array($courseid));
        $ficha = array('courseid' => $courseid, 'fullname' => $curso->fullname, 'shortname' => $curso->shortname,
            'alumnosMatriculados' => $alumnos, 'entregasDeAlumnos' => $entregas, 'recursos' => $recursos,
            'url' => $CFG->wwwroot . '/course/view.php?id=' . $courseid);
        if ($confirmar !== '1') {
            $ficha['ok'] = true; $ficha['borrado'] = false;
            $ficha['nota'] = 'Solo descripcion. Para borrarlo agrega confirmar=1. No se puede deshacer.';
            salir_($ficha);
        }
        require_once($CFG->dirroot . '/course/lib.php');
        delete_course($curso, false);
        fix_course_sortorder();
        $ficha['ok'] = true; $ficha['borrado'] = true;
        $ficha['nota'] = 'Curso borrado de Moodle con sus ' . $recursos . ' recursos y ' . $alumnos . ' matriculas.';
        salir_($ficha);
    }

    // =====================================================================
    //  SECCION_ESTADO (lectura, 3-oct-2026) — radiografia de un aula: por cada
    //  seccion, que recursos tiene y QUIEN los puso. Lo que coloco el Guardian
    //  lleva marca en cm.idnumber (presv-, grab-, dpt-, bienv-, ...); lo que no
    //  tiene marca lo puso una persona. Con eso el generador sabe que semanas
    //  estan trabajadas por el docente y no debe tocar.
    //  GET seccion_estado&courseid=N
    // =====================================================================
    if ($accion === 'seccion_estado') {
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid']) : 0;
        if ($courseid <= 0) { salir_(array('ok' => false, 'error' => 'Falta courseid.')); }
        $curso = $DB->get_record('course', array('id' => $courseid));
        if (!$curso) { salir_(array('ok' => false, 'error' => 'No existe el curso ' . $courseid . '.')); }
        $secs = filas_("SELECT id, section, name, summary, visible FROM {course_sections} WHERE course = ? ORDER BY section", array($courseid));
        $mods = filas_(
            "SELECT cm.id AS cmid, cm.section AS secid, cm.instance, cm.idnumber, cm.visible, cm.added, md.name AS tipo
             FROM {course_modules} cm JOIN {modules} md ON md.id = cm.module
             WHERE cm.course = ? AND cm.deletioninprogress = 0", array($courseid));
        $nombres = array();
        foreach (array('assign','resource','page','url','forum','quiz','label','book','folder','feedback','choice','h5pactivity','lesson','workshop') as $tt) {
            try {
                $rr = filas_("SELECT id, name FROM {" . $tt . "} WHERE course = ?", array($courseid));
                foreach ($rr as $r) { $nombres[$tt . '-' . (int)$r['id']] = (string)$r['name']; }
            } catch (Exception $eN) { }
        }
        $tareas = array();
        try {
            $ff = filas_("SELECT a.id, a.duedate, a.allowsubmissionsfromdate,
                            (SELECT COUNT(s.id) FROM {assign_submission} s WHERE s.assignment = a.id AND s.status = 'submitted') AS entregas
                          FROM {assign} a WHERE a.course = ?", array($courseid));
            foreach ($ff as $f) { $tareas[(int)$f['id']] = array('cierre' => (int)$f['duedate'], 'apertura' => (int)$f['allowsubmissionsfromdate'], 'entregas' => (int)$f['entregas']); }
        } catch (Exception $eT) { }
        $porSec = array();
        foreach ($mods as $m) {
            $k = (string)$m['tipo'] . '-' . (int)$m['instance'];
            $marca = (string)$m['idnumber'];
            $reg = array('cmid' => (int)$m['cmid'], 'tipo' => (string)$m['tipo'], 'nombre' => isset($nombres[$k]) ? $nombres[$k] : '',
                'marca' => $marca, 'origen' => ($marca !== '' ? 'guardian' : 'docente'), 'visible' => (int)$m['visible'], 'agregado' => (int)$m['added']);
            if ((string)$m['tipo'] === 'assign' && isset($tareas[(int)$m['instance']])) { $reg['tarea'] = $tareas[(int)$m['instance']]; }
            $porSec[(int)$m['secid']][] = $reg;
        }
        $out = array(); $hoy = time();
        foreach ($secs as $sc) {
            $rec = isset($porSec[(int)$sc['id']]) ? $porSec[(int)$sc['id']] : array();
            $guardian = 0; $docente = 0; $ultimo = 0; $presentacion = false; $tarea = false; $grabacion = false; $foro = false; $entregas = 0;
            foreach ($rec as $r) {
                if ($r['origen'] === 'guardian') { $guardian++; } else { $docente++; }
                if ($r['agregado'] > $ultimo) { $ultimo = $r['agregado']; }
                if (strpos($r['marca'], 'pres') === 0 || strpos($r['marca'], 'dph-') === 0) { $presentacion = true; }
                if (strpos($r['marca'], 'grab-') === 0) { $grabacion = true; }
                if ($r['tipo'] === 'assign') { $tarea = true; if (isset($r['tarea'])) { $entregas += (int)$r['tarea']['entregas']; } }
                if ($r['tipo'] === 'forum') { $foro = true; }
            }
            $resumen = trim(strip_tags((string)$sc['summary']));
            $out[] = array('numero' => (int)$sc['section'], 'nombre' => (string)$sc['name'], 'visible' => (int)$sc['visible'],
                'largoEncuadre' => mb_strlen($resumen), 'recursos' => $rec,
                'resumen' => array('total' => count($rec), 'guardian' => $guardian, 'docente' => $docente, 'vacia' => (count($rec) === 0 && mb_strlen($resumen) < 40),
                    'presentacion' => $presentacion, 'tarea' => $tarea, 'entregasDeAlumnos' => $entregas, 'grabacion' => $grabacion, 'foro' => $foro,
                    'ultimoCambio' => $ultimo, 'ultimoCambioHace' => ($ultimo ? (int)floor(($hoy - $ultimo) / 86400) : null)));
        }
        salir_(array('ok' => true, 'courseid' => $courseid, 'curso' => $curso->fullname, 'clave' => $curso->shortname, 'visible' => (int)$curso->visible, 'secciones' => $out));
    }

    // =====================================================================
    //  RECURSO_RETIRAR (escritura, 3-oct-2026) — quita del aula UN recurso que
    //  colocó el Guardian, por su marca EXACTA (cm.idnumber). Nunca toca lo que
    //  no tiene marca (lo puso una persona). Sin confirmar=1 solo describe.
    //  GET recurso_retirar&courseid=N&marca=presv-DP-...[&confirmar=1]
    //  RECURSO_VISIBILIDAD — oculta o muestra un recurso por marca.
    //  GET recurso_visibilidad&courseid=N&marca=...&visible=0|1&confirmar=1
    // =====================================================================
    if ($accion === 'recurso_retirar' || $accion === 'recurso_visibilidad') {
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid']) : 0;
        $marca = isset($_GET['marca']) ? trim((string)$_GET['marca']) : '';
        $confirmar = isset($_GET['confirmar']) ? (string)$_GET['confirmar'] : '';
        if ($courseid <= 0 || $marca === '') { salir_(array('ok' => false, 'error' => 'Faltan courseid y marca.')); }
        $cms = filas_("SELECT cm.id, cm.section, cm.visible, cm.instance, md.name AS tipo, cs.section AS numero
                       FROM {course_modules} cm JOIN {modules} md ON md.id = cm.module JOIN {course_sections} cs ON cs.id = cm.section
                       WHERE cm.course = ? AND cm.idnumber = ? AND cm.deletioninprogress = 0", array($courseid, $marca));
        if (!count($cms)) { salir_(array('ok' => true, 'encontrados' => 0, 'marca' => $marca, 'nota' => 'No hay ningun recurso con esa marca en el curso ' . $courseid . '.')); }
        $lista = array();
        foreach ($cms as $c) {
            $nombre = '';
            try { $rn = $DB->get_record($c['tipo'], array('id' => (int)$c['instance']), 'id, name'); if ($rn) { $nombre = (string)$rn->name; } } catch (Exception $eN) { }
            $lista[] = array('cmid' => (int)$c['id'], 'tipo' => (string)$c['tipo'], 'nombre' => $nombre, 'seccion' => (int)$c['numero'], 'visible' => (int)$c['visible']);
        }
        if ($confirmar !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'encontrados' => count($lista), 'marca' => $marca, 'recursos' => $lista,
                'nota' => 'Solo descripcion. Agrega confirmar=1 para ' . ($accion === 'recurso_retirar' ? 'retirarlo del aula.' : 'cambiar su visibilidad.')));
        }
        require_once($CFG->dirroot . '/course/lib.php');
        $hechos = 0; $fallos = array();
        foreach ($lista as $r) {
            try {
                if ($accion === 'recurso_retirar') { course_delete_module($r['cmid']); }
                else { $vis = (isset($_GET['visible']) && (string)$_GET['visible'] === '1') ? 1 : 0; set_coursemodule_visible($r['cmid'], $vis); }
                $hechos++;
            } catch (Exception $eD) { $fallos[] = 'cmid ' . $r['cmid'] . ': ' . $eD->getMessage(); }
        }
        if ($hechos) { rebuild_course_cache($courseid, true); }
        salir_(array('ok' => true, 'marca' => $marca, 'recursos' => $lista, ($accion === 'recurso_retirar' ? 'retirados' : 'cambiados') => $hechos, 'fallos' => $fallos));
    }

    if ($accion === 'matricular') {
        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        if ((string)$confirmar !== '1') {
            salir_(array('ok' => false, 'error' => 'Falta confirmacion (confirmar=1).'));
        }
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid'])
            : (isset($_POST['courseid']) ? intval($_POST['courseid']) : 0);
        $shortname = isset($_GET['shortname']) ? trim($_GET['shortname'])
            : (isset($_POST['shortname']) ? trim($_POST['shortname']) : '');
        if ($courseid <= 0 && $shortname !== '') {
            $c = $DB->get_record('course', array('shortname' => $shortname));
            if ($c) { $courseid = (int)$c->id; }
        }
        if ($courseid <= 0) { salir_(array('ok' => false, 'error' => 'Falta courseid o shortname valido.')); }
        if (!$email) { salir_(array('ok' => false, 'error' => 'Falta email.')); }
        $u = $DB->get_record('user', array('email' => $email, 'deleted' => 0));
        if (!$u) { salir_(array('ok' => false, 'error' => 'No existe un usuario con ese correo en el Aula.')); }
        $roleid = isset($_GET['roleid']) ? intval($_GET['roleid'])
            : (isset($_POST['roleid']) ? intval($_POST['roleid']) : 0);
        if ($roleid <= 0) {
            $sr = $DB->get_record('role', array('shortname' => 'student'));
            $roleid = $sr ? (int)$sr->id : 5;
        }
        require_once($CFG->dirroot . '/lib/enrollib.php');
        $enrol = enrol_get_plugin('manual');
        if (!$enrol) { salir_(array('ok' => false, 'error' => 'El metodo manual de matriculacion no esta disponible.')); }
        $instance = $DB->get_record('enrol', array('courseid' => $courseid, 'enrol' => 'manual'));
        if (!$instance) {
            $course = $DB->get_record('course', array('id' => $courseid), '*', MUST_EXIST);
            $instanceid = $enrol->add_default_instance($course);
            if (!$instanceid) { $instanceid = $enrol->add_instance($course); }
            $instance = $DB->get_record('enrol', array('id' => $instanceid));
        }
        $ctx = context_course::instance($courseid);
        $yaEstaba = is_enrolled($ctx, $u->id) ? true : false;
        $enrol->enrol_user($instance, $u->id, $roleid);
        salir_(array('ok' => true, 'courseid' => $courseid, 'email' => $email,
            'userid' => (int)$u->id, 'roleid' => $roleid, 'yaEstaba' => $yaEstaba));
    }

    // =====================================================================
    //  CREAR CATEGORIA (escritura) — crea una categoria (ej. "Maestria en
    //  Educacion (MENE 26-2)") bajo un padre. Idempotente por nombre exacto.
    //  Requiere: confirmar=1, name. Opcional: parent (id; 0 = raiz).
    // =====================================================================
    if ($accion === 'crear_categoria') {
        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        if ((string)$confirmar !== '1') {
            salir_(array('ok' => false, 'error' => 'Falta confirmacion (confirmar=1).'));
        }
        $name = isset($_GET['name']) ? trim($_GET['name'])
            : (isset($_POST['name']) ? trim($_POST['name']) : '');
        $parent = isset($_GET['parent']) ? intval($_GET['parent'])
            : (isset($_POST['parent']) ? intval($_POST['parent']) : 0);
        if ($name === '') { salir_(array('ok' => false, 'error' => 'Falta name.')); }
        // Idempotente: si ya existe una categoria con ese nombre exacto, se devuelve.
        $exist = $DB->get_record('course_categories', array('name' => $name));
        if ($exist) {
            salir_(array('ok' => true, 'yaExistia' => true, 'categoryid' => (int)$exist->id,
                'name' => $name));
        }
        $data = new stdClass();
        $data->name = $name;
        $data->parent = $parent;
        $cat = core_course_category::create($data);
        salir_(array('ok' => true, 'categoryid' => (int)$cat->id, 'name' => $name, 'parent' => $parent));
    }

    // =====================================================================
    //  ENTREGAS_PENDIENTES (ago-2026) — entregas de alumnos SUBIDAS y aún
    //  SIN CALIFICAR, para el control de calidad de revisión en 24 horas.
    //  Parámetros: courseid (opcional), dias (ventana hacia atrás, def. 10).
    //  Regresa cmid para el link directo de calificación:
    //  {wwwroot}/mod/assign/view.php?id={cmid}&action=grading
    // =====================================================================
    // =====================================================================
    //  AULA_RECURSOS — radiografía de recursos por curso (ago-2026):
    //  módulos por tipo, tareas con/sin fecha, nombres de recursos (para
    //  detectar programa/carta) y visibilidad. Param: cursos=1,2,3
    // =====================================================================
    // =====================================================================
    //  SALUD_DATADIR — diagnóstico del error "Invalid permissions detected
    //  when trying to create a directory": ¿moodledata es escribible?
    //  ¿cuánto disco libre hay? ¿puede crear un directorio de prueba?
    // =====================================================================
    // =====================================================================
    //  RETRO_RECIENTES — calificaciones de tareas puestas por el profesor
    //  en los últimos N minutos, CON su retroalimentación escrita. El
    //  Guardián las recoge cada hora y le manda a cada alumno su correo.
    //  Params: &min=90 (ventana hacia atrás en minutos, tope 10080=7 días)
    // =====================================================================
    if ($accion === 'retro_recientes') {
        $min = isset($_GET['min']) ? intval($_GET['min']) : 90;
        if ($min < 5) { $min = 5; }
        if ($min > 10080) { $min = 10080; }
        $desde = time() - ($min * 60);
        $regs = filas_(
            "SELECT ag.id AS gid, ag.grade, ag.timemodified,
                    a.name AS actividad, a.grade AS grademax,
                    c.fullname AS curso, c.shortname AS cursocorto,
                    u.email, u.firstname, u.lastname,
                    cm.id AS cmid, afc.commenttext AS retro
               FROM {assign_grades} ag
               JOIN {assign} a ON a.id = ag.assignment
               JOIN {course} c ON c.id = a.course
               JOIN {user} u ON u.id = ag.userid AND u.deleted = 0
               JOIN {course_modules} cm ON cm.instance = a.id
                    AND cm.module = (SELECT id FROM {modules} WHERE name = 'assign')
          LEFT JOIN {assignfeedback_comments} afc ON afc.grade = ag.id
              WHERE ag.timemodified >= ? AND ag.grade >= 0
           ORDER BY ag.timemodified ASC",
            array($desde));
        $out = array();
        foreach ($regs as $r) {
            $retro = isset($r['retro']) ? strip_tags(
                preg_replace('/<br\s*\/?>|<\/p>/i', "\n", (string)$r['retro'])) : '';
            $out[] = array(
                'gid' => (int)$r['gid'],
                'ts' => (int)$r['timemodified'],
                'curso' => $r['curso'],
                'cursocorto' => $r['cursocorto'],
                'actividad' => $r['actividad'],
                'calificacion' => round((float)$r['grade'], 1),
                'sobre' => round((float)$r['grademax'], 0),
                'correo' => strtolower(trim($r['email'])),
                'nombre' => trim($r['firstname'] . ' ' . $r['lastname']),
                'retro' => trim($retro),
                'url' => $CFG->wwwroot . '/mod/assign/view.php?id=' . (int)$r['cmid']
            );
        }
        salir_(array('ok' => true, 'desdeMin' => $min, 'total' => count($out),
            'calificaciones' => array_slice($out, 0, 200)));
    }

    if ($accion === 'salud_datadir') {
        global $CFG;
        $out = array('ok' => true);
        $out['dataroot'] = $CFG->dataroot;
        $out['dataroot_existe'] = is_dir($CFG->dataroot);
        $out['dataroot_escribible'] = is_writable($CFG->dataroot);
        $out['espacio_libre_mb'] = @disk_free_space($CFG->dataroot) !== false
            ? round(@disk_free_space($CFG->dataroot) / 1048576) : null;
        $out['espacio_total_mb'] = @disk_total_space($CFG->dataroot) !== false
            ? round(@disk_total_space($CFG->dataroot) / 1048576) : null;
        $out['usuario_php'] = function_exists('get_current_user') ? @get_current_user() : '';
        $subdirs = array('cache', 'localcache', 'temp', 'sessions', 'filedir', 'lang', 'muc');
        $det = array();
        foreach ($subdirs as $sd) {
            $ruta = $CFG->dataroot . '/' . $sd;
            $det[$sd] = array('existe' => is_dir($ruta),
                'escribible' => is_dir($ruta) ? is_writable($ruta) : null);
        }
        $out['subdirectorios'] = $det;
        // Prueba REAL: crear y borrar un directorio.
        $pruebaDir = $CFG->dataroot . '/temp/diag_' . time();
        $creado = @mkdir($pruebaDir, 0777, true);
        $out['prueba_crear_directorio'] = $creado ? 'OK' : 'FALLÓ';
        if ($creado) { @rmdir($pruebaDir); }
        else {
            $e = error_get_last();
            $out['prueba_error'] = $e ? $e['message'] : 'sin detalle';
        }
        // Conteo aproximado de archivos en cache/localcache (síntoma de inodos).
        foreach (array('cache', 'localcache') as $cd) {
            $ruta = $CFG->dataroot . '/' . $cd;
            if (is_dir($ruta)) {
                $n = 0;
                $iter = new RecursiveIteratorIterator(
                    new RecursiveDirectoryIterator($ruta, FilesystemIterator::SKIP_DOTS));
                foreach ($iter as $x) { $n++; if ($n > 60000) { break; } }
                $out['archivos_' . $cd] = ($n > 60000) ? '60000+' : $n;
            }
        }
        salir_($out);
    }

    if ($accion === 'aula_recursos') {
        $csv = isset($_GET['cursos']) ? $_GET['cursos'] : '';
        $ids = array();
        foreach (explode(',', $csv) as $x) { $x = intval(trim($x)); if ($x > 0) { $ids[] = $x; } }
        $ids = array_slice(array_unique($ids), 0, 120);
        if (count($ids) === 0) { salir_(array('ok' => false, 'error' => 'Sin cursos.')); }
        list($insql, $inparams) = $DB->get_in_or_equal($ids);
        $out = array();
        $cursos = filas_("SELECT id, fullname, visible, startdate FROM {course} WHERE id $insql", $inparams);
        foreach ($cursos as $c) {
            $out[(int)$c['id']] = array('courseid' => (int)$c['id'], 'curso' => $c['fullname'],
                'visible' => (int)$c['visible'], 'mods' => array(),
                'assignsTotal' => 0, 'assignsConFecha' => 0,
                'nombresRecursos' => array(), 'hasPrograma' => false, 'hasForo' => false,
                'modsOcultos' => array(), 'materialesOcultos' => 0,
                'nombresOcultos' => array(), 'assignsOcultas' => 0);
        }
        // (18-ago-2026) `mod` ES PALABRA RESERVADA EN MARIADB: es el operador
        // de modulo. El motor leia el alias como operador y reventaba la
        // sintaxis, asi que esta consulta NUNCA funciono y la revision de
        // aulas jamas devolvio un dato. El alias se llama ahora `modname`.
        $mods = filas_(
            "SELECT cm.course AS course, md.name AS modname, COUNT(*) AS n
             FROM {course_modules} cm JOIN {modules} md ON md.id = cm.module
             WHERE cm.course $insql AND cm.deletioninprogress = 0 AND cm.visible = 1
             GROUP BY cm.course, md.name", $inparams);
        foreach ($mods as $m) {
            $cid = (int)$m['course'];
            if (isset($out[$cid])) { $out[$cid]['mods'][$m['modname']] = (int)$m['n']; }
        }
        // Lo MISMO, pero de lo OCULTO. Un aula con cuatro materiales ocultos
        // es, para el alumno, un aula vacia: hay que poder nombrarlos para
        // pedirle al docente que los haga visibles, no solo no contarlos.
        try {
            $modsOc = filas_(
                "SELECT cm.course AS course, md.name AS modname, COUNT(*) AS n
                 FROM {course_modules} cm JOIN {modules} md ON md.id = cm.module
                 WHERE cm.course $insql AND cm.deletioninprogress = 0 AND cm.visible = 0
                 GROUP BY cm.course, md.name", $inparams);
            foreach ($modsOc as $m2) {
                $cid = (int)$m2['course'];
                if (isset($out[$cid])) { $out[$cid]['modsOcultos'][$m2['modname']] = (int)$m2['n']; }
            }
        } catch (Exception $eOc) { /* si falla, simplemente no hay conteo */ }
        $asg = filas_(
            "SELECT course, COUNT(*) AS total,
                    SUM(CASE WHEN duedate > 0 THEN 1 ELSE 0 END) AS confecha
             FROM {assign} WHERE course $insql GROUP BY course", $inparams);
        foreach ($asg as $a2) {
            $cid = (int)$a2['course'];
            if (isset($out[$cid])) {
                $out[$cid]['assignsTotal'] = (int)$a2['total'];
                $out[$cid]['assignsConFecha'] = (int)$a2['confecha'];
            }
        }
        // (15-ago-2026) CADA TABLA EN SU PROPIO try. Antes, si un módulo no
        // estaba instalado —book y folder no siempre lo están— la consulta
        // fallaba y se llevaba TODA la acción: el Guardián recibía "Error al
        // leer de la base de datos" y no se podía revisar ningún aula.
        // Ahora lo que no exista simplemente no aporta recursos.
        foreach (array('resource', 'page', 'url', 'book', 'folder') as $tabla) {
            $rr = array();
            try {
                // Se une con course_modules para saber si CADA material esta
                // visible. Antes se contaban todos por igual y un aula podia
                // cumplir la rubrica con todo escondido.
                $rr = filas_(
                    "SELECT t.course AS course, t.name AS name, cm.visible AS visible
                     FROM {" . $tabla . "} t
                     JOIN {course_modules} cm ON cm.instance = t.id
                          AND cm.module = (SELECT id FROM {modules} WHERE name = '" . $tabla . "')
                     WHERE t.course $insql AND cm.deletioninprogress = 0", $inparams);
            } catch (Exception $eT) { $rr = array(); }
            foreach ($rr as $r2) {
                $cid = (int)$r2['course'];
                if (!isset($out[$cid])) { continue; }
                $visible = ((int)$r2['visible'] === 1);
                if ($visible) {
                    if (count($out[$cid]['nombresRecursos']) < 40) { $out[$cid]['nombresRecursos'][] = $r2['name']; }
                } else {
                    $out[$cid]['materialesOcultos']++;
                    if (count($out[$cid]['nombresOcultos']) < 20) { $out[$cid]['nombresOcultos'][] = $r2['name']; }
                }
                // El programa cuenta aunque este oculto: existir y estar
                // visible son dos faltas distintas y conviene no mezclarlas.
                $nlow = mb_strtolower($r2['name']);
                if (preg_match('/programa|carta|encuadre|s[íi]labo|syllabus|dosificaci/u', $nlow)) {
                    $out[$cid]['hasPrograma'] = true;
                }
            }
        }
        // Tareas ocultas: una tarea que el alumno no ve no se puede entregar.
        try {
            $asgOc = filas_(
                "SELECT a.course AS course, COUNT(*) AS n
                 FROM {assign} a
                 JOIN {course_modules} cm ON cm.instance = a.id
                      AND cm.module = (SELECT id FROM {modules} WHERE name = 'assign')
                 WHERE a.course $insql AND cm.deletioninprogress = 0 AND cm.visible = 0
                 GROUP BY a.course", $inparams);
            foreach ($asgOc as $a3) {
                $cid = (int)$a3['course'];
                if (isset($out[$cid])) { $out[$cid]['assignsOcultas'] = (int)$a3['n']; }
            }
        } catch (Exception $eAO) { /* opcional */ }
        foreach ($out as $cid2 => $c2) { $out[$cid2]['hasForo'] = !empty($c2['mods']['forum']); }
        salir_(array('ok' => true, 'cursos' => array_values($out)));
    }

    // =====================================================================
    //  (15-ago-2026) ESTRUCTURA DEL AULA — secciones y recursos.
    //  `aula_recursos` solo cuenta: cuántas tareas, cuántos materiales. Con
    //  eso no se distingue un aula bien construida de una que cumple el
    //  mínimo. El curso modelo de CESSUM tiene una sección por sesión y en
    //  cada una el mismo esqueleto: encuadre escrito, diapositivas, recurso
    //  interactivo, podcast, video, cuadernillo, generador de tarea, tarea
    //  con fechas, grabación y lista de asistencia.
    //  Para poder verificar eso hace falta leer las SECCIONES y qué hay en
    //  cada una, que es lo que devuelve esta acción.
    //    ?accion=aula_estructura&cursos=571
    // =====================================================================
    if ($accion === 'aula_estructura') {
        $csv = isset($_GET['cursos']) ? $_GET['cursos'] : '';
        $ids = array();
        foreach (explode(',', $csv) as $x) { $x = intval(trim($x)); if ($x > 0) { $ids[] = $x; } }
        $ids = array_slice(array_unique($ids), 0, 40);
        if (count($ids) === 0) { salir_(array('ok' => false, 'error' => 'Sin cursos.')); }
        list($insql, $inparams) = $DB->get_in_or_equal($ids);

        $out = array();
        $cursos = filas_("SELECT id, fullname, shortname, visible, startdate, enddate
                          FROM {course} WHERE id $insql", $inparams);
        foreach ($cursos as $c) {
            $out[(int)$c['id']] = array(
                'courseid' => (int)$c['id'],
                'curso' => $c['fullname'],
                'clave' => $c['shortname'],
                'visible' => (int)$c['visible'],
                'secciones' => array());
        }

        // Secciones con su nombre y resumen. El resumen es donde vive el
        // ENCUADRE de la sesión: sin él, la sección es una lista de archivos.
        $secs = filas_("SELECT id, course, section, name, summary
                        FROM {course_sections} WHERE course $insql ORDER BY course, section", $inparams);
        $porSec = array();
        foreach ($secs as $sc) {
            $cid = (int)$sc['course'];
            if (!isset($out[$cid])) { continue; }
            $resumen = trim(strip_tags((string)$sc['summary']));
            $reg = array(
                'numero' => (int)$sc['section'],
                'nombre' => (string)$sc['name'],
                'tieneEncuadre' => (mb_strlen($resumen) >= 200),
                'largoEncuadre' => mb_strlen($resumen),
                'recursos' => array());
            $out[$cid]['secciones'][(int)$sc['section']] = $reg;
            $porSec[$cid . '-' . (int)$sc['section']] = true;
        }

        // Cada módulo con su tipo, su nombre y en qué sección está.
        $mods = filas_(
            "SELECT cm.id AS k, cm.course, cm.section AS secid, md.name AS tipo, cm.instance, cm.visible
             FROM {course_modules} cm
             JOIN {modules} md ON md.id = cm.module
             WHERE cm.course $insql AND cm.deletioninprogress = 0", $inparams);

        // Nombre de cada instancia, tabla por tabla y cada una protegida.
        $nombres = array();
        $fechas = array();
        foreach (array('assign','resource','page','url','forum','quiz','label',
                       'book','folder','feedback','choice','h5pactivity') as $t) {
            try {
                $rr = filas_("SELECT CONCAT('$t-', id) AS k, id, name FROM {" . $t . "} WHERE course $insql", $inparams);
                foreach ($rr as $r) { $nombres[$t . '-' . (int)$r['id']] = (string)$r['name']; }
            } catch (Exception $eN) { /* módulo no instalado: se ignora */ }
        }
        try {
            $ff = filas_("SELECT CONCAT('assign-', id) AS k, id, duedate, allowsubmissionsfromdate
                          FROM {assign} WHERE course $insql", $inparams);
            foreach ($ff as $f) {
                $fechas['assign-' . (int)$f['id']] = array(
                    'cierre' => (int)$f['duedate'],
                    'apertura' => (int)$f['allowsubmissionsfromdate']);
            }
        } catch (Exception $eF) { }

        // Sección a la que pertenece cada módulo (por id de course_sections).
        $secPorId = array();
        foreach ($secs as $sc) { $secPorId[(int)$sc['id']] = array((int)$sc['course'], (int)$sc['section']); }

        foreach ($mods as $m) {
            $cid = (int)$m['course'];
            if (!isset($out[$cid])) { continue; }
            $sid = (int)$m['secid'];
            if (!isset($secPorId[$sid])) { continue; }
            $numSec = $secPorId[$sid][1];
            if (!isset($out[$cid]['secciones'][$numSec])) { continue; }
            $llave = $m['tipo'] . '-' . (int)$m['instance'];
            $reg = array(
                'tipo' => $m['tipo'],
                'nombre' => isset($nombres[$llave]) ? $nombres[$llave] : '',
                'visible' => (int)$m['visible']);
            if (isset($fechas[$llave])) {
                $reg['cierre'] = $fechas[$llave]['cierre'];
                $reg['apertura'] = $fechas[$llave]['apertura'];
            }
            $out[$cid]['secciones'][$numSec]['recursos'][] = $reg;
        }

        // Las secciones se devuelven como lista ordenada, no como mapa.
        $res = array();
        foreach ($out as $cid => $c) {
            $lista = array();
            ksort($c['secciones']);
            foreach ($c['secciones'] as $sc) { $lista[] = $sc; }
            $c['secciones'] = $lista;
            $c['totalSecciones'] = count($lista);
            $res[] = $c;
        }
        salir_(array('ok' => true, 'cursos' => $res));
    }

    if ($accion === 'entregas_pendientes') {
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid'])
            : (isset($_POST['courseid']) ? intval($_POST['courseid']) : 0);
        $dias = isset($_GET['dias']) ? intval($_GET['dias']) : 10;
        if ($dias <= 0 || $dias > 60) { $dias = 10; }
        $desde = time() - ($dias * 86400);
        $sql =
            "SELECT s.id AS sid, s.assignment AS assignid, a.name AS tarea,
                    a.course AS courseid, c.fullname AS curso,
                    cm.id AS cmid,
                    s.userid, u.firstname, u.lastname, u.email,
                    s.timemodified AS entregada
             FROM {assign_submission} s
             JOIN {assign} a ON a.id = s.assignment
             JOIN {course} c ON c.id = a.course
             JOIN {course_modules} cm ON cm.instance = a.id
             JOIN {modules} md ON md.id = cm.module AND md.name = 'assign'
             JOIN {user} u ON u.id = s.userid AND u.deleted = 0
             LEFT JOIN {assign_grades} g ON g.assignment = s.assignment
                  AND g.userid = s.userid
                  AND g.attemptnumber = s.attemptnumber
             WHERE s.status = 'submitted' AND s.latest = 1
               AND s.timemodified >= ?
               AND (g.id IS NULL OR g.grade IS NULL OR g.grade < 0)" .
            ($courseid > 0 ? " AND a.course = ?" : "") .
            " ORDER BY s.timemodified ASC";
        $params = array($desde);
        if ($courseid > 0) { $params[] = $courseid; }
        $rows = filas_($sql, $params);
        $out = array();
        foreach ($rows as $r) {
            $out[] = array(
                'courseid' => (int)$r['courseid'],
                'curso' => $r['curso'],
                'assignid' => (int)$r['assignid'],
                'tarea' => $r['tarea'],
                'cmid' => (int)$r['cmid'],
                'alumno' => trim($r['firstname'] . ' ' . $r['lastname']),
                'correoAlumno' => $r['email'],
                'entregadaEpoch' => (int)$r['entregada'],
                'entregada' => date('d/m/Y H:i', (int)$r['entregada']),
                'linkCalificar' => $CFG->wwwroot .
                    '/mod/assign/view.php?id=' . (int)$r['cmid'] . '&action=grading'
            );
        }
        salir_(array('ok' => true, 'dias' => $dias, 'total' => count($out),
            'entregas' => $out));
    }

    if ($accion === 'push_recientes') {
        // (ago-2026) PUSH CASI INSTANTÁNEO: un cron de cPanel llama esta
        // acción cada minuto. Toma las entregas SUBIDAS en los últimos
        // minutos (ventana con solapamiento; el Guardián deduplica por
        // llave, así que repetir es inofensivo) y se las empuja a
        // guardian.php -> entrega_push, que notifica al docente al momento.
        // Prueba manual: ...&accion=push_recientes  (JSON con el conteo).
        $minutos = isset($_GET['minutos']) ? intval($_GET['minutos']) : 10;
        if ($minutos <= 0 || $minutos > 120) { $minutos = 10; }
        $desde = time() - ($minutos * 60);
        $sql =
            "SELECT s.id AS sid, s.assignment AS assignid, a.name AS tarea,
                    a.course AS courseid, c.fullname AS curso,
                    cm.id AS cmid,
                    s.userid, u.firstname, u.lastname, u.email,
                    s.timemodified AS entregada
             FROM {assign_submission} s
             JOIN {assign} a ON a.id = s.assignment
             JOIN {course} c ON c.id = a.course
             JOIN {course_modules} cm ON cm.instance = a.id
             JOIN {modules} md ON md.id = cm.module AND md.name = 'assign'
             JOIN {user} u ON u.id = s.userid AND u.deleted = 0
             WHERE s.status = 'submitted' AND s.latest = 1
               AND s.timemodified >= ?
             ORDER BY s.timemodified ASC";
        $rows = filas_($sql, array($desde));
        $guardian = 'https://app.cessum.mx/guardian.php';
        $enviadas = 0;
        $detalle = array();
        $tope = 40; // por corrida; el cron del siguiente minuto retoma
        foreach ($rows as $r) {
            if ($enviadas >= $tope) { break; }
            $qs = http_build_query(array(
                'accion'       => 'entrega_push',
                'clave'        => $CLAVE,
                'courseid'     => (int)$r['courseid'],
                'cmid'         => (int)$r['cmid'],
                'assignid'     => (int)$r['assignid'],
                'curso'        => $r['curso'],
                'tarea'        => $r['tarea'],
                'alumno'       => trim($r['firstname'] . ' ' . $r['lastname']),
                'correoAlumno' => $r['email'],
            ));
            $resp = '';
            if (function_exists('curl_init')) {
                $ch = curl_init($guardian . '?' . $qs);
                curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
                curl_setopt($ch, CURLOPT_MAXREDIRS, 4);
                curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 4);
                curl_setopt($ch, CURLOPT_TIMEOUT, 12);
                $resp = curl_exec($ch);
                curl_close($ch);
            } else {
                $resp = @file_get_contents($guardian . '?' . $qs);
            }
            $enviadas++;
            $j = json_decode((string)$resp, true);
            $detalle[] = trim($r['firstname'] . ' ' . $r['lastname']) . ' · ' .
                $r['tarea'] . ' → ' .
                (is_array($j)
                    ? (!empty($j['duplicada']) ? 'ya registrada'
                        : (!empty($j['avisada']) ? 'AVISADA a ' . $j['docente']
                            : 'registrada sin aviso'))
                    : 'sin respuesta');
        }
        salir_(array('ok' => true, 'minutos' => $minutos,
            'encontradas' => count($rows), 'empujadas' => $enviadas,
            'detalle' => $detalle));
    }

    // =====================================================================
    //  IMAGEN DEL CURSO (escritura) — pone la portada que se ve en «Vista
    //  general de curso». Moodle la guarda como archivo del área
    //  'overviewfiles' en el contexto del curso, no como un campo de texto:
    //  hay que meterla por la API de archivos, borrando antes la anterior
    //  para no acumular versiones.
    //
    //  Requiere: confirmar=1, courseid (o shortname), y la imagen por POST
    //  en 'imagen_b64' (base64) con 'nombre' opcional. Se acepta PNG y JPG.
    //  Idempotente: vuelve a llamarse y reemplaza la que hubiera.
    // =====================================================================
    if ($accion === 'imagen_curso') {
        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        if ((string)$confirmar !== '1') {
            salir_(array('ok' => false, 'error' => 'Falta confirmacion (confirmar=1).'));
        }
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid'])
            : (isset($_POST['courseid']) ? intval($_POST['courseid']) : 0);
        $shortname = isset($_GET['shortname']) ? trim($_GET['shortname'])
            : (isset($_POST['shortname']) ? trim($_POST['shortname']) : '');
        if ($courseid <= 0 && $shortname !== '') {
            $c = $DB->get_record('course', array('shortname' => $shortname));
            if ($c) { $courseid = (int)$c->id; }
        }
        if ($courseid <= 0) { salir_(array('ok' => false, 'error' => 'Falta courseid o shortname valido.')); }
        $curso = $DB->get_record('course', array('id' => $courseid));
        if (!$curso) { salir_(array('ok' => false, 'error' => 'No existe ese curso.')); }

        // La imagen llega en base64 por POST: una portada pesa cientos de KB
        // y no cabe en la URL.
        $b64 = isset($_POST['imagen_b64']) ? $_POST['imagen_b64'] : '';
        $url = isset($_POST['imagen_url']) ? trim($_POST['imagen_url'])
            : (isset($_GET['imagen_url']) ? trim($_GET['imagen_url']) : '');
        $datos = '';
        if ($b64 !== '') {
            // Se admite tanto el base64 pelón como el formato data:image/png;base64,...
            if (strpos($b64, ',') !== false && strpos($b64, 'base64') !== false) {
                $b64 = substr($b64, strpos($b64, ',') + 1);
            }
            $datos = base64_decode($b64, true);
            if ($datos === false) { salir_(array('ok' => false, 'error' => 'El base64 de la imagen no es valido.')); }
        } elseif ($url !== '') {
            $datos = @file_get_contents($url);
            if ($datos === false) { salir_(array('ok' => false, 'error' => 'No se pudo descargar la imagen desde esa direccion.')); }
        } else {
            salir_(array('ok' => false, 'error' => 'Falta la imagen: manda imagen_b64 (POST) o imagen_url.'));
        }
        if (strlen($datos) < 500) { salir_(array('ok' => false, 'error' => 'La imagen llego vacia o demasiado pequena.')); }
        if (strlen($datos) > 8 * 1024 * 1024) { salir_(array('ok' => false, 'error' => 'La imagen pesa mas de 8 MB.')); }

        // Que sea una imagen de verdad, y de un tipo que Moodle acepte.
        $info = @getimagesizefromstring($datos);
        if (!$info) { salir_(array('ok' => false, 'error' => 'El archivo no es una imagen valida.')); }
        $mime = isset($info['mime']) ? $info['mime'] : '';
        $ext = ($mime === 'image/jpeg') ? 'jpg' : (($mime === 'image/png') ? 'png' : '');
        if ($ext === '') { salir_(array('ok' => false, 'error' => 'Solo se aceptan PNG o JPG. Llego: ' . $mime)); }

        $nombre = isset($_POST['nombre']) ? trim($_POST['nombre'])
            : (isset($_GET['nombre']) ? trim($_GET['nombre']) : '');
        if ($nombre === '') { $nombre = 'portada.' . $ext; }
        // Sin rutas ni caracteres raros en el nombre del archivo.
        $nombre = preg_replace('/[^A-Za-z0-9._-]/', '_', basename($nombre));
        if (!preg_match('/\.(png|jpg|jpeg)$/i', $nombre)) { $nombre .= '.' . $ext; }

        require_once($CFG->libdir . '/filelib.php');
        $ctx = context_course::instance($courseid);
        $fs = get_file_storage();

        // Fuera la anterior: si no, Moodle guarda las dos y muestra cualquiera.
        $anteriores = $fs->get_area_files($ctx->id, 'course', 'overviewfiles', 0, 'itemid', false);
        $borradas = 0;
        foreach ($anteriores as $f) { $f->delete(); $borradas++; }

        $registro = array(
            'contextid' => $ctx->id,
            'component' => 'course',
            'filearea'  => 'overviewfiles',
            'itemid'    => 0,
            'filepath'  => '/',
            'filename'  => $nombre,
        );
        $nuevo = $fs->create_file_from_string($registro, $datos);
        if (!$nuevo) { salir_(array('ok' => false, 'error' => 'Moodle no pudo guardar el archivo.')); }

        // La vista general lee de la caché del curso: sin esto, la portada
        // nueva no aparece hasta que Moodle decida refrescarla solo.
        try { rebuild_course_cache($courseid, true); } catch (Exception $eC) { }

        salir_(array('ok' => true, 'courseid' => $courseid,
            'curso' => $curso->fullname, 'archivo' => $nombre,
            'bytes' => strlen($datos), 'tipo' => $mime,
            'ancho' => $info[0], 'alto' => $info[1],
            'reemplazadas' => $borradas,
            'nota' => $borradas
                ? 'Portada reemplazada (' . $borradas . ' anterior(es) borrada(s)).'
                : 'Portada puesta.'));
    }

    // =====================================================================
    //  CURSOS SIN PORTADA (lectura) — los que se ven en gris en la vista
    //  general. Se consulta de una sola vez, no curso por curso: el área de
    //  archivos 'overviewfiles' se cruza contra la lista de cursos y se
    //  devuelven los que no tienen ninguna imagen.
    // =====================================================================
    if ($accion === 'cursos_sin_portada') {
        $soloVisibles = isset($_GET['visibles']) ? ($_GET['visibles'] === '1') : true;
        $rows = filas_(
            "SELECT c.id, c.shortname, c.fullname, c.visible, cat.name AS categoria
               FROM {course} c
               LEFT JOIN {course_categories} cat ON cat.id = c.category
              WHERE c.id > 1
              ORDER BY c.fullname");
        $sin = array(); $con = 0;
        $fs = get_file_storage();
        foreach ($rows as $c) {
            if ($soloVisibles && (int)$c['visible'] !== 1) { continue; }
            $ctx = context_course::instance((int)$c['id'], IGNORE_MISSING);
            if (!$ctx) { continue; }
            $files = $fs->get_area_files($ctx->id, 'course', 'overviewfiles', 0, 'itemid', false);
            if (!empty($files)) { $con++; continue; }
            $sin[] = array('id' => (int)$c['id'], 'shortname' => $c['shortname'],
                'nombre' => $c['fullname'], 'categoria' => isset($c['categoria']) ? $c['categoria'] : '',
                'visible' => ((int)$c['visible'] === 1));
        }
        salir_(array('ok' => true, 'conPortada' => $con, 'sinPortada' => count($sin),
            'cursos' => $sin,
            'nota' => count($sin) . ' curso(s) sin portada de ' . ($con + count($sin)) . ' revisados.'));
    }

    // =====================================================================
    //  VER LA IMAGEN DEL CURSO (lectura) — para comprobar sin abrir Moodle.
    // =====================================================================
    if ($accion === 'imagen_curso_ver') {
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid']) : 0;
        if ($courseid <= 0) { salir_(array('ok' => false, 'error' => 'Falta courseid.')); }
        require_once($CFG->libdir . '/filelib.php');
        $ctx = context_course::instance($courseid);
        $fs = get_file_storage();
        $files = $fs->get_area_files($ctx->id, 'course', 'overviewfiles', 0, 'itemid', false);
        $out = array();
        foreach ($files as $f) {
            $out[] = array('archivo' => $f->get_filename(), 'bytes' => (int)$f->get_filesize(),
                'tipo' => $f->get_mimetype(), 'cuando' => (int)$f->get_timemodified());
        }
        salir_(array('ok' => true, 'courseid' => $courseid, 'cuantas' => count($out), 'imagenes' => $out));
    }

    // =====================================================================
    //  SECCIONES_CONFIGURAR (escritura) — deja el curso con las secciones
    //  que se le indiquen: Bienvenida + una por semana de trabajo, cada una
    //  con su banner de encabezado. La sección 0 puede llevar además el
    //  texto de bienvenida, la portada de la materia, el enlace a la clase
    //  y el foro de dudas.
    //
    //  Se escribe en {course_sections} porque Moodle no expone un
    //  webservice del núcleo para renombrar secciones ni fijar su resumen.
    //  Los MÓDULOS (enlace y foro) sí van por add_moduleinfo(): un módulo
    //  toca varias tablas y la secuencia de la sección, y hacerlo a mano
    //  deja el curso inconsistente.
    //
    //  IDEMPOTENTE: reejecutarlo actualiza en vez de duplicar.
    //  Requiere: confirmar=1, courseid, secciones (JSON).
    // =====================================================================
    if ($accion === 'secciones_configurar') {
        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        if ((string)$confirmar !== '1') {
            salir_(array('ok' => false, 'error' => 'Falta confirmacion (confirmar=1).'));
        }
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid'])
            : (isset($_POST['courseid']) ? intval($_POST['courseid']) : 0);
        $secJ = isset($_GET['secciones']) ? (string)$_GET['secciones']
            : (isset($_POST['secciones']) ? (string)$_POST['secciones'] : '');
        if (!$courseid || $secJ === '') {
            salir_(array('ok' => false, 'error' => 'Faltan courseid o secciones.'));
        }
        $secciones = json_decode($secJ, true);
        if (!is_array($secciones) || !count($secciones)) {
            salir_(array('ok' => false, 'error' => 'El parametro secciones no es una lista valida.'));
        }

        require_once($CFG->dirroot . '/course/lib.php');
        require_once($CFG->dirroot . '/course/modlib.php');

        $curso = $DB->get_record('course', array('id' => $courseid));
        if (!$curso) { salir_(array('ok' => false, 'error' => 'No existe el curso ' . $courseid)); }

        $maxNum = 0;
        foreach ($secciones as $s) { $maxNum = max($maxNum, intval(isset($s['num']) ? $s['num'] : 0)); }

        /* (30-sep-2026) BUG CRÍTICO CORREGIDO — esto OCULTABA SEMANAS YA
           CREADAS. $maxNum se calculaba SOLO del payload que se manda en
           esta llamada: si se manda nada más la sección 0 (como hace
           "solo introducción", para no tocar las semanas), maxNum=0, y si
           el curso no tenía YA un registro de numsections, se creaba uno
           NUEVO con valor 0 — Moodle entonces deja de MOSTRAR las semanas
           que sí existen en course_sections (sus datos no se borran, pero
           quedan fuera de la vista). Caso real: curso 648, Seminario de
           Investigación I — sus 5 semanas desaparecieron de la vista tras
           llamar aula_solo_introduccion.
           Ahora SIEMPRE se toma el máximo entre lo pedido y lo que YA
           EXISTE en course_sections para este curso: nunca se reduce. */
        $maxExistente = (int)$DB->get_field_sql(
            "SELECT MAX(section) FROM {course_sections} WHERE course = ?",
            array($courseid));
        $maxNum = max($maxNum, $maxExistente);

        // El curso debe tener al menos tantas secciones como se piden.
        $fo = $DB->get_record('course_format_options',
            array('courseid' => $courseid, 'name' => 'numsections'));
        if ($fo) {
            if (intval($fo->value) < $maxNum) {
                $fo->value = $maxNum;
                $DB->update_record('course_format_options', $fo);
            }
        } else {
            $nuevo = new stdClass();
            $nuevo->courseid = $courseid; $nuevo->format = $curso->format;
            $nuevo->sectionid = 0; $nuevo->name = 'numsections'; $nuevo->value = $maxNum;
            $DB->insert_record('course_format_options', $nuevo);
        }

        $contexto = context_course::instance($courseid);
        $fs = get_file_storage();
        $creadas = 0; $conBanner = 0; $conEnlace = false; $conForo = false; $avisos = array();

        foreach ($secciones as $s) {
            $num     = intval(isset($s['num']) ? $s['num'] : 0);
            $nombre  = trim((string)(isset($s['nombre']) ? $s['nombre'] : ''));
            $banner  = (string)(isset($s['banner']) ? $s['banner'] : '');
            $htmlSec = (string)(isset($s['html']) ? $s['html'] : '');
            $portada = (string)(isset($s['portada']) ? $s['portada'] : '');
            $recurso = isset($s['recurso']) ? $s['recurso'] : null;
            $foro    = isset($s['foro']) ? $s['foro'] : null;

            $sec = $DB->get_record('course_sections',
                array('course' => $courseid, 'section' => $num));
            if (!$sec) {
                $sec = new stdClass();
                $sec->course = $courseid; $sec->section = $num;
                $sec->name = $nombre; $sec->summary = ''; $sec->summaryformat = FORMAT_HTML;
                $sec->sequence = ''; $sec->visible = 1; $sec->timemodified = time();
                $sec->id = $DB->insert_record('course_sections', $sec);
                $creadas++;
            } else {
                $sec->name = $nombre; $sec->timemodified = time();
                $DB->update_record('course_sections', $sec);
            }

            // Imágenes de la sección. Se borran las anteriores para no
            // acumular versiones invisibles que ocupan espacio.
            $viejos = $fs->get_area_files($contexto->id, 'course', 'section', $sec->id, 'filename', false);
            foreach ($viejos as $v) {
                $fn = $v->get_filename();
                if (strpos($fn, 'banner-seccion-') === 0 || $fn === 'portada-bienvenida.png') {
                    $v->delete();
                }
            }

            $resumen = '';
            if ($banner !== '') {
                $bin = base64_decode($banner, true);
                if ($bin === false) {
                    $avisos[] = 'Seccion ' . $num . ': banner ilegible.';
                } else {
                    $arch = 'banner-seccion-' . $num . '.png';
                    $fs->create_file_from_string(array(
                        'contextid' => $contexto->id, 'component' => 'course', 'filearea' => 'section',
                        'itemid' => $sec->id, 'filepath' => '/', 'filename' => $arch), $bin);
                    $resumen .= '<p style="margin:0 0 14px;"><img src="@@PLUGINFILE@@/' . $arch .
                        '" alt="' . htmlspecialchars($nombre, ENT_QUOTES, 'UTF-8') .
                        '" style="width:100%;height:auto;display:block;"></p>';
                    $conBanner++;
                }
            }
            if ($portada !== '') {
                $pbin = base64_decode($portada, true);
                if ($pbin !== false) {
                    $fs->create_file_from_string(array(
                        'contextid' => $contexto->id, 'component' => 'course', 'filearea' => 'section',
                        'itemid' => $sec->id, 'filepath' => '/', 'filename' => 'portada-bienvenida.png'), $pbin);
                } else {
                    $avisos[] = 'Seccion ' . $num . ': portada ilegible.';
                }
            }
            if ($htmlSec !== '') { $resumen .= $htmlSec; }
            if ($resumen !== '') {
                $sec->summary = $resumen;
                $sec->summaryformat = FORMAT_HTML;
                $DB->update_record('course_sections', $sec);
            }

            // El enlace a la clase, como recurso URL con la descripcion
            // visible en la pagina del curso (showdescription = 1).
            if (is_array($recurso) && isset($recurso['tipo']) && $recurso['tipo'] === 'url'
                && !empty($recurso['url'])) {
                $modUrl = $DB->get_record('modules', array('name' => 'url'));
                $nombreRec = trim((string)(isset($recurso['nombre']) ? $recurso['nombre'] : 'Enlace de conexion a la clase'));
                $existente = null;
                $seqIds = array_filter(explode(',', (string)$sec->sequence));
                foreach ($seqIds as $cmid) {
                    $cm = $DB->get_record('course_modules', array('id' => intval($cmid)));
                    if (!$cm || !$modUrl || intval($cm->module) !== intval($modUrl->id)) { continue; }
                    $inst = $DB->get_record('url', array('id' => $cm->instance));
                    if ($inst && strpos($inst->name, 'Enlace de conexi') === 0) {
                        $existente = array($cm, $inst); break;
                    }
                }
                if ($existente) {
                    $cm = $existente[0]; $inst = $existente[1];
                    $inst->name = $nombreRec;
                    $inst->externalurl = (string)$recurso['url'];
                    $inst->intro = (string)(isset($recurso['descripcion']) ? $recurso['descripcion'] : '');
                    $inst->introformat = FORMAT_HTML;
                    $inst->timemodified = time();
                    $DB->update_record('url', $inst);
                    $cm->showdescription = 1;
                    $DB->update_record('course_modules', $cm);
                    $conEnlace = true;
                } else if ($modUrl) {
                    $mod = new stdClass();
                    $mod->course = $courseid;  $mod->modulename = 'url';
                    $mod->module = $modUrl->id; $mod->section = $num;
                    $mod->name = $nombreRec;
                    $mod->externalurl = (string)$recurso['url'];
                    $mod->intro = (string)(isset($recurso['descripcion']) ? $recurso['descripcion'] : '');
                    $mod->introformat = FORMAT_HTML;
                    $mod->showdescription = 1;
                    $mod->display = 0; $mod->visible = 1; $mod->visibleoncoursepage = 1;
                    $mod->printintro = 1; $mod->popupwidth = 620; $mod->popupheight = 450;
                    $mod->cmidnumber = ''; $mod->completion = 0;
                    $mod->groupmode = 0; $mod->groupingid = 0;
                    try { add_moduleinfo($mod, $curso); $conEnlace = true; }
                    catch (Exception $eU) { $avisos[] = 'No se pudo crear el enlace: ' . $eU->getMessage(); }
                }
            }

            // El foro de dudas, con suscripcion FORZOSA: es lo que hace que
            // cada duda le llegue al correo del docente sin que entre a
            // revisar el aula.
            if (is_array($foro) && !empty($foro['nombre'])) {
                $modForo = $DB->get_record('modules', array('name' => 'forum'));
                $yaEsta = false;
                $seqF = array_filter(explode(',', (string)$sec->sequence));
                foreach ($seqF as $cmid) {
                    $cm = $DB->get_record('course_modules', array('id' => intval($cmid)));
                    if (!$cm || !$modForo || intval($cm->module) !== intval($modForo->id)) { continue; }
                    $inst = $DB->get_record('forum', array('id' => $cm->instance));
                    if ($inst && stripos($inst->name, 'Dudas') !== false) {
                        if (intval($inst->forcesubscribe) !== 1) {
                            $inst->forcesubscribe = 1;
                            $DB->update_record('forum', $inst);
                        }
                        $yaEsta = true; $conForo = true; break;
                    }
                }
                if (!$yaEsta && $modForo) {
                    $mf = new stdClass();
                    $mf->course = $courseid;   $mf->modulename = 'forum';
                    $mf->module = $modForo->id; $mf->section = $num;
                    $mf->name = (string)$foro['nombre'];
                    $mf->intro = (string)(isset($foro['descripcion']) ? $foro['descripcion'] : '');
                    $mf->introformat = FORMAT_HTML;
                    $mf->showdescription = 1;
                    $mf->type = 'general';
                    $mf->forcesubscribe = !empty($foro['suscripcionForzosa']) ? 1 : 0;
                    $mf->trackingtype = 1;
                    $mf->maxbytes = 0; $mf->maxattachments = 3;
                    $mf->displaywordcount = 0; $mf->assessed = 0; $mf->scale = 0;
                    $mf->visible = 1; $mf->visibleoncoursepage = 1;
                    $mf->cmidnumber = ''; $mf->completion = 0;
                    $mf->groupmode = 0; $mf->groupingid = 0;
                    try { add_moduleinfo($mf, $curso); $conForo = true; }
                    catch (Exception $eF2) { $avisos[] = 'No se pudo crear el foro: ' . $eF2->getMessage(); }
                }
            }
        }

        try { rebuild_course_cache($courseid, true); } catch (Exception $eC) { }

        salir_(array('ok' => true, 'courseid' => $courseid,
            'secciones' => count($secciones), 'creadas' => $creadas,
            'conBanner' => $conBanner, 'conEnlace' => $conEnlace,
            'conForo' => $conForo, 'avisos' => $avisos));
    }

    // =====================================================================
    //  SECCION_RECURSOS (escritura) — coloca material dentro de secciones ya
    //  existentes: la grabacion de la sesion incrustada y la lista de
    //  asistencia en Excel, cada una en su semana.
    //
    //  IDEMPOTENTE por "marca": cada recurso lleva un identificador propio
    //  que se guarda en idnumber. Correr el barrido a diario actualiza en
    //  vez de llenar el aula de copias.
    //  Requiere: confirmar=1, courseid, secciones (JSON).
    // =====================================================================
    if ($accion === 'seccion_recursos') {
        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        if ((string)$confirmar !== '1') {
            salir_(array('ok' => false, 'error' => 'Falta confirmacion (confirmar=1).'));
        }
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid'])
            : (isset($_POST['courseid']) ? intval($_POST['courseid']) : 0);
        $secJ = isset($_GET['secciones']) ? (string)$_GET['secciones']
            : (isset($_POST['secciones']) ? (string)$_POST['secciones'] : '');
        if (!$courseid || $secJ === '') {
            salir_(array('ok' => false, 'error' => 'Faltan courseid o secciones.'));
        }
        $secciones = json_decode($secJ, true);
        if (!is_array($secciones)) {
            salir_(array('ok' => false, 'error' => 'secciones no es una lista valida.'));
        }

        require_once($CFG->dirroot . '/course/lib.php');
        require_once($CFG->dirroot . '/course/modlib.php');

        $curso = $DB->get_record('course', array('id' => $courseid));
        if (!$curso) { salir_(array('ok' => false, 'error' => 'No existe el curso ' . $courseid)); }

        $modLabel = $DB->get_record('modules', array('name' => 'label'));
        $modUrl   = $DB->get_record('modules', array('name' => 'url'));
        $colocados = 0; $actualizados = 0; $avisos = array();

        foreach ($secciones as $s) {
            $num = intval(isset($s['num']) ? $s['num'] : -1);
            $recursos = isset($s['recursos']) ? $s['recursos'] : array();
            if ($num < 0 || !is_array($recursos) || !count($recursos)) { continue; }

            $sec = $DB->get_record('course_sections',
                array('course' => $courseid, 'section' => $num));
            if (!$sec) { $avisos[] = 'La seccion ' . $num . ' no existe en el curso.'; continue; }

            foreach ($recursos as $r) {
                $tipo   = (string)(isset($r['tipo']) ? $r['tipo'] : '');
                $marca  = (string)(isset($r['marca']) ? $r['marca'] : '');
                $nombre = trim((string)(isset($r['nombre']) ? $r['nombre'] : ''));
                if ($marca === '' || $nombre === '') { continue; }

                $cmPrev = $DB->get_record('course_modules',
                    array('course' => $courseid, 'idnumber' => $marca));

                if ($tipo === 'etiqueta' && $modLabel) {
                    $html = (string)(isset($r['html']) ? $r['html'] : '');
                    if ($cmPrev) {
                        $inst = $DB->get_record('label', array('id' => $cmPrev->instance));
                        if ($inst) {
                            $inst->name = $nombre; $inst->intro = $html;
                            $inst->introformat = FORMAT_HTML; $inst->timemodified = time();
                            $DB->update_record('label', $inst);
                            $actualizados++;
                        }
                        continue;
                    }
                    $mod = new stdClass();
                    $mod->course = $courseid; $mod->modulename = 'label';
                    $mod->module = $modLabel->id; $mod->section = $num;
                    $mod->name = $nombre; $mod->intro = $html;
                    $mod->introformat = FORMAT_HTML;
                    $mod->visible = 1; $mod->visibleoncoursepage = 1;
                    $mod->cmidnumber = $marca; $mod->completion = 0;
                    $mod->groupmode = 0; $mod->groupingid = 0;
                    try { add_moduleinfo($mod, $curso); $colocados++; }
                    catch (Exception $eL) { $avisos[] = 'Seccion ' . $num . ', ' . $marca . ': ' . $eL->getMessage(); }

                } else if ($tipo === 'url' && $modUrl) {
                    $url = (string)(isset($r['url']) ? $r['url'] : '');
                    if ($url === '') { continue; }
                    if ($cmPrev) {
                        $inst = $DB->get_record('url', array('id' => $cmPrev->instance));
                        if ($inst) {
                            $inst->name = $nombre; $inst->externalurl = $url;
                            $inst->intro = (string)(isset($r['descripcion']) ? $r['descripcion'] : '');
                            $inst->introformat = FORMAT_HTML; $inst->timemodified = time();
                            $DB->update_record('url', $inst);
                            $actualizados++;
                        }
                        continue;
                    }
                    $mod = new stdClass();
                    $mod->course = $courseid; $mod->modulename = 'url';
                    $mod->module = $modUrl->id; $mod->section = $num;
                    $mod->name = $nombre; $mod->externalurl = $url;
                    $mod->intro = (string)(isset($r['descripcion']) ? $r['descripcion'] : '');
                    $mod->introformat = FORMAT_HTML;
                    $mod->showdescription = 1; $mod->display = 0;
                    $mod->visible = 1; $mod->visibleoncoursepage = 1;
                    $mod->printintro = 1; $mod->popupwidth = 620; $mod->popupheight = 450;
                    $mod->cmidnumber = $marca; $mod->completion = 0;
                    $mod->groupmode = 0; $mod->groupingid = 0;
                    try { add_moduleinfo($mod, $curso); $colocados++; }
                    catch (Exception $eU2) { $avisos[] = 'Seccion ' . $num . ', ' . $marca . ': ' . $eU2->getMessage(); }
                }
            }
        }

        try { rebuild_course_cache($courseid, true); } catch (Exception $eC2) { }
        salir_(array('ok' => true, 'courseid' => $courseid,
            'colocados' => $colocados, 'actualizados' => $actualizados, 'avisos' => $avisos));
    }

    // =====================================================================
    //  FORO_DUDAS_PENDIENTES (lectura) — dudas publicadas en los foros de
    //  dudas que llevan mas de N horas SIN RESPUESTA DEL DOCENTE. Que otro
    //  alumno haya contestado no significa que la duda este atendida.
    //  Solo mira foros cuyo nombre empieza con "Dudas": los demas foros del
    //  curso no generan recordatorios.
    // =====================================================================
    if ($accion === 'foro_dudas_pendientes') {
        $horasP = isset($_GET['horas']) ? intval($_GET['horas'])
            : (isset($_POST['horas']) ? intval($_POST['horas']) : 72);
        if ($horasP < 1) { $horasP = 72; }
        $corte = time() - ($horasP * 3600);

        $sql = "SELECT d.id AS discusionid, d.name AS asunto, d.timemodified,
                       f.id AS foroid, c.id AS courseid, c.fullname AS curso,
                       ua.firstname AS alu_nom, ua.lastname AS alu_ape,
                       d.userid AS autorid
                  FROM {forum_discussions} d
                  JOIN {forum} f ON f.id = d.forum
                  JOIN {course} c ON c.id = f.course
                  JOIN {user} ua ON ua.id = d.userid
                 WHERE c.visible = 1
                   AND " . $DB->sql_like('f.name', ':pat', false) . "
                   AND d.timemodified < :corte
              ORDER BY d.timemodified ASC";
        $filas = $DB->get_records_sql($sql, array('pat' => 'Dudas%', 'corte' => $corte), 0, 300);

        $dudas = array(); $docentesPorCurso = array();
        foreach ($filas as $r) {
            if (!isset($docentesPorCurso[$r->courseid])) {
                $ctx = context_course::instance($r->courseid);
                $lista = array();
                foreach (get_enrolled_users($ctx, 'moodle/course:manageactivities') as $u) {
                    $lista[intval($u->id)] = array(
                        'nombre' => trim($u->firstname . ' ' . $u->lastname),
                        'correo' => $u->email);
                }
                $docentesPorCurso[$r->courseid] = $lista;
            }
            $docentes = $docentesPorCurso[$r->courseid];
            if (!count($docentes)) { continue; }
            // Si quien abrio la discusion ES el docente, no es una duda.
            if (isset($docentes[intval($r->autorid)])) { continue; }

            list($inSql, $inParams) = $DB->get_in_or_equal(array_keys($docentes), SQL_PARAMS_NAMED, 'dd');
            $inParams['disc'] = $r->discusionid;
            $respondio = $DB->record_exists_select('forum_posts',
                "discussion = :disc AND userid $inSql", $inParams);
            if ($respondio) { continue; }

            $doc = reset($docentes);
            $dudas[] = array(
                'discusionid' => intval($r->discusionid),
                'asunto' => $r->asunto,
                'materia' => $r->curso,
                'courseid' => intval($r->courseid),
                'alumno' => trim($r->alu_nom . ' ' . $r->alu_ape),
                'docente' => $doc['nombre'],
                'correoDocente' => $doc['correo'],
                'horas' => round((time() - intval($r->timemodified)) / 3600, 1),
                'url' => $CFG->wwwroot . '/mod/forum/discuss.php?d=' . intval($r->discusionid),
            );
        }
        salir_(array('ok' => true, 'horas' => $horasP, 'dudas' => $dudas, 'total' => count($dudas)));
    }


    /* ==================================================================
     *  (21-sep-2026) UN ARCHIVO PDF COMO RECURSO DE LA SECCION
     *  ------------------------------------------------------------------
     *  seccion_recursos solo sabe poner etiquetas y enlaces: una lista de
     *  asistencia salia como texto o como un enlace a Drive, nunca como un
     *  documento del aula. Esta accion crea un recurso ARCHIVO (mod_resource)
     *  con el PDF guardado dentro de Moodle, en la seccion indicada.
     *
     *  IDEMPOTENTE por marca, como el resto: si ya existe un recurso con esa
     *  marca, se le reemplaza el archivo y el nombre; no se duplica.
     *
     *  El archivo se guarda directo en el area del modulo, sin pasar por el
     *  area de borradores del usuario: el puente no inicia sesion, y el
     *  borrador exige un usuario con sesion.
     *
     *  POST seccion_archivo: courseid, num, marca, nombre, descripcion,
     *       archivo (nombre.pdf), datos_b64, confirmar=1
     * ================================================================== */
    if ($accion === 'seccion_archivo') {
        $courseid = isset($_POST['courseid']) ? intval($_POST['courseid'])
            : (isset($_GET['courseid']) ? intval($_GET['courseid']) : 0);
        $num = isset($_POST['num']) ? intval($_POST['num'])
            : (isset($_GET['num']) ? intval($_GET['num']) : -1);
        $marca = trim((string)(isset($_POST['marca']) ? $_POST['marca'] : ''));
        $nombre = trim((string)(isset($_POST['nombre']) ? $_POST['nombre'] : ''));
        $desc = (string)(isset($_POST['descripcion']) ? $_POST['descripcion'] : '');
        $archivo = trim((string)(isset($_POST['archivo']) ? $_POST['archivo'] : 'documento.pdf'));
        $b64 = (string)(isset($_POST['datos_b64']) ? $_POST['datos_b64'] : '');
        $confirmar = isset($_POST['confirmar']) ? $_POST['confirmar']
            : (isset($_GET['confirmar']) ? $_GET['confirmar'] : '');

        if ($courseid <= 0 || $num < 0) { salir_(array('ok' => false, 'error' => 'Faltan courseid y num.')); }
        if (strlen($marca) < 4) { salir_(array('ok' => false, 'error' => 'La marca es obligatoria y de 4 caracteres minimo.')); }
        if ($nombre === '') { salir_(array('ok' => false, 'error' => 'Falta el nombre del recurso.')); }
        $datos = base64_decode($b64, true);
        if ($datos === false || strlen($datos) < 200) { salir_(array('ok' => false, 'error' => 'El archivo llego vacio o el base64 no es valido.')); }
        if (substr($datos, 0, 4) !== '%PDF') { salir_(array('ok' => false, 'error' => 'El archivo no es un PDF.')); }
        if (strlen($datos) > 20 * 1024 * 1024) { salir_(array('ok' => false, 'error' => 'El PDF pesa mas de 20 MB.')); }
        $archivo = preg_replace('/[^A-Za-z0-9._-]/', '_', basename($archivo));
        if (!preg_match('/\.pdf$/i', $archivo)) { $archivo .= '.pdf'; }

        if ((string)$confirmar !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'courseid' => $courseid, 'num' => $num,
                'marca' => $marca, 'archivo' => $archivo, 'bytes' => strlen($datos),
                'nota' => 'NADA ESCRITO. Para hacerlo: confirmar=1'));
        }

        require_once($CFG->dirroot . '/course/lib.php');
        require_once($CFG->dirroot . '/course/modlib.php');
        require_once($CFG->libdir . '/filelib.php');
        require_once($CFG->libdir . '/resourcelib.php');

        $curso = $DB->get_record('course', array('id' => $courseid), '*', IGNORE_MISSING);
        if (!$curso) { salir_(array('ok' => false, 'error' => 'No existe el curso ' . $courseid . '.')); }
        $modRes = $DB->get_record('modules', array('name' => 'resource'));
        if (!$modRes) { salir_(array('ok' => false, 'error' => 'El modulo Archivo no esta instalado.')); }
        $fs = get_file_storage();

        $cmPrev = $DB->get_record('course_modules', array('course' => $courseid, 'idnumber' => $marca));
        if ($cmPrev && (int)$cmPrev->module !== (int)$modRes->id) {
            salir_(array('ok' => false, 'error' => 'Ya hay un recurso de OTRO tipo con la marca ' . $marca .
                '. Borralo primero con seccion_borrar_marca.'));
        }

        $cmid = 0; $accionHecha = '';
        if ($cmPrev) {
            $cmid = (int)$cmPrev->id;
            $inst = $DB->get_record('resource', array('id' => $cmPrev->instance));
            if ($inst) {
                $inst->name = $nombre; $inst->intro = $desc; $inst->introformat = FORMAT_HTML;
                $inst->revision = (int)$inst->revision + 1; $inst->timemodified = time();
                $DB->update_record('resource', $inst);
            }
            $accionHecha = 'actualizado';
        } else {
            $mod = new stdClass();
            $mod->course = $courseid; $mod->modulename = 'resource';
            $mod->module = $modRes->id; $mod->section = $num;
            $mod->name = $nombre; $mod->intro = $desc; $mod->introformat = FORMAT_HTML;
            $mod->showdescription = 1; $mod->visible = 1; $mod->visibleoncoursepage = 1;
            $mod->files = 0;
            $mod->display = defined('RESOURCELIB_DISPLAY_EMBED') ? RESOURCELIB_DISPLAY_EMBED : 1;
            $mod->printintro = 1; $mod->showsize = 0; $mod->showtype = 1; $mod->showdate = 0;
            $mod->popupwidth = 620; $mod->popupheight = 450; $mod->filterfiles = 0;
            $mod->cmidnumber = $marca; $mod->completion = 0;
            $mod->groupmode = 0; $mod->groupingid = 0;
            try {
                $info = add_moduleinfo($mod, $curso);
                $cmid = (int)$info->coursemodule;
            } catch (Exception $eR) {
                salir_(array('ok' => false, 'error' => 'Moodle no pudo crear el recurso: ' . $eR->getMessage()));
            }
            $accionHecha = 'colocado';
        }

        // El archivo, directo en el area del modulo. Fuera el anterior.
        $ctx = context_module::instance($cmid);
        $fs->delete_area_files($ctx->id, 'mod_resource', 'content');
        $nuevo = $fs->create_file_from_string(array(
            'contextid' => $ctx->id, 'component' => 'mod_resource', 'filearea' => 'content',
            'itemid' => 0, 'filepath' => '/', 'filename' => $archivo, 'sortorder' => 1
        ), $datos);
        if (!$nuevo) { salir_(array('ok' => false, 'error' => 'Moodle no pudo guardar el PDF.')); }

        try { rebuild_course_cache($courseid, true); } catch (Exception $eC3) { }
        salir_(array('ok' => true, 'courseid' => $courseid, 'num' => $num, 'cmid' => $cmid,
            'marca' => $marca, 'archivo' => $archivo, 'bytes' => strlen($datos),
            'accion' => $accionHecha,
            'nota' => 'PDF ' . $accionHecha . ' en la seccion ' . $num . ' como recurso Archivo.'));
    }

    /* ==================================================================
     *  (9-sep-2026) BORRAR RECURSOS POR MARCA
     *  ------------------------------------------------------------------
     *  Nace de un caso concreto: las grabaciones de clase se colocaron como
     *  ENLACE y hay que volver a ponerlas como video incrustado. Moodle no
     *  admite dos recursos con el mismo idnumber en un curso, asi que la
     *  version nueva necesita otra marca — y sin poder borrar, cada semana
     *  quedaria con el enlace viejo y el video nuevo, uno debajo del otro.
     *
     *  ESTO ES DESTRUCTIVO Y NO TIENE DESHACER. Por eso:
     *    · exige confirmar=1 Y frase=BORRAR (dos llaves, no una);
     *    · sin ellas responde que HARIA, sin tocar nada;
     *    · el prefijo es obligatorio y de 4 caracteres minimo, para que un
     *      parametro vacio no pueda barrer un curso entero;
     *    · nunca borra por nombre ni por tipo: solo por idnumber, que es una
     *      marca que pone el sistema, no algo que un humano haya escrito.
     *
     *  GET/POST seccion_borrar_marca&prefijo=grab-[&courseid=N][&confirmar=1&frase=BORRAR]
     * ================================================================== */
    if ($accion === 'seccion_borrar_marca') {
        $prefijo = isset($_GET['prefijo']) ? (string)$_GET['prefijo']
            : (isset($_POST['prefijo']) ? (string)$_POST['prefijo'] : '');
        $prefijo = trim($prefijo);
        if (strlen($prefijo) < 4) {
            salir_(array('ok' => false,
                'error' => 'El prefijo es obligatorio y de 4 caracteres minimo.'));
        }

        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid'])
            : (isset($_POST['courseid']) ? intval($_POST['courseid']) : 0);
        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        $frase = isset($_GET['frase']) ? (string)$_GET['frase']
            : (isset($_POST['frase']) ? (string)$_POST['frase'] : '');
        $deVeras = ((string)$confirmar === '1' && $frase === 'BORRAR');

        require_once($CFG->dirroot . '/course/lib.php');

        $params = array('pat' => $prefijo . '%');
        $where = $DB->sql_like('cm.idnumber', ':pat', false);
        if ($courseid) { $where .= ' AND cm.course = :cid'; $params['cid'] = $courseid; }

        $sql = "SELECT cm.id, cm.course, cm.idnumber, cm.section, m.name AS modulo, c.fullname AS curso
                  FROM {course_modules} cm
                  JOIN {modules} m ON m.id = cm.module
                  JOIN {course} c ON c.id = cm.course
                 WHERE $where
              ORDER BY cm.course ASC, cm.id ASC";
        $filas = $DB->get_records_sql($sql, $params, 0, 1000);

        $lista = array();
        foreach ($filas as $r) {
            $lista[] = array('cmid' => intval($r->id), 'courseid' => intval($r->course),
                'curso' => $r->curso, 'marca' => $r->idnumber, 'modulo' => $r->modulo);
        }

        if (!$deVeras) {
            salir_(array('ok' => true, 'prueba' => true, 'encontrados' => count($lista),
                'detalle' => array_slice($lista, 0, 60),
                'nota' => 'NADA BORRADO. Se borrarian ' . count($lista) .
                    ' recurso(s) con marca que empieza en "' . $prefijo .
                    '". Para hacerlo de verdad: &confirmar=1&frase=BORRAR'));
        }

        $borrados = 0; $fallos = array();
        foreach ($filas as $r) {
            try { course_delete_module(intval($r->id)); $borrados++; }
            catch (Exception $eB) {
                $fallos[] = array('cmid' => intval($r->id), 'error' => $eB->getMessage());
            }
        }
        salir_(array('ok' => true, 'borrados' => $borrados, 'fallos' => $fallos,
            'encontrados' => count($lista),
            'nota' => $borrados . ' recurso(s) borrado(s).'));
    }
    /* (10-sep-2026) SABER QUÉ VERSIÓN ESTÁ CORRIENDO, SIN ADIVINAR.
     * Nació de perder media hora creyendo que el archivo no había subido:
     * el tamaño en cPanel decía lo nuevo, el editor mostraba el código
     * nuevo, y la URL seguía respondiendo como el viejo — era la caché del
     * NAVEGADOR guardando una respuesta anterior. Con esta acción se pide
     * una URL que nadie ha pedido antes y la respuesta dice qué archivo
     * está vivo. Cuando actualices el puente, llama a esto primero.
     * Y si una acción se comporta raro después de subir un archivo,
     * agrégale un parámetro cualquiera (&z=2) para saltarte la caché. */
    // =====================================================================
    //  (24-sep-2026) ENTREGAS_ALUMNO — SOLO LECTURA. Las tareas de un curso
    //  con la entrega de UN alumno (estado, fecha, calificación). La usa la
    //  pre-revisión con IA del recursamiento autogestivo.
    //  Requiere: courseid, email.
    // =====================================================================
    if ($accion === 'entregas_alumno') {
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid']) : 0;
        if ($courseid <= 0 || $email === '') {
            salir_(array('ok' => false, 'error' => 'Falta courseid o email.'));
        }
        $u = $DB->get_record_sql("SELECT id, firstname, lastname FROM {user}
             WHERE LOWER(email) = ? AND deleted = 0", array($email), IGNORE_MULTIPLE);
        if (!$u) { salir_(array('ok' => false, 'error' => 'El alumno no existe en el aula.')); }
        $tareas = filas_("SELECT a.id AS assignid, a.name, a.duedate, a.grade AS maxgrade, cm.id AS cmid
             FROM {assign} a
             JOIN {course_modules} cm ON cm.instance = a.id
             JOIN {modules} md ON md.id = cm.module AND md.name = 'assign'
             WHERE a.course = ? AND cm.visible = 1 AND cm.deletioninprogress = 0
             ORDER BY cm.section, cm.id", array($courseid));
        $out = array();
        foreach ($tareas as $t) {
            $s = $DB->get_record_sql("SELECT id, status, timemodified, attemptnumber FROM {assign_submission}
                 WHERE assignment = ? AND userid = ? AND latest = 1", array($t['assignid'], $u->id), IGNORE_MULTIPLE);
            $g = $s ? $DB->get_record_sql("SELECT grade FROM {assign_grades}
                 WHERE assignment = ? AND userid = ? AND attemptnumber = ?",
                 array($t['assignid'], $u->id, $s->attemptnumber), IGNORE_MULTIPLE) : null;
            $out[] = array(
                'assignid' => (int)$t['assignid'],
                'cmid' => (int)$t['cmid'],
                'tarea' => $t['name'],
                'vence' => (int)$t['duedate'] > 0 ? date('d/m/Y H:i', (int)$t['duedate']) : '',
                'calificacionMaxima' => (float)$t['maxgrade'],
                'sid' => $s ? (int)$s->id : 0,
                'estado' => $s ? $s->status : 'sin entrega',
                'entregada' => ($s && $s->status === 'submitted') ? date('d/m/Y H:i', (int)$s->timemodified) : '',
                'calificacion' => ($g && $g->grade !== null && (float)$g->grade >= 0) ? (float)$g->grade : null
            );
        }
        salir_(array('ok' => true, 'courseid' => $courseid,
            'alumno' => trim($u->firstname . ' ' . $u->lastname), 'tareas' => $out));
    }

    // =====================================================================
    //  (24-sep-2026) ENTREGA_CONTENIDO — SOLO LECTURA. El contenido de UNA
    //  entrega para que la IA la pre-revise: consigna de la tarea, rúbrica
    //  (si la tiene), texto en línea y archivos. Los Word (.docx) se
    //  convierten a texto aquí; PDF e imágenes van en base64 (máx. 4 MB por
    //  archivo y 6 MB en total); lo demás se lista sin contenido.
    //  Requiere: sid, o bien assignid + email.
    // =====================================================================
    if ($accion === 'entrega_contenido') {
        $sid = isset($_GET['sid']) ? intval($_GET['sid']) : 0;
        $assignid = isset($_GET['assignid']) ? intval($_GET['assignid']) : 0;
        if ($sid <= 0 && $assignid > 0 && $email !== '') {
            $sx = $DB->get_record_sql("SELECT s.id FROM {assign_submission} s
                 JOIN {user} u ON u.id = s.userid
                 WHERE s.assignment = ? AND LOWER(u.email) = ? AND s.latest = 1 AND u.deleted = 0",
                 array($assignid, $email), IGNORE_MULTIPLE);
            if ($sx) { $sid = (int)$sx->id; }
        }
        if ($sid <= 0) { salir_(array('ok' => false, 'error' => 'No encontré la entrega.')); }
        $s = $DB->get_record('assign_submission', array('id' => $sid));
        if (!$s) { salir_(array('ok' => false, 'error' => 'No encontré la entrega.')); }
        $a = $DB->get_record('assign', array('id' => $s->assignment), 'id, course, name, intro, grade, duedate');
        $cm = $DB->get_record_sql("SELECT cm.id FROM {course_modules} cm
             JOIN {modules} md ON md.id = cm.module AND md.name = 'assign'
             WHERE cm.instance = ?", array($a->id), IGNORE_MULTIPLE);
        $u = $DB->get_record('user', array('id' => $s->userid), 'id, firstname, lastname, email');
        $limpiar = function ($html) {
            $t = str_replace(array('<br>', '<br />', '<br/>', '</p>', '</li>', '</div>'), "\n", (string)$html);
            $t = html_entity_decode(strip_tags($t), ENT_QUOTES, 'UTF-8');
            return trim(preg_replace("/\n{3,}/", "\n\n", $t));
        };
        $texto = '';
        $ot = $DB->get_record('assignsubmission_onlinetext', array('submission' => $sid), 'onlinetext', IGNORE_MULTIPLE);
        if ($ot && $ot->onlinetext) { $texto = substr($limpiar($ot->onlinetext), 0, 40000); }
        require_once($CFG->libdir . '/filelib.php');
        $ctx = context_module::instance($cm->id);
        $fs = get_file_storage();
        $files = $fs->get_area_files($ctx->id, 'assignsubmission_file', 'submission_files', $sid, 'filename', false);
        $archivos = array();
        $total = 0;
        // (4-oct-2026, Mesa de revisión R1) ver=1: la app quiere MOSTRAR la entrega, no solo leerla: el Word viaja completo para
        // verse con su formato, el tope sube un poco y todo archivo trae su enlace directo de Moodle como respaldo.
        $ver = isset($_GET['ver']) && (string)$_GET['ver'] === '1';
        $topeArch = $ver ? 6 * 1024 * 1024 : 4 * 1024 * 1024;
        $topeTotal = $ver ? 12 * 1024 * 1024 : 6 * 1024 * 1024;
        foreach ($files as $f) {
            $mime = $f->get_mimetype();
            $nombre = $f->get_filename();
            $bytes = (int)$f->get_filesize();
            $ext = strtolower(pathinfo($nombre, PATHINFO_EXTENSION));
            $item = array('nombre' => $nombre, 'tipo' => $mime, 'bytes' => $bytes);
            if ($ver) {
                $item['url'] = moodle_url::make_pluginfile_url($ctx->id, 'assignsubmission_file', 'submission_files', $sid,
                    $f->get_filepath(), $nombre, true)->out(false);
                if ($ext === 'docx' && $bytes <= $topeArch && $total + $bytes <= $topeTotal) {
                    $item['base64'] = base64_encode($f->get_content()); $total += $bytes;
                }
            }
            if ($ext === 'docx' && class_exists('ZipArchive')) {
                $tmp = $f->copy_content_to_temp();
                $z = new ZipArchive();
                if ($tmp && $z->open($tmp) === true) {
                    $xml = $z->getFromName('word/document.xml');
                    $z->close();
                    if ($xml) {
                        $xml = str_replace(array('</w:p>', '<w:tab/>', '<w:br/>'), array("\n", "\t", "\n"), $xml);
                        $item['texto'] = trim(html_entity_decode(strip_tags($xml), ENT_QUOTES | ENT_XML1, 'UTF-8'));
                    }
                }
                if ($tmp) { @unlink($tmp); }
                if (!isset($item['texto'])) { $item['omitido'] = 'no se pudo leer el Word'; }
            } elseif (in_array($ext, array('txt', 'md', 'csv'))) {
                $item['texto'] = (string)$f->get_content();
            } elseif (($mime === 'application/pdf' || strpos($mime, 'image/') === 0)
                && $bytes <= $topeArch && $total + $bytes <= $topeTotal) {
                $item['base64'] = base64_encode($f->get_content());
                $total += $bytes;
            } else {
                $item['omitido'] = 'formato o tamaño que no se puede leer aquí';
            }
            if (isset($item['texto']) && strlen($item['texto']) > 40000) {
                $item['texto'] = substr($item['texto'], 0, 40000);
                $item['recortado'] = true;
            }
            $archivos[] = $item;
        }
        // Rúbrica de la tarea (calificación avanzada), si tiene.
        $rubrica = array();
        $area = $DB->get_record('grading_areas', array('contextid' => $ctx->id,
            'component' => 'mod_assign', 'areaname' => 'submissions'), 'id, activemethod', IGNORE_MULTIPLE);
        if ($area && $area->activemethod === 'rubric') {
            $def = $DB->get_record_sql("SELECT id FROM {grading_definitions}
                 WHERE areaid = ? AND method = 'rubric' ORDER BY id DESC", array($area->id), IGNORE_MULTIPLE);
            if ($def) {
                $crit = filas_("SELECT id, description, sortorder FROM {gradingform_rubric_criteria}
                     WHERE definitionid = ? ORDER BY sortorder", array($def->id));
                foreach ($crit as $c) {
                    $niv = filas_("SELECT id, score, definition FROM {gradingform_rubric_levels}
                         WHERE criterionid = ? ORDER BY score", array($c['id']));
                    $niveles = array();
                    foreach ($niv as $n) {
                        $niveles[] = array('id' => (int)$n['id'], 'puntos' => (float)$n['score'], 'descripcion' => $limpiar($n['definition']));
                    }
                    $rubrica[] = array('id' => (int)$c['id'], 'criterio' => $limpiar($c['description']), 'niveles' => $niveles);
                }
            }
        }
        salir_(array('ok' => true, 'sid' => $sid, 'assignid' => (int)$a->id, 'courseid' => (int)$a->course,
            'tarea' => $a->name, 'consigna' => substr($limpiar($a->intro), 0, 8000),
            'calificacionMaxima' => (float)$a->grade,
            'vence' => (int)$a->duedate > 0 ? date('d/m/Y H:i', (int)$a->duedate) : '',
            'vencida' => ((int)$a->duedate > 0 && (int)$a->duedate < time()),
            'alumno' => trim($u->firstname . ' ' . $u->lastname), 'correo' => $u->email,
            'estado' => $s->status, 'entregada' => date('d/m/Y H:i', (int)$s->timemodified),
            'texto' => $texto, 'archivos' => $archivos, 'rubrica' => $rubrica));
    }

    /* ==================================================================
     *  (30-sep-2026) CREAR TAREA (mod_assign) CON ARCHIVO ADJUNTO
     *  ------------------------------------------------------------------
     *  Crea una actividad tipo "Tarea" de Moodle en la sección indicada,
     *  con fecha de apertura y de cierre, y un archivo (el HTML de la
     *  actividad que generó el Guardián) adjunto en la introducción para
     *  que el alumno lo descargue, lo edite y lo vuelva a subir como su
     *  entrega. Sigue el mismo patrón que seccion_archivo: idempotente por
     *  "marca" (idnumber), exige confirmar=1.
     *
     *  POST tarea_moodle_crear
     *    confirmar=1, courseid, num (sección), marca (idnumber, 4+ car.),
     *    titulo, descripcion (HTML, opcional), archivo (nombre, ej. .html),
     *    datos_b64 (el archivo en base64),
     *    fechaInicio (timestamp unix, opcional — 0 = sin restricción),
     *    fechaCierre (timestamp unix, opcional — 0 = sin fecha límite)
     * ================================================================== */
    if ($accion === 'tarea_moodle_crear') {
        $courseid = isset($_POST['courseid']) ? intval($_POST['courseid'])
            : (isset($_GET['courseid']) ? intval($_GET['courseid']) : 0);
        $num = isset($_POST['num']) ? intval($_POST['num'])
            : (isset($_GET['num']) ? intval($_GET['num']) : -1);
        $marca = trim((string)(isset($_POST['marca']) ? $_POST['marca'] : ''));
        $titulo = trim((string)(isset($_POST['titulo']) ? $_POST['titulo'] : ''));
        $desc = (string)(isset($_POST['descripcion']) ? $_POST['descripcion'] : '');
        $archivo = trim((string)(isset($_POST['archivo']) ? $_POST['archivo'] : 'actividad.html'));
        $b64 = (string)(isset($_POST['datos_b64']) ? $_POST['datos_b64'] : '');
        $fIni = isset($_POST['fechaInicio']) ? intval($_POST['fechaInicio']) : 0;
        $fFin = isset($_POST['fechaCierre']) ? intval($_POST['fechaCierre']) : 0;
        $confirmar = isset($_POST['confirmar']) ? $_POST['confirmar']
            : (isset($_GET['confirmar']) ? $_GET['confirmar'] : '');

        if ($courseid <= 0 || $num < 0) { salir_(array('ok' => false, 'error' => 'Faltan courseid y num.')); }
        if (strlen($marca) < 4) { salir_(array('ok' => false, 'error' => 'La marca es obligatoria y de 4 caracteres minimo.')); }
        if ($titulo === '') { salir_(array('ok' => false, 'error' => 'Falta el titulo de la tarea.')); }
        $datos = $b64 !== '' ? base64_decode($b64, true) : '';
        if ($b64 !== '' && ($datos === false || strlen($datos) < 10)) {
            salir_(array('ok' => false, 'error' => 'El archivo llego vacio o el base64 no es valido.'));
        }
        if (strlen($datos) > 15 * 1024 * 1024) { salir_(array('ok' => false, 'error' => 'El archivo pesa mas de 15 MB.')); }
        $archivo = preg_replace('/[^A-Za-z0-9._-]/', '_', basename($archivo));
        if ($archivo === '' || $archivo === '.') { $archivo = 'actividad.html'; }

        /* (3-oct-2026) DOS PROTECCIONES DEL TEXTO QUE VA A LA BASE.
         *  · Si la base NO es utf8mb4, un emoji (4 bytes) hace que la escritura falle con «Error escribiendo a la base de datos».
         *    Solo se quitan los caracteres de 4 bytes cuando la colación no es utf8mb4.
         *  · assign.name es varchar(255): el título se corta antes, sin romper un carácter a la mitad. */
        $colacion = (isset($CFG->dboptions) && is_array($CFG->dboptions) && isset($CFG->dboptions['dbcollation']))
            ? (string)$CFG->dboptions['dbcollation'] : '';
        $esUtf8mb4 = (stripos($colacion, 'utf8mb4') !== false);
        if (!$esUtf8mb4) {
            $titulo = preg_replace('/[\x{10000}-\x{10FFFF}]/u', '', $titulo);
            $desc = preg_replace('/[\x{10000}-\x{10FFFF}]/u', '', $desc);
        }
        $titulo = trim(function_exists('mb_substr') ? mb_substr($titulo, 0, 250, 'UTF-8') : substr($titulo, 0, 250));
        if ($titulo === '') { salir_(array('ok' => false, 'error' => 'El titulo quedo vacio al limpiarlo.')); }

        if ((string)$confirmar !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'courseid' => $courseid, 'num' => $num,
                'marca' => $marca, 'titulo' => $titulo, 'archivo' => $archivo, 'bytes' => strlen($datos),
                'fechaInicio' => $fIni, 'fechaCierre' => $fFin,
                'nota' => 'NADA ESCRITO. Para hacerlo: confirmar=1'));
        }

        require_once($CFG->dirroot . '/course/lib.php');
        require_once($CFG->dirroot . '/course/modlib.php');
        require_once($CFG->libdir . '/filelib.php');

        $curso = $DB->get_record('course', array('id' => $courseid), '*', IGNORE_MISSING);
        if (!$curso) { salir_(array('ok' => false, 'error' => 'No existe el curso ' . $courseid . '.')); }
        $modAssign = $DB->get_record('modules', array('name' => 'assign'));
        if (!$modAssign) { salir_(array('ok' => false, 'error' => 'El modulo Tarea (assign) no esta instalado.')); }
        $fs = get_file_storage();

        $cmPrev = $DB->get_record('course_modules', array('course' => $courseid, 'idnumber' => $marca));
        if ($cmPrev && (int)$cmPrev->module !== (int)$modAssign->id) {
            salir_(array('ok' => false, 'error' => 'Ya hay una actividad de OTRO tipo con la marca ' . $marca .
                '. Borrala primero con seccion_borrar_marca.'));
        }

        /* (3-oct) UN MÓDULO A MEDIAS SE REHACE, NO SE DA POR BUENO.
         * Si un intento anterior dejó el módulo del curso sin su actividad (course_modules sin fila en assign), el flujo de
         * «ya existe, se actualiza» lo daba por bueno y la tarea quedaba rota en el aula. Se borra el cascarón y se crea de nuevo. */
        $curado = false;
        if ($cmPrev && !$DB->record_exists('assign', array('id' => $cmPrev->instance))) {
            try { course_delete_module((int)$cmPrev->id); }
            catch (Exception $eO) {
                try { $DB->delete_records('course_modules', array('id' => $cmPrev->id)); } catch (Exception $eO2) { }
            }
            $cmPrev = false;
            $curado = true;
        }

        $cmid = 0; $accionHecha = '';
        if ($cmPrev) {
            // Ya existe: se actualizan fechas, titulo y descripcion (idempotente).
            $cmid = (int)$cmPrev->id;
            $inst = $DB->get_record('assign', array('id' => $cmPrev->instance));
            if ($inst) {
                $inst->name = $titulo; $inst->intro = $desc; $inst->introformat = FORMAT_HTML;
                $inst->allowsubmissionsfromdate = $fIni; $inst->duedate = $fFin;
                $inst->timemodified = time();
                try { $DB->update_record('assign', $inst); }
                catch (Exception $eU) {
                    $d = detalle_excepcion_($eU);
                    $d['ok'] = false; $d['accion'] = $accion; $d['etapa'] = 'actualizar';
                    $d['error'] = 'Moodle no pudo actualizar la tarea: ' . $eU->getMessage();
                    $d['marca'] = $marca; $d['cmid'] = $cmid;
                    salir_($d);
                }
            }
            $accionHecha = 'actualizada';
        } else {
            $mod = new stdClass();
            $mod->course = $courseid; $mod->modulename = 'assign';
            $mod->module = $modAssign->id; $mod->section = $num;
            $mod->name = $titulo; $mod->intro = $desc; $mod->introformat = FORMAT_HTML;
            $mod->showdescription = 1; $mod->visible = 1; $mod->visibleoncoursepage = 1;
            $mod->allowsubmissionsfromdate = $fIni; $mod->duedate = $fFin;
            $mod->cutoffdate = 0; $mod->gradingduedate = 0;
            // Entrega por ARCHIVO (el alumno sube su HTML ya editado), sin
            // texto en línea — es justo lo que se pidió: descarga, edita,
            // sube.
            $mod->assignsubmission_file_enabled = 1;
            /* (5-oct-2026) Productos de la planeación: el alumno puede entregar texto en línea O archivos (hasta 3). */
            $enLinea = (string)(isset($_POST['enlinea']) ? $_POST['enlinea'] : '') === '1';
            $maxArch = isset($_POST['maxarchivos']) ? max(1, min(5, intval($_POST['maxarchivos']))) : 1;
            $mod->assignsubmission_file_maxfiles = $maxArch;
            $mod->assignsubmission_file_maxsizebytes = 15 * 1024 * 1024;
            $mod->assignsubmission_onlinetext_enabled = $enLinea ? 1 : 0;
            $mod->assignsubmission_onlinetext_wordlimit = 0; $mod->assignsubmission_onlinetext_wordlimit_enabled = 0;
            $mod->submissiondrafts = 0;
            $mod->requiresubmissionstatement = 0;
            $mod->sendnotifications = 0;
            $mod->sendlatenotifications = 0;
            $mod->sendstudentnotifications = 1;
            $mod->completion = 0;
            $mod->groupmode = 0; $mod->groupingid = 0;
            $mod->cmidnumber = $marca;
            /* (3-oct-2026) LA CAUSA MÁS PROBABLE DE «Error escribiendo a la base de datos» EN LAS CUATRO SESIONES.
             * assign::add_instance() lee SIN COMPROBAR varios campos del formulario (grade, teamsubmission,
             * requireallteammemberssubmit, blindmarking, hidegrader, preventsubmissionnotingroup…). Si no vienen, valen NULL, y el
             * INSERT en una columna NOT NULL lo rechaza la base. El foro de este mismo puente sí manda los suyos; la tarea no.
             * Estos son los valores que el propio Moodle usa al crear una tarea sin tocar nada. */
            $mod->alwaysshowdescription = 1; $mod->nosubmissions = 0;
            $mod->grade = 10;                                   // CESSUM califica sobre 10 (la rúbrica suma 10 puntos)
            $mod->teamsubmission = 0; $mod->requireallteammemberssubmit = 0; $mod->teamsubmissiongroupingid = 0;
            $mod->blindmarking = 0; $mod->hidegrader = 0; $mod->revealidentities = 0;
            $mod->attemptreopenmethod = 'none'; $mod->maxattempts = -1;
            $mod->markingworkflow = 0; $mod->markingallocation = 0;
            $mod->preventsubmissionnotingroup = 0;
            $mod->completionsubmit = 0; $mod->submissionattachments = 0; $mod->timelimit = 0;
            // El docente puede dejar comentarios al calificar; sin archivo de retroalimentación ni calificación sin conexión.
            $mod->assignfeedback_comments_enabled = 1; $mod->assignfeedback_comments_commentinline = 0;
            $mod->assignfeedback_file_enabled = 0; $mod->assignfeedback_offline_enabled = 0;
            try {
                $info = add_moduleinfo($mod, $curso);
                $cmid = (int)$info->coursemodule;
            } catch (Exception $eA) {
                /* (3-oct) ANTES SOLO SE DEVOLVÍA getMessage(): el debuginfo —el SQL y el error real del motor— se perdía, y de ahí
                 * «Error escribiendo a la base de datos» no decía qué columna o qué valor rechazó la base. */
                $d = detalle_excepcion_($eA);
                $d['ok'] = false; $d['accion'] = $accion; $d['etapa'] = 'add_moduleinfo';
                $d['error'] = 'Moodle no pudo crear la tarea: ' . $eA->getMessage();
                $d['marca'] = $marca; $d['seccion'] = $num; $d['curso'] = $courseid;
                $d['moodle'] = isset($CFG->release) ? $CFG->release : '';
                $d['colacion'] = $colacion;
                salir_($d);
            }
            $accionHecha = 'creada';
        }

        // El archivo de partida (plantilla HTML), como adjunto de la
        // introduccion — el alumno lo descarga desde ahi antes de trabajar.
        if (strlen($datos) > 0) {
            try {
                $ctx = context_module::instance($cmid);
                $fs->delete_area_files($ctx->id, 'mod_assign', 'introattachment');
                $fs->create_file_from_string(array(
                    'contextid' => $ctx->id, 'component' => 'mod_assign', 'filearea' => 'introattachment',
                    'itemid' => 0, 'filepath' => '/', 'filename' => $archivo, 'sortorder' => 1
                ), $datos);
                /* (3-oct) «introattachments» NO es una columna de la tabla assign en Moodle 4.1: los adjuntos de la introducción
                 * viven solo en el área de archivos. Escribirla reventaba con «Error escribiendo a la base de datos». Ahora solo se
                 * escribe si la columna existe en ESTA instalación. */
                $instId = $DB->get_field('course_modules', 'instance', array('id' => $cmid));
                $colsAssign = $DB->get_columns('assign');
                if ($instId && is_array($colsAssign) && isset($colsAssign['introattachments'])) {
                    $DB->set_field('assign', 'introattachments', 1, array('id' => $instId));
                }
            } catch (Exception $eF) {
                $d = detalle_excepcion_($eF);
                $d['ok'] = false; $d['accion'] = $accion; $d['etapa'] = 'adjuntar';
                $d['error'] = 'La tarea se creó, pero no se pudo adjuntar el archivo: ' . $eF->getMessage();
                $d['tareaCreada'] = true; $d['cmid'] = $cmid; $d['marca'] = $marca;
                $d['url'] = $CFG->wwwroot . '/mod/assign/view.php?id=' . $cmid;
                salir_($d);
            }
        }

        try { rebuild_course_cache($courseid, true); } catch (Exception $eC4) { }
        salir_(array('ok' => true, 'courseid' => $courseid, 'num' => $num, 'cmid' => $cmid,
            'marca' => $marca, 'titulo' => $titulo, 'archivo' => $archivo, 'bytes' => strlen($datos),
            'fechaInicio' => $fIni, 'fechaCierre' => $fFin, 'accion' => $accionHecha,
            'moduloAMediasRehecho' => $curado,
            'url' => $CFG->wwwroot . '/mod/assign/view.php?id=' . $cmid,
            'nota' => 'Tarea ' . $accionHecha . ' en la seccion ' . $num . '.'));
    }

    /* ==================================================================
     *  (5-oct-2026) RÚBRICA DE UNA TAREA — los productos de la planeación validada llegan al aula con su rúbrica.
     *  POST tarea_rubrica { cmid, titulo, criterios (JSON: [{criterio, niveles:[{definicion, puntos}]}]), confirmar }
     *  Pone «Rúbrica» como método de calificación avanzada y escribe la definición. Si la tarea YA tiene alumnos
     *  calificados con una rúbrica, NO la reescribe (cambiaría esas calificaciones): la deja y lo dice.
     * ================================================================== */
    if ($accion === 'tarea_rubrica') {
        $cmid = isset($_POST['cmid']) ? intval($_POST['cmid']) : 0;
        $titulo = trim((string)(isset($_POST['titulo']) ? $_POST['titulo'] : 'Rúbrica'));
        $crit = json_decode((string)(isset($_POST['criterios']) ? $_POST['criterios'] : '[]'), true);
        $confirmar = (string)(isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        if ($cmid <= 0) { salir_(array('ok' => false, 'error' => 'Falta cmid.')); }
        if (!is_array($crit) || !count($crit)) { salir_(array('ok' => false, 'error' => 'La rúbrica no trae criterios.')); }
        $cm = $DB->get_record('course_modules', array('id' => $cmid), '*', IGNORE_MISSING);
        if (!$cm) { salir_(array('ok' => false, 'error' => 'No existe la tarea ' . $cmid . '.')); }
        if ($confirmar !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'cmid' => $cmid, 'criterios' => count($crit), 'nota' => 'NADA ESCRITO. Para hacerlo: confirmar=1'));
        }
        require_once($CFG->dirroot . '/grade/grading/lib.php');
        $ctx = context_module::instance($cmid);
        $gm = get_grading_manager($ctx, 'mod_assign', 'submissions');
        // ¿Ya hay una rúbrica con calificaciones? Entonces no se toca.
        $areaRec = $DB->get_record('grading_areas', array('contextid' => $ctx->id, 'component' => 'mod_assign', 'areaname' => 'submissions'));
        $areaId = $areaRec ? (int)$areaRec->id : 0;
        if ($areaId) {
            $defs = $DB->get_records('grading_definitions', array('areaid' => $areaId, 'method' => 'rubric'));
            foreach ($defs as $df) {
                if ($DB->record_exists('grading_instances', array('definitionid' => $df->id))) {
                    salir_(array('ok' => true, 'conservada' => true, 'cmid' => $cmid,
                        'nota' => 'La tarea ya tiene alumnos calificados con su rúbrica: no se reescribió.'));
                }
            }
        }
        try {
            $gm->set_active_method('rubric');
            $controller = $gm->get_controller('rubric');
            $criteria = array(); $ci = 0;
            foreach ($crit as $c) {
                $ci++; $levels = array(); $li = 0;
                foreach ((isset($c['niveles']) && is_array($c['niveles'])) ? $c['niveles'] : array() as $n) {
                    $li++;
                    $levels['NEWID' . $li] = array('score' => floatval(isset($n['puntos']) ? $n['puntos'] : 0),
                        'definition' => (string)(isset($n['definicion']) ? $n['definicion'] : ''), 'definitionformat' => FORMAT_MOODLE);
                }
                if (count($levels) < 2) { continue; }
                $criteria['NEWID' . $ci] = array('sortorder' => $ci, 'description' => (string)(isset($c['criterio']) ? $c['criterio'] : ('Criterio ' . $ci)),
                    'descriptionformat' => FORMAT_MOODLE, 'levels' => $levels);
            }
            if (!count($criteria)) { salir_(array('ok' => false, 'error' => 'Ningún criterio trae al menos dos niveles.')); }
            // Si ya había una definición sin calificaciones, se reemplaza completa.
            if ($controller->is_form_defined()) { $controller->delete_definition(); $controller = $gm->get_controller('rubric'); }
            $def = new stdClass();
            $def->name = function_exists('mb_substr') ? mb_substr($titulo, 0, 250, 'UTF-8') : substr($titulo, 0, 250);
            $def->description_editor = array('text' => '', 'format' => FORMAT_HTML);
            $def->status = gradingform_controller::DEFINITION_STATUS_READY;
            $def->rubric = array('criteria' => $criteria, 'options' => array(
                'sortlevelsasc' => 1, 'lockzeropoints' => 1, 'alwaysshowdefinition' => 1, 'showdescriptionteacher' => 1,
                'showdescriptionstudent' => 1, 'showscoreteacher' => 1, 'showscorestudent' => 1, 'enableremarks' => 1, 'showremarksstudent' => 1));
            $controller->update_definition($def);
        } catch (Exception $eR) {
            $d = detalle_excepcion_($eR);
            $d['ok'] = false; $d['accion'] = $accion; $d['cmid'] = $cmid;
            $d['error'] = 'Moodle no pudo guardar la rúbrica: ' . $eR->getMessage();
            salir_($d);
        }
        salir_(array('ok' => true, 'cmid' => $cmid, 'criterios' => count($criteria), 'metodo' => 'rubric',
            'nota' => 'Rúbrica con ' . count($criteria) . ' criterio(s) puesta como método de calificación.'));
    }

    /* ==================================================================
     *  (3-oct-2026) DIAGNÓSTICO DE LA TAREA — SOLO LECTURA.
     *  Dice qué columnas tiene la tabla assign de ESTA instalación y cuáles son obligatorias (NOT NULL, sin valor por omisión),
     *  si «introattachments» existe, con qué colación guarda el texto y, si se da un curso, qué tareas a medias hay en él.
     *  Sirve para ver contra qué se estrella assign::add_instance sin adivinar.
     *  GET tarea_moodle_diagnostico[&courseid=N]
     * ================================================================== */
    if ($accion === 'tarea_moodle_diagnostico') {
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid']) : 0;
        $cols = $DB->get_columns('assign');
        $colsOut = array(); $obligatorias = array();
        if (is_array($cols)) {
            foreach ($cols as $nombreCol => $c) {
                $notNull = !empty($c->not_null); $tieneDef = !empty($c->has_default);
                $colsOut[] = array('nombre' => (string)$nombreCol, 'obligatoria' => $notNull, 'tieneDefault' => $tieneDef,
                    'default' => isset($c->default_value) ? (string)$c->default_value : '');
                if ($notNull && !$tieneDef && $nombreCol !== 'id') { $obligatorias[] = (string)$nombreCol; }
            }
        }
        // Lo que assign::add_instance lee sin comprobar (Moodle 3.x-4.1).
        $leidosSinComprobar = array('name', 'intro', 'introformat', 'preventsubmissionnotingroup', 'submissiondrafts',
            'requiresubmissionstatement', 'sendnotifications', 'sendlatenotifications', 'duedate', 'cutoffdate',
            'gradingduedate', 'allowsubmissionsfromdate', 'grade', 'teamsubmission', 'requireallteammemberssubmit',
            'blindmarking', 'hidegrader');
        $huerfanas = array();
        if ($courseid > 0) {
            $mA = $DB->get_record('modules', array('name' => 'assign'));
            if ($mA) {
                $cms = filas_("SELECT id, section, idnumber, instance FROM {course_modules} WHERE course = ? AND module = ?",
                    array($courseid, $mA->id));
                foreach ($cms as $cm) {
                    if (!$DB->record_exists('assign', array('id' => $cm['instance']))) { $huerfanas[] = $cm; }
                }
            }
        }
        salir_(array('ok' => true, 'moodle' => isset($CFG->release) ? $CFG->release : '',
            'colacion' => isset($CFG->dboptions['dbcollation']) ? (string)$CFG->dboptions['dbcollation'] : '(no definida)',
            'introattachmentsExiste' => is_array($cols) && isset($cols['introattachments']),
            'columnasObligatoriasSinDefault' => $obligatorias,
            'campoQueAddInstanceLeeYEsObligatorio' => array_values(array_intersect($leidosSinComprobar, $obligatorias)),
            'totalColumnas' => count($colsOut), 'columnas' => $colsOut,
            'tareasAMediasEnElCurso' => $huerfanas,
            'nota' => 'Solo lectura. Si «columnasObligatoriasSinDefault» incluye campos que add_instance lee, son los que hay que mandar siempre.'));
    }

    /* ==================================================================
     *  (30-sep-2026) REPARAR NUMSECTIONS — arregla cursos afectados por el
     *  bug de secciones_configurar (ver nota ahí): recalcula el número de
     *  secciones visibles al máximo REAL que existe en course_sections,
     *  sin tocar ningún contenido, banner, ni archivo. Solo lectura de
     *  course_sections + una escritura a course_format_options.
     *  GET/POST curso_reparar_numsections&courseid=N[&confirmar=1]
     * ================================================================== */
    if ($accion === 'curso_reparar_numsections') {
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid'])
            : (isset($_POST['courseid']) ? intval($_POST['courseid']) : 0);
        if ($courseid <= 0) { salir_(array('ok' => false, 'error' => 'Falta courseid.')); }
        $curso = $DB->get_record('course', array('id' => $courseid), '*', IGNORE_MISSING);
        if (!$curso) { salir_(array('ok' => false, 'error' => 'No existe el curso ' . $courseid . '.')); }

        $maxExistente = (int)$DB->get_field_sql(
            "SELECT MAX(section) FROM {course_sections} WHERE course = ?",
            array($courseid));
        $fo = $DB->get_record('course_format_options',
            array('courseid' => $courseid, 'name' => 'numsections'));
        $valorActual = $fo ? (int)$fo->value : null;

        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        if ((string)$confirmar !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'courseid' => $courseid,
                'valorActual' => $valorActual, 'maxSeccionReal' => $maxExistente,
                'nota' => $valorActual === $maxExistente
                    ? 'Ya está correcto, no hace falta nada.'
                    : ('NADA CAMBIADO. Se pondría numsections=' . $maxExistente .
                       ' (estaba en ' . var_export($valorActual, true) . '). Para hacerlo: confirmar=1')));
        }

        if ($fo) {
            $fo->value = $maxExistente;
            $DB->update_record('course_format_options', $fo);
        } else {
            $nuevo = new stdClass();
            $nuevo->courseid = $courseid; $nuevo->format = $curso->format;
            $nuevo->sectionid = 0; $nuevo->name = 'numsections'; $nuevo->value = $maxExistente;
            $DB->insert_record('course_format_options', $nuevo);
        }
        try { rebuild_course_cache($courseid, true); } catch (Exception $eRC) { }
        salir_(array('ok' => true, 'courseid' => $courseid,
            'valorAnterior' => $valorActual, 'valorNuevo' => $maxExistente,
            'nota' => 'numsections corregido a ' . $maxExistente . '. Ningún contenido fue tocado.'));
    }

    /* ==================================================================
     *  (30-sep-2026) DIAGNÓSTICO DE EMERGENCIA — SOLO LECTURA.
     *  Ver si el CONTENIDO (course_modules: páginas, recursos, tareas) de
     *  un curso sigue existiendo en la base de datos aunque las filas de
     *  course_sections que los agrupaban hayan desaparecido. No modifica
     *  nada.
     *  GET curso_diagnostico_emergencia&courseid=N
     * ================================================================== */
    if ($accion === 'curso_diagnostico_emergencia') {
        $courseid = isset($_GET['courseid']) ? intval($_GET['courseid']) : 0;
        if ($courseid <= 0) { salir_(array('ok' => false, 'error' => 'Falta courseid.')); }

        $secciones = filas_(
            "SELECT id, section, name FROM {course_sections} WHERE course = ? ORDER BY section",
            array($courseid));

        $modulos = filas_(
            "SELECT cm.id, cm.section as sectionid, cm.module, m.name as tipo, cm.instance
             FROM {course_modules} cm
             JOIN {modules} m ON m.id = cm.module
             WHERE cm.course = ?
             ORDER BY cm.section, cm.id",
            array($courseid));

        // Nombre real de cada módulo (según su tabla propia), para que se
        // entienda QUÉ es cada uno, no solo su tipo.
        $detalle = array();
        foreach ($modulos as $m) {
            $tabla = $m['tipo'];
            $nombre = '';
            try {
                $fila = $DB->get_record($tabla, array('id' => $m['instance']), 'name');
                if ($fila) { $nombre = $fila->name; }
            } catch (Exception $eN2) { $nombre = '(no se pudo leer el nombre)'; }
            $detalle[] = array('cmid' => (int)$m['id'], 'sectionid' => (int)$m['sectionid'],
                'tipo' => $m['tipo'], 'nombre' => $nombre);
        }

        salir_(array('ok' => true, 'courseid' => $courseid,
            'seccionesExistentes' => $secciones,
            'totalModulos' => count($detalle), 'modulos' => $detalle));
    }

    /* ==================================================================
     *  (30-sep-2026) REPARACIÓN PUNTUAL — curso 648. Recrea las 5 secciones
     *  que desaparecieron y reasigna cada módulo (que sigue existiendo
     *  íntegro) a la semana que le corresponde, según el mapeo confirmado
     *  contra el checklist previo al incidente. Con prueba=1 (default) NO
     *  escribe nada: solo muestra qué haría.
     *  GET/POST curso_reparar_648[&confirmar=1]
     * ================================================================== */
    if ($accion === 'curso_reparar_648') {
        $courseid = 648;
        $curso = $DB->get_record('course', array('id' => $courseid), '*', IGNORE_MISSING);
        if (!$curso) { salir_(array('ok' => false, 'error' => 'No existe el curso 648.')); }

        $plan = array(
            1 => array('nombre' => 'Introducción a la investigación.',
                'cmids' => array(28194,28195,28196,28197,28198,28199,28200,28201,28202,28203)),
            2 => array('nombre' => ' Identificación y formulación del problema de investigación',
                'cmids' => array(28204,28205,28206,28207,28208,28209)),
            3 => array('nombre' => 'Diseño de investigación',
                'cmids' => array(28210,28211,28212,28213,28214,28215,28216,28217,28218,28219,28220,28221,28222,28223,28224)),
            4 => array('nombre' => 'Ética',
                'cmids' => array(28225,28226,28227)),
            5 => array('nombre' => 'Desarrollo de Cartel',
                'cmids' => array(28228,28229,28230,28231,28232)),
        );

        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');

        if ((string)$confirmar !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'courseid' => $courseid,
                'plan' => $plan,
                'nota' => 'NADA ESCRITO. Esto crearía las secciones 1-5 y movería cada cmid listado ' .
                    'a su sección. Para hacerlo de verdad: confirmar=1'));
        }

        require_once($CFG->dirroot . '/course/lib.php');
        $seccionBienvenida = $DB->get_record('course_sections', array('course' => $courseid, 'section' => 0));
        if (!$seccionBienvenida) { salir_(array('ok' => false, 'error' => 'No encontré la sección 0 (Bienvenida).')); }

        $resultado = array();
        foreach ($plan as $num => $info) {
            // 1) Crear la sección si no existe.
            $sec = $DB->get_record('course_sections', array('course' => $courseid, 'section' => $num));
            if (!$sec) {
                $sec = new stdClass();
                $sec->course = $courseid; $sec->section = $num;
                $sec->name = $info['nombre']; $sec->summary = ''; $sec->summaryformat = FORMAT_HTML;
                $sec->sequence = ''; $sec->visible = 1; $sec->timemodified = time();
                $sec->id = $DB->insert_record('course_sections', $sec);
            }
            // 2) Mover cada módulo a esta sección (campo course_modules.section
            //    es el ID de la fila de course_sections, no el número).
            $movidos = array();
            foreach ($info['cmids'] as $cmid) {
                $cm = $DB->get_record('course_modules', array('id' => $cmid, 'course' => $courseid));
                if (!$cm) { continue; }
                $cm->section = $sec->id;
                $DB->update_record('course_modules', $cm);
                $movidos[] = $cmid;
            }
            // 3) La secuencia de la sección: los cmids en el orden del plan.
            $sec->sequence = implode(',', $movidos);
            $DB->update_record('course_sections', $sec);
            $resultado[] = array('seccion' => $num, 'nombre' => $info['nombre'], 'movidos' => $movidos);
        }

        // 4) Quitar de la sección 0 los cmids que ya se movieron a otras.
        $todosMovidos = array();
        foreach ($plan as $info) { $todosMovidos = array_merge($todosMovidos, $info['cmids']); }
        $seqActual = array_filter(explode(',', (string)$seccionBienvenida->sequence));
        $seqNueva = array_diff($seqActual, array_map('strval', $todosMovidos));
        $seccionBienvenida->sequence = implode(',', $seqNueva);
        $DB->update_record('course_sections', $seccionBienvenida);

        // 5) numsections a 5.
        $fo = $DB->get_record('course_format_options', array('courseid' => $courseid, 'name' => 'numsections'));
        if ($fo) { $fo->value = 5; $DB->update_record('course_format_options', $fo); }
        else {
            $nuevo = new stdClass();
            $nuevo->courseid = $courseid; $nuevo->format = $curso->format;
            $nuevo->sectionid = 0; $nuevo->name = 'numsections'; $nuevo->value = 5;
            $DB->insert_record('course_format_options', $nuevo);
        }

        try { rebuild_course_cache($courseid, true); } catch (Exception $eRC2) { }
        salir_(array('ok' => true, 'courseid' => $courseid, 'resultado' => $resultado,
            'nota' => 'Secciones 1-5 recreadas y módulos reasignados.'));
    }

    /* ==================================================================
     *  (30-sep-2026) BORRADO PERMANENTE — curso 648, SOLO las 5 semanas
     *  de contenido académico (39 módulos). Deja la Bienvenida intacta
     *  (Avisos, Conoce a tu profesor, Contenido temático, Plantillas
     *  CESSUM) y las secciones 1-5 creadas pero VACÍAS, listas para
     *  llenarse de nuevo. ESTO ES IRREVERSIBLE: borra en cascada
     *  entregas de alumnos en las tareas. Exige confirmar=1 Y
     *  frase=BORRAR — sin ambas, solo dice qué haría.
     *  GET/POST curso_648_vaciar_semanas[&confirmar=1&frase=BORRAR]
     * ================================================================== */
    if ($accion === 'curso_648_vaciar_semanas') {
        $courseid = 648;
        $curso = $DB->get_record('course', array('id' => $courseid), '*', IGNORE_MISSING);
        if (!$curso) { salir_(array('ok' => false, 'error' => 'No existe el curso 648.')); }

        $nombresSecciones = array(
            1 => 'Introducción a la investigación.',
            2 => ' Identificación y formulación del problema de investigación',
            3 => 'Diseño de investigación',
            4 => 'Ética',
            5 => 'Desarrollo de Cartel',
        );
        // Los 39 cmids de las 5 semanas (confirmados contra el checklist
        // previo al incidente) — excluye los 5 generales de Bienvenida.
        $cmidsABorrar = array(
            28194,28195,28196,28197,28198,28199,28200,28201,28202,28203,
            28204,28205,28206,28207,28208,28209,
            28210,28211,28212,28213,28214,28215,28216,28217,28218,28219,28220,28221,28222,28223,28224,
            28225,28226,28227,
            28228,28229,28230,28231,28232,
        );

        $confirmar = isset($_GET['confirmar']) ? $_GET['confirmar']
            : (isset($_POST['confirmar']) ? $_POST['confirmar'] : '');
        $frase = isset($_GET['frase']) ? $_GET['frase']
            : (isset($_POST['frase']) ? $_POST['frase'] : '');

        if ((string)$confirmar !== '1' || (string)$frase !== 'BORRAR') {
            salir_(array('ok' => true, 'prueba' => true, 'courseid' => $courseid,
                'totalABorrar' => count($cmidsABorrar), 'cmids' => $cmidsABorrar,
                'seccionesQuedanVacias' => $nombresSecciones,
                'nota' => 'NADA BORRADO. Esto eliminaría PERMANENTEMENTE estos ' . count($cmidsABorrar) .
                    ' módulos (y cualquier entrega de alumno en ellos), dejando las secciones 1-5 ' .
                    'creadas pero vacías. Para hacerlo de verdad: confirmar=1&frase=BORRAR'));
        }

        require_once($CFG->dirroot . '/course/lib.php');

        $borrados = array(); $fallos = array();
        foreach ($cmidsABorrar as $cmid) {
            try {
                course_delete_module($cmid);
                $borrados[] = $cmid;
            } catch (Exception $eDel) {
                $fallos[] = array('cmid' => $cmid, 'error' => $eDel->getMessage());
            }
        }

        // Crear las secciones 1-5 vacías, listas para llenarse de nuevo.
        foreach ($nombresSecciones as $num => $nombre) {
            $sec = $DB->get_record('course_sections', array('course' => $courseid, 'section' => $num));
            if (!$sec) {
                $sec = new stdClass();
                $sec->course = $courseid; $sec->section = $num;
                $sec->name = $nombre; $sec->summary = ''; $sec->summaryformat = FORMAT_HTML;
                $sec->sequence = ''; $sec->visible = 1; $sec->timemodified = time();
                $DB->insert_record('course_sections', $sec);
            } else {
                $sec->sequence = ''; $sec->timemodified = time();
                $DB->update_record('course_sections', $sec);
            }
        }

        $fo = $DB->get_record('course_format_options', array('courseid' => $courseid, 'name' => 'numsections'));
        if ($fo) { $fo->value = 5; $DB->update_record('course_format_options', $fo); }
        else {
            $nuevo = new stdClass();
            $nuevo->courseid = $courseid; $nuevo->format = $curso->format;
            $nuevo->sectionid = 0; $nuevo->name = 'numsections'; $nuevo->value = 5;
            $DB->insert_record('course_format_options', $nuevo);
        }

        try { rebuild_course_cache($courseid, true); } catch (Exception $eRC3) { }
        salir_(array('ok' => true, 'courseid' => $courseid,
            'borrados' => count($borrados), 'fallos' => $fallos,
            'nota' => count($borrados) . ' módulo(s) borrado(s) permanentemente. Secciones 1-5 creadas y vacías.'));
    }

    // =====================================================================
    //  (4-oct-2026) CENTRO DE AULAS · MOMENTO 0 — operaciones nuevas.
    //  Todas responden VISTA PREVIA si no llevan confirmar=1 (las de
    //  escritura) y nunca tocan cuentas de administrador.
    // =====================================================================
    $confirmarM0 = isset($_GET['confirmar']) ? (string)$_GET['confirmar'] : (isset($_POST['confirmar']) ? (string)$_POST['confirmar'] : '');
    $courseidM0 = isset($_GET['courseid']) ? intval($_GET['courseid']) : (isset($_POST['courseid']) ? intval($_POST['courseid']) : 0);
    $usuarioM0 = function ($email) use ($DB) {
        if (!$email) { salir_(array('ok' => false, 'error' => 'Falta email.')); }
        $u = $DB->get_record('user', array('email' => $email, 'deleted' => 0));
        if (!$u) { salir_(array('ok' => false, 'error' => 'No existe un usuario con ese correo en el Aula.')); }
        if (function_exists('is_siteadmin') && is_siteadmin($u->id)) {
            salir_(array('ok' => false, 'error' => 'No se permite modificar una cuenta de administrador.'));
        }
        return $u;
    };
    $cursoM0 = function ($courseid) use ($DB) {
        if ($courseid <= 1) { salir_(array('ok' => false, 'error' => 'Falta courseid.')); }
        $c = $DB->get_record('course', array('id' => $courseid));
        if (!$c) { salir_(array('ok' => false, 'error' => 'No existe el curso ' . $courseid . '.')); }
        return $c;
    };

    // ROLES — los roles del sitio (id y nombre corto).
    if ($accion === 'roles') {
        $out = array();
        foreach ($DB->get_records('role', null, 'sortorder ASC', 'id, shortname, name') as $r) {
            $out[] = array('id' => (int)$r->id, 'shortname' => $r->shortname, 'nombre' => $r->name);
        }
        salir_(array('ok' => true, 'roles' => $out));
    }

    // PARTICIPANTES — quién está en un curso, con sus roles (lectura).
    if ($accion === 'participantes') {
        $c = $cursoM0($courseidM0);
        $ctx = context_course::instance($c->id);
        $usuarios = get_enrolled_users($ctx, '', 0, 'u.id, u.email, u.firstname, u.lastname, u.suspended, u.lastaccess', null, 0, 0, false);
        $out = array();
        foreach ($usuarios as $u) {
            $roles = array();
            foreach (get_user_roles($ctx, $u->id, false) as $ra) { $roles[] = $ra->shortname; }
            $out[] = array('email' => strtolower($u->email), 'nombre' => trim($u->firstname . ' ' . $u->lastname),
                'roles' => $roles, 'suspendido' => ((int)$u->suspended === 1),
                'ultimoAcceso' => $u->lastaccess ? date('d/m/Y H:i', $u->lastaccess) : '');
        }
        salir_(array('ok' => true, 'courseid' => (int)$c->id, 'curso' => $c->fullname, 'visible' => ((int)$c->visible === 1),
            'total' => count($out), 'participantes' => $out));
    }

    // PARTICIPANTES EN LOTE (Momento 1) — varias aulas en una sola llamada: datos del curso y quién está, con roles.
    if ($accion === 'participantes_lote') {
        $ids = isset($_GET['courseids']) ? array_slice(array_values(array_unique(array_filter(array_map('intval', explode(',', $_GET['courseids'])), function ($x) { return $x > 1; }))), 0, 200) : array();
        if (!$ids) { salir_(array('ok' => false, 'error' => 'Falta courseids (lista separada por comas).')); }
        $out = array();
        foreach ($ids as $cid) {
            $c = $DB->get_record('course', array('id' => $cid), 'id, fullname, shortname, visible, startdate, enddate');
            if (!$c) { $out[] = array('courseid' => $cid, 'existe' => false); continue; }
            $ctx = context_course::instance($c->id);
            $ps = array();
            foreach (get_enrolled_users($ctx, '', 0, 'u.id, u.email, u.firstname, u.lastname, u.suspended, u.lastaccess', null, 0, 0, false) as $u) {
                $roles = array();
                foreach (get_user_roles($ctx, $u->id, false) as $ra) { $roles[] = $ra->shortname; }
                $la = $DB->get_field('user_lastaccess', 'timeaccess', array('userid' => $u->id, 'courseid' => $c->id));
                $ps[] = array('email' => strtolower($u->email), 'nombre' => trim($u->firstname . ' ' . $u->lastname), 'roles' => $roles,
                    'suspendido' => ((int)$u->suspended === 1), 'ultimoAccesoAula' => $la ? date('Y-m-d H:i', $la) : '');
            }
            $recursos = (int)$DB->count_records_sql("SELECT COUNT(cm.id) FROM {course_modules} cm WHERE cm.course = ? AND cm.deletioninprogress = 0", array($c->id));
            $semanas = (int)$DB->count_records_sql("SELECT COUNT(cs.id) FROM {course_sections} cs WHERE cs.course = ? AND cs.section > 0", array($c->id));
            $out[] = array('courseid' => (int)$c->id, 'existe' => true, 'curso' => $c->fullname, 'visible' => ((int)$c->visible === 1),
                'inicio' => $c->startdate ? date('Y-m-d', $c->startdate) : '', 'fin' => (isset($c->enddate) && $c->enddate) ? date('Y-m-d', $c->enddate) : '',
                'recursos' => $recursos, 'semanas' => $semanas, 'participantes' => $ps);
        }
        salir_(array('ok' => true, 'cursos' => $out));
    }

    // =====================================================================
    //  (4-oct-2026) CENTRO DE AULAS · MOMENTO 4 — lo académico de un aula.
    //  aula_academico: tareas (fechas, entregas, sin calificar, quién falta,
    //  ampliaciones de plazo), dudas sin respuesta y calificación final de
    //  cada alumno en Moodle. Solo lectura.
    // =====================================================================
    if ($accion === 'aula_academico') {
        $c = $cursoM0($courseidM0);
        $ctx = context_course::instance($c->id);
        $alumnos = array();
        foreach (get_enrolled_users($ctx, '', 0, 'u.id, u.email, u.firstname, u.lastname', null, 0, 0, true) as $u) {
            $esAl = false;
            foreach (get_user_roles($ctx, $u->id, false) as $ra) { if ($ra->shortname === 'student') { $esAl = true; } }
            if ($esAl) { $alumnos[(int)$u->id] = array('email' => strtolower($u->email), 'nombre' => trim($u->firstname . ' ' . $u->lastname)); }
        }
        $tareas = array();
        $rows = $DB->get_records_sql("SELECT a.id, a.name, a.duedate, a.cutoffdate, cm.id AS cmid, cm.visible
              FROM {assign} a JOIN {course_modules} cm ON cm.instance = a.id
              JOIN {modules} md ON md.id = cm.module AND md.name = 'assign'
             WHERE a.course = ? AND cm.deletioninprogress = 0 ORDER BY a.duedate ASC, a.id ASC", array($c->id));
        foreach ($rows as $a) {
            $ent = array(); $sinCal = 0;
            $rsE = $DB->get_recordset_sql("SELECT s.id, s.userid, s.attemptnumber,
                       (SELECT g.grade FROM {assign_grades} g WHERE g.assignment = s.assignment AND g.userid = s.userid AND g.attemptnumber = s.attemptnumber) AS nota
                  FROM {assign_submission} s WHERE s.assignment = ? AND s.latest = 1 AND s.status = 'submitted' AND s.userid > 0", array($a->id));
            foreach ($rsE as $s) {
                $ent[(int)$s->userid] = true;
                if ($s->nota === null || (float)$s->nota < 0) { $sinCal++; }
            }
            $rsE->close();
            $pro = array();
            foreach ($DB->get_records_select('assign_user_flags', 'assignment = ? AND extensionduedate > 0', array($a->id), '', 'userid, extensionduedate') as $f) {
                if (isset($alumnos[(int)$f->userid])) { $pro[$alumnos[(int)$f->userid]['email']] = date('Y-m-d H:i', $f->extensionduedate); }
            }
            $faltan = array();
            foreach ($alumnos as $uid => $al) { if (!isset($ent[$uid])) { $faltan[] = $al; } }
            $tareas[] = array('assignid' => (int)$a->id, 'cmid' => (int)$a->cmid, 'nombre' => $a->name, 'visible' => ((int)$a->visible === 1),
                'vence' => $a->duedate ? date('Y-m-d H:i', $a->duedate) : '', 'corte' => $a->cutoffdate ? date('Y-m-d H:i', $a->cutoffdate) : '',
                'vencida' => ($a->duedate && $a->duedate < time()), 'entregadas' => count(array_intersect_key($ent, $alumnos)), 'sinCalificar' => $sinCal,
                'faltan' => $faltan, 'prorrogas' => $pro);
        }
        // Dudas sin respuesta: discusiones con un solo mensaje en foros «Dudas…» del curso.
        $dudas = array();
        foreach ($DB->get_records_sql("SELECT d.id, d.name, d.timemodified, u.firstname, u.lastname,
                   (SELECT COUNT(p.id) FROM {forum_posts} p WHERE p.discussion = d.id) AS mensajes
              FROM {forum_discussions} d JOIN {forum} f ON f.id = d.forum JOIN {user} u ON u.id = d.userid
             WHERE f.course = :cid AND " . $DB->sql_like('f.name', ':pat', false) . " ORDER BY d.timemodified ASC", array('cid' => $c->id, 'pat' => 'Dudas%')) as $d) {
            if ((int)$d->mensajes <= 1) { $dudas[] = array('asunto' => $d->name, 'autor' => trim($d->firstname . ' ' . $d->lastname), 'desde' => date('Y-m-d H:i', $d->timemodified)); }
        }
        // Calificación final de cada alumno (total del curso en el libro de calificaciones).
        $finales = array(); $max = null;
        $gi = $DB->get_record('grade_items', array('courseid' => $c->id, 'itemtype' => 'course'));
        if ($gi) {
            $max = (float)$gi->grademax;
            foreach ($DB->get_records('grade_grades', array('itemid' => $gi->id), '', 'userid, finalgrade') as $g) {
                if (isset($alumnos[(int)$g->userid]) && $g->finalgrade !== null) { $finales[$alumnos[(int)$g->userid]['email']] = round((float)$g->finalgrade, 2); }
            }
        }
        salir_(array('ok' => true, 'courseid' => (int)$c->id, 'curso' => $c->fullname, 'alumnos' => array_values($alumnos),
            'tareas' => $tareas, 'dudas' => $dudas, 'finales' => $finales, 'escalaFinal' => $max));
    }

    // PRÓRROGA — ampliación de plazo nativa de Moodle para UNA persona en UNA tarea (assign_user_flags.extensionduedate).
    if ($accion === 'prorroga') {
        $assignid = isset($_GET['assignid']) ? intval($_GET['assignid']) : 0;
        $hasta = isset($_GET['hasta']) ? trim($_GET['hasta']) : '';
        $a = $assignid > 0 ? $DB->get_record('assign', array('id' => $assignid)) : null;
        if (!$a) { salir_(array('ok' => false, 'error' => 'Falta assignid válido.')); }
        $u = $usuarioM0($email);
        $ts = $hasta !== '' ? strtotime(str_replace('T', ' ', $hasta) . (strlen($hasta) <= 10 ? ' 23:59:00' : '')) : 0;
        if (!$ts) { salir_(array('ok' => false, 'error' => 'Falta hasta (AAAA-MM-DD o AAAA-MM-DD HH:MM).')); }
        if ($a->duedate && $ts <= $a->duedate) { salir_(array('ok' => false, 'error' => 'La nueva fecha debe ser posterior a la fecha límite de la tarea (' . date('Y-m-d H:i', $a->duedate) . ').')); }
        $fl = $DB->get_record('assign_user_flags', array('assignment' => $a->id, 'userid' => $u->id));
        $antes = ($fl && $fl->extensionduedate) ? date('Y-m-d H:i', $fl->extensionduedate) : '';
        if ($confirmarM0 !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'tarea' => $a->name, 'email' => $email, 'vence' => $a->duedate ? date('Y-m-d H:i', $a->duedate) : '',
                'corte' => $a->cutoffdate ? date('Y-m-d H:i', $a->cutoffdate) : '', 'prorrogaActual' => $antes, 'quedaria' => date('Y-m-d H:i', $ts),
                'nota' => 'VISTA PREVIA. Para hacerlo, agrega confirmar=1.'));
        }
        $hecho = false; $via = '';
        try {   // primero por la API de Moodle (eventos y calendario), como administrador
            require_once($CFG->dirroot . '/mod/assign/locallib.php');
            $cm = get_coursemodule_from_instance('assign', $a->id, 0, false, MUST_EXIST);
            \core\session\manager::set_user(get_admin());
            $obj = new assign(context_module::instance($cm->id), $cm, get_course($a->course));
            $hecho = (bool)$obj->save_user_extension($u->id, $ts); $via = 'api';
        } catch (Exception $eApi) { $hecho = false; }
        if (!$hecho) {   // respaldo: el mismo registro que escribe Moodle
            if ($fl) { $fl->extensionduedate = $ts; $DB->update_record('assign_user_flags', $fl); }
            else { $DB->insert_record('assign_user_flags', (object)array('userid' => $u->id, 'assignment' => $a->id, 'locked' => 0, 'mailed' => 0,
                'extensionduedate' => $ts, 'workflowstate' => '', 'allocatedmarker' => 0)); }
            $hecho = true; $via = 'registro';
        }
        salir_(array('ok' => $hecho, 'tarea' => $a->name, 'email' => $email, 'antes' => $antes, 'hasta' => date('Y-m-d H:i', $ts), 'via' => $via));
    }

    // =====================================================================
    //  (4-oct-2026) MESA DE REVISIÓN · R3 — CALIFICAR DESDE LA APP.
    //  calificacion_estado: lo que hay hoy (calificación, retroalimentación,
    //  rúbrica con sus id, si la tarea avisa al alumno, flujo de calificación).
    //  calificar (POST): escribe como lo haría Moodle (assign::save_grade):
    //  calificación, retroalimentación y niveles de la rúbrica.
    //  Los parámetros se leen de POST o de GET (la retro puede ser larga).
    // =====================================================================
    if ($accion === 'calificacion_estado' || $accion === 'calificar') {
        $Q = function ($k) { return isset($_POST[$k]) ? $_POST[$k] : (isset($_GET[$k]) ? $_GET[$k] : ''); };
        $assignidC = intval($Q('assignid'));
        $emailC = strtolower(trim((string)$Q('email')));
        $a = $assignidC > 0 ? $DB->get_record('assign', array('id' => $assignidC)) : null;
        if (!$a) { salir_(array('ok' => false, 'error' => 'Falta assignid válido.')); }
        $u = $usuarioM0($emailC);
        require_once($CFG->dirroot . '/mod/assign/locallib.php');
        require_once($CFG->dirroot . '/grade/grading/lib.php');
        $cm = get_coursemodule_from_instance('assign', $a->id, 0, false, MUST_EXIST);
        $ctxA = context_module::instance($cm->id);
        \core\session\manager::set_user(get_admin());
        $obj = new assign($ctxA, $cm, get_course($a->course));
        // Rúbrica activa, con sus id
        $rubrica = array(); $metodo = '';
        $gm = get_grading_manager($ctxA, 'mod_assign', 'submissions');
        $metodo = (string)$gm->get_active_method();
        $ctrl = $metodo ? $gm->get_controller($metodo) : null;
        if ($metodo === 'rubric' && $ctrl && $ctrl->is_form_available()) {
            $def = $ctrl->get_definition();
            foreach ($def->rubric_criteria as $cid => $cr) {
                $niv = array();
                foreach ($cr['levels'] as $lid => $lv) { $niv[] = array('id' => (int)$lid, 'puntos' => (float)$lv['score'], 'descripcion' => trim(strip_tags($lv['definition']))); }
                usort($niv, function ($x, $y) { return $x['puntos'] <=> $y['puntos']; });
                $rubrica[] = array('id' => (int)$cid, 'criterio' => trim(strip_tags($cr['description'])), 'niveles' => $niv);
            }
        }
        $g = $obj->get_user_grade($u->id, false);
        $fb = '';
        if ($g) { $fc = $DB->get_record('assignfeedback_comments', array('grade' => $g->id), 'commenttext', IGNORE_MULTIPLE); if ($fc) { $fb = (string)$fc->commenttext; } }
        $estado = array('ok' => true, 'tarea' => $a->name, 'alumno' => fullname($u), 'calificacionMaxima' => (float)$a->grade,
            'calificacionActual' => ($g && $g->grade !== null && (float)$g->grade >= 0) ? round((float)$g->grade, 2) : null,
            'retroActual' => trim(html_entity_decode(strip_tags(str_replace(array('<br>', '<br />', '</p>'), "\n", $fb)), ENT_QUOTES, 'UTF-8')),
            'metodo' => $metodo ?: 'directo', 'rubrica' => $rubrica,
            'avisaAlAlumno' => isset($a->sendstudentnotifications) ? ((int)$a->sendstudentnotifications === 1) : true,
            'flujoDeCalificacion' => !empty($a->markingworkflow));
        if ($accion === 'calificacion_estado') { salir_($estado); }

        // ── calificar ──
        if ((string)$Q('confirmar') !== '1') { salir_(array('ok' => false, 'error' => 'Falta confirmacion (confirmar=1).')); }
        if ((float)$a->grade <= 0) { salir_(array('ok' => false, 'error' => 'La tarea no se califica con puntos (escala o sin calificación): califícala en el aula.')); }
        $retro = (string)$Q('retro');
        $data = new stdClass();
        $data->attemptnumber = -1;
        $data->sendstudentnotifications = ((string)$Q('notificar') === '1') ? 1 : 0;
        $data->assignfeedbackcomments_editor = array('text' => $retro === '' ? '' : nl2br(s($retro)), 'format' => FORMAT_HTML);
        if (!empty($a->markingworkflow)) { $data->workflowstate = ASSIGN_MARKING_WORKFLOW_STATE_RELEASED; }
        $niveles = json_decode((string)$Q('niveles'), true);   // {criterioId: nivelId}
        if ($metodo === 'rubric' && $rubrica) {
            if (!is_array($niveles) || count($niveles) < count($rubrica)) { salir_(array('ok' => false, 'error' => 'La tarea tiene rúbrica: falta elegir el nivel de cada criterio.')); }
            $crit = array();
            foreach ($rubrica as $cr) {
                $lid = isset($niveles[(string)$cr['id']]) ? intval($niveles[(string)$cr['id']]) : 0;
                $valido = false; foreach ($cr['niveles'] as $nv) { if ($nv['id'] === $lid) { $valido = true; } }
                if (!$valido) { salir_(array('ok' => false, 'error' => 'Nivel no válido en el criterio «' . $cr['criterio'] . '».')); }
                $crit[$cr['id']] = array('levelid' => $lid, 'remark' => '');
            }
            $data->advancedgrading = array('criteria' => $crit);
            $data->grade = 0;   // la calcula la rúbrica
        } else {
            $cal = (float)str_replace(',', '.', (string)$Q('calificacion'));
            if ($cal < 0 || $cal > (float)$a->grade) { salir_(array('ok' => false, 'error' => 'La calificación debe estar entre 0 y ' . (float)$a->grade . '.')); }
            $data->grade = $cal;
        }
        $obj->save_grade($u->id, $data);
        $g2 = $obj->get_user_grade($u->id, false);
        salir_(array('ok' => true, 'tarea' => $a->name, 'email' => $emailC,
            'calificacion' => ($g2 && $g2->grade !== null) ? round((float)$g2->grade, 2) : null, 'calificacionMaxima' => (float)$a->grade,
            'avisado' => $data->sendstudentnotifications === 1, 'liberada' => !empty($a->markingworkflow)));
    }

    // =====================================================================
    //  (4-oct-2026) MESA DE REVISIÓN · R4 — ARCHIVO DE RETROALIMENTACIÓN.
    //  retro_archivo (POST): adjunta el PDF anotado por el docente como
    //  «archivo de retroalimentación» de la entrega (assignfeedback_file),
    //  el que el alumno ve junto a su calificación. Si la tarea no tenía
    //  activada la retroalimentación con archivo, se activa y se avisa.
    // =====================================================================
    if ($accion === 'retro_archivo') {
        $Q = function ($k) { return isset($_POST[$k]) ? $_POST[$k] : (isset($_GET[$k]) ? $_GET[$k] : ''); };
        if ((string)$Q('confirmar') !== '1') { salir_(array('ok' => false, 'error' => 'Falta confirmacion (confirmar=1).')); }
        $a = $DB->get_record('assign', array('id' => intval($Q('assignid'))));
        if (!$a) { salir_(array('ok' => false, 'error' => 'Falta assignid válido.')); }
        $u = $usuarioM0(strtolower(trim((string)$Q('email'))));
        $bytes = base64_decode((string)$Q('datos_b64'), true);
        if ($bytes === false || strlen($bytes) < 100) { salir_(array('ok' => false, 'error' => 'El archivo llegó vacío o dañado.')); }
        if (substr($bytes, 0, 4) !== '%PDF') { salir_(array('ok' => false, 'error' => 'Solo se adjuntan archivos PDF.')); }
        if (strlen($bytes) > 15 * 1024 * 1024) { salir_(array('ok' => false, 'error' => 'El PDF anotado pasa de 15 MB.')); }
        $nombre = clean_filename(trim((string)$Q('nombre')) ?: 'retroalimentacion.pdf');
        if (strtolower(substr($nombre, -4)) !== '.pdf') { $nombre .= '.pdf'; }
        require_once($CFG->dirroot . '/mod/assign/locallib.php');
        $cm = get_coursemodule_from_instance('assign', $a->id, 0, false, MUST_EXIST);
        $ctxA = context_module::instance($cm->id);
        \core\session\manager::set_user(get_admin());
        $obj = new assign($ctxA, $cm, get_course($a->course));
        // La tarea debe tener activada la retroalimentación con archivo
        $activada = false;
        $cfg = $DB->get_record('assign_plugin_config', array('assignment' => $a->id, 'plugin' => 'file', 'subtype' => 'assignfeedback', 'name' => 'enabled'));
        if (!$cfg) { $DB->insert_record('assign_plugin_config', (object)array('assignment' => $a->id, 'plugin' => 'file', 'subtype' => 'assignfeedback', 'name' => 'enabled', 'value' => '1')); $activada = true; }
        else if ((string)$cfg->value !== '1') { $cfg->value = '1'; $DB->update_record('assign_plugin_config', $cfg); $activada = true; }
        $g = $obj->get_user_grade($u->id, true);   // la crea si aún no hay calificación
        $fs = get_file_storage();
        $prev = $fs->get_file($ctxA->id, 'assignfeedback_file', 'feedback_files', $g->id, '/', $nombre);
        if ($prev) { $prev->delete(); }
        $fs->create_file_from_string(array('contextid' => $ctxA->id, 'component' => 'assignfeedback_file', 'filearea' => 'feedback_files',
            'itemid' => $g->id, 'filepath' => '/', 'filename' => $nombre, 'userid' => get_admin()->id), $bytes);
        $num = count($fs->get_area_files($ctxA->id, 'assignfeedback_file', 'feedback_files', $g->id, 'id', false));
        $fr = $DB->get_record('assignfeedback_file', array('grade' => $g->id));
        if ($fr) { $fr->numfiles = $num; $DB->update_record('assignfeedback_file', $fr); }
        else { $DB->insert_record('assignfeedback_file', (object)array('assignment' => $a->id, 'grade' => $g->id, 'numfiles' => $num)); }
        salir_(array('ok' => true, 'tarea' => $a->name, 'email' => $u->email, 'archivo' => $nombre, 'bytes' => strlen($bytes),
            'archivosDeRetro' => $num, 'seActivoEnLaTarea' => $activada));
    }

    // =====================================================================
    //  (4-oct-2026) FOTO DE PERFIL EN EL AULA — la foto de la credencial
    //  como imagen de perfil del usuario en Moodle (process_new_icon: la
    //  recorta y genera sus tamaños, como al subirla desde «Editar perfil»).
    //  POST: email, datos_b64, mime, confirmar=1. No avisa al usuario.
    // =====================================================================
    if ($accion === 'foto_perfil') {
        $Q = function ($k) { return isset($_POST[$k]) ? $_POST[$k] : (isset($_GET[$k]) ? $_GET[$k] : ''); };
        if ((string)$Q('confirmar') !== '1') { salir_(array('ok' => false, 'error' => 'Falta confirmacion (confirmar=1).')); }
        $u = $usuarioM0(strtolower(trim((string)$Q('email'))));
        $bytes = base64_decode((string)$Q('datos_b64'), true);
        if ($bytes === false || strlen($bytes) < 200) { salir_(array('ok' => false, 'error' => 'La foto llegó vacía o dañada.')); }
        if (strlen($bytes) > 8 * 1024 * 1024) { salir_(array('ok' => false, 'error' => 'La foto pasa de 8 MB.')); }
        $mime = strtolower((string)$Q('mime'));
        $ext = (strpos($mime, 'png') !== false) ? 'png' : ((strpos($mime, 'gif') !== false) ? 'gif' : 'jpg');
        $info = @getimagesizefromstring($bytes);
        if (!$info || !in_array($info[2], array(IMAGETYPE_JPEG, IMAGETYPE_PNG, IMAGETYPE_GIF))) {
            salir_(array('ok' => false, 'error' => 'Formato de imagen no compatible con el aula (usa JPG o PNG).'));
        }
        require_once($CFG->libdir . '/gdlib.php');
        $dir = make_request_directory();
        $tmp = $dir . '/foto.' . $ext;
        file_put_contents($tmp, $bytes);
        $ctxU = context_user::instance($u->id, MUST_EXIST);
        $pic = (int)process_new_icon($ctxU, 'user', 'icon', 0, $tmp);
        if (!$pic) { salir_(array('ok' => false, 'error' => 'El aula no pudo procesar la imagen.')); }
        $DB->set_field('user', 'picture', $pic, array('id' => $u->id));
        \core\event\user_updated::create_from_userid($u->id)->trigger();
        salir_(array('ok' => true, 'email' => strtolower($u->email), 'userid' => (int)$u->id, 'ancho' => (int)$info[0], 'alto' => (int)$info[1]));
    }

    // DESMATRICULAR — saca a una persona de un curso (todas sus formas de inscripción en ese curso).
    if ($accion === 'desmatricular') {
        $c = $cursoM0($courseidM0); $u = $usuarioM0($email);
        require_once($CFG->dirroot . '/lib/enrollib.php');
        $instancias = array();
        foreach (enrol_get_instances($c->id, false) as $inst) {
            if ($DB->record_exists('user_enrolments', array('enrolid' => $inst->id, 'userid' => $u->id))) { $instancias[] = $inst; }
        }
        if (!$instancias) { salir_(array('ok' => true, 'sinCambio' => true, 'nota' => 'No estaba inscrito en ese curso.', 'courseid' => (int)$c->id, 'email' => $email)); }
        if ($confirmarM0 !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'curso' => $c->fullname, 'email' => $email,
                'inscripciones' => array_map(function ($i) { return $i->enrol; }, $instancias),
                'nota' => 'VISTA PREVIA. Se le sacaria del curso. Para hacerlo, agrega confirmar=1.'));
        }
        $hechas = array();
        foreach ($instancias as $inst) {
            $plugin = enrol_get_plugin($inst->enrol);
            if ($plugin) { $plugin->unenrol_user($inst, $u->id); $hechas[] = $inst->enrol; }
        }
        salir_(array('ok' => true, 'courseid' => (int)$c->id, 'email' => $email, 'desmatriculado' => $hechas));
    }

    // ROL EN UN CURSO — asigna o quita un rol (student, teacher, editingteacher) dentro de un curso.
    if ($accion === 'rol_curso') {
        $c = $cursoM0($courseidM0); $u = $usuarioM0($email);
        $rol = isset($_GET['rol']) ? trim($_GET['rol']) : '';
        $modo = isset($_GET['modo']) ? trim($_GET['modo']) : 'asignar';
        if (!in_array($rol, array('student', 'teacher', 'editingteacher'), true)) {
            salir_(array('ok' => false, 'error' => 'rol debe ser student, teacher o editingteacher.'));
        }
        $r = $DB->get_record('role', array('shortname' => $rol));
        if (!$r) { salir_(array('ok' => false, 'error' => 'El rol ' . $rol . ' no existe en el sitio.')); }
        $ctx = context_course::instance($c->id);
        $tiene = $DB->record_exists('role_assignments', array('roleid' => $r->id, 'userid' => $u->id, 'contextid' => $ctx->id));
        if ($confirmarM0 !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'curso' => $c->fullname, 'email' => $email, 'rol' => $rol, 'modo' => $modo,
                'yaLoTiene' => $tiene, 'nota' => 'VISTA PREVIA. Para hacerlo, agrega confirmar=1.'));
        }
        if ($modo === 'quitar') {
            if ($tiene) { role_unassign($r->id, $u->id, $ctx->id); }
            salir_(array('ok' => true, 'courseid' => (int)$c->id, 'email' => $email, 'rol' => $rol, 'quitado' => $tiene));
        }
        require_once($CFG->dirroot . '/lib/enrollib.php');
        if (!is_enrolled($ctx, $u->id)) {
            $enrol = enrol_get_plugin('manual');
            $inst = $DB->get_record('enrol', array('courseid' => $c->id, 'enrol' => 'manual'));
            if (!$inst) { $iid = $enrol->add_default_instance($c); if (!$iid) { $iid = $enrol->add_instance($c); } $inst = $DB->get_record('enrol', array('id' => $iid)); }
            $enrol->enrol_user($inst, $u->id, $r->id);
        } else if (!$tiene) {
            role_assign($r->id, $u->id, $ctx->id);
        }
        salir_(array('ok' => true, 'courseid' => (int)$c->id, 'email' => $email, 'rol' => $rol, 'asignado' => true, 'yaLoTenia' => $tiene));
    }

    // VISIBILIDAD — muestra u oculta un curso a los alumnos.
    if ($accion === 'curso_visibilidad') {
        $c = $cursoM0($courseidM0);
        $visible = isset($_GET['visible']) ? ((string)$_GET['visible'] === '1' ? 1 : 0) : -1;
        if ($visible < 0) { salir_(array('ok' => false, 'error' => 'Falta visible=1 o visible=0.')); }
        if ((int)$c->visible === $visible) { salir_(array('ok' => true, 'sinCambio' => true, 'courseid' => (int)$c->id, 'visible' => ($visible === 1))); }
        if ($confirmarM0 !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'curso' => $c->fullname, 'visibleAhora' => ((int)$c->visible === 1), 'quedaria' => ($visible === 1),
                'nota' => 'VISTA PREVIA. Para hacerlo, agrega confirmar=1.'));
        }
        require_once($CFG->dirroot . '/course/lib.php');
        if (function_exists('course_change_visibility')) { course_change_visibility($c->id, $visible === 1); }
        else { $DB->set_field('course', 'visible', $visible, array('id' => $c->id)); rebuild_course_cache($c->id, true); }
        salir_(array('ok' => true, 'courseid' => (int)$c->id, 'visible' => ($visible === 1)));
    }

    // FECHAS — inicio y fin del curso (AAAA-MM-DD).
    if ($accion === 'curso_fechas') {
        $c = $cursoM0($courseidM0);
        $ini = isset($_GET['inicio']) ? trim($_GET['inicio']) : '';
        $fin = isset($_GET['fin']) ? trim($_GET['fin']) : '';
        $tIni = $ini !== '' ? strtotime($ini . ' 00:00:00') : 0;
        $tFin = $fin !== '' ? strtotime($fin . ' 23:59:00') : 0;
        if (($ini !== '' && !$tIni) || ($fin !== '' && !$tFin)) { salir_(array('ok' => false, 'error' => 'Las fechas van como AAAA-MM-DD.')); }
        if (!$tIni && !$tFin) { salir_(array('ok' => false, 'error' => 'Falta inicio o fin.')); }
        if ($tIni && $tFin && $tFin <= $tIni) { salir_(array('ok' => false, 'error' => 'El fin debe ser posterior al inicio.')); }
        $antes = array('inicio' => $c->startdate ? date('Y-m-d', $c->startdate) : '', 'fin' => (isset($c->enddate) && $c->enddate) ? date('Y-m-d', $c->enddate) : '');
        if ($confirmarM0 !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'curso' => $c->fullname, 'antes' => $antes,
                'quedaria' => array('inicio' => $tIni ? date('Y-m-d', $tIni) : $antes['inicio'], 'fin' => $tFin ? date('Y-m-d', $tFin) : $antes['fin']),
                'nota' => 'VISTA PREVIA. Para hacerlo, agrega confirmar=1.'));
        }
        $rec = (object)array('id' => $c->id);
        if ($tIni) { $rec->startdate = $tIni; }
        if ($tFin) { $rec->enddate = $tFin; }
        $DB->update_record('course', $rec);
        rebuild_course_cache($c->id, true);
        salir_(array('ok' => true, 'courseid' => (int)$c->id, 'antes' => $antes, 'inicio' => $tIni ? date('Y-m-d', $tIni) : $antes['inicio'], 'fin' => $tFin ? date('Y-m-d', $tFin) : $antes['fin']));
    }

    // GRUPO INTERNO DE MOODLE — crea (si no existe) un grupo dentro del curso y, si se indica, agrega a una persona.
    if ($accion === 'grupo_moodle') {
        $c = $cursoM0($courseidM0);
        $nombre = isset($_GET['nombre']) ? trim($_GET['nombre']) : '';
        if ($nombre === '') { salir_(array('ok' => false, 'error' => 'Falta nombre del grupo.')); }
        require_once($CFG->dirroot . '/group/lib.php');
        $g = $DB->get_record('groups', array('courseid' => $c->id, 'name' => $nombre));
        $u = $email ? $usuarioM0($email) : null;
        if ($confirmarM0 !== '1') {
            salir_(array('ok' => true, 'prueba' => true, 'curso' => $c->fullname, 'grupo' => $nombre, 'existe' => (bool)$g,
                'agregaria' => $u ? $email : '', 'nota' => 'VISTA PREVIA. Para hacerlo, agrega confirmar=1.'));
        }
        if (!$g) { $gid = groups_create_group((object)array('courseid' => $c->id, 'name' => $nombre)); } else { $gid = (int)$g->id; }
        $agregado = false;
        if ($u) {
            if (!is_enrolled(context_course::instance($c->id), $u->id)) { salir_(array('ok' => false, 'error' => 'Esa persona no esta inscrita en el curso.', 'grupoId' => (int)$gid)); }
            $agregado = groups_add_member($gid, $u->id);
        }
        salir_(array('ok' => true, 'courseid' => (int)$c->id, 'grupoId' => (int)$gid, 'creado' => !$g, 'agregado' => (bool)$agregado));
    }

    if ($accion === 'ping_version') {
        salir_(array('ok' => true,
            'version' => '2026-10-04 · foto_perfil (credencial → perfil del aula) + Mesa de revisión R1-R4 + Centro de aulas M0-M4',
            'archivo' => basename(__FILE__),
            'ruta' => __DIR__,
            'modificado' => date('Y-m-d H:i:s', filemtime(__FILE__))));
    }
    salir_(array('ok' => false, 'error' => 'Acción no reconocida: ' . $accion));

} catch (Exception $e) {
    // (15-ago-2026) EL DETALLE, NO SOLO EL MENSAJE. Moodle contesta "Error al
    // leer de la base de datos" y esconde qué consulta falló, así que del
    // otro lado solo queda adivinar. El debuginfo trae el SQL y el error real
    // del motor; sin él, cada intento de arreglo es a ciegas.
    $det = array('ok' => false, 'error' => $e->getMessage(), 'accion' => $accion);
    if (isset($e->debuginfo) && $e->debuginfo) { $det['detalle'] = (string)$e->debuginfo; }
    if (isset($e->errorcode) && $e->errorcode) { $det['codigo'] = (string)$e->errorcode; }
    $det['linea'] = $e->getLine();
    salir_($det);
} 
