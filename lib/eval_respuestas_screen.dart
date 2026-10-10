// VICERRECTORÍA: respuestas de los alumnos, una por una y anónimas.
//
// (ago-22) Hasta ahora el seguimiento docente solo entregaba PROMEDIOS por
// pregunta y tres comentarios. Con eso no se distingue «todos pusieron 5» de
// «casi todos pusieron 5 y uno puso 1», que son dos realidades opuestas y
// piden decisiones distintas. Y los comentarios —lo único que de verdad
// explica un número— se veían recortados a tres.
//
// La hoja de evaluación NO guarda matrícula ni correo: es anónima por diseño.
// Aun así, en un grupo chico una respuesta con su fecha exacta se puede
// atribuir, así que el backend reduce la fecha a MES y oculta las respuestas
// individuales cuando son menos de cuatro. Esta pantalla respeta eso y lo
// dice: no esconde el límite, lo explica.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class EvalRespuestasScreen extends StatefulWidget {
  final String correo;
  final String docente;
  const EvalRespuestasScreen(
      {super.key, required this.correo, required this.docente});

  @override
  State<EvalRespuestasScreen> createState() => _EvalRespuestasScreenState();
}

class _EvalRespuestasScreenState extends State<EvalRespuestasScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  String _materia = '';

  static const Color _ambar = Color(0xFFB07D12);
  static const Color _verde = Color(0xFF1E8E3E);

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
      final q = {
        'accion': 'eval_respuestas_anon',
        'correo': widget.correo,
        'docente': widget.docente,
      };
      if (_materia.isNotEmpty) q['materia'] = _materia;
      final u = Uri.parse(guardianUrl).replace(queryParameters: q);
      final r = await http.get(u).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _preguntas =>
      ((_d['preguntas'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  List<Map<String, dynamic>> get _filas => ((_d['filas'] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  List<Map<String, dynamic>> get _comentarios =>
      ((_d['comentarios'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  List<String> get _materias {
    final s = <String>{};
    for (final f in _filas) {
      final m = (f['materia'] ?? '').toString().trim();
      if (m.isNotEmpty) s.add(m);
    }
    final l = s.toList()..sort();
    return l;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Respuestas de los alumnos'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No se pudo cargar: $_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _cabecera(),
                    if ((_d['nota'] ?? '').toString().isNotEmpty) _nota(),
                    _bloquePreguntas(),
                    _bloqueComentarios(),
                    _bloqueFilas(),
                    const SizedBox(height: 30),
                  ],
                ),
    );
  }

  Widget _cabecera() {
    final n = (_d['respuestas'] ?? 0).toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_d['docente'] ?? widget.docente}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('$n respuesta(s) de alumnos · sin nombre ni matrícula',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (_materias.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip('Todas', _materia.isEmpty, () {
                    setState(() => _materia = '');
                    _cargar();
                  }),
                  for (final m in _materias)
                    _chip(m, _materia == m, () {
                      setState(() => _materia = m);
                      _cargar();
                    }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String t, bool activo, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: activo ? cessumRed : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: activo ? cessumRed : Colors.grey.shade300),
            ),
            child: Text(t,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: activo ? Colors.white : Colors.black87)),
          ),
        ),
      );

  Widget _nota() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _ambar.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _ambar),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 17, color: _ambar),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${_d['nota']}',
              style: const TextStyle(
                  fontSize: 12, height: 1.35, color: Color(0xFF8A5A00))),
        ),
      ]),
    );
  }

  /// Cada pregunta con su promedio Y su distribución. La barra apilada es lo
  /// que hace visible de un golpe si hubo consenso o desacuerdo: un promedio
  /// no distingue entre las dos cosas.
  Widget _bloquePreguntas() {
    final ps = _preguntas;
    if (ps.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CADA CRITERIO Y CÓMO SE REPARTIERON LAS RESPUESTAS',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w800,
                  color: Colors.black45)),
          const SizedBox(height: 10),
          for (final p in ps) _renglonPregunta(p),
          const SizedBox(height: 6),
          const Text(
              'La desviación en 0 significa que todos contestaron exactamente '
              'lo mismo. Un criterio así no está midiendo nada.',
              style: TextStyle(fontSize: 11, color: Colors.black45)),
        ],
      ),
    );
  }

  Widget _renglonPregunta(Map<String, dynamic> p) {
    final dist = Map<String, dynamic>.from(
        (p['distribucion'] as Map?) ?? const <String, dynamic>{});
    final total = (p['respuestas'] ?? 0) is num ? (p['respuestas'] as num) : 0;
    final sinVar = p['sinVariacion'] == true;
    const colores = [
      Color(0xFFB11D29),
      Color(0xFFE65100),
      Color(0xFFB07D12),
      Color(0xFF7CB342),
      _verde,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${p['codigo']} · ${p['texto']}',
                    style: const TextStyle(fontSize: 12.5, height: 1.25)),
              ),
              const SizedBox(width: 8),
              Text('${p['promedio']}',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 9,
              child: Row(
                children: [
                  for (var v = 1; v <= 5; v++)
                    if (((dist['$v'] ?? 0) as num) > 0)
                      Expanded(
                        flex: ((dist['$v'] ?? 0) as num).toInt(),
                        child: Container(color: colores[v - 1]),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
              [
                for (var v = 1; v <= 5; v++)
                  if (((dist['$v'] ?? 0) as num) > 0) '$v: ${dist['$v']}',
              ].join('   ') +
                  '   ·   n=$total   ·   σ=${p['desviacion']}'
                      '${sinVar ? '  ← sin variación' : ''}',
              style: TextStyle(
                  fontSize: 10.5,
                  color: sinVar ? _ambar : Colors.black45,
                  fontWeight: sinVar ? FontWeight.w700 : FontWeight.w400)),
        ],
      ),
    );
  }

  Widget _bloqueComentarios() {
    final cs = _comentarios;
    if (cs.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LO QUE ESCRIBIERON (${cs.length})',
              style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w800,
                  color: Colors.black45)),
          const SizedBox(height: 8),
          // Todos, no tres. El texto es lo que explica el número.
          for (final c in cs)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9),
                border: Border(
                    left: BorderSide(color: cessumGold, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c['texto']}',
                      style: const TextStyle(fontSize: 12.5, height: 1.4)),
                  const SizedBox(height: 3),
                  Text(
                      [
                        (c['materia'] ?? '').toString(),
                        (c['mes'] ?? '').toString(),
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.black45)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bloqueFilas() {
    final fs = _filas;
    if (fs.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RESPUESTA POR RESPUESTA (${fs.length})',
              style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w800,
                  color: Colors.black45)),
          const SizedBox(height: 3),
          const Text(
              'Cada tarjeta es un alumno distinto. No hay nombre ni matrícula, '
              'y la fecha se reduce al mes.',
              style: TextStyle(fontSize: 11, color: Colors.black45)),
          const SizedBox(height: 10),
          for (var i = 0; i < fs.length; i++) _tarjetaFila(i + 1, fs[i]),
        ],
      ),
    );
  }

  Widget _tarjetaFila(int n, Map<String, dynamic> f) {
    final vals = ((f['valores'] as List?) ?? []).toList();
    final numeros = vals.whereType<num>().toList();
    final prom = numeros.isEmpty
        ? null
        : numeros.reduce((a, b) => a + b) / numeros.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: cessumBg(context),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Respuesta $n',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              if (prom != null)
                Text('promedio ${prom.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54)),
            ],
          ),
          Text(
              [
                (f['materia'] ?? '').toString(),
                (f['grupo'] ?? '').toString(),
                (f['generacion'] ?? '').toString(),
                (f['mes'] ?? '').toString(),
              ].where((e) => e.toString().trim().isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 11, color: Colors.black45)),
          if ((f['dificultad'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Dificultad que reportó: ${f['dificultad']}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < vals.length; i++)
                if (vals[i] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _colorValor(vals[i] as num),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                        '${i < 12 ? 'M${i + 1}' : 'T${i - 11}'}:${vals[i]}',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
            ],
          ),
          if ((f['comentario'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text('“${f['comentario']}”',
                style: const TextStyle(
                    fontSize: 12, height: 1.35, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  Color _colorValor(num v) {
    if (v <= 1) return const Color(0xFFB11D29);
    if (v <= 2) return const Color(0xFFE65100);
    if (v <= 3) return const Color(0xFFB07D12);
    if (v <= 4) return const Color(0xFF7CB342);
    return _verde;
  }
}
