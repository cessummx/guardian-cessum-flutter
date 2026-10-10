// Pantalla de administrador: "Planes faltantes".
//
// Detecta los programas activos que NO tienen plan de estudios cargado en
// cartas.json (los que en "Avance por programa" salen como "Plan no cargado").
// Así sabes exactamente qué planes faltan para que todos los avances muestren
// su porcentaje.
//
// Acción del Guardián:
//   POST planes_faltantes -> {ok, totalProgramas, faltan, programas:[...]}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class PlanesFaltantesScreen extends StatefulWidget {
  const PlanesFaltantesScreen({super.key});

  @override
  State<PlanesFaltantesScreen> createState() => _PlanesFaltantesScreenState();
}

class _PlanesFaltantesScreenState extends State<PlanesFaltantesScreen> {
  bool _cargando = true;
  String _actor = '';
  int _total = 0;
  int _faltan = 0;
  List<Map<String, dynamic>> _programas = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      _actor = (await SessionStore.realEmail()) ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(
                  {'accion': 'planes_faltantes', 'actor': _actor}))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _total = (data['totalProgramas'] ?? 0) as int;
        _faltan = (data['faltan'] ?? 0) as int;
        _programas = ((data['programas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _programas = [];
      }
    } catch (_) {
      _programas = [];
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    final faltantes = _programas.where((p) => p['tienePlan'] != true).toList();
    final conPlan = _programas.where((p) => p['tienePlan'] == true).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planes faltantes'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _resumen(),
                const SizedBox(height: 16),
                if (faltantes.isNotEmpty) ...[
                  _encabezado(
                      'Sin plan cargado', faltantes.length, cessumRed),
                  ...faltantes.map((p) => _tarjeta(p, false)),
                  const SizedBox(height: 18),
                ],
                if (conPlan.isNotEmpty) ...[
                  _encabezado('Con plan', conPlan.length,
                      const Color(0xFF1E8E3E)),
                  ...conPlan.map((p) => _tarjeta(p, true)),
                ],
              ],
            ),
    );
  }

  Widget _resumen() {
    final ok = _faltan == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (ok ? const Color(0xFF1E8E3E) : cessumRed)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (ok ? const Color(0xFF1E8E3E) : cessumRed)
                .withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.verified_outlined : Icons.warning_amber_rounded,
              color: ok ? const Color(0xFF1E8E3E) : cessumRed, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ok
                  ? 'Todos los programas activos tienen su plan cargado.'
                  : '$_faltan de $_total programas activos no tienen plan en cartas.json. '
                      'Mientras falte, su avance no muestra porcentaje.',
              style: TextStyle(
                  fontSize: 13, height: 1.35, color: cessumMuted(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezado(String t, int n, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(width: 10, height: 10,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('$t · $n',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cessumMuted(context))),
          ],
        ),
      );

  Widget _tarjeta(Map<String, dynamic> p, bool tienePlan) {
    final alumnos = p['alumnos'] ?? 0;
    final total = p['totalPlan'] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: tienePlan
                ? cessumMuted(context).withValues(alpha: 0.18)
                : cessumRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
              tienePlan
                  ? Icons.check_circle
                  : Icons.error_outline,
              color: tienePlan ? const Color(0xFF1E8E3E) : cessumRed,
              size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['programa'] ?? ''}',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: cessumIsDark(context)
                            ? Colors.white
                            : cessumInk(context))),
                const SizedBox(height: 2),
                Text(
                    tienePlan
                        ? '$total materias en el plan · $alumnos alumno(s)'
                        : '$alumnos alumno(s) afectado(s) · sin plan',
                    style:
                        TextStyle(fontSize: 12, color: cessumMuted(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
