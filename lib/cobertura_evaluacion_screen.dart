import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Cobertura de evaluación docente: qué docentes ya tienen evaluación y
/// cuáles faltan, agrupado por programa. Solo lectura.
class CoberturaEvaluacionScreen extends StatefulWidget {
  const CoberturaEvaluacionScreen({super.key});

  @override
  State<CoberturaEvaluacionScreen> createState() =>
      _CoberturaEvaluacionScreenState();
}

class _CoberturaEvaluacionScreenState
    extends State<CoberturaEvaluacionScreen> {
  Map<String, dynamic>? _data;
  bool _cargando = true;
  bool _soloFaltantes = false;
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
          .get(Uri.parse('$guardianUrl?accion=cobertura_evaluacion'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _data = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la cobertura.';
      });
    }
  }

  Color _colorCobertura(num pct) {
    if (pct >= 80) return const Color(0xFF1E8E3E);
    if (pct >= 50) return cessumGold;
    return cessumRed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Cobertura de evaluación',
            style: TextStyle(fontWeight: FontWeight.w600)),
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
    final d = _data!;
    final resumen = (d['resumen'] ?? {}) as Map<String, dynamic>;
    final programas = (d['programas'] as List?) ?? [];
    final coberturaGlobal = (resumen['coberturaGlobal'] ?? 0) as num;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colorCobertura(coberturaGlobal).withValues(alpha: 0.12),
                ),
                child: Text('$coberturaGlobal%',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _colorCobertura(coberturaGlobal))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cobertura global',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      '${resumen['conEvaluacion'] ?? 0} de ${resumen['totalDocentes'] ?? 0} docentes con evaluación registrada',
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.black54, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Solo mostrar pendientes',
                style: TextStyle(fontSize: 13)),
            const Spacer(),
            Switch(
              value: _soloFaltantes,
              activeColor: cessumRed,
              onChanged: (v) => setState(() => _soloFaltantes = v),
            ),
          ],
        ),
        ...programas.map((raw) {
          final p = Map<String, dynamic>.from(raw as Map);
          final docentes = ((p['docentes'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((doc) => !_soloFaltantes || doc['evaluado'] != true)
              .toList();
          if (docentes.isEmpty) return const SizedBox.shrink();
          final cobertura = (p['cobertura'] ?? 0) as num;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${p['programa']}',
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w800)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _colorCobertura(cobertura)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${p['conEvaluacion']}/${p['total']} · $cobertura%',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _colorCobertura(cobertura)),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  ...docentes.map((doc) {
                    final evaluado = doc['evaluado'] == true;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                              evaluado
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 16,
                              color: evaluado
                                  ? const Color(0xFF1E8E3E)
                                  : cessumRed),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${doc['docente']}',
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                          Text(
                            evaluado
                                ? '${doc['evaluaciones']} resp.'
                                : 'Sin evaluación',
                            style: TextStyle(
                                fontSize: 11,
                                color: evaluado
                                    ? Colors.black54
                                    : cessumRed,
                                fontWeight: evaluado
                                    ? FontWeight.w400
                                    : FontWeight.w700),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 24),
      ],
    );
  }
}
