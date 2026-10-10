// AGENDA DE PROFESORES · HERRAMIENTAS (23-sep-2026)
//
//   AgendaAlertasScreen      · grupos que se quedarán sin clase e invitaciones
//                              sin respuesta, con reemplazo libre y reasignación
//   AgendaPlanPeriodoScreen  · todas las materias pendientes de un grupo en una
//                              tabla: fechas encadenadas, profesor libre, revisar
//                              con el Guardián y guardar todas juntas
//   AgendaCargaDocenteScreen · materias y horas por profesor, sobrecarga,
//                              choques y profesores con experiencia sin asignar
//
//   GET  agenda_alertas · agenda_plan_periodo · maestros_disponibles
//   POST asignacion_reasignar · asignacion_guardar (con y sin soloValidar)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';

const Color _kVerde = Color(0xFF1E7F52);
const Color _kAmbar = Color(0xFFB7791F);
const Color _kMorado = Color(0xFF6A1B9A);

Future<Map<String, dynamic>> _agGet(Map<String, String> qp, {int segundos = 90}) async {
  final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: qp)).timeout(Duration(seconds: segundos));
  return jsonDecode(r.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _agPost(Map<String, dynamic> body, {int segundos = 75}) async {
  final r = await http
      .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
      .timeout(Duration(seconds: segundos));
  return jsonDecode(r.body) as Map<String, dynamic>;
}

DateTime? _agFecha(String s) {
  final t = s.trim().replaceAll(RegExp(r'[\u2010\u2011\u2012\u2013\u2014]'), '-');
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

String _agIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _agMeses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
String _agCorta(String iso) {
  final d = _agFecha(iso);
  return d == null ? iso : '${d.day} ${_agMeses[d.month - 1]} ${d.year}';
}

DateTime _agLunesDesde(DateTime d) {
  var x = DateTime(d.year, d.month, d.day);
  while (x.weekday != DateTime.monday) {
    x = x.add(const Duration(days: 1));
  }
  return x;
}

Widget _agCaja(BuildContext context, Widget hijo, {Color? borde}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (borde ?? cessumGold).withValues(alpha: 0.4)),
      ),
      child: hijo,
    );

Widget _agTitulo(BuildContext context, String t, [String? sub]) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        if (sub != null) Text(sub, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      ]),
    );

/* ==========================================================================
   1 y 3 · ALERTAS
   ========================================================================== */
class AgendaAlertasScreen extends StatefulWidget {
  /// Abre el formulario de la agenda (con su propuesta automática) para el grupo.
  final Future<void> Function(String programa, String generacion, String grupo) onProgramar;
  const AgendaAlertasScreen({super.key, required this.onProgramar});

  @override
  State<AgendaAlertasScreen> createState() => _AgendaAlertasScreenState();
}

