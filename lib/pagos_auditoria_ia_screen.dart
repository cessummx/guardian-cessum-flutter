// =====================================================================
//  pagos_auditoria_ia_screen.dart · CESSUM · (24-sep-2026)
//  AUDITORÍA DE COMPROBANTES CON IA (administración)
//
//  Los pagos consolidados entran como «Validado» sin que nadie revise el
//  archivo. Aquí la IA lee cada comprobante nuevo y marca los que no
//  corresponden: monto distinto al registrado, otra cuenta, fecha fuera de
//  lugar o el MISMO archivo usado en dos pagos. Una persona decide:
//  Correcto · Aclarar con el alumno · Pago no válido. Nada se invalida solo.
//
//  Guardián: GET pagos_ia_auditoria_listar · GET pagos_ia_auditar
//            GET pagos_ia_instalar · POST pagos_ia_decidir
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class PagosAuditoriaIaScreen extends StatefulWidget {
  const PagosAuditoriaIaScreen({super.key});

  @override
  State<PagosAuditoriaIaScreen> createState() => _PagosAuditoriaIaScreenState();
}

class _PagosAuditoriaIaScreenState extends State<PagosAuditoriaIaScreen> {
  bool _cargando = true;
  bool _auditando = false;
  String _error = '';
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _resumen = {};
  bool _soloPorDecidir = true;
  final Set<int> _ocupados = {};
  static const _verde = Color(0xFF1E7F52);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp, {int segundos = 60}) async {
    final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: qp)).timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void _aviso(String t, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : _verde,
      duration: const Duration(seconds: 6),
      content: Text(t),
    ));
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final d = await _get({'accion': 'pagos_ia_auditoria_listar'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cargar.');
      _items = ((d['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _resumen = Map<String, dynamic>.from((d['resumen'] as Map?) ?? {});
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _auditarAhora() async {
    setState(() => _auditando = true);
    try {
      final d = await _get({'accion': 'pagos_ia_auditar', 'dias': '30', 'limite': '10'}, segundos: 400);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo auditar.');
      final res = Map<String, dynamic>.from((d['resultado'] as Map?) ?? {});
      _aviso(d['auditados'] == 0
          ? 'No hay comprobantes nuevos por auditar en los últimos 30 días.'
          : 'Auditados: ${d['auditados']} · Corresponden: ${res['Corresponde'] ?? 0} · Por revisar: '
              '${(res['Revisar'] ?? 0) + (res['Duplicado'] ?? 0) + (res['No legible'] ?? 0)}'
              '${(d['pendientesPorAuditar'] ?? 0) > 0 ? ' · Quedan ${d['pendientesPorAuditar']} por auditar' : ''}');
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _auditando = false);
  }

  Future<void> _programar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Programar la auditoría diaria?'),
        content: const Text(
            'Cada día a las 6:00 la IA revisará hasta 25 comprobantes nuevos. No envía correos a nadie: solo '
            'escribe el resultado en la hoja y, si encuentra algo por revisar, avisa a Vicerrectoría en la app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Programar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final d = await _get({'accion': 'pagos_ia_instalar'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo programar.');
      _aviso('Auditoría diaria programada a las 6:00.');
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _decidir(Map<String, dynamic> x, String decision) async {
    final nota = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(decision, style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x['nombre']} · ${x['matricula']} · \$${x['monto']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              decision == 'Pago no válido'
                  ? 'Queda registrado como no válido en la auditoría. Si hay que quitarlo del estado de cuenta, hágalo desde Pagos.'
                  : decision == 'Aclarar con el alumno'
                      ? 'Queda marcado para aclararlo con el alumno.'
                      : 'Queda registrado como revisado y correcto.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nota,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, labelText: 'Nota (opcional)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: decision == 'Correcto' ? _verde : cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final texto = nota.text.trim();
    nota.dispose();
    if (ok != true || !mounted) return;
    final fila = (x['fila'] as num).toInt();
    setState(() => _ocupados.add(fila));
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'pagos_ia_decidir', 'fila': fila, 'decision': decision, 'nota': texto}))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('Decisión registrada.');
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _ocupados.remove(fila));
  }

  Color _color(String r) => switch (r) {
        'Corresponde' => _verde,
        'Duplicado' => cessumRed,
        'Revisar' => cessumGold,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final vis = _soloPorDecidir
        ? _items.where((x) => x['resultado'] != 'Corresponde' && '${x['decision']}'.isEmpty).toList()
        : _items;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Auditoría de comprobantes'),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error, textAlign: TextAlign.center),
                  TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                ]))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(padding: const EdgeInsets.all(14), children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cessumGold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        'Los pagos entran como validados sin que nadie revise el comprobante. La IA lee cada archivo y marca '
                        'los que no corresponden: monto distinto al registrado, otra cuenta, fecha fuera de lugar o el mismo '
                        'archivo usado en dos pagos. Usted decide; nada se invalida solo.',
                        style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumMuted(context)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: cessumRed),
                        onPressed: _auditando ? null : _auditarAhora,
                        icon: _auditando
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.fact_check, size: 18),
                        label: Text(_auditando ? 'Auditando… (puede tardar 1-2 min)' : 'Auditar ahora (10 comprobantes)'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                        onPressed: _programar,
                        icon: const Icon(Icons.schedule, size: 18),
                        label: const Text('Programar auditoría diaria'),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final k in const ['Duplicado', 'Revisar', 'No legible', 'Corresponde'])
                        if (_resumen[k] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: _color(k).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                            child: Text('$k: ${_resumen[k]}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _color(k))),
                          ),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: [
                      ChoiceChip(
                        label: Text('Por decidir (${_resumen['porDecidir'] ?? 0})'),
                        selected: _soloPorDecidir,
                        onSelected: (_) => setState(() => _soloPorDecidir = true),
                      ),
                      ChoiceChip(
                        label: Text('Todos (${_items.length})'),
                        selected: !_soloPorDecidir,
                        onSelected: (_) => setState(() => _soloPorDecidir = false),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    if (vis.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text(
                              _items.isEmpty
                                  ? 'Todavía no se ha auditado ningún comprobante. Toque «Auditar ahora».'
                                  : 'Nada pendiente de decidir.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cessumMuted(context))),
                        ),
                      )
                    else
                      ...vis.map(_tarjeta),
                  ]),
                ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> x) {
    final res = '${x['resultado']}';
    final c = _color(res);
    final fila = (x['fila'] as num).toInt();
    final ocupado = _ocupados.contains(fila);
    final decidido = '${x['decision']}'.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${x['nombre']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(res, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
          ),
        ]),
        Text('${x['matricula']} · ${x['fecha']} · \$${x['monto']} · ${x['concepto']}',
            style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        Text('${x['fuente']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        if ('${x['motivos']}'.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${x['motivos']}', style: TextStyle(fontSize: 12.5, color: c, fontWeight: FontWeight.w600)),
        ],
        if (decidido)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Decisión: ${x['decision']} · ${x['quien']}${'${x['nota']}'.isNotEmpty ? ' · «${x['nota']}»' : ''}',
                style: const TextStyle(fontSize: 12, color: _verde, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if ('${x['comprobante']}'.contains('http'))
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
              onPressed: () => launchUrl(Uri.parse('${x['comprobante']}'), webOnlyWindowName: '_blank'),
              icon: const Icon(Icons.receipt_long, size: 16),
              label: const Text('Ver comprobante'),
            ),
          if (!decidido) ...[
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _verde, visualDensity: VisualDensity.compact),
              onPressed: ocupado ? null : () => _decidir(x, 'Correcto'),
              child: const Text('Correcto'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: cessumGold, visualDensity: VisualDensity.compact),
              onPressed: ocupado ? null : () => _decidir(x, 'Aclarar con el alumno'),
              child: const Text('Aclarar con el alumno'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
              onPressed: ocupado ? null : () => _decidir(x, 'Pago no válido'),
              child: const Text('Pago no válido'),
            ),
          ],
        ]),
      ]),
    );
  }
}
