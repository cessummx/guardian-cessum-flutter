// =====================================================================
//  cumplimiento_acuerdo_screen.dart · CESSUM · (27-sep-2026)
//  ACUERDO 17/11/17 — Artículos 62, 63 y 61-IV en una sola pantalla.
//
//  Guardián:
//    GET art63_seguimiento
//    GET art62_pendientes · POST art62_verificar · POST art62_aviso_sep
//    GET libro_titulos_grados
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'acceso_bloqueos_screen.dart';

class CumplimientoAcuerdoScreen extends StatefulWidget {
  const CumplimientoAcuerdoScreen({super.key});
  @override
  State<CumplimientoAcuerdoScreen> createState() => _CumplimientoAcuerdoScreenState();
}

class _CumplimientoAcuerdoScreenState extends State<CumplimientoAcuerdoScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  bool _cargando63 = true, _cargando62 = true, _cargandoLibro = true;
  List<Map<String, dynamic>> _art63 = [];
  List<Map<String, dynamic>> _art62 = [];
  List<Map<String, dynamic>> _libro = [];

  Future<String> _actor() async => await SessionStore.realEmail() ?? await SessionStore.validEmail() ?? '';

  @override
  void initState() {
    super.initState();
    _cargar63();
    _cargar62();
    _cargarLibro();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(String accion) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': accion, 'actor': await _actor()});
    final r = await http.get(uri).timeout(const Duration(seconds: 60));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode({...body, 'actor': await _actor()}))
        .timeout(const Duration(seconds: 30));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> _lista(dynamic v) => ((v as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _cargar63() async {
    setState(() => _cargando63 = true);
    try {
      final d = await _get('art63_seguimiento');
      if (d['ok'] == true && mounted) setState(() => _art63 = _lista(d['alumnos']));
    } catch (_) {}
    if (mounted) setState(() => _cargando63 = false);
  }

  Future<void> _cargar62() async {
    setState(() => _cargando62 = true);
    try {
      final d = await _get('art62_pendientes');
      if (d['ok'] == true && mounted) setState(() => _art62 = _lista(d['alumnos']));
    } catch (_) {}
    if (mounted) setState(() => _cargando62 = false);
  }

  Future<void> _cargarLibro() async {
    setState(() => _cargandoLibro = true);
    try {
      final d = await _get('libro_titulos_grados');
      if (d['ok'] == true && mounted) setState(() => _libro = _lista(d['registros']));
    } catch (_) {}
    if (mounted) setState(() => _cargandoLibro = false);
  }

  void _aviso(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: error ? cessumRed : Colors.green, content: Text(t)));
  }

  Future<void> _verificarArt62(Map<String, dynamic> a) async {
    String resultado = 'Auténtico';
    final notas = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Verificar antecedente de ${a['nombre']}', style: const TextStyle(fontSize: 15)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a['tipoDocumento']}', style: const TextStyle(fontSize: 12.5)),
            TextButton.icon(
              onPressed: () => Helpers.abrirUrlExterna('${a['url']}', context),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Ver documento'),
            ),
            const SizedBox(height: 6),
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Auténtico', style: TextStyle(fontSize: 13)),
              value: 'Auténtico',
              groupValue: resultado,
              onChanged: (v) => setLocal(() => resultado = v ?? resultado),
            ),
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Apócrifo', style: TextStyle(fontSize: 13)),
              value: 'Apócrifo',
              groupValue: resultado,
              onChanged: (v) => setLocal(() => resultado = v ?? resultado),
            ),
            const SizedBox(height: 6),
            TextField(controller: notas, decoration: const InputDecoration(labelText: 'Notas (opcional)', border: OutlineInputBorder(), isDense: true)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final d = await _post({'accion': 'art62_verificar', 'matricula': a['matricula'], 'resultado': resultado, 'notas': notas.text.trim()});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _cargar62();
      final pasos = ((d['pasosSiguientes'] as List?) ?? []).map((e) => '$e').toList();
      if (pasos.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Documento apócrifo · pasos a seguir', style: TextStyle(fontSize: 15, color: cessumRed)),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final p in pasos) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(p, style: const TextStyle(fontSize: 13))),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final r = await _post({'accion': 'art62_aviso_sep', 'matricula': a['matricula']});
                  if (r['ok'] == true) _aviso('Fecha de aviso a la SEP registrada.${'${r['aviso'] ?? ''}'.isNotEmpty ? ' ${r['aviso']}' : ''}');
                },
                child: const Text('Ya avisé a la SEP: registrar fecha'),
              ),
            ],
          ),
        );
      } else {
        _aviso('Registrado: $resultado.');
      }
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
        title: const Text('Cumplimiento · Acuerdo 17/11/17'),
        bottom: TabBar(controller: _tabs, indicatorColor: Colors.white, labelColor: Colors.white, unselectedLabelColor: Colors.white70, tabs: const [
          Tab(text: 'Art. 63'),
          Tab(text: 'Art. 62'),
          Tab(text: 'Libro de títulos'),
        ]),
      ),
      body: TabBarView(controller: _tabs, children: [_pestana63(), _pestana62(), _pestanaLibro()]),
    );
  }

  Widget _pestana63() {
    if (_cargando63) return const Center(child: CircularProgressIndicator(color: cessumRed));
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text('Alumnos de nuevo ingreso sin antecedente académico entregado. 6 meses para entregarlo; 24 meses improrrogables para reingresar.',
          style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 10),
      if (_art63.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('No hay casos pendientes.', textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context)))),
      for (final a in _art63)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text('${a['nombre']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            subtitle: Text('${a['matricula']} · ${a['programa']} ${a['generacion']} · ${a['accionSugerida']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            trailing: a['estado'] == 'venceArt63'
                ? TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccesoBloqueosScreen())),
                    child: const Text('Bloquear', style: TextStyle(color: cessumRed)),
                  )
                : Text('${a['mesesDesdeIngreso']} m', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          ),
        ),
    ]);
  }

  Widget _pestana62() {
    if (_cargando62) return const Center(child: CircularProgressIndicator(color: cessumRed));
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text('Verificación de autenticidad del documento con el que el alumno acreditó su nivel anterior, dentro de 6 meses del ingreso.',
          style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 10),
      if (_art62.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('No hay documentos pendientes de verificar.', textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context)))),
      for (final a in _art62)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text('${a['nombre']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            subtitle: Text('${a['matricula']} · ${a['tipoDocumento']} · ${a['accionSugerida']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            trailing: TextButton(onPressed: () => _verificarArt62(a), child: const Text('Verificar')),
          ),
        ),
    ]);
  }

  Widget _pestanaLibro() {
    if (_cargandoLibro) return const Center(child: CircularProgressIndicator(color: cessumRed));
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text('Art. 61-IV: registro consecutivo de títulos, diplomas y grados expedidos, con su acta correspondiente.',
          style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 10),
      if (_libro.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('Aún no hay registros.', textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context)))),
      for (final r in _libro)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: cessumGold.withValues(alpha: 0.2), child: Text('${r['numeroDeRegistro']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
            title: Text('${r['nombre']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            subtitle: Text('${r['matricula']} · ${r['programa']} · ${r['opcionTitulacion']} · ${r['fechaExamen']} · ${r['resultado']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            trailing: IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => Helpers.abrirUrlExterna('${r['actaPdf']}', context)),
          ),
        ),
    ]);
  }
}
