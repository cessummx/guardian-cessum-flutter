// =====================================================================
//  CONCILIACIÓN BANCARIA DE PAGOS (4-oct-2026)
//  Cruza los pagos «por validar» de los alumnos con los depósitos de los
//  estados de cuenta ya cargados en Finanzas, y los separa en:
//    · Conciliados: el depósito está en el banco (monto, fecha y nombre).
//    · Probables: monto igual y fecha cercana, falta confirmar a ojo.
//    · Sin depósito: el estado de cuenta de esa fecha ya está cargado y
//      no aparece un abono con ese monto.
//    · Fuera de periodo: aún no se sube el estado de cuenta de esa fecha.
//    · Depósitos sin pago: entró dinero de un alumno y nadie lo registró.
//  Validar sigue siendo una decisión de una persona: cada «Validar» usa el
//  pago_validar de siempre (le manda al alumno su comprobante) y lleva el
//  candado de fila (matrícula y monto). Ruta: pagos_conciliar.
// =====================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

const Color _verde = Color(0xFF1E7B34);
const Color _ambar = Color(0xFFB7791F);
const Color _azul = Color(0xFF2F5D8A);

class ConciliacionPagosScreen extends StatefulWidget {
  const ConciliacionPagosScreen({super.key});
  @override
  State<ConciliacionPagosScreen> createState() => _ConciliacionPagosScreenState();
}

