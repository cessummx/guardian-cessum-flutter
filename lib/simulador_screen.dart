// SIMULADOR DE GRUPOS (22-sep-2026)
//
// Antes de abrir un grupo: cuántos alumnos lo sostienen, qué cuesta en
// docentes, qué deja y qué pasa si se cae una parte. Todo sale del plan de
// pagos, del tabulador docente, de las cartas descriptivas y de las bajas
// reales de generaciones pasadas. Si falta un dato, la pantalla lo dice en
// lugar de inventarlo. Solo lectura.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class SimuladorScreen extends StatefulWidget {
  const SimuladorScreen({super.key});
  @override
  State<SimuladorScreen> createState() => _SimuladorScreenState();
}

class _SimuladorScreenState extends State<SimuladorScreen> {
  String _actor = '';
  bool _cargandoCat = true;
  List<Map<String, dynamic>> _programas = [];
  String? _programa;
  String _modalidad = 'sabatino';
  int _alumnos = 12;
  int _caida = 20;
  final _cGen = TextEditingController();
  bool _calculando = false;
  String _error = '';
  Map<String, dynamic>? _r;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _cGen.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp) async {
    final r = await http
        .get(Uri.parse(guardianUrl).replace(queryParameters: {...qp, 'actor': _actor}))
        .timeout(const Duration(seconds: 90));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _iniciar() async {
    _actor = ((await SessionStore.validEmail()) ?? '').trim().toLowerCase();
    try {
      final d = await _get({'accion': 'simulador_grupo'});
      if (!mounted) return;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cargar');
      setState(() {
        _programas = ((d['programas'] as List?) ?? [])
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList()
          ..sort((a, b) => '${a['programa']}'.compareTo('${b['programa']}'));
        _cargandoCat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoCat = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _calcular() async {
    if (_programa == null) return;
    setState(() {
      _calculando = true;
      _error = '';
    });
    try {
      final d = await _get({
        'accion': 'simulador_grupo',
        'programa': _programa!,
        'modalidad': _modalidad,
        'alumnos': '$_alumnos',
        'caida': '$_caida',
        if (_cGen.text.trim().isNotEmpty) 'generacion': _cGen.text.trim(),
      });
      if (!mounted) return;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo calcular');
      setState(() {
        _r = d;
        _calculando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _calculando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /// Selector de programa con buscador.
  Future<void> _elegirPrograma() async {
    final elegido = await showDialog<String>(
      context: context,
      builder: (ctx) {
        var filtro = '';
        return StatefulBuilder(builder: (ctx2, setD) {
          final lista = _programas.where((p) =>
              '${p['programa']}'.toLowerCase().contains(filtro.toLowerCase())).toList();
          return AlertDialog(
            title: const Text('Programa', style: TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 440,
              height: 380,
              child: Column(children: [
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar programa',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (v) => setD(() => filtro = v),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: lista
                        .map((p) => ListTile(
                              dense: true,
                              title: Text('${p['programa']}',
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              subtitle: Text('${p['materias']} materias · ${p['meses']} meses',
                                  style: const TextStyle(fontSize: 11.5)),
                              onTap: () => Navigator.pop(ctx2, '${p['programa']}'),
                            ))
                        .toList(),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('Cancelar')),
            ],
          );
        });
      },
    );
    if (elegido != null) {
      setState(() {
        _programa = elegido;
        _r = null;
      });
      _calcular();
    }
  }

  static String _m(dynamic v) {
    final x = (v is num ? v : num.tryParse('$v') ?? 0).toDouble();
    final s = x.abs().round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${x < 0 ? '-' : ''}\$$b';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Simulador de grupos'),
      ),
      body: _cargandoCat
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 30), children: [
              _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Supuestos', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _elegirPrograma,
                  icon: const Icon(Icons.school_outlined, size: 18),
                  label: Text(_programa ?? 'Elegir programa'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in const ['entre semana', 'sabatino', 'mixta'])
                      ChoiceChip(
                        label: Text(m),
                        selected: _modalidad == m,
                        onSelected: (_) {
                          setState(() => _modalidad = m);
                          _calcular();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 110, child: Text('Alumnos', style: TextStyle(fontSize: 13))),
                  Expanded(
                    child: Slider(
                      value: _alumnos.toDouble(),
                      min: 1,
                      max: 40,
                      divisions: 39,
                      activeColor: cessumRed,
                      label: '$_alumnos',
                      onChanged: (v) => setState(() => _alumnos = v.round()),
                      onChangeEnd: (_) => _calcular(),
                    ),
                  ),
                  SizedBox(width: 34, child: Text('$_alumnos', textAlign: TextAlign.right)),
                ]),
                Row(children: [
                  const SizedBox(width: 110, child: Text('Si se cae el', style: TextStyle(fontSize: 13))),
                  Expanded(
                    child: Slider(
                      value: _caida.toDouble(),
                      min: 0,
                      max: 60,
                      divisions: 12,
                      activeColor: cessumGold,
                      label: '$_caida %',
                      onChanged: (v) => setState(() => _caida = v.round()),
                      onChangeEnd: (_) => _calcular(),
                    ),
                  ),
                  SizedBox(width: 34, child: Text('$_caida%', textAlign: TextAlign.right)),
                ]),
                TextField(
                  controller: _cGen,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Generación (opcional, para la mensualidad de ese plan)',
                    hintText: 'Ej. 26-4',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onSubmitted: (_) => _calcular(),
                ),
              ])),
              if (_error.isNotEmpty)
                _tarjeta(Text(_error, style: const TextStyle(color: cessumRed)), borde: cessumRed),
              if (_calculando)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(color: cessumRed)),
                ),
              if (_r != null && !_calculando) ..._resultados(),
            ]),
    );
  }

  Widget _tarjeta(Widget hijo, {Color? borde}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: (borde ?? cessumGold).withValues(alpha: 0.30)),
        ),
        child: hijo,
      );

  Widget _cifra(String t, String v, Color c) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(fontSize: 10.5, color: c)),
            Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c)),
          ]),
        ),
      );

  List<Widget> _resultados() {
    final r = _r!;
    final plan = Map<String, dynamic>.from(r['plan'] as Map);
    final doc = Map<String, dynamic>.from(r['docente'] as Map);
    final esc = Map<String, dynamic>.from(r['escenarios'] as Map);
    final eq = Map<String, dynamic>.from(r['equilibrio'] as Map);
    final ret = Map<String, dynamic>.from(r['retencion'] as Map);
    final faltan = ((r['faltan'] as List?) ?? []).map((f) => '$f').toList();
    final verde = const Color(0xFF1E7F52);
    Widget escenario(String titulo, Map<String, dynamic>? e, {String? pie}) {
      if (e == null) return const SizedBox.shrink();
      final margen = (e['margen'] as num?)?.toDouble() ?? 0;
      return _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Row(children: [
          _cifra('Ingreso del grupo', _m(e['ingreso']), verde),
          _cifra('Costo docente', _m(doc['total']), cessumRed),
          _cifra('Margen', _m(margen), margen >= 0 ? verde : cessumRed),
        ]),
        if (pie != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(pie, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ),
      ]), borde: margen >= 0 ? verde : cessumRed);
    }

    final gens = ((ret['generaciones'] as List?) ?? [])
        .map((g) => Map<String, dynamic>.from(g as Map))
        .toList();
    return [
      if (faltan.isNotEmpty)
        _tarjeta(
          Text('Faltan datos, y sin ellos el resultado no vale: ${faltan.join(' · ')}.',
              style: const TextStyle(fontSize: 12.5, color: cessumRed, fontWeight: FontWeight.w700)),
          borde: cessumRed,
        ),
      _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${r['programa']} · ${r['modalidad']} · ${r['alumnos']} alumnos',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          '${plan['materias']} materias en ${plan['meses']} meses · mensualidad ${_m(plan['mensualidad'])} · '
          'cada alumno deja ${_m(plan['ingresoPorAlumno'])} en todo el programa.\n'
          'Docente: ${_m(doc['porMateria'])} por materia (${doc['regla']}).',
          style: const TextStyle(fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _cifra('Punto de equilibrio', '${eq['alumnos'] ?? '—'} alumnos', cessumGold),
          _cifra('Con caída del ${esc['caida']?['pct']}%', '${eq['conCaida'] ?? '—'} alumnos', cessumGold),
        ]),
      ])),
      escenario('Si todos terminan', esc['completo'] is Map ? Map<String, dynamic>.from(esc['completo']) : null),
      escenario('Si se cae el ${esc['caida']?['pct']}%',
          esc['caida'] is Map ? Map<String, dynamic>.from(esc['caida']) : null,
          pie: 'Quien se da de baja se cuenta como si pagara la mitad del programa.'),
      escenario('Con la tasa histórica de bajas de este programa (${ret['tasaBajas'] ?? '—'}%)',
          esc['historico'] is Map ? Map<String, dynamic>.from(esc['historico']) : null,
          pie: ret['base'] != null && (ret['base'] as num) > 0
              ? 'Calculada sobre ${ret['base']} alumnos de generaciones anteriores.'
              : 'Sin generaciones anteriores con datos suficientes.'),
      if (gens.isNotEmpty)
        _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Bajas reales por generación',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          ...gens.map((g) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${g['generacion']}: ${g['bajas']} de ${g['alumnos']} (${g['pct']}%)',
                    style: const TextStyle(fontSize: 12.5)),
              )),
        ])),
      Text('${r['nota']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
    ];
  }
}
