import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Tablero de avance programático para administración: cuánto se ha cubierto
/// de cada materia-grupo frente a la meta, ordenado por menor avance.
class AvanceTableroScreen extends StatefulWidget {
  const AvanceTableroScreen({super.key});

  @override
  State<AvanceTableroScreen> createState() => _AvanceTableroScreenState();
}

class _AvanceTableroScreenState extends State<AvanceTableroScreen> {
  Map<String, dynamic>? _data;
  bool _cargando = true;
  bool _procesando = false;
  bool _soloSinMeta = false;
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
          .get(Uri.parse('$guardianUrl?accion=avance_tablero'))
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
        _error = 'No se pudo cargar el tablero.';
      });
    }
  }

  Color _color(int pct, bool conMeta) {
    if (!conMeta) return cessumFaint(context);
    if (pct >= 80) return const Color(0xFF1E8E3E);
    if (pct >= 50) return cessumGold;
    return cessumRed;
  }

  Future<void> _fijarMeta(Map<String, dynamic> m) async {
    final sesiones =
        TextEditingController(text: ((m['meta'] ?? 0) as int).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Meta de sesiones\n${m['materia']}',
            style: const TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Clave ${m['clave']}',
                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            const SizedBox(height: 12),
            TextField(
              controller: sesiones,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sesiones totales planeadas',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Define el total de sesiones del programa para esta materia. Sirve para calcular el % de avance.',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'avance_meta_fijar',
                'clave': m['clave'],
                'materia': m['materia'],
                'sesiones': int.tryParse(sesiones.text.trim()) ?? 0,
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Avance programático',
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
    final todas = ((d['materias'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final materias = _soloSinMeta
        ? todas.where((m) => m['conMeta'] != true).toList()
        : todas;

    return Column(
      children: [
        if (_procesando) const LinearProgressIndicator(color: cessumRed),
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cessumRed.withValues(alpha: 0.10),
                ),
                child: Text('${resumen['avancePromedio'] ?? 0}%',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cessumRed)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Avance promedio',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      '${resumen['conMeta'] ?? 0} de ${resumen['total'] ?? 0} materias-grupo con meta definida',
                      style: TextStyle(
                          fontSize: 12, color: cessumMuted(context), height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('Solo sin meta definida',
                  style: TextStyle(fontSize: 13)),
              const Spacer(),
              Switch(
                value: _soloSinMeta,
                activeThumbColor: cessumRed,
                onChanged: (v) => setState(() => _soloSinMeta = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: materias.isEmpty
              ? Center(
                  child: Text('Sin materias para mostrar.',
                      style: TextStyle(color: cessumMuted(context))),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: materias.length,
                  itemBuilder: (ctx, i) {
                    final m = materias[i];
                    final conMeta = m['conMeta'] == true;
                    final pct = (m['porcentaje'] ?? 0) as int;
                    final color = _color(pct, conMeta);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('${m['materia']}',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    conMeta
                                        ? '$pct% · ${m['registradas']}/${m['meta']}'
                                        : '${m['registradas']} sesiones',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: color),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${m['generacion']} · Grupo ${m['grupo']} · ${m['docente']}',
                              style: TextStyle(
                                  fontSize: 11.5, color: cessumMuted(context)),
                            ),
                            if (conMeta) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: LinearProgressIndicator(
                                  value: pct / 100,
                                  minHeight: 8,
                                  backgroundColor: cessumMuted(context).withValues(alpha: 0.18),
                                  color: color,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if ((m['ultimaActividad'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      'Última: ${m['ultimaActividad']}',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: cessumFaint(context)),
                                    ),
                                  )
                                else
                                  const Expanded(
                                    child: Text('Sin registros aún',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: cessumRed)),
                                  ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact),
                                  onPressed: _procesando
                                      ? null
                                      : () => _fijarMeta(m),
                                  icon: const Icon(Icons.flag, size: 16),
                                  label: Text(
                                      conMeta ? 'Editar meta' : 'Fijar meta',
                                      style: const TextStyle(fontSize: 11.5)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
