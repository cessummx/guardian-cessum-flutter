import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Comparativo de generaciones: evolución de matrícula, promedio y tasa de
/// aprobación generación tras generación.
class ComparativoGeneracionesScreen extends StatefulWidget {
  const ComparativoGeneracionesScreen({super.key});

  @override
  State<ComparativoGeneracionesScreen> createState() =>
      _ComparativoGeneracionesScreenState();
}

class _ComparativoGeneracionesScreenState
    extends State<ComparativoGeneracionesScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String? _error;
  int _aprobatoria = 6;
  List<Map<String, dynamic>> _gen = [];

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
          .get(Uri.parse('$guardianUrl?accion=comparativo_generaciones'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _aprobatoria = (data['aprobatoria'] ?? 6) as int;
        _gen = ((data['generaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el comparativo.';
      });
    }
  }

  void _copiarExcel() {
    final sb = StringBuffer();
    sb.writeln('Generación\tAlumnos\tPromedio\tAprobación %\tCalificaciones');
    for (final g in _gen) {
      sb.writeln('${g['generacion']}\t${g['alumnos'] ?? 0}\t'
          '${g['promedio'] ?? ''}\t${g['tasaAprob'] ?? ''}\t'
          '${g['calificaciones'] ?? 0}');
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
        title: const Text('Comparativo de generaciones',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Copiar para Excel',
            onPressed: _gen.isEmpty ? null : _copiarExcel,
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
              : _gen.isEmpty
                  ? const Center(
                      child: Text('Sin datos de generaciones.',
                          style: TextStyle(color: Colors.black54)))
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 2, bottom: 10),
                            child: Text(
                              'De la generación más antigua a la más reciente.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                          ),
                          ..._gen.map(_tarjeta),
                        ],
                      ),
                    ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> g) {
    final prom = g['promedio'];
    final tasa = g['tasaAprob'];
    final alumnos = (g['alumnos'] ?? 0) as int;
    final calif = (g['calificaciones'] ?? 0) as int;
    final promD = (prom is num) ? prom.toDouble() : 0.0;
    final colorProm = promD >= _aprobatoria ? _verde : cessumRed;
    final tasaI = (tasa is num) ? tasa.toInt() : null;
    final colorTasa = tasaI == null
        ? Colors.black45
        : (tasaI >= 80 ? _verde : (tasaI >= 60 ? cessumGold : cessumRed));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Generación ${g['generacion']}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$alumnos alumnos',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cessumRed)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Promedio',
                          style: TextStyle(
                              fontSize: 11, color: Colors.black54)),
                      Text(prom == null ? '—' : '$prom',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: colorProm)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Aprobación',
                          style: TextStyle(
                              fontSize: 11, color: Colors.black54)),
                      Text(tasaI == null ? '—' : '$tasaI%',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: colorTasa)),
                    ],
                  ),
                ),
              ],
            ),
            if (tasaI != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (tasaI / 100).clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(colorTasa),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text('$calif calificaciones registradas',
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
          ],
        ),
      ),
    );
  }
}
