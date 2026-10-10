import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// Vista de administración: solicitudes de CAMBIO DE PROGRAMA que envían los
/// alumnos. El admin aprueba (capturando la generación y grupo destino) o
/// rechaza. Al aprobar, el backend aplica el cambio empezando desde 0
/// (archiva el historial, limpia materias, pone el nuevo programa) conservando
/// la misma matrícula.
class CambioProgramaSolicitudesScreen extends StatefulWidget {
  const CambioProgramaSolicitudesScreen({super.key});

  @override
  State<CambioProgramaSolicitudesScreen> createState() =>
      _CambioProgramaSolicitudesScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

class _CambioProgramaSolicitudesScreenState
    extends State<CambioProgramaSolicitudesScreen> {
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
        'accion': 'cambio_programa_listar',
        if (_soloPendientes) 'pendientes': 'true',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        setState(() => _error = (data['error'] ?? 'Error').toString());
      } else {
        setState(() {
          _items = ((data['solicitudes'] as List?) ?? [])
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

  Future<void> _aprobar(Map<String, dynamic> it) async {
    final genCtrl = TextEditingController();
    final grupoCtrl = TextEditingController();
    final notaCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprobar cambio de programa',
            style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${it['nombre']} (${it['matricula']})',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'De: ${it['programaActual']}\nA: ${it['programaSolicitado']}',
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Al aprobar, el alumno inicia desde 0 en el nuevo programa. '
                  'Su historial se archiva y conserva la misma matrícula.',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: genCtrl,
                decoration: const InputDecoration(
                  labelText: 'Generación destino *  (ej. 26-2)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: grupoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Grupo destino  (ej. 1 - mixta)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notaCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota para el alumno (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _verdeOk, foregroundColor: Colors.white),
            onPressed: () {
              if (genCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('La generación destino es obligatoria.')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Aprobar y aplicar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _enviarResolucion(it, 'Aprobada',
        generacionDestino: genCtrl.text.trim(),
        grupoDestino: grupoCtrl.text.trim(),
        nota: notaCtrl.text.trim());
  }

  Future<void> _rechazar(Map<String, dynamic> it) async {
    final notaCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar solicitud', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${it['nombre']} (${it['matricula']})',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: notaCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo del rechazo (opcional)',
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
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _enviarResolucion(it, 'Rechazada', nota: notaCtrl.text.trim());
  }

  Future<void> _enviarResolucion(Map<String, dynamic> it, String estatus,
      {String generacionDestino = '',
      String grupoDestino = '',
      String nota = ''}) async {
    if (!mounted) return;
    final quien = await SessionStore.realEmail();
    try {
      final payload = <String, dynamic>{
        'accion': 'cambio_programa_resolver',
        'actor': quien ?? '',
        'fila': it['fila'],
        'estatus': estatus,
        'notaAdmin': nota,
        if (estatus == 'Aprobada') 'generacionDestino': generacionDestino,
        if (estatus == 'Aprobada') 'grupoDestino': grupoDestino,
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(estatus == 'Aprobada'
              ? 'Aprobado. El alumno inicia en el nuevo programa.'
              : 'Rechazado. Se avisó al alumno.'),
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

  Color _colorEstatus(String e) {
    switch (e) {
      case 'Aprobada':
        return _verdeOk;
      case 'Rechazada':
        return cessumRed;
      default:
        return cessumGold;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Cambios de programa'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text('Solo pendientes'),
                const Spacer(),
                Switch(
                  value: _soloPendientes,
                  activeColor: cessumRed,
                  onChanged: (v) {
                    setState(() => _soloPendientes = v);
                    _cargar();
                  },
                ),
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
                            child: Text('No hay solicitudes.'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _items.length,
                            itemBuilder: (ctx, i) => _tarjeta(_items[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> it) {
    final estatus = (it['estatus'] ?? '').toString();
    final pendiente = estatus == 'Pendiente';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${it['nombre']} (${it['matricula']})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _colorEstatus(estatus).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(estatus,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _colorEstatus(estatus))),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text((it['fecha'] ?? '').toString(),
                style: TextStyle(fontSize: 11, color: cessumFaint(context))),
            const SizedBox(height: 8),
            _linea('De', (it['programaActual'] ?? '').toString()),
            _linea('A', (it['programaSolicitado'] ?? '').toString()),
            if ((it['generacionActual'] ?? '').toString().isNotEmpty)
              _linea('Generación actual',
                  (it['generacionActual'] ?? '').toString()),
            if ((it['motivo'] ?? '').toString().isNotEmpty)
              _linea('Motivo', (it['motivo'] ?? '').toString()),
            if ((it['notaAdmin'] ?? '').toString().isNotEmpty)
              _linea('Nota', (it['notaAdmin'] ?? '').toString()),
            if (pendiente) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: cessumRed,
                          side: const BorderSide(color: cessumRed)),
                      onPressed: () => _rechazar(it),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _verdeOk,
                          foregroundColor: Colors.white),
                      onPressed: () => _aprobar(it),
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

  Widget _linea(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
          children: [
            TextSpan(
                text: '$k: ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: v),
          ],
        ),
      ),
    );
  }
}
