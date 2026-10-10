import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// Vista del docente: el avance de captura de calificaciones de sus propios
/// grupos. Le muestra cuáles ya completó y cuáles le faltan. Solo lectura.
class MiCapturaScreen extends StatefulWidget {
  const MiCapturaScreen({super.key});

  @override
  State<MiCapturaScreen> createState() => _MiCapturaScreenState();
}

class _MiCapturaScreenState extends State<MiCapturaScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _asignaciones = [];

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
      final correo = (await SessionStore.validEmail()) ?? '';
      if (correo.isEmpty) {
        setState(() {
          _cargando = false;
          _error = 'No encontré tu sesión. Vuelve a iniciar sesión.';
        });
        return;
      }
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=avance_captura_docente'
              '&correo=${Uri.encodeComponent(correo)}'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _resumen = Map<String, dynamic>.from((data['resumen'] as Map?) ?? {});
        _asignaciones = ((data['asignaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar tu avance de captura.';
      });
    }
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'completa':
        return _verde;
      case 'parcial':
        return cessumGold;
      case 'sin_iniciar':
        return cessumRed;
      default:
        return cessumIsDark(context) ? Colors.white54 : cessumFaint(context);
    }
  }

  String _textoEstado(String estado) {
    switch (estado) {
      case 'completa':
        return 'Completa';
      case 'parcial':
        return 'Parcial';
      case 'sin_iniciar':
        return 'Sin iniciar';
      default:
        return 'Sin alumnos';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Avance de captura',
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
              : _asignaciones.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          'No tienes grupos activos con clave de materia para medir captura.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cessumMuted(context)),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                        children: [
                          _banner(),
                          const SizedBox(height: 14),
                          ..._asignaciones.map(_tarjeta),
                        ],
                      ),
                    ),
    );
  }

  Widget _banner() {
    final completas = (_resumen['completas'] ?? 0) as int;
    final parciales = (_resumen['parciales'] ?? 0) as int;
    final sinIniciar = (_resumen['sinIniciar'] ?? 0) as int;
    final pendientes = parciales + sinIniciar;
    final color = pendientes == 0 ? _verde : cessumRed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pendientes == 0
                ? '¡Vas al día! Toda tu captura está completa.'
                : 'Te faltan $pendientes grupo(s) por completar.',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            children: [
              _kpi('Completas', completas, _verde),
              _kpi('Parciales', parciales, cessumGold),
              _kpi('Sin iniciar', sinIniciar, cessumRed),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(String etiqueta, int valor, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$valor $etiqueta',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final estado = (a['estado'] ?? '').toString();
    final color = _colorEstado(estado);
    final total = (a['total'] ?? 0) as int;
    final cap = (a['capturadas'] ?? 0) as int;
    final pct = (a['porcentaje'] ?? 0) as int;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((a['materia'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_textoEstado(estado),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${a['generacion']} · grupo ${a['grupo']}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor:
                          cessumIsDark(context) ? Colors.white12 : cessumMuted(context).withValues(alpha: 0.18),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('$cap/$total',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
