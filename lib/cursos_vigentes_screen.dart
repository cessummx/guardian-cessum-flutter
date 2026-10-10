// ADMIN: Cursos vigentes (jul-2026). Lista los cursos EN MARCHA hoy
// (inicio <= hoy <= término) con docente, clase en formato de aula
// "Materia (SIGLA GEN[ SAB])", fechas, estado de invitación y link del
// aula. Botón para descargar todo en Excel (ruta cursos_vigentes_excel).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class CursosVigentesScreen extends StatefulWidget {
  const CursosVigentesScreen({super.key});

  @override
  State<CursosVigentesScreen> createState() => _CursosVigentesScreenState();
}

class _CursosVigentesScreenState extends State<CursosVigentesScreen> {
  bool _cargando = true;
  bool _descargando = false;
  String _error = '';
  String _hoy = '';
  List<Map<String, dynamic>> _cursos = [];

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
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=cursos_vigentes'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo cargar.');
      }
      if (!mounted) return;
      setState(() {
        _hoy = (data['hoy'] ?? '').toString();
        _cursos = ((data['cursos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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

  Future<void> _descargarExcel() async {
    setState(() => _descargando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=cursos_vigentes_excel'))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true || (data['xlsxUrl'] ?? '').toString().isEmpty) {
        throw Exception(data['error'] ?? 'No se pudo generar el Excel.');
      }
      if (!mounted) return;
      await Helpers.abrirUrlExterna(data['xlsxUrl'].toString(), context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text('Excel generado: ${data['nombre'] ?? ''}'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('No se pudo descargar: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Cursos vigentes',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error: $_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Text(
                      'Cursos en marcha hoy ($_hoy): su inicio ya pasó y su '
                      'término aún no llega. ${_cursos.length} curso(s).',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E8E3E),
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed:
                            _descargando || _cursos.isEmpty ? null : _descargarExcel,
                        icon: _descargando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.table_view),
                        label: Text(_descargando
                            ? 'Generando Excel…'
                            : 'Descargar Excel (docente, clase, fechas y link del aula)'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_cursos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text('No hay cursos vigentes hoy.',
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.black54)),
                        ),
                      )
                    else
                      ..._porModalidad(),
                  ],
                ),
    );
  }

  // Secciones agrupadas por modalidad (Mixta, Sabatino, Entre semana...).
  List<Widget> _porModalidad() {
    final orden = <String>[];
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final c in _cursos) {
      final m = (c['modalidad'] ?? 'Otra').toString();
      if (!grupos.containsKey(m)) orden.add(m);
      grupos.putIfAbsent(m, () => []).add(c);
    }
    final out = <Widget>[];
    for (final m in orden) {
      final lista = grupos[m]!;
      out.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(
          '${m.toUpperCase()} · ${lista.length} curso(s)',
          style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: cessumRed,
              letterSpacing: 0.4),
        ),
      ));
      for (final c in lista) {
        out.add(_filaCurso(c));
      }
    }
    return out;
  }

  Widget _filaCurso(Map<String, dynamic> c) {
    final inv = (c['estadoInvitacion'] ?? '').toString();
    final aceptada = inv.toLowerCase() == 'aceptada';
    final link = (c['linkAula'] ?? '').toString().trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((c['clase'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text((c['docente'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87)),
                if ((c['sesion'] ?? '').toString().isNotEmpty ||
                    (c['alumnos'] ?? 0) != 0)
                  Text(
                    [
                      if ((c['sesion'] ?? '').toString().isNotEmpty)
                        (c['sesion'] ?? '').toString(),
                      '${c['alumnos'] ?? 0} alumno(s)',
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.black87),
                  ),
                Text(
                  'Del ${c['inicio']} al ${c['termino']}'
                  '${inv.isNotEmpty ? ' · Invitación: $inv' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      color: aceptada
                          ? Colors.black54
                          : const Color(0xFFB08D57)),
                ),
              ],
            ),
          ),
          if (link.isNotEmpty)
            IconButton(
              tooltip: 'Abrir aula',
              icon: const Icon(Icons.school, color: cessumRed),
              onPressed: () => Helpers.abrirUrlExterna(link, context),
            )
          else
            const Tooltip(
              message: 'Sin aula creada',
              child:
                  Icon(Icons.school_outlined, color: Colors.black26, size: 22),
            ),
        ],
      ),
    );
  }
}
