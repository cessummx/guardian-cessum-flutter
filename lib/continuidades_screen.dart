import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';

/// Detector global de continuidad de grado: alumnos que aparecen con varias
/// matrículas (maestría↔doctorado). Permite vincularlos como una sola persona,
/// con identidad anclada a la matrícula más antigua. No fusiona calificaciones.
class ContinuidadesScreen extends StatefulWidget {
  const ContinuidadesScreen({super.key});

  @override
  State<ContinuidadesScreen> createState() => _ContinuidadesScreenState();
}

class _ContinuidadesScreenState extends State<ContinuidadesScreen> {
  bool _cargando = true;
  String? _error;
  List<dynamic> _candidatos = [];
  final Set<int> _ocupados = {};

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
      final actor = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'continuidad_candidatos',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      if (!mounted) return;
      setState(() {
        _candidatos = (data['candidatos'] as List?) ?? [];
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

  Future<void> _vincular(int index, Map c) async {
    final ident = (c['identidadSugerida'] ?? '').toString();
    final mats = (c['matriculas'] as List?) ?? [];
    final otras = mats
        .map((e) => (e as Map)['matricula'].toString())
        .where((m) => m != ident)
        .toList();
    if (ident.isEmpty || otras.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vincular como misma persona'),
        content: Text(
          'Se unirán las matrículas de "${c['nombre']}" con identidad en la '
          'más antigua ($ident).\n\nLas calificaciones de cada grado siguen '
          'separadas. ¿Continuar?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vincular'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _ocupados.add(index));
    try {
      final actor = await SessionStore.realEmail() ?? '';
      for (final m in otras) {
        await http
            .post(Uri.parse(guardianUrl),
                headers: {'Content-Type': 'text/plain;charset=utf-8'},
                body: jsonEncode({
                  'accion': 'vincular_matriculas',
                  'actor': actor,
                  'identidad': ident,
                  'vinculada': m,
                  'nombre': c['nombre'],
                }))
            .timeout(const Duration(seconds: 60));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF1E8E3E),
        content: Text('Vinculadas las matrículas de ${c['nombre']}.'),
      ));
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupados.remove(index));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumRed, content: Text('No se pudo: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Continuidad de grado'),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: cessumRed),
                            onPressed: _cargar,
                            child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : _candidatos.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No se detectaron alumnos con varias matrículas '
                          'sin vincular.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cessumGold.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Se encontraron ${_candidatos.length} posible(s) '
                            'continuidad(es). Verifica que sea la misma persona '
                            'antes de vincular; la identidad queda en la '
                            'matrícula más antigua.',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        ...List.generate(_candidatos.length, (i) {
                          final c = _candidatos[i] as Map;
                          final mats = (c['matriculas'] as List?) ?? [];
                          final ident =
                              (c['identidadSugerida'] ?? '').toString();
                          final ocupado = _ocupados.contains(i);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${c['nombre']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                  const SizedBox(height: 6),
                                  ...mats.map((e) {
                                    final m = e as Map;
                                    final esId =
                                        m['matricula'].toString() == ident;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                              esId
                                                  ? Icons.star
                                                  : Icons
                                                      .subdirectory_arrow_right,
                                              size: 15,
                                              color: esId
                                                  ? cessumGold
                                                  : Colors.grey),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${m['matricula']}'
                                              '${(m['programa'] ?? '').toString().isNotEmpty ? ' · ${m['programa']}' : ''}'
                                              '${(m['generacion'] ?? '').toString().isNotEmpty ? ' · ${m['generacion']}' : ''}'
                                              '${esId ? '  (identidad)' : ''}',
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: cessumRed,
                                        side:
                                            const BorderSide(color: cessumRed),
                                      ),
                                      onPressed:
                                          ocupado ? null : () => _vincular(i, c),
                                      icon: ocupado
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: cessumRed))
                                          : const Icon(Icons.link, size: 18),
                                      label: Text(ocupado
                                          ? 'Vinculando…'
                                          : 'Vincular como misma persona'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
    );
  }
}