class _AgendaAlertasScreenState extends State<AgendaAlertasScreen> {
  Map<String, dynamic>? _d;
  bool _cargando = true;
  String _error = '';
  final Set<int> _reasignando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final d = await _agGet({'accion': 'agenda_alertas'}, segundos: 180);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo consultar.');
      if (!mounted) return;
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  void _msg(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? cessumRed : _kVerde));
  }

  Future<void> _reasignar(Map<String, dynamic> inv) async {
    final rem = Map<String, dynamic>.from(inv['reemplazo'] as Map);
    final fila = (inv['fila'] as num).toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reasignar la invitación', style: TextStyle(fontSize: 16)),
        content: Text(
            '«${inv['materia']}» (${inv['programa']} ${inv['generacion']} ${inv['grupo']}) pasa de ${inv['docente']}, '
            'que no respondió en ${inv['diasSinRespuesta']} días, a ${rem['nombre']}.\n\n'
            'Se ENVIARÁ UN CORREO de invitación a ${rem['nombre']} (${rem['correo']}). '
            'El enlace que recibió ${inv['docente']} deja de funcionar. A nadie más le llega nada.',
            style: const TextStyle(fontSize: 13.5, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reasignar e invitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _reasignando.add(fila));
    try {
      final r = await _agPost({
        'accion': 'asignacion_reasignar',
        'fila': fila,
        'nombre': '${rem['nombre'] ?? ''}',
        'correo': '${rem['correo'] ?? ''}',
        'motivo': 'Sin respuesta en ${inv['diasSinRespuesta']} días',
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo reasignar.');
      _msg(r['enviado'] == true
          ? 'Reasignada: la invitación ya le llegó a ${rem['nombre']}.'
          : 'Reasignada, pero la invitación no se pudo enviar: reenvíela desde «Sin respuesta».');
      await _cargar();
    } catch (e) {
      _msg('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _reasignando.remove(fila));
  }

  @override
  Widget build(BuildContext context) {
    final sinClase = ((_d?['sinClase'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final sinResp = ((_d?['sinRespuesta'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Alertas de la agenda', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, textAlign: TextAlign.center)))
              : ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 40), children: [
                  _agTitulo(context, 'Grupos que se quedarán sin clase',
                      'Su última materia termina en ${_d?['diasAlerta'] ?? 21} días o menos, no hay otra programada y aún les quedan materias del plan'),
                  if (sinClase.isEmpty)
                    _agCaja(context, const Text('Ningún grupo en riesgo: todos tienen su siguiente materia programada.'))
                  else
                    ...sinClase.map((g) {
                      final dias = (g['diasRestantes'] as num?)?.toInt() ?? 0;
                      final urgente = dias <= 7;
                      return _agCaja(
                          context,
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(urgente ? Icons.priority_high : Icons.schedule, color: urgente ? cessumRed : _kAmbar, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${g['programa']} · ${g['generacion']} · ${g['grupo']}',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Text(
                                dias >= 0
                                    ? 'Su materia «${g['ultimaMateria']}» termina el ${_agCorta('${g['termina']}')}: faltan $dias día(s).'
                                    : 'Su materia «${g['ultimaMateria']}» terminó hace ${-dias} día(s) y el grupo no tiene la siguiente.',
                                style: const TextStyle(fontSize: 13)),
                            Text(
                                '${g['alumnos']} alumno(s) activos${g['pendientesPlan'] != null ? ' · ${g['pendientesPlan']} materia(s) pendiente(s) del plan' : ''}',
                                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                                onPressed: () async {
                                  await widget.onProgramar('${g['programa']}', '${g['generacion']}', '${g['grupo']}');
                                  _cargar();
                                },
                                icon: const Icon(Icons.auto_awesome, size: 18),
                                label: const Text('Programar la siguiente'),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                                onPressed: () async {
                                  final cambio = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => AgendaPlanPeriodoScreen(
                                              programa: '${g['programa']}', generacion: '${g['generacion']}', grupo: '${g['grupo']}')));
                                  if (cambio == true) _cargar();
                                },
                                icon: const Icon(Icons.view_timeline_outlined, size: 18),
                                label: const Text('Planear el periodo completo'),
                              ),
                            ]),
                          ]),
                          borde: urgente ? cessumRed : _kAmbar);
                    }),
                  _agTitulo(context, 'Invitaciones sin respuesta',
                      'Llevan ${_d?['diasSinRespuesta'] ?? 4} días o más sin que el profesor acepte ni rechace'),
                  if (sinResp.isEmpty)
                    _agCaja(context, const Text('Ninguna invitación atrasada.'))
                  else
                    ...sinResp.map((inv) {
                      final fila = (inv['fila'] as num?)?.toInt() ?? 0;
                      final rem = inv['reemplazo'] == null ? null : Map<String, dynamic>.from(inv['reemplazo'] as Map);
                      final verif = inv['disponibilidadVerificada'] == true;
                      return _agCaja(
                          context,
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${inv['docente']} · ${inv['diasSinRespuesta']} días sin responder',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                            Text('«${inv['materia']}» · ${inv['programa']} ${inv['generacion']} ${inv['grupo']}',
                                style: const TextStyle(fontSize: 13)),
                            Text(
                                'Invitación enviada el ${_agCorta('${inv['enviada']}')}'
                                '${'${inv['dia'] ?? ''}'.isNotEmpty ? ' · ${inv['dia']} ${inv['hora']}' : ''}'
                                '${'${inv['inicio'] ?? ''}'.isNotEmpty ? ' · inicia el ${_agCorta('${inv['inicio']}')}' : ''}',
                                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                            const SizedBox(height: 8),
                            if (inv['bloque'] == true)
                              const Text('Es una invitación de bloque o de grupos juntos: reasígnela desde la agenda.',
                                  style: TextStyle(fontSize: 12.5))
                            else if (rem == null)
                              const Text('No hay otro profesor que la haya impartido o tenga perfil afín y esté libre: elíjalo desde la agenda.',
                                  style: TextStyle(fontSize: 12.5))
                            else ...[
                              Text('Reemplazo sugerido: ${rem['nombre']} — ${rem['motivo']}'
                                  '${verif ? '; está libre ese día y hora.' : '. ⚠ No se pudo revisar su disponibilidad.'}',
                                  style: const TextStyle(fontSize: 12.5, color: _kMorado, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              _reasignando.contains(fila)
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed))
                                  : FilledButton.icon(
                                      style: FilledButton.styleFrom(backgroundColor: cessumRed),
                                      onPressed: () => _reasignar(inv),
                                      icon: const Icon(Icons.swap_horiz, size: 18),
                                      label: Text('Reasignar a ${rem['nombre']}'),
                                    ),
                            ],
                          ]),
                          borde: _kAmbar);
                    }),
                ]),
    );
  }
}

