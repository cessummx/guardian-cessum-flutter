import 'dart:ui' as ui;   // (4-oct-2026) desenfoque detrás de la carpeta abierta
import 'autoevaluacion_tablero_screen.dart';
// (22-sep) Tableros de dirección.
import 'finanzas_screen.dart';
import 'salud_screen.dart';
import 'senales_screen.dart';
import 'altas_screen.dart';
import 'simulador_screen.dart';
import 'bajas_pago_screen.dart';
import 'acceso_bloqueos_screen.dart';
import 'quejas_admin_screen.dart';
import 'beca_convocatoria_admin_screen.dart';
import 'cumplimiento_acuerdo_screen.dart';
import 'incidencias_admin_screen.dart';
import 'avisos_admin_screen.dart';
import 'ficha_alumno_screen.dart';
import 'riesgo_screen.dart';
import 'recursamientos_panel_screen.dart';
import 'reingresos_admin_screen.dart';
import 'titulacion_admin_screen.dart';
import 'titulacion_cierre_screen.dart';
import 'buzon_eventos_admin_screen.dart';
import 'importador_screen.dart';
import 'horarios_admin_screen.dart';
import 'choques_horario_screen.dart';
import 'avance_tablero_screen.dart';
import 'calendario_admin_screen.dart';
import 'tablero_rapido_screen.dart';
import 'herramientas_screen.dart';
import 'tablero_screen.dart';
import 'constancias_lote_screen.dart';
import 'bitacora_screen.dart';
import 'vencimientos_screen.dart';
import 'vistos_screen.dart';
import 'no_adeudo_admin_screen.dart';
import 'circular_screen.dart';
import 'tablero_bi_screen.dart';
import 'reportes_datos_screen.dart';
import 'comunicado_screen.dart';
import 'formatos_screen.dart';
import 'diploma_congreso_screen.dart';
import 'automatizaciones_screen.dart';
import 'verificador_qr_screen.dart';
import 'estudios_admin_screen.dart';
import 'cobertura_evaluacion_screen.dart';
import 'centro_inteligencia_screen.dart';
import 'salud_datos_screen.dart';
import 'moodle_admin_screen.dart';
import 'resumen_ejecutivo_screen.dart';
import 'avance_captura_screen.dart';
import 'estadisticas_padron_screen.dart';
import 'cursos_vigentes_screen.dart';
import 'pagos_administrativos_screen.dart';
import 'adaptaciones_admin_screen.dart';
import 'convenios_admin_screen.dart';
import 'seguimiento_docente_screen.dart';
import 'tesis_solicitudes_admin_screen.dart';
import 'oficios_screen.dart';
import 'analisis_calificaciones_screen.dart';
import 'directorio_docentes_screen.dart';
import 'comparativo_generaciones_screen.dart';
import 'recordatorio_docentes_screen.dart';
import 'resumen_docentes_screen.dart';
import 'boletas_periodo_screen.dart';
import 'bitacora_correos_screen.dart';
import 'torre_control_screen.dart';
import 'pendientes_dia_screen.dart';
import 'auth/session_store.dart';
import 'admin_config.dart';
import 'roles_admin_screen.dart';
import 'pagos_docentes_screen.dart';
import 'asistente_ia_screen.dart';
import 'uso_ia_screen.dart';
import 'cambio_programa_screen.dart';
import 'documentos_plantilla_screen.dart';
import 'recomienda_admin_screen.dart';
import 'becas_tipos_admin_screen.dart';
import 'becas_admin_screen.dart';
import 'costos_colegiaturas_screen.dart';
import 'monto_grupo_screen.dart';
import 'siga_screen.dart';   // (23-sep) una sola entrada de SIGA: la Cabina
import 'aspirantes_pendientes_screen.dart';
import 'helpers.dart';   // (4-oct-2026) abrir las páginas de admisiones y el Centro de aulas
import 'altas_anomalias_screen.dart';
import 'padron_overrides_screen.dart';
import 'enviar_notificacion_screen.dart';
import 'respaldos_screen.dart';
import 'documentos_admin_screen.dart';
import 'dart:convert' show jsonDecode;
import 'package:http/http.dart' as http_pend;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'active_profile.dart';
import 'alumnos_service.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'generaciones_service.dart';
import 'menu_screen.dart';
import 'student_profile.dart';
import 'elegir_profesor_screen.dart';
import 'teacher_menu_screen.dart';
import 'welcome_screen.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'admin_calificaciones_screen.dart';
import 'admin_grupos_screen.dart';
import 'agenda_profesores_screen.dart';
import 'planeaciones_revision_screen.dart';
import 'respuestas_docentes_screen.dart';
import 'materias_sin_maestro_screen.dart';
import 'recordatorio_invitaciones_screen.dart';
import 'localizador_alumnos_screen.dart';
import 'tablero_programacion_screen.dart';
import 'evaluacion_grupo_screen.dart';
import 'clasificacion_alumnos_screen.dart';
import 'justificaciones_lista_screen.dart';
import 'bajas_lista_screen.dart';
import 'tramites_lista_screen.dart';
import 'pagos_screen.dart';
import 'seguimiento_pagos_admin_screen.dart';
import 'centro_pagos_screen.dart';
import 'expedientes_screen.dart';
import 'bandeja_correos_screen.dart';
import 'marketing_correos_screen.dart';
import 'corregir_grupo_alumno_screen.dart';
import 'cambiar_matricula_alumno_screen.dart';   // (5-oct-2026)
import 'validacion_actas_screen.dart';
import 'solicitudes_correccion_screen.dart';
import 'credenciales_admin_screen.dart';
import 'registro_accesos_screen.dart';
import 'alta_alumno_screen.dart';
import 'alta_lote_screen.dart';
import 'cambiar_programa_screen.dart';
import 'profesores_admin_screen.dart';
import 'docente_alta_screen.dart';
import 'lista_asistencia_screen.dart';
import 'buscador_global_screen.dart';
import 'operaciones_lote_screen.dart';
import 'avance_multiprograma_screen.dart';
import 'planes_faltantes_screen.dart';
import 'contratos_validacion_screen.dart';
import 'contratos_tablero_screen.dart';
import 'contratos_faltantes_screen.dart';
import 'recordatorio_captura_screen.dart';
import 'carga_docente_screen.dart';
import 'respaldo_excel_screen.dart';
import 'centro_mando_screen.dart'; // (24-sep) centros inteligentes · fase 1
import 'bandeja_solicitudes_screen.dart';
import 'expediente_360_screen.dart';
import 'expediente_docente_360_screen.dart'; // (24-sep) centros inteligentes · fase 4
import 'calendario_operativo_screen.dart'; // (24-sep) centros inteligentes · fase 4
import 'planeacion_ciclo_screen.dart'; // (24-sep) centros inteligentes · fase 4
import 'cobranza_screen.dart'; // (24-sep) centros inteligentes · fase 4
import 'retencion_predictiva_screen.dart'; // (24-sep) centros inteligentes · fase 4
import 'calidad_datos_screen.dart'; // (24-sep) centros inteligentes · fase 3
import 'auditoria_seguridad_screen.dart'; // (24-sep) centros inteligentes · fase 3
import 'asistente_operaciones_screen.dart'; // (24-sep) centros inteligentes · fase 3
import 'centro_comunicaciones_screen.dart'; // (24-sep) centros inteligentes · fase 2
import 'selector_buscable.dart'; // (24-sep) selectores largos con búsqueda

/// Pantalla SOLO para administradores (contacto@ / soporte@).
///
/// Permite previsualizar la app tal como la ven los estudiantes y los
/// docentes, sin necesidad de tener matricula ni estar en la lista de
/// alumnos.json.
///
/// Como funciona: al elegir "Ver como estudiante" se crea un perfil de
/// DEMOSTRACION que se guarda solo en este navegador (no toca la lista real
/// de alumnos) y se entra al menu de estudiante normal. Para SALIR de la
/// vista previa, dentro del menu se toca el icono de las dos flechas
/// (Cambiar perfil) y se regresa aqui.
String _genLegible(String g) {
  final s = g.trim();
  if (s.isEmpty) return s;
  const meses = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
  };
  final mTxt = RegExp(r'\b([A-Za-z]{3})\s+(\d{1,2})\s+\d{4}').firstMatch(s);
  if (mTxt != null) {
    final mes = meses[mTxt.group(1)!.toLowerCase()];
    final dia = int.tryParse(mTxt.group(2)!);
    if (mes != null && dia != null) return '$dia-$mes';
  }
  return s;
}

class AdminPreviewScreen extends StatefulWidget {
  const AdminPreviewScreen({super.key});

  @override
  State<AdminPreviewScreen> createState() => _AdminPreviewScreenState();
}

class _AdminPreviewScreenState extends State<AdminPreviewScreen> {
  Map<String, int> _pend = {};
  String _rol = 'total';

  // El rol y los permisos se resuelven con admin_config (que ya considera
  // los roles asignados dinámicamente desde la app vía RolesService).

  /// (ago-29) Se conserva el correo de la sesión, no solo el rol. Las
  /// pantallas que ESCRIBEN piden `actor` para dejar constancia de quién
  /// resolvió; sin él, el backend responde «Solo administradores».
  String _correoSesion = '';

  Future<void> _cargarRol() async {
    final correo = await SessionStore.validEmail();
    if (mounted) {
      setState(() {
        _rol = rolDe(correo);
        _correoSesion = correo ?? '';
      });
    }
  }

  bool _ve(String seccion) => rolPermite(_rol, seccion);

  /// Agrupa varias tarjetas en una sección colapsable (acordeón).
  /// Si ninguna tarjeta del grupo es visible, no muestra nada.
  // ---- BUSCADOR DE OPCIONES DEL PANEL (jul-2026) ----
  final _buscaAdminCtrl = TextEditingController();
  String _qAdmin = '';

  String _normBuscaAdmin(String s) {
    var t = s.toLowerCase();
    const con = 'áéíóúüñ';
    const sin = 'aeiouun';
    for (var i = 0; i < con.length; i++) {
      t = t.replaceAll(con[i], sin[i]);
    }
    return t;
  }

