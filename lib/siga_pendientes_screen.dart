// SIGA · ALUMNOS PENDIENTES (22-sep-2026)
//
// Los alumnos del reporte que se va a entregar a los que les falta la CURP o,
// si son de nuevo ingreso, el promedio del nivel anterior. Se captura aquí
// mismo; la CURP se valida con la regla de la SEC (la de su Verificador) antes
// de guardarla. Se abre desde la Cabina SIGA con el ciclo y la carga elegidos.
//   GET  siga_pendientes_alumnos&actor&ciclo&carga[&origen][&programa]
//   POST curp_guardar {actor, matricula, curp, origen}
//   GET  promedio_ingreso_guardar&actor&matricula&promedio
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'curp_aviso.dart' show reCurpSec, UpperCaseTextFormatter;

class SigaPendientesScreen extends StatefulWidget {
  final String ciclo;
  final String carga;
  final bool inicio;
  final String programa;
  const SigaPendientesScreen({
    super.key,
    required this.ciclo,
    required this.carga,
    this.inicio = false,
    this.programa = '',
  });
  @override
  State<SigaPendientesScreen> createState() => _SigaPendientesScreenState();
}

class _SigaPendientesScreenState extends State<SigaPendientesScreen> {
  String _actor = '';
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  final _cBuscar = TextEditingController();
  final Map<String, TextEditingController> _cCurp = {};
  final Map<String, TextEditingController> _cProm = {};
  final Set<String> _guardando = {};
  final Set<String> _curpListas = {};
  final Set<String> _promListos = {};
  String _filtro = 'todos'; // todos · curp · promedio

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _cBuscar.dispose();
    for (final c in _cCurp.values) {
      c.dispose();
    }
    for (final c in _cProm.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _iniciar() async {
    // Correo REAL del administrador: en «Ver como profesor», validEmail() da el del profesor y SIGA lo rechazaría.
    _actor = ((await SessionStore.realEmail()) ?? '').trim().toLowerCase();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final qp = {
        'accion': 'siga_pendientes_alumnos',
        'actor': _actor,
        'ciclo': widget.ciclo,
        'carga': widget.carga,
        if (widget.inicio) 'origen': 'asignaciones',
        if (widget.programa.isNotEmpty) 'programa': widget.programa,
      };
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: qp))
          .timeout(const Duration(minutes: 3));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo consultar');
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? cessumRed : const Color(0xFF1E7F52),
    ));
  }

  Future<void> _guardarCurp(String mat) async {
    final curp = (_cCurp[mat]?.text ?? '').trim().toUpperCase();
    if (!reCurpSec.hasMatch(curp)) {
      _msg('Esa CURP no es válida para la SEC: revise fecha, sexo (H/M) y estado.', error: true);
      return;
    }
    setState(() => _guardando.add('c$mat'));
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'curp_guardar',
                'actor': _actor,
                'matricula': mat,
                'curp': curp,
                'origen': 'Vicerrectoría (Cabina SIGA)',
              }))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        setState(() => _curpListas.add(mat));
        _msg('CURP guardada.');
      } else {
        _msg('${d['error'] ?? 'No se pudo guardar.'}', error: true);
      }
    } catch (_) {
      _msg('No me pude conectar. Intente de nuevo.', error: true);
    }
    if (mounted) setState(() => _guardando.remove('c$mat'));
  }

  Future<void> _guardarPromedio(String mat) async {
    final v = double.tryParse((_cProm[mat]?.text ?? '').trim().replaceAll(',', '.'));
    if (v == null || v <= 0 || v > 100) {
      _msg('Escriba un número de 0 a 10 (o de 0 a 100).', error: true);
      return;
    }
    setState(() => _guardando.add('p$mat'));
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'promedio_ingreso_guardar',
            'actor': _actor,
            'matricula': mat,
            'promedio': '$v',
          }))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        setState(() => _promListos.add(mat));
        _msg('Promedio guardado: ${d['promedio']}.');
      } else {
        _msg('${d['error'] ?? 'No se pudo guardar.'}', error: true);
      }
    } catch (_) {
      _msg('No me pude conectar. Intente de nuevo.', error: true);
    }
    if (mounted) setState(() => _guardando.remove('p$mat'));
  }

  @override
  Widget build(BuildContext context) {
    final todos = ((_d['alumnos'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final q = _cBuscar.text.trim().toLowerCase();
    final lista = todos.where((a) {
      final mat = '${a['matricula']}';
      final faltaC = a['faltaCurp'] == true && !_curpListas.contains(mat);
      final faltaP = a['faltaPromedio'] == true && !_promListos.contains(mat);
      if (!faltaC && !faltaP) return false;
      if (_filtro == 'curp' && !faltaC) return false;
      if (_filtro == 'promedio' && !faltaP) return false;
      return q.isEmpty ||
          '${a['nombre']} ${a['matricula']} ${a['programa']} ${a['generacion']}'.toLowerCase().contains(q);
    }).toList();
    final hechos = _curpListas.length + _promListos.length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text('Pendientes SIGA · ${widget.ciclo} carga ${widget.carga}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Volver a consultar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: cessumRed),
                  SizedBox(height: 14),
                  Text('Armando la lista de Alumnos del reporte…', textAlign: TextAlign.center),
                ]),
              ),
            )
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off, size: 42, color: cessumGold),
                      const SizedBox(height: 12),
                      Text(_error, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: cessumRed),
                        onPressed: _cargar,
                        child: const Text('Reintentar'),
                      ),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 30), children: [
                  _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_d['pendientes'] ?? 0} de ${_d['alumnosEnElReporte'] ?? 0} alumnos del reporte tienen algo pendiente',
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    // (23-sep) Con qué criterio se armó la lista: inicio de periodo y calificaciones dan conjuntos distintos.
                    if ('${_d['modo'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('Criterio: ${_d['modo']}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cessumGold)),
                      ),
                    Text(
                      '${_d['sinCurp'] ?? 0} sin CURP válida · ${_d['sinPromedio'] ?? 0} de nuevo ingreso sin promedio del nivel anterior'
                      '${hechos > 0 ? ' · $hechos capturado(s) en esta sesión' : ''}.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      for (final f in const [['todos', 'Todos'], ['curp', 'Sin CURP'], ['promedio', 'Sin promedio']])
                        ChoiceChip(
                          label: Text(f[1]),
                          selected: _filtro == f[0],
                          selectedColor: cessumRed.withValues(alpha: 0.15),
                          onSelected: (_) => setState(() => _filtro = f[0]),
                        ),
                    ]),
                  ])),
                  TextField(
                    controller: _cBuscar,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Buscar por nombre, matrícula, programa o generación',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  if (lista.isEmpty)
                    _caja(const Text('Nada pendiente con este filtro.'))
                  else
                    ...lista.map(_fila),
                ]),
    );
  }

  Widget _caja(Widget hijo) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
        ),
        child: hijo,
      );

  Widget _fila(Map<String, dynamic> a) {
    final mat = '${a['matricula']}';
    final faltaC = a['faltaCurp'] == true && !_curpListas.contains(mat);
    final faltaP = a['faltaPromedio'] == true && !_promListos.contains(mat);
    final cc = _cCurp.putIfAbsent(mat, () => TextEditingController());
    final cp = _cProm.putIfAbsent(mat, () => TextEditingController());
    return _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('${a['nombre']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
        Text(mat, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      ]),
      Text('${a['programa']} ${a['generacion']}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
      if (faltaC) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: cc,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                UpperCaseTextFormatter(),
                FilteringTextInputFormatter.allow(RegExp('[A-Z0-9]')),
                LengthLimitingTextInputFormatter(18),
              ],
              decoration: const InputDecoration(isDense: true, labelText: 'CURP', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: _guardando.contains('c$mat') ? null : () => _guardarCurp(mat),
            child: _guardando.contains('c$mat')
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Guardar'),
          ),
        ]),
      ],
      if (faltaP) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: cp,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(
                  isDense: true, labelText: 'Promedio del nivel anterior (0-10)', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumGold),
            onPressed: _guardando.contains('p$mat') ? null : () => _guardarPromedio(mat),
            child: _guardando.contains('p$mat')
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Guardar'),
          ),
        ]),
      ],
    ]));
  }
}