/* ==========================================================================
   2 · PLANEAR EL PERIODO COMPLETO DE UN GRUPO
   ========================================================================== */
class AgendaPlanPeriodoScreen extends StatefulWidget {
  final String programa;
  final String generacion;
  final String grupo;
  const AgendaPlanPeriodoScreen({super.key, required this.programa, required this.generacion, required this.grupo});

  @override
  State<AgendaPlanPeriodoScreen> createState() => _AgendaPlanPeriodoScreenState();
}

class _FilaPlan {
  final Map<String, dynamic> materia;
  bool incluir = true;
  Map<String, dynamic>? docente;
  String inicio = '';
  String termino = '';
  String dispNota = '';     // libre / ocupado / sin verificar
  bool dispVerificada = false;
  String revision = '';     // resultado de «Revisar con el Guardián»
  bool? revisionOk;
  String resultado = '';    // resultado al guardar
  bool? guardada;
  _FilaPlan(this.materia);
  List<Map<String, dynamic>> get sugeridos =>
      ((materia['docentesSugeridos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

class _AgendaPlanPeriodoScreenState extends State<AgendaPlanPeriodoScreen> {
  Map<String, dynamic>? _base;
  bool _cargando = true;
  String _error = '';
  final List<_FilaPlan> _filas = [];
  int _semanas = 5;
  int _receso = 1;
  String? _dia;
  final _cHora = TextEditingController();
  DateTime _inicio = _agLunesDesde(DateTime.now());
  String _razonInicio = '';
  bool _calculando = false;
  bool _trabajando = false;
  bool _huboCambios = false;

  static const _dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cHora.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final d = await _agGet({
        'accion': 'agenda_plan_periodo',
        'programa': widget.programa,
        'generacion': widget.generacion,
        'grupo': widget.grupo,
      }, segundos: 120);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo consultar.');
      _base = d;
      _semanas = (d['semanas'] as num?)?.toInt() ?? 5;
      _receso = (d['receso'] as num?)?.toInt() ?? 1;
      final u = d['ultimo'] == null ? null : Map<String, dynamic>.from(d['ultimo'] as Map);
      if (u != null) {
        final dia = '${u['dia'] ?? ''}';
        if (_dias.contains(dia)) _dia = dia;
        _cHora.text = '${u['hora'] ?? ''}';
        final fin = _agFecha('${u['termina'] ?? ''}');
        if (fin != null) {
          _inicio = _agLunesDesde(fin.add(Duration(days: 1 + _receso * 7)));
          _razonInicio = 'Después de «${u['materia']}», que termina el ${_agCorta('${u['termina']}')}, más el receso.';
        }
      }
      if (_razonInicio.isEmpty) _razonInicio = 'El grupo no tiene materias anteriores: inicia el próximo lunes.';
      _filas
        ..clear()
        ..addAll(((d['materias'] as List?) ?? []).map((e) => _FilaPlan(Map<String, dynamic>.from(e as Map))));
      if (!mounted) return;
      setState(() => _cargando = false);
      await _recalcular();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /// Encadena las fechas y elige, para cada materia, al profesor sugerido que esté libre.
  Future<void> _recalcular() async {
    if (_base?['paralelo'] == true) return;
    setState(() => _calculando = true);
    var ini = _inicio;
    for (final f in _filas.where((f) => f.incluir)) {
      f.inicio = _agIso(ini);
      final fin = ini.add(Duration(days: _semanas * 7 - 1));
      f.termino = _agIso(fin);
      ini = _agLunesDesde(fin.add(Duration(days: 1 + _receso * 7)));
      f.revision = '';
      f.revisionOk = null;
    }
    for (final f in _filas.where((f) => !f.incluir)) {
      f.inicio = '';
      f.termino = '';
    }
    for (final f in _filas.where((f) => f.incluir)) {
      var ocupados = <String, String>{};
      var verificada = false;
      if ((_dia ?? '').isNotEmpty && _cHora.text.trim().isNotEmpty) {
        try {
          final r = await _agGet({
            'accion': 'maestros_disponibles',
            'dia': _dia!,
            'hora': _cHora.text.trim(),
            'inicio': f.inicio,
            'termino': f.termino,
          }, segundos: 45);
          if (r['ok'] == true) {
            verificada = true;
            for (final m in ((r['maestros'] as List?) ?? [])) {
              final mm = Map<String, dynamic>.from(m as Map);
              if (mm['disponible'] != true) ocupados['${mm['correo']}'.toLowerCase()] = '${mm['conflicto'] ?? 'ocupado'}';
            }
          }
        } catch (_) {
          verificada = false;
        }
      }
      f.dispVerificada = verificada;
      Map<String, dynamic>? elegido;
      final saltados = <String>[];
      for (final d in f.sugeridos) {
        final c = '${d['correo'] ?? ''}'.toLowerCase();
        if (verificada && ocupados.containsKey(c)) {
          saltados.add('${d['nombre']}');
          continue;
        }
        elegido = d;
        break;
      }
      f.docente = elegido;
      if (elegido == null) {
        f.dispNota = f.sugeridos.isEmpty
            ? 'Nadie la ha impartido antes: elija al profesor al guardarla desde la agenda.'
            : 'Los sugeridos tienen choque a esa hora (${saltados.join(', ')}).';
      } else if (!verificada) {
        f.dispNota = (_dia ?? '').isEmpty || _cHora.text.trim().isEmpty
            ? 'Falta el día y la hora para revisar si está libre.'
            : '⚠ No se pudo revisar su disponibilidad.';
      } else {
        f.dispNota = 'Libre ese día y hora${saltados.isNotEmpty ? ' · se saltó a ${saltados.join(', ')} por choque' : ''}.';
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _calculando = false);
  }

  Map<String, dynamic> _payload(_FilaPlan f, {bool validar = false}) {
    final u = _base?['ultimo'] == null ? <String, dynamic>{} : Map<String, dynamic>.from(_base!['ultimo'] as Map);
    return {
      'accion': 'asignacion_guardar',
      if (validar) 'soloValidar': true,
      'programa': widget.programa,
      'generacion': widget.generacion,
      'grupo': widget.grupo,
      'periodo': '',
      'tipoSesiones': '${u['tipoSesiones'] ?? ''}',
      'dia': _dia ?? '',
      'hora': _cHora.text.trim(),
      'materia': '${f.materia['materia'] ?? ''}',
      'clave': '${f.materia['clave'] ?? ''}',
      'ciclo': '${u['ciclo'] ?? ''}',
      'docente': '${f.docente?['nombre'] ?? ''}',
      'correo': '${f.docente?['correo'] ?? ''}',
      'directo': false,
      'prospectivo': true, // agenda a futuro: invitación desde ahora, marca [PROGRAMADA A FUTURO]
      'inicio': f.inicio,
      'termino': f.termino,
      'activa': 'SI',
      'notas': 'Programada con el planificador del periodo.',
      'linkLlamada': '',
      'linkAula': '',
    };
  }

  List<_FilaPlan> get _listas => _filas.where((f) => f.incluir && f.docente != null && f.inicio.isNotEmpty).toList();

  Future<void> _revisarTodo() async {
    setState(() => _trabajando = true);
    for (final f in _listas) {
      try {
        final r = await _agPost(_payload(f, validar: true));
        f.revisionOk = r['ok'] == true;
        f.revision = r['ok'] == true
            ? 'Pasa todas las validaciones.'
            : '${r['choqueDocente'] == true ? 'Posible choque del profesor: ' : ''}${r['error'] ?? 'No pasa.'}';
      } catch (_) {
        f.revisionOk = false;
        f.revision = 'No se pudo revisar: sin respuesta del Guardián.';
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _trabajando = false);
  }

  Future<void> _guardarTodo() async {
    final listas = _listas;
    if (listas.isEmpty) return;
    final profes = <String>{for (final f in listas) '${f.docente!['nombre']} (${f.docente!['correo']})'};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Guardar ${listas.length} asignación(es)', style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Text(
              'Se programan a futuro y SE ENVIARÁ UN CORREO DE INVITACIÓN a ${profes.length} profesor(es):\n\n'
              '${profes.map((p) => '• $p').join('\n')}\n\n'
              'Una por materia. A los alumnos no les llega nada. Si alguna choca, no se guarda y se le avisa.',
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar e invitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _trabajando = true);
    for (final f in listas) {
      if (f.guardada == true) continue;
      try {
        final r = await _agPost(_payload(f));
        f.guardada = r['ok'] == true;
        f.resultado = r['ok'] == true
            ? 'Guardada e invitación enviada.'
            : '${r['choqueDocente'] == true ? 'No se guardó por posible choque del profesor: ' : 'No se guardó: '}${r['error'] ?? ''}';
        if (r['ok'] == true) _huboCambios = true;
      } catch (_) {
        f.guardada = false;
        f.resultado = 'No se guardó: sin respuesta del Guardián.';
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _trabajando = false);
  }

  @override
  Widget build(BuildContext context) {
    final paralelo = _base?['paralelo'] == true;
    final listas = _listas.length;
    return PopScope(
      canPop: !_trabajando,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _trabajando ? null : () => Navigator.pop(context, _huboCambios),
          ),
          title: const Text('Planear el periodo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator(color: cessumRed))
            : _error.isNotEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, textAlign: TextAlign.center)))
                : ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 40), children: [
                    Text('${widget.programa} · ${widget.generacion} · ${widget.grupo}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('${_filas.length} materia(s) del plan sin programar, en el orden del plan.',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                    if (paralelo)
                      _agCaja(
                          context,
                          const Text(
                              'En licenciatura las materias del cuatrimestre corren en paralelo, no se encadenan: prográmelas desde la agenda, una por una.'),
                          borde: _kAmbar)
                    else if (_filas.isEmpty)
                      _agCaja(context, const Text('Este grupo ya tiene programadas todas las materias pendientes de su plan.'))
                    else ...[
                      _agCaja(
                          context,
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Cómo se encadena', style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              const Text('Semanas por materia:', style: TextStyle(fontSize: 12.5)),
                              for (final n in const [4, 5, 6, 8])
                                ChoiceChip(
                                  label: Text('$n'),
                                  selected: _semanas == n,
                                  selectedColor: cessumRed.withValues(alpha: 0.15),
                                  onSelected: _trabajando || _calculando
                                      ? null
                                      : (_) {
                                          setState(() => _semanas = n);
                                          _recalcular();
                                        },
                                ),
                            ]),
                            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              const Text('Receso entre materias:', style: TextStyle(fontSize: 12.5)),
                              for (final n in const [0, 1, 2])
                                ChoiceChip(
                                  label: Text(n == 0 ? 'sin receso' : '$n sem.'),
                                  selected: _receso == n,
                                  selectedColor: cessumRed.withValues(alpha: 0.15),
                                  onSelected: _trabajando || _calculando
                                      ? null
                                      : (_) {
                                          setState(() => _receso = n);
                                          _recalcular();
                                        },
                                ),
                            ]),
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _dia,
                                  isExpanded: true,
                                  decoration: const InputDecoration(isDense: true, labelText: 'Día', border: OutlineInputBorder()),
                                  items: [for (final d in _dias) DropdownMenuItem(value: d, child: Text(d))],
                                  onChanged: _trabajando || _calculando
                                      ? null
                                      : (v) {
                                          setState(() => _dia = v);
                                          _recalcular();
                                        },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _cHora,
                                  decoration: const InputDecoration(
                                      isDense: true, labelText: 'Hora (ej. 18:00-20:00)', border: OutlineInputBorder()),
                                  onSubmitted: (_) => _recalcular(),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                child: Text('Primera materia: lunes ${_agCorta(_agIso(_inicio))}. $_razonInicio',
                                    style: const TextStyle(fontSize: 12.5)),
                              ),
                              TextButton(
                                onPressed: _trabajando || _calculando
                                    ? null
                                    : () async {
                                        final hoy = DateTime.now();
                                        final p = await showDatePicker(
                                          context: context,
                                          initialDate: _inicio,
                                          firstDate: DateTime(hoy.year - 1),
                                          lastDate: DateTime(hoy.year + 2),
                                          selectableDayPredicate: (d) => d.weekday == DateTime.monday,
                                          helpText: 'Elija el LUNES de inicio',
                                        );
                                        if (p == null) return;
                                        setState(() {
                                          _inicio = DateTime(p.year, p.month, p.day);
                                          _razonInicio = 'Elegido a mano.';
                                        });
                                        _recalcular();
                                      },
                                child: const Text('Cambiar'),
                              ),
                            ]),
                            if (_calculando)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Row(children: [
                                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed)),
                                  SizedBox(width: 8),
                                  Text('Revisando quién está libre en cada materia…', style: TextStyle(fontSize: 12)),
                                ]),
                              ),
                          ])),
                      ..._filas.asMap().entries.map((e) => _filaUI(e.key, e.value)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: cessumRed, padding: const EdgeInsets.symmetric(vertical: 12)),
                            onPressed: _trabajando || _calculando || listas == 0 ? null : _revisarTodo,
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Revisar todo'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: cessumRed, padding: const EdgeInsets.symmetric(vertical: 12)),
                            onPressed: _trabajando || _calculando || listas == 0 ? null : _guardarTodo,
                            icon: _trabajando
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save),
                            label: Text('Guardar $listas'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                          'Solo se guardan las materias marcadas y con profesor. «Revisar todo» pasa cada una por los candados del Guardián sin guardar nada.',
                          style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                    ],
                  ]),
      ),
    );
  }

  Widget _filaUI(int i, _FilaPlan f) {
    final sug = f.sugeridos;
    final colorEstado = f.guardada == true
        ? _kVerde
        : f.guardada == false
            ? cessumRed
            : f.revisionOk == true
                ? _kVerde
                : f.revisionOk == false
                    ? cessumRed
                    : cessumGold;
    return _agCaja(
        context,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Checkbox(
              value: f.incluir,
              activeColor: cessumRed,
              onChanged: _trabajando || f.guardada == true
                  ? null
                  : (v) {
                      setState(() => f.incluir = v ?? true);
                      _recalcular();
                    },
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}. ${f.materia['materia']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                if ('${f.materia['periodo'] ?? ''}'.isNotEmpty)
                  Text('Periodo ${f.materia['periodo']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              ]),
            ),
          ]),
          if (f.incluir && f.inicio.isNotEmpty) ...[
            Text('Del ${_agCorta(f.inicio)} al ${_agCorta(f.termino)}', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 6),
            if (sug.isEmpty)
              Text(f.dispNota, style: TextStyle(fontSize: 12, color: cessumMuted(context)))
            else ...[
              DropdownButtonFormField<String>(
                value: f.docente == null ? '' : '${f.docente!['correo']}',
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, labelText: 'Profesor', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Sin profesor (no se guarda)')),
                  for (final d in sug)
                    DropdownMenuItem(
                        value: '${d['correo']}',
                        child: Text('${d['nombre']} · ${d['motivo']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _trabajando || f.guardada == true
                    ? null
                    : (v) => setState(() {
                          f.docente = (v == null || v.isEmpty) ? null : sug.firstWhere((d) => '${d['correo']}' == v);
                          f.dispNota = 'Elegido a mano: el choque se revisa con «Revisar todo» o al guardar.';
                          f.revision = '';
                          f.revisionOk = null;
                        }),
              ),
              const SizedBox(height: 4),
              Text(f.dispNota,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: f.dispNota.startsWith('Libre') ? _kVerde : (f.dispNota.startsWith('⚠') ? _kAmbar : cessumMuted(context)))),
            ],
          ],
          if (f.revision.isNotEmpty || f.resultado.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(f.resultado.isNotEmpty ? f.resultado : f.revision,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colorEstado)),
            ),
        ]),
        borde: colorEstado);
  }
}

