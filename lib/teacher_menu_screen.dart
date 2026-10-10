import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; // (8-oct-2026) botón "Créditos de Claude"
import 'dart:convert' show jsonDecode;
import 'dart:ui' as ui;   // (4-oct-2026) desenfoque detrás de la carpeta abierta

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'admin_config.dart';
import 'admin_preview_screen.dart';
import 'mensajes_screen.dart';
import 'auth/session_store.dart';
import 'mis_interacciones_screen.dart';
import 'teacher_about_screen.dart';
import 'teacher_profile.dart';
import 'credencial_profesor_screen.dart';
import 'aula_helper.dart';
import 'cartas_descriptivas_screen.dart';
import 'apa_referencias_screen.dart';
import 'justificaciones_lista_screen.dart';
import 'captura_calificaciones_screen.dart';
import 'curp_docente_gate.dart';
import 'firma_digital_screen.dart';
import 'mis_pagos_docente_screen.dart';
import 'mis_materias_screen.dart';
import 'revisiones_screen.dart';
import 'mi_informe_docente_screen.dart';
import 'banners_semanales_screen.dart';
import 'portadas_asignaturas_screen.dart';
import 'docente_tesis_screen.dart';
import 'constancias_trabajo_screen.dart';
import 'mi_contrato_screen.dart';
import 'tablero_docente_screen.dart';
import 'mi_horario_docente_screen.dart';
import 'avisos_docente_screen.dart';
import 'reporte_grupo_screen.dart';
import 'asistencia_docente_screen.dart';
import 'avance_docente_screen.dart';
import 'mi_captura_screen.dart';
import 'mi_panel_docente_screen.dart';
import 'tutorias_docente_screen.dart';
import 'riesgo_docente_screen.dart';
import 'welcome_screen.dart';
import 'notificaciones_screen.dart';
import 'material_ia_hub_screen.dart';
import 'mi_semana_screen.dart'; // (24-sep) centros inteligentes · fase 2
import 'laboratorio_clases_screen.dart'; // (8-oct-2026) taller de práctica, cualquier materia del catálogo
import 'banco_planeaciones_screen.dart'; // (8-oct-2026) planeaciones validadas de otros docentes, como referencia

class TeacherMenuScreen extends StatefulWidget {
  const TeacherMenuScreen({super.key});

  @override
  State<TeacherMenuScreen> createState() => _TeacherMenuScreenState();
}

