import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Admin: revisa solicitudes de constancia de no adeudo, ve el estado de
/// pagos de cada alumno y aprueba (emite el PDF) o rechaza con motivo.
class NoAdeudoAdminScreen extends StatefulWidget {
  const NoAdeudoAdminScreen({super.key});

  @override
  State<NoAdeudoAdminScreen> createState() => _NoAdeudoAdminScreenState();
}

class _NoAdeudoAdminScreenState extends State<NoAdeudoAdminScreen> {
  List<Map<String, dynamic>> _lista = [];
  String _filtro = 'Pendiente';
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
      final uri = Uri.parse('$guardianUrl?accion=noadeudo_listar'
          '${_filtro != 'Todas' ? '&estatus=${Uri.encodeComponent(_filtro)}' : ''}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _lista = (data['solicitudes'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar las solicitudes.';
      });
    }
  }

  Future<void> _resolver(
      Map<String, dynamic> s, String decision) async {
    String motivo = '';
    if (decision == 'Rechazada') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Motivo del rechazo'),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Se le informará al alumno.',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rechazar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      motivo = ctrl.text.trim();
    } else {
      // confirmar aprobación, advirtiendo si tiene adeudo
      final alCorriente = s['alCorriente'] == true;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Aprobar y emitir'),
          content: Text(alCorriente
              ? 'Se emitirá la constancia de no adeudo de ${s['nombre']} y se le enviará por correo.'
              : '⚠️ ${s['nombre']} tiene adeudos pendientes registrados. ¿Aun así deseas emitir la constancia?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E8E3E),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aprobar y emitir'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'noadeudo_resolver',
                'fila': s['fila'],
                'decision': decision,
                'motivo': motivo,
              }))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text(decision == 'Aprobada'
              ? 'Constancia emitida y enviada.'
              : 'Solicitud rechazada.'),
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
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtros = ['Pendiente', 'Aprobada', 'Rechazada', 'Todas'];
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Constancias de no adeudo',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: filtros.map((f) {
                final activo = _filtro == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f),
                    selected: activo,
                    selectedColor: cessumRed.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      color: activo ? cessumRed : Colors.black87,
                      fontWeight: activo ? FontWeight.w700 : FontWeight.w400,
                    ),
                    onSelected: (_) {
                      setState(() => _filtro = f);
                      _cargar();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          if (_procesando) const LinearProgressIndicator(color: cessumRed),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 8),
                            TextButton(
                                onPressed: _cargar,
                                child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : _lista.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Sin solicitudes en este filtro.',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: _lista.length,
                            itemBuilder: (ctx, i) => _tarjeta(_lista[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> s) {
    final estatus = (s['estatus'] ?? '') as String;
    final alCorriente = s['alCorriente'] == true;
    final pendientes = (s['pendientes'] as List?) ?? [];
    final esPendiente = estatus == 'Pendiente';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${s['nombre']} (${s['matricula']})',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: alCorriente
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFDECEA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    alCorriente ? 'Al corriente' : '${pendientes.length} adeudo(s)',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: alCorriente
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFF8B1A1A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text('${s['programa']} · ${s['folio']} · ${s['fecha']}',
                style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            if (pendientes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  pendientes
                      .map((p) =>
                          '• ${(p as Map)['concepto']} (${p['estatus']})')
                      .join('\n'),
                  style: const TextStyle(fontSize: 11.5, color: cessumRed),
                ),
              ),
            if (esPendiente) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: cessumRed,
                          side: const BorderSide(color: cessumRed)),
                      onPressed:
                          _procesando ? null : () => _resolver(s, 'Rechazada'),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E8E3E),
                          foregroundColor: Colors.white),
                      onPressed:
                          _procesando ? null : () => _resolver(s, 'Aprobada'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Aprobar'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                      estatus == 'Aprobada'
                          ? Icons.check_circle
                          : Icons.cancel,
                      size: 16,
                      color: estatus == 'Aprobada'
                          ? const Color(0xFF1E8E3E)
                          : cessumRed),
                  const SizedBox(width: 6),
                  Text(estatus,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: estatus == 'Aprobada'
                              ? const Color(0xFF1E8E3E)
                              : cessumRed)),
                  const Spacer(),
                  if (estatus == 'Aprobada' &&
                      (s['enlace'] ?? '').toString().isNotEmpty)
                    TextButton.icon(
                      onPressed: () => Helpers.abrirUrlExterna(
                          s['enlace'].toString(), context),
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('PDF', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              if (estatus == 'Rechazada' &&
                  (s['motivo'] ?? '').toString().isNotEmpty)
                Text('Motivo: ${s['motivo']}',
                    style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            ],
          ],
        ),
      ),
    );
  }
}
