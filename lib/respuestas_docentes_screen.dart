import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// MEJORA 1 — Respuestas de docentes (estado de invitaciones).
///
/// Muestra, por cada materia programada, si el docente está PENDIENTE de
/// responder, ACEPTÓ (con el día y la hora que eligió) o RECHAZÓ, junto con
/// sus comentarios. Permite reenviar la invitación con un toque.
///
/// Se alimenta de la acción `asignaciones_listar` (que ya devuelve
/// invitacionEstado, dia, hora, comentarios) y reenvía con
/// `asignacion_invitar` (solo necesita la fila). No toca nada más de la app.
class RespuestasDocentesScreen extends StatefulWidget {
  const RespuestasDocentesScreen({super.key});

  @override
  State<RespuestasDocentesScreen> createState() =>
      _RespuestasDocentesScreenState();
}

class _RespuestasDocentesScreenState extends State<RespuestasDocentesScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _asignaciones = [];
  String _filtro = 'Todas'; // Todas / Pendiente / Aceptada / Rechazada / Sin correo
  final TextEditingController _busqueda = TextEditingController();
  final Set<int> _reenviando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'asignaciones_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final lista = (data['asignaciones'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _asignaciones = lista;
          _cargando = false;
        });
      } else {
        setState(() {
          _error = (data['error'] ?? 'No se pudo cargar').toString();
          _cargando = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Sin conexión o error: $e';
        _cargando = false;
      });
    }
  }

  Future<void> _reenviar(Map<String, dynamic> a) async {
    final fila = int.tryParse('${a['fila']}') ?? 0;
    if (fila < 2) return;
    setState(() => _reenviando.add(fila));
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'asignacion_invitar', 'fila': fila}))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true && data['enviado'] == true) {
        _aviso('Invitación reenviada a ${a['docente']}.');
        await _cargar();
      } else {
        _aviso((data['error'] ?? 'No se pudo reenviar.').toString(),
            error: true);
      }
    } catch (e) {
      if (mounted) _aviso('Error al reenviar: $e', error: true);
    } finally {
      if (mounted) setState(() => _reenviando.remove(fila));
    }
  }

  void _aviso(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
    ));
  }

  String _estadoDe(Map<String, dynamic> a) {
    final correo = (a['correo'] ?? '').toString().trim();
    if (correo.isEmpty || !correo.contains('@')) return 'Sin correo';
    final est = (a['invitacionEstado'] ?? '').toString().trim();
    if (est.isEmpty) return 'Pendiente';
    return est; // Pendiente / Aceptada / Rechazada
  }

  Color _colorEstado(String est) {
    switch (est) {
      case 'Aceptada':
        return const Color(0xFF1E8E3E);
      case 'Rechazada':
        return cessumRed;
      case 'Sin correo':
        return Colors.grey;
      default:
        return cessumGold; // Pendiente
    }
  }

  List<Map<String, dynamic>> get _filtradas {
    final q = _busqueda.text.trim().toLowerCase();
    return _asignaciones.where((a) {
      final est = _estadoDe(a);
      if (_filtro != 'Todas' && est != _filtro) return false;
      if (q.isEmpty) return true;
      final blob =
          '${a['materia']} ${a['docente']} ${a['programa']} ${a['grupo']} ${a['correo']}'
              .toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final conteo = <String, int>{
      'Pendiente': 0,
      'Aceptada': 0,
      'Rechazada': 0,
      'Sin correo': 0,
    };
    for (final a in _asignaciones) {
      final e = _estadoDe(a);
      conteo[e] = (conteo[e] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Respuestas de docentes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _vistaError()
              : Column(
                  children: [
                    _resumen(conteo),
                    _filtros(),
                    Expanded(child: _lista()),
                  ],
                ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _resumen(Map<String, int> c) {
    Widget chip(String etq, int n, Color color) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text('$n',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              Text(etq,
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
      child: Row(
        children: [
          chip('Pendientes', c['Pendiente'] ?? 0, cessumGold),
          chip('Aceptadas', c['Aceptada'] ?? 0, const Color(0xFF1E8E3E)),
          chip('Rechazadas', c['Rechazada'] ?? 0, cessumRed),
          chip('Sin correo', c['Sin correo'] ?? 0, Colors.grey),
        ],
      ),
    );
  }

  Widget _filtros() {
    const ops = ['Todas', 'Pendiente', 'Aceptada', 'Rechazada', 'Sin correo'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Column(
        children: [
          TextField(
            controller: _busqueda,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Buscar materia, docente, grupo…',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ops.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final sel = _filtro == ops[i];
                return ChoiceChip(
                  label: Text(ops[i]),
                  selected: sel,
                  selectedColor: cessumRed,
                  labelStyle: TextStyle(
                      color: sel ? Colors.white : Colors.black87,
                      fontSize: 12),
                  onSelected: (_) => setState(() => _filtro = ops[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _lista() {
    final items = _filtradas;
    if (items.isEmpty) {
      return const Center(
        child: Text('No hay asignaciones con ese filtro.',
            style: TextStyle(color: Colors.black54)),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: items.length,
        itemBuilder: (_, i) => _tarjeta(items[i]),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final est = _estadoDe(a);
    final color = _colorEstado(est);
    final fila = int.tryParse('${a['fila']}') ?? 0;
    final reenviando = _reenviando.contains(fila);
    final dia = (a['dia'] ?? '').toString().trim();
    final hora = (a['hora'] ?? '').toString().trim();
    final coment = (a['comentarios'] ?? '').toString().trim();
    final correo = (a['correo'] ?? '').toString().trim();
    final puedeReenviar = correo.contains('@') && est != 'Aceptada';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text((a['materia'] ?? '(sin materia)').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(est,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                '${a['programa']} · Grupo ${a['grupo']} · Gen. ${a['generacion']}',
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 16, color: Colors.black45),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                      correo.isEmpty
                          ? (a['docente'] ?? '(sin docente)').toString()
                          : '${a['docente']}  ($correo)',
                      style: const TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
            if (est == 'Aceptada' && (dia.isNotEmpty || hora.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.event_available,
                      size: 16, color: Color(0xFF1E8E3E)),
                  const SizedBox(width: 4),
                  Text('Eligió: $dia ${hora.isNotEmpty ? '· $hora' : ''}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF1E8E3E),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            if (coment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F6F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('“$coment”',
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic)),
              ),
            ],
            if (puedeReenviar) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: reenviando ? null : () => _reenviar(a),
                  icon: reenviando
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.mail_outline, size: 16),
                  label: Text(reenviando ? 'Enviando…' : 'Reenviar invitación'),
                  style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                ),
              ),
            ],
            if (correo.isEmpty) ...[
              const SizedBox(height: 6),
              const Text('Sin correo del docente: no se puede invitar.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}
