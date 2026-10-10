import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'csv_export.dart';

/// Panel de administrador: bitácora de auditoría ("quién hizo qué y cuándo").
class BitacoraScreen extends StatefulWidget {
  const BitacoraScreen({super.key});

  @override
  State<BitacoraScreen> createState() => _BitacoraScreenState();
}

class _BitacoraScreenState extends State<BitacoraScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _eventos = [];
  String _filtro = '';

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
      final correo = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'auditoria_listar',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      if (!mounted) return;
      setState(() {
        _eventos = ((data['eventos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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

  List<Map<String, dynamic>> get _filtrados {
    final q = _filtro.trim().toLowerCase();
    if (q.isEmpty) return _eventos;
    return _eventos.where((e) {
      return e.values.any((v) => v.toString().toLowerCase().contains(q));
    }).toList();
  }

  void _exportar() {
    final filas = _eventos
        .map((e) => <Object?>[
              e['fecha'] ?? '',
              e['usuario'] ?? '',
              e['accion'] ?? '',
              e['detalle'] ?? '',
              e['referencia'] ?? '',
            ])
        .toList();
    descargarCsv(
      'bitacora.csv',
      construirCsv(
          ['Fecha', 'Usuario', 'Acción', 'Detalle', 'Referencia'], filas),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Bitácora'),
        actions: [
          IconButton(
              onPressed: _cargando || _eventos.isEmpty ? null : _exportar,
              tooltip: 'Exportar CSV',
              icon: const Icon(Icons.download)),
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
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      child: TextField(
                        onChanged: (v) => setState(() => _filtro = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar (usuario, acción, fecha...)',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: lista.isEmpty
                          ? const Center(
                              child: Text('Sin eventos.',
                                  style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: lista.length,
                              itemBuilder: (c, i) => _fila(lista[i]),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _fila(Map<String, dynamic> e) {
    final detalle = (e['detalle'] ?? '').toString();
    final ref = (e['referencia'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((e['accion'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800)),
                ),
                Text((e['fecha'] ?? '').toString(),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 3),
            Text((e['usuario'] ?? '').toString(),
                style: const TextStyle(fontSize: 12, color: cessumGold)),
            if (detalle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(detalle, style: const TextStyle(fontSize: 12.5)),
            ],
            if (ref.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Ref: $ref',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}
