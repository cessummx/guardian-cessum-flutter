// ALUMNO: Mis materias (ago-2026). Panorama del grupo del alumno:
// EN CURSO (con "Conoce a tu profesor": título + semblanza de la hoja
// Docentes) y PRÓXIMAS MATERIAS (proyección con fechas, día/hora y
// docente confirmado o por confirmar).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class MateriasAlumnoScreen extends StatefulWidget {
  final String matricula;
  const MateriasAlumnoScreen({super.key, required this.matricula});

  @override
  State<MateriasAlumnoScreen> createState() => _MateriasAlumnoScreenState();
}

class _MateriasAlumnoScreenState extends State<MateriasAlumnoScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final u = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'alumno_materias_panorama',
        'matricula': widget.matricula,
      });
      final r = await http.get(u).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _data = d;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  List<Map<String, dynamic>> _lista(String k) => ((_data[k] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  void _conocerProfesor(Map<String, dynamic> m) {
    final semblanza = (m['semblanza'] ?? '').toString().trim();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.school, color: cessumRed),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${m['docente']}',
                  style: const TextStyle(fontSize: 15.5)),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Imparte: ${m['materia']}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(
                  semblanza.isNotEmpty
                      ? semblanza
                      : 'La semblanza de este profesor estará disponible '
                          'próximamente.',
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enCurso = _lista('enCurso');
    final futuras = _lista('futuras');
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis materias',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No se pudo cargar: $_error'),
                ))
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Text(
                        '${_data['programa'] ?? ''} · Gen. ${_data['generacion'] ?? ''} · ${_data['grupo'] ?? ''}',
                        style: TextStyle(
                            fontSize: 12.5, color: cessumMuted(context)),
                      ),
                      const SizedBox(height: 14),
                      _encabezado('EN CURSO', Icons.play_circle_fill,
                          const Color(0xFF1E8E3E)),
                      if (enCurso.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                              'No tienes materias en curso en este momento.',
                              style: TextStyle(
                                  fontSize: 12.5, color: cessumMuted(context))),
                        ),
                      for (final m in enCurso) _tarjeta(m, enCurso: true),
                      const SizedBox(height: 18),
                      _encabezado('PRÓXIMAS MATERIAS · proyección',
                          Icons.upcoming, cessumGold),
                      Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Así viene tu camino: qué cursarás, cuándo y con '
                          'quién. Los docentes confirmados ya aceptaron '
                          'impartir su materia.',
                          style: TextStyle(
                              fontSize: 11.5, color: cessumMuted(context)),
                        ),
                      ),
                      if (futuras.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                              'Aún no hay materias futuras programadas para '
                              'tu grupo. Vuelve pronto.',
                              style: TextStyle(
                                  fontSize: 12.5, color: cessumMuted(context))),
                        ),
                      for (final m in futuras) _tarjeta(m, enCurso: false),
                      if ((_data['pasadas'] ?? 0) != 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            'Ya cursaste ${_data['pasadas']} materia(s). '
                            'Consulta tus resultados en Mis calificaciones.',
                            style: TextStyle(
                                fontSize: 11.5, color: cessumFaint(context)),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _encabezado(String t, IconData ic, Color c) {
    return Row(
      children: [
        Icon(ic, size: 18, color: c),
        const SizedBox(width: 6),
        Text(t,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: c)),
      ],
    );
  }

  Widget _tarjeta(Map<String, dynamic> m, {required bool enCurso}) {
    final confirmado = m['docenteConfirmado'] == true;
    final tieneDocente = (m['docente'] ?? '').toString().trim().isNotEmpty;
    final esBloque =
        (m['bloqueConjunto'] ?? '').toString().trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: enCurso
                ? const Color(0xFF1E8E3E).withValues(alpha: 0.45)
                : cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${m['materia']}',
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700)),
          if (esBloque)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                  'Se imparte a la par con otra materia de tu bloque '
                  '(comparten sesión y acreditación).',
                  style:
                      TextStyle(fontSize: 11, color: Color(0xFF7B1FA2))),
            ),
          const SizedBox(height: 4),
          Text(
            'Del ${m['inicio']} al ${m['termino']}'
            '${(m['dia'] ?? '').toString().isNotEmpty ? ' · ${m['dia']}' : ''}'
            '${(m['hora'] ?? '').toString().isNotEmpty ? ' · ${m['hora']}' : ''}',
            style: TextStyle(fontSize: 12, color: cessumInk(context)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  tieneDocente ? '${m['docente']}' : 'Docente por asignar',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color:
                          tieneDocente ? cessumInk(context) : cessumFaint(context)),
                ),
              ),
              if (tieneDocente)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (confirmado
                            ? const Color(0xFF1E8E3E)
                            : cessumGold)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    confirmado ? 'Docente confirmado' : 'Por confirmar',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: confirmado
                            ? const Color(0xFF1E8E3E)
                            : cessumGold),
                  ),
                ),
            ],
          ),
          if (enCurso) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (tieneDocente)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: cessumRed,
                          side: const BorderSide(color: cessumRed)),
                      onPressed: () => _conocerProfesor(m),
                      icon: const Icon(Icons.badge, size: 17),
                      label: const Text('Conoce a tu profesor',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                if (tieneDocente &&
                    (m['linkAula'] ?? '').toString().isNotEmpty)
                  const SizedBox(width: 8),
                if ((m['linkAula'] ?? '').toString().isNotEmpty)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cessumRed,
                          foregroundColor: Colors.white),
                      onPressed: () => Helpers.abrirUrlExterna(
                          (m['linkAula'] ?? '').toString(), context),
                      icon: const Icon(Icons.school, size: 17),
                      label: const Text('Abrir aula',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
