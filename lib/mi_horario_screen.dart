import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'student_profile.dart';
import 'cessum_ui.dart';

const _dias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo'
];

/// El alumno ve el horario de su grupo (solo lectura).
class MiHorarioScreen extends StatefulWidget {
  final StudentProfile perfil;
  const MiHorarioScreen({super.key, required this.perfil});

  @override
  State<MiHorarioScreen> createState() => _MiHorarioScreenState();
}

class _MiHorarioScreenState extends State<MiHorarioScreen> {
  List<Map<String, dynamic>> _clases = [];
  String _grupo = '';
  bool _cargando = true;
  bool _encontrado = false;
  bool _modoOffline = false;
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
      final uri = Uri.parse('$guardianUrl?accion=horario_alumno'
          '&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _encontrado = data['encontrado'] == true;
        _grupo = (data['grupo'] ?? '').toString();
        _clases = ((data['clases'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _modoOffline = false;
        _cargando = false;
      });
      _guardarCacheHorario();
    } catch (e) {
      final restaurado = await _restaurarCacheHorario();
      if (restaurado) return;
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar tu horario.';
      });
    }
  }

  // Guarda el horario para verlo sin conexión.
  Future<void> _guardarCacheHorario() async {
    final mat = widget.perfil.matricula;
    if (mat.isEmpty || !_encontrado) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('horario_cache_$mat',
          jsonEncode({'grupo': _grupo, 'clases': _clases}));
    } catch (_) {}
  }

  // Si no hay conexión, restaura el horario guardado.
  Future<bool> _restaurarCacheHorario() async {
    final mat = widget.perfil.matricula;
    if (mat.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('horario_cache_$mat');
      if (raw == null) return false;
      final c = jsonDecode(raw) as Map<String, dynamic>;
      final clases = ((c['clases'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (clases.isEmpty) return false;
      if (!mounted) return false;
      setState(() {
        _grupo = (c['grupo'] ?? '').toString();
        _clases = clases;
        _encontrado = true;
        _modoOffline = true;
        _error = null;
        _cargando = false;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi horario',
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
              : !_encontrado
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Aún no encontramos tu grupo. Comunícate con servicios escolares.',
                          style: TextStyle(color: cessumMuted(context)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _clases.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Tu grupo ($_grupo) aún no tiene horario publicado.',
                              style: TextStyle(color: cessumMuted(context)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _vista(),
    );
  }

  Widget _vista() {
    final porDia = <String, List<Map<String, dynamic>>>{};
    for (final c in _clases) {
      porDia.putIfAbsent((c['dia'] ?? '').toString(), () => []).add(c);
    }
    final diasConClase = _dias.where((d) => porDia.containsKey(d)).toList();
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_modoOffline)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEAD9AE)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, size: 16, color: Color(0xFFA56B16)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Sin conexión: horario guardado.',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF5b4a1f))),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.groups, color: cessumRed, size: 20),
                const SizedBox(width: 10),
                Text('Grupo $_grupo',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cessumRed)),
              ],
            ),
          ),
          ...diasConClase.map((dia) {
            final clases = porDia[dia]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text(dia,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: cessumGold)),
                ),
                ...clases.map((c) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Container(
                          width: 56,
                          alignment: Alignment.center,
                          child: Text(
                            '${c['horaInicio']}\n${c['horaFin']}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: cessumRed),
                          ),
                        ),
                        title: Text('${c['materia']}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [
                            if ((c['docente'] ?? '').toString().isNotEmpty)
                              '${c['docente']}',
                            if ((c['aula'] ?? '').toString().isNotEmpty)
                              'Aula ${c['aula']}',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    )),
              ],
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