class _TeacherMenuScreenState extends State<TeacherMenuScreen> {
  String _version = 'v1.0.0';
  TeacherProfile? _perfil;
  bool _esAdmin = false;
  String _correo = '';
  int _notisNoLeidas = 0;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = 'v${info.version}';
        });
      }
    } catch (_) {}

    final perfil = await TeacherProfile.load();
    final correo = await SessionStore.validEmail();
    if (mounted) {
      setState(() {
        _perfil = perfil;
        _esAdmin = esAdmin(correo);
        _correo = correo ?? '';
      });
      _cargarNotis();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _verificarCurpDocente();
      });
    }
  }

  // Candado de CURP: la autoridad educativa (SIGA) exige la CURP de cada
  // docente. Si el docente entra sin CURP registrada, primero se intenta
  // recuperar de su contrato (autocuración en el backend); si tampoco ahí
  // está, se le pide capturarla antes de continuar. Los administradores
  // pueden cerrar la pantalla (para previsualizar sin quedar bloqueados).
  bool _curpVerificada = false;
  Future<void> _verificarCurpDocente() async {
    if (_curpVerificada || _correo.isEmpty) return;
    _curpVerificada = true;
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=docente_curp_estado'
              '&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true || !mounted) return;
      if (data['esDocente'] != true) return; // no está en la hoja Docentes
      if (data['tieneCurp'] == true) return; // ya tiene (o se recuperó del contrato)
      await Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CurpDocenteGate(
            correo: _correo,
            nombre: _perfil?.nombreCompleto ?? '',
            permitirSalir: _esAdmin,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _cargarNotis() async {
    if (_correo.isEmpty) return;
    try {
      final uri = Uri.parse('$guardianUrl?accion=notificaciones'
          '&correo=${Uri.encodeComponent(_correo)}&matricula=');
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (mounted && data['ok'] == true) {
        // (8-oct-2026) `(data['noLeidas'] ?? 0) as int` truena si el backend lo manda como
        // decimal (p. ej. 3.0 en vez de 3); el error quedaba atrapado por el catch de abajo,
        // así que el contador simplemente se congelaba sin aviso. Ahora acepta num o texto.
        final nl = data['noLeidas'];
        setState(() => _notisNoLeidas = nl is num ? nl.toInt() : (int.tryParse('${nl ?? 0}') ?? 0));
      }
    } catch (_) {}
  }

  void _abrirVistaAdmin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminPreviewScreen()),
    );
  }

  Future<void> _cambiarPerfil(BuildContext context) async {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  void _abrirAcercaDe() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TeacherAboutScreen()),
    ).then((_) => _refrescarPerfil());
  }

  void _abrirCartas() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartasDescriptivasScreen()),
    );
  }

  void _abrirReferenciasApa() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ApaReferenciasScreen()),
    );
  }

  void _abrirCaptura() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CapturaCalificacionesScreen()),
    );
  }

  void _abrirFirmaDigital() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FirmaDigitalScreen()),
    );
  }

  void _abrirMisMaterias() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MisMateriasScreen()),
    );
  }

  void _abrirRevisiones() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RevisionesScreen()),
    );
  }

  void _abrirMiInforme() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MiInformeDocenteScreen()),
    );
  }

  void _abrirConstancias() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConstanciasTrabajoScreen()),
    );
  }

  void _abrirMiContrato() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MiContratoScreen()),
    );
  }

  void _abrirJustificaciones() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JustificacionesListaScreen(
          docenteFiltro: _perfil?.nombreCompleto ?? '',
        ),
      ),
    );
  }

  // (8-oct-2026) Antes volvían a pedir SessionStore.validEmail() por su cuenta, en vez de
  // reusar `_correo` (ya resuelto por _cargarTodo): si esa segunda consulta regresaba algo
  // distinto (o vacío), estas pantallas abrían con un correo que no correspondía a la sesión
  // que el resto del menú ya tenía funcionando.
  void _abrirMiDesempeno() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TableroDocenteScreen(correo: _correo),
      ),
    );
  }

  void _abrirRiesgoDocente() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RiesgoDocenteScreen(correo: _correo),
      ),
    );
  }

  Future<void> _abrirMiHorario() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MiHorarioDocenteScreen()),
    );
  }

  Future<void> _abrirAvisosDocente() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AvisosDocenteScreen()),
    );
  }

  // (18-sep) El registro de asistencia ya existía y se levantaba solo de las
  // conexiones a las videollamadas, pero NO había dónde consultarlo: el dato
  // estaba en el sistema y el profesor no podía verlo. Sin eso, quien quiere
  // entender por qué un alumno va mal no distingue entre el que no entrega y
  // el que ni siquiera se conecta.
  Future<void> _abrirAsistenciaDocente() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AsistenciaDocenteScreen()),
    );
  }

  Future<void> _abrirReporteGrupo() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReporteGrupoScreen()),
    );
  }

  void _abrirMiCaptura() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MiCapturaScreen()),
    );
  }

  Future<void> _abrirAvanceDocente() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AvanceDocenteScreen()),
    );
  }

  Future<void> _abrirTutoriasDocente() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TutoriasDocenteScreen()),
    );
  }

  void _abrirMisPagos() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MisPagosDocenteScreen()),
    );
  }

  Future<void> _refrescarPerfil() async {
    final perfil = await TeacherProfile.load();
    if (mounted) {
      setState(() {
        _perfil = perfil;
      });
    }
  }

  Widget _tarjetaNotificaciones() {
    final hay = _notisNoLeidas > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: hay ? cessumRed.withValues(alpha: 0.10) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        elevation: hay ? 0 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotificacionesScreen(correo: _correo),
              ),
            );
            _cargarNotis();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.notifications,
                        color: hay ? cessumRed : cessumMuted(context), size: 24),
                    if (hay)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: cessumRed, shape: BoxShape.circle),
                          constraints: const BoxConstraints(
                              minWidth: 16, minHeight: 16),
                          child: Text('$_notisNoLeidas',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    hay ? 'Tienes $_notisNoLeidas sin leer' : 'Notificaciones',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: hay ? FontWeight.w700 : FontWeight.w600,
                      color: cessumIsDark(context) ? Colors.white : cessumInk(context),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: cessumMuted(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  // ---- BUSCADOR DE RECURSOS DEL PORTAL ----
  final _buscaCtrl = TextEditingController();
  String _q = '';

  // Normaliza para buscar: minúsculas y sin acentos.
  String _normBusca(String s) {
    var t = s.toLowerCase();
    const con = 'áéíóúüñ';
    const sin = 'aeiouun';
    for (var i = 0; i < con.length; i++) {
      t = t.replaceAll(con[i], sin[i]);
    }
    return t;
  }

  // Catálogo completo de opciones del portal con SU DESCRIPCIÓN (también
  // se busca por ella). Misma acción que la tarjeta correspondiente.
  List<_OpcionDocente> _catalogoOpciones() {
    return [
      _OpcionDocente('Mi panel',
          'Resumen de tus grupos, pendientes y avisos del día en un solo tablero.',
          Icons.dashboard, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MiPanelDocenteScreen()));
      }),
      _OpcionDocente('Mi semana',
          'Tus clases por día, captura pendiente, entregas por revisar y mensajes, con tu plan de la semana con IA.',
          Icons.view_week_outlined, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MiSemanaScreen()));
      }),
      _OpcionDocente('Capturar calificaciones',
          'Registra las calificaciones de tus grupos y genera el acta oficial.',
          Icons.grading, _abrirCaptura),
      _OpcionDocente('Aula Virtual',
          'Entra al aula virtual (Moodle) con tus cursos y actividades.',
          Icons.school, () => abrirAula(context)),
      _OpcionDocente('Mi horario',
          'Tus clases con día, hora y vigencia de cada materia.',
          Icons.calendar_month, _abrirMiHorario),
      _OpcionDocente('Mis materias',
          'Consulta los grupos y materias que tienes asignados.',
          Icons.menu_book_outlined, _abrirMisMaterias),
      _OpcionDocente('Revisiones pendientes',
          'Entregas de tus alumnos con cuenta regresiva de 24 horas para revisarlas y calificarlas.',
          Icons.timer_outlined, _abrirRevisiones),
      // (ago-24) El chat existía y funcionaba, pero el menú del docente nunca
      // lo enlazó: solo estaba en el del alumno. O sea que los alumnos
      // escribían y del otro lado no había puerta para entrar a leer.
      _OpcionDocente('Chat con alumno',
          'Dudas de tus alumnos por el único canal institucional. Tienes 24 horas para la primera respuesta.',
          Icons.forum_outlined,
          () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MensajesScreen()),
              )),
      _OpcionDocente('Mi informe de evaluación',
          'Tu puntaje de calidad y las observaciones de clase de Coordinación: duración, fortalezas y recomendaciones.',
          Icons.assessment_outlined, _abrirMiInforme),
      _OpcionDocente('Calendario y clases',
          'Calendario institucional con las sesiones y fechas importantes.',
          Icons.event,
          () => Helpers.abrirUrlExterna(calendarioUrl, context)),
      _OpcionDocente('Avisos a mi grupo',
          'Envía avisos o recordatorios a los alumnos de tus grupos.',
          Icons.campaign, _abrirAvisosDocente),
      _OpcionDocente('Asistencia de mis alumnos',
          'Quién se ha conectado a tus clases y quién se está quedando atrás.',
          Icons.how_to_reg, _abrirAsistenciaDocente),
      _OpcionDocente('Reporte de mi grupo',
          'Panorama del grupo que impartes: alumnos, asistencia y avance.',
          Icons.summarize, _abrirReporteGrupo),
      _OpcionDocente('Alumnos en riesgo',
          'Alumnos de tus grupos con reprobación o baja actividad.',
          Icons.warning_amber_rounded, _abrirRiesgoDocente),
      _OpcionDocente('Justificaciones de faltas',
          'Revisa las justificaciones de inasistencia que envían tus alumnos.',
          Icons.event_busy, _abrirJustificaciones),
      _OpcionDocente('Tutorías y asesorías',
          'Registra tutorías y asesorías con tus alumnos y su seguimiento.',
          Icons.support_agent, _abrirTutoriasDocente),
      _OpcionDocente('Avance de captura',
          'Qué grupos ya calificaste y cuáles te faltan por capturar.',
          Icons.fact_check, _abrirMiCaptura),
      _OpcionDocente('Mi avance programático',
          'Tu progreso de sesiones frente al plan de cada materia.',
          Icons.trending_up, _abrirAvanceDocente),
      _OpcionDocente('Mi desempeño',
          'Resultados de tu evaluación docente respondida por los alumnos.',
          Icons.insights, _abrirMiDesempeno),
      // (4-oct-2026) El informe de las interacciones complejas de sus clases, con histórico y lo que suma a su escalafón.
      _OpcionDocente('Mis interacciones de clase',
          'Cuántas interacciones complejas logras en tus clases, tu histórico y lo que suma a tu escalafón.',
          Icons.forum_outlined, () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MisInteraccionesScreen()));
      }),
      // (4-oct-2026) Estaba en la carpeta «Material didáctico» pero no en el buscador:
      // buscar «diapositivas» o «planeación» no la encontraba. Misma acción que su tarjeta.
      _OpcionDocente('Planeación y Diapositivas con IA',
          'Planea tus sesiones, envíalas a validación y convierte las autorizadas en presentaciones.',
          Icons.auto_awesome_motion,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MaterialIaHubScreen()))),
      _OpcionDocente('Cartas Descriptivas',
          'Consulta la carta descriptiva (propósitos y temario) de tus materias.',
          Icons.description_outlined, _abrirCartas),
      _OpcionDocente('Referencias APA 7',
          'Genera y copia citas y referencias en formato APA 7.',
          Icons.format_quote, _abrirReferenciasApa),
      _OpcionDocente('Portadas de asignatura',
          'Descarga la portada oficial de cada asignatura.',
          Icons.collections_bookmark_outlined, () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const PortadasAsignaturasScreen()));
      }),
      _OpcionDocente('Banners semanales',
          'Imágenes listas para anunciar la sesión de cada semana.',
          Icons.image_outlined, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BannersSemanalesScreen()));
      }),
      _OpcionDocente('Mis tesis dirigidas',
          'Da seguimiento a las tesis que diriges y sus avances.',
          Icons.menu_book, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const DocenteTesisScreen()));
      }),
      _OpcionDocente('Mi contrato',
          'Revisa tus datos, lee tu contrato por materia y fírmalo.',
          Icons.assignment_ind_outlined, _abrirMiContrato),
      _OpcionDocente('Constancias de trabajo',
          'Descarga la constancia de cada materia con acta validada.',
          Icons.workspace_premium_outlined, _abrirConstancias),
      _OpcionDocente('Mi credencial',
          'Tu credencial digital de docente CESSUM.',
          Icons.badge_outlined, () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const CredencialProfesorScreen()));
      }),
      _OpcionDocente('Mis pagos',
          'Historial y estatus de tus pagos por materia impartida.',
          Icons.payments, _abrirMisPagos),
      _OpcionDocente('Subir firma digital',
          'Sube tu firma para que aparezca en actas y documentos oficiales.',
          Icons.draw, _abrirFirmaDigital),
      if (_esAdmin)
        _OpcionDocente('Vista de administrador',
            'Abre el panel completo de administración de CESSUM.',
            Icons.admin_panel_settings, _abrirVistaAdmin),
    ];
  }

  List<Widget> _resultadosBusqueda() {
    final q = _normBusca(_q.trim());
    // (4-oct-2026) También por palabras relacionadas; primero lo que coincide en el nombre.
    final terminos = _terminosDocente(q);
    int puntaje(_OpcionDocente o) {
      final n = _normBusca(o.nombre), d = _normBusca(o.descripcion);
      if (n.contains(q)) return 0;
      if (d.contains(q)) return 1;
      if (terminos.any((x) => n.contains(x))) return 2;
      if (terminos.any((x) => d.contains(x))) return 3;
      return 9;
    }
    final res = _catalogoOpciones().where((o) => puntaje(o) < 9).toList()
      ..sort((x, y) => puntaje(x).compareTo(puntaje(y)));
    if (res.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'Sin resultados para "${_q.trim()}".\n'
              'Prueba con otra palabra: actas, constancia, banners, pagos…',
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
        child: Text(
          '${res.length} resultado(s)',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
      ),
      for (final o in res) ...[
        _tarjetaGrande(
          icono: o.icono,
          titulo: o.nombre,
          subtitulo: o.descripcion,
          onTap: o.accion,
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  // =====================================================================
  //  (4-oct-2026) GRUPOS EN CUADRÍCULA, COMO CARPETAS (igual que la vista de
  //  alumno y el panel de administración). Cada grupo es una tarjeta-widget
  //  (2 columnas en celular, 3 en tableta, 4 en computadora); al tocarla,
  //  sus opciones se abren en un panel sobre la pantalla. Las opciones son
  //  EXACTAMENTE las mismas, con su misma acción.
  // =====================================================================
  _CarpetaDocente _grupoDocente(String titulo, IconData icono, List<Widget> children) =>
      _CarpetaDocente(titulo, icono, children);

  static const Map<String, String> _descGrupoDocente = {
    'Mis clases y grupos': 'Calendario, avisos, asistencia, riesgo, revisiones y tutorías',
    'Captura y avance': 'Avance de captura, avance programático y desempeño',
    'Material didáctico': 'Planeación y diapositivas con IA, portadas, banners y cartas',
    'Tesis y acompañamiento': 'Las tesis que diriges',
    'Mi identidad y documentos': 'Credencial, pagos, contrato, constancias y firma',
  };

  /// Las opciones sueltas de un grupo, en orden: las tarjetas pequeñas salen
  /// de sus filas; las tarjetas anchas y los botones quedan como están. Los
  /// espaciadores VACÍOS sobran (un SizedBox CON contenido, como «Subir firma
  /// digital», sí es una opción).
  List<Widget> _piezasDe(List<Widget> hijos) {
    final out = <Widget>[];
    for (final h in hijos) {
      if (h is Row) {
        for (final c in h.children) {
          if (c is _MenuCard) out.add(c);
        }
      } else if (h is SizedBox && h.child == null) {
        continue;
      } else {
        out.add(h);
      }
    }
    return out;
  }

  int _columnasDocente(double ancho) => ancho < 600 ? 2 : (ancho < 1024 ? 3 : 4);

  Widget _rejillaDocente(List<_CarpetaDocente> carpetas) {
    final visibles = carpetas.where((c) => _piezasDe(c.hijos).isNotEmpty).toList();
    return LayoutBuilder(builder: (ctx, cons) {
      final cols = _columnasDocente(cons.maxWidth);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Text('MÁS OPCIONES',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: cessumMuted(context))),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: visibles.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 172,
            ),
            itemBuilder: (_, i) => _tarjetaCarpetaDocente(visibles[i]),
          ),
        ]),
      );
    });
  }

  IconData? _iconoDe(Widget w) => w is _MenuCard ? w.icon : (w is _TarjetaGrande ? w.icono : null);

  Widget _tarjetaCarpetaDocente(_CarpetaDocente g) {
    final piezas = _piezasDe(g.hijos);
    final iconos = piezas.map(_iconoDe).whereType<IconData>().toList();
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _abrirCarpetaDocente(g),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cessumRed.withValues(alpha: 0.10)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(15)),
                child: Icon(g.icono, color: cessumRed, size: 27),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Text('${piezas.length}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: cessumGold)),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              for (final ic in iconos.take(4))
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(7)),
                  child: Icon(ic, size: 14, color: cessumRed.withValues(alpha: 0.75)),
                ),
              if (iconos.length > 4)
                Text('+${iconos.length - 4}',
                    style: TextStyle(fontSize: 11, color: cessumMuted(context), fontWeight: FontWeight.w700)),
            ]),
            const Spacer(),
            Text(g.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cessumIsDark(context) ? Colors.white : cessumInk(context))),
            const SizedBox(height: 2),
            Text(_descGrupoDocente[g.titulo] ?? '${piezas.length} opciones',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ]),
        ),
      ),
    );
  }

  /// Abre el grupo como carpeta: panel sobre la pantalla con el fondo
  /// desenfocado. Las tarjetas pequeñas van en cuadrícula y las anchas a lo
  /// ancho, en su mismo orden. Al elegir una opción, la carpeta se cierra.
  void _abrirCarpetaDocente(_CarpetaDocente g) {
    final piezas = _piezasDe(g.hijos);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar ${g.titulo}',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dCtx, _, __) {
        final tam = MediaQuery.of(dCtx).size;
        Widget cerrandoAl(Widget w) {
          if (w is _MenuCard) {
            return _MenuCard(icon: w.icon, label: w.label, color: w.color, onTap: () { Navigator.pop(dCtx); w.onTap(); });
          }
          if (w is _TarjetaGrande) {
            return _TarjetaGrande(icono: w.icono, titulo: w.titulo, subtitulo: w.subtitulo, onTap: () { Navigator.pop(dCtx); w.onTap(); });
          }
          return w;
        }
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 760, maxHeight: tam.height * 0.86),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: Theme.of(dCtx).cardColor,
                    borderRadius: BorderRadius.circular(28),
                    clipBehavior: Clip.antiAlias,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cessumRed.withValues(alpha: 0.10)))),
                        child: Row(children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(13)),
                            child: Icon(g.icono, color: cessumRed, size: 23),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(g.titulo,
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cessumIsDark(dCtx) ? Colors.white : cessumInk(dCtx))),
                              if (_descGrupoDocente[g.titulo] != null)
                                Text(_descGrupoDocente[g.titulo]!, style: TextStyle(fontSize: 12, color: cessumMuted(dCtx))),
                            ]),
                          ),
                          IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(dCtx), icon: const Icon(Icons.close_rounded)),
                        ]),
                      ),
                      Flexible(
                        child: LayoutBuilder(builder: (_, cons) {
                          final w = cons.maxWidth - 28;
                          final cols = w < 520 ? 2 : (w < 700 ? 3 : 4);
                          // En orden: las tarjetas pequeñas seguidas forman una cuadrícula; lo ancho va a lo ancho.
                          final bloques = <Widget>[];
                          var buffer = <_MenuCard>[];
                          void vaciar() {
                            if (buffer.isEmpty) return;
                            final lote = List<_MenuCard>.from(buffer);
                            bloques.add(GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: lote.length,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                mainAxisExtent: 124,
                              ),
                              // _MenuCard se envuelve sola en Expanded: cada celda es una fila con una tarjeta.
                              itemBuilder: (_, i) => Row(children: [cerrandoAl(lote[i])]),
                            ));
                            bloques.add(const SizedBox(height: 10));
                            buffer = <_MenuCard>[];
                          }
                          for (final p in piezas) {
                            if (p is _MenuCard) {
                              buffer.add(p);
                            } else {
                              vaciar();
                              bloques.add(cerrandoAl(p));
                              bloques.add(const SizedBox(height: 10));
                            }
                          }
                          vaciar();
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: bloques),
                          );
                        }),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curva = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: curva, child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(curva), child: child));
      },
    );
  }

  /// (4-oct-2026) EL BUSCADOR, PROTAGONISTA: grande, fijo bajo el encabezado y con sugerencias.
  static const List<String> _sugerenciasDocente = [
    'Calificaciones', 'Horario', 'Diapositivas', 'Asistencia', 'Pagos', 'Contrato', 'Constancia', 'Avisos',
  ];

  Widget _buscadorDocente() {
    final esc = MediaQuery.textScalerOf(context).scale(1.0);
    return Container(
      color: cessumBg(context),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: cessumRed.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 5))],
          ),
          child: TextField(
            controller: _buscaCtrl,
            onChanged: (v) => setState(() => _q = v),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '¿Qué necesitas hacer hoy?',
              hintStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: cessumMuted(context)),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.search_rounded, color: cessumRed, size: 26),
              ),
              suffixIcon: _q.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() {
                        _buscaCtrl.clear();
                        _q = '';
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
            itemCount: _sugerenciasDocente.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final s = _sugerenciasDocente[i];
              final activa = _normBusca(_q.trim()) == _normBusca(s);
              return ActionChip(
                label: Text(s),
                labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: activa ? Colors.white : cessumRed),
                backgroundColor: activa ? cessumRed : cessumRed.withValues(alpha: 0.07),
                side: BorderSide(color: cessumRed.withValues(alpha: activa ? 1 : 0.15)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _buscaCtrl.text = s;
                  _q = s;
                }),
              );
            },
          ),
        ),
      ]),
    );
  }

  /// Palabras relacionadas del portal docente (sin acentos, en minúsculas).
  static const Map<String, List<String>> _relacionadasDocente = {
    'calificacion': ['captura', 'acta', 'avance de captura', 'evaluacion'],
    'acta': ['captura', 'calificacion'],
    'captura': ['calificacion', 'acta', 'avance'],
    'horario': ['calendario', 'clase', 'materia'],
    'clase': ['calendario', 'horario', 'aula', 'interacciones', 'materia'],
    'diapositiva': ['planeacion', 'material', 'presentacion', 'con ia'],
    'planeacion': ['diapositiva', 'material', 'carta descriptiva'],
    'material': ['planeacion', 'diapositiva', 'portada', 'banner', 'carta'],
    'asistencia': ['justificacion', 'falta', 'riesgo'],
    'falta': ['justificacion', 'asistencia'],
    'pago': ['pagos', 'nomina', 'honorario', 'contrato'],
    'contrato': ['firma', 'pagos', 'constancia'],
    'constancia': ['trabajo', 'contrato', 'documento'],
    'aviso': ['avisos', 'grupo', 'mensaje', 'notificacion'],
    'alumno': ['grupo', 'riesgo', 'chat', 'tutoria', 'asistencia'],
    'chat': ['mensaje', 'alumno'],
    'tarea': ['revision', 'entrega', 'aula'],
    'entrega': ['revision', 'tarea'],
    'tesis': ['tesis dirigidas', 'acompanamiento'],
    'credencial': ['identidad', 'foto'],
    'desempeno': ['informe', 'evaluacion', 'ranking'],
    'moodle': ['aula virtual', 'aula'],
  };

  List<String> _terminosDocente(String q) {
    if (q.length < 3) return const [];
    final out = <String>{};
    _relacionadasDocente.forEach((clave, rel) {
      final toca = q.contains(clave) || clave.startsWith(q) || rel.any((r) => r.startsWith(q) || q.contains(r));
      if (toca) {
        out.add(clave);
        out.addAll(rel);
      }
    });
    out.remove(q);
    return out.toList();
  }

  // Tarjeta grande con título y descripción (Cartas, Contrato, Captura...).
  // (4-oct-2026) Ahora es un componente (_TarjetaGrande) para que la carpeta
  // pueda cerrarse al usarla; se ve y funciona igual que antes.
  Widget _tarjetaGrande({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) =>
      _TarjetaGrande(icono: icono, titulo: titulo, subtitulo: subtitulo, onTap: onTap);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      body: SafeArea(
        // (4-oct-2026) El encabezado se compacta al desplazarse y el buscador queda fijo debajo.
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _EncabezadoDocente(
                perfil: _perfil,
                escala: MediaQuery.textScalerOf(context).scale(1.0),
                onInfo: _abrirAcercaDe,
                onCambiar: () => _cambiarPerfil(context),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _BuscadorFijoDocente(alto: 62 + 56 * MediaQuery.textScalerOf(context).scale(1.0), construir: _buscadorDocente),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                [
                  _tarjetaNotificaciones(),
                  // (4-oct-2026) El buscador ya no va aquí: quedó fijo arriba (_buscadorDocente).
                  if (_q.trim().isEmpty) ...[
                  // ============================================================
                  // MENÚ REORGANIZADO (jul-2026): lo diario arriba (Mi panel,
                  // Capturar calificaciones, Aula, Mi horario) y el resto en
                  // grupos colapsables por tema.
                  // ============================================================
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'PORTAL DOCENTE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cessumRed,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MiPanelDocenteScreen()),
                      ),
                      icon: const Icon(Icons.dashboard),
                      label: const Text('Mi panel',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // (24-sep) Centros inteligentes · fase 2: Mi semana.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed,
                        side: const BorderSide(color: cessumRed, width: 1.4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MiSemanaScreen()),
                      ),
                      icon: const Icon(Icons.view_week_outlined),
                      label: const Text('Mi semana',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _tarjetaGrande(
                    icono: Icons.grading,
                    titulo: 'Capturar calificaciones',
                    subtitulo:
                        'Registra calificaciones por grupo y genera el acta oficial',
                    onTap: _abrirCaptura,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MenuCard(
                        icon: Icons.school,
                        label: 'Aula\nVirtual',
                        color: cessumRed,
                        onTap: () => abrirAula(context),
                      ),
                      const SizedBox(width: 12),
                      _MenuCard(
                        icon: Icons.calendar_month,
                        label: 'Mi\nhorario',
                        color: cessumGold,
                        onTap: _abrirMiHorario,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // (4-oct-2026) Los grupos, en cuadrícula de carpetas (ver _rejillaDocente).
                  _rejillaDocente([
                  _grupoDocente('Mis clases y grupos', Icons.groups, [
                    _tarjetaGrande(
                      icono: Icons.menu_book_outlined,
                      titulo: 'Mis materias',
                      subtitulo:
                          'Consulta los grupos y materias que tienes asignados',
                      onTap: _abrirMisMaterias,
                    ),
                    const SizedBox(height: 12),
                    _tarjetaGrande(
                      icono: Icons.timer_outlined,
                      titulo: 'Revisiones pendientes',
                      subtitulo:
                          'Entregas de tus alumnos con cuenta regresiva de 24 h',
                      onTap: _abrirRevisiones,
                    ),
                    const SizedBox(height: 12),
                    _tarjetaGrande(
                      icono: Icons.assessment_outlined,
                      titulo: 'Mi informe de evaluación',
                      subtitulo:
                          'Tu puntaje de calidad y las observaciones de Coordinación',
                      onTap: _abrirMiInforme,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MenuCard(
                          icon: Icons.event,
                          label: 'Calendario\ny clases',
                          color: cessumRed,
                          onTap: () => Helpers.abrirUrlExterna(
                            calendarioUrl,
                            context,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _MenuCard(
                          icon: Icons.campaign,
                          label: 'Avisos a\nmi grupo',
                          color: cessumGold,
                          onTap: _abrirAvisosDocente,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MenuCard(
                          icon: Icons.summarize,
                          label: 'Reporte de\nmi grupo',
                          color: cessumRed,
                          onTap: _abrirReporteGrupo,
                        ),
                        const SizedBox(width: 12),
                        // Va junto al reporte y a los alumnos en riesgo: es la
                        // misma pregunta —cómo va mi grupo— vista por otro lado.
                        _MenuCard(
                          icon: Icons.how_to_reg,
                          label: 'Asistencia\nde mis alumnos',
                          color: cessumRed,
                          onTap: _abrirAsistenciaDocente,
                        ),
                        const SizedBox(width: 12),
                        _MenuCard(
                          icon: Icons.warning_amber_rounded,
                          label: 'Alumnos\nen riesgo',
                          color: cessumGold,
                          onTap: _abrirRiesgoDocente,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MenuCard(
                          icon: Icons.event_busy,
                          label: 'Justificaciones\nde faltas',
                          color: cessumRed,
                          onTap: _abrirJustificaciones,
                        ),
                        const SizedBox(width: 12),
                        _MenuCard(
                          icon: Icons.support_agent,
                          label: 'Tutorías y\nasesorias',
                          color: cessumGold,
                          onTap: _abrirTutoriasDocente,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // (8-oct-2026) El chat ya existía (ver el comentario de ago-24 en
                    // _catalogoOpciones) pero la corrección de entonces solo lo agregó al
                    // buscador, no a ninguna carpeta visible: seguía sin puerta para quien
                    // no escribiera «chat» o «mensaje».
                    _tarjetaGrande(
                      icono: Icons.forum_outlined,
                      titulo: 'Chat con alumno',
                      subtitulo:
                          'Dudas de tus alumnos por el único canal institucional. Tienes 24 horas para la primera respuesta',
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const MensajesScreen())),
                    ),
                  ]),

                  _grupoDocente('Captura y avance', Icons.fact_check, [
                    Row(
                      children: [
                        _MenuCard(
                          icon: Icons.fact_check,
                          label: 'Avance de\ncaptura',
                          color: cessumRed,
                          onTap: _abrirMiCaptura,
                        ),
                        const SizedBox(width: 12),
                        _MenuCard(
                          icon: Icons.trending_up,
                          label: 'Mi avance\nprogramatico',
                          color: cessumGold,
                          onTap: _abrirAvanceDocente,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MenuCard(
                          icon: Icons.insights,
                          label: 'Mi\ndesempeno',
                          color: cessumRed,
                          onTap: _abrirMiDesempeno,
                        ),
                        const SizedBox(width: 12),
                        // (8-oct-2026) Antes solo estaba en el buscador del menú (catálogo de
                        // opciones): quien no escribiera «interacciones» no la encontraba.
                        _MenuCard(
                          icon: Icons.forum_outlined,
                          label: 'Mis\ninteracciones',
                          color: cessumGold,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const MisInteraccionesScreen())),
                        ),
                      ],
                    ),
                  ]),

                  _grupoDocente('Material didáctico', Icons.auto_stories, [
                    // (9-sep) UNA SOLA PUERTA AL CICLO DE MATERIAL CON IA.
                    // Antes eran tres renglones sueltos —planear, ver el
                    // estatus, crear presentaciones— y el docente no tenía
                    // por qué saber que uno depende del otro: la presentación
                    // solo se arma con una planeación que Vicerrectoría ya
                    // validó. La pantalla nueva los presenta en orden y dice
                    // en qué paso va cada quien.
                    _tarjetaGrande(
                      icono: Icons.auto_awesome_motion,
                      titulo: 'Planeación y Diapositivas con IA',
                      subtitulo:
                          'Planea tus sesiones, envíalas a validación y convierte las autorizadas en presentaciones',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MaterialIaHubScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // (8-oct-2026) Laboratorio de clases: practicar con CUALQUIER materia
                    // del catálogo (no solo las asignadas), sin que nada se coloque en un
                    // aula real; pensado para un taller/convocatoria con varios docentes.
                    _tarjetaGrande(
                      icono: Icons.science_outlined,
                      titulo: 'Laboratorio de clases',
                      subtitulo:
                          'Practica presentaciones y planeaciones de cualquier materia, sin afectar ningún curso real',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LaboratorioClasesScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // (8-oct-2026) Banco de Planeaciones: planeaciones de otros
                    // docentes ya validadas por Vicerrectoría, como referencia.
                    _tarjetaGrande(
                      icono: Icons.auto_stories_outlined,
                      titulo: 'Banco de Planeaciones',
                      subtitulo:
                          'Consulta planeaciones de otros docentes ya validadas, como referencia para la tuya',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BancoPlaneacionesScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _tarjetaGrande(
                      icono: Icons.description_outlined,
                      titulo: 'Cartas Descriptivas',
                      subtitulo:
                          'Consulta la carta descriptiva de cada una de tus materias',
                      onTap: _abrirCartas,
                    ),
                    const SizedBox(height: 12),
                    _tarjetaGrande(
                      icono: Icons.format_quote,
                      titulo: 'Referencias APA 7',
                      subtitulo:
                          'Genera y copia citas y referencias en formato APA 7',
                      onTap: _abrirReferenciasApa,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MenuCard(
                          icon: Icons.collections_bookmark_outlined,
                          label: 'Portadas de\nasignatura',
                          color: cessumRed,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const PortadasAsignaturasScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _MenuCard(
                          icon: Icons.image_outlined,
                          label: 'Banners\nsemanales',
                          color: cessumGold,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BannersSemanalesScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ]),

                  _grupoDocente('Tesis y acompañamiento', Icons.menu_book, [
                    Row(
                      children: [
                        _MenuCard(
                          icon: Icons.menu_book,
                          label: 'Mis tesis\ndirigidas',
                          color: cessumRed,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DocenteTesisScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ]),

                  _grupoDocente('Mi identidad y documentos', Icons.badge, [
                    _tarjetaGrande(
                      icono: Icons.assignment_ind_outlined,
                      titulo: 'Mi contrato',
                      subtitulo: 'Revisa tus datos, lee tu contrato y fírmalo',
                      onTap: _abrirMiContrato,
                    ),
                    const SizedBox(height: 12),
                    _tarjetaGrande(
                      icono: Icons.workspace_premium_outlined,
                      titulo: 'Constancias de trabajo',
                      subtitulo:
                          'Descarga la constancia de cada materia con acta validada',
                      onTap: _abrirConstancias,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MenuCard(
                          icon: Icons.badge_outlined,
                          label: 'Mi\ncredencial',
                          color: cessumRed,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const CredencialProfesorScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _MenuCard(
                          icon: Icons.payments,
                          label: 'Mis\npagos',
                          color: cessumGold,
                          onTap: _abrirMisPagos,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cessumGold,
                          side:
                              const BorderSide(color: cessumGold, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _abrirFirmaDigital,
                        icon: const Icon(Icons.draw),
                        label: const Text('Subir firma digital',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                  ]),


                  const SizedBox(height: 16),
                  if (_esAdmin) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cessumRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        onPressed: _abrirVistaAdmin,
                        icon: const Icon(Icons.admin_panel_settings, size: 22),
                        label: const Text(
                          'Vista de administrador',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // (8-oct-2026) Créditos de Claude: en vez de jalar el dato por API
                    // (exigiría una Admin API Key que la cuenta no tiene a la mano),
                    // abre directo la página de la plataforma donde ya se ve el saldo.
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cessumRed,
                          side: const BorderSide(color: cessumRed),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => launchUrl(
                          Uri.parse('https://platform.claude.com/claude-code'),
                          mode: LaunchMode.externalApplication,
                          webOnlyWindowName: '_blank',
                        ),
                        icon: const Icon(Icons.account_balance_wallet_outlined, size: 22),
                        label: const Text(
                          'Créditos de Claude',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      onPressed: () => Helpers.abrirWhatsApp(context),
                      icon: const Icon(Icons.chat, size: 22),
                      label: const Text(
                        'WhatsApp - Soporte CESSUM',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD93025),
                        side: const BorderSide(
                          color: Color(0xFFD93025),
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Helpers.abrirGmail(context),
                      icon: const Icon(Icons.email, size: 22),
                      label: const Text(
                        'Abrir Gmail',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  ] else ...[
                    ..._resultadosBusqueda(),
                  ],
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          '$_version - Portal Docente',
                          style: TextStyle(
                            fontSize: 11,
                            color: cessumMuted(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => Helpers.abrirUrlExterna(
                            avisoPrivacidadUrl,
                            context,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Text(
                              'Aviso de privacidad',
                              style: TextStyle(
                                fontSize: 11,
                                color: cessumRed,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaludoDocente extends StatelessWidget {
  final TeacherProfile perfil;

  const _SaludoDocente({required this.perfil});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.school, color: cessumRed, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              perfil.saludoCompleto,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cessumIsDark(context) ? Colors.white : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            height: 120,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cessumIsDark(context) ? Colors.white : Colors.black87,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Una opción del portal para el buscador: nombre, descripción (también se
// busca por ella), icono y la acción que abre.
class _OpcionDocente {
  final String nombre;
  final String descripcion;
  final IconData icono;
  final VoidCallback accion;
  const _OpcionDocente(this.nombre, this.descripcion, this.icono, this.accion);
}

/// (4-oct-2026) Un grupo del portal docente como «carpeta».
class _CarpetaDocente {
  final String titulo;
  final IconData icono;
  final List<Widget> hijos;
  const _CarpetaDocente(this.titulo, this.icono, this.hijos);
}

/// Tarjeta ancha con ícono, título y descripción (antes era un método; el
/// aspecto y la acción son los mismos).
class _TarjetaGrande extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;
  const _TarjetaGrande({required this.icono, required this.titulo, required this.subtitulo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icono, color: cessumRed, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cessumIsDark(context)
                            ? Colors.white
                            : cessumInk(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: cessumMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cessumMuted(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// (4-oct-2026) Encabezado que se COMPACTA al desplazarse: arriba, el venado,
/// «App CESSUM» y el docente; al bajar, una barra delgada con el logotipo
/// pequeño y el nombre.
class _EncabezadoDocente extends SliverPersistentHeaderDelegate {
  final TeacherProfile? perfil;
  final double escala;
  final VoidCallback onInfo;
  final VoidCallback onCambiar;
  _EncabezadoDocente({required this.perfil, required this.onInfo, required this.onCambiar, this.escala = 1.0});

  @override
  double get maxExtent => (perfil != null ? 176 : 138) + 50 * (escala - 1).clamp(0.0, 1.0);
  @override
  double get minExtent => 58;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final oscuro = cessumIsDark(context);
    return Material(
      color: Theme.of(context).cardColor,
      elevation: t > 0.95 ? 2 : 0,
      child: ClipRect(
        child: Stack(children: [
          Positioned(
            left: 0,
            right: 0,
            top: 6 - shrinkOffset * 0.35,
            child: Opacity(
              opacity: (1 - t * 1.6).clamp(0.0, 1.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/images/logo.png', height: 56, fit: BoxFit.contain),
                const SizedBox(height: 6),
                Text('App CESSUM',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: oscuro ? Colors.white : cessumInk(context))),
                if (perfil != null) ...[
                  const SizedBox(height: 10),
                  _SaludoDocente(perfil: perfil!),
                ],
              ]),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 58,
            child: Row(children: [
              IconButton(icon: const Icon(Icons.info_outline, color: cessumRed), tooltip: 'Acerca de', onPressed: onInfo),
              Expanded(
                child: Opacity(
                  opacity: ((t - 0.55) / 0.45).clamp(0.0, 1.0),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Image.asset('assets/images/logo.png', height: 28, fit: BoxFit.contain),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(perfil?.saludoCompleto ?? 'App CESSUM',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: oscuro ? Colors.white : cessumInk(context))),
                    ),
                  ]),
                ),
              ),
              IconButton(icon: const Icon(Icons.swap_horiz, color: cessumRed), tooltip: 'Cambiar perfil', onPressed: onCambiar),
            ]),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 3,
            child: Opacity(
              opacity: t,
              child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [cessumRed, cessumGold]))),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _EncabezadoDocente old) => old.perfil != perfil || old.escala != escala;
}

/// (4-oct-2026) El buscador queda FIJO bajo el encabezado, siempre visible.
class _BuscadorFijoDocente extends SliverPersistentHeaderDelegate {
  final double alto;
  final Widget Function() construir;
  _BuscadorFijoDocente({required this.alto, required this.construir});
  @override
  double get maxExtent => alto;
  @override
  double get minExtent => alto;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox(height: alto, child: construir());
  @override
  bool shouldRebuild(covariant _BuscadorFijoDocente old) => true;
}
