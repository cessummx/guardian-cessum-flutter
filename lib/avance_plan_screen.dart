import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Alumno: avance del plan de estudios. % de materias y de créditos cubiertos,
/// promedio general, egreso aproximado y el detalle por ciclo.
class AvancePlanScreen extends StatefulWidget {
  const AvancePlanScreen({super.key});

  @override
  State<AvancePlanScreen> createState() => _AvancePlanScreenState();
}

class _AvancePlanScreenState extends State<AvancePlanScreen> {
  bool _cargando = true;
  String? _error;

  String _programa = '';
  String _generacion = '';
  int _total = 0;
  int _aprobadas = 0;
  int _pendientes = 0;
  num _crTot = 0;
  num _crAprob = 0;
  int _porc = 0;
  int _porcCr = 0;
  num _promedio = 0;
  String _egreso = '';
  List<Map<String, dynamic>> _ciclos = [];

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
      final p = await StudentProfile.load();
      if (p == null) {
        setState(() {
          _cargando = false;
          _error = 'Completa tu perfil para ver tu avance.';
        });
        return;
      }
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'avance_plan',
        'matricula': p.matricula,
        'programa': p.programa,
        'generacion': p.generacion,
        'modalidad': p.modalidad,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _programa = (data['programa'] ?? '').toString();
      _generacion = (data['generacion'] ?? '').toString();
      _total = (data['totalMaterias'] ?? 0) as int;
      _aprobadas = (data['aprobadas'] ?? 0) as int;
      _pendientes = (data['pendientes'] ?? 0) as int;
      _crTot = (data['creditosTotales'] ?? 0) as num;
      _crAprob = (data['creditosAprobados'] ?? 0) as num;
      _porc = (data['porcentaje'] ?? 0) as int;
      _porcCr = (data['porcentajeCreditos'] ?? 0) as int;
      _promedio = (data['promedio'] ?? 0) as num;
      _egreso = (data['egresoAprox'] ?? '').toString();
      _ciclos = ((data['ciclos'] as List<dynamic>? ?? []))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      _error = 'No se pudo cargar tu avance. Intenta de nuevo.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi avance'),
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
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _cabecera(),
                      const SizedBox(height: 16),
                      _kpis(),
                      const SizedBox(height: 18),
                      const Text('Materias por ciclo',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      if (_ciclos.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Aún no hay materias registradas para tu generación.',
                            style: TextStyle(color: cessumMuted(context)),
                          ),
                        ),
                      ..._ciclos.map(_bloqueCiclo),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }

  Widget _cabecera() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [cessumRed, Color(0xFF8E1622)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CircularProgressIndicator(
                    value: _porc / 100.0,
                    strokeWidth: 9,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                Text('$_porc%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_programa,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                if (_generacion.isNotEmpty)
                  Text('Generación $_generacion',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5)),
                const SizedBox(height: 6),
                Text('$_aprobadas de $_total materias aprobadas',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
                Text('Créditos: $_porcCr%  ($_crAprob de $_crTot)',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpis() {
    Widget kpi(String valor, String label, IconData ic) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
            ),
            child: Column(
              children: [
                Icon(ic, color: cessumGold, size: 20),
                const SizedBox(height: 4),
                Text(valor,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10.5, color: cessumMuted(context))),
              ],
            ),
          ),
        );
    return Row(
      children: [
        kpi('$_pendientes', 'Materias\npor cursar', Icons.pending_actions),
        kpi(_promedio > 0 ? _promedio.toStringAsFixed(1) : '—', 'Promedio\ngeneral',
            Icons.grade),
        kpi(_egreso.isEmpty ? '—' : _egreso, 'Egreso\naprox.', Icons.event_available),
      ],
    );
  }

  Widget _bloqueCiclo(Map<String, dynamic> c) {
    final materias = ((c['materias'] as List<dynamic>? ?? []))
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final aprob = materias.where((m) => m['estado'] == 'Aprobada').length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((c['ciclo'] ?? '').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: cessumRed)),
                ),
                Text('$aprob/${materias.length}',
                    style: TextStyle(
                        fontSize: 12.5, color: cessumMuted(context))),
              ],
            ),
            const SizedBox(height: 4),
            ...materias.map(_itemMateria),
          ],
        ),
      ),
    );
  }

  Widget _itemMateria(Map<String, dynamic> m) {
    final aprobada = m['estado'] == 'Aprobada';
    final cal = (m['cal'] ?? '').toString();
    final cr = (m['creditos'] ?? 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(aprobada ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: aprobada ? const Color(0xFF1E8E3E) : cessumFaint(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((m['materia'] ?? '').toString(),
                    style: const TextStyle(fontSize: 13)),
                if (cr is num && cr > 0)
                  Text('$cr créditos',
                      style: TextStyle(
                          fontSize: 10.5, color: cessumFaint(context))),
              ],
            ),
          ),
          if (aprobada)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E8E3E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(cal.isEmpty ? 'Aprobada' : cal,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E8E3E))),
            )
          else
            Text('Pendiente',
                style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
        ],
      ),
    );
  }
}
