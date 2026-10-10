// expediente_docente_360_screen.dart · CESSUM · (24-sep-2026)
//
// EXPEDIENTE 360 DEL DOCENTE · fase 4 de los centros inteligentes.
// Todo lo de un profesor en una vista: carga y captura pendiente, evaluación
// (escalafón, observaciones, seguimiento), contrato, pagos recibidos,
// inasistencias, tareas y una línea de tiempo. Con IA: «Cinco líneas», un
// apoyo para la conversación de renovación, con todo a la vista.
// Base: directorio_docentes, GET expediente_docente_360 y
// expediente_docente_360_ia (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'centros_nav.dart';
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';
import 'selector_buscable.dart';

class ExpedienteDocente360Screen extends StatefulWidget {
  final String? correo;
  const ExpedienteDocente360Screen({super.key, this.correo});

  @override
  State<ExpedienteDocente360Screen> createState() => _ExpedienteDocente360ScreenState();
}

class _ExpedienteDocente360ScreenState extends State<ExpedienteDocente360Screen> {
  static const Color _verde = Color(0xFF1E8E3E);

  List<Map<String, dynamic>> _docentes = [];
  String? _correo;
  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _exp;
  bool _pidiendoIa = false;
  List<String> _lineas = [];
  String _aviso = '';

  @override
  void initState() {
    super.initState();
    _cargarDirectorio();
    if ((widget.correo ?? '').isNotEmpty) _abrir(widget.correo!);
  }

