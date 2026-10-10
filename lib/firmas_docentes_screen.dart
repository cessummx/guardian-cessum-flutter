import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'csv_export.dart';

/// Panel de administrador: muestra qué docentes ya registraron su firma
/// digital y cuáles faltan, para darles seguimiento antes de generar actas.
class FirmasDocentesScreen extends StatefulWidget {
  const FirmasDocentesScreen({super.key});

  @override
  State<FirmasDocentesScreen> createState() => _FirmasDocentesScreenState();
}

class _FirmasDocentesScreenState extends State<FirmasDocentesScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _docentes = [];
  int _conFirma = 0, _sinFirma = 0;
  String _filtro = '';
  bool _soloSinFirma = false;

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
        'accion': 'firmas_docentes_resumen',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      if (!mounted) return;
      setState(() {
        _docentes = ((data['docentes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _conFirma = (data['conFirma'] ?? 0) as int;
        _sinFirma = (data['sinFirma'] ?? 0) as int;
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

  void _exportar() {
    final filas = _docentes
        .map((d) => <Object?>[
              d['docente'] ?? '',
              d['correo'] ?? '',
              d['tiene'] == true ? 'Sí' : 'No',
              d['conFondo'] == true ? 'Con fondo' : 'Transparente',
            ])
        .toList();
    descargarCsv(
      'firmas_docentes.csv',
      construirCsv(['Docente', 'Correo', 'Tiene firma', 'Tipo'], filas),
    );
  }

  Future<void> _recordar() async {
    // (24-sep) ANTES de enviar: a quiénes les llega (vista previa del Guardián,
    // no envía nada). Antes el aviso no decía a cuántos docentes.
    List<Map<String, dynamic>> dest;
    int sinCorreo = 0;
    try {
      final solicitante = await SessionStore.realEmail() ?? '';
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'recordatorio_firma', 'solicitante': solicitante}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo preparar la vista previa.');
      dest = ((d['docentes'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      sinCorreo = (d['sinCorreo'] as num?)?.toInt() ?? 0;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')), backgroundColor: cessumRed));
      return;
    }
    if (!mounted) return;
    if (dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sinCorreo > 0
              ? 'Faltan $sinCorreo firma(s), pero esos docentes no tienen correo registrado: no se envió nada.'
              : 'Todos los docentes ya registraron su firma: no hay a quién escribir.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recordar a ${dest.length} docente(s)'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cada uno recibirá UN correo pidiéndole registrar su firma digital:',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final x in dest)
                Text('• ${x['docente']} · ${x['correo']}', style: const TextStyle(fontSize: 12.5)),
              if (sinCorreo > 0) ...[
                const SizedBox(height: 8),
                Text('$sinCorreo docente(s) sin correo registrado no se incluyen.',
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
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Enviar ${dest.length} recordatorio(s)'),
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
                'accion': 'recordatorio_firma',
                'solicitante': solicitante,
                'confirmar': 'ENVIAR', // (24-sep) sin esto el Guardián solo muestra la vista previa
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Recordatorios enviados: ${data['enviados']}'
              '${(data['sinCorreo'] ?? 0) is int && (data['sinCorreo'] ?? 0) > 0 ? ' · ${data['sinCorreo']} sin correo' : ''}.'),
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

  List<Map<String, dynamic>> get _filtrados {
    final q = _filtro.trim().toLowerCase();
    return _docentes.where((d) {
      if (_soloSinFirma && d['tiene'] == true) return false;
      if (q.isEmpty) return true;
      final n = (d['docente'] ?? '').toString().toLowerCase();
      final c = (d['correo'] ?? '').toString().toLowerCase();
      return n.contains(q) || c.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Firmas de docentes'),
        actions: [
          IconButton(
              onPressed: _cargando || _docentes.isEmpty ? null : _exportar,
              tooltip: 'Exportar CSV',
              icon: const Icon(Icons.download)),
          IconButton(
              onPressed: _cargando ? null : _recordar,
              tooltip: 'Recordar a los que faltan',
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Row(
                        children: [
                          Expanded(
                              child: _contador('Con firma', _conFirma,
                                  const Color(0xFF1E8E3E))),
                          const SizedBox(width: 10),
                          Expanded(
                              child:
                                  _contador('Faltan', _sinFirma, cessumRed)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: TextField(
                        onChanged: (v) => setState(() => _filtro = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar docente',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      value: _soloSinFirma,
                      onChanged: (v) => setState(() => _soloSinFirma = v),
                      activeColor: cessumRed,
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      title: const Text('Mostrar solo los que faltan',
                          style: TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      child: lista.isEmpty
                          ? const Center(
                              child: Text('Sin coincidencias.',
                                  style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: lista.length,
                              itemBuilder: (c, i) => _fila(lista[i]),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _contador(String etq, int n, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text('$n',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: color)),
          Text(etq,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _fila(Map<String, dynamic> d) {
    final tiene = d['tiene'] == true;
    final nombre = (d['docente'] ?? '').toString();
    final correo = (d['correo'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(tiene ? Icons.check_circle : Icons.cancel,
            color: tiene ? const Color(0xFF1E8E3E) : cessumRed),
        title: Text(nombre.isEmpty ? '(sin nombre)' : nombre,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Text(correo, style: const TextStyle(fontSize: 11.5)),
        trailing: Text(
          tiene ? 'Con firma' : 'Falta',
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: tiene ? const Color(0xFF1E8E3E) : cessumRed),
        ),
      ),
    );
  }
}
