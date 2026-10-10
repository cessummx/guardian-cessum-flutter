import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin: detección "inteligente" de posibles becas a partir del histórico de
/// pagos. Compara lo que paga cada alumno contra el monto normal de su grupo
/// (programa + generación) y marca a quienes pagan de menos, con el % implícito.
class BecasDeteccionScreen extends StatefulWidget {
  const BecasDeteccionScreen({super.key});

  @override
  State<BecasDeteccionScreen> createState() => _BecasDeteccionScreenState();
}

class _BecasDeteccionScreenState extends State<BecasDeteccionScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _alertas = [];
  List<Map<String, dynamic>> _grupos = [];
  final Set<String> _ocultas = {};
  String? _confirmandoMat;
  bool _verGrupos = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? cessumRed : Colors.green));
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'becas_deteccion',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _alertas = ((data['alertas'] as List<dynamic>? ?? []))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _grupos = ((data['grupos'] as List<dynamic>? ?? []))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      _error = '$e'.replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _confirmar(Map<String, dynamic> a) async {
    final mat = (a['matricula'] ?? '').toString();
    setState(() => _confirmandoMat = mat);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'beca_guardar',
                'actor': actor,
                'matricula': mat,
                'nombre': a['nombre'],
                'programa': a['programa'],
                'generacion': a['generacion'],
                'porcentaje': a['porcentaje'],
                'montoOrdinario': a['montoGrupo'],
                'montoBeca': a['montoAlumno'],
                'notas': 'Detectada por histórico de pagos',
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso('Beca registrada para ${a['nombre']}.');
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceAll('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _confirmandoMat = null);
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _alertas
        .where((a) => !_ocultas.contains((a['matricula'] ?? '').toString()))
        .toList();
    final sinBeca = visibles.where((a) => a['tieneBeca'] != true).length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Detección de becas'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off, color: cessumRed, size: 44),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cessumRed,
                          foregroundColor: Colors.white),
                      onPressed: _cargar,
                      child: const Text('Reintentar'),
                    ),
                  ]),
                ))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Se revisó el histórico de pagos. Estos alumnos pagan menos '
                        'que el monto normal de su grupo: confirma si tienen beca y '
                        'con qué porcentaje. ${sinBeca > 0 ? '\n\n$sinBeca por confirmar.' : ''}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => setState(() => _verGrupos = !_verGrupos),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                                _verGrupos
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: cessumRed),
                            const SizedBox(width: 4),
                            Text('Monto normal por grupo (${_grupos.length})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: cessumRed)),
                          ],
                        ),
                      ),
                    ),
                    if (_verGrupos)
                      ..._grupos.map((g) => Padding(
                            padding: const EdgeInsets.only(
                                left: 8, bottom: 6, top: 2),
                            child: Text(
                              '${g['programa']} · Gen. ${g['generacion']} → '
                              'normal \$${g['montoNormal']} '
                              '(${g['alumnos']} alumnos)',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          )),
                    const Divider(height: 24),
                    if (visibles.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text(
                            'No se detectaron pagos por debajo de lo normal.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      ),
                    ...visibles.map(_tarjeta),
                    const SizedBox(height: 30),
                  ],
                ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final mat = (a['matricula'] ?? '').toString();
    final tieneBeca = a['tieneBeca'] == true;
    final porc = a['porcentaje'];
    final becaPorc = a['becaPorcentaje'];
    final becaEstatus = (a['becaEstatus'] ?? '').toString();
    final confirmando = _confirmandoMat == mat;
    // ¿el % registrado coincide con el detectado?
    final coincide = tieneBeca &&
        (becaPorc is num) &&
        (porc is num) &&
        (becaPorc - porc).abs() <= 2 &&
        becaEstatus.toLowerCase() == 'activa';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((a['nombre'] ?? '').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                _badge(a),
              ],
            ),
            Text('$mat · ${a['programa']} · Gen. ${a['generacion']}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Text(
              'Paga \$${a['montoAlumno']}  ·  el grupo paga \$${a['montoGrupo']}',
              style: const TextStyle(fontSize: 13),
            ),
            Text('≈ $porc% de beca implícita (${a['pagosAlumno']} pagos)',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cessumRed)),
            const SizedBox(height: 6),
            if (coincide)
              const Text('Beca ya registrada y coincide. Sin acción.',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF1E8E3E),
                      fontWeight: FontWeight.w600))
            else
              Wrap(
                spacing: 6,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact),
                    icon: confirmando
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(tieneBeca
                        ? 'Actualizar a $porc%'
                        : 'Confirmar beca $porc%'),
                    onPressed: confirmando ? null : () => _confirmar(a),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _ocultas.add(mat)),
                    child: const Text('No es beca'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(Map<String, dynamic> a) {
    final tieneBeca = a['tieneBeca'] == true;
    final estatus = (a['becaEstatus'] ?? '').toString();
    String txt;
    Color color;
    if (!tieneBeca) {
      txt = 'Sin registrar';
      color = cessumGold;
    } else if (estatus.toLowerCase() == 'activa') {
      txt = 'Beca ${a['becaPorcentaje']}%';
      color = const Color(0xFF1E8E3E);
    } else {
      txt = estatus;
      color = Colors.black54;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(txt,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
