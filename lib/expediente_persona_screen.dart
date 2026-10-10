import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';

/// Expediente unificado de la PERSONA: junta todas sus matrículas (identidad =
/// la más antigua) y muestra cada grado por separado (maestría, doctorado…).
class ExpedientePersonaScreen extends StatefulWidget {
  final String matriculaInicial;
  const ExpedientePersonaScreen({super.key, this.matriculaInicial = ''});

  @override
  State<ExpedientePersonaScreen> createState() =>
      _ExpedientePersonaScreenState();
}

class _ExpedientePersonaScreenState extends State<ExpedientePersonaScreen> {
  final _ctrl = TextEditingController();
  bool _cargando = false;
  String? _error;
  Map<String, dynamic>? _res;

  @override
  void initState() {
    super.initState();
    if (widget.matriculaInicial.isNotEmpty) {
      _ctrl.text = widget.matriculaInicial;
      _buscar();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final mat = _ctrl.text.trim();
    if (mat.isEmpty) {
      setState(() => _error = 'Escribe una matrícula.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
      _res = null;
    });
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'expediente_persona',
        'actor': actor,
        'matricula': mat,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _cargando = false;
        if (data['ok'] == true) {
          _res = data;
        } else {
          _error = data['error']?.toString() ?? 'No se pudo';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final grados = (_res?['grados'] as List?) ?? [];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Expediente de la persona'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          TextField(
            controller: _ctrl,
            onSubmitted: (_) => _buscar(),
            decoration: const InputDecoration(
              labelText: 'Matrícula (cualquiera de la persona)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: _cargando ? null : _buscar,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Buscar'),
            ),
          ),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: CircularProgressIndicator(color: cessumRed)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: cessumRed)),
            ),
          if (_res != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_res!['nombre'] ?? '(sin nombre)'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    'Identidad (matrícula más antigua): '
                    '${_res!['identidad'] ?? ''}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  Text(
                    'Matrículas: '
                    '${((_res!['matriculas'] as List?) ?? []).join(', ')}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (grados.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Sin calificaciones registradas.',
                    style: TextStyle(color: Colors.black54)),
              )
            else
              ...grados.map((g) {
                final gr = g as Map;
                final materias = (gr['materias'] as List?) ?? [];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${gr['programa']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: cessumRed)),
                        Text(
                          'Gen. ${gr['generacion']}  ·  Mat. ${gr['matricula']}'
                          '${(gr['promedio'] ?? '').toString().isNotEmpty ? '  ·  Prom. ${gr['promedio']}' : ''}',
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.grey),
                        ),
                        const Divider(height: 16),
                        ...materias.map((m) {
                          final ma = m as Map;
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('${ma['materia']}',
                                      style: const TextStyle(fontSize: 12.5)),
                                ),
                                Text(
                                  '${ma['cal']}'
                                  '${(ma['estatus'] ?? '').toString().isNotEmpty ? ' · ${ma['estatus']}' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: (ma['estatus'] == 'Validada')
                                        ? const Color(0xFF1E8E3E)
                                        : Colors.black87,
                                  ),
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
          ],
        ],
      ),
    );
  }
}
