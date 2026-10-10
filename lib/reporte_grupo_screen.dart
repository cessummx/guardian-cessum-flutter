import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';

/// El docente genera el concentrado de calificaciones (PDF) de uno de sus
/// grupos: lista, promedio y % de aprobación.
class ReporteGrupoScreen extends StatefulWidget {
  const ReporteGrupoScreen({super.key});

  @override
  State<ReporteGrupoScreen> createState() => _ReporteGrupoScreenState();
}

class _ReporteGrupoScreenState extends State<ReporteGrupoScreen> {
  String _correo = '';
  List<Map<String, dynamic>> _grupos = [];
  bool _cargando = true;
  String? _generandoClave;
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
      _correo = (await SessionStore.validEmail()) ?? '';
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=mis_grupos'
              '&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _grupos = ((data['grupos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus grupos.';
      });
    }
  }

  Future<void> _generar(Map<String, dynamic> g) async {
    final clave = (g['clave'] ?? '').toString();
    setState(() => _generandoClave = '$clave|${g['grupo']}');
    try {
      final uri = Uri.parse('$guardianUrl?accion=reporte_grupo_pdf'
          '&correo=${Uri.encodeComponent(_correo)}'
          '&programa=${Uri.encodeComponent((g['programa'] ?? '').toString())}'
          '&generacion=${Uri.encodeComponent((g['generacion'] ?? '').toString())}'
          '&grupo=${Uri.encodeComponent((g['grupo'] ?? '').toString())}'
          '&clave=${Uri.encodeComponent(clave)}'
          '&materia=${Uri.encodeComponent((g['materia'] ?? '').toString())}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final pdf = (data['pdf'] ?? '').toString();
      if (!mounted) return;
      if (pdf.isNotEmpty) Helpers.abrirUrlExterna(pdf, context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text(
            'Reporte generado · ${data['alumnos']} alumnos, promedio ${data['promedio']}, aprobación ${data['aprobacion']}%.'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _generandoClave = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Reporte de mi grupo',
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
              : _grupos.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No tienes grupos asignados.',
                            style: TextStyle(color: Colors.black54)),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Genera el concentrado de calificaciones (PDF) de cualquiera de tus grupos: lista, promedio y porcentaje de aprobación.',
                          style: TextStyle(
                              fontSize: 13, height: 1.5, color: Colors.black87),
                        ),
                        const SizedBox(height: 14),
                        ..._grupos.map((g) {
                          final clave = (g['clave'] ?? '').toString();
                          final generando =
                              _generandoClave == '$clave|${g['grupo']}';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${g['materia']}',
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${g['programa']} · ${g['generacion']} · Grupo ${g['grupo']}',
                                    style: const TextStyle(
                                        fontSize: 11.5, color: Colors.black54),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: cessumRed,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: generando
                                          ? null
                                          : () => _generar(g),
                                      icon: generando
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white))
                                          : const Icon(Icons.picture_as_pdf,
                                              size: 18),
                                      label: Text(generando
                                          ? 'Generando...'
                                          : 'Generar reporte PDF'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 24),
                      ],
                    ),
    );
  }
}