class _ConciliacionPagosScreenState extends State<ConciliacionPagosScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  int _dias = 120;
  final Set<int> _validados = {};
  final Set<int> _validando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final actor = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'pagos_conciliar', 'actor': actor, 'dias': '$_dias'});
      final r = await http.get(uri).timeout(const Duration(seconds: 150));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() { _cargando = false; _d = d; _validados.clear(); if (d['ok'] != true) _error = '${d['error'] ?? 'No se pudo conciliar.'}'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = 'No se pudo conciliar (conexión o tiempo). Intenta de nuevo.'; });
    }
  }

  List<Map<String, dynamic>> _l(String k) => ((_d[k] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  int _n(dynamic v) => int.tryParse('${v ?? 0}'.split('.').first) ?? 0;
  String _dinero(dynamic v) {
    final x = double.tryParse('${v ?? 0}') ?? 0;
    final p = x.toStringAsFixed(2).split('.');
    return '\$${p[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}.${p[1]}';
  }

  void _snack(String t) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t))); }

  Future<bool> _validarUno(Map<String, dynamic> p) async {
    final fila = _n(p['fila']);
    setState(() => _validando.add(fila));
    try {
      final actor = (await SessionStore.validEmail()) ?? '';
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'pago_validar', 'fila': fila, 'actor': actor, 'matricula': '${p['matricula']}', 'monto': p['monto']}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return false;
      if (d['ok'] == true) {
        setState(() { _validando.remove(fila); _validados.add(fila); });
        return true;
      }
      setState(() => _validando.remove(fila));
      _snack('${p['nombre']}: ${d['error'] ?? 'no se pudo validar.'}');
      return false;
    } catch (e) {
      if (mounted) setState(() => _validando.remove(fila));
      _snack('${p['nombre']}: error de conexión.');
      return false;
    }
  }

  Future<void> _confirmarYValidar(List<Map<String, dynamic>> lista, {required bool enBloque}) async {
    final pend = lista.where((p) => !_validados.contains(_n(p['fila']))).toList();
    if (pend.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(enBloque ? 'Validar ${pend.length} pago(s) conciliados' : 'Validar el pago de ${pend.first['nombre']}'),
        content: Text(
          '${enBloque ? 'Cada alumno' : 'El alumno'} recibe por correo su comprobante de pago validado, como cuando se valida desde Seguimiento.'
          '${enBloque ? '\n\nSon ${pend.length} correo(s), uno por alumno, por un total de ${_dinero(pend.fold<double>(0, (s, p) => s + (double.tryParse('${p['monto']}') ?? 0)))}.' : ''}',
          style: const TextStyle(height: 1.45)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: _verde), onPressed: () => Navigator.pop(ctx, true),
              child: Text(enBloque ? 'Validar ${pend.length}' : 'Validar')),
        ],
      ),
    );
    if (ok != true) return;
    var hechos = 0;
    for (final p in pend) {
      if (!mounted) return;
      if (await _validarUno(p)) hechos++;
    }
    _snack('$hechos de ${pend.length} pago(s) validados.');
  }

  @override
  Widget build(BuildContext context) {
    final r = Map<String, dynamic>.from((_d['resumen'] as Map?) ?? {});
    final tabs = <(String, int, Color)>[
      ('Conciliados', _n(r['conciliados']), _verde),
      ('Probables', _n(r['probables']), _ambar),
      ('Sin depósito', _n(r['sinDeposito']), cessumRed),
      ('Fuera de periodo', _n(r['fueraDePeriodo']), Colors.grey),
      ('Depósitos sin pago', _n(r['depositosSinPago']), _azul),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Conciliación bancaria'),
          actions: [
            PopupMenuButton<int>(
              tooltip: 'Periodo',
              icon: const Icon(Icons.date_range),
              onSelected: (v) { setState(() => _dias = v); _cargar(); },
              itemBuilder: (_) => [for (final v in [60, 120, 240, 365]) CheckedPopupMenuItem(value: v, checked: v == _dias, child: Text('Últimos $v días'))],
            ),
            IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
          ],
          bottom: _cargando || _error.isNotEmpty
              ? null
              : TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: cessumGold,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: [for (final t in tabs) Tab(text: '${t.$1} · ${t.$2}')],
                ),
        ),
        body: _cargando
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: cessumRed), SizedBox(height: 12),
                Text('Cruzando pagos con el banco…')]))
            : _error.isNotEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: cessumRed))))
                : Column(children: [
                    _resumen(r),
                    Expanded(child: TabBarView(children: [
                      _listaPagos(_l('conciliados'), tipo: 'conciliado'),
                      _listaPagos(_l('probables'), tipo: 'probable'),
                      _listaPagos(_l('sinDeposito'), tipo: 'sin'),
                      _listaPagos(_l('fueraDePeriodo'), tipo: 'fuera'),
                      _listaDepositos(_l('depositosSinPago')),
                    ])),
                  ]),
      ),
    );
  }

  Widget _resumen(Map<String, dynamic> r) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18))),
        child: Text(
          '${r['porValidar'] ?? 0} pago(s) por validar en los últimos $_dias días · '
          '${_dinero(r['montoConciliado'])} ya está en el banco · ${_dinero(r['montoSinDeposito'])} sin depósito encontrado · '
          '${_dinero(r['montoDepositosSinPago'])} en depósitos sin pago registrado.'
          '${_n(_d['periodosCargados']) == 0 ? '\nTodavía no hay estados de cuenta cargados en Finanzas: súbelos para poder conciliar.' : ''}',
          style: const TextStyle(fontSize: 12.8, height: 1.45)),
      );

  Widget _vacio(String t) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context), height: 1.5))));

  Widget _listaPagos(List<Map<String, dynamic>> l, {required String tipo}) {
    if (l.isEmpty) {
      return _vacio({
        'conciliado': 'Ningún pago se pudo confirmar todavía contra el banco.',
        'probable': 'No hay coincidencias dudosas.',
        'sin': 'Todos los pagos con estado de cuenta cargado tienen su depósito.',
        'fuera': 'Todos los pagos caen en periodos con estado de cuenta cargado.',
      }[tipo]!);
    }
    final explicacion = {
      'conciliado': 'El depósito está en el banco con el mismo monto, en fecha cercana y a nombre del alumno. Puedes validarlos con confianza.',
      'probable': 'Hay un depósito con el mismo monto y fecha cercana, pero el banco no muestra el nombre. Revisa el comprobante antes de validar.',
      'sin': 'El estado de cuenta de esa fecha ya está cargado y no aparece un depósito con ese monto. Revisa el comprobante: puede ser de otra cuenta, otro monto o no haberse hecho.',
      'fuera': 'Todavía no se sube el estado de cuenta que cubre estas fechas. En cuanto lo subas en Finanzas, entran a la conciliación.',
    }[tipo]!;
    final pendientes = l.where((p) => !_validados.contains(_n(p['fila']))).length;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 30), children: [
      Text(explicacion, style: TextStyle(fontSize: 12.3, color: cessumMuted(context), height: 1.45)),
      if (tipo == 'conciliado' && pendientes > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _verde),
            onPressed: _validando.isNotEmpty ? null : () => _confirmarYValidar(l, enBloque: true),
            icon: const Icon(Icons.done_all),
            label: Text('Validar los $pendientes conciliados'),
          ),
        ),
      const SizedBox(height: 10),
      for (final p in l) _tarjetaPago(p, tipo),
    ]);
  }

  Widget _tarjetaPago(Map<String, dynamic> p, String tipo) {
    final fila = _n(p['fila']);
    final hecho = _validados.contains(fila), enCurso = _validando.contains(fila);
    final dep = p['deposito'] is Map ? Map<String, dynamic>.from(p['deposito'] as Map) : null;
    final color = {'conciliado': _verde, 'probable': _ambar, 'sin': cessumRed, 'fuera': Colors.grey}[tipo]!;
    final comp = '${p['comprobante'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hecho ? _verde.withValues(alpha: 0.06) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${p['nombre']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
          Text(_dinero(p['monto']), style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
        ]),
        Text('Matrícula ${p['matricula']} · registró el pago el ${p['fecha']}${'${p['concepto'] ?? ''}'.isNotEmpty ? ' · ${p['concepto']}' : ''}',
            style: TextStyle(fontSize: 11.8, color: cessumMuted(context))),
        if (dep != null) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Banco: ${dep['fecha']} · ${_dinero(dep['abono'])}${'${dep['contraparte'] ?? ''}'.isNotEmpty ? ' · ${dep['contraparte']}' : ''}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if ('${dep['concepto'] ?? ''}'.isNotEmpty) Text('${dep['concepto']}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
              Text('Coincide: ${((p['motivos'] as List?) ?? []).join(' · ')}', style: TextStyle(fontSize: 11, color: color)),
            ]),
          ),
        ],
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (comp.startsWith('http'))
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => launchUrl(Uri.parse(comp), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.receipt_long, size: 16), label: const Text('Ver comprobante', style: TextStyle(fontSize: 12))),
          if (hecho)
            const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, color: _verde, size: 18), SizedBox(width: 4), Text('Validado', style: TextStyle(color: _verde, fontWeight: FontWeight.w700, fontSize: 12.5))])
          else if (tipo == 'conciliado' || tipo == 'probable')
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: _verde, side: const BorderSide(color: _verde), visualDensity: VisualDensity.compact),
              onPressed: enCurso ? null : () => _confirmarYValidar([p], enBloque: false),
              child: enCurso ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Validar', style: TextStyle(fontSize: 12)),
            ),
        ]),
      ]),
    );
  }

  Widget _listaDepositos(List<Map<String, dynamic>> l) {
    if (l.isEmpty) return _vacio('Todos los depósitos de alumnos en el periodo tienen un pago registrado.');
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 30), children: [
      Text('Entró dinero a la cuenta, clasificado como pago de alumno, y nadie registró el pago en el sistema. '
          'Si identificas de quién es, pídele que suba su comprobante o regístralo en «Registro de pagos».',
          style: TextStyle(fontSize: 12.3, color: cessumMuted(context), height: 1.45)),
      const SizedBox(height: 10),
      for (final m in l)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12), border: const Border(left: BorderSide(color: _azul, width: 5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${'${m['contraparte'] ?? ''}'.isNotEmpty ? m['contraparte'] : 'Sin nombre en el banco'}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
              Text(_dinero(m['abono']), style: const TextStyle(fontWeight: FontWeight.w800, color: _azul, fontSize: 15)),
            ]),
            Text('${m['fecha']} · ${m['categoria']}', style: TextStyle(fontSize: 11.8, color: cessumMuted(context))),
            if ('${m['concepto'] ?? ''}'.isNotEmpty) Text('${m['concepto']}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          ]),
        ),
    ]);
  }
}
