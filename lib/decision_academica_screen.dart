// =====================================================================
//  decision_academica_screen.dart · CESSUM · (25-sep-2026)
//  PANEL DE DECISIÓN ACADÉMICA (administración)
//
//  Parte de la evaluación que hacen los alumnos a sus docentes y la
//  convierte en decisiones. Como casi todas las respuestas son 5 (efecto
//  techo), la métrica es la TASA DE RESPUESTAS POR DEBAJO DE 5, ajustada por
//  tamaño de muestra y con intervalo de confianza.
//   1. Diagnóstico: dimensiones, programas (mapa de calor), tendencia,
//      dificultad percibida y método.
//   2. Docentes: segmento, tasa cruda con IC y ajustada, cruce con el
//      desempeño operativo del escalafón, y plan de mejora con IA.
//   3. Decisiones: análisis con IA (incluye los comentarios) y decisiones
//      por reglas; cualquiera se adopta con un toque.
//   4. Seguimiento: decisiones adoptadas, estado, notas y EFECTO medido
//      (tasa antes vs. evaluaciones posteriores a la adopción).
//
//  Guardián: GET decision_panel · GET decision_panel_ia · GET decision_docente_ia
//            GET decisiones_listar · POST decision_adoptar · POST decision_actualizar
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

const _verde = Color(0xFF1E7F52);
const _azul = Color(0xFF2F5D8A);

Color _colorSeg(String s) => switch (s) {
      'Atención prioritaria' => cessumRed,
      'Seguimiento' => cessumGold,
      'Referente' => _verde,
      'Estable' => _azul,
      _ => Colors.grey,
    };

class DecisionAcademicaScreen extends StatefulWidget {
  const DecisionAcademicaScreen({super.key});
  @override
  State<DecisionAcademicaScreen> createState() => _DecisionAcademicaScreenState();
}

