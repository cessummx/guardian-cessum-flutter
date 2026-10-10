import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Centro de automatizaciones (admin): lista los procesos
/// automáticos, su estado, frecuencia y última corrida; permite
/// prenderlos/apagarlos, correr la "previa" o ejecutarlos al momento.
class AutomatizacionesScreen extends StatefulWidget {
  const AutomatizacionesScreen({super.key});

  @override
  State<AutomatizacionesScreen> createState() => _AutomatizacionesScreenState();
}

class _AutomatizacionesScreenState extends State<AutomatizacionesScreen> {
  String _correo = '';
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _items = [];
  final Set<String> _ocupado = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      // (24-sep) Correo REAL: en «Ver como profesor» validEmail() devuelve el del profesor.
      _correo = (await SessionStore.realEmail()) ?? '';
      final uri = Uri.parse(
          '$guardianUrl?accion=automatizaciones_listar&actor=${Uri.encodeComponent(_correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        setState(() { _error = (d['error'] ?? 'No se pudo cargar.').toString(); _cargando = false; });
        return;
      }
      final lista = (d['automatizaciones'] is List) ? d['automatizaciones'] as List : [];
      setState(() {
        _items = lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _cargando = false;
      });
    } catch (e) {
      setState(() { _error = 'Error de conexión.'; _cargando = false; });
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 120));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// (24-sep) Resumen legible de una respuesta del Guardián (vista previa).
  String _resumen(Map<String, dynamic> d) {
    final partes = <String>[];
    d.forEach((k, v) {
      if (k == 'ok' || v is Map) return;
      partes.add(v is List ? '$k: ${v.length}' : '$k: $v');
    });
    return partes.join('\n');
  }

  Future<void> _toggle(Map<String, dynamic> item, bool val) async {
    final id = item['id'].toString();
    // (24-sep) Encenderla la deja corriendo sola, y puede enviar correos: se
    // confirma diciendo qué hace y cada cuánto. Apagarla no envía nada.
    if (val) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Encender · ${item['nombre']}', style: const TextStyle(fontSize: 16)),
          content: Text(
              'Desde ahora correrá SOLA (${item['frecuencia']}) y puede ENVIAR CORREOS:\n\n'
              '${item['descripcion']}\n\n'
              'Si no lo ha hecho, cancele y use «Previa» para ver a quiénes les llegaría.',
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Encender'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _ocupado.add(id));
    try {
      final d = await _post({
        'accion': 'automatizacion_toggle',
        'actor': _correo,
        'id': id,
        'encender': val,
      });
      if (d['ok'] == true) {
        setState(() => item['instalado'] = val);
      } else {
        _aviso(d['error']?.toString() ?? 'No se pudo cambiar.');
      }
    } catch (e) {
      _aviso('Error de conexión.');
    } finally {
      setState(() => _ocupado.remove(id));
    }
  }

  Future<void> _correr(Map<String, dynamic> item, bool ejecutar) async {
    final id = item['id'].toString();
    final accion = (ejecutar ? item['ejecutar'] : item['previa']).toString();
    if (accion.isEmpty) return;
    if (ejecutar) {
      // (24-sep) Primero la vista previa, para confirmar con el alcance a la vista.
      String previa = '';
      final accPrevia = '${item['previa'] ?? ''}';
      if (accPrevia.isNotEmpty) {
        setState(() => _ocupado.add(id));
        try {
          final d = await _post({'accion': accPrevia, 'actor': _correo});
          previa = d['ok'] == true ? _resumen(d) : 'No se pudo obtener la vista previa: ${d['error'] ?? ''}';
        } catch (_) {
          previa = 'No se pudo obtener la vista previa.';
        }
        if (mounted) setState(() => _ocupado.remove(id));
        if (!mounted) return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(item['nombre'].toString()),
          content: SingleChildScrollView(
            child: Text(
                'Se ejecutará ahora y ENVIARÁ los avisos correspondientes.'
                '${previa.isNotEmpty ? '\n\nVista previa (lo que haría):\n$previa' : ''}'
                '\n\n¿Confirma?',
                style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ejecutar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _ocupado.add(id));
    try {
      final d = await _post({'accion': accion, 'actor': _correo});
      _mostrarResultado(item['nombre'].toString(), d, ejecutar);
    } catch (e) {
      _aviso('Error de conexión.');
    } finally {
      setState(() => _ocupado.remove(id));
    }
  }

  void _mostrarResultado(String titulo, Map<String, dynamic> d, bool ejecutar) {
    final partes = <String>[];
    d.forEach((k, v) {
      if (k == 'ok' || v is List || v is Map) return;
      partes.add('$k: $v');
    });
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${ejecutar ? 'Ejecutado' : 'Previa'} · $titulo'),
        content: Text(d['ok'] == true
            ? (partes.isEmpty ? 'Listo.' : partes.join('\n'))
            : (d['error']?.toString() ?? 'No se pudo.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text('Centro de automatizaciones'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(child: Text(_error, style: TextStyle(color: cessumMuted(context))))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final item in _items) _tarjeta(item),
                  ],
                ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final instalado = item['instalado'] == true;
    final ocupado = _ocupado.contains(id);
    final ultima = (item['ultimaCorrida'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (instalado ? const Color(0xFF1E8E3E) : cessumGold).withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item['nombre'].toString(),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cessumInk(context))),
              ),
              if (ocupado)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Switch(
                  value: instalado,
                  activeThumbColor: const Color(0xFF1E8E3E),
                  onChanged: (v) => _toggle(item, v),
                ),
            ],
          ),
          Text(item['descripcion'].toString(),
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: cessumGold),
              const SizedBox(width: 4),
              Text(item['frecuencia'].toString(),
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              const Spacer(),
              Text(
                instalado ? 'Activa' : 'Apagada',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: instalado ? const Color(0xFF1E8E3E) : cessumFaint(context),
                ),
              ),
            ],
          ),
          if (ultima.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Última actividad: $ultima',
                  style: TextStyle(fontSize: 11, color: cessumFaint(context))),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ocupado ? null : () => _correr(item, false),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Previa'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: ocupado ? null : () => _correr(item, true),
                  style: FilledButton.styleFrom(backgroundColor: cessumRed),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Ejecutar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