/* ==========================================================================
   4 · CARGA DOCENTE
   ========================================================================== */
class AgendaCargaDocenteScreen extends StatefulWidget {
  final List<Map<String, dynamic>> asignaciones;
  const AgendaCargaDocenteScreen({super.key, required this.asignaciones});

  @override
  State<AgendaCargaDocenteScreen> createState() => _AgendaCargaDocenteScreenState();
}

class _Carga {
  final String correo;
  String nombre;
  final List<Map<String, dynamic>> vigentes = [];
  final List<Map<String, dynamic>> proximas = [];
  final Set<String> materiasImpartidas = {};
  int historial = 0;
  int pendientesInvitacion = 0;
  double horas = 0;
  final List<String> choques = [];
  _Carga(this.correo, this.nombre);
}

class _AgendaCargaDocenteScreenState extends State<AgendaCargaDocenteScreen> {
  String _filtro = 'activos'; // activos · sobrecarga · sinAsignar · todos
  int _umbral = 4;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// Duración de una sesión a partir de «18:00-20:00», «18:00 a 20:00», «7:30–9:00»…
  static double? _duracion(String hora) {
    final ms = RegExp(r'(\d{1,2}):(\d{2})').allMatches(hora).toList();
    if (ms.length < 2) return null;
    double h(RegExpMatch m) => int.parse(m.group(1)!) + int.parse(m.group(2)!) / 60;
    final d = h(ms[1]) - h(ms[0]);
    return d > 0 && d < 12 ? d : null;
  }

