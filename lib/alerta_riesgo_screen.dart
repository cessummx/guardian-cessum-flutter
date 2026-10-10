import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

// =====================================================================
// PANTALLA: "Alerta temprana de riesgo académico" (ADMINISTRADOR)
// ---------------------------------------------------------------------
// Lista a los alumnos en riesgo de reprobar o abandonar, con su nivel
// (Alto/Medio), el porqué y un resumen por nivel. Los datos provienen del
// motor del Guardián (riesgo_panel), que combina promedio, calificaciones
// al límite, materias estancadas en validación e inactividad en la app.
//
// (24-sep) Segunda fase:
//  · Buscador y filtros por nivel y por programa.
//  · SEGUIMIENTO: cada alumno muestra cuántos seguimientos tiene y el
//    último (quién, cuándo, qué se hizo y la nota), y un botón para
//    registrar uno nuevo. Antes se guardaban y nadie los veía, así que el
//    riesgo se quedaba en una lista.
//  · Mensajes de error con el motivo real y colores del tema (modo oscuro).
//
// CONTRATO (Code.gs):
//   riesgo_panel (GET) -> { ok, resumen:{alto,medio,bajo,total},
//        alumnos:[{matricula,nombre,programa,generacion,nivel,score,razones,
//                  promedio,validadas,estancadas,diasSinAcceso,
//                  seguimiento?:{total,fecha,quien,accion,nota}}] }
//   riesgo_seguimiento (POST) { matricula, alumno, correoDocente, tipo, nota }
//        (el Guardián toma como autor al dueño de la llave de sesión)
// =====================================================================

const List<String> _tiposSeguimiento = [
  'Llamada',
  'Mensaje',
  'Reunión',
  'Canalizado a tutoría',
  'Otro',
];

class AlertaRiesgoScreen extends StatefulWidget {
  const AlertaRiesgoScreen({super.key});

  @override
  State<AlertaRiesgoScreen> createState() => _AlertaRiesgoScreenState();
}

