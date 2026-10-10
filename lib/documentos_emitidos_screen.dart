import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'csv_export.dart';

/// Panel de administrador: documentos emitidos (folios), con buscador y
/// verificación de un toque.
class DocumentosEmitidosScreen extends StatefulWidget {
  const DocumentosEmitidosScreen({super.key});

  @override
  State<DocumentosEmitidosScreen> createState() =>
      _DocumentosEmitidosScreenState();
}

class _DocumentosEmitidosScreenState extends State<DocumentosEmitidosScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _docs = [];
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
        'accion': 'documentos_listar',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      if (!mounted) return;
      setState(() {
        _docs = ((data['documentos'] as List?) ?? [])
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
    if (q.isEmpty) return _docs;
    return _docs
        .where((d) => d.values.any((v) => v.toString().toLowerCase().contains(q)))
        .toList();
  }

  void _exportar() {
    final filas = _docs
        .map((d) => <Object?>[
              d['folio'] ?? '',
              d['fecha'] ?? '',
              d['tipo'] ?? '',
              d['matricula'] ?? '',
              d['nombre'] ?? '',
              d['programa'] ?? '',
              d['firmado'] ?? '',
            ])
        .toList();
    descargarCsv(
      'documentos_emitidos.csv',
      construirCsv([
        'Folio',
        'Fecha',
        'Tipo',
        'Matrícula',
        'Nombre',
        'Programa',
        'Firmado'
      ], filas),
    );
  }

  Future<void> _verificar(String url) async {
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Documentos emitidos'),
        actions: [
          IconButton(
              onPressed: _cargando || _docs.isEmpty ? null : _exportar,
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
                          hintText: 'Buscar (folio, alumno, tipo...)',
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
                              child: Text('Sin documentos.',
                                  style: TextStyle(color: Colors.black54)))
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

  Widget _fila(Map<String, dynamic> d) {
    final firmado = (d['firmado'] ?? '').toString().toUpperCase() == 'SI';
    final verificar = (d['verificar'] ?? '').toString();
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
                  child: Text((d['tipo'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800)),
                ),
                Icon(firmado ? Icons.verified : Icons.description,
                    size: 18,
                    color: firmado ? const Color(0xFF1E8E3E) : Colors.black38),
              ],
            ),
            const SizedBox(height: 2),
            Text('Folio: ${d['folio'] ?? ''}',
                style: const TextStyle(fontSize: 11.5, color: cessumGold)),
            const SizedBox(height: 2),
            Text(
              '${d['nombre'] ?? ''}'
              '${(d['matricula'] ?? '').toString().isNotEmpty ? ' · ${d['matricula']}' : ''}',
              style: const TextStyle(fontSize: 12.5),
            ),
            Text('${d['fecha'] ?? ''}',
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
            if (verificar.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _verificar(verificar),
                  icon: const Icon(Icons.qr_code_2, size: 16),
                  label: const Text('Verificar'),
                  style: TextButton.styleFrom(foregroundColor: cessumRed),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
