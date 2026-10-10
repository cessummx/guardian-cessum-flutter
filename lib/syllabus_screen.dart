import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';

/// Syllabus del programa: el alumno consulta las cartas descriptivas de sus
/// asignaturas (propósito, clave y ciclo) desde cartas.json.
class SyllabusScreen extends StatefulWidget {
  final String programa;
  const SyllabusScreen({super.key, required this.programa});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  List<Map<String, dynamic>> _asignaturas = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _llave(String s) {
    const con = 'áéíóúüñÁÉÍÓÚÜÑ';
    const sin = 'aeiouunAEIOUUN';
    var t = s;
    for (var i = 0; i < con.length; i++) {
      t = t.replaceAll(con[i], sin[i]);
    }
    return t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('https://app.cessum.mx/cartas.json'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(utf8.decode(resp.bodyBytes))
          as Map<String, dynamic>;
      final progs = (data['programas'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final k = _llave(widget.programa);
      Map<String, dynamic>? mio;
      for (final p in progs) {
        if (_llave((p['programa'] ?? '').toString()) == k) {
          mio = p;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _asignaturas = mio == null
            ? []
            : (mio['asignaturas'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        _cargando = false;
        if (mio == null) {
          _error =
              'Aún no hay cartas descriptivas publicadas para tu programa.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el plan de estudios.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // agrupar por ciclo/semestre conservando el orden
    final Map<String, List<Map<String, dynamic>>> porCiclo = {};
    for (final a in _asignaturas) {
      final c = ((a['semestre'] ?? '') as String).trim().isEmpty
          ? 'Sin ciclo'
          : (a['semestre'] ?? '') as String;
      porCiclo.putIfAbsent(c, () => []).add(a);
    }

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis asignaturas',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cessumMuted(context))),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      widget.programa,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cessumRed),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Toca una asignatura para ver su propósito formativo.',
                      style:
                          TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                    const SizedBox(height: 12),
                    ...porCiclo.entries.expand((entry) => [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: cessumGold),
                            ),
                          ),
                          ...entry.value.map((a) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                                child: ExpansionTile(
                                  title: Text(
                                    (a['denominacion'] ?? '') as String,
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    'Clave: ${a['clave'] ?? ''}',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: cessumFaint(context)),
                                  ),
                                  childrenPadding:
                                      const EdgeInsets.fromLTRB(
                                          16, 0, 16, 14),
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: cessumGold.withValues(alpha: 0.08),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        ((a['fines'] ?? '') as String)
                                                .trim()
                                                .isEmpty
                                            ? 'Propósito en actualización.'
                                            : (a['fines'] ?? '') as String,
                                        style: const TextStyle(
                                            fontSize: 12.5, height: 1.5),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ]),
                  ],
                ),
    );
  }
}
