import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'student_profile.dart';

/// Vista del propio alumno: muestra sus cursos del Aula Virtual (Moodle),
/// cuánto ha avanzado, su última conexión, calificaciones y tareas.
class MiAulaScreen extends StatefulWidget {
  const MiAulaScreen({super.key});

  @override
  State<MiAulaScreen> createState() => _MiAulaScreenState();
}

class _MiAulaScreenState extends State<MiAulaScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String? _error;
  String _matricula = '';
  bool _enMoodle = false;
  Map<String, dynamic> _actividad = {};
  List<Map<String, dynamic>> _cursos = [];
  List<Map<String, dynamic>> _tareas = [];

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
      final perfil = await StudentProfile.load();
      final matricula = perfil?.matricula ?? '';
      _matricula = matricula;
      if (matricula.isEmpty) {
        setState(() {
          _cargando = false;
          _error = 'No encontré tu matrícula. Vuelve a iniciar sesión.';
        });
        return;
      }
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'moodle_alumno',
        'matricula': matricula,
        'dias': '30',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _enMoodle = data['enMoodle'] == true;
        _actividad =
            Map<String, dynamic>.from((data['actividad'] as Map?) ?? {});
        _cursos = ((data['inscripciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _tareas = ((data['tareas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar tu Aula Virtual. Intenta de nuevo.';
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
        title: const Text('Aula virtual (Moodle)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: () => Helpers.abrirUrlExterna(moodleUrl, context),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Abrir el Aula'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vacio(_error!, conReintento: true)
              : !_enMoodle
                  ? _vacio(
                      'Aún no apareces inscrito en el Aula Virtual con tu '
                      'cuenta. Si crees que es un error, avisa a Control Escolar.')
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                        children: [
                          _encabezado(),
                          const SizedBox(height: 16),
                          if (_cursosActuales().isNotEmpty) ...[
                            _titulo('Asignatura en curso'),
                            ..._cursosActuales().map(_tarjetaCurso),
                          ],
                          if (_tareasPendientes().isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _titulo('Tareas por entregar'),
                            ..._tareasPendientes().map(_tarjetaTarea),
                          ],
                          if (_cursosActuales().isEmpty &&
                              _tareasPendientes().isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Text(
                                'No tienes cursos ni tareas pendientes ahora mismo.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cessumMuted(context)),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }

  List<Map<String, dynamic>> _tareasPendientes() {
    return _tareas.where((t) => t['entregado'] != true).toList();
  }

  /// Solo la(s) asignatura(s) que el alumno está cursando ahora: cursos a los
  /// que entró y cuyo avance está entre 1% y 99%. Si no hay ninguno "en curso"
  /// (todo en 0% o ya terminado), muestra el último curso al que sí entró,
  /// para no dejar la vista vacía.
  List<Map<String, dynamic>> _cursosActuales() {
    bool entrado(Map<String, dynamic> c) =>
        (c['ultimoAcceso'] ?? '').toString().isNotEmpty ||
        c['diasSinEntrar'] != null;
    num? avance(Map<String, dynamic> c) =>
        (c['progreso'] is num) ? c['progreso'] as num : null;
    int reciente(Map<String, dynamic> c) =>
        (c['diasSinEntrar'] is int) ? c['diasSinEntrar'] as int : 1 << 30;

    var enCurso = _cursos.where((c) {
      final p = avance(c);
      return entrado(c) && p != null && p > 0 && p < 100;
    }).toList();

    if (enCurso.isEmpty) {
      final entrados = _cursos.where(entrado).toList()
        ..sort((a, b) => reciente(a).compareTo(reciente(b)));
      if (entrados.isNotEmpty) enCurso = [entrados.first];
    } else {
      enCurso.sort((a, b) => reciente(a).compareTo(reciente(b)));
    }
    return enCurso;
  }

  Widget _encabezado() {
    final eventos = _actividad['eventos'] ?? 0;
    final dias = _actividad['dias'] ?? 30;
    final ultimo = (_actividad['ultimoEvento'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cessumRed, cessumRed.withValues(alpha: 0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tu actividad reciente',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('$eventos acciones en los últimos $dias días',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          if (ultimo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Última vez en el Aula: $ultimo',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _titulo(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(t,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: cessumRed)),
    );
  }

  Widget _tarjetaCurso(Map<String, dynamic> c) {
    final prog = c['progreso'];
    final calif = c['calificacion'];
    final califMax = c['calificacionMax'];
    final dias = c['diasSinEntrar'];
    final ultimo = (c['ultimoAcceso'] ?? '').toString();
    final colorDias = (dias == null)
        ? cessumFaint(context)
        : (dias <= 7 ? _verde : (dias <= 20 ? cessumGold : cessumRed));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((c['curso'] ?? '').toString(),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: colorDias),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    ultimo.isEmpty
                        ? 'Aún no entras a este curso'
                        : 'Entraste: $ultimo'
                            '${dias != null ? ' (hace $dias días)' : ''}',
                    style: TextStyle(fontSize: 11.5, color: colorDias),
                  ),
                ),
              ],
            ),
            if (prog != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ((prog as num).toDouble() / 100).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: cessumMuted(context).withValues(alpha: 0.18),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(cessumGold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$prog%',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
            if (calif != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _verde.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Calificación: $calif${califMax != null ? ' / $califMax' : ''}',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _verde),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tarjetaTarea(Map<String, dynamic> t) {
    final vencida = t['vencida'] == true;
    final color = vencida ? cessumRed : cessumGold;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(vencida ? Icons.error : Icons.assignment_outlined,
            color: color),
        title: Text((t['tarea'] ?? '').toString(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${t['curso'] ?? ''}'
          '${(t['fechaLimite'] ?? '').toString().isNotEmpty ? '\nEntrega: ${t['fechaLimite']}' : ''}',
          style: const TextStyle(fontSize: 11),
        ),
        isThreeLine: (t['fechaLimite'] ?? '').toString().isNotEmpty,
        trailing: Text(vencida ? 'Vencida' : 'Pendiente',
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }

  Widget _vacio(String mensaje, {bool conReintento = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, size: 48, color: cessumFaint(context)),
            const SizedBox(height: 12),
            Text(mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context))),
            if (conReintento) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ],
        ),
      ),
    );
  }
}
