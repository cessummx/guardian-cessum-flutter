import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// Vista de administración: solicitudes de cambio de día/hora que envían los
/// docentes desde "Mi horario". El admin aprueba o rechaza. Al aprobar un
/// cambio PERMANENTE, el backend actualiza la asignación; el TEMPORAL solo
/// queda registrado y se avisa al docente.
class CambiosHorarioListaScreen extends StatefulWidget {
  const CambiosHorarioListaScreen({super.key});

  @override
  State<CambiosHorarioListaScreen> createState() =>
      _CambiosHorarioListaScreenState();
}

class _CambiosHorarioListaScreenState extends State<CambiosHorarioListaScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _cargando = true;
  String? _error;
  bool _soloPendientes = true;

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
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'cambios_horario_listar',
        if (_soloPendientes) 'pendientes': 'true',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        setState(() => _error = (data['error'] ?? 'Error').toString());
      } else {
        setState(() {
          _items = ((data['cambios'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _resolver(
      Map<String, dynamic> it, String estatus) async {
    final notaCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(estatus == 'Aprobado' ? 'Aprobar solicitud' : 'Rechazar solicitud',
            style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${it['materia']} · ${it['docente']}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              it['tipo'] == 'Permanente'
                  ? 'Cambio PERMANENTE a ${it['diaSolicitado']} ${it['horaSolicitada']}. Al aprobar se actualizará el horario fijo.'
                  : 'Cambio TEMPORAL: sesión del ${it['fechaTemporal']} a las ${it['horaSolicitada']}.',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notaCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Nota para el docente (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    estatus == 'Aprobado' ? const Color(0xFF1E8E3E) : cessumRed,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(estatus == 'Aprobado' ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    final quien = await SessionStore.realEmail();
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'cambio_horario_resolver',
        'fila': (it['fila'] ?? '').toString(),
        'estatus': estatus,
        'resueltoPor': quien ?? 'Administración',
        'nota': notaCtrl.text.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        final aplicado = data['aplicado'] == true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(estatus == 'Aprobado'
              ? (aplicado
                  ? 'Aprobado. El horario fijo se actualizó.'
                  : 'Aprobado. Se avisó al docente.')
              : 'Rechazado. Se avisó al docente.'),
        ));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo: ${data['error'] ?? 'error'}')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error de conexión.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Cambios de día/hora'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Solo pendientes'),
                  selected: _soloPendientes,
                  onSelected: (v) {
                    setState(() => _soloPendientes = v);
                    _cargar();
                  },
                ),
                const Spacer(),
                Text('${_items.length} solicitud(es)',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? const Center(
                            child: Text('No hay solicitudes.',
                                style: TextStyle(color: Colors.black54)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _items.length,
                            itemBuilder: (_, i) => _tarjeta(_items[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> it) {
    final tipo = (it['tipo'] ?? '').toString();
    final estatus = (it['estatus'] ?? '').toString();
    final esTemporal = tipo == 'Temporal';
    final pendiente = estatus == 'Pendiente';

    Color colorEstatus;
    switch (estatus) {
      case 'Aprobado':
        colorEstatus = const Color(0xFF1E8E3E);
        break;
      case 'Rechazado':
        colorEstatus = cessumRed;
        break;
      default:
        colorEstatus = cessumGold;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (esTemporal ? cessumGold : cessumRed)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(tipo,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: esTemporal
                              ? const Color(0xFF8A6118)
                              : cessumRed)),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorEstatus.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(estatus,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorEstatus)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${it['materia']}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            Text('${it['docente']}',
                style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
            Text(
              '${it['programa']} · ${it['generacion']} · Grupo ${it['grupo']}',
              style: const TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            _linea('Actual',
                '${it['diaActual'] == '' ? '(sin día)' : it['diaActual']} ${it['horaActual']}'),
            if (esTemporal)
              _linea('Solicita', 'Mover la sesión del ${it['fechaTemporal']} a ${it['horaSolicitada']}')
            else
              _linea('Solicita',
                  '${it['diaSolicitado']} ${it['horaSolicitada']} (fijo)'),
            if ((it['motivo'] ?? '').toString().isNotEmpty)
              _linea('Motivo', it['motivo'].toString()),
            if ((it['notaAdmin'] ?? '').toString().isNotEmpty)
              _linea('Nota', it['notaAdmin'].toString()),
            if (pendiente) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: cessumRed,
                          side: const BorderSide(color: cessumRed)),
                      onPressed: () => _resolver(it, 'Rechazado'),
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
                      onPressed: () => _resolver(it, 'Aprobado'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Aprobar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linea(String etq, String val) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12.5, color: Colors.black87),
          children: [
            TextSpan(
                text: '$etq: ',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black54)),
            TextSpan(text: val),
          ],
        ),
      ),
    );
  }
}
