import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';

/// Eventos institucionales y confirmación de asistencia (RSVP) del alumno.
class EventosScreen extends StatefulWidget {
  final StudentProfile perfil;
  const EventosScreen({super.key, required this.perfil});

  @override
  State<EventosScreen> createState() => _EventosScreenState();
}

class _EventosScreenState extends State<EventosScreen> {
  List<Map<String, dynamic>> _eventos = [];
  bool _cargando = true;
  String? _enviandoId;
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
      final uri = Uri.parse('$guardianUrl?accion=eventos_listar'
          '&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _eventos = ((data['eventos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los eventos.';
      });
    }
  }

  Future<void> _responder(Map<String, dynamic> ev, String respuesta) async {
    setState(() => _enviandoId = ev['id'].toString());
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'evento_confirmar',
                'id': ev['id'],
                'matricula': widget.perfil.matricula,
                'nombre': widget.perfil.nombreCompleto,
                'respuesta': respuesta,
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('Respuesta registrada: $respuesta'),
        ));
      }
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _enviandoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Eventos',
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
              : _eventos.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No hay eventos por ahora.',
                            style: TextStyle(color: Colors.black54)),
                      ),
                    )
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _eventos.length,
                        itemBuilder: (ctx, i) => _tarjeta(_eventos[i]),
                      ),
                    ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> ev) {
    final miResp = (ev['miRespuesta'] ?? '').toString();
    final enviando = _enviandoId == ev['id'].toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${ev['titulo']}',
                style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: cessumRed)),
            if ((ev['descripcion'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('${ev['descripcion']}',
                  style: const TextStyle(fontSize: 13, height: 1.4)),
            ],
            const SizedBox(height: 10),
            if ((ev['fechaEvento'] ?? '').toString().isNotEmpty)
              _linea(Icons.event, '${ev['fechaEvento']}'),
            if ((ev['lugar'] ?? '').toString().isNotEmpty)
              _linea(Icons.location_on, '${ev['lugar']}'),
            const Divider(height: 22),
            if (miResp.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (miResp == 'Asistiré'
                          ? const Color(0xFF1E8E3E)
                          : Colors.grey)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                        miResp == 'Asistiré'
                            ? Icons.check_circle
                            : Icons.cancel,
                        size: 18,
                        color: miResp == 'Asistiré'
                            ? const Color(0xFF1E8E3E)
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Text('Respondiste: $miResp',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton(
                      onPressed: enviando
                          ? null
                          : () => _responder(
                              ev,
                              miResp == 'Asistiré'
                                  ? 'No asistiré'
                                  : 'Asistiré'),
                      child: const Text('Cambiar',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E8E3E),
                        foregroundColor: Colors.white,
                      ),
                      onPressed:
                          enviando ? null : () => _responder(ev, 'Asistiré'),
                      icon: enviando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check, size: 18),
                      label: const Text('Asistiré'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black54,
                        side: const BorderSide(color: Colors.black26),
                      ),
                      onPressed: enviando
                          ? null
                          : () => _responder(ev, 'No asistiré'),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('No asistiré'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _linea(IconData icono, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icono, size: 16, color: cessumGold),
          const SizedBox(width: 8),
          Expanded(
              child: Text(texto, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }
}
