import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'student_profile.dart';

/// El alumno ve el material que sus docentes compartieron con su grupo.
class RecursosAlumnoScreen extends StatefulWidget {
  final StudentProfile perfil;
  const RecursosAlumnoScreen({super.key, required this.perfil});

  @override
  State<RecursosAlumnoScreen> createState() => _RecursosAlumnoScreenState();
}

class _RecursosAlumnoScreenState extends State<RecursosAlumnoScreen> {
  List<Map<String, dynamic>> _recursos = [];
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
      final uri = Uri.parse('$guardianUrl?accion=recursos_alumno'
          '&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _recursos = ((data['recursos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el material.';
      });
    }
  }

  IconData _iconoTipo(String tipo) {
    switch (tipo) {
      case 'Lectura':
        return Icons.menu_book;
      case 'Video':
        return Icons.play_circle;
      case 'Presentación':
        return Icons.slideshow;
      default:
        return Icons.link;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Material de clase',
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
              : _recursos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Aún no hay material compartido.',
                            style: TextStyle(color: cessumMuted(context))),
                      ),
                    )
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _recursos.length,
                        itemBuilder: (ctx, i) {
                          final r = _recursos[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: Icon(
                                  _iconoTipo((r['tipo'] ?? '').toString()),
                                  color: cessumRed),
                              title: Text('${r['titulo']}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                [
                                  '${r['materia']}',
                                  if ((r['docente'] ?? '').toString().isNotEmpty)
                                    '${r['docente']}',
                                  if ((r['descripcion'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    '${r['descripcion']}',
                                ].join('\n'),
                                style: const TextStyle(
                                    fontSize: 11.5, height: 1.4),
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.open_in_new,
                                  color: cessumGold),
                              onTap: () => Helpers.abrirUrlExterna(
                                  (r['url'] ?? '').toString(), context),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
