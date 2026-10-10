import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'asistencia_grupo_screen.dart';
import 'pedagogia_pase_lista_screen.dart';
import 'eval_grupo_screen.dart';
import 'laboratorio_evaluacion_screen.dart';

const _ordenDias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo'
];

/// Horario semanal del docente: sus clases por día, con grupo, materia y
/// accesos directos a la videollamada y al Aula.
class MiHorarioDocenteScreen extends StatefulWidget {
  const MiHorarioDocenteScreen({super.key});

  @override
  State<MiHorarioDocenteScreen> createState() => _MiHorarioDocenteScreenState();
}

class _MiHorarioDocenteScreenState extends State<MiHorarioDocenteScreen> {
  List<Map<String, dynamic>> _clases = [];
  // Materias cuya fecha de término ya pasó. Se conservan aparte: el docente
  // sigue necesitando su asistencia y su acta.
  List<Map<String, dynamic>> _terminadas = [];
  bool _cargando = true;
  /// (ago-12) El correo del docente, guardado al cargar: lo necesita el
  /// perfil del grupo y pedirlo otra vez en cada toque sería un viaje de más.
  String _correoDoc = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final correo = await SessionStore.validEmail();
      _correoDoc = correo ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_grupos',
        'correo': correo ?? '',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        // (ago-25) Las materias que YA TERMINARON salen del horario.
        // «Mi horario» responde a «¿qué clase tengo esta semana?», y una
        // materia del 26-1 con su botón de videollamada contesta que sí
        // cuando la respuesta es no. Peor: si el docente lo pulsa, entra a
        // una sala vacía.
        // No se borran: se muestran aparte, sin botones de acción, porque
        // el docente todavía necesita ver la asistencia y capturar actas.
        final todas = ((data['grupos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _clases = todas.where((c) => c['terminada'] != true).toList();
        _terminadas = todas.where((c) => c['terminada'] == true).toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar tu horario.';
      });
    }
  }

  int _ordenDia(String dia) {
    final i = _ordenDias.indexWhere(
        (d) => d.toLowerCase() == dia.trim().toLowerCase());
    return i < 0 ? 99 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi horario',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : (_clases.isEmpty && _terminadas.isEmpty)
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No tienes clases asignadas por ahora.',
                          style: TextStyle(color: cessumMuted(context)),
                        ),
                      ),
                    )
                  : _vista(),
    );
  }

  Widget _vista() {
    final porDia = <String, List<Map<String, dynamic>>>{};
    for (final c in _clases) {
      final dia = (c['dia'] ?? 'Sin día').toString();
      porDia.putIfAbsent(dia, () => []).add(c);
    }
    final dias = porDia.keys.toList()
      ..sort((a, b) => _ordenDia(a).compareTo(_ordenDia(b)));

    // Se arma la lista en pasos, no encadenando operadores sobre un literal:
    // más largo de leer pero imposible de romper con un paréntesis mal puesto.
    final items = <Widget>[];

    if (dias.isEmpty && _terminadas.isNotEmpty) {
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'No tienes clases programadas esta semana. Todas tus materias '
          'asignadas ya terminaron.',
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700),
        ),
      ));
    }

    for (final dia in dias) {
      final clases = porDia[dia]!;
      clases.sort((a, b) =>
          (a['hora'] ?? '').toString().compareTo((b['hora'] ?? '').toString()));
      items.add(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(dia,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: cessumRed)),
          ),
          ...clases.map(_tarjetaClase),
        ],
      ));
    }

    if (_terminadas.isNotEmpty) items.add(_bloqueTerminadas());

    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: items,
      ),
    );
  }

  /// (ago-25) Materias cuya fecha de término ya pasó.
  ///
  /// No se borran de la vista: el docente todavía necesita revisar la
  /// asistencia y capturar el acta si quedó pendiente. Pero salen del
  /// horario semanal y SIN los botones de videollamada ni de reponer
  /// sesión, que en una materia cerrada solo llevan a una sala vacía.
  Widget _bloqueTerminadas() {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.history, size: 17, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text('Materias que ya terminaron',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700)),
          ]),
          const SizedBox(height: 3),
          Text(
            'Ya no tienen sesión, pero puedes consultar su asistencia y '
            'capturar el acta si quedó pendiente.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          ..._terminadas.map(_tarjetaTerminada),
        ],
      ),
    );
  }

  Widget _tarjetaTerminada(Map<String, dynamic> c) {
    final dias = c['diasDesdeTermino'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey.withValues(alpha: 0.05),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c['materia'] ?? ''}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800)),
            const SizedBox(height: 2),
            Text(
              '${c['programa'] ?? ''} · ${c['generacion'] ?? ''} · '
              'Grupo ${c['grupo'] ?? ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              dias is num && dias > 0
                  ? 'Terminó hace ${dias.toInt()} día(s)'
                  : 'Terminada',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            // (9-oct-2026) Una materia terminada es justo la que se va a
            // evaluar: asistencia y laboratorio, sin botones de sesión.
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1E7B34),
                      padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AsistenciaGrupoScreen(
                        programa: (c['programa'] ?? '').toString(),
                        generacion: (c['generacion'] ?? '').toString(),
                        grupo: (c['grupo'] ?? '').toString(),
                        materia: (c['materia'] ?? '').toString(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.fact_check_outlined, size: 16),
                  label: const Text('Asistencia del grupo',
                      style: TextStyle(fontSize: 11.5)),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: cessumGold,
                      padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => _abrirLaboratorio(c),
                  icon: const Icon(Icons.science_outlined, size: 16),
                  label: const Text('Laboratorio de evaluación',
                      style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// (9-oct-2026) Abre el Laboratorio de evaluación de una clase. Desde aquí
  /// «Pasar a captura» abre «Capturar calificaciones» con la materia ya
  /// seleccionada y las sugerencias puestas.
  void _abrirLaboratorio(Map<String, dynamic> c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LaboratorioEvaluacionScreen(
          programa: (c['programa'] ?? '').toString(),
          generacion: (c['generacion'] ?? '').toString(),
          grupo: (c['grupo'] ?? '').toString(),
          materia: (c['materia'] ?? '').toString(),
          clave: (c['clave'] ?? '').toString(),
          ciclo: (c['ciclo'] ?? '').toString(),
          modalidad: (c['modalidad'] ?? '').toString(),
          docente: (c['docente'] ?? '').toString(),
          desdeCaptura: false,
        ),
      ),
    );
  }

  Widget _tarjetaClase(Map<String, dynamic> c) {
    final hora = (c['hora'] ?? '').toString();
    final linkLlamada = (c['linkLlamada'] ?? '').toString();
    final linkAula = (c['linkAula'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hora.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: cessumGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(hora,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF8A6118))),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c['materia']}',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${c['programa']} · ${c['generacion']} · Grupo ${c['grupo']}',
                        style: TextStyle(
                            fontSize: 11.5, color: cessumMuted(context)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (linkLlamada.isNotEmpty || linkAula.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (linkLlamada.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: cessumRed,
                            side: const BorderSide(color: cessumRed),
                            padding:
                                const EdgeInsets.symmetric(vertical: 4)),
                        onPressed: () =>
                            Helpers.abrirUrlExterna(linkLlamada, context),
                        icon: const Icon(Icons.videocam, size: 16),
                        label: const Text('Videollamada',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ),
                  if (linkLlamada.isNotEmpty && linkAula.isNotEmpty)
                    const SizedBox(width: 8),
                  if (linkAula.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: cessumGold,
                            side: const BorderSide(color: cessumGold),
                            padding:
                                const EdgeInsets.symmetric(vertical: 4)),
                        onPressed: () =>
                            Helpers.abrirUrlExterna(linkAula, context),
                        icon: const Icon(Icons.school, size: 16),
                        label: const Text('Aula',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: cessumRed,
                      padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => _solicitarCambioHorario(c),
                  icon: const Icon(Icons.schedule, size: 16),
                  label: const Text('Solicitar cambio de día/hora',
                      style: TextStyle(fontSize: 11.5)),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6A4FB0),
                      padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => _reponerSesion(c),
                  icon: const Icon(Icons.event_repeat, size: 16),
                  label: const Text('Reponer sesión',
                      style: TextStyle(fontSize: 11.5)),
                ),
                if ((c['programa'] ?? '').toString().toLowerCase().contains('licenciatura en pedagog'))
                  TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PedagogiaPaseListaScreen(
                      programa:(c['programa'] ?? '').toString(), generacion:(c['generacion'] ?? '').toString(),
                      grupo:(c['grupo'] ?? '').toString(), materia:(c['materia'] ?? '').toString()))),
                    icon:const Icon(Icons.how_to_reg),label:const Text('Pase de lista presencial')),
                // (ago-9) La ruta asistencia_grupo existía desde el 6-ago y
                // nunca tuvo pantalla: el dato se calculaba y nadie lo veía.
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1E7B34),
                      padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AsistenciaGrupoScreen(
                        programa: (c['programa'] ?? '').toString(),
                        generacion: (c['generacion'] ?? '').toString(),
                        grupo: (c['grupo'] ?? '').toString(),
                        materia: (c['materia'] ?? '').toString(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.fact_check_outlined, size: 16),
                  label: const Text('Asistencia del grupo',
                      style: TextStyle(fontSize: 11.5)),
                ),
                // (9-oct-2026) Laboratorio de evaluación: las actividades del
                // aula y la asistencia de ESTA materia, con la sugerencia de
                // calificación y el paso a la captura.
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: cessumGold,
                      padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => _abrirLaboratorio(c),
                  icon: const Icon(Icons.science_outlined, size: 16),
                  label: const Text('Laboratorio de evaluación',
                      style: TextStyle(fontSize: 11.5)),
                ),
                // (ago-12) El perfil que dejaron otros profesores de este
                // grupo, y el formulario para dejar el tuyo. Va aquí porque
                // es donde el docente mira su clase antes de darla.
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: cessumRed,
                      padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EvalGrupoScreen(
                        correo: _correoDoc,
                        docente: (c['docente'] ?? '').toString(),
                        programa: (c['programa'] ?? '').toString(),
                        generacion: (c['generacion'] ?? '').toString(),
                        grupo: (c['grupo'] ?? '').toString(),
                        materia: (c['materia'] ?? '').toString(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.groups_outlined, size: 16),
                  label: const Text('Perfil del grupo',
                      style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // El docente registra que una sesión se repondrá/repuso otro día (solo fecha
  // + nota, sin archivos). La grabación la cuelga aparte en Moodle. Se envía a
  // reposicion_enviar y la coordinación recibe el aviso.
  Future<void> _reponerSesion(Map<String, dynamic> c) async {
    final fechaPerdidaCtrl = TextEditingController();
    final fechaRepoCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reponer sesión', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${c['materia']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                '${c['programa']} · ${c['generacion']} · Grupo ${c['grupo']}',
                style: TextStyle(fontSize: 12, color: cessumMuted(context)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fechaPerdidaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Fecha de la sesión que se repone',
                  hintText: 'ej. 22/07/2026',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fechaRepoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Fecha en que se repondrá / se repuso',
                  hintText: 'ej. 25/07/2026',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo / nota (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'La grabación cuélgala directamente en Moodle. Aquí solo queda el registro para la coordinación.',
                style: TextStyle(fontSize: 11, color: cessumFaint(context)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A4FB0),
                foregroundColor: Colors.white),
            onPressed: () {
              if (fechaPerdidaCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    final correo = await SessionStore.validEmail();
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'reposicion_enviar',
        'docente': (c['docente'] ?? '').toString(),
        'correoDocente': correo ?? (c['correo'] ?? '').toString(),
        'programa': (c['programa'] ?? '').toString(),
        'generacion': (c['generacion'] ?? '').toString(),
        'grupo': (c['grupo'] ?? '').toString(),
        'materia': (c['materia'] ?? '').toString(),
        'fechaPerdida': fechaPerdidaCtrl.text.trim(),
        'fechaReposicion': fechaRepoCtrl.text.trim(),
        'motivo': motivoCtrl.text.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(data['ok'] == true
            ? 'Reposición registrada. La coordinación fue avisada.'
            : 'No se pudo: ${data['error'] ?? 'error'}'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error de conexión. Intenta de nuevo.')),
      );
    }
  }

  // El docente pide mover su clase: TEMPORAL (una fecha puntual) o PERMANENTE
  // (cambia el horario fijo). Se envía a cambio_horario_enviar; el admin lo
  // resuelve y le llega aviso.
  /// (ago-28) Las fechas se eligen en CALENDARIO, no se escriben.
  /// El campo era texto libre con el ejemplo "sábado 26/07/2026", así que
  /// llegaban en cualquier formato y el backend las guardaba tal cual: una
  /// fecha mal tecleada terminaba en el correo de treinta alumnos.
  String _fmt(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/'
      '${f.month.toString().padLeft(2, '0')}/${f.year}';

  Future<DateTime?> _pedirFecha(DateTime? inicial, String titulo) {
    final hoy = DateTime.now();
    return showDatePicker(
      context: context,
      helpText: titulo,
      initialDate: inicial ?? hoy,
      // Se permite hacia atrás un poco por si la sesión original ya pasó,
      // pero no un año entero: casi siempre es un error de dedo.
      firstDate: hoy.subtract(const Duration(days: 30)),
      lastDate: hoy.add(const Duration(days: 365)),
      locale: const Locale('es', 'MX'),
    );
  }

  Future<void> _solicitarCambioHorario(Map<String, dynamic> c) async {
    var tipo = 'Temporal';
    DateTime? fechaOriginal;
    DateTime? fechaPropuesta;
    String? diaSel;
    final horaCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();
    const dias = [
      'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Solicitar cambio de día/hora',
              style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['materia']}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${c['programa']} · ${c['generacion']} · Grupo ${c['grupo']}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                ),
                const SizedBox(height: 12),
                // Tipo: temporal o permanente
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Temporal', label: Text('Temporal')),
                    ButtonSegment(
                        value: 'Permanente', label: Text('Permanente')),
                  ],
                  selected: {tipo},
                  onSelectionChanged: (v) => setLocal(() => tipo = v.first),
                ),
                const SizedBox(height: 6),
                Text(
                  tipo == 'Temporal'
                      ? 'Solo mueve UNA sesión (una fecha específica). No cambia tu horario fijo.'
                      : 'Cambia tu horario fijo de aquí en adelante.',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                ),
                const SizedBox(height: 12),
                // (ago-28) Aviso institucional. Mover una clase no es un
                // trámite de rutina: descoloca a todo el grupo y cuenta en el
                // ranking. Decirlo aquí, antes de enviar, es más útil que
                // reclamarlo después.
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0A800).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFFE0A800)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 17, color: Color(0xFF8A6100)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cambiar el día u hora de una clase no es un '
                          'procedimiento ordinario. Afecta la organización del '
                          'grupo y queda registrado en tu ranking '
                          'institucional. Úsalo solo cuando sea necesario.',
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: Color(0xFF6B4C00)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (tipo == 'Temporal') ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      alignment: Alignment.centerLeft,
                      foregroundColor: cessumInk(context),
                      side: BorderSide(color: cessumFaint(context)),
                    ),
                    onPressed: () async {
                      final f = await _pedirFecha(
                          fechaOriginal, 'Día original de tu clase');
                      if (f != null) setLocal(() => fechaOriginal = f);
                    },
                    icon: const Icon(Icons.event_busy,
                        size: 18, color: cessumRed),
                    label: Text(
                      fechaOriginal == null
                          ? 'Día original de tu clase *'
                          : 'Original: ${_fmt(fechaOriginal!)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 46),
                      alignment: Alignment.centerLeft,
                      foregroundColor: cessumInk(context),
                      side: BorderSide(color: cessumFaint(context)),
                    ),
                    onPressed: () async {
                      final f = await _pedirFecha(
                          fechaPropuesta ?? fechaOriginal,
                          'Fecha propuesta para reponerla');
                      if (f != null) setLocal(() => fechaPropuesta = f);
                    },
                    icon: const Icon(Icons.event_available,
                        size: 18, color: Color(0xFF1E7B34)),
                    label: Text(
                      fechaPropuesta == null
                          ? 'Fecha propuesta para el cambio *'
                          : 'Propuesta: ${_fmt(fechaPropuesta!)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (fechaOriginal != null &&
                      fechaPropuesta != null &&
                      !fechaPropuesta!.isAfter(fechaOriginal!))
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'La fecha propuesta es anterior o igual a la original. '
                        'Revísala: se puede reponer antes, pero conviene '
                        'confirmar que es lo que quieres.',
                        style: TextStyle(fontSize: 11.5, color: cessumRed),
                      ),
                    ),
                ] else
                  DropdownButtonFormField<String>(
                    value: diaSel,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Nuevo día fijo *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: dias
                        .map((d) =>
                            DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) => setLocal(() => diaSel = v),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: horaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hora solicitada *',
                    hintText: 'ej. 11:30 o 11:30-13:00',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: motivoCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Motivo (opcional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                if (horaCtrl.text.trim().isEmpty) return;
                if (tipo == 'Temporal' &&
                    (fechaOriginal == null || fechaPropuesta == null)) return;
                if (tipo == 'Permanente' && (diaSel == null)) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    final correo = await SessionStore.validEmail();
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'cambio_horario_enviar',
        'docente': (c['docente'] ?? '').toString(),
        'correoDocente': correo ?? (c['correo'] ?? '').toString(),
        'programa': (c['programa'] ?? '').toString(),
        'generacion': (c['generacion'] ?? '').toString(),
        'grupo': (c['grupo'] ?? '').toString(),
        'materia': (c['materia'] ?? '').toString(),
        'tipo': tipo,
        'diaActual': (c['dia'] ?? '').toString(),
        'horaActual': (c['hora'] ?? '').toString(),
        'fecha': (tipo == 'Temporal' && fechaOriginal != null)
            ? _fmt(fechaOriginal!)
            : '',
        'fechaPropuesta': (tipo == 'Temporal' && fechaPropuesta != null)
            ? _fmt(fechaPropuesta!)
            : '',
        'diaSolicitado': tipo == 'Permanente' ? (diaSel ?? '') : '',
        'horaSolicitada': horaCtrl.text.trim(),
        'motivo': motivoCtrl.text.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(data['ok'] == true
            ? 'Solicitud enviada. La coordinación te avisará.'
            : 'No se pudo: ${data['error'] ?? 'error'}'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error de conexión. Intenta de nuevo.')),
      );
    }
  }
}
