import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'student_profile.dart';
import 'cessum_ui.dart';

/// El alumno ve los avisos que sus docentes publicaron para su grupo.
class AvisosAlumnoScreen extends StatefulWidget {
  final StudentProfile perfil;
  const AvisosAlumnoScreen({super.key, required this.perfil});

  @override
  State<AvisosAlumnoScreen> createState() => _AvisosAlumnoScreenState();
}

class _AvisosAlumnoScreenState extends State<AvisosAlumnoScreen> {
  List<Map<String, dynamic>> _avisos = [];
  bool _cargando = true;
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
      final uri = Uri.parse('$guardianUrl?accion=avisos_grupo_alumno'
          '&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _avisos = ((data['avisos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los avisos.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Avisos de mis maestros',
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
              : _avisos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No tienes avisos por ahora.',
                          style: TextStyle(color: cessumMuted(context)),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _avisos.length,
                        itemBuilder: (ctx, i) {
                          final a = _avisos[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.campaign,
                                          color: cessumRed, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text('${a['materia']}',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: cessumRed)),
                                      ),
                                    ],
                                  ),
                                  if ((a['docente'] ?? '')
                                      .toString()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text('${a['docente']}',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: cessumMuted(ctx))),
                                  ],
                                  const SizedBox(height: 8),
                                  Text('${a['mensaje']}',
                                      style: const TextStyle(
                                          fontSize: 13, height: 1.45)),
                                  const SizedBox(height: 6),
                                  Text('${a['fecha']}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cessumFaint(ctx))),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
