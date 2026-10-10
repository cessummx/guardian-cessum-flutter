import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Análisis de calificaciones: promedio general, aprobadas/reprobadas,
/// distribución por nota y desglose por programa-generación.
class AnalisisCalificacionesScreen extends StatefulWidget {
  const AnalisisCalificacionesScreen({super.key});

  @override
  State<AnalisisCalificacionesScreen> createState() =>
      _AnalisisCalificacionesScreenState();
}

class _AnalisisCalificacionesScreenState
    extends State<AnalisisCalificacionesScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String? _error;
  int _aprobatoria = 6;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _porGrupo = [];
  List<Map<String, dynamic>> _distribucion = [];
  // (24-sep) Filtro por programa, orden por reprobación y umbral de alerta.
  String _prog = 'Todos';
  bool _ordenReprob = false;
  static const double _umbralReprob = 20; // % de reprobación que enciende la alerta
  static const int _minCalif = 5;         // con menos calificaciones no se alarma

  double _pctReprob(Map<String, dynamic> g) {
    final n = ((g['n'] ?? 0) as num).toDouble();
    return n <= 0 ? 0.0 : ((g['reprob'] ?? 0) as num) * 100 / n;
  }

  bool _alta(Map<String, dynamic> g) => ((g['n'] ?? 0) as num) >= _minCalif && _pctReprob(g) >= _umbralReprob;

  List<String> get _programas {
    final s = <String>{for (final g in _porGrupo) '${g['programa'] ?? ''}'.trim()}..remove('');
    return s.toList()..sort();
  }

  List<Map<String, dynamic>> get _gruposVis {
    final l = _porGrupo.where((g) => _prog == 'Todos' || '${g['programa'] ?? ''}'.trim() == _prog).toList();
    if (_ordenReprob) l.sort((a, b) => _pctReprob(b).compareTo(_pctReprob(a)));
    return l;
  }

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
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=analisis_calificaciones'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _aprobatoria = (data['aprobatoria'] ?? 6) as int;
        _resumen = Map<String, dynamic>.from((data['resumen'] as Map?) ?? {});
        _porGrupo = ((data['porGrupo'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _distribucion = ((data['distribucion'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      // (24-sep) El motivo real (p. ej. «cierre sesión y vuelva a entrar»).
      final m = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _cargando = false;
        _error = (m == 'Error' || m.contains('TimeoutException') || m.startsWith('FormatException'))
            ? 'No se pudo cargar el análisis de calificaciones.'
            : m;
      });
    }
  }

  bool _leyendo = false;

  /// (24-sep) Pide al Guardián la lectura con IA del análisis (solo cifras).
  Future<void> _lecturaIa() async {
    setState(() => _leyendo = true);
    Map<String, dynamic> d;
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=calif_ia_lectura'))
          .timeout(const Duration(seconds: 120));
      d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar la lectura.');
    } catch (e) {
      if (mounted) {
        setState(() => _leyendo = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _leyendo = false);
    final focos = ((d['focos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final lectura = '${d['lectura'] ?? ''}';
    final texto = StringBuffer()
      ..writeln(lectura)
      ..writeln('')
      ..writeln([for (final f in focos) '• ${f['grupo']}: ${f['dato']}. ${f['sugerencia']}'].join('\n'));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lectura de las calificaciones', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              SelectableText(lectura, style: TextStyle(fontSize: 13.5, height: 1.45, color: cessumInk(ctx))),
              if (focos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Focos de atención', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: cessumInk(ctx))),
                const SizedBox(height: 6),
                for (final f in focos)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${f['grupo'] ?? ''}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cessumInk(ctx))),
                      const SizedBox(height: 2),
                      Text('${f['dato'] ?? ''}', style: TextStyle(fontSize: 12.5, color: cessumMuted(ctx))),
                      const SizedBox(height: 3),
                      Text('→ ${f['sugerencia'] ?? ''}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cessumRed)),
                    ]),
                  ),
              ],
              const SizedBox(height: 6),
              Text('${d['aviso'] ?? ''}',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Helpers.copiarAlPortapapeles(ctx, texto.toString(), 'Lectura'),
            child: const Text('Copiar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _copiarExcel() {
    final sb = StringBuffer();
    sb.writeln('Resumen general');
    sb.writeln('Registros\t${_resumen['registros'] ?? 0}');
    sb.writeln('Promedio\t${_resumen['promedio'] ?? ''}');
    sb.writeln('Aprobadas\t${_resumen['aprobadas'] ?? 0}');
    sb.writeln('Reprobadas\t${_resumen['reprobadas'] ?? 0}');
    sb.writeln('');
    sb.writeln('Distribución por nota');
    sb.writeln('Nota\tCantidad');
    for (final d in _distribucion) {
      sb.writeln('${d['nota']}\t${d['cantidad'] ?? 0}');
    }
    sb.writeln('');
    sb.writeln('Por programa y generación');
    sb.writeln('Programa\tGeneración\tCalificaciones\tPromedio\tAprobadas\tReprobadas');
    for (final g in _porGrupo) {
      sb.writeln('${g['programa']}\t${g['generacion']}\t${g['n'] ?? 0}\t'
          '${g['promedio'] ?? ''}\t${g['aprob'] ?? 0}\t${g['reprob'] ?? 0}');
    }
    Helpers.copiarAlPortapapeles(context, sb.toString(), 'Tabla');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Análisis de calificaciones',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          // (24-sep) Lectura con IA: qué significan las cifras y qué hacer.
          IconButton(
            tooltip: 'Lectura con IA',
            onPressed: (_cargando || _leyendo || _porGrupo.isEmpty) ? null : _lecturaIa,
            icon: _leyendo
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: 'Copiar para Excel',
            onPressed: _porGrupo.isEmpty ? null : _copiarExcel,
            icon: const Icon(Icons.grid_on),
          ),
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
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _tarjetaResumen(),
                      const SizedBox(height: 16),
                      _distribucionBloque(),
                      const SizedBox(height: 16),
                      _porGrupoBloque(),
                    ],
                  ),
                ),
    );
  }

  Widget _tarjetaResumen() {
    final registros = (_resumen['registros'] ?? 0) as int;
    final promedio = _resumen['promedio'] ?? 0;
    final aprob = (_resumen['aprobadas'] ?? 0) as int;
    final reprob = (_resumen['reprobadas'] ?? 0) as int;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _kpi('Promedio', '$promedio', cessumGold),
              _kpi('Aprobadas', '$aprob', _verde),
              _kpi('Reprobadas', '$reprob', cessumRed),
            ],
          ),
          const SizedBox(height: 6),
          Text('$registros calificaciones · mínima aprobatoria: $_aprobatoria',
              style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ],
      ),
    );
  }

  Widget _kpi(String etiqueta, String valor, Color color) {
    return Column(
      children: [
        Text(valor,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        Text(etiqueta,
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      ],
    );
  }

  Widget _distribucionBloque() {
    int maximo = 1;
    for (final d in _distribucion) {
      final v = (d['cantidad'] ?? 0) as int;
      if (v > maximo) maximo = v;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text('Distribución por nota',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _distribucion.isEmpty
                ? Text('Sin calificaciones registradas.',
                    style: TextStyle(color: cessumMuted(context)))
                : Column(
                    children: _distribucion.map((d) {
                      final nota = (d['nota'] ?? '').toString();
                      final cant = (d['cantidad'] ?? 0) as int;
                      final esReprob = nota.startsWith('<');
                      final color = esReprob ? cessumRed : _verde;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(nota,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: (cant / maximo).clamp(0.0, 1.0),
                                  minHeight: 9,
                                  backgroundColor: cessumMuted(context).withValues(alpha: 0.15),
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(color),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('$cant',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _porGrupoBloque() {
    final vis = _gruposVis;
    final altas = _porGrupo.where(_alta).toList()..sort((a, b) => _pctReprob(b).compareTo(_pctReprob(a)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text('Por programa y generación',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        // (24-sep) Los grupos con reprobación alta, arriba y con nombre.
        if (altas.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
            ),
            child: Text(
              '${altas.length} grupo(s) con reprobación de ${_umbralReprob.round()}% o más '
              '(con al menos $_minCalif calificaciones): '
              '${altas.map((g) => '${g['programa']} ${g['generacion']} (${_pctReprob(g).round()}%)').join('; ')}.',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumRed),
            ),
          ),
        if (_programas.length > 1)
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final p in ['Todos', ..._programas])
              ChoiceChip(
                label: Text(p == 'Todos' ? 'Todos los programas' : p, style: const TextStyle(fontSize: 12)),
                selected: _prog == p,
                visualDensity: VisualDensity.compact,
                selectedColor: cessumGold.withValues(alpha: 0.2),
                onSelected: (_) => setState(() => _prog = p),
              ),
          ]),
        Row(children: [
          Switch(
            value: _ordenReprob,
            activeThumbColor: cessumRed,
            onChanged: (v) => setState(() => _ordenReprob = v),
          ),
          Text('Mayor reprobación primero', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        ]),
        const SizedBox(height: 6),
        if (vis.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text('Sin datos.',
                style: TextStyle(color: cessumMuted(context))),
          )
        else
          ...vis.map(_filaGrupo),
      ],
    );
  }

  Widget _filaGrupo(Map<String, dynamic> g) {
    final prom = g['promedio'] ?? 0;
    final n = (g['n'] ?? 0) as int;
    final aprob = (g['aprob'] ?? 0) as int;
    final reprob = (g['reprob'] ?? 0) as int;
    final promD = (prom is num) ? prom.toDouble() : 0.0;
    final color = promD >= _aprobatoria ? _verde : cessumRed;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${g['programa']}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${g['generacion']} · $n calif. · '
                    '$aprob aprob. / $reprob reprob.',
                    style:
                        TextStyle(fontSize: 11, color: cessumMuted(context)),
                  ),
                  if (n > 0)
                    Text(
                      'Reprobación: ${_pctReprob(g).toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _alta(g) ? cessumRed : cessumMuted(context)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              children: [
                Text('$prom',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color)),
                Text('prom.',
                    style: TextStyle(fontSize: 10, color: cessumFaint(context))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
