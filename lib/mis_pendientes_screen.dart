import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'tesis_convenio_screen.dart';
import 'mis_tramites_screen.dart';
import 'encuesta_screen.dart';
import 'mi_titulacion_screen.dart';
import 'mi_pagos_screen.dart';

/// Alumno: "Mis pendientes". Tablero accionable de "qué me toca ahora":
/// cuotas por pagar, convenio/hito de tesis, evaluaciones, trámites y
/// titulación. Lee el agregador del Guardián (accion=mis_pendientes) y
/// enruta a las pantallas existentes según el tipo de pendiente.
class MisPendientesScreen extends StatefulWidget {
  final String matricula;
  final String nombre;
  final String correo;
  const MisPendientesScreen({
    super.key,
    required this.matricula,
    this.nombre = '',
    this.correo = '',
  });

  @override
  State<MisPendientesScreen> createState() => _MisPendientesScreenState();
}

class _MisPendientesScreenState extends State<MisPendientesScreen> {
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _pendientes = [];
  Map<String, dynamic> _resumen = {};

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
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_pendientes',
        'matricula': widget.matricula,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _pendientes = ((data['pendientes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _resumen = Map<String, dynamic>.from((data['resumen'] as Map?) ?? {});
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus pendientes. Revisa tu conexión.';
      });
    }
  }

  Color _colorUrg(String u) {
    switch (u) {
      case 'alta':
        return cessumRed;
      case 'media':
        return cessumGold;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _iconoTipo(String t) {
    switch (t) {
      case 'pago':
        return Icons.payments;
      case 'tesis':
        return Icons.menu_book;
      case 'encuesta':
        return Icons.fact_check;
      case 'tramite':
        return Icons.description;
      case 'titulacion':
        return Icons.school;
      default:
        return Icons.notifications_active;
    }
  }

  void _ir(String accion) {
    Widget? destino;
    switch (accion) {
      case 'pago':
        destino = MiPagosScreen(
          matriculaForzada: widget.matricula,
          nombreAlumno: widget.nombre,
        );
        break;
      case 'tesis':
        destino = TesisConvenioScreen(
          matricula: widget.matricula,
          nombre: widget.nombre,
          correo: widget.correo,
          rol: 'alumno',
        );
        break;
      case 'encuesta':
        destino = const EncuestaScreen();
        break;
      case 'tramites':
        destino = MisTramitesScreen(matricula: widget.matricula);
        break;
      case 'titulacion':
        destino = const MiTitulacionScreen();
        break;
    }
    if (destino != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => destino!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis pendientes'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(child: Text(_error)),
                    const SizedBox(height: 12),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _cargar,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ),
                  ])
                : _pendientes.isEmpty
                    ? _vacio()
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _encabezado(),
                          const SizedBox(height: 12),
                          ..._pendientes.map(_tarjeta),
                        ],
                      ),
      ),
    );
  }

  Widget _encabezado() {
    final alta = '${_resumen['alta'] ?? 0}';
    final media = '${_resumen['media'] ?? 0}';
    final baja = '${_resumen['baja'] ?? 0}';
    return Row(children: [
      _chipResumen('Urgentes', alta, cessumRed),
      const SizedBox(width: 8),
      _chipResumen('Pronto', media, cessumGold),
      const SizedBox(width: 8),
      _chipResumen('Después', baja, Colors.blueGrey),
    ]);
  }

  Widget _chipResumen(String etiqueta, String valor, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(children: [
          Text(valor,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(etiqueta, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> p) {
    final u = '${p['urgencia'] ?? 'baja'}';
    final color = _colorUrg(u);
    final tipo = '${p['tipo'] ?? ''}';
    final accion = '${p['accion'] ?? ''}';
    final titulo = '${p['titulo'] ?? ''}';
    final detalle = '${p['detalle'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconoTipo(tipo), color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                if (detalle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detalle,
                      style: TextStyle(color: cessumMuted(context))),
                ],
                if (accion.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Resolver'),
                      onPressed: () => _ir(accion),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _vacio() {
    return ListView(children: [
      const SizedBox(height: 90),
      const Icon(Icons.check_circle, color: Colors.green, size: 64),
      const SizedBox(height: 12),
      const Center(
        child: Text('¡Estás al día!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(height: 4),
      Center(
        child: Text('No tienes pendientes por ahora.',
            style: TextStyle(color: cessumMuted(context))),
      ),
      const SizedBox(height: 16),
      Center(
        child: OutlinedButton.icon(
          onPressed: _cargar,
          icon: const Icon(Icons.refresh),
          label: const Text('Actualizar'),
        ),
      ),
    ]);
  }
}
