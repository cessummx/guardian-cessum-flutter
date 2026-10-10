import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';

/// El alumno ve las tareas de sus grupos y marca su entrega (con enlace).
class TareasAlumnoScreen extends StatefulWidget {
  final StudentProfile perfil;
  const TareasAlumnoScreen({super.key, required this.perfil});

  @override
  State<TareasAlumnoScreen> createState() => _TareasAlumnoScreenState();
}

class _TareasAlumnoScreenState extends State<TareasAlumnoScreen> {
  List<Map<String, dynamic>> _tareas = [];
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
      // "Mis tareas" ahora muestra las tareas de MOODLE (aula.cessum.mx), que es
      // donde los docentes las ponen. Antes leía tareas_alumno (tareas creadas
      // EN LA APP), y alumnos como Frania —con todo en Moodle— veían la lista
      // vacía. moodle_alumno devuelve las tareas del curso en curso ya filtradas.
      final uri = Uri.parse('$guardianUrl?accion=moodle_alumno'
          '&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      // Buscar el linkAula del curso en curso, para el botón "Ir al aula".
      String linkAula = '';
      final insc = (data['inscripciones'] as List?) ?? [];
      final materiaEnCurso = (data['materiaEnCurso'] ?? '').toString();
      for (final it in insc) {
        final m = Map<String, dynamic>.from(it as Map);
        if ((m['curso'] ?? '').toString() == materiaEnCurso) {
          final id = m['courseid'];
          if (id != null) {
            linkAula = 'https://aula.cessum.mx/course/view.php?id=$id';
          }
          break;
        }
      }
      setState(() {
        _tareas = ((data['tareas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .map((t) => {
                  // Normaliza los campos de Moodle a lo que la tarjeta espera.
                  'titulo': t['tarea'] ?? '',
                  'materia': t['curso'] ?? '',
                  'fechaLimite': t['fechaLimite'] ?? '',
                  'estatus': (t['entregado'] == true) ? 'Entregado' : 'Pendiente',
                  'vencida': t['vencida'] == true,
                  'linkAula': linkAula,
                })
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus tareas.';
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
        title: const Text('Mis tareas',
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
              : _tareas.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No tienes tareas por ahora.',
                            style: TextStyle(color: cessumMuted(context))),
                      ),
                    )
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _tareas.length,
                        itemBuilder: (ctx, i) => _tarjeta(_tareas[i]),
                      ),
                    ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> t) {
    final entregado = t['estatus'] == 'Entregado';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${t['titulo']}',
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: cessumRed)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (entregado ? const Color(0xFF1E8E3E) : cessumGold)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(entregado ? 'Entregado' : 'Pendiente',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: entregado
                              ? const Color(0xFF1E8E3E)
                              : const Color(0xFF8A6118))),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${t['materia']}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            if ((t['descripcion'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${t['descripcion']}',
                  style: const TextStyle(fontSize: 13, height: 1.4)),
            ],
            if ((t['fechaLimite'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.event, size: 15, color: cessumGold),
                  const SizedBox(width: 6),
                  Text('Entrega: ${t['fechaLimite']}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8A6118))),
                ],
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      entregado ? Colors.grey.shade200 : cessumRed,
                  foregroundColor: entregado ? cessumInk(context) : Colors.white,
                  elevation: 0,
                ),
                onPressed: (t['linkAula'] ?? '').toString().isEmpty
                    ? null
                    : () => _abrirAula((t['linkAula'] ?? '').toString()),
                icon: Icon(entregado ? Icons.check_circle_outline : Icons.open_in_new,
                    size: 18),
                label: Text(entregado
                    ? 'Ver en el Aula'
                    : 'Ir al Aula a entregar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirAula(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo abrir el Aula.'),
        ));
      }
    }
  }
}
