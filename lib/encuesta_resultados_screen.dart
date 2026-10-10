import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'helpers.dart';

const List<String> _etiquetasCortas = [
  'Dominio',
  'Claridad',
  'Organización',
  'Evaluación',
  'Trato',
  'Satisfacción',
];

const Color _kVerde = Color(0xFF1E8E3E);

/// Admin: resultados de la encuesta de satisfacción.
///
/// (24-sep) Dos vistas:
///  · Por docente (nueva): promedio general, TENDENCIA entre periodos (sube,
///    baja o se mantiene), la pregunta más baja —qué atender— y ALERTA cuando
///    el último periodo queda por debajo de 3.5 con al menos 3 respuestas
///    (una o dos opiniones no marcan a nadie). Los que tienen alerta, arriba.
///  · Por materia: la de siempre (promedio, por pregunta y comentarios).
/// Colores que respetan el modo oscuro.
class EncuestaResultadosScreen extends StatefulWidget {
  const EncuestaResultadosScreen({super.key});

  @override
  State<EncuestaResultadosScreen> createState() => _EncuestaResultadosScreenState();
}

class _EncuestaResultadosScreenState extends State<EncuestaResultadosScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _resultados = [];
  List<Map<String, dynamic>> _porDocente = [];
  num _umbral = 3.5;
  int _minResp = 3;
  bool _verDocentes = true;
  final _filtro = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _filtro.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _lista(dynamic x) =>
      ((x as List<dynamic>?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'encuesta_resultados',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _resultados = _lista(data['resultados']);
      _porDocente = _lista(data['porDocente']);
      _umbral = (data['umbral'] as num?) ?? 3.5;
      _minResp = (data['minRespuestas'] as num?)?.toInt() ?? 3;
    } catch (e) {
      _error = '$e'.replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
  }

  Color _color(num v) {
    if (v >= 4.0) return _kVerde;
    if (v >= 3.0) return cessumGold;
    return cessumRed;
  }

  bool _pasa(Map<String, dynamic> r) {
    final q = _filtro.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${r['docente'] ?? ''} ${r['materia'] ?? ''}'.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final docentes = _porDocente.where(_pasa).toList();
    final materias = _resultados.where(_pasa).toList();
    final alertas = _porDocente.where((d) => d['alerta'] == true).toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Resultados de encuestas'),
        actions: [
          IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    if (alertas.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cessumRed.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.warning_amber_rounded, color: cessumRed),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${alertas.length} docente(s) por debajo de ${_umbral.toStringAsFixed(1)} en su último periodo: '
                              '${alertas.map((d) => d['docente']).join(', ')}.',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cessumRed),
                            ),
                          ),
                        ]),
                      ),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: true, label: Text('Por docente (${_porDocente.length})')),
                        ButtonSegment(value: false, label: Text('Por materia (${_resultados.length})')),
                      ],
                      selected: {_verDocentes},
                      onSelectionChanged: (s) => setState(() => _verDocentes = s.first),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _filtro,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Filtrar por docente o materia',
                        isDense: true,
                        prefixIcon: Icon(Icons.search, color: cessumRed),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_verDocentes)
                      Text(
                          'La tendencia compara el último periodo con el anterior; '
                          'solo cuentan los periodos con $_minResp respuestas o más.',
                          style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                    const SizedBox(height: 8),
                    if ((_verDocentes ? docentes : materias).isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text('Aún no hay respuestas de encuesta.',
                              style: TextStyle(color: cessumMuted(context))),
                        ),
                      ),
                    if (_verDocentes) ...docentes.map(_tarjetaDocente) else ...materias.map(_tarjeta),
                    const SizedBox(height: 30),
                  ],
                ),
    );
  }

  // ---------- síntesis con IA ----------
  final Set<String> _sintetizando = {};

  /// (24-sep) Síntesis de los comentarios de un docente con IA: fortalezas,
  /// áreas de mejora, comentarios representativos y cómo plantear la
  /// conversación. Solo administración; no se guarda ni se envía.
  Future<void> _sintesis(String docente) async {
    setState(() => _sintetizando.add(docente));
    Map<String, dynamic> d;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'encuesta_ia_sintesis', 'docente': docente}))
          .timeout(const Duration(seconds: 90));
      d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar la síntesis.');
    } catch (e) {
      if (mounted) {
        setState(() => _sintetizando.remove(docente));
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _sintetizando.remove(docente));
    List<String> l(String k) => ((d[k] as List?) ?? []).map((e) => '$e').toList();
    final texto = StringBuffer()
      ..writeln('Síntesis de encuestas · $docente')
      ..writeln('Fortalezas:')
      ..writeln(l('fortalezas').map((x) => '• $x').join('\n'))
      ..writeln('Áreas de mejora:')
      ..writeln(l('mejoras').map((x) => '• $x').join('\n'))
      ..writeln('Cómo plantear la conversación: ${d['conversacion'] ?? ''}');
    Widget lista(String titulo, List<String> xs, Color c) => xs.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 13)),
              for (final x in xs) Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('• $x', style: const TextStyle(fontSize: 12.8, height: 1.35)),
              ),
            ]),
          );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Síntesis · $docente', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${d['respuestas'] ?? 0} respuesta(s) · ${d['comentarios'] ?? 0} comentario(s) escrito(s)',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(ctx))),
              lista('Fortalezas', l('fortalezas'), _kVerde),
              lista('Áreas de mejora', l('mejoras'), cessumRed),
              lista('Comentarios representativos', l('citas').map((c) => '“$c”').toList(), cessumGold),
              if ('${d['conversacion'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Cómo plantear la conversación', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 3),
                Text('${d['conversacion']}', style: const TextStyle(fontSize: 12.8, height: 1.4)),
              ],
              const SizedBox(height: 10),
              Text('Generada con IA a partir de los comentarios anónimos: es un apoyo, no un dictamen.',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Helpers.copiarAlPortapapeles(ctx, texto.toString(), 'Síntesis'),
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

  // ---------- por docente ----------
  Widget _tarjetaDocente(Map<String, dynamic> r) {
    final prom = (r['promedio'] ?? 0) as num;
    final alerta = r['alerta'] == true;
    final tend = r['tendencia'] as num?;
    final baja = (r['preguntaMasBaja'] as num?)?.toInt() ?? -1;
    final porP = ((r['porPregunta'] as List<dynamic>? ?? [])).map((e) => (e ?? 0) as num).toList();
    final periodos = _lista(r['periodos']);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: alerta ? BorderSide(color: cessumRed.withValues(alpha: 0.6), width: 1.4) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['docente'] ?? 'Docente'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${r['materias'] ?? 0} materia(s) · ${r['respuestas'] ?? 0} respuesta(s)',
                    style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(prom.toStringAsFixed(1),
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _color(prom))),
              if (tend != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    tend > 0.05 ? Icons.trending_up : (tend < -0.05 ? Icons.trending_down : Icons.trending_flat),
                    size: 16,
                    color: tend > 0.05 ? _kVerde : (tend < -0.05 ? cessumRed : cessumMuted(context)),
                  ),
                  const SizedBox(width: 3),
                  Text('${tend > 0 ? '+' : ''}${tend.toStringAsFixed(1)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: tend > 0.05 ? _kVerde : (tend < -0.05 ? cessumRed : cessumMuted(context)))),
                ]),
            ]),
          ]),
          if (alerta)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Último periodo: ${(r['ultimo'] as num?)?.toStringAsFixed(1) ?? '—'}, por debajo de ${_umbral.toStringAsFixed(1)}.',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumRed)),
            ),
          if (baja >= 0 && baja < _etiquetasCortas.length && baja < porP.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Lo más bajo: ${_etiquetasCortas[baja]} (${porP[baja].toStringAsFixed(1)}).',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
            ),
          if (periodos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in periodos)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _color((p['promedio'] as num?) ?? 0).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${p['periodo']}: ${((p['promedio'] as num?) ?? 0).toStringAsFixed(1)} · ${p['respuestas']} resp.'
                    '${((p['respuestas'] as num?) ?? 0) < _minResp ? ' (pocas)' : ''}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cessumInk(context)),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 8),
          ..._barras(porP),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
              onPressed: _sintetizando.contains('${r['docente']}') ? null : () => _sintesis('${r['docente']}'),
              icon: _sintetizando.contains('${r['docente']}')
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed))
                  : const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Síntesis con IA'),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _barras(List<num> porPregunta) => List.generate(porPregunta.length, (i) {
        final v = porPregunta[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(
              width: 96,
              child: Text(i < _etiquetasCortas.length ? _etiquetasCortas[i] : 'P${i + 1}',
                  style: const TextStyle(fontSize: 11.5)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (v / 5.0).clamp(0.0, 1.0).toDouble(),
                  minHeight: 8,
                  backgroundColor: cessumMuted(context).withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(_color(v)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 28,
              child: Text(v.toStringAsFixed(1),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ]),
        );
      });

  // ---------- por materia (la de siempre) ----------
  Widget _tarjeta(Map<String, dynamic> r) {
    final prom = (r['promedio'] ?? 0) as num;
    final n = (r['respuestas'] ?? 0);
    final porPregunta = ((r['porPregunta'] as List<dynamic>? ?? [])).map((e) => (e ?? 0) as num).toList();
    final comentarios = ((r['comentarios'] as List<dynamic>? ?? []))
        .map((e) => e.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((r['docente'] ?? 'Docente').toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text((r['materia'] ?? '').toString(),
                          style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(prom.toStringAsFixed(1),
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _color(prom))),
                    Text('$n resp.', style: TextStyle(fontSize: 11, color: cessumFaint(context))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._barras(porPregunta),
            if (comentarios.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text('Comentarios (${comentarios.length})',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cessumRed)),
                  children: comentarios
                      .map((c) => Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cessumGold.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('“$c”', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