  // Catálogo de TODAS las tarjetas del panel (título+descripción) para el
  // buscador. Cada entrada conserva su guarda de permisos y renderiza la
  // tarjeta REAL (misma acción). Generado del propio panel.
  List<_OpcionAdmin> _catalogoAdmin() {
    return [
      // (22-sep) TABLEROS DE DIRECCIÓN. Existían en el menú general pero
      // no aquí, que es donde entra un administrador: buscarlos daba «Sin
      // resultados».
      // (24-sep) CENTROS INTELIGENTES · fase 1.
      if (_ve('academico')) _OpcionAdmin('Centro de mando',
          'Lo que requiere su decisión hoy, por impacto: actas, pagos, riesgo, captura, grupos sin maestro y solicitudes vencidas. Con tres líneas de IA.',
          _tarjetaCentroMando),
      if (_ve('academico')) _OpcionAdmin('Bandeja de solicitudes',
          'Todas las solicitudes pendientes en una sola lista, con semáforo de tiempo y borrador de respuesta con IA.',
          _tarjetaBandeja),
      if (_ve('academico')) _OpcionAdmin('Centro de comunicaciones',
          'Un solo redactor para alumnos o docentes: audiencia por programa, generación, grupo, riesgo o adeudo; vista previa obligatoria e historial.',
          _tarjetaComunicaciones),
      if (_ve('academico')) _OpcionAdmin('Asistente de operaciones',
          'Pregunte con sus palabras: responde con datos reales y propone acciones que usted revisa y confirma.',
          _tarjetaAsistenteOps),
      if (_ve('academico')) _OpcionAdmin('Auditoría y seguridad',
          'La bitácora convertida en alertas: acciones sensibles, horarios inusuales, rechazos de los candados y accesos.',
          _tarjetaAuditoria),
      if (_ve('academico')) _OpcionAdmin('Calidad de datos',
          'Descuadres, duplicados, huérfanos, CURP, sin maestro, SIGA y anomalías en una sola vista, con tendencia diaria.',
          _tarjetaCalidadDatos),
      if (_ve('academico')) _OpcionAdmin('Retención predictiva',
          'Quién podría abandonar, con probabilidad, adeudo, intervenciones hechas y qué tipo de intervención sí retiene.',
          _tarjetaRetencionPredictiva),
      if (_ve('academico')) _OpcionAdmin('Cobranza inteligente',
          'Adeudos por urgencia y probabilidad de pago, recuperable estimado y recordatorio con vista previa.',
          _tarjetaCobranza),
      if (_ve('academico')) _OpcionAdmin('Planeación del ciclo',
          'Oferta y claves, programación, docentes sin choques e invitaciones: qué falta antes de publicar, con lectura IA.',
          _tarjetaPlaneacionCiclo),
      if (_ve('academico')) _OpcionAdmin('Calendario operativo',
          'Inicio y cierre de materias, eventos, exámenes y calendario institucional en una línea del tiempo con responsable.',
          _tarjetaCalendarioOperativo),
      if (_ve('academico')) _OpcionAdmin('Expediente 360 · docente',
          'Carga, captura, evaluación, contrato, pagos e inasistencias de un docente en una vista, con cinco líneas de IA.',
          _tarjetaExpedienteDocente),
      if (_ve('academico')) _OpcionAdmin('Expediente 360',
          'Todo lo de un alumno en una línea de tiempo: calificaciones, pagos, trámites, riesgo y asistencia. Con la situación en cinco líneas.',
          _tarjetaExpediente360),
      if (_esFinanzas) _OpcionAdmin('Finanzas · estados de cuenta',
          'Suba el estado de cuenta de BBVA: gastos por categoría, histórico, alertas y asistente de IA.',
          _tarjetaFinanzas),
      if (_ve('academico')) _OpcionAdmin('Salud del sistema',
          'Disparadores, colas pendientes, clases y datos: qué está detenido y cómo se arregla.',
          _tarjetaSaludSistema),
      if (_ve('academico')) _OpcionAdmin('Señales académicas',
          'A quién se le está apagando la participación y qué materias hunden la permanencia, con razones.',
          _tarjetaSenales),
      if (_ve('academico')) _OpcionAdmin('Altas de inscripción',
          'Cada solicitud de inscripción con sus pasos comprobados: revisión, cuenta, matrícula, padrón, grupo, aula y bienvenida.',
          _tarjetaAltasInscripcion),
      if (_ve('academico')) _OpcionAdmin('Bajas por pago',
          'Alumnos con colegiaturas incompletas al cierre de su corte: autorizar, posponer o descartar la baja.',
          _tarjetaBajasPago),
      if (_ve('academico')) _OpcionAdmin('Simulador de grupos',
          'Ingreso, costo docente, punto de equilibrio y qué pasa si se cae una parte, con las bajas reales.',
          _tarjetaSimulador),
      _OpcionAdmin('Asistente IA',
          'Pregúntale en lenguaje natural; te ayuda a localizar y usar las secciones del panel.',
          _tarjetaAsistenteIa),
      if (_ve('academico')) _OpcionAdmin('Buscador global',
          'Encuentra cualquier alumno o profesor por nombre, matrícula o correo.',
          _tarjetaBuscadorGlobal),
      if (_ve('academico')) _OpcionAdmin('Pendientes del día',
          'Lo accionable hoy: captura, trámites y alumnos en riesgo.',
          _tarjetaPendientesDia),
      if (_ve('academico')) _OpcionAdmin('Tablero ejecutivo',
          'Matrícula, ingresos, trámites, riesgo, titulación y desempeño docente en una sola vista.',
          _tarjetaTablero),
      if (_ve('academico')) _OpcionAdmin('Tablero institucional (BI)',
          'Matricula, aprobacion, carga docente, actas y contratos en una sola vista.',
          _tarjetaTableroBI),
      if (_ve('academico')) _OpcionAdmin('Tablero rapido',
          'Numeros clave, buscar alumno, directorio docente, por programa y cumpleanos.',
          _tarjetaTableroRapido),
      if (_ve('academico')) _OpcionAdmin('Resumen ejecutivo',
          'Focos de atención en un vistazo: datos, inactividad en el Aula e inscripciones pendientes.',
          _tarjetaResumenEjecutivo),
      if (_ve('academico')) _OpcionAdmin('Centro de inteligencia',
          'Expediente PDF del alumno, generaciones por egresar y matriculas duplicadas.',
          _tarjetaCentroInteligencia),
      if (_ve('academico')) _OpcionAdmin('Estadísticas del padrón',
          'Alumnos por programa, generación y modalidad.',
          _tarjetaEstadisticasPadron),
      if (_ve('academico')) _OpcionAdmin('Análisis de calificaciones',
          'Promedios, aprobados/reprobados y distribución por nota.',
          _tarjetaAnalisisCalificaciones),
      if (_ve('academico')) _OpcionAdmin('Comparativo de generaciones',
          'Evolución de matrícula, promedio y aprobación por generación.',
          _tarjetaComparativoGeneraciones),
      if (_ve('academico')) _OpcionAdmin('Autoevaluación CESSUM 2026',
          'Avance de las 10 carpetas, indicadores y responsables.',
          _tarjetaAutoevaluacion),
      if (_ve('academico')) _OpcionAdmin('Reportes de datos',
          'Validador de CURP, demografia y exportar padron a Excel.',
          _tarjetaReportesDatos),
      if (_ve('academico')) _OpcionAdmin('Salud de datos',
          'Detecta duplicados, grupos sin docente, calificaciones fuera del padron y generaciones mal etiquetadas.',
          _tarjetaSaludDatos),
      if (_ve('academico')) _OpcionAdmin('Cursos vigentes',
          'Los cursos en marcha hoy: docente, clase, fechas, link del aula y descarga a Excel.',
          _tarjetaCursosVigentes),
      if (_ve('seguimientoPagos')) _OpcionAdmin('Pagos a administrativos',
          'Nómina del personal: pendientes por quincena o mes, CLABE, marcar pagado e historial.',
          _tarjetaPagosAdministrativos),
      if (_ve('academico')) _OpcionAdmin('Adaptaciones de modalidad',
          'Adaptaciones aprobadas en espera: el vigilante matricula al alumno solo cuando su materia está en línea, con aviso por correo.',
          _tarjetaAdaptaciones),
      if (_ve('documentos')) _OpcionAdmin('Convenios',
          'Crea convenios institucionales, promuévelos por correo y sigue el avance de firmas de consentimiento.',
          _tarjetaConvenios),
      if (_ve('academico')) _OpcionAdmin('Seguimiento docente',
          'Ranking de desempeño docente en revisiones: puntaje de calidad, en tiempo y forma dentro de las 24 horas.',
          _tarjetaSeguimientoDocente),
      if (_ve('academico')) _OpcionAdmin('Solicitudes de tutor de tesis',
          'Solicitudes firmadas del alumnado para asignarles director de tesis: tema propuesto, justificación y firma.',
          _tarjetaTesisSolicitudes),
      _OpcionAdmin('Uso de IA',
          'Cuántas consultas se han hecho al asistente: hoy, semana, mes y quién la usa más.',
          _tarjetaUsoIa),
      _OpcionAdmin('Aspirantes',
          'Triage de inscripciones: semáforo por matrícula, código y pago. Marca lo revisado.',
          _tarjetaAspirantes),
      _OpcionAdmin('Anomalías de alta',
          'Verifica si alguien ya existe antes de darlo de alta y detecta matrículas, correos y CURPs duplicados.',
          _tarjetaAnomalias),
      _OpcionAdmin('Recomendaciones',
          'Registra aspirantes por código y habilita la bonificación del alumno.',
          _tarjetaRecomienda),
      _OpcionAdmin('Becas por tipo',
          'USICAMM, Indígena, Discapacidad, Directa y Crédito Educativo. Aplica el % en la hoja de becas.',
          _tarjetaBecasTipos),
      // (ago-12) BECADOS NO ERA ENCONTRABLE. Este buscador indexa el catálogo
      // de ESTA pantalla, y "Becados" vivía solo como un botón dentro de otra
      // tarjeta en menu_screen: buscar "beca" devolvía el catálogo de tipos y
      // los costos, nunca la pantalla donde se AUTORIZAN. La descripción lleva
      // a propósito las palabras que de verdad se teclean: IBCEES, crédito
      // educativo, solicitudes, validar, autorizar.
      if (_ve('academico')) _OpcionAdmin('Becados · autorizar solicitudes',
          'Valida las solicitudes de beca que suben los alumnos (IBCEES, '
          'Instituto de Becas y Crédito Educativo, USICAMM), captura el '
          'porcentaje y genera el convenio.',
          _tarjetaBecados),
      if (_ve('academico')) _OpcionAdmin('Dar de alta alumno',
          'Registra un alumno nuevo en el grupo y en el padrón (matrícula, programa, generación).',
          _tarjetaAltaAlumno),
      if (_ve('academico')) _OpcionAdmin('Dar de alta por lote',
          'Da de alta a varios alumnos de una vez: pegas la lista, ves la vista previa y el reporte.',
          _tarjetaAltaLote),
      _OpcionAdmin('Cambio de programa',
          'Promueve a un alumno (p. ej. de maestría a doctorado) conservando su matrícula e historial.',
          _tarjetaCambioPrograma),
      if (_ve('academico')) _OpcionAdmin('Cambiar de programa o generación',
          'Mueve al alumno de programa, generación o grupo en un solo paso (materias y actas incluidas).',
          _tarjetaCambiarPrograma),
      if (_ve('academico')) _OpcionAdmin('Avance por programa',
          'Para alumnos con continuidad (maestría y doctorado): avance de cada programa por separado.',
          _tarjetaAvancePrograma),
      if (_ve('academico')) _OpcionAdmin('Planes faltantes',
          'Programas activos sin plan en cartas.json (los que no muestran % de avance).',
          _tarjetaPlanesFaltantes),
      if (_ve('academico')) _OpcionAdmin('Operaciones por lote',
          'Da de baja o cambia de programa a varios alumnos a la vez, pegando una lista.',
          _tarjetaOperacionesLote),
      if (_ve('academico')) _OpcionAdmin('Corregir grupo de alumno',
          'Pasa a un alumno al grupo correcto (por ejemplo, sabatino que quedó entre semana) y lo inscribe en sus aulas de Moodle.',
          _tarjetaCorregirGrupo),
      if (_ve('academico')) _OpcionAdmin('Cambiar matrícula de alumno',
          'Cambia la matrícula de un alumno en todo el sistema (grupos, padrón, pagos y bajas), con vista previa. Solo Rectoría y Vicerrectoría.',
          _tarjetaCambiarMatricula),
      if (_ve('academico')) _OpcionAdmin('Armar / corregir grupos',
          'Corrige el programa, generación o grupo de un alumno, o agrégalo a un grupo. Surte efecto en la base del Guardián.',
          _tarjetaGrupos),
      if (_ve('academico')) _OpcionAdmin('Listas de asistencia',
          'Imprime la lista de asistencia (PDF) de cualquier grupo, con columnas de fechas para palomear.',
          _tarjetaListasAsistencia),
      if (_ve('academico')) _OpcionAdmin('Clasificación de alumnos',
          'Activos, bajas, egresados y titulados. El sistema propone una clasificación y tú puedes ajustarla.',
          _tarjetaClasificacion),
      if (_ve('academico')) _OpcionAdmin('Planeaciones por revisar',
          'Dictamina las planeaciones didácticas que entregan los docentes: validarlas o devolverlas con observaciones. La planeación validada es requisito para el pago.',
          _tarjetaPlaneacionesRevision),
      if (_ve('academico')) _OpcionAdmin('Agenda de profesores',
          'Crea y edita las asignaciones (grupo, materia, maestro, horario y links de videollamada y Aula CESSUM). Incluye los grupos que aún no tienen maestro.',
          _tarjetaAgendaProfesores),
      if (_ve('academico')) _OpcionAdmin('Respuestas de docentes',
          'Quién aceptó o rechazó cada materia, con el día y hora que eligió y sus comentarios. Permite reenviar la invitación.',
          _tarjetaRespuestasDocentes),
      if (_ve('academico')) _OpcionAdmin('Programación por grupo',
          'Por cada grupo, qué materias ya tienen docente y horario y cuáles faltan, con el estado de cada invitación.',
          _tarjetaTableroProgramacion),
      if (_ve('academico')) _OpcionAdmin('Grupos sin maestro',
          'Grupos que ya tienen alumnos pero todavía no tienen ningún docente asignado. Los huecos por programar.',
          _tarjetaMateriasSinMaestro),
      if (_ve('academico')) _OpcionAdmin('Invitaciones pendientes',
          'Reenvía en lote la invitación a todos los docentes que aún no han respondido. (Distinto del recordatorio de captura de calificaciones.)',
          _tarjetaRecordatorioInvitaciones),
      if (_ve('academico')) _OpcionAdmin('Localizador de alumnos',
          'Ubica alumnos filtrando por programa, generación, grupo y modalidad, o busca por nombre, matrícula o correo.',
          _tarjetaLocalizadorAlumnos),
      if (_ve('academico')) _OpcionAdmin('Horarios por grupo',
          'Arma y publica el horario de cada grupo; el alumno lo ve en su app.',
          _tarjetaHorarios),
      if (_ve('academico')) _OpcionAdmin('Choques de horario',
          'Detecta cuando un maestro o un grupo tienen clases encimadas el mismo dia.',
          _tarjetaChoquesHorario),
      if (_ve('academico')) _OpcionAdmin('Correcciones del padrón',
          'Corrige nombre, modalidad, correo, programa, generación, grupo o estatus por matrícula.',
          _tarjetaCorreccionesPadron),
      if (_ve('ficha')) _OpcionAdmin('Ficha del alumno',
          'Todo de un alumno por matricula: calificaciones, tramites, incidencias, justificaciones y accesos.',
          _tarjetaFicha),
      if (_ve('bajas')) _OpcionAdmin('Bajas',
          'Revisa las solicitudes de baja (temporal o definitiva), valídalas o regístralas a mano.',
          _tarjetaBajas),
      if (_ve('academico')) _OpcionAdmin('Torre de Control',
          'Índice de Salud Institucional en vivo, con focos de atención.',
          _tarjetaTorreControl),
      if (_ve('academico')) _OpcionAdmin('Avance de captura',
          'Qué docentes ya capturaron sus grupos y cuáles van pendientes.',
          _tarjetaAvanceCaptura),
      if (_ve('academico')) _OpcionAdmin('Recordatorio de captura',
          'Avisa por correo a los docentes con captura de calificaciones pendiente.',
          _tarjetaRecordatorioCaptura),
      if (_ve('academico')) _OpcionAdmin('ABIERTA',
          'CERRADA',
          _tarjetaSemaforo),
      if (_ve('academico')) _OpcionAdmin('Validación de actas',
          'Revisa y valida las actas que los docentes capturaron.',
          _tarjetaValidacionActas),
      if (_ve('academico')) _OpcionAdmin('Editar calificaciones',
          'Busca a un alumno por matrícula y agrega, corrige o borra sus calificaciones.',
          _tarjetaEditarCalificaciones),
      if (_ve('academico')) _OpcionAdmin('Evaluación manual del grupo',
          'Elige grupo y materia, ve a todos los alumnos con su nota actual, corrige o digita a mano y guarda directo en las listas de calificaciones.',
          _tarjetaEvaluacionGrupo),
      if (_ve('academico')) _OpcionAdmin('Importar calificaciones (Excel)',
          'Pega filas de Excel, previsualiza con validacion y carga en lote.',
          _tarjetaImportador),
      if (_ve('academico')) _OpcionAdmin('Avance programatico',
          'Cuanto se ha cubierto de cada materia-grupo frente a la meta.',
          _tarjetaAvance),
      if (_ve('academico')) _OpcionAdmin('Riesgo académico',
          'Semaforo de alumnos a distancia: inactividad en Moodle y reprobacion, calculado cada noche.',
          _tarjetaRiesgo),
      if (_ve('solicitudesCorreccion')) _OpcionAdmin('correcciones',
          'Solicitudes de corrección',
          _tarjetaSolicitudesCorreccion),
      // (ago-28) El catálogo del buscador es una SEGUNDA lista, aparte de
      // las secciones de abajo. Agregar la tarjeta a la sección no la hace
      // buscable: hay que anotarla también aquí. Se le ponen las palabras
      // con que uno la busca de verdad —recursar, recursamiento, reprobada,
      // matricular— porque el buscador solo mira título y descripción.
      if (_ve('academico')) _OpcionAdmin('Recursamientos',
          'Quien va a recursar una materia reprobada: solicitudes, verificacion de pago y matricula en el grupo que la oferta.',
          _tarjetaRecursamientos),
      if (_ve('justificaciones')) _OpcionAdmin('Reingresos',
          'Alumnos dados de baja que solicitan reingresar: kardex, informe financiero, solicitud firmada, convenio de recursamiento y resolucion.',
          _tarjetaReingresos),
      if (_ve('academico')) _OpcionAdmin('Profesores',
          'Agrega, edita o da de baja docentes. Se refleja al instante, sin regenerar archivos.',
          _tarjetaProfesores),
      if (_ve('academico')) _OpcionAdmin('Directorio de docentes',
          'Docentes activos, sus materias y contacto directo.',
          _tarjetaDirectorioDocentes),
      if (_ve('academico')) _OpcionAdmin('Carga docente',
          'Cuántas materias trae cada maestro y quiénes están sobrecargados.',
          _tarjetaCargaDocente),
      if (_ve('academico')) _OpcionAdmin('Cobertura de evaluación docente',
          'Que docentes ya tienen evaluacion y cuales faltan, por programa.',
          _tarjetaCobertura),
      if (_ve('academico')) _OpcionAdmin('Resumen a docentes',
          'Envía a cada docente su resumen de captura (grupos y avance).',
          _tarjetaResumenDocentes),
      if (_ve('academico')) _OpcionAdmin('Recordatorio a docentes',
          'Avisa por correo a quienes tienen captura pendiente.',
          _tarjetaRecordatorioDocentes),
      if (_ve('academico')) _OpcionAdmin('Contratos por validar',
          'Revisa los contratos que los profesores firmaron y envíalos por correo al validarlos.',
          _tarjetaContratosValidar),
      if (_ve('academico')) _OpcionAdmin('Tablero de contratos',
          'Contadores por estatus y exportación a Excel de todos los contratos.',
          _tarjetaTableroContratos),
      if (_ve('academico')) _OpcionAdmin('Contratos pendientes',
          'Qué docentes tienen materias activas sin contrato, para dar seguimiento.',
          _tarjetaContratosFaltantes),
      if (_ve('academico')) _OpcionAdmin('Actualizar padron ahora',
          'Usalo cuando edites las hojas a mano: el padron se guarda 6 horas y esto lo vuelve a leer al instante.',
          _tarjetaRefrescarPadron),
      if (_ve('tramites')) _OpcionAdmin('Trámites escolares',
          'Solicitudes de constancias, boletas, kardex, etc. Márcalas como atendidas o rechazadas.',
          _tarjetaTramites),
      if (_ve('justificaciones')) _OpcionAdmin('Justificaciones de faltas',
          'Revisa las justificaciones enviadas por los alumnos y valida o rechaza desde aquí.',
          _tarjetaJustificaciones),
      if (_ve('credenciales')) _OpcionAdmin('credenciales',
          'Credenciales',
          _tarjetaCredenciales),
      if (_ve('titulacion')) _OpcionAdmin('titulacion',
          'Titulación',
          _tarjetaTitulacion),
      if (_ve('titulacion')) _OpcionAdmin('Cierre de titulacion',
          'Control de cedula profesional (SEP) y actas de egreso por generacion.',
          _tarjetaTitulacionCierre),
      if (_ve('titulacion')) _OpcionAdmin('Expedientes',
          'Documentos de cada alumno para el Acuerdo 17/11/17 y para titularse, desde los formularios, la app y titulación.',
          _tarjetaExpedientes),
      if (_ve('documentos')) _OpcionAdmin('Constancias por lote',
          'Genera todas las constancias de una generacion de un golpe, con folio, firma y QR.',
          _tarjetaConstanciasLote),
      if (_ve('documentos')) _OpcionAdmin('Documentos oficiales',
          'Constancias y kardex con folio, firma del Rector y descarga en PDF o DOCX.',
          _tarjetaDocumentos),
      _OpcionAdmin('Documentos por plantilla',
          'Reconocimientos y constancias con QR de verificación, en una sola pantalla.',
          _tarjetaDocumentosPlantilla),
      if (_ve('academico')) _OpcionAdmin('Diploma de congreso',
          'Emite el diploma de un participante de COINEDU con QR.',
          _tarjetaDiplomaCongreso),
      if (_ve('academico')) _OpcionAdmin('Verificar documento (QR)',
          'Escanea el QR de una constancia, acta, contrato o diploma.',
          _tarjetaVerificadorQr),
      if (_ve('academico')) _OpcionAdmin('Boletas por periodo',
          'Envía la boleta a quienes ya completaron su periodo.',
          _tarjetaBoletasPeriodo),
      if (_ve('pagos')) _OpcionAdmin('Registro de pagos',
          'Base central de pagos: inscripciones, reinscripciones, colegiaturas y trámites.',
          _tarjetaPagos),
      if (_ve('pagos')) _OpcionAdmin('Costos y colegiaturas',
          'Costo por programa y modalidad (Mixta incluida) y ajuste manual por alumno con beca o descuento.',
          _tarjetaCostosColegiaturas),
      if (_ve('pagos')) _OpcionAdmin('Monto de pago por grupo',
          'Fija manualmente el monto de un grupo cuando el sistema toma la modalidad equivocada (mixtos, doctorados).',
          _tarjetaMontoPorGrupo),
      if (_ve('seguimientoPagos')) _OpcionAdmin('Seguimiento de pagos',
          'Quién ha pagado, cuántas veces y cuándo. Lee los formularios de pago (informativo).',
          _tarjetaSeguimientoPagos),
      if (_ve('seguimientoPagos')) _OpcionAdmin('Pagos a docentes',
          'Registra pagos por asignatura (acta validada), adjunta el comprobante y avisa al profesor.',
          _tarjetaPagosDocentes),
      if (_ve('pagos')) _OpcionAdmin('Recordatorios de pago',
          'Registra vencimientos; el alumno recibe aviso 3 dias antes y a ti te reportamos los vencidos.',
          _tarjetaVencimientos),
      if (_ve('pagos')) _OpcionAdmin('noadeudo',
          'Constancias de no adeudo',
          _tarjetaNoAdeudo),
      if (_ve('avisos')) _OpcionAdmin('Aviso masivo (circular)',
          'Envía un correo con diseño CESSUM a una generación, un programa o a todos.',
          _tarjetaCircular),
      if (_ve('academico')) _OpcionAdmin('Comunicado institucional',
          'Envia un aviso a alumnos, docentes o ambos (in-app y correo).',
          _tarjetaComunicado),
      // (ago-18) El Banco de formatos solo se alcanzaba desde el menú
      // principal. Se administra desde aquí —se agregan, editan y ordenan los
      // formatos—, así que buscarlo en el panel y no encontrarlo no tenía
      // sentido. Es la MISMA pantalla: entra en modo edición porque quien
      // abre es administrador.
      if (_ve('academico')) _OpcionAdmin('Banco de formatos',
          'Publica plantillas y formatos que descargan alumnos y docentes.',
          _tarjetaFormatos),
      if (_ve('avisos')) _OpcionAdmin('Buzón y eventos',
          'Mensajes anónimos de alumnos y confirmación de asistencia a eventos.',
          _tarjetaBuzonEventos),
      if (_ve('avisos')) _OpcionAdmin('Correos de marketing',
          'Correos a aspirantes y prospectos con plantilla personalizable (no a alumnos).',
          _tarjetaMarketing),
      if (_ve('avisos')) _OpcionAdmin('Bandeja de solicitudes',
          'Correos de contacto, rectoría y vicerrectoría que piden algo, ya clasificados y por urgencia.',
          _tarjetaBandejaCorreos),
      if (_ve('avisos')) _OpcionAdmin('Calendario académico',
          'Publica fechas clave (inscripciones, exámenes, pagos) que ven alumnos y docentes.',
          _tarjetaCalendario),
      if (_ve('avisos')) _OpcionAdmin('Enviar notificacion',
          'Avisa a un alumno o a todo un grupo dentro de la app.',
          _tarjetaEnviarNotificacion),
      if (_ve('avisos')) _OpcionAdmin('Avisos institucionales',
          'Publica comunicados para todos o segmentados por programa, modalidad, generacion y grupo.',
          _tarjetaAvisos),
      if (_ve('academico')) _OpcionAdmin('Confirmaciones de lectura',
          'Quién ya recibió su boleta o aviso de trámite/titulación, y por qué canal.',
          _tarjetaVistos),
      if (_ve('academico')) _OpcionAdmin('Bitácora de correos',
          'Qué se envió, qué falló y cuánta cuota queda.',
          _tarjetaBitacoraCorreos),
      if (_ve('academico')) _OpcionAdmin('Bitacora de auditoria',
          'Registro de quién validó, resolvió, emitió o cambió algo, y cuándo.',
          _tarjetaBitacora),
      if (_rol == 'total') _OpcionAdmin('Gestion de roles',
          'Da o quita acceso de administracion a otros usuarios.',
          _tarjetaRoles),
      if (_rol == 'total') _OpcionAdmin('Respaldos del sistema',
          'Copias automaticas de las bases. Revisa o respalda ahora.',
          _tarjetaRespaldos),
      if (_ve('academico')) _OpcionAdmin('Respaldo en Excel',
          'Descarga las hojas clave (calificaciones, asignaciones, alumnos, contratos) en un Excel.',
          _tarjetaRespaldoExcel),
      if (_ve('academico')) _OpcionAdmin('Centro de automatizaciones',
          'Prende, apaga y ejecuta los recordatorios y avisos automaticos.',
          _tarjetaAutomatizaciones),
      if (_ve('accesos')) _OpcionAdmin('Registro de accesos',
          'Consulta quién ha entrado a la app y cuándo: accesos recientes, buscador y conteo por persona.',
          _tarjetaAccesos),
      if (_ve('incidencias')) _OpcionAdmin('incidencias',
          'Mesa de ayuda (incidencias)',
          _tarjetaIncidencias),
      if (_ve('control')) _OpcionAdmin('Herramientas',
          'Reconocimientos en PDF, exportar a CSV y mas utilidades rapidas.',
          _tarjetaHerramientas),
      _OpcionAdmin('Panel de admisiones',
          'Seguimiento de aspirantes, contactos y conversaciones de admisiones (cessum.mx/adminadmisiones).',
          _tarjetaPanelAdmisiones),
      _OpcionAdmin('Página de admisiones',
          'La página pública donde los aspirantes se registran: para revisarla o compartirla (cessum.mx/admisiones).',
          _tarjetaPaginaAdmisiones),
      if (_ve('academico')) _OpcionAdmin('Centro de aulas',
          'Revisión de las aulas de Moodle: mapa, alumnos y docentes, fechas, reglas diarias, alertas e inteligencia, y bitácora.',
          _tarjetaCentroAulas),
      if (_ve('academico')) _OpcionAdmin('Aula Virtual (Moodle)',
          'Panorama de cursos (inscritos, activos, promedio) y la actividad de cada alumno en el Aula.',
          _tarjetaMoodle),
      if (_ve('academico')) _OpcionAdmin('SIGA · Exportables para la SEC',
          'Diagnóstico de lo que falta, paquetes para el portal, alumnos pendientes, equivalencias de generaciones y bitácora.',
          _tarjetaSigaEquivalencias),
    ];
  }