class _AlertaRiesgoScreenState extends State<AlertaRiesgoScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _alumnos = [];
  final _q = TextEditingController();
  String _nivel = 'Todos';
  String _programa = 'Todos';
  bool _soloSinSeguimiento = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'riesgo_panel'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      if (!mounted) return;
      setState(() {
        _resumen = Map<String, dynamic>.from((data['resumen'] as Map?) ?? const {});
        _alumnos = ((data['alumnos'] as List?) ?? []).map((a) => Map<String, dynamic>.from(a as Map)).toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final m = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _cargando = false;
        _error = (m.contains('TimeoutException') || m.startsWith('FormatException') || m == 'Respuesta invalida')
            ? 'No se pudo cargar el análisis de riesgo.'
            : m;
      });
    }
  }

  Color _colorNivel(String n) {
    if (n == 'Alto') return cessumRed;
    if (n == 'Medio') return Colors.orange.shade800;
    return Colors.green.shade700;
  }

  List<String> get _programas {
    final s = <String>{for (final a in _alumnos) '${a['programa'] ?? ''}'.trim()}..remove('');
    return s.toList()..sort();
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _q.text.trim().toLowerCase();
    return _alumnos.where((a) {
      if (_nivel != 'Todos' && a['nivel'] != _nivel) return false;
      if (_programa != 'Todos' && '${a['programa'] ?? ''}'.trim() != _programa) return false;
      if (_soloSinSeguimiento && a['seguimiento'] != null) return false;
      if (q.isEmpty) return true;
      return '${a['nombre']} ${a['matricula']} ${a['programa']} ${a['generacion']}'.toLowerCase().contains(q);
    }).toList();
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
      content: Text(m),
    ));
  }

  // ---------- sugerencia de intervención con IA ----------
  final Set<String> _sugiriendo = {};

  /// (24-sep) Pasos de intervención priorizados y un mensaje para el alumno,
  /// a partir de lo que ya muestra la alerta. No envía nada.
  Future<void> _sugerir(Map<String, dynamic> a) async {
    final mat = '${a['matricula'] ?? ''}';
    setState(() => _sugiriendo.add(mat));
    Map<String, dynamic> d;
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'riesgo_ia_sugerir', 'alumno': a}))
          .timeout(const Duration(seconds: 90));
      d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar la sugerencia.');
    } catch (e) {
      if (mounted) setState(() => _sugiriendo.remove(mat));
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _sugiriendo.remove(mat));
    final pasos = ((d['pasos'] as List?) ?? []).map((e) => '$e').toList();
    final mensaje = '${d['mensaje'] ?? ''}';
    final usar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Intervención sugerida · ${a['nombre'] ?? ''}', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if ('${d['prioridad'] ?? ''}'.isNotEmpty)
                Text('Prioridad: ${d['prioridad']}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              const SizedBox(height: 8),
              const Text('Pasos sugeridos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              for (var i = 0; i < pasos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${i + 1}. ${pasos[i]}', style: const TextStyle(fontSize: 12.8, height: 1.35)),
                ),
              if (mensaje.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Expanded(
                      child: Text('Mensaje para el alumno', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                  IconButton(
                    tooltip: 'Copiar',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => Helpers.copiarAlPortapapeles(ctx, mensaje, 'Mensaje'),
                  ),
                ]),
                SelectableText(mensaje, style: const TextStyle(fontSize: 12.8, height: 1.4)),
              ],
              const SizedBox(height: 10),
              Text('${d['aviso'] ?? 'Sugerencia generada con IA: la decisión es de la institución.'}',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usar como nota de seguimiento'),
          ),
        ],
      ),
    );
    if (usar == true && mounted) {
      await _registrarSeguimiento(a, notaInicial: 'Plan: ${pasos.map((p) => '• $p').join(' ')}');
    }
  }

  Future<void> _registrarSeguimiento(Map<String, dynamic> a, {String notaInicial = ''}) async {
    String tipo = _tiposSeguimiento.first;
    final nota = TextEditingController(text: notaInicial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Seguimiento · ${a['nombre'] ?? ''}', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('¿Qué se hizo?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in _tiposSeguimiento)
                  ChoiceChip(
                    label: Text(t),
                    selected: tipo == t,
                    selectedColor: cessumRed.withValues(alpha: 0.15),
                    onSelected: (_) => setD(() => tipo = t),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: nota,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nota',
                  hintText: 'Qué se habló, qué se acordó, cuándo se vuelve a revisar…',
                  border: OutlineInputBorder(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final textoNota = nota.text.trim();
    nota.dispose();
    if (ok != true) return;
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'riesgo_seguimiento',
                'matricula': '${a['matricula'] ?? ''}',
                'alumno': '${a['nombre'] ?? ''}',
                'correoDocente': actor,
                'tipo': tipo,
                'nota': textoNota,
              }))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('Seguimiento registrado.');
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Alerta temprana'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: cessumRed),
            const SizedBox(height: 14),
            Text('Analizando el riesgo de los alumnos...', style: TextStyle(color: cessumMuted(context))),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52, color: cessumRed),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _cargar,
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
                child: const Text('Reintentar', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    final lista = _visibles;
    final sinSeg = _alumnos.where((a) => a['seguimiento'] == null).length;
    return RefreshIndicator(
      onRefresh: _cargar,
      color: cessumRed,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _resumenCard(sinSeg),
          const SizedBox(height: 10),
          TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar por nombre, matrícula, programa o generación',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final n in const ['Todos', 'Alto', 'Medio'])
              ChoiceChip(
                label: Text(n == 'Todos' ? 'Todos los niveles' : 'Riesgo ${n.toLowerCase()}'),
                selected: _nivel == n,
                visualDensity: VisualDensity.compact,
                selectedColor: cessumRed.withValues(alpha: 0.15),
                onSelected: (_) => setState(() => _nivel = n),
              ),
            FilterChip(
              label: Text('Sin seguimiento ($sinSeg)'),
              selected: _soloSinSeguimiento,
              visualDensity: VisualDensity.compact,
              selectedColor: cessumRed.withValues(alpha: 0.15),
              onSelected: (v) => setState(() => _soloSinSeguimiento = v),
            ),
          ]),
          if (_programas.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final p in ['Todos', ..._programas])
                  ChoiceChip(
                    label: Text(p == 'Todos' ? 'Todos los programas' : p, style: const TextStyle(fontSize: 12)),
                    selected: _programa == p,
                    visualDensity: VisualDensity.compact,
                    selectedColor: cessumGold.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _programa = p),
                  ),
              ]),
            ),
          const SizedBox(height: 10),
          if (_alumnos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text('Sin alumnos en riesgo por ahora. ¡Buen trabajo!',
                    style: TextStyle(color: cessumMuted(context), fontSize: 14)),
              ),
            )
          else if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('Nadie con estos filtros.', style: TextStyle(color: cessumMuted(context)))),
            )
          else
            ...lista.map(_fichaAlumno),
          const SizedBox(height: 16),
          Text(
            'El nivel combina promedio, calificaciones al límite, materias '
            'estancadas en validación e inactividad en la app. Sirve para '
            'priorizar a quién contactar primero, no como dictamen.',
            style: TextStyle(fontSize: 11.5, color: cessumFaint(context), height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _resumenCard(int sinSeg) {
    final alto = (_resumen['alto'] ?? 0);
    final medio = (_resumen['medio'] ?? 0);
    final bajo = (_resumen['bajo'] ?? 0);
    final total = (_resumen['total'] ?? 0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Panorama de $total alumnos activos', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              _mini('Riesgo alto', '$alto', cessumRed),
              _mini('Riesgo medio', '$medio', Colors.orange.shade800),
              _mini('Estables', '$bajo', Colors.green.shade700),
            ],
          ),
          if (_alumnos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              sinSeg == 0
                  ? 'Todos los alumnos en riesgo tienen al menos un seguimiento registrado.'
                  : '$sinSeg de ${_alumnos.length} alumno(s) en riesgo todavía no tienen ningún seguimiento.',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: sinSeg == 0 ? Colors.green.shade700 : cessumRed),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mini(String etiqueta, String valor, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(etiqueta, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          ],
        ),
      ),
    );
  }

  Widget _fichaAlumno(Map<String, dynamic> a) {
    final nivel = '${a['nivel'] ?? ''}';
    final color = _colorNivel(nivel);
    final razones = ((a['razones'] as List?) ?? []).cast<dynamic>();
    final prom = a['promedio'];
    final promTxt = (prom is num) ? prom.toStringAsFixed(1) : '—';
    final seg = a['seguimiento'] == null ? null : Map<String, dynamic>.from(a['seguimiento'] as Map);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 38,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a['nombre'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      Text(
                        '${a['matricula'] ?? ''} · ${a['programa'] ?? ''} · ${a['generacion'] ?? ''}',
                        style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Text(nivel, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _pill('Promedio $promTxt'),
                _pill('${a['validadas'] ?? 0} validadas'),
                if (((a['diasSinAcceso'] ?? -1) as num) >= 0) _pill('${a['diasSinAcceso']} días sin entrar'),
              ],
            ),
            const SizedBox(height: 8),
            ...razones.map((r) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 15, color: color),
                      const SizedBox(width: 6),
                      Expanded(child: Text(r.toString(), style: const TextStyle(fontSize: 12.5, height: 1.3))),
                    ],
                  ),
                )),
            const Divider(height: 18),
            if (seg == null)
              const Text('Sin seguimiento registrado.',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumRed))
            else
              Text(
                'Último seguimiento (${seg['total']} en total): ${seg['accion'] ?? ''} · ${seg['fecha'] ?? ''}'
                '${'${seg['quien'] ?? ''}'.isNotEmpty ? ' · ${seg['quien']}' : ''}'
                '${'${seg['nota'] ?? ''}'.isNotEmpty ? '\n«${seg['nota']}»' : ''}',
                style: TextStyle(fontSize: 12.5, color: cessumInk(context), height: 1.35),
              ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
                onPressed: () => _registrarSeguimiento(a),
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Registrar seguimiento'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cessumGold, visualDensity: VisualDensity.compact),
                onPressed: _sugiriendo.contains('${a['matricula']}') ? null : () => _sugerir(a),
                icon: _sugiriendo.contains('${a['matricula']}')
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cessumGold))
                    : const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Sugerir intervención (IA)'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _pill(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(texto, style: TextStyle(fontSize: 11, color: cessumInk(context))),
    );
  }
}
