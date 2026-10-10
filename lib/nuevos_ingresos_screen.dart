import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin: nuevos ingresos detectados del formulario de inscripción que aún no
/// están en el padrón. Propone correo @cessum.mx y matrícula automáticos; con
/// un clic da de alta, escribe el correo en el formulario y envía el acceso al
/// correo personal del alumno.
class NuevosIngresosScreen extends StatefulWidget {
  const NuevosIngresosScreen({super.key});

  @override
  State<NuevosIngresosScreen> createState() => _NuevosIngresosScreenState();
}

class _NuevosIngresosScreenState extends State<NuevosIngresosScreen> {
  bool _cargando = true;
  String? _error;
  String? _altaKey; // item en proceso
  List<Map<String, dynamic>> _lista = [];
  final Map<String, TextEditingController> _correoCtl = {};
  final Map<String, TextEditingController> _matCtl = {};
  final Map<String, TextEditingController> _grupoCtl = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _correoCtl.values) {
      c.dispose();
    }
    for (final c in _matCtl.values) {
      c.dispose();
    }
    for (final c in _grupoCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _keyDe(Map<String, dynamic> r) =>
      '${r['formId'] ?? ''}_${r['fila'] ?? ''}';

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'nuevos_ingresos_listar',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _lista = ((data['nuevos'] as List<dynamic>? ?? []))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (final r in _lista) {
        final k = _keyDe(r);
        _correoCtl[k] = TextEditingController(
            text: (r['correoInstitucional'] ?? '').toString());
        _matCtl[k] = TextEditingController(
            text: (r['matriculaSugerida'] ?? '').toString());
        _grupoCtl[k] = TextEditingController(text: 'A');
      }
    } catch (e) {
      _error = '$e'.replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? cessumRed : Colors.green));
  }

  Future<void> _alta(Map<String, dynamic> r) async {
    final k = _keyDe(r);
    final correo = _correoCtl[k]?.text.trim() ?? '';
    final matricula = _matCtl[k]?.text.trim() ?? '';
    final grupo = _grupoCtl[k]?.text.trim() ?? 'A';
    if (correo.isEmpty || !correo.toLowerCase().endsWith('@cessum.mx')) {
      _aviso('El correo institucional debe ser @cessum.mx.', error: true);
      return;
    }
    if (matricula.isEmpty) {
      _aviso('Falta la matrícula.', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dar de alta'),
        content: Text(
            'Se dará de alta a ${r['nombre']}\n\n'
            'Correo: $correo\nMatrícula: $matricula\nGrupo: $grupo\n\n'
            'Se le enviará el acceso a su correo personal '
            '(${r['correoPersonal'] ?? '—'}).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dar de alta'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _altaKey = k);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'nuevo_ingreso_alta',
                'actor': actor,
                'correo': correo,
                'matricula': matricula,
                'grupo': grupo,
                'nombre': r['nombre'],
                'programa': r['programa'],
                'generacion': r['generacion'],
                'curp': r['curp'],
                'correoPersonal': r['correoPersonal'],
                'formId': r['formId'],
                'fila': r['fila'],
              }))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _aviso((data['mensaje'] ?? 'Alta realizada.').toString());
        setState(() {
          _lista.removeWhere((x) => _keyDe(x) == k);
        });
      } else {
        _aviso('${data['error'] ?? 'No se pudo dar de alta.'}', error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    } finally {
      if (mounted) setState(() => _altaKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Nuevos ingresos'),
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
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off, color: cessumRed, size: 44),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cessumRed,
                          foregroundColor: Colors.white),
                      onPressed: _cargar,
                      child: const Text('Reintentar'),
                    ),
                  ]),
                ))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Aspirantes del formulario que aún no están en el padrón. '
                        'Revisa el correo y la matrícula propuestos y da de alta. '
                        'Se enviará el acceso al correo personal del alumno.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Pendientes de alta (${_lista.length})',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: cessumRed)),
                    const SizedBox(height: 8),
                    if (_lista.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No hay nuevos ingresos por dar de alta.',
                            style: TextStyle(color: cessumMuted(context))),
                      )
                    else
                      ..._lista.map(_item),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _item(Map<String, dynamic> r) {
    final k = _keyDe(r);
    final enProceso = _altaKey == k;
    final comprobante = (r['comprobante'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((r['nombre'] ?? '').toString(),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(
              '${r['programa'] ?? ''} · ${r['generacion'] ?? ''}'
              '${(r['modalidad'] ?? '').toString().isNotEmpty ? ' · ${r['modalidad']}' : ''}',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
          Text('Correo personal: ${r['correoPersonal'] ?? '—'}',
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if ((r['curp'] ?? '').toString().isNotEmpty)
            Text('CURP: ${r['curp']}',
                style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          Text('Fecha: ${r['fecha'] ?? ''}',
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if (comprobante.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: cessumGold,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact),
                onPressed: () => Helpers.abrirUrlExterna(comprobante, context),
                icon: const Icon(Icons.receipt_long, size: 16),
                label: const Text('Ver comprobante de pago'),
              ),
            ),
          const Divider(height: 18),
          TextField(
            controller: _correoCtl[k],
            decoration: const InputDecoration(
              labelText: 'Correo institucional @cessum.mx',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _matCtl[k],
                  decoration: const InputDecoration(
                    labelText: 'Matrícula',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _grupoCtl[k],
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Grupo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E8E3E),
                  foregroundColor: Colors.white),
              onPressed: enProceso ? null : () => _alta(r),
              icon: enProceso
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add_alt_1, size: 18),
              label: Text(enProceso
                  ? 'Dando de alta…'
                  : 'Dar de alta + enviar acceso'),
            ),
          ),
        ],
      ),
    );
  }
}
