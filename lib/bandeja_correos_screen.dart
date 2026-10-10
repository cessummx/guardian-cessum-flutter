// =====================================================================
//  BANDEJA DE SOLICITUDES (4-oct-2026) · solo Rectoría, Vicerrectoría,
//  Administración y contacto@.
//  Los correos de contacto@, rectoria@ y vicerrectoria@ (estos dos por
//  reenvío a contacto@) que NO son spam ni avisos automáticos, ya
//  clasificados: Solicitud, Queja, Pago, Seguimiento, Información, con
//  resumen, qué piden, área y urgencia. Primero lo urgente y lo no
//  atendido. No responde ni borra nada: «Abrir en Gmail» para contestar
//  y «Atendido» para marcarlo (etiqueta en Gmail).
//  Rutas: bandeja_listar · bandeja_atender.
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

class BandejaCorreosScreen extends StatefulWidget {
  const BandejaCorreosScreen({super.key});
  @override
  State<BandejaCorreosScreen> createState() => _BandejaCorreosScreenState();
}

class _BandejaCorreosScreenState extends State<BandejaCorreosScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  int _dias = 7;
  String _buzon = '';
  String _categoria = 'pide';   // pide = Solicitud + Queja + Pago + Seguimiento
  bool _verAtendidos = false;
  String _q = '';
  final Set<String> _enCurso = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'bandeja_listar', 'actor': await _actor(), 'dias': '$_dias'});
      final r = await http.get(uri).timeout(const Duration(seconds: 260));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() { _cargando = false; _d = d; if (d['ok'] != true) _error = '${d['error'] ?? 'No se pudo leer la bandeja.'}'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = 'No se pudo leer la bandeja (conexión o tiempo). La primera vez clasifica todo y puede tardar; intenta de nuevo.'; });
    }
  }

  Future<void> _atender(Map<String, dynamic> it, bool deshacer) async {
    final h = '${it['hilo']}';
    setState(() => _enCurso.add(h));
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'bandeja_atender', 'actor': await _actor(), 'hilo': h, if (deshacer) 'deshacer': '1'});
      final r = await http.get(uri).timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() { _enCurso.remove(h); if (d['ok'] == true) it['atendido'] = !deshacer; });
      if (d['ok'] != true) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${d['error'] ?? 'No se pudo marcar.'}')));
    } catch (_) {
      if (mounted) setState(() => _enCurso.remove(h));
    }
  }

  List<Map<String, dynamic>> get _items {
    final todos = ((_d['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final q = _q.trim().toLowerCase();
    return todos.where((x) {
      final c = '${x['categoria']}';
      if (_categoria == 'pide' && !['Solicitud', 'Queja', 'Pago', 'Seguimiento', 'Sin clasificar'].contains(c)) return false;
      if (_categoria != 'pide' && _categoria != 'todo' && c != _categoria) return false;
      if (_buzon.isNotEmpty && '${x['buzon']}' != _buzon) return false;
      if (!_verAtendidos && x['atendido'] == true) return false;
      if (q.isNotEmpty && !'${x['de']} ${x['asunto']} ${x['resumen']} ${x['pide']}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  String _corto(String b) => b.split('@').first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Bandeja de solicitudes'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Periodo', icon: const Icon(Icons.date_range),
            onSelected: (v) { setState(() => _dias = v); _cargar(); },
            itemBuilder: (_) => [for (final v in [2, 7, 15, 30]) CheckedPopupMenuItem(value: v, checked: v == _dias, child: Text('Últimos $v días'))],
          ),
          IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: Padding(padding: EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: cessumRed), SizedBox(height: 12),
              Text('Leyendo los buzones y clasificando los correos nuevos…', textAlign: TextAlign.center)])))
          : _error.isNotEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: cessumRed))))
              : _contenido(),
    );
  }

  Widget _contenido() {
    final items = _items;
    final porBuzon = Map<String, dynamic>.from((_d['porBuzon'] as Map?) ?? {});
    final buzones = ((_d['buzones'] as List?) ?? []).map((e) => '$e').toList();
    final porCat = Map<String, dynamic>.from((_d['porCategoria'] as Map?) ?? {});
    final pendientesAlta = ((_d['items'] as List?) ?? []).where((e) => (e as Map)['urgencia'] == 'alta' && e['atendido'] != true && ['Solicitud', 'Queja', 'Pago'].contains(e['categoria'])).length;
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 30), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cessumRed, borderRadius: BorderRadius.circular(14), border: const Border(bottom: BorderSide(color: cessumGold, width: 4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${(porCat['Solicitud'] ?? 0)} solicitud(es) · ${(porCat['Queja'] ?? 0)} queja(s) · ${(porCat['Pago'] ?? 0)} de pagos',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Últimos $_dias días · $pendientesAlta urgente(s) sin atender · corte ${_d['generado'] ?? ''}',
                style: const TextStyle(color: Color(0xFFF7DCDC), fontSize: 12)),
            if ('${_d['iaError'] ?? ''}'.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('Algunos correos no se pudieron clasificar: ${_d['iaError']}', style: const TextStyle(color: Color(0xFFF6EBD3), fontSize: 11.5))),
          ]),
        ),
        // (5-oct-2026) Si un buzón no reenvía a contacto@, sus correos no pueden aparecer: se dice, en lugar de callarlo.
        if (((_d['buzonesSinReenvio'] as List?) ?? []).isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB7791F).withValues(alpha: 0.5)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFB7791F)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No están llegando correos de: ${((_d['buzonesSinReenvio'] as List?) ?? []).join(', ')}. '
                  'La bandeja solo puede leer contacto@cessum.mx; los demás buzones tienen que reenviarle su correo. '
                  'En esa cuenta de Gmail: Configuración → Reenvío y correo POP/IMAP → Agregar una dirección de reenvío → '
                  'contacto@cessum.mx (confirmar el código que llega a contacto@) → «Reenviar una copia del correo entrante» '
                  'y «conservar la copia en Recibidos».',
                  style: const TextStyle(fontSize: 12.5, height: 1.45),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 10),
        TextField(
          decoration: InputDecoration(hintText: 'Buscar remitente, asunto o lo que piden', prefixIcon: const Icon(Icons.search), isDense: true,
              filled: true, fillColor: Theme.of(context).cardColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, children: [
          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('Todos los buzones'), selected: _buzon.isEmpty, onSelected: (_) => setState(() => _buzon = ''))),
          for (final b in buzones)
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
              label: Text('${_corto(b)} · ${porBuzon[b] ?? 0}'), selected: _buzon == b, selectedColor: cessumGold.withValues(alpha: 0.2),
              onSelected: (s) => setState(() => _buzon = s ? b : ''))),
        ])),
        const SizedBox(height: 6),
        SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final c in [('pide', 'Lo que piden algo'), ('Solicitud', 'Solicitudes'), ('Queja', 'Quejas'), ('Pago', 'Pagos'), ('Seguimiento', 'Seguimiento'), ('Información', 'Informativos'), ('Automático', 'Automáticos'), ('todo', 'Todo')])
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
              label: Text(c.$2), selected: _categoria == c.$1, selectedColor: cessumRed.withValues(alpha: 0.15),
              onSelected: (_) => setState(() => _categoria = c.$1))),
        ])),
        SwitchListTile(
          dense: true, contentPadding: EdgeInsets.zero, value: _verAtendidos,
          title: const Text('Mostrar también los atendidos', style: TextStyle(fontSize: 13)),
          onChanged: (v) => setState(() => _verAtendidos = v),
        ),
        if (items.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text('Nada pendiente con estos filtros.', textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context)))),
        for (final it in items) _tarjeta(it),
        const SizedBox(height: 10),
        Text('${_d['nota'] ?? ''}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.4)),
      ]),
    );
  }

  Widget _tarjeta(Map<String, dynamic> it) {
    final urg = '${it['urgencia'] ?? ''}';
    final colorUrg = urg == 'alta' ? cessumRed : (urg == 'media' ? _ambar : _azul);
    final atendido = it['atendido'] == true, enCurso = _enCurso.contains('${it['hilo']}');
    final cat = '${it['categoria']}';
    return Opacity(
      opacity: atendido ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: atendido ? _verde : colorUrg, width: 5))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _etiqueta(cat, cat == 'Queja' ? cessumRed : (cat == 'Solicitud' ? _azul : (cat == 'Pago' ? _verde : Colors.grey))),
            if (urg.isNotEmpty && cat != 'Automático') _etiqueta('Urgencia $urg', colorUrg),
            _etiqueta(_corto('${it['buzon']}'), cessumGold),
            if ('${it['area'] ?? ''}'.isNotEmpty) _etiqueta('${it['area']}', Colors.blueGrey),
            if (it['respondido'] == true) _etiqueta('Ya respondido', _verde),
            if (it['noLeido'] == true) _etiqueta('No leído', cessumRed),
          ]),
          const SizedBox(height: 6),
          Text('${it['asunto']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          Text('${it['de']} · ${it['fecha']}${(it['mensajes'] ?? 1) > 1 ? ' · ${it['mensajes']} mensajes' : ''}${(it['adjuntos'] ?? 0) > 0 ? ' · ${it['adjuntos']} adjunto(s)' : ''}',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          if ('${it['resumen'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${it['resumen']}', style: const TextStyle(fontSize: 13, height: 1.4))),
          if ('${it['pide'] ?? ''}'.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Pide: ${it['pide']}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: colorUrg))),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => launchUrl(Uri.parse('${it['gmail']}'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 16), label: const Text('Abrir en Gmail', style: TextStyle(fontSize: 12))),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: atendido ? Colors.grey : _verde, visualDensity: VisualDensity.compact),
              onPressed: enCurso ? null : () => _atender(it, atendido),
              icon: Icon(atendido ? Icons.undo : Icons.check, size: 16),
              label: Text(atendido ? 'Reabrir' : 'Atendido', style: const TextStyle(fontSize: 12))),
          ]),
        ]),
      ),
    );
  }

  Widget _etiqueta(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
      );
}
