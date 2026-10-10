import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'csv_export.dart';

/// Panel de administrador: historial de actas devueltas a los docentes
/// con observaciones (hoja "Devoluciones de actas" del Guardián).
class DevolucionesActasScreen extends StatefulWidget {
  const DevolucionesActasScreen({super.key});

  @override
  State<DevolucionesActasScreen> createState() =>
      _DevolucionesActasScreenState();
}

class _DevolucionesActasScreenState extends State<DevolucionesActasScreen> {
  bool _cargando = true;
  bool _enviando = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _filtro = '';

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
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'devoluciones_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _items = (data['devoluciones'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _error = (data['error'] ?? 'No se pudo cargar').toString();
      }
    } catch (e) {
      _error = 'Error de conexión: $e';
    }
    if (mounted) setState(() => _cargando = false);
  }

  List<Map<String, dynamic>> get _filtrados {
    if (_filtro.trim().isEmpty) return _items;
    final q = _filtro.toLowerCase();
    return _items.where((e) {
      return ('${e['materia']} ${e['programa']} ${e['docente']} '
              '${e['generacion']} ${e['observaciones']}')
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  void _exportarCsv() {
    final filas = _filtrados
        .map<List<Object?>>((e) => [
              e['fecha'],
              e['programa'],
              e['generacion'],
              e['grupo'],
              e['materia'],
              e['docente'],
              e['observaciones'],
              e['por'],
            ])
        .toList();
    descargarCsv(
      'devoluciones_actas.csv',
      construirCsv(
        ['Fecha', 'Programa', 'Generación', 'Grupo', 'Materia', 'Docente',
          'Observaciones', 'Devuelta por'],
        filas,
      ),
    );
  }

  Future<void> _recordar() async {
    // (24-sep) ANTES de enviar: a quiénes les llega (vista previa del Guardián,
    // no envía nada). Antes el aviso no decía a cuántos docentes.
    setState(() => _enviando = true);
    List<Map<String, dynamic>> actas;
    int total = 0, sinCorreo = 0;
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'recordatorio_devueltas', 'actor': actor}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo preparar la vista previa.');
      actas = ((d['actas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      total = (d['total'] as num?)?.toInt() ?? 0;
      sinCorreo = (d['sinCorreo'] as num?)?.toInt() ?? 0;
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _enviando = false);
    if (total == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sinCorreo > 0
              ? 'Hay $sinCorreo acta(s) devuelta(s), pero sus docentes no tienen correo en la asignación: no se envió nada.'
              : 'No hay actas devueltas pendientes: no hay a quién escribir.')));
      return;
    }
    final conCorreo = actas.where((a) => a['sinCorreo'] != true).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enviar $total recordatorio(s)'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cada docente recibirá UN correo por su acta devuelta pendiente de corregir:',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final a in conCorreo)
                Text('• ${a['docente'] ?? a['correo']} · ${a['materia']} (Grupo ${a['grupo']})',
                    style: const TextStyle(fontSize: 12.5)),
              if (sinCorreo > 0) ...[
                const SizedBox(height: 8),
                Text('$sinCorreo acta(s) no se incluyen porque el docente no tiene correo en la asignación.',
                    style: const TextStyle(fontSize: 12, color: cessumRed)),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumGold),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Enviar $total recordatorio(s)'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _enviando = true);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(
                  {'accion': 'recordatorio_devueltas', 'actor': actor, 'confirmar': 'ENVIAR'}))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumGold,
          content: Text('Recordatorios enviados: ${data['enviados'] ?? 0}.'),
        ));
      } else {
        throw Exception(data['error'] ?? 'No se pudo enviar');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e')));
    }
    if (mounted) setState(() => _enviando = false);
  }

  Future<void> _recordarUna(Map<String, dynamic> e) async {
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'recordatorio_devuelta_una',
                'actor': actor,
                'programa': e['programa'],
                'generacion': e['generacion'],
                'grupo': e['grupo'],
                'materia': e['materia'],
                'docente': e['docente'],
                'observaciones': e['observaciones'],
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumGold,
          content:
              Text('Recordatorio enviado a ${data['correo'] ?? 'el docente'}.'),
        ));
      } else {
        throw Exception(data['error'] ?? 'No se pudo enviar');
      }
    } catch (e2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e2')));
    }
  }

  Widget _resumen() {
    if (_items.isEmpty) return const SizedBox.shrink();
    final docentes = <String>{
      for (final e in _items) (e['docente'] ?? '').toString()
    }..removeWhere((x) => x.isEmpty);
    final porPrograma = <String, int>{};
    for (final e in _items) {
      final p = (e['programa'] ?? '').toString();
      if (p.isEmpty) continue;
      porPrograma[p] = (porPrograma[p] ?? 0) + 1;
    }
    String topPrograma = '—';
    int topN = 0;
    porPrograma.forEach((k, v) {
      if (v > topN) {
        topN = v;
        topPrograma = k;
      }
    });
    Widget chip(IconData ic, String txt) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic, size: 15, color: cessumRed),
            const SizedBox(width: 6),
            Text(txt, style: const TextStyle(fontSize: 12.5)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip(Icons.assignment_return, '${_items.length} devolución(es)'),
          chip(Icons.person, '${docentes.length} docente(s)'),
          if (topN > 0) chip(Icons.school, 'Más: $topPrograma ($topN)'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Devoluciones de actas'),
        actions: [
          IconButton(
            onPressed: _enviando ? null : _recordar,
            icon: _enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.notifications_active_outlined),
            tooltip: 'Recordar a docentes',
          ),
          IconButton(
            onPressed: _items.isEmpty ? null : _exportarCsv,
            icon: const Icon(Icons.download),
            tooltip: 'Exportar CSV',
          ),
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : _vistaLista(),
    );
  }

  Widget _vistaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: cessumRed, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _vistaLista() {
    final lista = _filtrados;
    return Column(
      children: [
        _resumen(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar por materia, docente, programa...',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (v) => setState(() => _filtro = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${lista.length} devolución(es).',
              style: TextStyle(color: Colors.grey, fontSize: 12.5),
            ),
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? Center(
                  child: Text(
                    _items.isEmpty
                        ? 'Aún no hay actas devueltas.'
                        : 'Sin resultados para la búsqueda.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: lista.length,
                    itemBuilder: (_, i) => _tarjeta(lista[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _tarjeta(Map<String, dynamic> e) {
    final obs = (e['observaciones'] ?? '').toString();
    return Card(
      color: Theme.of(context).cardColor,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${e['materia']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Text('${e['fecha']}',
                    style: TextStyle(color: Colors.grey, fontSize: 11.5)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${e['programa']} · Gen. ${e['generacion']} · Grupo ${e['grupo']}',
              style: TextStyle(color: Colors.grey, fontSize: 12.5),
            ),
            const SizedBox(height: 2),
            Text('Docente: ${e['docente']}',
                style: const TextStyle(fontSize: 12.5)),
            if (obs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  border: const Border(
                      left: BorderSide(color: cessumGold, width: 3)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(obs, style: const TextStyle(fontSize: 13)),
              ),
            ],
            const SizedBox(height: 6),
            Text('Devuelta por: ${e['por']}',
                style: TextStyle(color: Colors.grey, fontSize: 11)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: cessumGold),
                onPressed: () => _recordarUna(e),
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Recordar al docente'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
