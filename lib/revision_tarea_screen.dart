// =====================================================================
//  revision_tarea_screen.dart · CESSUM · App CESSUM
//  REVISIÓN POR TAREA (5-oct-2026).
//
//  RevisionPorTareaScreen: las tareas del docente con su avance
//  (revisadas contra pendientes) y los borradores listos.
//
//  RevisionTareaLoteScreen: UNA tarea completa:
//   · quién entregó y quién falta (de Moodle), en porcentaje;
//   · sus criterios de revisión (prompt o rúbrica del docente);
//   · «Pre-llenar con IA»: borrador de TODAS las entregas pendientes, 3 a
//     la vez, con la misma lógica (criterios del docente, retro formal de
//     un párrafo con feedforward). NO ENVÍA NADA: deja la calificación y la
//     retroalimentación escritas;
//   · cada fila: calificación (o rúbrica), retro editable, «Ver entrega»
//     en ventana emergente, volver a generar;
//   · «Editar todas»: abre todas las retroalimentaciones de corrido;
//   · «Enviar todas»: escribe en Moodle todo lo listo, de un jalón.
//  Rutas: revision_tareas · revision_tarea (GET) · revision_borrador ·
//  revision_borrador_editar · revision_enviar (POST).
// =====================================================================
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'entrega_visor_screen.dart';
import 'revision_estilo.dart';   // (6-oct-2026) tipo de revisión con IA

const Color _verde = Color(0xFF1E7B34);
const Color _ambar = Color(0xFFB7791F);