  static List<double>? _rango(String hora) {
    final ms = RegExp(r'(\d{1,2}):(\d{2})').allMatches(hora).toList();
    if (ms.length < 2) return null;
    double h(RegExpMatch m) => int.parse(m.group(1)!) + int.parse(m.group(2)!) / 60;
    return [h(ms[0]), h(ms[1])];
  }

  List<_Carga> _calcular() {
    final hoy = DateTime.now();
    final d0 = DateTime(hoy.year, hoy.month, hoy.day);
    final en60 = d0.add(const Duration(days: 60));
    final m = <String, _Carga>{};
    for (final a in widget.asignaciones) {
      final estado = '${a['invitacionEstado'] ?? a['estado'] ?? ''}'.toLowerCase();
      if (estado == 'rechazada') continue;
      final correo = '${a['correo'] ?? ''}'.trim().toLowerCase();
      final nombre = '${a['docente'] ?? ''}'.trim();
      final llave = correo.isNotEmpty ? correo : nombre.toLowerCase();
      if (llave.isEmpty) continue;
      final c = m.putIfAbsent(llave, () => _Carga(correo, nombre));
      if (c.nombre.isEmpty) c.nombre = nombre;
      c.historial++;
      c.materiasImpartidas.add('${a['materia'] ?? ''}');
      if (estado == 'pendiente') c.pendientesInvitacion++;
      if ('${a['activa'] ?? 'SI'}'.toUpperCase() == 'NO') continue;
      final ini = _agFecha('${a['inicio'] ?? ''}');
      final fin = _agFecha('${a['termino'] ?? ''}');
      if (ini != null && fin != null && !ini.isAfter(d0) && !fin.isBefore(d0)) {
        c.vigentes.add(a);
        c.horas += _duracion('${a['hora'] ?? ''}') ?? 0.0;
      } else if (ini != null && ini.isAfter(d0) && !ini.isAfter(en60)) {
        c.proximas.add(a);
      }
    }
    // Choques entre sus materias vigentes: mismo día y horas que se encimen.
    for (final c in m.values) {
      for (var i = 0; i < c.vigentes.length; i++) {
        for (var j = i + 1; j < c.vigentes.length; j++) {
          final a = c.vigentes[i], b = c.vigentes[j];
          if ('${a['dia']}'.toLowerCase() != '${b['dia']}'.toLowerCase() || '${a['dia']}'.isEmpty) continue;
          final ra = _rango('${a['hora'] ?? ''}'), rb = _rango('${b['hora'] ?? ''}');
          if (ra == null || rb == null) continue;
          if (ra[0] < rb[1] && rb[0] < ra[1]) {
            c.choques.add('${a['dia']}: «${a['materia']}» y «${b['materia']}»');
          }
        }
      }
    }
    return m.values.toList();
  }

