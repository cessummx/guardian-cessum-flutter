// auditoria_seguridad_screen.dart · CESSUM · (24-sep-2026)
//
// AUDITORÍA Y SEGURIDAD · fase 3 de los centros inteligentes.
// La bitácora deja de ser una lista para leer y se convierte en ALERTAS:
// acciones sensibles por cuentas sin rol, acciones críticas en horario
// inusual, volumen inusual en un día, intentos repetidos rechazados por los
// candados y accesos con error. Abajo, las acciones sensibles recientes y
// los rechazos, para revisar el detalle. Reglas del Guardián, sin IA: en
// seguridad conviene que cada alerta tenga una regla explicable.
// Base: GET auditoria_alertas (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'centros_nav.dart';
import 'cessum_ui.dart';
import 'constants.dart';

class AuditoriaSeguridadScreen extends StatefulWidget {
  const AuditoriaSeguridadScreen({super.key});

  @override
  State<AuditoriaSeguridadScreen> createState() => _AuditoriaSeguridadScreenState();
}

class _AuditoriaSeguridadScreenState extends State<AuditoriaSeguridadScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String _error = '';
  int _dias = 7;
  Map<String, dynamic>? _d;
  String _vista = 'alertas'; // alertas | sensibles | rechazos

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'auditoria_alertas', 'dias': '$_dias'}))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo revisar la bitácora.');
      if (!mounted) return;
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final m = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _cargando = false;
        _error = (m.contains('TimeoutException') || m.contains('ClientException') || m.contains('SocketException'))
            ? 'No se pudo cargar. Revise su conexión e intente de nuevo.'
            : m;
      });
    }
  }

  Color _nivel(String n) => n == 'alto' ? cessumRed : (n == 'medio' ? cessumGold : cessumMuted(context));

  List<Map<String, dynamic>> _lista(String k) => ((_d?[k] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    final resumen = Map<String, dynamic>.from((_d?['resumen'] as Map?) ?? {});
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Auditoría y seguridad', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Periodo',
            initialValue: _dias,
            onSelected: (v) {
              setState(() => _dias = v);
              _cargar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1, child: Text('Hoy')),
              PopupMenuItem(value: 7, child: Text('Últimos 7 días')),
              PopupMenuItem(value: 30, child: Text('Últimos 30 días')),
            ],
            icon: const Icon(Icons.date_range_outlined),
          ),
          IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.shield_outlined, size: 44, color: cessumFaint(context)),
                      const SizedBox(height: 10),
                      Text(_error, textAlign: TextAlign.center, style: TextStyle(color: cessumInk(context))),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _encabezado(resumen),
                      const SizedBox(height: 12),
                      _cifras(resumen),
                      const SizedBox(height: 14),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'alertas', label: Text('Alertas (${_lista('alertas').length})')),
                          ButtonSegment(value: 'sensibles', label: Text('Sensibles (${_lista('sensibles').length})')),
                          ButtonSegment(value: 'rechazos', label: Text('Rechazos (${_lista('rechazos').length})')),
                        ],
                        selected: {_vista},
                        onSelectionChanged: (s) => setState(() => _vista = s.first),
                      ),
                      const SizedBox(height: 12),
                      if (_vista == 'alertas') ..._alertas(),
                      if (_vista == 'sensibles') ..._sensibles(),
                      if (_vista == 'rechazos') ..._rechazos(),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, children: [
                        OutlinedButton.icon(onPressed: () => abrirPantallaCentro(context, 'bitacora'), icon: const Icon(Icons.history, size: 18), label: const Text('Bitácora completa')),
                        OutlinedButton.icon(onPressed: () => abrirPantallaCentro(context, 'accesos'), icon: const Icon(Icons.login_outlined, size: 18), label: const Text('Registro de accesos')),
                      ]),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _encabezado(Map<String, dynamic> r) {
    final n = (r['alertas'] as num?)?.toInt() ?? 0;
    final altas = _lista('alertas').where((a) => '${a['nivel']}' == 'alto').length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n == 0 ? 'Sin alertas en el periodo' : (altas > 0 ? '$altas alerta(s) de nivel alto' : '$n alerta(s), ninguna de nivel alto'),
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Últimos $_dias día(s) · ${_d?['generado'] ?? ''}. Cada alerta sale de una regla explicable, no de una suposición.',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
      ]),
    );
  }

  Widget _cifras(Map<String, dynamic> r) {
    Widget c(String n, String t, Color col) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).dividerColor)),
            child: Column(children: [
              Text(n, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: col)),
              Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
            ]),
          ),
        );
    return Row(children: [
      c('${r['acciones'] ?? 0}', 'acciones', cessumInk(context)),
      const SizedBox(width: 6),
      c('${r['sensibles'] ?? 0}', 'sensibles', cessumGold),
      const SizedBox(width: 6),
      c('${r['criticas'] ?? 0}', 'críticas', cessumRed),
      const SizedBox(width: 6),
      c('${r['rechazos'] ?? 0}', 'rechazos', ((r['rechazos'] as num?) ?? 0) > 0 ? cessumGold : _verde),
    ]);
  }

  List<Widget> _alertas() {
    final l = _lista('alertas');
    if (l.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            Icon(Icons.verified_user_outlined, size: 44, color: _verde),
            const SizedBox(height: 8),
            Text('Ninguna regla se activó en el periodo.', style: TextStyle(color: cessumMuted(context))),
          ]),
        ),
      ];
    }
    return [
      for (final a in l)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          color: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _nivel('${a['nivel']}').withValues(alpha: 0.5))),
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: _nivel('${a['nivel']}').withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon('${a['nivel']}' == 'alto' ? Icons.gpp_maybe_outlined : Icons.info_outline, color: _nivel('${a['nivel']}')),
            ),
            title: Text('${a['titulo'] ?? ''}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cessumInk(context))),
            subtitle: Text(
              [
                if ('${a['detalle'] ?? ''}'.isNotEmpty) '${a['detalle']}',
                if ('${a['actor'] ?? ''}'.isNotEmpty) 'Cuenta: ${a['actor']}',
                if ('${a['fecha'] ?? ''}'.isNotEmpty) '${a['fecha']}',
              ].join('\n'),
              style: TextStyle(fontSize: 12, height: 1.35, color: cessumMuted(context)),
            ),
            isThreeLine: true,
          ),
        ),
    ];
  }

  List<Widget> _sensibles() {
    final l = _lista('sensibles');
    if (l.isEmpty) return [Padding(padding: const EdgeInsets.all(20), child: Text('Sin acciones sensibles en el periodo.', style: TextStyle(color: cessumMuted(context))))];
    return [
      for (final s in l)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(s['critica'] == true ? Icons.priority_high : Icons.circle, size: s['critica'] == true ? 18 : 8, color: s['critica'] == true ? cessumRed : cessumGold),
          title: Text('${s['accion'] ?? ''}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cessumInk(context))),
          subtitle: Text('${s['fecha'] ?? ''} · ${s['usuario'] ?? ''}${'${s['detalle'] ?? ''}'.isNotEmpty ? ' · ${s['detalle']}' : ''}',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ),
    ];
  }

  List<Widget> _rechazos() {
    final l = _lista('rechazos');
    if (l.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Ningún candado rechazó peticiones en el periodo. El registro empezó con esta versión del Guardián.',
              style: TextStyle(color: cessumMuted(context))),
        ),
      ];
    }
    return [
      for (final r in l)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.block, size: 18, color: cessumGold),
          title: Text('${r['ruta'] ?? ''} · candado de ${r['candado'] ?? ''}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cessumInk(context))),
          subtitle: Text('${r['fecha'] ?? ''} · sesión ${r['sesion'] ?? ''}${'${r['dato'] ?? ''}'.isNotEmpty ? ' · pidió ${r['dato']}' : ''}',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ),
    ];
  }
}
