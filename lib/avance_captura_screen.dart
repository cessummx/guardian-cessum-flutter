import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'csv_export.dart';

/// Panel de administrador: avance de captura de calificaciones por docente.
/// Cruza las asignaciones (lo que se espera capturar) contra lo que ya está
/// en la hoja de Calificaciones, y muestra qué falta por capturar.
class AvanceCapturaScreen extends StatefulWidget {
  const AvanceCapturaScreen({super.key});

  @override
  State<AvanceCapturaScreen> createState() => _AvanceCapturaScreenState();
}

class _AvanceCapturaScreenState extends State<AvanceCapturaScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _docentes = [];
  int _totalAsig = 0, _totalCap = 0;
  bool _soloPendientes = false;

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
      final correo = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'avance_captura',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      if (!mounted) return;
      setState(() {
        _docentes = ((data['docentes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _totalAsig = (data['totalAsignaciones'] ?? 0) as int;
        _totalCap = (data['totalCapturadas'] ?? 0) as int;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar ($e)';
      });
    }
  }

  int _i(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

  void _exportar() {
    final filas = _docentes.map((d) {
      final pend = (d['pendientes'] as List?) ?? [];
      return <Object?>[
        d['docente'] ?? '',
        d['correo'] ?? '',
        _i(d['total']),
        _i(d['capturadas']),
        _i(d['total']) - _i(d['capturadas']),
        pend.join(' | '),
      ];
    }).toList();
    descargarCsv(
      'avance_captura.csv',
      construirCsv(
        ['Docente', 'Correo', 'Total', 'Capturadas', 'Pendientes', 'Lista pendientes'],
        filas,
      ),
    );
  }

  Future<void> _recordar() async {
    // (24-sep) ANTES de enviar: a quiénes les llega y cuántas materias tiene
    // cada uno (vista previa del Guardián; no envía nada). Antes el aviso no
    // decía a cuántos docentes les llegaría el correo.
    List<Map<String, dynamic>> dest;
    try {
      final correo = await SessionStore.realEmail() ?? '';
      final r = await http
          .get(Uri.parse(guardianUrl)
              .replace(queryParameters: {'accion': 'recordatorio_captura_previa', 'correo': correo}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo preparar la vista previa.');
      dest = ((d['docentes'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', '')), backgroundColor: cessumRed));
      return;
    }
    if (!mounted) return;
    if (dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ningún docente tiene captura pendiente: no hay a quién escribir.')));
      return;
    }
    final totMat = dest.fold<int>(0, (s, d) => s + (((d['materias'] as List?) ?? []).length));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enviar recordatorio a ${dest.length} docente(s)'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Cada uno recibirá UN correo con su lista personal de materias por capturar '
                  '($totMat en total). A nadie más le llega nada.',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final d in dest)
                Text('• ${d['nombre'] ?? d['correo']} · ${((d['materias'] as List?) ?? []).length} materia(s)',
                    style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Enviar ${dest.length} correo(s)'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final solicitante = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'recordatorio_captura',
                'solicitante': solicitante,
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Recordatorios enviados: ${data['enviados']}'
              '${_i(data['sinCorreo']) > 0 ? ' · ${data['sinCorreo']} sin correo' : ''}.'),
          backgroundColor: const Color(0xFF1E8E3E),
        ));
      } else {
        throw Exception(data['error'] ?? 'No autorizado');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: cessumRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _soloPendientes
        ? _docentes.where((d) => _i(d['capturadas']) < _i(d['total'])).toList()
        : _docentes;
    final pct = _totalAsig > 0 ? _totalCap / _totalAsig : 0.0;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Avance de captura'),
        actions: [
          IconButton(
              onPressed: _cargando || _docentes.isEmpty ? null : _exportar,
              tooltip: 'Exportar CSV',
              icon: const Icon(Icons.download)),
          IconButton(
              onPressed: _cargando ? null : _recordar,
              tooltip: 'Enviar recordatorio',
              icon: const Icon(Icons.notifications_active)),
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
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Avance general: $_totalCap de $_totalAsig '
                            '(${(pct * 100).toStringAsFixed(0)}%)',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 12,
                              backgroundColor: Theme.of(context).dividerColor,
                              color: pct >= 1
                                  ? const Color(0xFF1E8E3E)
                                  : cessumGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      value: _soloPendientes,
                      onChanged: (v) => setState(() => _soloPendientes = v),
                      activeColor: cessumRed,
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      title: const Text('Mostrar solo docentes con pendientes',
                          style: TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      child: lista.isEmpty
                          ? const Center(
                              child: Text('Sin docentes que mostrar.',
                                  style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: lista.length,
                              itemBuilder: (c, i) => _tarjetaDocente(lista[i]),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _tarjetaDocente(Map<String, dynamic> d) {
    final total = _i(d['total']);
    final cap = _i(d['capturadas']);
    final pend = (d['pendientes'] as List?) ?? [];
    final pct = total > 0 ? cap / total : 0.0;
    final completo = cap >= total;
    final color = completo ? const Color(0xFF1E8E3E) : cessumRed;
    final nombre = (d['docente'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(nombre.isEmpty ? '(sin nombre)' : nombre,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: Theme.of(context).dividerColor,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$cap de $total capturadas',
                    style: const TextStyle(fontSize: 11.5)),
              ],
            ),
          ),
          trailing: Text(
            completo ? 'Completo' : '${total - cap} pend.',
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
          children: completo
              ? const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Todo capturado.',
                        style: TextStyle(
                            fontSize: 12.5, color: Color(0xFF1E8E3E))),
                  )
                ]
              : pend
                  .map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.radio_button_unchecked,
                                size: 14, color: cessumRed),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(e.toString(),
                                  style: const TextStyle(fontSize: 12.5)),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
        ),
      ),
    );
  }
}
