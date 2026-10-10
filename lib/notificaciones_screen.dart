import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Buzón de notificaciones dentro de la app. Lo usan alumno y docente.
/// Consulta por correo y/o matrícula y muestra los avisos del usuario.
class NotificacionesScreen extends StatefulWidget {
  final String correo;
  final String matricula;

  const NotificacionesScreen({
    super.key,
    required this.correo,
    this.matricula = '',
  });

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _cargando = true;
  bool _procesando = false;
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
      final uri = Uri.parse('$guardianUrl?accion=notificaciones'
          '&correo=${Uri.encodeComponent(widget.correo)}'
          '&matricula=${Uri.encodeComponent(widget.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _items = ((data['notificaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar las notificaciones.';
      });
    }
  }

  Future<void> _marcarLeida(Map<String, dynamic> n) async {
    if (n['leida'] == true) return;
    setState(() => n['leida'] = true); // feedback inmediato
    try {
      await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'notificacion_marcar_leida',
                'id': n['id'],
              }))
          .timeout(const Duration(seconds: 30));
    } catch (_) {}
  }

  Future<void> _marcarTodas() async {
    setState(() => _procesando = true);
    try {
      await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'notificaciones_marcar_todas',
                'correo': widget.correo,
                'matricula': widget.matricula,
              }))
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        for (final n in _items) {
          n['leida'] = true;
        }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  IconData _icono(String tipo) {
    switch (tipo) {
      case 'calificacion':
        return Icons.grading;
      case 'tramite':
        return Icons.description;
      case 'aviso':
        return Icons.campaign;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hayNoLeidas = _items.any((n) => n['leida'] != true);
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Notificaciones',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          if (hayNoLeidas)
            TextButton(
              onPressed: _procesando ? null : _marcarTodas,
              child: const Text('Marcar todas',
                  style: TextStyle(color: Colors.white, fontSize: 12.5)),
            ),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
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
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none,
                                size: 56, color: cessumFaint(context)),
                            const SizedBox(height: 12),
                            Text('No tienes notificaciones por ahora.',
                                style: TextStyle(color: cessumMuted(context))),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      color: cessumRed,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        itemBuilder: (ctx, i) => _fila(_items[i]),
                      ),
                    ),
    );
  }

  Widget _fila(Map<String, dynamic> n) {
    final leida = n['leida'] == true;
    final tipo = (n['tipo'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: leida
          ? null
          : (cessumEsOscuro(context)
              ? const Color(0xFF2A211F)
              : const Color(0xFFFDF3F4)),
      child: ListTile(
        onTap: () => _marcarLeida(n),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: leida ? 0.07 : 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_icono(tipo),
              color: leida ? cessumFaint(context) : cessumRed, size: 20),
        ),
        title: Text('${n['titulo']}',
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: leida ? FontWeight.w600 : FontWeight.w800)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('${n['mensaje']}',
                style: const TextStyle(fontSize: 12.5, height: 1.3)),
            const SizedBox(height: 4),
            Text('${n['fecha']}',
                style: TextStyle(fontSize: 10.5, color: cessumFaint(context))),
          ],
        ),
        trailing: leida
            ? null
            : Container(
                width: 9,
                height: 9,
                decoration:
                    const BoxDecoration(color: cessumRed, shape: BoxShape.circle),
              ),
      ),
    );
  }
}