class _DecisionAcademicaScreenState extends State<DecisionAcademicaScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};

  // Docentes
  String _seg = 'todos';
  final _busca = TextEditingController();

  // IA
  bool _iaCargando = false;
  String _iaError = '';
  Map<String, dynamic>? _ia;

  // Seguimiento
  bool _segCargando = false;
  List<Map<String, dynamic>> _decisiones = [];
  final Set<String> _adoptadas = {};

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarSeguimiento();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp, {int segundos = 150}) async {
    final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: qp)).timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 90));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void _aviso(String t, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : _verde,
      duration: const Duration(seconds: 5),
      content: Text(t),
    ));
  }

  List<Map<String, dynamic>> _lista(dynamic v) => ((v as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final d = await _get({'accion': 'decision_panel'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cargar.');
      _d = d;
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarIa({bool rehacer = false}) async {
    setState(() {
      _iaCargando = true;
      _iaError = '';
    });
    try {
      final d = await _get({'accion': 'decision_panel_ia', if (rehacer) 'rehacer': '1'}, segundos: 280);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar el análisis.');
      _ia = d;
    } catch (e) {
      _iaError = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _iaCargando = false);
  }

  Future<void> _cargarSeguimiento() async {
    setState(() => _segCargando = true);
    try {
      final d = await _get({'accion': 'decisiones_listar'});
      if (d['ok'] == true) _decisiones = _lista(d['items']);
    } catch (_) {}
    if (mounted) setState(() => _segCargando = false);
  }

  Future<void> _adoptar(Map<String, dynamic> x, String origen) async {
    final clave = '${x['titulo']}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Adoptar esta decisión?', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(clave, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('${x['accion'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 8),
            const Text(
                'Queda registrada con su línea base (la tasa actual). En «Seguimiento» verá su estado y, conforme lleguen evaluaciones nuevas, su efecto. No se avisa a nadie.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Adoptar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final d = await _post({
        'accion': 'decision_adoptar',
        'titulo': x['titulo'],
        'tipo': x['tipo'] ?? '',
        'prioridad': x['prioridad'] ?? '',
        'dirigidoA': x['dirigidoA'] ?? '',
        'docentes': ((x['docentes'] as List?) ?? []).map((e) => '$e').toList(),
        'dimension': x['dimension'] ?? '',
        'evidencia': x['evidencia'] ?? '',
        'accion': x['accion'] ?? '',
        'indicador': x['indicador'] ?? '',
        'meta': x['meta'] ?? '',
        'plazo': x['plazo'] ?? '',
        'origen': origen,
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo registrar.');
      setState(() => _adoptadas.add(clave));
      _aviso('Decisión adoptada (${d['id']}).');
      _cargarSeguimiento();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _planDocente(Map<String, dynamic> x) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    Map<String, dynamic> d;
    try {
      d = await _get({'accion': 'decision_docente_ia', 'llave': '${x['llave']}'});
    } catch (_) {
      d = {'ok': false, 'error': 'No se pudo conectar.'};
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (d['ok'] != true) {
      _aviso('${d['error'] ?? 'No se pudo generar el plan.'}', error: true);
      return;
    }
    final plan = _lista(d['plan']);
    final areas = _lista(d['areas']);
    final adoptar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.auto_awesome, color: cessumGold),
          const SizedBox(width: 8),
          Expanded(child: Text('Plan de mejora · ${x['docente']}', style: const TextStyle(fontSize: 16))),
        ]),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['sintesis'] ?? ''}', style: const TextStyle(fontSize: 13.5, height: 1.45)),
              Text('Confianza: ${d['confianza'] ?? '—'} (${x['evaluaciones']} evaluaciones)',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(ctx))),
              const SizedBox(height: 10),
              const Text('Fortalezas', style: TextStyle(fontWeight: FontWeight.w800, color: _verde)),
              for (final f in ((d['fortalezas'] as List?) ?? [])) Text('+ $f', style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
              const Text('Áreas de mejora', style: TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              for (final a in areas)
                Text('– ${a['dimension']}: ${a['evidencia']}', style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
              const Text('Plan', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final p in plan)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• ${p['accion']} · ${p['plazo']} · indicador: ${p['indicador']}',
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('Cómo plantear la conversación: ${d['conversacion'] ?? ''}',
                    style: const TextStyle(fontSize: 12.8, height: 1.45)),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Adoptar como decisión'),
          ),
        ],
      ),
    );
    if (adoptar == true && mounted) {
      await _adoptar({
        'titulo': 'Plan de mejora: ${x['docente']}',
        'tipo': 'Acompañamiento',
        'prioridad': x['segmento'] == 'Atención prioritaria' ? 'Alta' : 'Media',
        'dirigidoA': x['docente'],
        'docentes': [x['docente']],
        'evidencia': 'Tasa ajustada ${x['tasaAjustada']} % con ${x['evaluaciones']} evaluaciones.',
        'accion': plan.map((p) => '${p['accion']} (${p['plazo']})').join('; '),
        'indicador': 'Tasa ajustada del docente',
        'meta': 'Acercarse a la institucional',
        'plazo': plan.isNotEmpty ? '${plan.last['plazo']}' : '8 semanas',
      }, 'ia-docente');
    }
  }

  Future<void> _actualizar(Map<String, dynamic> x, {String? estado}) async {
    String? nota;
    if (estado == null) {
      final ctl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Agregar nota de seguimiento', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 440,
            child: TextField(
              controller: ctl,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Ej. Se observó la clase del 3/10; acuerdos firmados.'),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      nota = ctl.text.trim();
      ctl.dispose();
      if (ok != true || nota.isEmpty) return;
    }
    try {
      final d = await _post({'accion': 'decision_actualizar', 'id': x['id'], if (estado != null) 'estado': estado, if (nota != null) 'nota': nota});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _cargarSeguimiento();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  // ---------------- Vista ----------------

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Decisión académica'),
          actions: [
            IconButton(
                tooltip: 'Actualizar',
                onPressed: _cargando
                    ? null
                    : () {
                        _cargar();
                        _cargarSeguimiento();
                      },
                icon: const Icon(Icons.refresh)),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Diagnóstico'), Tab(text: 'Docentes'), Tab(text: 'Decisiones'), Tab(text: 'Seguimiento')],
          ),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator(color: cessumRed))
            : _error.isNotEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error, textAlign: TextAlign.center),
                    TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                  ]))
                : _d['vacio'] == true
                    ? const Center(child: Text('Todavía no hay evaluaciones de alumnos.'))
                    : TabBarView(children: [_tabDiagnostico(), _tabDocentes(), _tabDecisiones(), _tabSeguimiento()]),
      ),
    );
  }

  Widget _kpi(String valor, String etiqueta, Color c) => Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c)),
          Text(etiqueta, style: TextStyle(fontSize: 11, color: cessumMuted(context), height: 1.3)),
        ]),
      );

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
      );

  // ---- 1. Diagnóstico ----
  Widget _tabDiagnostico() {
    final g = Map<String, dynamic>.from((_d['global'] as Map?) ?? {});
    final seg = Map<String, dynamic>.from((_d['segmentos'] as Map?) ?? {});
    final dims = _lista(_d['dimensiones'])..sort((a, b) => ((b['tasa'] ?? 0) as num).compareTo((a['tasa'] ?? 0) as num));
    final maxT = dims.isEmpty ? 1.0 : ((dims.first['tasa'] ?? 1) as num).toDouble().clamp(1.0, 100.0);
    final progs = _lista(_d['programas']);
    final tend = _lista(_d['tendencia']);
    final dif = Map<String, dynamic>.from((_d['dificultad'] as Map?) ?? {});
    final dimNombres = _lista(_d['dimensiones']).map((x) => '${x['clave']}').toList();
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _kpi('${_d['evaluaciones']}', 'evaluaciones de alumnos\n${g['desde']} a ${g['hasta']}', _azul),
          _kpi('${g['tasaBajo5']} %', 'respuestas por debajo de 5\n(la métrica del panel)', cessumRed),
          _kpi('${g['pct5']} %', 'respuestas en 5\n${g['efectoTecho'] == true ? 'efecto techo' : ''}', cessumGold),
          _kpi('${seg['Atención prioritaria'] ?? 0}', 'docentes en\natención prioritaria', cessumRed),
          _kpi('${seg['Referente'] ?? 0}', 'docentes\nreferentes', _verde),
          _kpi('${seg['Evidencia insuficiente'] ?? 0}', 'con evidencia\ninsuficiente', Colors.grey),
          if (g['aulaTasaNo'] != null) _kpi('${g['aulaTasaNo']} %', 'de «No» en el aula\nvirtual (bloque T)', _azul),
        ]),
        if (g['efectoTecho'] == true)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
            ),
            child: Text(
              'El ${g['pct5']} % de las respuestas son 5: el promedio (${g['media']}) no distingue entre docentes. Por eso el panel mide '
              'la tasa de respuestas por debajo de 5, ajustada por el número de evaluaciones.',
              style: const TextStyle(fontSize: 12.8, height: 1.45),
            ),
          ),
        _titulo('Dimensiones: dónde están las áreas de mejora'),
        for (final x in dims)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${x['clave']} · ${x['dimension']}', style: const TextStyle(fontSize: 12.5))),
                // (25-sep) Votos del cuestionario nuevo: lo que más ayudó / puede mejorar.
                if (((x['votosMejora'] ?? 0) as num) > 0 || ((x['votosFortaleza'] ?? 0) as num) > 0)
                  Text('↑${x['votosFortaleza'] ?? 0}  ↓${x['votosMejora'] ?? 0}   ',
                      style: TextStyle(fontSize: 11, color: cessumMuted(context), fontWeight: FontWeight.w700)),
                Text('${x['tasa']} %', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (((x['tasa'] ?? 0) as num).toDouble() / maxT).clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: cessumMuted(context).withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(((x['indice'] ?? 1) as num) >= 1.2 ? cessumRed : cessumGold),
                ),
              ),
            ]),
          ),
        if (((_d['votos'] as Map?)?['respuestas'] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                '↑ votos «lo que más me ayudó» · ↓ votos «puede mejorar» (${(_d['votos'] as Map)['respuestas']} respuestas del cuestionario nuevo; '
                '${(_d['votos'] as Map)['ninguna']} sin sugerencia).',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ),
        // (25-sep) Aula virtual según los alumnos (bloque T, Sí/No).
        _titulo('Aula virtual según los alumnos (% de «No»)'),
        for (final t in _lista(_d['aula']).take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(children: [
              Expanded(child: Text('${t['clave']} · ${t['elemento']}', style: const TextStyle(fontSize: 12.5))),
              Text('${t['tasaNo']} %  (${t['no']} de ${t['n']})',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: ((t['tasaNo'] ?? 0) as num) >= 5 ? cessumRed : null)),
            ]),
          ),
        _titulo('Programas × dimensiones (% de respuestas por debajo de 5)'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 30,
            dataRowMaxHeight: 38,
            columnSpacing: 10,
            horizontalMargin: 6,
            columns: [
              const DataColumn(label: Text('Programa', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800))),
              const DataColumn(label: Text('Total', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800))),
              for (final n in dimNombres) DataColumn(label: Text(n, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
            ],
            rows: [
              for (final p in progs)
                DataRow(cells: [
                  DataCell(SizedBox(
                      width: 170,
                      child: Text('${p['programa']} (${p['evaluaciones']})', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
                  _celdaCalor(p['tasa']),
                  for (final v in ((p['dims'] as List?) ?? [])) _celdaCalor(v),
                ]),
            ],
          ),
        ),
        _titulo('Tendencia mensual'),
        for (final t in tend)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 64, child: Text('${t['mes']}', style: const TextStyle(fontSize: 12))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (((t['tasa'] ?? 0) as num).toDouble() / 30).clamp(0.0, 1.0),
                    minHeight: 9,
                    backgroundColor: cessumMuted(context).withValues(alpha: 0.12),
                    valueColor: const AlwaysStoppedAnimation(cessumRed),
                  ),
                ),
              ),
              SizedBox(
                  width: 110,
                  child: Text('  ${t['tasa']} % · ${t['evaluaciones']} eval.', style: const TextStyle(fontSize: 12))),
            ]),
          ),
        _titulo('Dificultad percibida'),
        Text('${dif['lectura'] ?? ''}${dif['media'] != null ? ' Dificultad media: ${dif['media']} de 10.' : ''}',
            style: const TextStyle(fontSize: 13, height: 1.4)),
        _titulo('Método'),
        Text('${_d['metodo'] ?? ''}', style: TextStyle(fontSize: 12, height: 1.45, color: cessumMuted(context))),
        const SizedBox(height: 20),
      ]),
    );
  }

  DataCell _celdaCalor(dynamic v) {
    final n = (v is num) ? v.toDouble() : 0.0;
    final a = (n / 30).clamp(0.0, 1.0);
    return DataCell(Container(
      width: 40,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.06 + a * 0.6), borderRadius: BorderRadius.circular(4)),
      child: Text(n == 0 ? '0' : n.toStringAsFixed(n >= 10 ? 0 : 1),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: a > 0.5 ? Colors.white : null)),
    ));
  }

  // ---- 2. Docentes ----
  Widget _tabDocentes() {
    final todos = _lista(_d['docentes']);
    final segs = Map<String, dynamic>.from((_d['segmentos'] as Map?) ?? {});
    final q = _busca.text.trim().toLowerCase();
    final vis = todos.where((x) {
      if (_seg != 'todos' && x['segmento'] != _seg) return false;
      if (q.isEmpty) return true;
      return '${x['docente']} ${((x['materias'] as List?) ?? []).join(' ')} ${((x['programas'] as List?) ?? []).join(' ')}'.toLowerCase().contains(q);
    }).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      TextField(
        controller: _busca,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.search),
          hintText: 'Buscar docente, materia o programa…',
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ChoiceChip(label: Text('Todos (${todos.length})'), selected: _seg == 'todos', onSelected: (_) => setState(() => _seg = 'todos')),
        for (final s in const ['Atención prioritaria', 'Seguimiento', 'Estable', 'Referente', 'Evidencia insuficiente'])
          if ((segs[s] ?? 0) > 0)
            ChoiceChip(label: Text('$s (${segs[s]})'), selected: _seg == s, onSelected: (_) => setState(() => _seg = s)),
      ]),
      const SizedBox(height: 10),
      for (final x in vis) _tarjetaDocente(x),
    ]);
  }

  Widget _tarjetaDocente(Map<String, dynamic> x) {
    final s = '${x['segmento']}';
    final c = _colorSeg(s);
    final ic = (x['ic'] as List?) ?? [];
    final peores = _lista(x['peores']);
    final tend = _lista(x['tendencia']);
    final opd = Map<String, dynamic>.from((x['operacionDims'] as Map?) ?? {});
    const nomOp = {'revision': 'revisión', 'retro': 'retroalimentación', 'aula': 'aula', 'sesiones': 'sesiones'};
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${x['docente']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(s, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
          ),
        ]),
        Text('${x['evaluaciones']} evaluaciones · ${((x['programas'] as List?) ?? []).join(', ')}',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 4, children: [
          Text('Tasa: ${x['tasa']} %${ic.length == 2 ? ' (IC ${ic[0]}–${ic[1]} %)' : ''}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          Text('Ajustada: ${x['tasaAjustada']} %', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: c)),
          if (x['operacion'] != null)
            Text('Operación: ${x['operacion']}/100', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          if (x['dificultad'] != null) Text('Dificultad: ${x['dificultad']}/10', style: const TextStyle(fontSize: 12.5)),
        ]),
        if ('${x['cuadrante'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Cruce clase × operación: ${x['cuadrante']}'
                '${opd.isNotEmpty ? ' (${opd.entries.map((e) => '${nomOp[e.key] ?? e.key} ${e.value}').join(', ')})' : ''}',
                style: const TextStyle(fontSize: 12, color: _azul, fontWeight: FontWeight.w600)),
          ),
        if (peores.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Más bajas: ${peores.map((p) => '${p['dimension']} (${p['tasa']} %)').join(' · ')}',
                style: const TextStyle(fontSize: 12.3, height: 1.35, color: cessumRed)),
          ),
        if (x['aulaTasaNo'] != null && ((x['aulaTasaNo'] as num) > 0))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'Aula virtual: ${x['aulaTasaNo']} % de «No»'
                '${((x['aulaFaltantes'] as List?) ?? []).isNotEmpty ? ' · señalan: ${(x['aulaFaltantes'] as List).join(', ')}' : ''}',
                style: const TextStyle(fontSize: 12, color: _azul, height: 1.35)),
          ),
        if (((x['votosMejora'] as List?) ?? []).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Sus alumnos dicen que puede mejorar en: ${(x['votosMejora'] as List).join(', ')}',
                style: const TextStyle(fontSize: 12, color: cessumGold, fontWeight: FontWeight.w700, height: 1.35)),
          ),
        if (tend.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Por mes: ${tend.map((t) => '${t['mes']} ${t['tasa']} %').join(' → ')}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: cessumGold, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => _planDocente(x),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Plan de mejora con IA'),
          ),
        ),
      ]),
    );
  }

  // ---- 3. Decisiones ----
  Widget _tabDecisiones() {
    final reglas = _lista(_d['decisionesReglas']);
    final ia = _ia;
    return ListView(padding: const EdgeInsets.all(14), children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.auto_awesome, color: cessumGold),
            SizedBox(width: 8),
            Expanded(child: Text('Análisis con IA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 4),
          Text('Lee el diagnóstico completo y los comentarios de los alumnos; propone decisiones priorizadas con evidencia, meta y riesgo.',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: _iaCargando ? null : () => _cargarIa(),
              icon: _iaCargando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.psychology, size: 18),
              label: Text(_iaCargando ? 'Analizando… (1-3 min)' : (ia == null ? 'Generar análisis' : 'Ver análisis')),
            ),
            if (ia != null)
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                onPressed: _iaCargando ? null : () => _cargarIa(rehacer: true),
                child: const Text('Rehacer'),
              ),
          ]),
          if (_iaError.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_iaError, style: const TextStyle(color: cessumRed))),
        ]),
      ),
      if (ia != null) ...[
        _titulo('Diagnóstico${ia['guardado'] == true ? ' (generado ${ia['generado']})' : ''}'),
        Text('${ia['diagnostico'] ?? ''}', style: const TextStyle(fontSize: 13.5, height: 1.5)),
        if (((ia['alertas'] as List?) ?? []).isNotEmpty) ...[
          _titulo('Alertas'),
          for (final a in (ia['alertas'] as List))
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
              child: Text('$a', style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
        ],
        _titulo('Lo que dicen los alumnos (temas de los comentarios)'),
        for (final t in _lista(ia['temas']))
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: (t['tono'] == 'negativo' ? cessumRed : t['tono'] == 'positivo' ? _verde : cessumGold).withValues(alpha: 0.5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t['tema']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              Text('Tono ${t['tono']} · frecuencia ${t['frecuencia']}${((t['docentes'] as List?) ?? []).isNotEmpty ? ' · ${(t['docentes'] as List).join(', ')}' : ''}',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              if ('${t['ejemplo'] ?? ''}'.isNotEmpty)
                Text('«${t['ejemplo']}»', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, height: 1.4)),
            ]),
          ),
        _titulo('Decisiones propuestas por la IA'),
        for (final x in _lista(ia['decisiones'])) _tarjetaDecision(x, 'ia'),
      ],
      _titulo('Decisiones por reglas (del diagnóstico estadístico)'),
      for (final x in reglas) _tarjetaDecision(x, 'reglas'),
      const SizedBox(height: 20),
    ]);
  }

  Widget _tarjetaDecision(Map<String, dynamic> x, String origen) {
    final pr = '${x['prioridad'] ?? ''}';
    final c = pr == 'Alta' ? cessumRed : pr == 'Media' ? cessumGold : _azul;
    final ya = _adoptadas.contains('${x['titulo']}') || _decisiones.any((d) => d['titulo'] == x['titulo'] && d['estado'] != 'Descartada');
    Widget fila(String k, dynamic v) => '${v ?? ''}'.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 3),
            child: RichText(
              text: TextSpan(style: TextStyle(fontSize: 12.5, height: 1.4, color: Theme.of(context).textTheme.bodyMedium?.color), children: [
                TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '$v'),
              ]),
            ),
          );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${x['titulo']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Text('$pr · ${x['tipo'] ?? ''}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
        ]),
        fila('Para', x['dirigidoA']),
        fila('Evidencia', x['evidencia']),
        fila('Acción', x['accion']),
        fila('Indicador', x['indicador']),
        fila('Meta', x['meta']),
        fila('Plazo', x['plazo']),
        fila('Riesgo', x['riesgo']),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: ya
              ? const Text('✓ Adoptada', style: TextStyle(color: _verde, fontWeight: FontWeight.w800))
              : FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: cessumRed, visualDensity: VisualDensity.compact),
                  onPressed: () => _adoptar(x, origen),
                  icon: const Icon(Icons.task_alt, size: 16),
                  label: const Text('Adoptar decisión'),
                ),
        ),
      ]),
    );
  }

  // ---- 4. Seguimiento ----
  Widget _tabSeguimiento() {
    if (_segCargando && _decisiones.isEmpty) return const Center(child: CircularProgressIndicator(color: cessumRed));
    return RefreshIndicator(
      onRefresh: _cargarSeguimiento,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        Text(
          'Decisiones adoptadas y su efecto: se compara la línea base (al adoptarla) con las evaluaciones que llegaron después. '
          'Se mide cuando hay al menos 24 respuestas nuevas.',
          style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumMuted(context)),
        ),
        const SizedBox(height: 10),
        if (_decisiones.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
                child: Text('Aún no hay decisiones adoptadas. Adóptelas desde la pestaña «Decisiones».',
                    textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context)))),
          ),
        for (final x in _decisiones) _tarjetaSeguimiento(x),
      ]),
    );
  }

  Widget _tarjetaSeguimiento(Map<String, dynamic> x) {
    final ef = Map<String, dynamic>.from((x['efecto'] as Map?) ?? {});
    final est = '${x['estado']}';
    final lect = '${ef['lectura'] ?? ''}';
    final Color cEf = lect == 'Mejoró' ? _verde : lect == 'Empeoró' ? cessumRed : Colors.grey;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${x['titulo']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          DropdownButton<String>(
            value: const ['Pendiente', 'En curso', 'Cumplida', 'Descartada'].contains(est) ? est : 'Pendiente',
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumRed),
            items: const ['Pendiente', 'En curso', 'Cumplida', 'Descartada']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) {
              if (v != null && v != est) _actualizar(x, estado: v);
            },
          ),
        ]),
        Text('${x['id']} · ${x['fecha']} · ${x['tipo']} · ${x['prioridad']} · ${x['responsable']}',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 4),
        Text('${x['accion']}', style: const TextStyle(fontSize: 12.8, height: 1.4)),
        if ('${x['meta']}'.isNotEmpty)
          Text('Meta: ${x['meta']} · Plazo: ${x['plazo']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: cEf.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
          child: Text(
            ef['despues'] != null
                ? 'Efecto: ${ef['antes']} % → ${ef['despues']} % (${(ef['cambio'] as num) > 0 ? '+' : ''}${ef['cambio']} puntos) · $lect · ${ef['evaluaciones']} evaluaciones después'
                : 'Línea base: ${ef['antes'] ?? '—'} % · $lect (${ef['evaluaciones'] ?? 0} evaluaciones después)',
            style: TextStyle(fontSize: 12.3, fontWeight: FontWeight.w700, color: cEf),
          ),
        ),
        if ('${x['notas']}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${x['notas']}', style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: cessumRed, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => _actualizar(x),
            icon: const Icon(Icons.note_add_outlined, size: 16),
            label: const Text('Agregar nota'),
          ),
        ),
      ]),
    );
  }
}
