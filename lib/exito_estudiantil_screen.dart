import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';

// =====================================================================
// PANTALLA: "Índice de éxito estudiantil" (ADMINISTRADOR)
// ---------------------------------------------------------------------
// Fusiona riesgo + avance curricular en un puntaje 0-100 por alumno,
// muestra el índice institucional y una lista de seguimiento priorizada
// con la intervención sugerida para cada caso.
//
// CONTRATO (Code.gs -> exito_panel):
//   { ok, resumen:{promedio,excelente,bueno,observacion,riesgo,total},
//     alumnos:[{matricula,nombre,programa,generacion,score,banda,
//               recomendacion,factores:[...],riesgoNivel,avancePct,
//               estadoEgreso,diasSinAcceso}] }
// =====================================================================

const Color _hueso = Color(0xFFF5F1E8);

class ExitoEstudiantilScreen extends StatefulWidget {
  const ExitoEstudiantilScreen({super.key});

  @override
  State<ExitoEstudiantilScreen> createState() => _ExitoEstudiantilScreenState();
}

class _ExitoEstudiantilScreenState extends State<ExitoEstudiantilScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _alumnos = [];

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
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'exito_panel'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      if (!mounted) return;
      setState(() {
        _resumen = (data['resumen'] as Map<String, dynamic>?) ?? {};
        _alumnos = ((data['alumnos'] as List?) ?? [])
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el indice de exito.';
      });
    }
  }

  Color _colorBanda(String banda) {
    switch (banda) {
      case 'Excelente':
        return Colors.teal.shade600;
      case 'Bueno':
        return Colors.green.shade700;
      case 'En observación':
        return Colors.orange.shade800;
      default:
        return cessumRed;
    }
  }

  Color _colorScore(int s) {
    if (s >= 80) return Colors.teal.shade600;
    if (s >= 60) return Colors.green.shade700;
    if (s >= 40) return Colors.orange.shade800;
    return cessumRed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hueso,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Índice de éxito'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52, color: cessumRed),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _cargar,
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
                child: const Text('Reintentar',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final prom = _resumen['promedio'];
    final promInt = (prom is num) ? prom.toInt() : null;

    return RefreshIndicator(
      onRefresh: _cargar,
      color: cessumRed,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _hero(promInt),
          const SizedBox(height: 12),
          _distribucion(),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Lista de seguimiento (${_alumnos.length})',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          if (_alumnos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Ningún alumno requiere seguimiento. Excelente salud académica.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ..._alumnos.map(_ficha),
          const SizedBox(height: 16),
          const Text(
            'El índice combina el riesgo académico (calificaciones y '
            'actividad) con el avance curricular frente al tiempo. 100 = '
            'trayectoria óptima. La lista muestra a quienes están por debajo '
            'de 60, ordenados del más urgente al menos.',
            style:
                TextStyle(fontSize: 11.5, color: Colors.black45, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _hero(int? prom) {
    final color = prom == null ? Colors.blueGrey : _colorScore(prom);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: color, width: 3),
            ),
            alignment: Alignment.center,
            child: Text(
              prom?.toString() ?? '—',
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Índice de éxito institucional',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Promedio de ${_resumen['total'] ?? 0} alumnos en curso. '
                  'Sobre 100 puntos.',
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _distribucion() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          _mini('Excelente', _resumen['excelente'], Colors.teal.shade600),
          _mini('Bueno', _resumen['bueno'], Colors.green.shade700),
          _mini('Observación', _resumen['observacion'], Colors.orange.shade800),
          _mini('En riesgo', _resumen['riesgo'], cessumRed),
        ],
      ),
    );
  }

  Widget _mini(String etiqueta, dynamic valor, Color color) {
    final v = (valor is num) ? valor.toInt() : 0;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$v',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(etiqueta,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _ficha(Map<String, dynamic> a) {
    final banda = (a['banda'] ?? '').toString();
    final color = _colorBanda(banda);
    final score = (a['score'] is num) ? (a['score'] as num).toInt() : 0;
    final factores = ((a['factores'] as List?) ?? []).cast<dynamic>();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.12),
                    border: Border.all(color: color, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text('$score',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((a['nombre'] ?? '').toString(),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      Text(
                        '${a['matricula'] ?? ''} · ${a['programa'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Text(banda,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Intervención sugerida
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag_rounded, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (a['recomendacion'] ?? '').toString(),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color),
                    ),
                  ),
                ],
              ),
            ),
            if (factores.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...factores.map((f) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ',
                            style: TextStyle(
                                fontSize: 12.5, color: Colors.black45)),
                        Expanded(
                          child: Text(f.toString(),
                              style: const TextStyle(
                                  fontSize: 12.5, color: Colors.black87)),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
