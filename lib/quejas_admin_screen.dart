// =====================================================================
//  quejas_admin_screen.dart · CESSUM · (27-sep-2026)
//  ART. 48, ACUERDO 17/11/17 — Vista de administrador de las quejas.
//
//  Guardián: GET quejas_listar[&estatus=] · POST queja_resolver
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

const _kEstatusQueja = ['En revisión', 'Conciliada', 'Resuelta', 'Improcedente', 'Turnada a autoridad'];

class QuejasAdminScreen extends StatefulWidget {
  const QuejasAdminScreen({super.key});
  @override
  State<QuejasAdminScreen> createState() => _QuejasAdminScreenState();
}

class _QuejasAdminScreenState extends State<QuejasAdminScreen> {
  bool _cargando = true;
  List<Map<String, dynamic>> _quejas = [];
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<String> _actor() async => await SessionStore.realEmail() ?? await SessionStore.validEmail() ?? '';

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'quejas_listar',
        'actor': await _actor(),
        if (_filtro.isNotEmpty) 'estatus': _filtro,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() => _quejas = ((d['quejas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _resolver(Map<String, dynamic> q) async {
    String estatus = _kEstatusQueja.contains(q['estatus']) ? q['estatus'] : 'En revisión';
    final resolucion = TextEditingController(text: '${q['resolucion'] ?? ''}');
    bool posibleDelito = q['posibleDelito'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Resolver queja', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                value: estatus,
                decoration: const InputDecoration(labelText: 'Estatus', border: OutlineInputBorder(), isDense: true),
                items: [for (final e in _kEstatusQueja) DropdownMenuItem(value: e, child: Text(e))],
                onChanged: (v) => setLocal(() => estatus = v ?? estatus),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: resolucion,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Resolución', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: posibleDelito,
                onChanged: (v) => setLocal(() => posibleDelito = v == true),
                title: const Text('De los hechos se desprende un posible delito (Art. 46-XI)', style: TextStyle(fontSize: 12.5)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'queja_resolver',
                'actor': await _actor(),
                'folio': q['folio'],
                'estatus': estatus,
                'resolucion': resolucion.text.trim(),
                if (posibleDelito) 'posibleDelito': '1',
              }))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('Queja actualizada.${'${d['nota'] ?? ''}'.isNotEmpty ? ' ${d['nota']}' : ''}');
      _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _aviso(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: error ? cessumRed : Colors.green, content: Text(t)));
  }

  Color _colorEstatus(String e) {
    switch (e) {
      case 'Recibida':
        return cessumGold;
      case 'Resuelta':
      case 'Conciliada':
        return Colors.green;
      case 'Improcedente':
        return cessumMuted(context);
      case 'Turnada a autoridad':
        return cessumRed;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Quejas'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(padding: const EdgeInsets.all(14), children: [
              Wrap(spacing: 8, runSpacing: 6, children: [
                ChoiceChip(label: const Text('Todas'), selected: _filtro.isEmpty, onSelected: (_) => setState(() { _filtro = ''; _cargar(); })),
                for (final e in ['Recibida', ..._kEstatusQueja])
                  ChoiceChip(label: Text(e), selected: _filtro == e, onSelected: (_) => setState(() { _filtro = e; _cargar(); })),
              ]),
              const SizedBox(height: 12),
              if (_quejas.isEmpty)
                Padding(padding: const EdgeInsets.all(20), child: Text('No hay quejas con ese filtro.', textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context)))),
              for (final q in _quejas) _tarjeta(q),
            ]),
    );
  }

  Widget _tarjeta(Map<String, dynamic> q) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Row(children: [
          Expanded(child: Text('${q['tipo']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _colorEstatus('${q['estatus']}').withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text('${q['estatus']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _colorEstatus('${q['estatus']}'))),
          ),
        ]),
        subtitle: Text('${q['folio']} · ${q['fecha']}${'${q['matricula'] ?? ''}'.isNotEmpty ? ' · ${q['matricula']}' : ''}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${q['descripcion']}', style: const TextStyle(fontSize: 13, height: 1.4)),
              if ('${q['contra'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Señala a: ${q['contra']}', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic))),
              if (q['posibleDelito'] == true)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('⚠ Marcada con posible hecho delictivo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cessumRed))),
              if ('${q['resolucion'] ?? ''}'.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text('Resolución: ${q['resolucion']}', style: const TextStyle(fontSize: 12.5))),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _resolver(q), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Resolver / actualizar'))),
            ]),
          ),
        ],
      ),
    );
  }
}
