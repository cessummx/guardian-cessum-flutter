import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

// =====================================================================
// PANTALLA: "Hallazgos inteligentes" (RECTORÍA / VICERRECTORÍA)
// ---------------------------------------------------------------------
// Lista priorizada de conclusiones accionables que el motor del Guardián
// deriva de todos los datos: retención, egreso, riesgo por programa,
// validación estancada, índice de éxito, etc. No es un tablero de
// números: dice qué significa y qué hacer.
//
// CONTRATO (Code.gs -> insights):
//   { ok, generado, resumen:{alto,medio,info},
//     hallazgos:[{sev:'alto'|'medio'|'info',categoria,titulo,detalle,accion}] }
// =====================================================================


class HallazgosScreen extends StatefulWidget {
  const HallazgosScreen({super.key});

  @override
  State<HallazgosScreen> createState() => _HallazgosScreenState();
}

class _HallazgosScreenState extends State<HallazgosScreen> {
  bool _cargando = true;
  String? _error;
  String? _generado;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _hallazgos = [];

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
          .replace(queryParameters: {'accion': 'insights'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      if (!mounted) return;
      setState(() {
        _generado = data['generado']?.toString();
        _resumen = (data['resumen'] as Map<String, dynamic>?) ?? {};
        _hallazgos = ((data['hallazgos'] as List?) ?? [])
            .map((a) => Map<String, dynamic>.from(a as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los hallazgos.';
      });
    }
  }

  bool _resumiendo = false;

  /// (24-sep) Pide al Guardián el resumen ejecutivo con IA de los hallazgos.
  Future<void> _resumenIa() async {
    setState(() => _resumiendo = true);
    Map<String, dynamic> d;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'insights_ia_resumen'}))
          .timeout(const Duration(seconds: 120));
      d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar el resumen.');
    } catch (e) {
      if (mounted) {
        setState(() => _resumiendo = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _resumiendo = false);
    final prios = ((d['prioridades'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final parrafo = '${d['parrafo'] ?? ''}';
    final texto = StringBuffer()
      ..writeln('Prioridades institucionales')
      ..writeln('')
      ..writeln([for (var i = 0; i < prios.length; i++)
        '${i + 1}. ${prios[i]['titulo']}\n   Por qué: ${prios[i]['porque']}\n   Acción: ${prios[i]['accion']}'].join('\n\n'))
      ..writeln('')
      ..writeln(parrafo);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resumen ejecutivo', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < prios.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(radius: 12, backgroundColor: cessumRed,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${prios[i]['titulo'] ?? ''}',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cessumInk(ctx))),
                        const SizedBox(height: 2),
                        Text('${prios[i]['porque'] ?? ''}',
                            style: TextStyle(fontSize: 12.5, height: 1.35, color: cessumMuted(ctx))),
                        const SizedBox(height: 3),
                        Text('→ ${prios[i]['accion'] ?? ''}',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cessumRed)),
                      ]),
                    ),
                  ]),
                ),
              if (parrafo.isNotEmpty) ...[
                const Divider(height: 18),
                Text('Para Rectoría', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cessumInk(ctx))),
                const SizedBox(height: 4),
                SelectableText(parrafo, style: TextStyle(fontSize: 13, height: 1.45, color: cessumInk(ctx))),
              ],
              const SizedBox(height: 10),
              Text('${d['aviso'] ?? ''}',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Helpers.copiarAlPortapapeles(ctx, texto.toString(), 'Resumen'),
            child: const Text('Copiar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Color _color(String sev) {
    switch (sev) {
      case 'alto':
        return cessumRed;
      case 'medio':
        return Colors.orange.shade800;
      default:
        return Colors.teal.shade600;
    }
  }

  IconData _icono(String sev) {
    switch (sev) {
      case 'alto':
        return Icons.priority_high_rounded;
      case 'medio':
        return Icons.info_outline_rounded;
      default:
        return Icons.lightbulb_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context), // (24-sep) modo oscuro
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Hallazgos inteligentes'),
        actions: [
          // (24-sep) Resumen ejecutivo con IA: 3-5 prioridades y un párrafo para Rectoría.
          IconButton(
            icon: _resumiendo
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
            onPressed: (_cargando || _resumiendo || _hallazgos.isEmpty) ? null : _resumenIa,
            tooltip: 'Resumen ejecutivo con IA',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: cessumRed),
            SizedBox(height: 14),
            Text('Analizando los datos de la institución...',
                style: TextStyle(color: cessumMuted(context))),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52, color: cessumRed),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _cargar,
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
                child: const Text('Reintentar',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      color: cessumRed,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (_generado != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 2),
              child: Text('Generado el $_generado',
                  style: TextStyle(fontSize: 12, color: cessumFaint(context))),
            ),
          _resumenRow(),
          const SizedBox(height: 14),
          ..._hallazgos.map(_ficha),
          const SizedBox(height: 16),
          Text(
            'Los hallazgos se recalculan al abrir la pantalla, a partir de los '
            'mismos motores de riesgo, egreso y éxito. Son una guía de '
            'priorización, no un dictamen.',
            style:
                TextStyle(fontSize: 11.5, color: cessumFaint(context), height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _resumenRow() {
    return Row(
      children: [
        _mini('Prioridad alta', _resumen['alto'], cessumRed),
        _mini('Atención', _resumen['medio'], Colors.orange.shade800),
        _mini('Informativos', _resumen['info'], Colors.teal.shade600),
      ],
    );
  }

  Widget _mini(String etiqueta, dynamic valor, Color color) {
    final v = (valor is num) ? valor.toInt() : 0;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Text('$v',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(etiqueta,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          ],
        ),
      ),
    );
  }

  Widget _ficha(Map<String, dynamic> h) {
    final sev = (h['sev'] ?? 'info').toString();
    final color = _color(sev);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Franja de severidad
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_icono(sev), size: 18, color: color),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text((h['categoria'] ?? '').toString(),
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: color)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text((h['titulo'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            height: 1.25)),
                    const SizedBox(height: 4),
                    Text((h['detalle'] ?? '').toString(),
                        style: TextStyle(
                            fontSize: 12.5,
                            color: cessumMuted(context),
                            height: 1.35)),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.arrow_forward_rounded,
                            size: 15, color: color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text((h['accion'] ?? '').toString(),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: color)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
