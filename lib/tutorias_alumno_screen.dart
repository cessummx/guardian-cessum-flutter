import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';

/// El alumno consulta las tutorías/asesorías que su docente registró para él:
/// fecha, motivo, acuerdos y estatus. (El registro lo hace el docente desde su
/// panel; aquí es solo de consulta.)
class TutoriasAlumnoScreen extends StatefulWidget {
  final StudentProfile perfil;
  const TutoriasAlumnoScreen({super.key, required this.perfil});

  @override
  State<TutoriasAlumnoScreen> createState() => _TutoriasAlumnoScreenState();
}

class _TutoriasAlumnoScreenState extends State<TutoriasAlumnoScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _tutorias = [];

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
      final uri = Uri.parse('$guardianUrl?accion=tutorias_alumno'
          '&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _tutorias = ((data['tutorias'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus tutorías.';
      });
    }
  }

  Color _colorEstatus(String e) {
    final s = e.toLowerCase();
    if (s.contains('realiz') || s.contains('atend') || s.contains('conclu')) {
      return const Color(0xFF1E8E3E);
    }
    if (s.contains('program') || s.contains('agend') || s.contains('pend')) {
      return cessumGold;
    }
    if (s.contains('cancel')) return cessumRed;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis tutorías y asesorías',
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
              ? _vacio(_error!, conReintento: true)
              : _tutorias.isEmpty
                  ? _vacio(
                      'Aún no tienes tutorías o asesorías registradas. '
                      'Cuando tu docente registre una, aparecerá aquí.')
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: _tutorias.length,
                        itemBuilder: (ctx, i) => _tarjeta(_tutorias[i]),
                      ),
                    ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> t) {
    final docente = (t['docente'] ?? '').toString();
    final fecha = (t['fechaAsesoria'] ?? '').toString();
    final motivo = (t['motivo'] ?? '').toString();
    final acuerdo = (t['acuerdo'] ?? '').toString();
    final estatus = (t['estatus'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.support_agent, color: cessumRed, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    docente.isEmpty ? 'Tutoría' : docente,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                if (estatus.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _colorEstatus(estatus).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      estatus,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _colorEstatus(estatus),
                      ),
                    ),
                  ),
              ],
            ),
            if (fecha.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.event, size: 14, color: cessumMuted(context)),
                  const SizedBox(width: 5),
                  Text(fecha,
                      style: TextStyle(
                          fontSize: 12, color: cessumMuted(context))),
                ],
              ),
            ],
            if (motivo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Motivo',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cessumMuted(context))),
              const SizedBox(height: 2),
              Text(motivo, style: const TextStyle(fontSize: 13, height: 1.35)),
            ],
            if (acuerdo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Acuerdo: $acuerdo',
                    style: const TextStyle(fontSize: 12.5, height: 1.4)),
              ),
            ],
          ],
        ),
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
            Icon(Icons.support_agent, size: 48, color: cessumFaint(context)),
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
