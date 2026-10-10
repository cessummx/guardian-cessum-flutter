import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Tablero ejecutivo de Vicerrectoría: indicadores vivos de toda la
/// institución (matrícula, ingresos, trámites, incidencias, riesgo,
/// titulación, desempeño docente y satisfacción).
class TableroScreen extends StatefulWidget {
  const TableroScreen({super.key});

  @override
  State<TableroScreen> createState() => _TableroScreenState();
}

class _TableroScreenState extends State<TableroScreen> {
  bool _generandoPdf = false;
  Map<String, dynamic>? _d;
  bool _cargando = true;
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
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=tablero'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _d = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el tablero.';
      });
    }
  }

  String _money(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\$$b';
  }

  Future<void> _descargarPdf() async {
    setState(() => _generandoPdf = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=tablero_pdf'))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final pdf = (data['pdf'] ?? '').toString();
      if (!mounted) return;
      if (pdf.isNotEmpty) {
        Helpers.abrirUrlExterna(pdf, context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('Reporte generado · folio ${data['folio']}'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo generar el PDF: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tablero ejecutivo',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: (_cargando || _generandoPdf) ? null : _descargarPdf,
              icon: _generandoPdf
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf),
              tooltip: 'Descargar PDF'),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      body: _cargando
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: cessumRed),
                  SizedBox(height: 14),
                  Text('Calculando indicadores...',
                      style: TextStyle(color: cessumMuted(context))),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : _contenido(),
    );
  }

  Widget _contenido() {
    final d = _d!;
    final mat = (d['matricula'] ?? {}) as Map<String, dynamic>;
    final ing = (d['ingresos'] ?? {}) as Map<String, dynamic>;
    final tra = (d['tramites'] ?? {}) as Map<String, dynamic>;
    final inc = (d['incidencias'] ?? {}) as Map<String, dynamic>;
    final rie = (d['riesgo'] ?? {}) as Map<String, dynamic>;
    final tit = (d['titulacion'] ?? {}) as Map<String, dynamic>;
    final cal = (d['calificaciones'] ?? {}) as Map<String, dynamic>;
    final sat = (d['satisfaccion'] ?? {}) as Map<String, dynamic>;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Generado el ${d['generado'] ?? ''}',
            style: TextStyle(fontSize: 11, color: cessumFaint(context))),
        const SizedBox(height: 12),

        // KPIs principales
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.55,
          children: [
            _kpi('Matrícula activa', '${mat['activos'] ?? 0}',
                Icons.groups, cessumRed,
                sub: '${mat['bajas'] ?? 0} bajas históricas'),
            _kpi('Ingresos del mes', _money((ing['mes'] ?? 0) as num),
                Icons.payments, const Color(0xFF1E8E3E),
                sub: '${ing['pagosMes'] ?? 0} pagos · total ${_money((ing['total'] ?? 0) as num)}'),
            _kpi('Trámites pendientes', '${tra['pendientes'] ?? 0}',
                Icons.description, cessumGold,
                sub: '${tra['horasPromedio'] ?? 0} h promedio de atención'),
            _kpi('Incidencias abiertas', '${inc['abiertas'] ?? 0}',
                Icons.support_agent, cessumRed,
                sub: '${inc['resueltas'] ?? 0} resueltas'),
            _kpi('Alumnos en riesgo', '${rie['rojo'] ?? 0}',
                Icons.warning_amber_rounded, const Color(0xFFB11D29),
                sub: '${rie['amarillo'] ?? 0} en alerta amarilla'),
            _kpi('Satisfacción', '${sat['promedio'] ?? 0} / 5',
                Icons.star, cessumGold,
                sub: '${sat['votos'] ?? 0} respuestas'),
          ],
        ),
        const SizedBox(height: 8),

        _seccion('Matrícula por programa'),
        _barras(_topLista(mat['porPrograma']), cessumRed),

        _seccion('Matrícula por modalidad'),
        _barras(_topLista(mat['porModalidad']), cessumGold),

        if (((ing['porConcepto'] as List?) ?? []).isNotEmpty) ...[
          _seccion('Ingresos por concepto (histórico)'),
          _barrasMoney(_topLista(ing['porConcepto'])),
        ],

        _seccion('Aprobación académica'),
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aprobación global: ${cal['aprobacionGlobal'] ?? 0}%  ·  '
              '${cal['total'] ?? 0} calificaciones validadas',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ..._distribucion((cal['distribucion'] ?? {}) as Map<String, dynamic>),
          ],
        )),

        _seccion('Desempeño por docente (promedio y % aprobación)'),
        _tablaDocentes((cal['docentes'] as List?) ?? []),

        if (((tit['porEtapa'] as List?) ?? []).isNotEmpty) ...[
          _seccion('Titulación por etapa'),
          _barras(_topLista(tit['porEtapa']), const Color(0xFF1E8E3E)),
        ],

        if (((inc['porCategoria'] as List?) ?? []).isNotEmpty) ...[
          _seccion('Incidencias por categoría'),
          _barras(_topLista(inc['porCategoria']), cessumRed),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  List<Map<String, dynamic>> _topLista(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Widget _kpi(String titulo, String valor, IconData icono, Color color,
      {String sub = ''}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 20),
              const Spacer(),
            ],
          ),
          const Spacer(),
          Text(valor,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, color: color)),
          Text(titulo,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          if (sub.isNotEmpty)
            Text(sub,
                style:
                    const TextStyle(fontSize: 10.5, color: Colors.black45),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: cessumRed)),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
        ),
        child: child,
      );

  Widget _barras(List<Map<String, dynamic>> datos, Color color) {
    if (datos.isEmpty) return _card(const Text('Sin datos.'));
    final maxV = datos
        .map((e) => (e['valor'] ?? 0) as num)
        .fold<num>(1, (a, b) => b > a ? b : a);
    return _card(Column(
      children: datos.map((e) {
        final v = (e['valor'] ?? 0) as num;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${e['nombre']}',
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('$v',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: v / maxV,
                  minHeight: 7,
                  backgroundColor: color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ));
  }

  Widget _barrasMoney(List<Map<String, dynamic>> datos) {
    if (datos.isEmpty) return _card(const Text('Sin datos.'));
    final maxV = datos
        .map((e) => (e['valor'] ?? 0) as num)
        .fold<num>(1, (a, b) => b > a ? b : a);
    return _card(Column(
      children: datos.map((e) {
        final v = (e['valor'] ?? 0) as num;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${e['nombre']}',
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text(_money(v),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E8E3E))),
                ],
              ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: v / maxV,
                  minHeight: 7,
                  backgroundColor:
                      const Color(0xFF1E8E3E).withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF1E8E3E)),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ));
  }

  List<Widget> _distribucion(Map<String, dynamic> dist) {
    final orden = ['10', '9', '8', '7', '6', 'Reprobado'];
    final total = dist.values.fold<num>(0, (a, b) => a + (b as num));
    return orden.where((k) => dist.containsKey(k)).map((k) {
      final v = (dist[k] ?? 0) as num;
      final pct = total > 0 ? (v / total) : 0.0;
      final color = k == 'Reprobado' ? cessumRed : cessumGold;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
                width: 78,
                child: Text(k == 'Reprobado' ? 'Reprobado' : 'Calif. $k',
                    style: const TextStyle(fontSize: 11.5))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct.toDouble(),
                  minHeight: 8,
                  backgroundColor: color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('$v', style: const TextStyle(fontSize: 11.5)),
          ],
        ),
      );
    }).toList();
  }

  Widget _tablaDocentes(List docentes) {
    if (docentes.isEmpty) return _card(const Text('Sin datos.'));
    return _card(Column(
      children: [
        const Row(
          children: [
            Expanded(
                flex: 5,
                child: Text('Docente',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800))),
            Expanded(
                flex: 2,
                child: Text('Prom.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800))),
            Expanded(
                flex: 2,
                child: Text('Aprob.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800))),
            Expanded(
                flex: 2,
                child: Text('Eval.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800))),
          ],
        ),
        const Divider(height: 14),
        ...docentes.map((raw) {
          final e = Map<String, dynamic>.from(raw as Map);
          final aprob = (e['aprobacion'] ?? 0) as num;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                    flex: 5,
                    child: Text('${e['docente']}',
                        style: const TextStyle(fontSize: 11.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    flex: 2,
                    child: Text('${e['promedio']}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700))),
                Expanded(
                    flex: 2,
                    child: Text('$aprob%',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: aprob >= 80
                                ? const Color(0xFF1E8E3E)
                                : (aprob >= 60
                                    ? cessumGold
                                    : cessumRed)))),
                Expanded(
                    flex: 2,
                    child: Text('${e['evaluados']}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11.5, color: cessumMuted(context)))),
              ],
            ),
          );
        }),
      ],
    ));
  }
}