  List<Widget> _resultadosAdmin() {
    final q = _normBuscaAdmin(_qAdmin.trim());
    // (4-oct-2026) También por palabras relacionadas; primero lo que coincide en el nombre.
    final terminos = _terminosAdmin(q);
    int puntaje(_OpcionAdmin o) {
      final n = _normBuscaAdmin(o.titulo), d = _normBuscaAdmin(o.descripcion);
      if (n.contains(q)) return 0;
      if (d.contains(q)) return 1;
      if (terminos.any((x) => n.contains(x))) return 2;
      if (terminos.any((x) => d.contains(x))) return 3;
      return 9;
    }
    final res = _catalogoAdmin().where((o) => puntaje(o) < 9).toList()
      ..sort((x, y) => puntaje(x).compareTo(puntaje(y)));
    if (res.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'Sin resultados. Prueba: actas, pagos, SIGA, contratos, riesgo…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
            ),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text('${res.length} resultado(s)',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      ),
      for (final o in res) ...[
        o.builder(),
        const SizedBox(height: 10),
      ],
    ];
  }

  // =====================================================================
  //  (4-oct-2026) PANEL EN CUADRÍCULA DE CARPETAS (como la vista de alumno).
  //  Cada grupo es una tarjeta-widget (2 columnas en celular, 3 en tableta,
  //  4 en computadora). Al tocarla, sus opciones se abren en un panel sobre
  //  la pantalla. Las opciones son EXACTAMENTE las mismas tarjetas, con sus
  //  mismos permisos (_ve) y acciones.
  // =====================================================================
  _CarpetaAdmin _grupoAdmin(String titulo, IconData icono, List<Widget> hijos) =>
      // Los espaciadores (SizedBox) no son opciones: no cuentan ni se dibujan.
      _CarpetaAdmin(titulo, icono, hijos.where((w) => w is! SizedBox).toList());

  /// Una línea de descripción por grupo, para la tarjeta-widget.
  static const Map<String, String> _descGrupo = {
    'Atención del día': 'Adaptaciones, seguimiento docente, oficios, tesis y convenios',
    'Centros inteligentes': 'Centro de mando, bandeja, expediente 360, auditoría y más',
    'Tableros de dirección': 'Finanzas, salud del sistema, señales, altas y bajas',
    'Tableros y reportes': 'Tableros, estadísticas, análisis y reportes',
    'Admisiones y becas': 'Aspirantes, panel y página de admisiones, referidos y becas',
    'Grupos y alumnos': 'Altas, grupos, cambios, horarios y padrón',
    'Calificaciones y captura': 'Captura, actas, riesgo, recursamientos y reingresos',
    'Docentes y contratos': 'Profesores, carga docente, cobertura y contratos',
    'Trámites y documentos': 'Trámites, credenciales, titulación y constancias',
    'Pagos': 'Pagos, colegiaturas, seguimiento y no adeudo',
    'Comunicación': 'Circulares, avisos, correos y calendario',
    'Administración del sistema': 'Bitácora, roles, respaldos, Moodle, Centro de aulas y SIGA',
  };

  /// Todas las carpetas del panel. Se vuelve a calcular cada vez que hace
  /// falta, para que una carpeta abierta muestre el estado al día.
  List<_CarpetaAdmin> _carpetasAdmin() => [
    // (24-sep) Lo del día y los centros inteligentes, al frente: son las dos primeras carpetas.
    _grupoAdmin('Atención del día', Icons.today_outlined, [
      if (_ve('academico')) _tarjetaAdaptaciones(),
      if (_ve('academico')) _tarjetaSeguimientoDocente(),
      if (_ve('academico')) _tarjetaOficios(),
      if (_ve('academico')) _tarjetaTesisSolicitudes(),
      if (_ve('documentos')) _tarjetaConvenios(),
    ]),
    _grupoAdmin('Centros inteligentes', Icons.hub_outlined, [
      if (_ve('academico')) _tarjetaCentroMando(),
      if (_ve('academico')) _tarjetaBandeja(),
      if (_ve('academico')) _tarjetaExpediente360(),
      if (_ve('academico')) _tarjetaComunicaciones(),
      if (_ve('academico')) _tarjetaAsistenteOps(),
      if (_ve('academico')) _tarjetaAuditoria(),
      if (_ve('academico')) _tarjetaCalidadDatos(),
      if (_ve('academico')) _tarjetaRetencionPredictiva(),
      if (_ve('academico')) _tarjetaCobranza(),
      if (_ve('academico')) _tarjetaPlaneacionCiclo(),
      if (_ve('academico')) _tarjetaCalendarioOperativo(),
      if (_ve('academico')) _tarjetaExpedienteDocente(),
      if (_ve('academico')) _tarjetaPendientesDia(),
    ]),
    // ===== OPCIONES AGRUPADAS EN SECCIONES COLAPSABLES =====
    _grupoAdmin('Tableros de dirección', Icons.monitor_heart_outlined, [
      if (_esFinanzas) _tarjetaFinanzas(),
      if (_ve('academico')) _tarjetaSaludSistema(),
      if (_ve('academico')) _tarjetaSenales(),
      if (_ve('academico')) _tarjetaAltasInscripcion(),
      if (_ve('academico')) _tarjetaSimulador(),
      if (_ve('academico')) _tarjetaBajasPago(),
      if (_ve('academico')) _tarjetaBloqueos(),
      if (_ve('academico')) _tarjetaQuejas(),
      if (_ve('academico')) _tarjetaBecasConvocatoria(),
      if (_ve('academico')) _tarjetaCumplimientoAcuerdo(),
    ]),

    _grupoAdmin('Tableros y reportes', Icons.insights, [
      if (_ve('academico')) _tarjetaTablero(),
      if (_ve('academico')) _tarjetaTableroBI(),
      if (_ve('academico')) _tarjetaTableroRapido(),
      if (_ve('academico')) _tarjetaResumenEjecutivo(),
      if (_ve('academico')) _tarjetaCentroInteligencia(),
      if (_ve('academico')) _tarjetaEstadisticasPadron(),
      if (_ve('academico')) _tarjetaAnalisisCalificaciones(),
      if (_ve('academico')) _tarjetaComparativoGeneraciones(),
      if (_ve('academico')) _tarjetaAutoevaluacion(),
      if (_ve('academico')) _tarjetaReportesDatos(),
      if (_ve('academico')) _tarjetaSaludDatos(),
      if (_ve('academico')) _tarjetaCursosVigentes(),
      _tarjetaUsoIa(),
    ]),

    _grupoAdmin('Admisiones y becas', Icons.how_to_reg, [
      _tarjetaAspirantes(),
      // (4-oct-2026) El panel de admisiones (cessum.mx) y la página pública de registro.
      _tarjetaPanelAdmisiones(),
      _tarjetaPaginaAdmisiones(),
      _tarjetaAnomalias(),
      _tarjetaRecomienda(),
      _tarjetaBecasTipos(),
      const SizedBox(height: 10),
      _tarjetaBecados(),
    ]),

    _grupoAdmin('Grupos y alumnos', Icons.groups, [
      if (_ve('academico')) _tarjetaAltaAlumno(),
      if (_ve('academico')) _tarjetaAltaLote(),
      // Las dos herramientas de cambio, JUNTAS para elegir la correcta:
      // "Cambio de programa" PROMUEVE (p. ej. maestría → doctorado)
      // conservando historial; "Cambiar de programa o generación"
      // CORRIGE programa/generación/grupo moviendo materias y actas.
      _tarjetaCambioPrograma(),
      if (_ve('academico')) _tarjetaCambiarPrograma(),
      if (_ve('academico')) _tarjetaAvancePrograma(),
      if (_ve('academico')) _tarjetaPlanesFaltantes(),
      if (_ve('academico')) _tarjetaOperacionesLote(),
      if (_ve('academico')) _tarjetaGrupos(),
      if (_ve('academico')) _tarjetaCorregirGrupo(),
      // (5-oct-2026) Cambiar la matrícula de un alumno (la función existía, pero solo por URL).
      if (_ve('academico')) _tarjetaCambiarMatricula(),
      if (_ve('academico')) _tarjetaListasAsistencia(),
      if (_ve('academico')) _tarjetaClasificacion(),
      if (_ve('academico')) _tarjetaPlaneacionesRevision(),
      if (_ve('academico')) _tarjetaAgendaProfesores(),
      if (_ve('academico')) _tarjetaRespuestasDocentes(),
      if (_ve('academico')) _tarjetaTableroProgramacion(),
      if (_ve('academico')) _tarjetaMateriasSinMaestro(),
      if (_ve('academico')) _tarjetaRecordatorioInvitaciones(),
      if (_ve('academico')) _tarjetaLocalizadorAlumnos(),
      if (_ve('academico')) _tarjetaHorarios(),
      if (_ve('academico')) _tarjetaChoquesHorario(),
      if (_ve('academico')) _tarjetaCorreccionesPadron(),
      if (_ve('ficha')) _tarjetaFicha(),
      if (_ve('bajas')) _tarjetaBajas(),
    ]),

    _grupoAdmin('Calificaciones y captura', Icons.edit_note, [
      if (_ve('academico')) _tarjetaTorreControl(),
      if (_ve('academico')) _tarjetaAvanceCaptura(),
      if (_ve('academico')) _tarjetaRecordatorioCaptura(),
      if (_ve('academico')) _tarjetaSemaforo(),
      if (_ve('academico')) _tarjetaValidacionActas(),
      if (_ve('academico')) _tarjetaEditarCalificaciones(),
      if (_ve('academico')) _tarjetaEvaluacionGrupo(),
      if (_ve('academico')) _tarjetaImportador(),
      if (_ve('academico')) _tarjetaAvance(),
      if (_ve('academico')) _tarjetaRiesgo(),
      if (_ve('solicitudesCorreccion')) _tarjetaSolicitudesCorreccion(),
      // (ago-28) El panel de recursamientos vivía SOLO en el catálogo
      // del buscador (menu_screen), con soloAdmin puesto. Funcionaba,
      // pero para llegar a él había que adivinar la palabra y buscarla:
      // en el menú de administración no existía. Aquí es donde se busca.
      if (_ve('academico')) _tarjetaRecursamientos(),
      if (_ve('justificaciones')) _tarjetaReingresos(),
    ]),

    _grupoAdmin('Docentes y contratos', Icons.co_present, [
      if (_ve('academico')) _tarjetaProfesores(),
      if (_ve('academico')) _tarjetaDirectorioDocentes(),
      if (_ve('academico')) _tarjetaCargaDocente(),
      if (_ve('academico')) _tarjetaCobertura(),
      if (_ve('academico')) _tarjetaResumenDocentes(),
      if (_ve('academico')) _tarjetaRecordatorioDocentes(),
      if (_ve('academico')) _tarjetaContratosValidar(),
      if (_ve('academico')) _tarjetaTableroContratos(),
      if (_ve('academico')) _tarjetaContratosFaltantes(),
      if (_ve('academico')) _tarjetaRefrescarPadron(),
    ]),

    _grupoAdmin('Trámites y documentos', Icons.description, [
      if (_ve('tramites')) _tarjetaTramites(),
      if (_ve('justificaciones')) _tarjetaJustificaciones(),
      if (_ve('credenciales')) _tarjetaCredenciales(),
      if (_ve('titulacion')) _tarjetaTitulacion(),
      if (_ve('titulacion')) _tarjetaTitulacionCierre(),
      if (_ve('titulacion')) _tarjetaExpedientes(),
      if (_ve('documentos')) _tarjetaConstanciasLote(),
      if (_ve('documentos')) _tarjetaDocumentos(),
      _tarjetaDocumentosPlantilla(),
      if (_ve('academico')) _tarjetaDiplomaCongreso(),
      if (_ve('academico')) _tarjetaVerificadorQr(),
      if (_ve('academico')) _tarjetaBoletasPeriodo(),
    ]),

    _grupoAdmin('Pagos', Icons.payments, [
      if (_ve('pagos')) _tarjetaPagos(),
      if (_ve('pagos')) _tarjetaCostosColegiaturas(),
      if (_ve('pagos')) _tarjetaMontoPorGrupo(),
      if (_ve('seguimientoPagos')) _tarjetaSeguimientoPagos(),
      if (_ve('seguimientoPagos')) _tarjetaPagosDocentes(),
      if (_ve('seguimientoPagos')) _tarjetaPagosAdministrativos(),
      if (_ve('pagos')) _tarjetaVencimientos(),
      if (_ve('pagos')) _tarjetaNoAdeudo(),
    ]),

    _grupoAdmin('Comunicación', Icons.campaign, [
      if (_ve('avisos')) _tarjetaCircular(),
      if (_ve('academico')) _tarjetaComunicado(),
      if (_ve('academico')) _tarjetaFormatos(),
      if (_ve('avisos')) _tarjetaBuzonEventos(),
      if (_ve('avisos')) _tarjetaBandejaCorreos(),
      if (_ve('avisos')) _tarjetaMarketing(),
      if (_ve('avisos')) _tarjetaCalendario(),
      if (_ve('avisos')) _tarjetaEnviarNotificacion(),
      if (_ve('avisos')) _tarjetaAvisos(),
      if (_ve('academico')) _tarjetaVistos(),
      if (_ve('academico')) _tarjetaBitacoraCorreos(),
    ]),

    _grupoAdmin('Administración del sistema', Icons.settings, [
      if (_ve('academico')) _tarjetaBitacora(),
      if (_rol == 'total') _tarjetaRoles(),
      if (_rol == 'total') _tarjetaRespaldos(),
      if (_ve('academico')) _tarjetaRespaldoExcel(),
      if (_ve('academico')) _tarjetaAutomatizaciones(),
      if (_ve('accesos')) _tarjetaAccesos(),
      if (_ve('incidencias')) _tarjetaIncidencias(),
      if (_ve('control')) _tarjetaHerramientas(),
      // Panel "Constancias de estudios" retirado: la constancia de
      // estudios se solicita y resuelve desde Trámites escolares.
      if (_ve('academico')) _tarjetaMoodle(),
      // (4-oct-2026) Centro de aulas en aula.cessum.mx: mapa, personas, reglas e inteligencia.
      if (_ve('academico')) _tarjetaCentroAulas(),
      if (_ve('academico')) _tarjetaSigaEquivalencias(),
    ]),
  ];

  /// Avisa a la carpeta abierta que el panel cambió (el semáforo, un contador…).
  final ValueNotifier<int> _refrescoAdmin = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (mounted) _refrescoAdmin.value++;
  }

  int _columnasAdmin(double ancho) => ancho < 600 ? 2 : (ancho < 1024 ? 3 : 4);

  Widget _rejillaAdmin(List<_CarpetaAdmin> carpetas) {
    final visibles = carpetas.where((c) => c.hijos.isNotEmpty).toList();
    return LayoutBuilder(builder: (ctx, cons) {
      final cols = _columnasAdmin(cons.maxWidth);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 14),
        itemCount: visibles.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 156,
        ),
        itemBuilder: (_, i) => _tarjetaCarpetaAdmin(visibles[i]),
      );
    });
  }

  Widget _tarjetaCarpetaAdmin(_CarpetaAdmin g) {
    final n = g.hijos.length;
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _abrirCarpetaAdmin(g.titulo),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cessumRed.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(g.icono, color: cessumRed, size: 27),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$n',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: cessumGold)),
              ),
            ]),
            const Spacer(),
            Text(g.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(_descGrupo[g.titulo] ?? '$n ${n == 1 ? 'opción' : 'opciones'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ]),
        ),
      ),
    );
  }

  /// Abre el grupo como carpeta: panel sobre la pantalla, fondo desenfocado,
  /// y sus tarjetas en 1, 2 o 3 columnas según el ancho. Se redibuja cuando
  /// el panel cambia, para que lo que se ve adentro esté al día.
  void _abrirCarpetaAdmin(String titulo) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar $titulo',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dCtx, _, __) {
        final tam = MediaQuery.of(dCtx).size;
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 1100, maxHeight: tam.height * 0.88),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: cessumBg(dCtx),
                    borderRadius: BorderRadius.circular(28),
                    clipBehavior: Clip.antiAlias,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _refrescoAdmin,
                      builder: (_, __, ___) {
                        final lista = _carpetasAdmin().where((c) => c.titulo == titulo).toList();
                        if (lista.isEmpty) return const SizedBox.shrink();
                        final g = lista.first;
                        return Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            color: Theme.of(dCtx).cardColor,
                            padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
                            child: Row(children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: cessumRed.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(g.icono, color: cessumRed, size: 23),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(g.titulo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                  Text('${g.hijos.length} ${g.hijos.length == 1 ? 'opción' : 'opciones'}'
                                      '${_descGrupo[g.titulo] != null ? ' · ${_descGrupo[g.titulo]}' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: cessumMuted(dCtx))),
                                ]),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: () => Navigator.pop(dCtx),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ]),
                          ),
                          Container(height: 3, decoration: const BoxDecoration(gradient: LinearGradient(colors: [cessumRed, cessumGold]))),
                          Flexible(
                            child: LayoutBuilder(builder: (_, cons) {
                              const sep = 12.0;
                              final w = cons.maxWidth - 28;
                              final cols = w < 640 ? 1 : (w < 980 ? 2 : 3);
                              final anchoTarjeta = (w - sep * (cols - 1)) / cols;
                              return SingleChildScrollView(
                                padding: const EdgeInsets.all(14),
                                child: Wrap(
                                  spacing: sep,
                                  runSpacing: sep,
                                  children: [for (final h in g.hijos) SizedBox(width: anchoTarjeta, child: h)],
                                ),
                              );
                            }),
                          ),
                        ]);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curva = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curva,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curva), child: child),
        );
      },
    );
  }

  /// (4-oct-2026) El buscador del panel, protagonista y fijo arriba.
  static const List<String> _sugerenciasAdmin = [
    'Actas', 'Pagos', 'SIGA', 'Contratos', 'Bajas', 'Credenciales', 'Grupos', 'Correos',
  ];

  Widget _buscadorAdmin() {
    final esc = MediaQuery.textScalerOf(context).scale(1.0);
    return Container(
      color: cessumBg(context),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: cessumRed.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 5))],
          ),
          child: TextField(
            controller: _buscaAdminCtrl,
            onChanged: (v) => setState(() => _qAdmin = v),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '¿Qué necesitas atender hoy?',
              hintStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: cessumMuted(context)),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.search_rounded, color: cessumRed, size: 26),
              ),
              suffixIcon: _qAdmin.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() {
                        _buscaAdminCtrl.clear();
                        _qAdmin = '';
                      }),
                    ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: cessumRed.withValues(alpha: 0.18))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: cessumRed.withValues(alpha: 0.18))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: cessumRed, width: 1.6)),
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34 * esc,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _sugerenciasAdmin.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final s = _sugerenciasAdmin[i];
              final activa = _normBuscaAdmin(_qAdmin.trim()) == _normBuscaAdmin(s);
              return ActionChip(
                label: Text(s),
                labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: activa ? Colors.white : cessumRed),
                backgroundColor: activa ? cessumRed : cessumRed.withValues(alpha: 0.07),
                side: BorderSide(color: cessumRed.withValues(alpha: activa ? 1 : 0.15)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _buscaAdminCtrl.text = s;
                  _qAdmin = s;
                }),
              );
            },
          ),
        ),
      ]),
    );
  }

  /// Palabras relacionadas del panel (sin acentos, en minúsculas).
  static const Map<String, List<String>> _relacionadasAdmin = {
    'acta': ['calificacion', 'captura', 'validacion', 'boleta'],
    'calificacion': ['acta', 'captura', 'boleta', 'riesgo', 'evaluacion'],
    'pago': ['colegiatura', 'cobranza', 'adeudo', 'vencimiento', 'finanzas', 'nomina'],
    'cobranza': ['pago', 'adeudo', 'vencimiento', 'colegiatura'],
    'siga': ['sec', 'exportable', 'equivalencia'],
    'contrato': ['docente', 'profesor', 'carga'],
    'docente': ['profesor', 'maestro', 'contrato', 'carga', 'cobertura'],
    'maestro': ['docente', 'profesor', 'carga'],
    'baja': ['bloqueo', 'adeudo', 'reingreso', 'retencion'],
    'credencial': ['identidad', 'foto', 'verificador'],
    'grupo': ['alumno', 'padron', 'horario', 'programa', 'generacion'],
    'alumno': ['grupo', 'padron', 'expediente', 'localizador', 'matricula'],
    'matricula': ['alumno', 'padron', 'cambiar matricula'],
    'correo': ['circular', 'aviso', 'notificacion', 'marketing', 'bitacora'],
    'aviso': ['circular', 'comunicado', 'notificacion', 'correo'],
    'tramite': ['documento', 'constancia', 'justificacion', 'solicitud'],
    'constancia': ['documento', 'tramite', 'boleta'],
    'titulo': ['titulacion', 'tesis', 'expediente'],
    'tesis': ['titulacion', 'director', 'expediente'],
    'beca': ['becado', 'convocatoria', 'descuento'],
    'aspirante': ['admision', 'inscripcion', 'referido'],
    'admision': ['aspirante', 'inscripcion', 'registro'],
    'aula': ['moodle', 'centro de aulas', 'curso'],
    'horario': ['choque', 'agenda', 'programacion'],
    'moodle': ['aula', 'curso', 'centro de aulas'],
    'respaldo': ['excel', 'copia'],
    'rol': ['permiso', 'acceso'],
  };

  List<String> _terminosAdmin(String q) {
    if (q.length < 3) return const [];
    final out = <String>{};
    _relacionadasAdmin.forEach((clave, rel) {
      final toca = q.contains(clave) || clave.startsWith(q) || rel.any((r) => r.startsWith(q) || q.contains(r));
      if (toca) {
        out.add(clave);
        out.addAll(rel);
      }
    });
    out.remove(q);
    return out.toList();
  }

  Future<void> _cargarPendientes() async {
    try {
      final r = await http_pend
          .get(Uri.parse('$guardianUrl?accion=pendientes_admin'))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() => _pend = (d['pendientes'] as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
      }
    } catch (_) {}
  }

  Widget _conBadge(int n, Widget child) {
    if (n <= 0) return child;
    return Badge(
      label: Text('$n'),
      backgroundColor: const Color(0xFFD32F2F),
      child: child,
    );
  }
  String? _programa;
  String? _modalidad;
  String? _generacion;

  List<GeneracionItem> _generaciones = [];
  bool _cargandoGeneraciones = true;
  String? _errorGeneraciones;

  // Semáforo de captura de calificaciones
  bool? _capturaAbierta; // null = cargando
  bool _cambiandoSemaforo = false;
  String? _errorSemaforo;

  // Contadores de solicitudes pendientes (trámites, justificaciones, bajas).
  final Map<String, int> _pendientes = {};

  @override
  void dispose() {
    _buscaAdminCtrl.dispose();
    _refrescoAdmin.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargarPendientes();
    _cargarRol();
    // Preseleccionamos el primer programa y la primera modalidad para que
    // el administrador pueda previsualizar con un solo toque.
    _programa = programasAcademicos.first.nombre;
    _modalidad = modalidadesEstudio.first;
    _cargarGeneraciones();
    _cargarSemaforo();
    _cargarContadores();
  }

  Future<void> _cargarContadores() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'solicitudes_contadores'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && mounted) {
        setState(() {
          _pendientes['tramites'] = (data['tramites'] ?? 0) as int;
          _pendientes['justificaciones'] = (data['justificaciones'] ?? 0) as int;
          _pendientes['bajas'] = (data['bajas'] ?? 0) as int;
        });
      }
    } catch (_) {
      // Silencioso: los contadores son un extra; no rompen la pantalla.
    }
  }

  Widget _badgePendientes(int n) {
    if (n <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: cessumRed,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$n',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800)),
    );
  }

  Future<void> _cargarSemaforo() async {
    setState(() {
      _errorSemaforo = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'estado_captura'});
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        if (mounted) setState(() => _capturaAbierta = data['abierta'] == true);
      } else {
        throw Exception('respuesta inválida');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorSemaforo = 'No se pudo leer el estado de la captura.';
        });
      }
    }
  }

  Future<void> _cambiarSemaforo(bool abrir) async {
    // (24-sep) Afecta a TODOS los docentes: se confirma antes, diciendo qué pasa.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(abrir ? 'Abrir la captura de calificaciones' : 'Cerrar la captura de calificaciones',
            style: const TextStyle(fontSize: 16)),
        content: Text(
            abrir
                ? 'Todos los docentes podrán capturar y modificar calificaciones desde la app hasta que la vuelva a cerrar.'
                : 'Ningún docente podrá capturar ni modificar calificaciones desde la app hasta que la vuelva a abrir. '
                    'Lo ya capturado no se pierde.',
            style: const TextStyle(fontSize: 13.5, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: abrir ? const Color(0xFF1E8E3E) : cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(abrir ? 'Abrir captura' : 'Cerrar captura'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _cambiandoSemaforo = true;
      _errorSemaforo = null;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'set_captura',
        'valor': abrir ? 'abierta' : 'cerrada',
      });
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        if (mounted) {
          setState(() {
            _capturaAbierta = data['abierta'] == true;
            _cambiandoSemaforo = false;
          });
        }
      } else {
        // (24-sep) El motivo real (p. ej. «cierre sesión y vuelva a entrar»),
        // no un «intenta de nuevo» que no dice qué hacer.
        throw Exception((data['error'] ?? 'respuesta inválida').toString());
      }
    } catch (e) {
      final m = '$e'.replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() {
          _cambiandoSemaforo = false;
          _errorSemaforo = (m.isEmpty || m == 'respuesta inválida' || m.contains('TimeoutException'))
              ? 'No se pudo cambiar el estado. Intenta de nuevo.'
              : m;
        });
      }
    }
  }

  Future<void> _cargarGeneraciones() async {
    setState(() {
      _cargandoGeneraciones = true;
      _errorGeneraciones = null;
    });
    try {
      final lista = await GeneracionesService.obtener();
      if (!mounted) return;
      setState(() {
        _generaciones = lista;
        _generacion = lista.isNotEmpty ? lista.first.nombre : null;
        _cargandoGeneraciones = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoGeneraciones = false;
        _errorGeneraciones = 'No se pudo cargar la lista de generaciones';
      });
    }
  }

  // Crea un perfil de alumno de DEMOSTRACION y entra al menu de estudiante.
  Future<void> _verComoEstudiante() async {
    await SessionStore.stopImpersonation();
    final perfil = StudentProfile(
      matricula: '00000000',
      nombreCompleto: 'Vista previa de alumno',
      programa: _programa ?? programasAcademicos.first.nombre,
      modalidad: _modalidad ?? modalidadesEstudio.first,
      generacion: _generacion ?? 'Generacion de prueba',
      esVistaAdmin: true,
    );
    await perfil.save();
    await ActiveProfile.setActive(ProfileType.student);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MenuScreen()),
    );
  }

  // Abre el selector para entrar al portal docente como un PROFESOR REAL
  // del padrón (ve sus clases y sus actas).
  Future<void> _verComoDocente() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ElegirProfesorScreen()),
    );
  }

  void _abrirComoUsuarioNormal() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        title: const Text(
          'Vista de administrador',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      // (4-oct-2026) El buscador queda fijo arriba, siempre visible; debajo, la misma lista.
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _BuscadorFijoAdmin(
              alto: 62 + 56 * MediaQuery.textScalerOf(context).scale(1.0),
              construir: _buscadorAdmin,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
        [
          if ((_pend['tramites'] ?? 0) + (_pend['justificaciones'] ?? 0) +
                  (_pend['incidencias'] ?? 0) + (_pend['correcciones'] ?? 0) +
                  (_pend['titulacion'] ?? 0) >
              0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFD32F2F).withValues(alpha: 0.35)),
              ),
              child: Text(
                'Pendientes por atender:  '
                'Trámites ${_pend['tramites'] ?? 0}  ·  '
                'Incidencias ${_pend['incidencias'] ?? 0}  ·  '
                'Correcciones ${_pend['correcciones'] ?? 0}  ·  '
                'Justificaciones ${_pend['justificaciones'] ?? 0}  ·  '
                'Titulación ${_pend['titulacion'] ?? 0}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB11D29)),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Aviso explicativo
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.admin_panel_settings, color: cessumGold, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modo administrador',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Previsualiza la app tal como la ven los usuarios. '
                        'Se usa un perfil de demostracion; no afecta la lista '
                        'real de alumnos.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ============================================================
          // PANEL REORGANIZADO (jul-2026): las tarjetas sueltas se
          // integraron a los grupos; "Tableros y reportes" quedó solo con
          // tableros; grupo nuevo "Admisiones y becas"; contratos con
          // Docentes; y las DOS herramientas de cambio de programa quedan
          // juntas en Grupos y alumnos para elegir la correcta.
          // ============================================================

          // Siempre visibles: el asistente, el buscador y lo urgente del día.
          _tarjetaAsistenteIa(),
          const SizedBox(height: 10),
          if (_ve('academico')) _tarjetaBuscadorGlobal(),
          // (4-oct-2026) Atención del día y Centros inteligentes: ahora son las dos primeras carpetas.
          const SizedBox(height: 12),

          if (_qAdmin.trim().isEmpty) ...[
          // (4-oct-2026) Los grupos, en cuadrícula de carpetas (ver _carpetasAdmin y _rejillaAdmin).
          _rejillaAdmin(_carpetasAdmin()),
          ] else ...[
            ..._resultadosAdmin(),
          ],

          const SizedBox(height: 8),

          // ===== Seccion: Ver como un alumno real =====
          const _TituloSeccion('Ver como un alumno real'),
          const SizedBox(height: 6),
          Text(
            'Entra a la app tal como la ve un alumno especifico de la lista. '
            'Sirve para reproducir un problema que reporte un alumno y entender '
            'su experiencia.',
            style: TextStyle(fontSize: 13, color: cessumMuted(context)),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 2,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminAlumnoPickerScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.person_search, size: 20),
              label: const Text(
                'Elegir un alumno...',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 20),

          // ===== Seccion: Ver con un perfil de demostracion =====
          const _TituloSeccion('Ver con un perfil de demostracion'),
          const SizedBox(height: 12),

          const _Etiqueta('Programa academico'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _programa,
            isExpanded: true,
            decoration: _deco(),
            items: programasAcademicos
                .map((p) => DropdownMenuItem<String>(
                      value: p.nombre,
                      child: Text(p.nombre, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _programa = v),
          ),
          const SizedBox(height: 16),

          const _Etiqueta('Modalidad'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _modalidad,
            isExpanded: true,
            decoration: _deco(),
            items: modalidadesEstudio
                .map((m) => DropdownMenuItem<String>(
                      value: m,
                      child: Text(m),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _modalidad = v),
          ),
          const SizedBox(height: 16),

          const _Etiqueta('Generación'),
          const SizedBox(height: 6),
          if (_cargandoGeneraciones)
            _cajaCargando()
          else if (_errorGeneraciones != null)
            _cajaError()
          else
            // (24-sep) Con búsqueda: son todas las generaciones.
            CessumSelectorBuscable<String>(
              label: 'Generación',
              valor: _generacion,
              opciones: _generaciones.map((g) => g.nombre).toList(),
              etiqueta: (g) => g,
              hint: 'Selecciona una generación',
              decoracion: _deco(),
              onChanged: (v) => setState(() => _generacion = v),
            ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 2,
              ),
              onPressed: _verComoEstudiante,
              icon: const Icon(Icons.school, size: 20),
              label: const Text(
                'Ver como estudiante',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 32),

          const Divider(),
          const SizedBox(height: 20),

          // ===== Seccion: Ver como profesor =====
          const _TituloSeccion('Ver como profesor'),
          const SizedBox(height: 6),
          Text(
            'Elige un profesor real: entra a su portal (efectos reales) o sube su firma.',
            style: TextStyle(fontSize: 13, color: cessumMuted(context)),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _verComoDocente,
              icon: const Icon(Icons.cast_for_education, size: 20),
              label: const Text(
                'Ver como profesor',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Nota: como salir de la vista previa
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.swap_horiz, color: cessumMuted(context), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Para salir de la vista previa: dentro del menu toca el '
                    'icono de las dos flechas (arriba a la derecha) para '
                    '"Cambiar perfil" y regresa a esta pantalla.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: cessumMuted(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Center(
            child: TextButton(
              onPressed: _abrirComoUsuarioNormal,
              child: const Text(
                'Abrir pantalla de inicio normal',
                style: TextStyle(color: cessumRed),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Helpers de estilo / cajas (mismo look que el resto de la app) ----

  Widget _tarjetaSolicitudesCorreccion() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const SolicitudesCorreccionScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _conBadge(_pend['correcciones'] ?? 0, const Icon(Icons.edit_note, color: cessumGold, size: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitudes de corrección',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Aprueba o rechaza las correcciones que piden los docentes.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaTramites() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TramitesListaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.assignment, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trámites escolares',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Solicitudes de constancias, boletas, kardex, etc. Márcalas como atendidas o rechazadas.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              _badgePendientes(_pendientes['tramites'] ?? 0),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaPagosDocentes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PagosDocentesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.payments, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pagos a docentes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Registra pagos por asignatura (acta validada), adjunta el comprobante y avisa al profesor.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRecomienda() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RecomiendaAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.card_giftcard, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recomendaciones',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                        'Registra aspirantes por código y habilita la bonificación del alumno.',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaBecasTipos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BecasTiposAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.school, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Becas por tipo',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                        'USICAMM, Indígena, Discapacidad, Directa y Crédito Educativo. Aplica el % en la hoja de becas.',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  /// (4-oct-2026) Tarjeta que abre una página web, con el mismo aspecto que las demás del panel.
  Widget _tarjetaEnlace({
    required IconData icono,
    required String titulo,
    required String descripcion,
    required String url,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Helpers.abrirUrlExterna(url, context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cessumInk(context))),
                    const SizedBox(height: 3),
                    Text(descripcion, style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, color: cessumRed, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaPanelAdmisiones() => _tarjetaEnlace(
        icono: Icons.support_agent,
        titulo: 'Panel de admisiones',
        descripcion: 'Seguimiento de aspirantes, contactos y conversaciones de admisiones.',
        url: 'https://cessum.mx/adminadmisiones.php',
      );

  Widget _tarjetaPaginaAdmisiones() => _tarjetaEnlace(
        icono: Icons.public,
        titulo: 'Página de admisiones',
        descripcion: 'La página pública donde los aspirantes se registran: para revisarla o compartirla.',
        url: 'https://www.cessum.mx/admisiones',
      );

  Widget _tarjetaCentroAulas() => _tarjetaEnlace(
        icono: Icons.dashboard_customize_outlined,
        titulo: 'Centro de aulas',
        descripcion: 'Revisión de las aulas de Moodle: mapa, alumnos y docentes, fechas, reglas diarias, alertas e inteligencia. '
            'Pide tu sesión de administrador del Aula.',
        url: 'https://aula.cessum.mx/centro_aulas.php',
      );

  Widget _tarjetaAspirantes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AspirantesPendientesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.how_to_reg, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aspirantes',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                        'Triage de inscripciones: semáforo por matrícula, código y pago. Marca lo revisado.',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAnomalias() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AltasAnomaliasScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fact_check, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Anomalías de alta',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                        'Verifica si alguien ya existe antes de darlo de alta y detecta matrículas, correos y CURPs duplicados.',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaDocumentosPlantilla() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DocumentosPlantillaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Documentos por plantilla',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                        'Reconocimientos y constancias con QR de verificación, en una sola pantalla.',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCambioPrograma() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CambioProgramaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.school, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cambio de programa',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                        'Promueve a un alumno (p. ej. de maestría a doctorado) conservando su matrícula e historial.',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaUsoIa() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UsoIaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Uso de IA',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Cuántas consultas se han hecho al asistente: hoy, semana, mes y quién la usa más.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAsistenteIa() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AsistenteIaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.smart_toy, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Asistente IA',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Pregúntale en lenguaje natural; te ayuda a localizar y usar las secciones del panel.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAltaAlumno() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AltaAlumnoScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_add_alt_1,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dar de alta alumno',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Registra un alumno nuevo en el grupo y en el padrón (matrícula, programa, generación).',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAltaLote() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AltaLoteScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.group_add,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dar de alta por lote',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Da de alta a varios alumnos de una vez: pegas la lista, ves la vista previa y el reporte.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaContratosValidar() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContratosValidacionScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fact_check_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contratos por validar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Revisa los contratos que los profesores firmaron y envíalos por correo al validarlos.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaTableroContratos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContratosTableroScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights_outlined,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tablero de contratos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Contadores por estatus y exportación a Excel de todos los contratos.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRespaldoExcel() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RespaldoExcelScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.backup_outlined,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Respaldo en Excel',
                        style: TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w700, color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                      'Descarga las hojas clave (calificaciones, asignaciones, alumnos, contratos) en un Excel.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCargaDocente() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CargaDocenteScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.balance,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Carga docente',
                        style: TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w700, color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                      'Cuántas materias trae cada maestro y quiénes están sobrecargados.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaBecados() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BecasAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.verified_outlined,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Becados · autorizar solicitudes',
                        style: TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w700, color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                      'Dictamina las solicitudes que suben los alumnos '
                      '(IBCEES, crédito educativo), captura el porcentaje y '
                      'genera el convenio de beca.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRecordatorioCaptura() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RecordatorioCapturaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mark_email_unread_outlined,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recordatorio de captura',
                        style: TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w700, color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                      'Avisa por correo a los docentes con captura de calificaciones pendiente.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaContratosFaltantes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContratosFaltantesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.assignment_late_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contratos pendientes',
                        style: TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w700, color: cessumInk(context))),
                    SizedBox(height: 3),
                    Text(
                      'Qué docentes tienen materias activas sin contrato, para dar seguimiento.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCambiarPrograma() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CambiarProgramaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.swap_horiz,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cambiar de programa o generación',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Mueve al alumno de programa, generación o grupo en un solo paso (materias y actas incluidas).',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  // V467: alta de docente que SI escribe en la hoja 'Docentes' (con semblanza).
  // La pantalla ya existia pero ningun menu la abria.
  Widget _tarjetaDocenteAlta() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DocenteAltaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_add_alt_1,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dar de alta docente',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Escribe en la hoja Docentes con su semblanza (la que usan las cartas y portadas) y le manda su correo de bienvenida.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  // V467: el padron se cachea 6 h. Si mueves la hoja a mano (Excel/Sheets),
  // el cambio no se ve hasta que vence. Esto lo refresca al instante.
  Future<void> _refrescarPadron() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    String msg;
    bool bien = false;
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=cache_refrescar'))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      bien = d['ok'] == true;
      msg = bien
          ? 'Padron actualizado. Los cambios que hiciste en la hoja ya se ven.'
          : (d['error']?.toString() ?? 'No se pudo actualizar.');
    } catch (_) {
      msg = 'No se pudo conectar. Revisa tu conexion.';
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: bien ? const Color(0xFF1E8E3E) : cessumRed,
      content: Text(msg),
    ));
  }

  Widget _tarjetaRefrescarPadron() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: _refrescarPadron,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.sync, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Actualizar padron ahora',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Usalo cuando edites las hojas a mano: el padron se guarda 6 horas y esto lo vuelve a leer al instante.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaProfesores() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfesoresAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.school_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profesores',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Agrega, edita o da de baja docentes. Se refleja al instante, sin regenerar archivos.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaBuscadorGlobal() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BuscadorGlobalScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.search, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Buscador global',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Encuentra cualquier alumno o profesor por nombre, matrícula o correo.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaOperacionesLote() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OperacionesLoteScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.playlist_add_check,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Operaciones por lote',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Da de baja o cambia de programa a varios alumnos a la vez, pegando una lista.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAvancePrograma() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AvanceMultiprogramaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.timeline, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avance por programa',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Para alumnos con continuidad (maestría y doctorado): avance de cada programa por separado.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaPlanesFaltantes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PlanesFaltantesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fact_check_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Planes faltantes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Programas activos sin plan en cartas.json (los que no muestran % de avance).',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCorreccionesPadron() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PadronOverridesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.manage_accounts, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Correcciones del padrón',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Corrige nombre, modalidad, correo, programa, generación, grupo o estatus por matrícula.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaSigaEquivalencias() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 1,
        child: InkWell(
          // (23-sep) Abre la Cabina SIGA completa (antes, solo Equivalencias).
          // Con el correo REAL: en «Ver como profesor» SIGA rechazaría el del profesor.
          onTap: () async {
            final yo = ((await SessionStore.realEmail()) ?? _correoSesion).trim().toLowerCase();
            if (!mounted) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => SigaScreen(actor: yo)));
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.event_note,
                      color: cessumRed, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SIGA · Exportables para la SEC',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cessumInk(context),
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Diagnóstico de lo que falta, paquetes para el portal, alumnos pendientes, equivalencias de generaciones y bitácora.',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjetaMontoPorGrupo() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 1,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MontoGrupoScreen()),
          ),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune, color: cessumGold, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monto de pago por grupo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cessumInk(context),
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Fija manualmente el monto de un grupo cuando el sistema toma la modalidad equivocada (mixtos, doctorados).',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCostosColegiaturas() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const CostosColegiaturasScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.price_change,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Costos y colegiaturas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Costo por programa y modalidad (Mixta incluida) y ajuste manual por alumno con beca o descuento.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaSeguimientoPagos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          // (4-oct-2026) Entra al Centro de pagos: desde ahí se llega al seguimiento y a las demás pantallas de pagos.
          MaterialPageRoute(
              builder: (_) => const CentroPagosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.fact_check, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Centro de pagos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Por validar, por aclarar, bajas, convenios y docentes por pagar, en un solo lugar.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaPagos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PagosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.payments, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registro de pagos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Base central de pagos: inscripciones, reinscripciones, colegiaturas y trámites.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaBajas() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BajasListaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.person_remove, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bajas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Revisa las solicitudes de baja (temporal o definitiva), valídalas o regístralas a mano.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              _badgePendientes(_pendientes['bajas'] ?? 0),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaJustificaciones() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const JustificacionesListaScreen(modoAdmin: true),
          ),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_busy, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Justificaciones de faltas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Revisa las justificaciones enviadas por los alumnos y valida o rechaza desde aquí.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              _badgePendientes(_pendientes['justificaciones'] ?? 0),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaClasificacion() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const ClasificacionAlumnosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.badge_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clasificación de alumnos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Activos, bajas, egresados y titulados. El sistema propone una clasificación y tú puedes ajustarla.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaEvaluacionGrupo() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EvaluacionGrupoScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.grading, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Evaluación manual del grupo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Elige grupo y materia, ve a todos los alumnos con su nota actual, corrige o digita a mano y guarda directo en las listas de calificaciones.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }


  Widget _tarjetaRespuestasDocentes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RespuestasDocentesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mark_email_read,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Respuestas de docentes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Quién aceptó o rechazó cada materia, con el día y hora que eligió y sus comentarios. Permite reenviar la invitación.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaTableroProgramacion() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TableroProgramacionScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.grid_view,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Programación por grupo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Por cada grupo, qué materias ya tienen docente y horario y cuáles faltan, con el estado de cada invitación.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaMateriasSinMaestro() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MateriasSinMaestroScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_off_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grupos sin maestro',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Grupos que ya tienen alumnos pero todavía no tienen ningún docente asignado. Los huecos por programar.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRecordatorioInvitaciones() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const RecordatorioInvitacionesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications_active_outlined,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invitaciones pendientes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Reenvía en lote la invitación a todos los docentes que aún no han respondido. (Distinto del recordatorio de captura de calificaciones.)',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaLocalizadorAlumnos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LocalizadorAlumnosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_search,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Localizador de alumnos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Ubica alumnos filtrando por programa, generación, grupo y modalidad, o busca por nombre, matrícula o correo.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  // (10-sep) PLANEACIONES POR REVISAR.
  // Las rutas planea_revision_listar y planea_dictaminar existían desde hace
  // semanas y NUNCA tuvieron pantalla: el docente entregaba, el correo salía,
  // y de este lado no había dónde abrirla. Va antes de Agenda de profesores
  // porque es trabajo pendiente con fecha —de la planeación validada depende
  // el pago del docente—, no una consulta.
  Widget _tarjetaPlaneacionesRevision() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const PlaneacionesRevisionScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fact_check_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Planeaciones por revisar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Dictamina las planeaciones didácticas que entregan los docentes: validarlas o devolverlas con observaciones. La planeación validada es requisito para el pago.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAgendaProfesores() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AgendaProfesoresScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_note, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agenda de profesores',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Crea y edita las asignaciones (grupo, materia, maestro, horario y links de videollamada y Aula CESSUM). Incluye los grupos que aún no tienen maestro.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaListasAsistencia() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ListaAsistenciaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fact_check, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Listas de asistencia',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Imprime la lista de asistencia (PDF) de cualquier grupo, con columnas de fechas para palomear.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  /// (4-oct-2026) Corregir el grupo de un alumno: lo mueve (arrastrando el override de padrón) y lo inscribe en sus aulas.
  Widget _tarjetaCorregirGrupo() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CorregirGrupoAlumnoScreen())),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.swap_horiz, color: cessumRed, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Corregir grupo de alumno', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cessumInk(context))),
              const SizedBox(height: 3),
              Text('Pasa a un alumno al grupo correcto y lo inscribe en sus aulas vigentes de Moodle. Con vista previa; no envía correos.',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            ])),
            const Icon(Icons.chevron_right, color: cessumRed),
          ]),
        ),
      ),
    );
  }

  /// (5-oct-2026) Cambiar la matrícula de un alumno, con vista previa.
  Widget _tarjetaCambiarMatricula() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CambiarMatriculaAlumnoScreen())),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.badge_outlined, color: cessumRed, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Cambiar matrícula de alumno', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cessumInk(context))),
              const SizedBox(height: 3),
              Text('Cambia la matrícula en grupos, padrón, pagos y bajas. Con vista previa; no toca a otra persona con la misma matrícula ni envía correos.',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            ])),
            const Icon(Icons.chevron_right, color: cessumRed),
          ]),
        ),
      ),
    );
  }

  Widget _tarjetaGrupos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminGruposScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Armar / corregir grupos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Corrige el programa, generación o grupo de un alumno, o agrégalo a un grupo. Surte efecto en la base del Guardián.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaEditarCalificaciones() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AdminCalificacionesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.grading, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Editar calificaciones',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Busca a un alumno por matrícula y agrega, corrige o borra sus calificaciones.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaHerramientas() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HerramientasScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.build, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Herramientas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Reconocimientos en PDF, exportar a CSV y mas utilidades rapidas.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaEnviarNotificacion() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EnviarNotificacionScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications_active,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enviar notificacion',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Avisa a un alumno o a todo un grupo dentro de la app.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRespaldos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RespaldosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E8E3E).withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E8E3E).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.backup,
                    color: Color(0xFF1E8E3E), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Respaldos del sistema',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Copias automaticas de las bases. Revisa o respalda ahora.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF1E8E3E)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRoles() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RolesAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.admin_panel_settings,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestion de roles',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Da o quita acceso de administracion a otros usuarios.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaTableroRapido() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TableroRapidoScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.speed, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tablero rapido',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Numeros clave, buscar alumno, directorio docente, por programa y cumpleanos.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAvance() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AvanceTableroScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.trending_up, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avance programatico',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Cuanto se ha cubierto de cada materia-grupo frente a la meta.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaChoquesHorario() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChoquesHorarioScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choques de horario',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Detecta cuando un maestro o un grupo tienen clases encimadas el mismo dia.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaHorarios() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HorariosAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.calendar_month, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Horarios por grupo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Arma y publica el horario de cada grupo; el alumno lo ve en su app.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaImportador() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ImportadorScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.upload_file, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Importar calificaciones (Excel)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Pega filas de Excel, previsualiza con validacion y carga en lote.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaValidacionActas() {    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ValidacionActasScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E8E3E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.verified,
                    color: Color(0xFF1E8E3E), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Validación de actas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Revisa y valida las actas que los docentes capturaron.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF1E8E3E)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCredenciales() {
    final pend = _pend['credenciales'] ?? 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CredencialesAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.badge, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Credenciales',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cessumInk(context),
                          ),
                        ),
                        if (pend > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cessumRed,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$pend',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Aprueba las credenciales que solicitan los alumnos y administra las vigencias.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAccesos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RegistroAccesosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.login, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registro de accesos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Consulta quién ha entrado a la app y cuándo: accesos recientes, buscador y conteo por persona.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaVencimientos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VencimientosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_available,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recordatorios de pago',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Registra vencimientos; el alumno recibe aviso 3 dias antes y a ti te reportamos los vencidos.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCalendario() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CalendarioAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.calendar_today, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calendario académico',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Publica fechas clave (inscripciones, exámenes, pagos) que ven alumnos y docentes.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaBuzonEventos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BuzonEventosAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inbox, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Buzón y eventos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Mensajes anónimos de alumnos y confirmación de asistencia a eventos.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCircular() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CircularScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.campaign, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aviso masivo (circular)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Envía un correo con diseño CESSUM a una generación, un programa o a todos.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaVistos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VistosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mark_email_read,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirmaciones de lectura',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Quién ya recibió su boleta o aviso de trámite/titulación, y por qué canal.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaBitacora() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BitacoraScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.history_edu,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bitacora de auditoria',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Registro de quién validó, resolvió, emitió o cambió algo, y cuándo.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaTablero() {
    return Material(
      color: cessumRed,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TableroScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tablero ejecutivo',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Matrícula, ingresos, trámites, riesgo, titulación y desempeño docente en una sola vista.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaEstudios() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EstudiosAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.badge, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Constancias de estudios',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Aprueba o rechaza solicitudes de vigencia; al aprobar se emite el PDF.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCentroInteligencia() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CentroInteligenciaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Centro de inteligencia',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Expediente PDF del alumno, generaciones por egresar y matriculas duplicadas.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaNav({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required Widget destino,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => destino),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700, color: cessumInk(context))),
                    const SizedBox(height: 3),
                    Text(subtitulo,
                        style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAutoevaluacion() {
    return _tarjetaNav(
      icono: Icons.fact_check_outlined,
      color: cessumRed,
      titulo: 'Autoevaluación CESSUM 2026',
      subtitulo: 'Avance de las 10 carpetas, indicadores y responsables.',
      destino: const AutoevaluacionTableroScreen(),
    );
  }

  Widget _tarjetaReportesDatos() {
    return _tarjetaNav(
      icono: Icons.dataset_outlined,
      color: cessumGold,
      titulo: 'Reportes de datos',
      subtitulo: 'Validador de CURP, demografia y exportar padron a Excel.',
      destino: const ReportesDatosScreen(),
    );
  }

  Widget _tarjetaFormatos() {
    return _tarjetaNav(
      icono: Icons.folder_copy_outlined,
      color: cessumGold,
      titulo: 'Banco de formatos',
      subtitulo:
          'Publica plantillas y formatos que descargan alumnos y docentes.',
      destino: const FormatosScreen(admin: true),
    );
  }

  Widget _tarjetaComunicado() {
    return _tarjetaNav(
      icono: Icons.campaign_outlined,
      color: cessumRed,
      titulo: 'Comunicado institucional',
      subtitulo: 'Envia un aviso a alumnos, docentes o ambos (in-app y correo).',
      destino: const ComunicadoScreen(),
    );
  }

  Widget _tarjetaDiplomaCongreso() {
    return _tarjetaNav(
      icono: Icons.workspace_premium_outlined,
      color: cessumGold,
      titulo: 'Diploma de congreso',
      subtitulo: 'Emite el diploma de un participante de COINEDU con QR.',
      destino: const DiplomaCongresoScreen(),
    );
  }

  Widget _tarjetaAutomatizaciones() {
    return _tarjetaNav(
      icono: Icons.bolt_outlined,
      color: cessumRed,
      titulo: 'Centro de automatizaciones',
      subtitulo: 'Prende, apaga y ejecuta los recordatorios y avisos automaticos.',
      destino: const AutomatizacionesScreen(),
    );
  }

  Widget _tarjetaVerificadorQr() {
    return _tarjetaNav(
      icono: Icons.qr_code_scanner,
      color: cessumGold,
      titulo: 'Verificar documento (QR)',
      subtitulo: 'Escanea el QR de una constancia, acta, contrato o diploma.',
      destino: const VerificadorQrScreen(),
    );
  }

  Widget _tarjetaTableroBI() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TableroBiScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tablero institucional (BI)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Matricula, aprobacion, carga docente, actas y contratos en una sola vista.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  // (ago-24) OFICIOS FOLIADOS. Antes se redactaban en Word, fuera del
  // sistema: sin folio, sin verificación y sin rastro de cuántos salieron ni
  // quién los firmó.
  Widget _tarjetaOficios() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OficiosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.40)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.article_outlined,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Oficios foliados',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Emite un oficio con membrete, folio y QR de verificación. Se descarga en Word y queda en seguimiento.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaTesisSolicitudes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const TesisSolicitudesAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.school_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitudes de tutor de tesis',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Solicitudes firmadas del alumnado: revisa el tema y asigna director de tesis.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaSeguimientoDocente() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const SeguimientoDocenteScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.emoji_events,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seguimiento docente',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Ranking de desempeño en revisiones: quién califica en tiempo y forma dentro de las 24 horas.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaConvenios() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ConveniosAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.history_edu,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Convenios',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Crea convenios, promuévelos por correo y sigue el avance de firmas de consentimiento de los alumnos.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAdaptaciones() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AdaptacionesAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.swap_horiz, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adaptaciones de modalidad',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Adaptaciones aprobadas en espera: el vigilante matricula al alumno solo cuando su materia está en línea.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaPagosAdministrativos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const PagosAdministrativosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.badge, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pagos a administrativos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Nómina del personal: pendientes por quincena o mes, CLABE, marcar pagado e historial.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCursosVigentes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CursosVigentesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.play_circle_outline,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cursos vigentes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Los cursos en marcha hoy: docente, clase, fechas, link del aula y descarga a Excel.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaSaludDatos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SaludDatosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.health_and_safety,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Salud de datos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Detecta duplicados, grupos sin docente, calificaciones fuera del padron y generaciones mal etiquetadas.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaTorreControl() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TorreControlScreen()),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7A1420), cessumRed],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: cessumRed.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.speed, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Torre de Control',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Índice de Salud Institucional en vivo, con focos de atención.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaPendientesDia() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PendientesDiaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications_active,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pendientes del día',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Lo accionable hoy: captura, trámites y alumnos en riesgo.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  /// (22-sep) Finanzas: solo Rectoría, Vicerrectoría y Administración y
  /// Finanzas, con la misma lista que usa la pantalla.
  bool get _esFinanzas =>
      kFinanzasCorreos.contains(_correoSesion.trim().toLowerCase());

  Widget _tarjetaDireccion(
      String titulo, String detalle, IconData icono, Widget destino) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => destino)),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cessumInk(context))),
                    const SizedBox(height: 3),
                    Text(detalle,
                        style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaFinanzas() => _tarjetaDireccion(
      'Finanzas · estados de cuenta',
      'Suba el estado de cuenta de BBVA: gastos por categoría, histórico, alertas y asistente de IA.',
      Icons.account_balance,
      const FinanzasScreen());

  // (24-sep) CENTROS INTELIGENTES · fase 1.
  Widget _tarjetaCentroMando() => _tarjetaDireccion(
      'Centro de mando',
      'Lo que requiere su decisión hoy, por impacto, con acceso directo a la acción y tres líneas de IA.',
      Icons.dashboard_customize_outlined,
      const CentroMandoScreen());

  Widget _tarjetaBandeja() => _tarjetaDireccion(
      'Bandeja de solicitudes',
      'Todas las solicitudes pendientes en una sola lista, con semáforo de tiempo y borrador de respuesta con IA.',
      Icons.inbox_outlined,
      const BandejaSolicitudesScreen());

  Widget _tarjetaComunicaciones() => _tarjetaDireccion(
      'Centro de comunicaciones',
      'Un solo redactor para alumnos o docentes, con audiencia calculada, vista previa obligatoria e historial.',
      Icons.campaign_outlined,
      const CentroComunicacionesScreen());

  Widget _tarjetaAsistenteOps() => _tarjetaDireccion(
      'Asistente de operaciones',
      'Pregunte con sus palabras: responde con datos reales y propone acciones que usted revisa y confirma.',
      Icons.support_agent_outlined,
      const AsistenteOperacionesScreen());

  Widget _tarjetaAuditoria() => _tarjetaDireccion(
      'Auditoría y seguridad',
      'La bitácora convertida en alertas: acciones sensibles, horarios inusuales, rechazos y accesos.',
      Icons.shield_outlined,
      const AuditoriaSeguridadScreen());

  Widget _tarjetaCalidadDatos() => _tarjetaDireccion(
      'Calidad de datos',
      'Ocho diagnósticos en una sola vista, con tendencia diaria y acceso a la herramienta que corrige cada uno.',
      Icons.health_and_safety_outlined,
      const CalidadDatosScreen());

  Widget _tarjetaRetencionPredictiva() => _tarjetaDireccion(
      'Retención predictiva',
      'Quién podría abandonar, con probabilidad, adeudo e intervenciones, y qué tipo de intervención sí retiene.',
      Icons.favorite_border,
      const RetencionPredictivaScreen());

  Widget _tarjetaCobranza() => _tarjetaDireccion(
      'Cobranza inteligente',
      'Adeudos por urgencia y probabilidad de pago, recuperable estimado y recordatorio con vista previa.',
      Icons.request_quote_outlined,
      const CobranzaScreen());

  Widget _tarjetaPlaneacionCiclo() => _tarjetaDireccion(
      'Planeación del ciclo',
      'Oferta, programación, docentes sin choques e invitaciones: qué falta antes de publicar.',
      Icons.event_note_outlined,
      const PlaneacionCicloScreen());

  Widget _tarjetaCalendarioOperativo() => _tarjetaDireccion(
      'Calendario operativo',
      'Todas las fechas críticas de los próximos 60 días, con responsable.',
      Icons.calendar_month_outlined,
      const CalendarioOperativoScreen());

  Widget _tarjetaExpedienteDocente() => _tarjetaDireccion(
      'Expediente 360 · docente',
      'Todo lo de un docente en una vista, con cinco líneas de IA para la conversación.',
      Icons.co_present_outlined,
      const ExpedienteDocente360Screen());

  Widget _tarjetaExpediente360() => _tarjetaDireccion(
      'Expediente 360',
      'Todo lo de un alumno en una línea de tiempo, con la situación en cinco líneas.',
      Icons.person_search_outlined,
      const Expediente360Screen());

  Widget _tarjetaSaludSistema() => _tarjetaDireccion(
      'Salud del sistema',
      'Disparadores, colas pendientes, clases y datos: qué está detenido y cómo se arregla.',
      Icons.monitor_heart_outlined,
      const SaludScreen());

  Widget _tarjetaSenales() => _tarjetaDireccion(
      'Señales académicas',
      'A quién se le está apagando la participación y qué materias hunden la permanencia, con razones.',
      Icons.insights_outlined,
      const SenalesScreen());

  Widget _tarjetaAltasInscripcion() => _tarjetaDireccion(
      'Altas de inscripción',
      'Cada solicitud con sus pasos comprobados: revisión, cuenta, matrícula, padrón, grupo, aula y bienvenida.',
      Icons.fact_check_outlined,
      const AltasScreen());

  Widget _tarjetaSimulador() => _tarjetaDireccion(
      'Simulador de grupos',
      'Ingreso, costo docente, punto de equilibrio y qué pasa si se cae una parte, con las bajas reales.',
      Icons.calculate_outlined,
      const SimuladorScreen());

  // (27-sep) Arts. 48, 49-58 y 62/63/61-IV del Acuerdo 17/11/17.
  Widget _tarjetaQuejas() => _tarjetaDireccion(
      'Quejas',
      'Buzón de quejas del alumno, incluidas acoso escolar, acoso sexual y plagio académico, con su seguimiento (Art. 48).',
      Icons.report_gmailerrorred,
      const QuejasAdminScreen());

  Widget _tarjetaBecasConvocatoria() => _tarjetaDireccion(
      'Becas por convocatoria',
      'Convocatoria pública, solicitud con estudio socioeconómico, dictamen, inconformidad, reembolso y el semáforo del 5 % mínimo (Arts. 49-58).',
      Icons.volunteer_activism_outlined,
      const BecaConvocatoriaAdminScreen());

  Widget _tarjetaCumplimientoAcuerdo() => _tarjetaDireccion(
      'Cumplimiento · Acuerdo 17/11/17',
      'Seguimiento de 6 y 24 meses del Art. 63, verificación de autenticidad del Art. 62, y el Libro de Títulos del Art. 61-IV.',
      Icons.gavel_outlined,
      const CumplimientoAcuerdoScreen());

  // (26-sep) Interrupción temporal del acceso (no es baja), con candidatos
  // por adeudo, análisis de IA y convenio de pago desde la misma pantalla.
  Widget _tarjetaBloqueos() => _tarjetaDireccion(
      'Bloqueos de acceso',
      'Pausar y reactivar el acceso a la app por falta de pago u otro motivo, con el mensaje que ve el alumno; candidatos con IA y convenio de pago.',
      Icons.lock_clock_outlined,
      const AccesoBloqueosScreen());

  Widget _tarjetaBajasPago() => _tarjetaDireccion(
      'Bajas por pago',
      'Alumnos con colegiaturas incompletas al cierre de su corte: autorizar, posponer o descartar la baja.',
      Icons.gavel,
      const BajasPagoScreen());

  Widget _tarjetaResumenEjecutivo() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ResumenEjecutivoScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.dashboard, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen ejecutivo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Focos de atención en un vistazo: datos, inactividad en el Aula e inscripciones pendientes.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAvanceCaptura() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AvanceCapturaScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fact_check, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avance de captura',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Qué docentes ya capturaron sus grupos y cuáles van pendientes.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaEstadisticasPadron() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EstadisticasPadronScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estadísticas del padrón',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Alumnos por programa, generación y modalidad.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAnalisisCalificaciones() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AnalisisCalificacionesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bar_chart, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Análisis de calificaciones',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Promedios, aprobados/reprobados y distribución por nota.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaComparativoGeneraciones() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const ComparativoGeneracionesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.trending_up, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Comparativo de generaciones',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Evolución de matrícula, promedio y aprobación por generación.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaDirectorioDocentes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DirectorioDocentesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.contacts, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Directorio de docentes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Docentes activos, sus materias y contacto directo.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRecordatorioDocentes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const RecordatorioDocentesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mark_email_unread,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recordatorio a docentes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Avisa por correo a quienes tienen captura pendiente.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaResumenDocentes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ResumenDocentesScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen a docentes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Envía a cada docente su resumen de captura (grupos y avance).',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaBoletasPeriodo() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BoletasPeriodoScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.description, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Boletas por periodo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Envía la boleta a quienes ya completaron su periodo.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaBitacoraCorreos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BitacoraCorreosScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.monitor_heart, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bitácora de correos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Qué se envió, qué falló y cuánta cuota queda.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaMoodle() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MoodleAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.school, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aula Virtual (Moodle)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Panorama de cursos (inscritos, activos, promedio) y la actividad de cada alumno en el Aula.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaCobertura() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CoberturaEvaluacionScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.fact_check, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cobertura de evaluación docente',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Que docentes ya tienen evaluacion y cuales faltan, por programa.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaNoAdeudo() {
    final pend = _pend['noadeudo'] ?? 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NoAdeudoAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.verified_user,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Constancias de no adeudo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cessumInk(context),
                          ),
                        ),
                        if (pend > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cessumRed,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$pend',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Aprueba o rechaza solicitudes; al aprobar se emite y se envia el PDF.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  /// (4-oct-2026) Correos de marketing a aspirantes y prospectos (no a alumnos; para ellos están Avisos y Circulares).
  Widget _tarjetaMarketing() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketingCorreosScreen())),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.campaign_outlined, color: cessumGold, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Correos de marketing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cessumInk(context))),
              const SizedBox(height: 3),
              Text('A aspirantes y prospectos, con plantilla y datos personalizables. Para alumnos usa Avisos o Circulares.', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            ])),
            const Icon(Icons.chevron_right, color: cessumGold),
          ]),
        ),
      ),
    );
  }

  /// (4-oct-2026) Bandeja de solicitudes por correo (solo Rectoría, Vicerrectoría, Administración y contacto@; el Guardián lo valida).
  Widget _tarjetaBandejaCorreos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BandejaCorreosScreen())),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.mark_email_unread_outlined, color: cessumRed, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bandeja de solicitudes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cessumInk(context))),
              const SizedBox(height: 3),
              Text('Correos de contacto, rectoría y vicerrectoría que piden algo, sin spam y por urgencia.', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            ])),
            const Icon(Icons.chevron_right, color: cessumRed),
          ]),
        ),
      ),
    );
  }

  /// (4-oct-2026) Expedientes: barrido de documentos por alumno (Acuerdo 17/11/17 y titulación).
  Widget _tarjetaExpedientes() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpedientesScreen())),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.folder_shared_outlined, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expedientes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cessumInk(context))),
                    const SizedBox(height: 3),
                    Text('Qué documentos tiene y cuáles le faltan a cada alumno (Acuerdo 17/11/17 y titulación).',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaTitulacionCierre() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TitulacionCierreScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.card_membership,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cierre de titulacion',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Control de cedula profesional (SEP) y actas de egreso por generacion.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaTitulacion() {
    final pend = _pend['titulacion'] ?? 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TitulacionAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.school, color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Titulación',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cessumInk(context),
                          ),
                        ),
                        if (pend > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cessumRed,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$pend',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Solicitudes de grado y expedientes documentales: revisar, aprobar y avanzar etapas.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  /// Panel de Vicerrectoría para recursamientos: quién solicitó, quién pagó
  /// y a quién falta matricular. Con el umbral de acreditación corregido
  /// (el 6 reprueba), esta lista dejó de estar vacía.
  /// Reingresos: alumnos dados de baja que piden volver. El backend llevaba
  /// días completo (`reingreso_listar`, `_propuesta`, `_dictaminar`) sin una
  /// sola pantalla que lo usara: las solicitudes se guardaban y nadie las veía.
  Widget _tarjetaReingresos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ReingresosAdminScreen(actor: _correoSesion)),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.how_to_reg_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reingresos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Alumnos de baja que piden volver: expediente, convenio de recursamiento y resolucion.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRecursamientos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const RecursamientosPanelScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.playlist_add_check_circle_outlined,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recursamientos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Quien esta recursando, verificacion de pagos y matricula en el grupo que oferta la materia.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRiesgo() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RiesgoScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Riesgo académico',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Semaforo de alumnos a distancia: inactividad en Moodle y reprobacion, calculado cada noche.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaFicha() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FichaAlumnoScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.person_search, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ficha del alumno',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Todo de un alumno por matricula: calificaciones, tramites, incidencias, justificaciones y accesos.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaConstanciasLote() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ConstanciasLoteScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.library_books,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Constancias por lote',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Genera todas las constancias de una generacion de un golpe, con folio, firma y QR.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaDocumentos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DocumentosAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium,
                    color: cessumGold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Documentos oficiales',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Constancias y kardex con folio, firma del Rector y descarga en PDF o DOCX.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaAvisos() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AvisosAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.campaign, color: cessumRed, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avisos institucionales',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Publica comunicados para todos o segmentados por programa, modalidad, generacion y grupo.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaIncidencias() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IncidenciasAdminScreen()),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _conBadge(
                    _pend['incidencias'] ?? 0,
                    const Icon(Icons.support_agent,
                        color: cessumGold, size: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mesa de ayuda (incidencias)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Revisa y responde los reportes de los alumnos. Al responder, el alumno recibe el aviso por correo.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaSemaforo() {
    final cargando = _capturaAbierta == null && _errorSemaforo == null;
    final abierta = _capturaAbierta ?? false;
    final Color colorEstado = abierta ? const Color(0xFF1E8E3E) : cessumRed;
    final String textoEstado = abierta ? 'ABIERTA' : 'CERRADA';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cargando ? Colors.grey.shade300 : colorEstado.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                abierta ? Icons.lock_open : Icons.lock_outline,
                color: cargando ? Colors.grey : colorEstado,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Captura de calificaciones',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: cessumInk(context),
                  ),
                ),
              ),
              if (cargando)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: cessumRed),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorEstado.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    textoEstado,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: colorEstado,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            abierta
                ? 'Los docentes pueden capturar calificaciones ahora mismo.'
                : 'Los docentes NO pueden capturar; verán un mensaje de que no es '
                    'momento de evaluar. (Tú como administrador sí puedes capturar.)',
            style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.4),
          ),
          if (_errorSemaforo != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorSemaforo!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _cargarSemaforo,
              icon: const Icon(Icons.refresh, size: 16, color: cessumRed),
              label: const Text('Reintentar', style: TextStyle(color: cessumRed)),
            ),
          ],
          if (!cargando && _errorSemaforo == null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    abierta ? 'Captura habilitada' : 'Captura deshabilitada',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorEstado,
                    ),
                  ),
                ),
                _cambiandoSemaforo
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cessumRed),
                      )
                    : Switch(
                        value: abierta,
                        activeThumbColor: const Color(0xFF1E8E3E),
                        onChanged: (v) => _cambiarSemaforo(v),
                      ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _deco() {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: cessumRed, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _cajaCargando() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed),
          ),
          SizedBox(width: 12),
          Text(
            'Cargando generaciones...',
            style: TextStyle(color: cessumMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _cajaError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_errorGeneraciones ?? 'Error'),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _cargarGeneraciones,
            icon: const Icon(Icons.refresh, size: 16, color: cessumRed),
            label: const Text('Reintentar', style: TextStyle(color: cessumRed)),
          ),
        ],
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  final String texto;
  const _TituloSeccion(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: Colors.black87,
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  const _Etiqueta(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }
}


