import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'csv_export.dart';

/// Panel de administrador: aprobación/reprobación por materia y por docente.
class GraficasAprobacionScreen extends StatefulWidget {
  const GraficasAprobacionScreen({super.key});

  @override
  State<GraficasAprobacionScreen> createState() =>
      _GraficasAprobacionScreenState();
}

class _GraficasAprobacionScreenState extends State<GraficasAprobacionScreen>
    with SingleTickerProviderStateMixin {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _materias = [];
  List<Map<String, dynamic>> _docentes = [];
  int _aprobatoria = 7;
  late TabController _tab;
  // (24-sep) Buscador por materia o docente.
  final _busca = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tab.dispose();
    _busca.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final correo = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'aprobacion_stats',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      if (!mounted) return;
      setState(() {
        _materias = ((data['materias'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _docentes = ((data['docentes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _aprobatoria = (data['aprobatoria'] ?? 7) is int
            ? data['aprobatoria'] as int
            : 7;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar ($e)';
      });
    }
  }

  void _exportar(String cual, List<Map<String, dynamic>> lista) {
    final filas = lista
        .map((m) => <Object?>[
              m['nombre'] ?? '',
              m['total'] ?? 0,
              m['aprob'] ?? 0,
              m['reprob'] ?? 0,
              '${m['pctReprob'] ?? 0}%',
            ])
        .toList();
    descargarCsv(
      'aprobacion_$cual.csv',
      construirCsv(
          ['Nombre', 'Total', 'Aprobados', 'Reprobados', '% reprob'], filas),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Aprobación / reprobación'),
        actions: [
          IconButton(
            onPressed: _cargando
                ? null
                : () => _tab.index == 0
                    ? _exportar('materias', _materias)
                    : _exportar('docentes', _docentes),
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.download),
          ),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: cessumGold,
          tabs: const [
            Tab(text: 'Por materia'),
            Tab(text: 'Por docente'),
          ],
        ),
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
              : TabBarView(
                  controller: _tab,
                  children: [_lista(_materias), _lista(_docentes)],
                ),
    );
  }

  Widget _lista(List<Map<String, dynamic>> datos) {
    if (datos.isEmpty) {
      return Center(
          child: Text('Sin datos suficientes.',
              style: TextStyle(color: cessumFaint(context))));
    }
    final q = _busca.text.trim().toLowerCase();
    final vis = q.isEmpty
        ? datos
        : datos.where((m) => '${m['nombre'] ?? ''}'.toLowerCase().contains(q)).toList();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        TextField(
          controller: _busca,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar materia o docente…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            suffixIcon: _busca.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _busca.clear())),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Aprobatoria: $_aprobatoria o más. Ordenado por mayor % de reprobación.',
            style: TextStyle(fontSize: 12, color: cessumFaint(context)),
          ),
        ),
        if (vis.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('Nada coincide con la búsqueda.', style: TextStyle(color: cessumMuted(context)))),
          ),
        ...vis.map(_barra),
      ],
    );
  }

  Widget _barra(Map<String, dynamic> m) {
    final total = (m['total'] ?? 0) is int ? m['total'] as int : 0;
    final aprob = (m['aprob'] ?? 0) is int ? m['aprob'] as int : 0;
    final reprob = (m['reprob'] ?? 0) is int ? m['reprob'] as int : 0;
    final pct = (m['pctReprob'] is num) ? (m['pctReprob'] as num).toDouble() : 0.0;
    final fAprob = total > 0 ? aprob / total : 0.0;
    final fReprob = total > 0 ? reprob / total : 0.0;
    final color = pct >= 30
        ? cessumRed
        : (pct >= 10 ? cessumGold : const Color(0xFF1E8E3E));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text((m['nombre'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                // (24-sep) Redondeado: antes salía «33.3333333% reprob.».
                child: Text('${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}% reprob.',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(
                  flex: (fAprob * 1000).round().clamp(0, 1000),
                  child: Container(
                      height: 16, color: const Color(0xFF1E8E3E)),
                ),
                Expanded(
                  flex: (fReprob * 1000).round().clamp(0, 1000),
                  child: Container(height: 16, color: cessumRed),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Total: $total · Aprobados: $aprob · Reprobados: $reprob',
            style: TextStyle(fontSize: 11.5, color: cessumFaint(context)),
          ),
        ],
      ),
    );
  }
}
