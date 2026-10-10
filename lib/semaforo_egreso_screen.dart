import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';

// =====================================================================
// PANTALLA: "Semáforo de egreso" (ADMINISTRADOR)
// ---------------------------------------------------------------------
// Muestra el avance curricular de cada alumno (materias validadas vs.
// total del plan) frente al tiempo transcurrido de su generación, y
// estima su mes de egreso. Permite detectar rezago y egresos vencidos.
//
// CONTRATO (Code.gs -> semaforo_egreso):
//   { ok, resumen:{completo,enRuta,rezagoLeve,rezagoCritico,vencido,
//                  sinDatos,total},
//     alumnos:[{matricula,nombre,programa,generacion,validadas,totalPlan,
//               avancePct,tiempoPct,estado,finEstimado,mesesRestantes,sev}] }
// =====================================================================

const Color _hueso = Color(0xFFF5F1E8);

class SemaforoEgresoScreen extends StatefulWidget {
  const SemaforoEgresoScreen({super.key});

  @override
  State<SemaforoEgresoScreen> createState() => _SemaforoEgresoScreenState();
}

class _SemaforoEgresoScreenState extends State<SemaforoEgresoScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _alumnos = [];
  String _filtro = 'Todos';

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
          .replace(queryParameters: {'accion': 'semaforo_egreso'});
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
        _error = 'No se pudo cargar el semaforo de egreso.';
      });
    }
  }

  Color _color(String estado) {
    switch (estado) {
      case 'Egreso vencido':
      case 'Rezago crítico':
        return cessumRed;
      case 'Rezago leve':
        return Colors.orange.shade800;
      case 'En ruta':
        return Colors.green.shade700;
      case 'Completó plan':
        return Colors.teal.shade600;
      default:
        return Colors.blueGrey;
    }
  }

  bool _coincideFiltro(Map<String, dynamic> a) {
    if (_filtro == 'Todos') return true;
    final e = (a['estado'] ?? '').toString();
    if (_filtro == 'Rezago') {
      return e == 'Rezago leve' || e == 'Rezago crítico';
    }
    return e == _filtro;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hueso,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Semáforo de egreso'),
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

    final visibles = _alumnos.where(_coincideFiltro).toList();

    return RefreshIndicator(
      onRefresh: _cargar,
      color: cessumRed,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _resumenCard(),
          const SizedBox(height: 10),
          _chipsFiltro(),
          const SizedBox(height: 4),
          if (visibles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text('Sin alumnos en esta categoría.',
                    style: TextStyle(color: Colors.black54)),
              ),
            )
          else
            ...visibles.map(_ficha),
          const SizedBox(height: 16),
          const Text(
            'El avance compara materias validadas contra el total del plan. '
            'La marca vertical indica dónde debería ir el alumno según el '
            'tiempo transcurrido de su generación. El mes de egreso es una '
            'estimación basada en la duración del programa.',
            style:
                TextStyle(fontSize: 11.5, color: Colors.black45, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _resumenCard() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Avance de ${_resumen['total'] ?? 0} alumnos',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              _mini('Vencidos', _resumen['vencido'], cessumRed),
              _mini('Críticos', _resumen['rezagoCritico'],
                  Colors.deepOrange.shade700),
              _mini('Rezago', _resumen['rezagoLeve'], Colors.orange.shade800),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _mini('En ruta', _resumen['enRuta'], Colors.green.shade700),
              _mini('Completó', _resumen['completo'], Colors.teal.shade600),
              _mini('Sin plan', _resumen['sinDatos'], Colors.blueGrey),
            ],
          ),
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

  Widget _chipsFiltro() {
    const opciones = [
      'Todos',
      'Egreso vencido',
      'Rezago crítico',
      'Rezago',
      'En ruta',
      'Completó plan'
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: opciones.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final o = opciones[i];
          final sel = _filtro == o;
          return ChoiceChip(
            label: Text(o, style: const TextStyle(fontSize: 12)),
            selected: sel,
            onSelected: (_) => setState(() => _filtro = o),
            selectedColor: cessumRed,
            labelStyle: TextStyle(
                color: sel ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          );
        },
      ),
    );
  }

  Widget _ficha(Map<String, dynamic> a) {
    final estado = (a['estado'] ?? '').toString();
    final color = _color(estado);
    final avance = (a['avancePct'] is num) ? (a['avancePct'] as num) / 100 : null;
    final tiempo = (a['tiempoPct'] is num) ? (a['tiempoPct'] as num) / 100 : null;
    final meses = a['mesesRestantes'];

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
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Text(estado,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (avance != null) _barraAvance(avance, tiempo, color),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _pill('${a['validadas'] ?? 0}/${a['totalPlan'] ?? 0} materias'),
                if (a['avancePct'] is num) _pill('${a['avancePct']}% avance'),
                if ((a['finEstimado'] ?? '').toString().isNotEmpty)
                  _pill('Egreso ~ ${a['finEstimado']}'),
                if (meses is num)
                  _pill(meses >= 0
                      ? 'faltan ${meses.toInt()} meses'
                      : 'vencido ${(-meses).toInt()} meses'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _barraAvance(double avance, double? tiempo, Color color) {
    final a = avance.clamp(0.0, 1.0);
    return SizedBox(
      height: 14,
      child: Stack(
        children: [
          // Track
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFFF1ECE0),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          // Avance real
          FractionallySizedBox(
            widthFactor: a == 0 ? 0.02 : a,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
          // Marca de tiempo esperado
          if (tiempo != null)
            Align(
              alignment: Alignment(
                  (tiempo.clamp(0.0, 1.0) * 2) - 1, 0),
              child: Container(
                width: 3,
                height: 18,
                color: Colors.black54,
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1ECE0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(texto,
          style: const TextStyle(fontSize: 11, color: Colors.black87)),
    );
  }
}