/// Pantalla de administrador: elegir a un alumno REAL de la lista y entrar a
/// la app tal como la ve ese alumno (mismo perfil, mismo menu).
class AdminAlumnoPickerScreen extends StatefulWidget {
  const AdminAlumnoPickerScreen({super.key});

  @override
  State<AdminAlumnoPickerScreen> createState() =>
      _AdminAlumnoPickerScreenState();
}

class _AdminAlumnoPickerScreenState extends State<AdminAlumnoPickerScreen> {
  List<AlumnoInfo> _todos = [];
  List<AlumnoInfo> _filtrados = [];
  bool _cargando = true;
  String? _error;
  final TextEditingController _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final lista = await AlumnosService.listarAlumnos();
      if (!mounted) return;
      setState(() {
        _todos = lista;
        _filtrados = lista;
        _cargando = false;
        if (lista.isEmpty) _error = 'No se pudo cargar la lista de alumnos.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la lista de alumnos.';
      });
    }
  }

  // Quita acentos para que la busqueda no dependa de ellos.
  String _norm(String s) {
    s = s.toLowerCase();
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sin = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    return s;
  }

  void _filtrar(String q) {
    final query = _norm(q.trim());
    setState(() {
      if (query.isEmpty) {
        _filtrados = _todos;
      } else {
        // (ago-22) SE BUSCA POR PALABRAS, NO POR CADENA CONTINUA.
        // Antes se pedía que lo tecleado apareciera TAL CUAL dentro del
        // nombre. Con "paulina ibarra" eso falla en cuanto el padrón trae un
        // segundo nombre o los apellidos primero: "Paulina Guadalupe Ibarra"
        // no contiene "paulina ibarra". Ahora basta con que TODAS las
        // palabras estén, en cualquier orden y en cualquiera de los campos.
        final palabras =
            query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        _filtrados = _todos.where((a) {
          final heno = _norm(
              '${a.nombre} ${a.correo} ${a.matricula} ${a.programa} ${a.generacion}');
          return palabras.every(heno.contains);
        }).toList();
      }
    });
  }

  Future<void> _entrarComoAlumno(AlumnoInfo a) async {
    final modo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ver como este alumno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${a.nombre}\n${a.correo}\n'
              'Matrícula: ${a.matricula.isEmpty ? "(sin matrícula)" : a.matricula}',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 14),
            const Text('¿Cómo quieres entrar?',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: const BorderSide(color: cessumRed),
                ),
                onPressed: () => Navigator.pop(ctx, 'ver'),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Solo ver (modo prueba)'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, 'real'),
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Actuar como el alumno (real)'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'En “real”, los trámites, facturas y solicitudes se envían DE '
              'VERDAD a nombre del alumno. Para volver a tu cuenta usa el aviso '
              'superior “Saliendo como…”.',
              style:
                  TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.3),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (modo == null || !mounted) return;

    final real = modo == 'real';
    if (real && a.correo.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Este alumno no tiene correo en el padrón; solo se puede entrar a ver.'),
        backgroundColor: cessumRed,
      ));
      return;
    }
    if (real) {
      await SessionStore.startImpersonation(a.correo, nombre: a.nombre);
    } else {
      await SessionStore.stopImpersonation();
    }

    final perfil = StudentProfile(
      matricula: a.matricula,
      nombreCompleto: a.nombre,
      programa: a.programa,
      modalidad: a.modalidad,
      generacion: a.generacion,
      esVistaAdmin: !real,
    );
    await perfil.save();
    await ActiveProfile.setActive(ProfileType.student);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MenuScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Elegir alumno'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _ctrl,
              onChanged: _filtrar,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, correo o matricula',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
          if (!_cargando && _error == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtrados.length} alumno(s)',
                  style: TextStyle(color: cessumMuted(context), fontSize: 12.5),
                ),
              ),
            ),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed),
                  )
                : _error != null
                    ? _cajaError()
                    : ListView.separated(
                        itemCount: _filtrados.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final a = _filtrados[i];
                          // (ago-28) Los dados de baja y los egresados ya
                          // aparecen en esta lista, pero MARCADOS. Sin la
                          // etiqueta, entrar como un alumno de baja se ve
                          // idéntico a entrar como uno vigente, y eso lleva
                          // a hacerle trámites a quien ya no cursa.
                          final est = a.estatus.trim();
                          final estN = est.toLowerCase();
                          final esBaja = estN == 'baja';
                          final esEgresado = estN == 'egresado';
                          final inactivo = esBaja || esEgresado;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  inactivo ? cessumFaint(context) : cessumRed,
                              child: Icon(
                                  esBaja
                                      ? Icons.person_off
                                      : (esEgresado
                                          ? Icons.school
                                          : Icons.person),
                                  color: Colors.white),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    a.nombre.isEmpty ? '(sin nombre)' : a.nombre,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (inactivo) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (esBaja ? cessumRed : cessumGold)
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      esBaja ? 'BAJA' : 'EGRESADO',
                                      style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: .5,
                                        fontWeight: FontWeight.w800,
                                        color: esBaja ? cessumRed : cessumGold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '${a.correo}\n'
                              '${a.matricula} - ${a.programa} - ${_genLegible(a.generacion)}',
                            ),
                            isThreeLine: true,
                            onTap: () => _entrarComoAlumno(a),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _cajaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? 'Error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

// Una opción del panel admin para el buscador: título, descripción y el
// constructor de su tarjeta real (misma acción y permisos).
class _OpcionAdmin {
  final String titulo;
  final String descripcion;
  final Widget Function() builder;
  const _OpcionAdmin(this.titulo, this.descripcion, this.builder);
}

/// (4-oct-2026) Un grupo del panel como «carpeta».
class _CarpetaAdmin {
  final String titulo;
  final IconData icono;
  final List<Widget> hijos;
  const _CarpetaAdmin(this.titulo, this.icono, this.hijos);
}

/// (4-oct-2026) El buscador del panel queda FIJO arriba, siempre visible.
class _BuscadorFijoAdmin extends SliverPersistentHeaderDelegate {
  final double alto;
  final Widget Function() construir;
  _BuscadorFijoAdmin({required this.alto, required this.construir});
  @override
  double get maxExtent => alto;
  @override
  double get minExtent => alto;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      SizedBox(height: alto, child: construir());
  @override
  bool shouldRebuild(covariant _BuscadorFijoAdmin old) => true;
}
