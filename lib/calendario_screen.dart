import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_header.dart';
import 'cargando_venado.dart';

/// Calendario académico: fechas clave (pagos, exámenes, reinscripción,
/// eventos y asuetos) que la institución publica desde la hoja "Calendario".
class CalendarioScreen extends StatefulWidget {
  const CalendarioScreen({super.key});

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  List<Map<String, dynamic>> _eventos = [];
  bool _cargando = true;
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
      final uri = Uri.parse('$guardianUrl?accion=calendario');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('Error');
      if (!mounted) return;
      setState(() {
        _eventos = (data['eventos'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el calendario.';
      });
    }
  }

  Color _colorTipo(String t) {
    switch (t.toLowerCase()) {
      case 'pago':
        return cessumRed;
      case 'reinscripción':
      case 'reinscripcion':
        return cessumGold;
      case 'examen':
        return const Color(0xFF1E8E3E);
      case 'asueto':
        return Colors.blueGrey;
      default:
        return cessumRed;
    }
  }

  IconData _iconoTipo(String t) {
    switch (t.toLowerCase()) {
      case 'pago':
        return Icons.payments;
      case 'reinscripción':
      case 'reinscripcion':
        return Icons.how_to_reg;
      case 'examen':
        return Icons.assignment;
      case 'asueto':
        return Icons.beach_access;
      default:
        return Icons.event;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CessumAppBar(titulo: 'Calendario académico'),
      body: _cargando
          ? const CargandoVenado()
          : _error != null
              ? Center(child: Text(_error!))
              : _eventos.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Aún no hay fechas publicadas.',
                            textAlign: TextAlign.center),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _eventos.length,
                        itemBuilder: (context, i) {
                          final e = _eventos[i];
                          final tipo = (e['tipo'] ?? 'Evento').toString();
                          final color = _colorTipo(tipo);
                          final detalle = (e['detalle'] ?? '').toString();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: color.withValues(alpha: 0.15),
                                child: Icon(_iconoTipo(tipo), color: color),
                              ),
                              title: Text(
                                (e['titulo'] ?? '').toString(),
                                style:
                                    const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                '${(e['fecha'] ?? '').toString()}'
                                '${detalle.isNotEmpty ? '\n$detalle' : ''}',
                              ),
                              isThreeLine: detalle.isNotEmpty,
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  tipo,
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