Future<Map<String, dynamic>> _getJ(Map<String, String> q, {int seg = 120}) async {
  final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: q)).timeout(Duration(seconds: seg));
  return jsonDecode(r.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _postJ(Map<String, dynamic> body, {int seg = 170}) async {
  final r = await http
      .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
      .timeout(Duration(seconds: seg));
  return jsonDecode(r.body) as Map<String, dynamic>;
}

// ═════════════════════════════════════════════════════ LISTA DE TAREAS
class RevisionPorTareaScreen extends StatefulWidget {
  const RevisionPorTareaScreen({super.key});
  @override
  State<RevisionPorTareaScreen> createState() => _RevisionPorTareaScreenState();
}

class _RevisionPorTareaScreenState extends State<RevisionPorTareaScreen> {
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _tareas = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final d = await _getJ({'accion': 'revision_tareas'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudieron leer tus tareas.');
      if (!mounted) return;
      setState(() {
        _tareas = ((d['tareas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Revisar por tarea', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(tooltip: 'Recargar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _cargando
          ? const CessumSkeletonList(count: 4)
          : _error.isNotEmpty
              ? CessumEmptyState(icon: Icons.cloud_off_rounded, title: 'No se pudieron leer tus tareas', subtitle: _error)
              : _tareas.isEmpty
                  ? const CessumEmptyState(icon: Icons.task_alt_rounded, title: 'No tienes tareas por revisar', subtitle: 'Cuando tus alumnos entreguen, aparecerán aquí.')
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 30), children: [
                        Text('Revisa una tarea completa: pre-llena con IA todas las retroalimentaciones, ajústalas y envíalas de un jalón.',
                            style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.4)),
                        const SizedBox(height: 10),
                        for (final t in _tareas) _tarjeta(t),
                      ]),
                    ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> t) {
    final total = (t['total'] as num?)?.toInt() ?? 0;
    final rev = (t['revisadas'] as num?)?.toInt() ?? 0;
    final pend = (t['pendientes'] as num?)?.toInt() ?? 0;
    final bor = (t['borradores'] as num?)?.toInt() ?? 0;
    final pct = total == 0 ? 0.0 : rev / total;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => RevisionTareaLoteScreen(tarea: '${t['tarea']}', nombre: '${t['nombre']}')));
          _cargar();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${t['nombre']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cessumInk(context))),
              ),
              if (pend > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                  child: Text('$pend por revisar', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: cessumRed)),
                )
              else
                const Icon(Icons.check_circle, color: _verde),
            ]),
            Text('${t['materia']}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: pct, minHeight: 8, color: _verde, backgroundColor: cessumRed.withValues(alpha: 0.12)),
            ),
            const SizedBox(height: 6),
            Text('Revisadas $rev de $total (${(pct * 100).round()} %) · pendientes $pend'
                '${bor > 0 ? ' · $bor borrador${bor == 1 ? '' : 'es'} listo${bor == 1 ? '' : 's'}' : ''}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════ UNA TAREA, EN LOTE
class _Fila {
  final Map<String, dynamic> e;
  final TextEditingController retro = TextEditingController();
  final TextEditingController cal = TextEditingController();
  Map<String, int> niveles = {};
  String estado = '';   // '' | borrador | enviado | error
  String error = '';
  bool sucio = false;
  bool trabajando = false;
  List<String> fortalezas = [], faltantes = [];
  String estiloEtiqueta = '';   // (6-oct-2026) con qué tipo de revisión se generó el borrador
  List<String> archivos = [];   // (6-oct-2026) relación de archivos que recibió la IA (nombre — cómo se leyó)
  _Fila(this.e) {
    final b = e['borrador'] is Map ? Map<String, dynamic>.from(e['borrador'] as Map) : null;
    if (b != null) aplicar(b);
  }
  String get llave => '${e['llave']}';
  String get alumno => '${e['alumno']}';
  bool get revisadaAntes => '${e['estado']}' == 'Revisada' && estado != 'borrador';
  void aplicar(Map<String, dynamic> b) {
    estado = '${b['estado'] ?? 'borrador'}';
    retro.text = '${b['retro'] ?? ''}';
    cal.text = b['calificacion'] == null ? '' : '${b['calificacion']}';
    niveles = {};
    final n = b['niveles'];
    if (n is Map) n.forEach((k, v) { final x = int.tryParse('$v'); if (x != null) niveles['$k'] = x; });
    error = '${b['error'] ?? ''}';
    fortalezas = ((b['fortalezas'] as List?) ?? []).map((x) => '$x').toList();
    faltantes = ((b['faltantes'] as List?) ?? []).map((x) => '$x').toList();
    estiloEtiqueta = EstiloRevisionIa.etiquetaDeJson(b['estilo']);
    archivos = ((b['archivos'] as List?) ?? []).map((x) => '$x').toList();
    sucio = false;
  }
}

class RevisionTareaLoteScreen extends StatefulWidget {
  final String tarea;
  final String nombre;
  const RevisionTareaLoteScreen({super.key, required this.tarea, this.nombre = ''});
  @override
  State<RevisionTareaLoteScreen> createState() => _RevisionTareaLoteScreenState();
}

class _RevisionTareaLoteScreenState extends State<RevisionTareaLoteScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  List<_Fila> _filas = [];
  List<Map<String, dynamic>> _rubrica = [];
  bool _editarTodas = false;
  String _filtro = 'todas';
  bool _lote = false;          // pre-llenando o enviando
  String _loteNota = '';
  int _loteHechas = 0, _loteTotal = 0;
  bool _verFaltan = false;
  EstiloRevisionIa _estilo = EstiloRevisionIa.actual.copia();   // (6-oct-2026) tipo de revisión elegido

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.retro.dispose();
      f.cal.dispose();
    }
    super.dispose();
  }

  double get _max => ((_d['calificacionMaxima'] as num?) ?? 10).toDouble();
  bool get _conRubrica => _rubrica.isNotEmpty;

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final d = await _getJ({'accion': 'revision_tarea', 'tarea': widget.tarea}, seg: 150);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo abrir la tarea.');
      if (!mounted) return;
      for (final f in _filas) { f.retro.dispose(); f.cal.dispose(); }
      setState(() {
        _d = d;
        _rubrica = ((d['rubrica'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _filas = ((d['entregas'] as List?) ?? []).map((e) => _Fila(Map<String, dynamic>.from(e as Map))).toList();
        _cargando = false;
      });
      // Precarga las primeras entregas: al abrirlas ya están listas.
      for (final f in _filas.where((x) => x.estado != 'enviado').take(3)) {
        EntregaVisorScreen.precargar(f.llave);
      }
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  // ─────────────── Rúbrica: la calificación como la calcula Moodle
  double? _calRubrica(Map<String, int> niv) {
    if (_rubrica.isEmpty || niv.length < _rubrica.length) return null;
    double suma = 0, minS = 0, maxS = 0;
    for (final c in _rubrica) {
      final ns = ((c['niveles'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
      if (ns.isEmpty) continue;
      final pts = ns.map((n) => ((n['puntos'] as num?) ?? 0).toDouble()).toList();
      minS += pts.reduce(math.min);
      maxS += pts.reduce(math.max);
      final el = ns.where((n) => (n['id'] as num?)?.toInt() == niv['${c['id']}']).toList();
      if (el.isEmpty) return null;
      suma += ((el.first['puntos'] as num?) ?? 0).toDouble();
    }
    if (maxS <= minS) return null;
    return ((suma - minS) / (maxS - minS) * _max * 100).roundToDouble() / 100;
  }

  double? _calDe(_Fila f) => _conRubrica ? _calRubrica(f.niveles) : double.tryParse(f.cal.text.trim().replaceAll(',', '.'));

  String? _problema(_Fila f) {
    if (f.retro.text.trim().isEmpty) return 'Falta la retroalimentación.';
    final c = _calDe(f);
    if (_conRubrica && c == null) return 'Falta elegir un nivel en cada criterio de la rúbrica.';
    if (c == null || c < 0 || c > _max) return 'La calificación debe estar entre 0 y ${_fmt(_max)}.';
    return null;
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  List<_Fila> get _listas => _filas.where((f) => f.estado == 'borrador' && _problema(f) == null).toList();
  List<_Fila> get _sinBorrador => _filas.where((f) => f.estado.isEmpty || f.estado == 'error').where((f) => !f.revisadaAntes).toList();

  // ─────────────── Pre-llenar con IA, 3 a la vez. NO envía nada.
  Future<void> _prellenar({List<_Fila>? solo, EstiloRevisionIa? estilo}) async {
    final est = estilo ?? _estilo;
    final cola = List<_Fila>.from(solo ?? _sinBorrador);
    if (cola.isEmpty) return;
    setState(() { _lote = true; _loteHechas = 0; _loteTotal = cola.length; _loteNota = 'Pre-llenando con IA (${est.etiqueta})…'; });
    Future<void> trabajador() async {
      while (cola.isNotEmpty && mounted) {
        final f = cola.removeAt(0);
        setState(() => f.trabajando = true);
        try {
          final d = await _postJ({'accion': 'revision_borrador', 'llave': f.llave, 'estilo': est.toJson()});
          if (!mounted) return;
          setState(() {
            if (d['ok'] == true) {
              f.aplicar(Map<String, dynamic>.from(d['borrador'] as Map));
            } else {
              f.estado = 'error';
              f.error = '${d['error'] ?? 'No se pudo generar.'}';
            }
          });
        } catch (_) {
          if (mounted) setState(() { f.estado = 'error'; f.error = 'Se cortó la conexión. Vuelve a generar esta.'; });
        }
        if (!mounted) return;
        setState(() { f.trabajando = false; _loteHechas++; });
      }
    }
    await Future.wait([trabajador(), trabajador(), trabajador()]);
    if (!mounted) return;
    setState(() => _lote = false);
    // (5-oct-2026) Si la IA dedujo los criterios de la instrucción en esta corrida, se muestran.
    if (!_conRubrica && '${_d['criteriosAuto'] ?? ''}'.isEmpty && _filas.isNotEmpty) {
      try {
        final c = await _getJ({'accion': 'entrega_criterios', 'llave': _filas.first.llave}, seg: 60);
        if (c['ok'] == true && mounted) setState(() => _d['criteriosAuto'] = c['criteriosAuto'] ?? '');
      } catch (_) {}
    }
    final errores = _filas.where((f) => f.estado == 'error').length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: errores == 0 ? _verde : _ambar,
        content: Text(errores == 0
            ? 'Borradores listos con tipo «${est.etiqueta}». Nada se ha enviado: revísalos y envíalos cuando quieras.'
            : 'Borradores listos, $errores con problema (ver cada fila). Nada se ha enviado.')));
  }

  // ─────────────── Guardar lo editado (sin enviar)
  Future<int> _guardarCambios({bool avisar = true}) async {
    final sucias = _filas.where((f) => f.sucio && f.estado != 'enviado').toList();
    var ok = 0;
    for (final f in sucias) {
      try {
        final d = await _postJ({
          'accion': 'revision_borrador_editar', 'llave': f.llave,
          'calificacion': _conRubrica ? _calRubrica(f.niveles) : double.tryParse(f.cal.text.trim().replaceAll(',', '.')),
          'retro': f.retro.text.trim(), 'niveles': f.niveles,
        }, seg: 60);
        if (d['ok'] == true) {
          ok++;
          f.sucio = false;
          if (f.estado.isEmpty) f.estado = 'borrador';
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {});
      if (avisar && sucias.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: ok == sucias.length ? _verde : _ambar,
            content: Text(ok == sucias.length ? 'Cambios guardados ($ok).' : 'Se guardaron $ok de ${sucias.length}. Intenta de nuevo.')));
      }
    }
    return ok;
  }

  // ─────────────── Enviar todas de un jalón
  Future<void> _enviarTodas() async {
    final listas = _listas;
    final conProblema = _filas.where((f) => f.estado == 'borrador' && _problema(f) != null).length;
    if (listas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: cessumRed, content: Text('No hay retroalimentaciones listas para enviar.')));
      return;
    }
    var avisar = _d['avisaAlAlumno'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Enviar todas al aula'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Se escribirá en Moodle la calificación y la retroalimentación de ${listas.length} entrega${listas.length == 1 ? '' : 's'} '
                'de «${_d['nombre'] ?? widget.nombre}».'
                '${conProblema > 0 ? '\n\n$conProblema con datos incompletos se quedan sin enviar.' : ''}'
                '${_d['flujoDeCalificacion'] == true ? '\n\nLa tarea usa flujo de calificación: se guardan como liberadas.' : ''}',
                style: const TextStyle(height: 1.45)),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: avisar,
              activeColor: cessumRed,
              onChanged: (v) => setD(() => avisar = v),
              title: const Text('Que Moodle les avise a los alumnos', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: Text(avisar
                  ? 'Cada alumno recibirá la notificación de Moodle de que su tarea fue calificada.'
                  : 'Moodle no les avisará; verán la calificación al entrar al aula.',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true),
                child: Text('Enviar ${listas.length}')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() { _lote = true; _loteHechas = 0; _loteTotal = listas.length; _loteNota = 'Enviando al aula…'; });
    var bien = 0;
    for (final f in listas) {
      if (!mounted) return;
      setState(() => f.trabajando = true);
      try {
        final d = await _postJ({
          'accion': 'revision_enviar', 'llave': f.llave,
          'calificacion': _conRubrica ? null : _calDe(f),
          'retro': f.retro.text.trim(), 'niveles': f.niveles, 'notificar': avisar,
        });
        if (!mounted) return;
        setState(() {
          if (d['ok'] == true) {
            f.estado = 'enviado'; f.error = ''; f.sucio = false; bien++;
            if (d['calificacion'] != null) f.cal.text = '${d['calificacion']}';
          } else {
            f.error = '${d['error'] ?? 'No se pudo enviar.'}';
          }
        });
      } catch (_) {
        if (mounted) setState(() => f.error = 'Se cortó la conexión; revisa en el aula si quedó antes de reenviar.');
      }
      if (!mounted) return;
      setState(() { f.trabajando = false; _loteHechas++; });
    }
    if (!mounted) return;
    setState(() => _lote = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: bien == listas.length ? _verde : _ambar,
        content: Text(bien == listas.length ? 'Listo: $bien enviadas al aula.' : '$bien de ${listas.length} enviadas. Las demás muestran su motivo.')));
  }

  // ─────────────── (6-oct-2026) Generar UNA entrega con el tipo actual, con otro tipo o personalizando
  Future<void> _generarFila(_Fila f, String v) async {
    var est = _estilo;
    if (v == 'justo' || v == 'duro' || v == 'calmado') {
      est = EstiloRevisionIa.preset(v);
    } else if (v == 'personalizar') {
      final r = await mostrarEstiloRevisionIa(context, _estilo);
      if (r == null || !mounted) return;
      est = r;
      setState(() { _estilo = r; EstiloRevisionIa.actual = r; });
    }
    await _prellenar(solo: [f], estilo: est);
  }

  // ─────────────── Ver la entrega en ventana emergente
  Future<void> _verEntrega(_Fila f) async {
    final i = _filas.indexOf(f);
    if (i >= 0 && i + 1 < _filas.length) EntregaVisorScreen.precargar(_filas[i + 1].llave);
    final tam = MediaQuery.of(context).size;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          width: math.min(1200.0, tam.width - 32),
          height: tam.height * 0.92,
          child: Stack(children: [
            EntregaVisorScreen(llave: f.llave, alumno: f.alumno, tarea: '${_d['nombre'] ?? widget.nombre}', enlaceAula: '${f.e['link'] ?? ''}', compacto: true),
            Positioned(
              right: 6,
              bottom: 6,
              child: FloatingActionButton.small(
                heroTag: null,
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(ctx),
                child: const Icon(Icons.close),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _rubricaDe(_Fila f) async {
    final sel = Map<String, int>.from(f.niveles);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Rúbrica · ${f.alumno}'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final c in _rubrica) ...[
                  Text('${c['criterio']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final n in ((c['niveles'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)))
                      ChoiceChip(
                        selected: sel['${c['id']}'] == (n['id'] as num?)?.toInt(),
                        selectedColor: cessumRed.withValues(alpha: 0.15),
                        onSelected: (_) => setD(() => sel['${c['id']}'] = (n['id'] as num).toInt()),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text('${n['puntos']} · ${n['descripcion']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                ],
                Text(_calRubrica(sel) == null ? 'Elige un nivel en cada criterio.' : 'Calificación: ${_fmt(_calRubrica(sel)!)} de ${_fmt(_max)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) setState(() { f.niveles = sel; f.sucio = true; if (f.estado.isEmpty) f.estado = 'borrador'; });
  }

  Future<void> _editarCriterios() async {
    if (_filas.isEmpty) return;
    final cambio = await editarCriteriosRevision(context, _filas.first.llave, tarea: '${_d['nombre'] ?? widget.nombre}');
    if (cambio) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final sucias = _filas.where((f) => f.sucio && f.estado != 'enviado').length;
    return PopScope(
      canPop: sucias == 0 && !_lote,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _lote) return;
        final salir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cambios sin guardar'),
            content: Text('Editaste $sucias retroalimentación${sucias == 1 ? '' : 'es'} y no las has guardado.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir aquí')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar y salir')),
            ],
          ),
        );
        if (salir == true) {
          await _guardarCambios(avisar: false);
          if (mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Revisión de la tarea', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text('${_d['nombre'] ?? widget.nombre}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
          actions: [IconButton(tooltip: 'Recargar', onPressed: (_cargando || _lote) ? null : _cargar, icon: const Icon(Icons.refresh_rounded))],
        ),
        bottomNavigationBar: (_cargando || _error.isNotEmpty) ? null : _barraInferior(sucias),
        body: _cargando
            ? const CessumSkeletonList(count: 4)
            : _error.isNotEmpty
                ? CessumEmptyState(icon: Icons.cloud_off_rounded, title: 'No se pudo abrir la tarea', subtitle: _error)
                : ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
                    _resumen(),
                    const SizedBox(height: 10),
                    _criterios(),
                    const SizedBox(height: 10),
                    EstiloRevisionIaSelector(
                      estilo: _estilo,
                      habilitado: !_lote,
                      onCambio: (nuevo) => setState(() { _estilo = nuevo; EstiloRevisionIa.actual = nuevo; }),
                    ),
                    const SizedBox(height: 10),
                    _acciones(),
                    if (_lote) ...[
                      const SizedBox(height: 10),
                      Text('$_loteNota $_loteHechas de $_loteTotal', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: _loteTotal == 0 ? null : _loteHechas / _loteTotal, color: cessumRed),
                    ],
                    const SizedBox(height: 10),
                    _filtros(),
                    const SizedBox(height: 6),
                    for (final f in _filtradas()) _fila(f),
                  ]),
      ),
    );
  }

  List<_Fila> _filtradas() {
    switch (_filtro) {
      case 'pendientes':
        return _filas.where((f) => f.estado != 'enviado' && !f.revisadaAntes).toList();
      case 'borrador':
        return _filas.where((f) => f.estado == 'borrador').toList();
      case 'enviadas':
        return _filas.where((f) => f.estado == 'enviado' || f.revisadaAntes).toList();
      default:
        return _filas;
    }
  }

  Widget _cifra(String n, String t, Color c) => Expanded(
        child: Column(children: [
          Text(n, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
          Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ]),
      );

  Widget _resumen() {
    final aula = Map<String, dynamic>.from((_d['aula'] as Map?) ?? {});
    final alumnos = (aula['alumnos'] as num?)?.toInt() ?? 0;
    final entregaron = (aula['entregadas'] as num?)?.toInt() ?? _filas.length;
    final faltan = ((aula['faltan'] as List?) ?? []).map((x) => '$x').toList();
    final enviadas = _filas.where((f) => f.estado == 'enviado' || f.revisadaAntes).length;
    final borr = _filas.where((f) => f.estado == 'borrador').length;
    final pctEnt = alumnos == 0 ? null : (entregaron * 100 / alumnos).round();
    final pctRev = _filas.isEmpty ? 0 : (enviadas * 100 / _filas.length).round();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_d['materia'] ?? ''}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          const SizedBox(height: 8),
          Row(children: [
            _cifra(pctEnt == null ? '$entregaron' : '$pctEnt %', alumnos == 0 ? 'entregaron' : 'entregaron ($entregaron de $alumnos)', _verde),
            _cifra('${faltan.length}', 'no han entregado', faltan.isEmpty ? _verde : cessumRed),
            _cifra('$pctRev %', 'revisadas ($enviadas de ${_filas.length})', cessumInk(context)),
            _cifra('$borr', 'borradores listos', cessumGold),
          ]),
          if (faltan.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _verFaltan = !_verFaltan),
              child: Row(children: [
                Icon(_verFaltan ? Icons.expand_less : Icons.expand_more, size: 18, color: cessumRed),
                Text(_verFaltan ? 'Ocultar quiénes faltan' : 'Ver quiénes no han entregado',
                    style: const TextStyle(fontSize: 12.5, color: cessumRed, fontWeight: FontWeight.w700)),
              ]),
            ),
            if (_verFaltan) Text(faltan.join(' · '), style: const TextStyle(fontSize: 12.5, height: 1.45)),
          ],
        ]),
      ),
    );
  }

  /// (5-oct-2026) La IA lee la tarea sola: la rúbrica de Moodle si la hay; si no, criterios deducidos de la instrucción.
  String _textoAuto() {
    if (_conRubrica) return 'La tarea tiene rúbrica en Moodle (${_rubrica.length} criterio${_rubrica.length == 1 ? '' : 's'}): la IA la usa sola. Tus indicaciones son opcionales.';
    final auto = '${_d['criteriosAuto'] ?? ''}'.replaceAll(RegExp(r'RÚBRICA DEDUCIDA DE LA INSTRUCCIÓN\s*'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (auto.isNotEmpty) return 'Sin rúbrica en Moodle: la IA dedujo los criterios de la instrucción y los usa para toda la tarea: ${auto.length > 110 ? '${auto.substring(0, 110)}…' : auto}';
    return 'Sin rúbrica en Moodle: al pre-llenar, la IA leerá la instrucción y deducirá los criterios una sola vez para toda la tarea.';
  }

  Widget _criterios() {
    final txt = '${_d['criterios'] ?? ''}'.trim();
    final resumen = txt.replaceAll(RegExp(r'\s+'), ' ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: txt.isEmpty ? Theme.of(context).cardColor : cessumGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.rule_folder_outlined, color: txt.isEmpty ? cessumMuted(context) : cessumGold),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            txt.isNotEmpty ? 'Tus criterios de revisión: ${resumen.length > 110 ? '${resumen.substring(0, 110)}…' : resumen}' : _textoAuto(),
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ),
        TextButton(
            onPressed: _lote ? null : _editarCriterios,
            child: Text(txt.isNotEmpty ? 'Editar' : ('${_d['criteriosAuto'] ?? ''}'.isNotEmpty ? 'Ver o ajustar' : 'Indicaciones (opcional)'))),
      ]),
    );
  }

  Widget _acciones() {
    final sin = _sinBorrador.length;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: cessumGold),
        onPressed: (_lote || sin == 0) ? null : () => _prellenar(),
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: Text(sin == 0 ? 'Todas tienen borrador' : 'Pre-llenar con IA ($sin)'),
      ),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
        onPressed: () => setState(() => _editarTodas = !_editarTodas),
        icon: Icon(_editarTodas ? Icons.unfold_less : Icons.edit_note, size: 18),
        label: Text(_editarTodas ? 'Vista compacta' : 'Editar todas'),
      ),
    ]);
  }

  Widget _filtros() {
    final n = {
      'todas': _filas.length,
      'pendientes': _filas.where((f) => f.estado != 'enviado' && !f.revisadaAntes).length,
      'borrador': _filas.where((f) => f.estado == 'borrador').length,
      'enviadas': _filas.where((f) => f.estado == 'enviado' || f.revisadaAntes).length,
    };
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final x in [('todas', 'Todas'), ('pendientes', 'Por revisar'), ('borrador', 'Con borrador'), ('enviadas', 'Enviadas')])
        ChoiceChip(
          label: Text('${x.$2} · ${n[x.$1]}'),
          selected: _filtro == x.$1,
          selectedColor: cessumRed.withValues(alpha: 0.15),
          onSelected: (_) => setState(() => _filtro = x.$1),
        ),
    ]);
  }

  Widget _chipEstado(_Fila f) {
    String t;
    Color c;
    if (f.trabajando) {
      t = 'Trabajando…'; c = cessumGold;
    } else if (f.estado == 'enviado' || f.revisadaAntes) {
      t = 'Enviada'; c = _verde;
    } else if (f.estado == 'borrador') {
      final p = _problema(f);
      t = p == null ? (f.sucio ? 'Editada, sin guardar' : 'Borrador listo') : 'Incompleta';
      c = p == null ? cessumGold : _ambar;
    } else if (f.estado == 'error') {
      t = 'Con problema'; c = cessumRed;
    } else {
      t = 'Sin borrador'; c = cessumMuted(context);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
    );
  }

  Widget _fila(_Fila f) {
    final enviada = f.estado == 'enviado' || f.revisadaAntes;
    final tieneBorrador = f.estado == 'borrador' || enviada;
    final calR = _conRubrica ? _calRubrica(f.niveles) : null;
    final problema = f.estado == 'borrador' ? _problema(f) : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.alumno, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cessumInk(context))),
                Text('Entregó: ${f.e['entregada'] ?? ''}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                if (f.estiloEtiqueta.isNotEmpty)
                  Text('Revisión: ${f.estiloEtiqueta}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                if (f.archivos.isNotEmpty)
                  Text('Archivos que recibió la IA (${f.archivos.length}): ${f.archivos.join(' · ')}',
                      style: TextStyle(fontSize: 11.5, height: 1.35, color: f.archivos.any((x) => x.contains('NO LEÍDO')) ? _ambar : cessumMuted(context))),
              ]),
            ),
            _chipEstado(f),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Ver entrega',
              onPressed: () => _verEntrega(f),
              icon: const Icon(Icons.picture_as_pdf_outlined, color: cessumRed),
            ),
            if (!enviada)
              PopupMenuButton<String>(
                tooltip: tieneBorrador ? 'Volver a generar con IA' : 'Generar con IA',
                enabled: !(_lote || f.trabajando),
                onSelected: (v) => _generarFila(f, v),
                icon: f.trabajando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(tieneBorrador ? Icons.refresh : Icons.auto_awesome, color: cessumGold),
                itemBuilder: (ctx) => [
                  PopupMenuItem<String>(value: 'actual', child: Text('Con el tipo actual · ${_estilo.etiqueta}')),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(value: 'justo', child: Text('Esta vez como Justo')),
                  const PopupMenuItem<String>(value: 'duro', child: Text('Esta vez como Duro')),
                  const PopupMenuItem<String>(value: 'calmado', child: Text('Esta vez como Calmado')),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(value: 'personalizar', child: Text('Personalizar y generar…')),
                ],
              ),
          ]),
          if (f.error.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(f.error, style: const TextStyle(fontSize: 12, color: cessumRed))),
          if (tieneBorrador) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (_conRubrica) ...[
                Text(calR == null ? 'Calificación: —' : 'Calificación: ${_fmt(calR)} / ${_fmt(_max)}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: cessumRed)),
                const SizedBox(width: 8),
                if (!enviada)
                  TextButton.icon(onPressed: () => _rubricaDe(f), icon: const Icon(Icons.rule, size: 16), label: const Text('Rúbrica')),
              ] else
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: f.cal,
                    enabled: !enviada,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() => f.sucio = true),
                    decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: 'Calificación / ${_fmt(_max)}'),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            if (_editarTodas && !enviada)
              TextField(
                controller: f.retro,
                minLines: 4,
                maxLines: 10,
                onChanged: (_) => setState(() => f.sucio = true),
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Retroalimentación'),
              )
            else
              InkWell(
                onTap: enviada ? null : () => setState(() => _editarTodas = true),
                child: Text(f.retro.text.isEmpty ? '(sin retroalimentación)' : f.retro.text,
                    maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, height: 1.45)),
              ),
            if (problema != null)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(problema, style: const TextStyle(fontSize: 12, color: _ambar, fontWeight: FontWeight.w600))),
          ],
        ]),
      ),
    );
  }

  Widget _barraInferior(int sucias) {
    final listas = _listas.length;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, -3))],
        ),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed, padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: (_lote || sucias == 0) ? null : () => _guardarCambios(),
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(sucias == 0 ? 'Sin cambios' : 'Guardar cambios ($sucias)'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed, padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: (_lote || listas == 0) ? null : _enviarTodas,
              icon: const Icon(Icons.send, size: 18),
              label: Text(listas == 0 ? 'Nada listo para enviar' : 'Enviar todas ($listas)'),
            ),
          ),
        ]),
      ),
    );
  }
}
