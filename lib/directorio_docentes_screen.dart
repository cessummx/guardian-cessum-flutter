import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Directorio de docentes: lista de docentes activos con sus materias y
/// correo, con buscador y botones para copiar o enviar correo.
class DirectorioDocentesScreen extends StatefulWidget {
  const DirectorioDocentesScreen({super.key});

  @override
  State<DirectorioDocentesScreen> createState() =>
      _DirectorioDocentesScreenState();
}

class _DirectorioDocentesScreenState extends State<DirectorioDocentesScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _docentes = [];
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
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=directorio_docentes'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('error');
      if (!mounted) return;
      setState(() {
        _docentes = ((data['docentes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el directorio.';
      });
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    if (_filtro.trim().isEmpty) return _docentes;
    final q = _filtro.toLowerCase();
    return _docentes.where((d) {
      final n = (d['docente'] ?? '').toString().toLowerCase();
      final c = (d['correo'] ?? '').toString().toLowerCase();
      return n.contains(q) || c.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Directorio de docentes',
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
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      child: TextField(
                        onChanged: (v) => setState(() => _filtro = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar docente por nombre o correo',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${lista.length} docente(s)',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                      ),
                    ),
                    Expanded(
                      child: lista.isEmpty
                          ? const Center(
                              child: Text('Sin coincidencias.',
                                  style: TextStyle(color: Colors.black54)))
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 6, 12, 24),
                              itemCount: lista.length,
                              itemBuilder: (ctx, i) => _tarjeta(lista[i]),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> d) {
    final nombre = (d['docente'] ?? '').toString();
    final correo = (d['correo'] ?? '').toString();
    final materias = (d['materias'] as List?) ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre.isEmpty ? '(sin nombre)' : nombre,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(correo,
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text('${materias.length} materia(s)',
                      style: const TextStyle(
                          fontSize: 11.5,
                          color: cessumGold,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (correo.isNotEmpty && correo != '(sin correo)') ...[
              IconButton(
                tooltip: 'Copiar correo',
                icon: const Icon(Icons.copy, size: 20, color: Colors.black45),
                onPressed: () =>
                    Helpers.copiarAlPortapapeles(context, correo, 'Correo'),
              ),
              IconButton(
                tooltip: 'Enviar correo',
                icon: const Icon(Icons.email, size: 20, color: cessumRed),
                onPressed: () => Helpers.abrirCorreo(
                  context: context,
                  destinatario: correo,
                  asunto: 'CESSUM',
                  cuerpo: '',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
