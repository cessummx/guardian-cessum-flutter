// =====================================================================
//  beca_convocatoria_admin_screen.dart · CESSUM · (27-sep-2026)
//  ARTS. 49-58, ACUERDO 17/11/17 — Vista de administrador.
//  Tres pestañas: Convocatorias, Solicitudes y el semáforo del 5% mínimo.
//
//  Guardián:
//    GET  beca_convocatorias_listar · POST beca_convocatoria_publicar
//    GET  beca_formal_listar[&estatus=]
//    POST beca_formal_dictaminar · beca_formal_inconformidad_resolver
//         beca_formal_reembolso · beca_formal_cancelar
//    GET  beca_formal_causales · GET beca_cumplimiento_5pct
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class BecaConvocatoriaAdminScreen extends StatefulWidget {
  const BecaConvocatoriaAdminScreen({super.key});
  @override
  State<BecaConvocatoriaAdminScreen> createState() => _BecaConvocatoriaAdminScreenState();
}

class _BecaConvocatoriaAdminScreenState extends State<BecaConvocatoriaAdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  bool _cargandoConv = true, _cargandoSol = true, _cargando5 = true;
  List<Map<String, dynamic>> _convocatorias = [];
  List<Map<String, dynamic>> _solicitudes = [];
  Map<String, dynamic>? _cumplimiento;
  String _filtroSol = '';

  Future<String> _actor() async => await SessionStore.realEmail() ?? await SessionStore.validEmail() ?? '';

  @override
  void initState() {
    super.initState();
    _cargarConvocatorias();
    _cargarSolicitudes();
    _cargarCumplimiento();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(String accion, [Map<String, String> extra = const {}]) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': accion, 'actor': await _actor(), ...extra});
    final r = await http.get(uri).timeout(const Duration(seconds: 30));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode({...body, 'actor': await _actor()}))
        .timeout(const Duration(seconds: 30));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> _lista(dynamic v) => ((v as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _cargarConvocatorias() async {
    setState(() => _cargandoConv = true);
    try {
      final d = await _get('beca_convocatorias_listar');
      if (d['ok'] == true && mounted) setState(() => _convocatorias = _lista(d['convocatorias']));
    } catch (_) {}
    if (mounted) setState(() => _cargandoConv = false);
  }

  Future<void> _cargarSolicitudes() async {
    setState(() => _cargandoSol = true);
    try {
      final d = await _get('beca_formal_listar', _filtroSol.isNotEmpty ? {'estatus': _filtroSol} : {});
      if (d['ok'] == true && mounted) setState(() => _solicitudes = _lista(d['solicitudes']));
    } catch (_) {}
    if (mounted) setState(() => _cargandoSol = false);
  }

  Future<void> _cargarCumplimiento() async {
    setState(() => _cargando5 = true);
    try {
      final d = await _get('beca_cumplimiento_5pct');
      if (d['ok'] == true && mounted) setState(() => _cumplimiento = d);
    } catch (_) {}
    if (mounted) setState(() => _cargando5 = false);
  }

  void _aviso(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: error ? cessumRed : Colors.green, content: Text(t)));
  }

  Future<void> _publicarConvocatoria() async {
    final ciclo = TextEditingController();
    final apertura = TextEditingController();
    final cierre = TextEditingController();
    final requisitos = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publicar convocatoria', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ciclo, decoration: const InputDecoration(labelText: 'Ciclo escolar (p. ej. 2026-2027)', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 8),
            TextField(controller: apertura, decoration: const InputDecoration(labelText: 'Apertura (AAAA-MM-DD)', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 8),
            TextField(controller: cierre, decoration: const InputDecoration(labelText: 'Cierre (AAAA-MM-DD)', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 8),
            TextField(controller: requisitos, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Requisitos (texto libre)', border: OutlineInputBorder(), isDense: true)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Publicar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final d = await _post({
        'accion': 'beca_convocatoria_publicar',
        'ciclo': ciclo.text.trim(),
        'apertura': apertura.text.trim(),
        'cierre': cierre.text.trim(),
        'requisitos': requisitos.text.trim(),
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo publicar.');
      _aviso('Convocatoria publicada.');
      _cargarConvocatorias();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _dictaminar(Map<String, dynamic> s) async {
    final porcentaje = TextEditingController();
    final montoOrdinario = TextEditingController();
    final decision = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Dictaminar solicitud de ${s['nombre']}', style: const TextStyle(fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Promedio declarado: ${s['promedioGeneral'] ?? '—'}', style: const TextStyle(fontSize: 12.5)),
              if ('${s['motivoSocioeconomico'] ?? ''}'.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('${s['motivoSocioeconomico']}', style: const TextStyle(fontSize: 12.5, height: 1.4))),
              const SizedBox(height: 10),
              TextField(controller: porcentaje, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '% a otorgar si se aprueba', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: montoOrdinario, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto ordinario de colegiatura', border: OutlineInputBorder(), isDense: true)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'rechazar'), child: const Text('Rechazar', style: TextStyle(color: cessumRed))),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, 'aprobar'), child: const Text('Aprobar')),
          ],
        ),
      ),
    );
    if (decision == null) return;
    try {
      final d = await _post({
        'accion': 'beca_formal_dictaminar',
        'folio': s['folio'],
        'decision': decision,
        if (decision == 'aprobar') 'porcentaje': porcentaje.text.trim(),
        if (decision == 'aprobar') 'montoOrdinario': montoOrdinario.text.trim(),
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo dictaminar.');
      _aviso('Solicitud ${d['decision']}.${'${d['nota'] ?? ''}'.isNotEmpty ? ' ${d['nota']}' : ''}');
      _cargarSolicitudes();
      _cargarCumplimiento();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _reembolso(Map<String, dynamic> s) async {
    final monto = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar reembolso (Art. 55)', style: TextStyle(fontSize: 15)),
        content: TextField(controller: monto, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto reembolsado', border: OutlineInputBorder(), isDense: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final d = await _post({'accion': 'beca_formal_reembolso', 'folio': s['folio'], 'monto': monto.text.trim()});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('Reembolso registrado.${'${d['aviso'] ?? ''}'.isNotEmpty ? ' ${d['aviso']}' : ''}');
      _cargarSolicitudes();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _cancelar(Map<String, dynamic> s) async {
    Map<String, dynamic> causales;
    try {
      causales = await _get('beca_formal_causales');
    } catch (_) {
      causales = {'ok': false};
    }
    final lista = _lista(causales['causales'] == null ? [] : (causales['causales'] as List).map((e) => {'c': e}).toList()).map((e) => '${e['c']}').toList();
    if (lista.isEmpty) {
      _aviso('No se pudieron cargar las causales.', error: true);
      return;
    }
    String? elegida = lista.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Cancelar beca (Art. 57)', style: TextStyle(fontSize: 15)),
          content: DropdownButtonFormField<String>(
            value: elegida,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Causal', border: OutlineInputBorder(), isDense: true),
            items: [for (final c in lista) DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12.5)))],
            onChanged: (v) => setLocal(() => elegida = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar beca')),
          ],
        ),
      ),
    );
    if (ok != true || elegida == null) return;
    try {
      final d = await _post({'accion': 'beca_formal_cancelar', 'folio': s['folio'], 'causal': elegida});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cancelar.');
      _aviso('Beca cancelada.');
      _cargarSolicitudes();
      _cargarCumplimiento();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _resolverInconformidad(Map<String, dynamic> s) async {
    final texto = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolver inconformidad (Art. 56)', style: TextStyle(fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s['inconformidadTexto']}', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
          TextField(controller: texto, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Resolución', border: OutlineInputBorder(), isDense: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final d = await _post({'accion': 'beca_formal_inconformidad_resolver', 'folio': s['folio'], 'resolucion': texto.text.trim()});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('Inconformidad resuelta.');
      _cargarSolicitudes();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Becas por convocatoria'),
        bottom: TabBar(controller: _tabs, indicatorColor: Colors.white, labelColor: Colors.white, unselectedLabelColor: Colors.white70, tabs: const [
          Tab(text: 'Convocatorias'),
          Tab(text: 'Solicitudes'),
          Tab(text: '5 % mínimo'),
        ]),
      ),
      body: TabBarView(controller: _tabs, children: [_pestanaConvocatorias(), _pestanaSolicitudes(), _pestanaCumplimiento()]),
    );
  }

  Widget _pestanaConvocatorias() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: _publicarConvocatoria, icon: const Icon(Icons.campaign_outlined), label: const Text('Publicar convocatoria')),
        ),
      ),
      Expanded(
        child: _cargandoConv
            ? const Center(child: CircularProgressIndicator(color: cessumRed))
            : ListView(padding: const EdgeInsets.symmetric(horizontal: 14), children: [
                for (final c in _convocatorias)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text('Ciclo ${c['ciclo']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('Del ${c['apertura']} al ${c['cierre']} · objetivo ${c['porcentajeObjetivo']} %', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                      trailing: c['activa'] == true ? const Icon(Icons.check_circle, color: Colors.green) : null,
                    ),
                  ),
              ]),
      ),
    ]);
  }

  Widget _pestanaSolicitudes() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in ['', 'Recibida', 'Aprobada', 'Rechazada', 'Cancelada'])
            ChoiceChip(label: Text(e.isEmpty ? 'Todas' : e), selected: _filtroSol == e, onSelected: (_) => setState(() { _filtroSol = e; _cargarSolicitudes(); })),
        ]),
      ),
      Expanded(
        child: _cargandoSol
            ? const Center(child: CircularProgressIndicator(color: cessumRed))
            : ListView(padding: const EdgeInsets.symmetric(horizontal: 14), children: [
                if (_solicitudes.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('No hay solicitudes con ese filtro.', textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context)))),
                for (final s in _solicitudes) _tarjetaSolicitud(s),
              ]),
      ),
    ]);
  }

  Widget _tarjetaSolicitud(Map<String, dynamic> s) {
    final estatus = '${s['estatus']}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${s['nombre']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
            Text(estatus, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: estatus == 'Aprobada' ? Colors.green : (estatus == 'Rechazada' || estatus == 'Cancelada' ? cessumRed : cessumGold))),
          ]),
          Text('${s['matricula']} · ${s['programa']} · folio ${s['folio']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          if ('${s['inconformidadTexto'] ?? ''}'.isNotEmpty && '${s['inconformidadResuelta'] ?? ''}'.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('Inconformidad pendiente: ${s['inconformidadTexto']}', style: const TextStyle(fontSize: 12, color: cessumRed))),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            if (estatus == 'Recibida') TextButton.icon(onPressed: () => _dictaminar(s), icon: const Icon(Icons.gavel, size: 16), label: const Text('Dictaminar')),
            if (estatus == 'Aprobada') TextButton.icon(onPressed: () => _reembolso(s), icon: const Icon(Icons.payments_outlined, size: 16), label: const Text('Reembolso')),
            if (estatus == 'Aprobada') TextButton.icon(onPressed: () => _cancelar(s), icon: const Icon(Icons.block, size: 16), label: const Text('Cancelar')),
            if ('${s['inconformidadTexto'] ?? ''}'.isNotEmpty && '${s['inconformidadResuelta'] ?? ''}'.isEmpty)
              TextButton.icon(onPressed: () => _resolverInconformidad(s), icon: const Icon(Icons.balance, size: 16), label: const Text('Resolver inconformidad')),
          ]),
        ]),
      ),
    );
  }

  Widget _pestanaCumplimiento() {
    if (_cargando5) return const Center(child: CircularProgressIndicator(color: cessumRed));
    final c = _cumplimiento;
    if (c == null) return Center(child: Text('No se pudo calcular.', style: TextStyle(color: cessumMuted(context))));
    final lic = c['licenciatura'] as Map<String, dynamic>? ?? {};
    final pos = c['posgrado'] as Map<String, dynamic>? ?? {};
    Widget fila(String nombre, Map<String, dynamic> d) {
      final pct = d['porcentaje'];
      final cumple = d['cumple5pct'] == true;
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nombre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('${d['conBeca'] ?? 0} de ${d['activos'] ?? 0} alumnos activos con beca', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
            const SizedBox(height: 8),
            Row(children: [
              Text(pct == null ? '—' : '$pct %', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cumple ? Colors.green : cessumRed)),
              const SizedBox(width: 10),
              Icon(cumple ? Icons.check_circle : Icons.warning_amber, color: cumple ? Colors.green : cessumRed, size: 20),
              const SizedBox(width: 4),
              Text(cumple ? 'Cumple el 5 % mínimo' : 'No llega al 5 % mínimo', style: TextStyle(fontSize: 12.5, color: cumple ? Colors.green : cessumRed)),
            ]),
          ]),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text('Art. 50, Acuerdo 17/11/17: mínimo 5 % de la matrícula con RVOE, por nivel educativo.',
          style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 12),
      fila('Licenciatura', lic),
      fila('Posgrado', pos),
    ]);
  }
}