  Future<void> _cargarDirectorio() async {
    try {
      final r = await http.get(Uri.parse('$guardianUrl?accion=directorio_docentes')).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body);
      final lista = d is List ? d : ((d as Map<String, dynamic>).values.firstWhere((v) => v is List, orElse: () => []) as List);
      if (!mounted) return;
      setState(() => _docentes = lista.map((e) => Map<String, dynamic>.from(e as Map)).where((e) => '${e['correo'] ?? ''}'.contains('@')).toList());
    } catch (_) {}
  }

  Future<void> _abrir(String correo) async {
    setState(() {
      _correo = correo;
      _cargando = true;
      _error = '';
      _exp = null;
      _lineas = [];
    });
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'expediente_docente_360', 'correo': correo}))
          .timeout(const Duration(seconds: 180));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo armar el expediente.');
      if (!mounted) return;
      setState(() {
        _exp = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _cincoLineas() async {
    if ((_correo ?? '').isEmpty) return;
    setState(() => _pidiendoIa = true);
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'expediente_docente_360_ia', 'correo': _correo!}))
          .timeout(const Duration(seconds: 180));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar el resumen.');
      if (!mounted) return;
      setState(() {
        _lineas = ((d['lineas'] as List?) ?? []).map((e) => '$e').toList();
        _aviso = '${d['aviso'] ?? ''}';
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
    if (mounted) setState(() => _pidiendoIa = false);
  }

  Color _colorTipo(String t) {
    switch (t) {
      case 'pago':
        return _verde;
      case 'observacion':
        return const Color(0xFF1F5B9C);
      case 'inasistencia':
        return cessumRed;
    }
    return cessumGold;
  }

  IconData _icono(String t) {
    switch (t) {
      case 'pago':
        return Icons.payments_outlined;
      case 'observacion':
        return Icons.visibility_outlined;
      case 'inasistencia':
        return Icons.event_busy_outlined;
      case 'materia':
        return Icons.class_outlined;
    }
    return Icons.circle_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Expediente 360 · docente', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_exp != null)
            IconButton(
              tooltip: 'Cinco líneas (IA)',
              onPressed: _pidiendoIa ? null : _cincoLineas,
              icon: _pidiendoIa ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_awesome),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CessumSelectorBuscable<String>(
            label: 'Docente',
            valor: _correo,
            opciones: _docentes.map((d) => '${d['correo']}').toList(),
            etiqueta: (c) {
              final d = _docentes.firstWhere((x) => '${x['correo']}' == c, orElse: () => <String, dynamic>{});
              return '${d['docente'] ?? d['nombre'] ?? c}';
            },
            hint: _docentes.isEmpty ? 'Cargando directorio…' : 'Elija al docente',
            onChanged: (v) {
              if (v != null) _abrir(v);
            },
          ),
          const SizedBox(height: 12),
          if (_cargando) const CessumSkeletonList(),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(children: [
                Text(_error, textAlign: TextAlign.center, style: TextStyle(color: cessumInk(context))),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () => _abrir(_correo ?? ''), child: const Text('Reintentar')),
              ]),
            ),
          if (_exp != null) ..._cuerpo(),
          if (_exp == null && !_cargando && _error.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(children: [
                Icon(Icons.co_present_outlined, size: 54, color: cessumFaint(context)),
                const SizedBox(height: 10),
                Text('Elija a un docente para ver todo su expediente.', style: TextStyle(color: cessumMuted(context))),
              ]),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _cuerpo() {
    final e = _exp!;
    final doc = Map<String, dynamic>.from((e['docente'] as Map?) ?? {});
    final carga = Map<String, dynamic>.from((e['carga'] as Map?) ?? {});
    final ev = Map<String, dynamic>.from((e['evaluacion'] as Map?) ?? {});
    final pagos = Map<String, dynamic>.from((e['pagos'] as Map?) ?? {});
    final contrato = e['contrato'] is Map ? Map<String, dynamic>.from(e['contrato'] as Map) : null;
    final eventos = ((e['eventos'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final capPend = (carga['capturaPendiente'] as num?)?.toInt() ?? 0;
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${doc['nombre'] ?? ''}'.isEmpty ? '$_correo' : '${doc['nombre']}', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text([_correo ?? '', if ('${doc['telefono'] ?? ''}'.isNotEmpty) '${doc['telefono']}', if ('${doc['estatus'] ?? ''}'.isNotEmpty) '${doc['estatus']}'].join(' · '), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ]),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _dato('${carga['materias'] ?? 0}', 'materias', cessumInk(context), () => abrirPantallaCentro(context, 'agenda')),
        _dato('$capPend', 'captura pendiente', capPend > 0 ? cessumRed : _verde, null),
        _dato('${ev['observaciones'] ?? 0}', 'observaciones', const Color(0xFF1F5B9C), () => abrirPantallaCentro(context, 'seguimientoDocente')),
        _dato('${carga['inasistencias'] ?? 0}', 'inasistencias', ((carga['inasistencias'] as num?) ?? 0) > 0 ? cessumGold : _verde, null),
        _dato('${pagos['registros'] ?? 0}', 'pagos · \$${(pagos['suma'] as num?)?.round() ?? 0}', _verde, () => abrirPantallaCentro(context, 'pagosProfesores')),
        _dato('${carga['tareas'] ?? 0}', 'tareas', cessumMuted(context), null),
      ]),
      if (ev['escalafon'] != null || contrato != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).dividerColor)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (ev['escalafon'] != null) Text('Escalafón: ${ev['escalafon'] is Map ? ((ev['escalafon'] as Map)['lugar'] ?? (ev['escalafon'] as Map)['nivel'] ?? '') : ev['escalafon']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cessumInk(context))),
            if (contrato != null)
              InkWell(
                onTap: () => abrirPantallaCentro(context, 'contratos'),
                child: Text('Contrato: ${contrato['estatus'] ?? contrato['estado'] ?? contrato['mensaje'] ?? 'ver'}', style: TextStyle(fontSize: 13, color: cessumInk(context))),
              ),
          ]),
        ),
      ],
      if (_lineas.isNotEmpty) ...[const SizedBox(height: 12), _cajaIa()],
      if (_lineas.isEmpty) ...[
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _pidiendoIa ? null : _cincoLineas, icon: const Icon(Icons.auto_awesome, size: 16, color: cessumGold), label: Text(_pidiendoIa ? 'Pensando…' : 'Cinco líneas para la conversación'))),
      ],
      const SizedBox(height: 14),
      Text('LÍNEA DE TIEMPO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumMuted(context))),
      const SizedBox(height: 8),
      if (eventos.isEmpty) Text('Sin registros.', style: TextStyle(color: cessumMuted(context))),
      for (final x in eventos) _evento(x),
    ];
  }

  Widget _dato(String n, String t, Color c, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 108,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.4))),
        child: Column(children: [
          Text(n, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
          Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
        ]),
      ),
    );
  }

  Widget _cajaIa() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12), border: Border.all(color: cessumGold.withValues(alpha: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, size: 16, color: cessumGold),
          const SizedBox(width: 6),
          Text('CINCO LÍNEAS', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumInk(context))),
          const Spacer(),
          IconButton(tooltip: 'Copiar', iconSize: 18, onPressed: () => Helpers.copiarAlPortapapeles(context, _lineas.map((l) => '• $l').join('\n'), 'Resumen'), icon: const Icon(Icons.copy_outlined)),
        ]),
        for (final l in _lineas)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('• ', style: TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              Expanded(child: Text(l, style: TextStyle(fontSize: 13.5, height: 1.4, color: cessumInk(context)))),
            ]),
          ),
        if (_aviso.isNotEmpty) ...[const SizedBox(height: 8), Text(_aviso, style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cessumMuted(context)))],
      ]),
    );
  }

  Widget _evento(Map<String, dynamic> x) {
    final t = '${x['tipo'] ?? ''}';
    final c = _colorTipo(t);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 74, child: Padding(padding: const EdgeInsets.only(top: 10), child: Text('${x['fecha'] ?? ''}', style: TextStyle(fontSize: 11, color: cessumMuted(context))))),
        Column(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle), child: Icon(_icono(t), size: 15, color: c)),
          Container(width: 2, height: 22, color: Theme.of(context).dividerColor),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x['titulo'] ?? ''}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cessumInk(context))),
              if ('${x['detalle'] ?? ''}'.isNotEmpty) Text('${x['detalle']}', style: TextStyle(fontSize: 12, height: 1.35, color: cessumMuted(context))),
            ]),
          ),
        ),
      ]),
    );
  }
}
