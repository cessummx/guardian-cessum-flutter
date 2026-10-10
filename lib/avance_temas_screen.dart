import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// El docente marca, contra los temas reales de la carta descriptiva, cuáles
/// ya cubrió. El % de avance es temas marcados sobre el total de la carta.
class AvanceTemasScreen extends StatefulWidget {
  final String programa;
  final String generacion;
  final String grupo;
  final String clave;
  final String materia;

  const AvanceTemasScreen({
    super.key,
    required this.programa,
    required this.generacion,
    required this.grupo,
    required this.clave,
    required this.materia,
  });

  @override
  State<AvanceTemasScreen> createState() => _AvanceTemasScreenState();
}

class _AvanceTemasScreenState extends State<AvanceTemasScreen> {
  String _correo = '';
  List<Map<String, dynamic>> _temas = [];
  int _marcados = 0;
  int _total = 0;
  int _porcentaje = 0;
  bool _cargando = true;
  String? _procesandoIndice;
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
      _correo = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse('$guardianUrl?accion=temas_avance_grupo'
          '&programa=${Uri.encodeComponent(widget.programa)}'
          '&generacion=${Uri.encodeComponent(widget.generacion)}'
          '&grupo=${Uri.encodeComponent(widget.grupo)}'
          '&clave=${Uri.encodeComponent(widget.clave)}'
          '&materia=${Uri.encodeComponent(widget.materia)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _temas = ((data['temas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _marcados = (data['marcados'] ?? 0) as int;
        _total = (data['total'] ?? 0) as int;
        _porcentaje = (data['porcentaje'] ?? 0) as int;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los temas de la carta.';
      });
    }
  }

  Future<void> _toggle(Map<String, dynamic> tema) async {
    final indice = tema['indice'].toString();
    setState(() => _procesandoIndice = indice);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'tema_avance_marcar',
                'correo': _correo,
                'programa': widget.programa,
                'generacion': widget.generacion,
                'grupo': widget.grupo,
                'clave': widget.clave,
                'materia': widget.materia,
                'indice': indice,
                'tema': tema['texto'],
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final marcado = data['marcado'] == true;
      if (!mounted) return;
      setState(() {
        tema['marcado'] = marcado;
        _marcados = _temas.where((t) => t['marcado'] == true).length;
        _porcentaje =
            _total > 0 ? ((_marcados / _total) * 100).round() : 0;
        _procesandoIndice = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _procesandoIndice = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Temas de la carta',
            style: TextStyle(fontWeight: FontWeight.w600)),
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
              : _total == 0
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No encontramos los temas de esta materia en la carta descriptiva. Revisa que el programa y la materia coincidan con cartas.json.',
                          style: TextStyle(color: cessumMuted(context)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        _cabecera(),
                        Expanded(
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(12, 0, 12, 16),
                            itemCount: _temas.length,
                            itemBuilder: (ctx, i) => _filaTema(_temas[i]),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _cabecera() {
    final color = _porcentaje >= 80
        ? const Color(0xFF1E8E3E)
        : (_porcentaje >= 50 ? cessumGold : cessumRed);
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.materia,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800)),
          Text('${widget.generacion} · Grupo ${widget.grupo}',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('$_marcados de $_total temas',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$_porcentaje%',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _total > 0 ? _marcados / _total : 0,
              minHeight: 10,
              backgroundColor: cessumMuted(context).withValues(alpha: 0.18),
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaTema(Map<String, dynamic> tema) {
    final marcado = tema['marcado'] == true;
    final indice = tema['indice'].toString();
    final procesando = _procesandoIndice == indice;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: CheckboxListTile(
        value: marcado,
        activeColor: const Color(0xFF1E8E3E),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        title: Text('${tema['texto']}',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: marcado ? cessumMuted(context) : cessumInk(context),
              decoration:
                  marcado ? TextDecoration.lineThrough : TextDecoration.none,
            )),
        secondary: procesando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : null,
        onChanged: procesando ? null : (_) => _toggle(tema),
      ),
    );
  }
}
