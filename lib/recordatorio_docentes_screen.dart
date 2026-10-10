import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// MEJORA 3 — Recordatorio en lote a docentes pendientes.
///
/// Reúne todas las asignaciones activas cuyo docente tiene correo pero
/// todavía NO ha respondido la invitación (estado distinto de Aceptada /
/// Rechazada) y permite reenviarles la invitación de un solo golpe.
/// Usa `asignaciones_listar` para detectarlos y `asignacion_invitar`
/// (solo necesita la fila) para reenviar uno por uno. No toca nada más.
class RecordatorioDocentesScreen extends StatefulWidget {
  const RecordatorioDocentesScreen({super.key});

  @override
  State<RecordatorioDocentesScreen> createState() =>
      _RecordatorioDocentesScreenState();
}

class _RecordatorioDocentesScreenState
    extends State<RecordatorioDocentesScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _pendientes = [];
  final Set<int> _seleccion = {};

  bool _enviando = false;
  int _enviadosOk = 0;
  int _enviadosErr = 0;
  int _totalEnvio = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  bool _esPendiente(Map<String, dynamic> a) {
    final correo = (a['correo'] ?? '').toString().trim();
    if (!correo.contains('@')) return false;
    final activa = (a['activa'] ?? 'SI').toString().trim().toUpperCase();
    if (activa == 'NO') return false;
    final est = (a['invitacionEstado'] ?? '').toString().trim();
    return est != 'Aceptada' && est != 'Rechazada';
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'asignaciones_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final lista = (data['asignaciones'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where(_esPendiente)
            .toList();
        setState(() {
          _pendientes = lista;
          _seleccion
            ..clear()
            ..addAll(lista
                .map((a) => int.tryParse('${a['fila']}') ?? 0)
                .where((f) => f >= 2));
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

  Future<bool> _reenviarUno(int fila) async {
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'asignacion_invitar', 'fila': fila}))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['ok'] == true && data['enviado'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _reenviarSeleccionados() async {
    final filas = _pendientes
        .map((a) => int.tryParse('${a['fila']}') ?? 0)
        .where((f) => f >= 2 && _seleccion.contains(f))
        .toList();
    if (filas.isEmpty) {
      _aviso('No hay docentes seleccionados.', error: true);
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reenviar invitaciones'),
        content: Text(
            'Se reenviará la invitación a ${filas.length} docente(s) pendiente(s). ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              child: const Text('Reenviar a todos',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() {
      _enviando = true;
      _enviadosOk = 0;
      _enviadosErr = 0;
      _totalEnvio = filas.length;
    });
    for (final f in filas) {
      final ok = await _reenviarUno(f);
      if (!mounted) return;
      setState(() {
        if (ok) {
          _enviadosOk++;
        } else {
          _enviadosErr++;
        }
      });
    }
    if (!mounted) return;
    setState(() => _enviando = false);
    _aviso(
        'Listo: $_enviadosOk reenviada(s)${_enviadosErr > 0 ? ', $_enviadosErr con error' : ''}.',
        error: _enviadosErr > 0);
    await _cargar();
  }

  void _aviso(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Recordatorio a docentes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: (_cargando || _enviando) ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _vistaError()
              : Column(
                  children: [
                    _cabecera(),
                    if (_enviando) _progreso(),
                    Expanded(child: _lista()),
                    _barraInferior(),
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

  Widget _cabecera() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_bottom, color: cessumGold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_pendientes.length} docente(s) sin responder la invitación.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progreso() {
    final hechos = _enviadosOk + _enviadosErr;
    final frac = _totalEnvio == 0 ? 0.0 : hechos / _totalEnvio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          LinearProgressIndicator(value: frac, color: cessumRed),
          const SizedBox(height: 4),
          Text('Enviando $hechos de $_totalEnvio…',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        ],
      ),
    );
  }

  Widget _lista() {
    if (_pendientes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 48, color: Color(0xFF1E8E3E)),
              SizedBox(height: 12),
              Text('Ningún docente pendiente. Todos respondieron.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cessumMuted(context))),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: _pendientes.length,
      itemBuilder: (_, i) {
        final a = _pendientes[i];
        final fila = int.tryParse('${a['fila']}') ?? 0;
        final sel = _seleccion.contains(fila);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: CheckboxListTile(
            value: sel,
            activeColor: cessumRed,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: _enviando
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _seleccion.add(fila);
                      } else {
                        _seleccion.remove(fila);
                      }
                    }),
            title: Text((a['docente'] ?? '(sin docente)').toString(),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((a['correo'] ?? '').toString(),
                    style: const TextStyle(fontSize: 12)),
                Text(
                    '${a['materia']} · ${a['programa']} · Grupo ${a['grupo']}',
                    style:
                        const TextStyle(fontSize: 11.5, color: Colors.black54)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _barraInferior() {
    final n = _seleccion.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text('$n seleccionado(s)',
                  style: TextStyle(color: cessumMuted(context))),
            ),
            ElevatedButton.icon(
              onPressed:
                  (_enviando || _pendientes.isEmpty) ? null : _reenviarSeleccionados,
              icon: const Icon(Icons.send),
              label: const Text('Reenviar a seleccionados'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