  bool _sobrecarga(_Carga c) => c.vigentes.length >= _umbral || c.horas >= 12 || c.choques.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final todas = _calcular();
    final activos = todas.where((c) => c.vigentes.isNotEmpty || c.proximas.isNotEmpty).toList();
    final sobre = todas.where(_sobrecarga).toList();
    final sinAsignar = todas.where((c) => c.vigentes.isEmpty && c.proximas.isEmpty && c.historial > 0).toList();
    var lista = switch (_filtro) {
      'sobrecarga' => sobre,
      'sinAsignar' => sinAsignar,
      'todos' => todas,
      _ => activos,
    };
    final q = _q.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      lista = lista.where((c) => '${c.nombre} ${c.correo} ${c.materiasImpartidas.join(' ')}'.toLowerCase().contains(q)).toList();
    }
    lista.sort((a, b) {
      final x = b.vigentes.length.compareTo(a.vigentes.length);
      return x != 0 ? x : a.nombre.compareTo(b.nombre);
    });
    final totalVig = activos.fold<int>(0, (s, c) => s + c.vigentes.length);
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Carga docente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 40), children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _kpi('Con materias ahora o en 60 días', '${activos.length}'),
          _kpi('Materias en curso', '$totalVig'),
          _kpi('Con sobrecarga', '${sobre.length}', color: sobre.isEmpty ? _kVerde : cessumRed),
          _kpi('Con experiencia y sin asignar', '${sinAsignar.length}', color: _kMorado),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final f in const [
            ['activos', 'Activos'],
            ['sobrecarga', 'Sobrecarga'],
            ['sinAsignar', 'Con experiencia, sin asignar'],
            ['todos', 'Todos'],
          ])
            ChoiceChip(
              label: Text(f[1]),
              selected: _filtro == f[0],
              selectedColor: cessumRed.withValues(alpha: 0.15),
              onSelected: (_) => setState(() => _filtro = f[0]),
            ),
        ]),
        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Sobrecarga desde', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          for (final n in const [3, 4, 5])
            ChoiceChip(
              label: Text('$n materias'),
              selected: _umbral == n,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _umbral = n),
            ),
          Text('a la vez, 12 h/semana o un choque', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _q,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar profesor o materia',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        if (lista.isEmpty)
          _agCaja(context, const Text('Nadie en esta vista.'))
        else
          ...lista.map((c) {
            final s = _sobrecarga(c);
            return _agCaja(
                context,
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(c.nombre.isEmpty ? c.correo : c.nombre,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                    if (s)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: const Text('Sobrecarga', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cessumRed)),
                      ),
                  ]),
                  if (c.correo.isNotEmpty) Text(c.correo, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                  const SizedBox(height: 4),
                  Text(
                      '${c.vigentes.length} en curso${c.horas > 0 ? ' · ~${c.horas.toStringAsFixed(1)} h/semana' : ''}'
                      ' · ${c.proximas.length} en los próximos 60 días'
                      '${c.pendientesInvitacion > 0 ? ' · ${c.pendientesInvitacion} invitación(es) sin responder' : ''}',
                      style: const TextStyle(fontSize: 12.5)),
                  for (final ch in c.choques)
                    Text('⚠ Choque: $ch', style: const TextStyle(fontSize: 12, color: cessumRed, fontWeight: FontWeight.w600)),
                  for (final a in c.vigentes)
                    Text('• ${a['materia']} · ${a['programa']} ${a['generacion']} ${a['grupo']} · ${a['dia'] ?? ''} ${a['hora'] ?? ''}',
                        style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                  if (c.vigentes.isEmpty && c.proximas.isEmpty)
                    Text('Ha impartido: ${c.materiasImpartidas.where((x) => x.isNotEmpty).join(', ')}',
                        style: const TextStyle(fontSize: 12, color: _kMorado)),
                ]),
                borde: s ? cessumRed : null);
          }),
      ]),
    );
  }

  Widget _kpi(String t, String v, {Color? color}) => Container(
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(t, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ]),
      );
}
