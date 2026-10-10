// expediente_360_screen.dart · CESSUM · (24-sep-2026)
//
// EXPEDIENTE 360 DEL ALUMNO (fase 1 de los centros inteligentes).
// Una sola línea de tiempo con calificaciones, pagos, trámites, solicitudes,
// mesa de ayuda, riesgo y asistencia. Arriba, «La situación en cinco líneas»
// con IA. Sirve para atender a un alumno sin abrir seis pantallas.
// Base: buscar_alumno (q), GET expediente_360 y expediente_360_ia (solo administración).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'centros_nav.dart';
import 'cessum_ui.dart';
import 'constants.dart';
import 'expediente_alumno_screen.dart';
import 'helpers.dart';

class Expediente360Screen extends StatefulWidget {
  /// Si se da, abre directamente el expediente de esa matrícula.
  final String? matricula;
  const Expediente360Screen({super.key, this.matricula});

  @override
  State<Expediente360Screen> createState() => _Expediente360ScreenState();
}

class _Expediente360ScreenState extends State<Expediente360Screen> {
  static const Color _verde = Color(0xFF1E8E3E);

  final _busca = TextEditingController();
  Timer? _debounce;
  bool _buscando = false;
  List<Map<String, dynamic>> _coincidencias = [];

  String _matricula = '';
  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _exp;
  String _filtro = '';

  bool _pidiendoIa = false;
  List<String> _lineasIa = [];
  String _avisoIa = '';

  @override
  void initState() {
    super.initState();
    final m = (widget.matricula ?? '').trim();
    if (m.isNotEmpty) _abrir(m);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busca.dispose();
    super.dispose();
  }

  void _alEscribir(String v) {
    _debounce?.cancel();
    final t = v.trim();
    if (t.isEmpty) {
      setState(() => _coincidencias = []);
      return;
    }
    if (RegExp(r'^\d{6,}$').hasMatch(t)) {
      setState(() => _coincidencias = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _buscar(t));
  }

  Future<void> _buscar(String q) async {
    setState(() => _buscando = true);
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'buscar_alumno', 'q': q}))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _coincidencias = ((d['alumnos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .take(12)
          .toList());
    } catch (_) {
      if (mounted) setState(() => _coincidencias = []);
    }
    if (mounted) setState(() => _buscando = false);
  }

  Future<void> _abrir(String matricula) async {
    setState(() {
      _matricula = matricula;
      _cargando = true;
      _error = '';
      _exp = null;
      _lineasIa = [];
      _coincidencias = [];
      _filtro = '';
    });
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'expediente_360', 'matricula': matricula}))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo armar el expediente.');
      if (!mounted) return;
      setState(() {
        _exp = d;
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

  Future<void> _cincoLineas() async {
    if (_matricula.isEmpty) return;
    setState(() => _pidiendoIa = true);
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'expediente_360_ia', 'matricula': _matricula}))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar el resumen.');
      if (!mounted) return;
      setState(() {
        _lineasIa = ((d['lineas'] as List?) ?? []).map((e) => '$e').toList();
        _avisoIa = '${d['aviso'] ?? ''}';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _pidiendoIa = false);
  }

  Color _colorTipo(String t) {
    switch (t) {
      case 'pago':
        return _verde;
      case 'calificacion':
        return const Color(0xFF1F5B9C);
      case 'baja':
      case 'justificacion':
        return cessumRed;
      case 'mesa':
        return const Color(0xFF7B1FA2);
    }
    return cessumGold;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Expediente 360', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_exp != null)
            IconButton(
              tooltip: 'La situación en cinco líneas (IA)',
              onPressed: _pidiendoIa ? null : _cincoLineas,
              icon: _pidiendoIa
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
            ),
          if (_exp != null)
            IconButton(
              tooltip: 'Expediente clásico',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpedienteAlumnoScreen())),
              icon: const Icon(Icons.folder_open_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buscador(),
          if (_coincidencias.isNotEmpty) _listaCoincidencias(),
          const SizedBox(height: 12),
          if (_cargando) const CessumSkeletonList(),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(children: [
                Text(_error, textAlign: TextAlign.center, style: TextStyle(color: cessumInk(context))),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () => _abrir(_matricula), child: const Text('Reintentar')),
              ]),
            ),
          if (_exp != null) ..._cuerpo(),
          if (_exp == null && !_cargando && _error.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(children: [
                Icon(Icons.person_search_outlined, size: 54, color: cessumFaint(context)),
                const SizedBox(height: 10),
                Text('Busque a un alumno por nombre o matrícula.', style: TextStyle(color: cessumMuted(context))),
              ]),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buscador() {
    return TextField(
      controller: _busca,
      onChanged: _alEscribir,
      onSubmitted: (v) {
        final t = v.trim();
        if (RegExp(r'^\d{6,}$').hasMatch(t)) _abrir(t);
      },
      decoration: InputDecoration(
        hintText: 'Nombre o matrícula del alumno',
        prefixIcon: _buscando
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            : const Icon(Icons.search),
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).cardColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: _busca.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() {
                  _busca.clear();
                  _coincidencias = [];
                })),
        helperText: 'Con matrícula, presione Intro para abrir directo.',
      ),
    );
  }

  Widget _listaCoincidencias() {
    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
      child: Column(children: [
        for (final a in _coincidencias)
          ListTile(
            dense: true,
            leading: const Icon(Icons.person_outline, color: cessumRed),
            title: Text('${a['nombre'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w700, color: cessumInk(context))),
            subtitle: Text('${a['matricula'] ?? ''}${'${a['programa'] ?? ''}'.isNotEmpty ? ' · ${a['programa']}' : ''}',
                style: TextStyle(color: cessumMuted(context))),
            onTap: () {
              _busca.text = '${a['nombre'] ?? ''}';
              _abrir('${a['matricula'] ?? ''}');
            },
          ),
      ]),
    );
  }

  List<Widget> _cuerpo() {
    final e = _exp!;
    final al = Map<String, dynamic>.from((e['alumno'] as Map?) ?? {});
    final riesgo = e['riesgo'] is Map ? Map<String, dynamic>.from(e['riesgo'] as Map) : null;
    final asis = e['asistencia'] is Map ? Map<String, dynamic>.from(e['asistencia'] as Map) : null;
    final conteo = Map<String, dynamic>.from((e['conteo'] as Map?) ?? {});
    final eventos = ((e['eventos'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final vis = _filtro.isEmpty ? eventos : eventos.where((x) => '${x['tipo']}' == _filtro).toList();
    return [
      _ficha(al, riesgo, asis),
      if (_lineasIa.isNotEmpty) ...[const SizedBox(height: 12), _cajaIa()],
      if (_lineasIa.isEmpty) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _pidiendoIa ? null : _cincoLineas,
            icon: const Icon(Icons.auto_awesome, size: 16, color: cessumGold),
            label: Text(_pidiendoIa ? 'Pensando…' : 'La situación en cinco líneas'),
          ),
        ),
      ],
      const SizedBox(height: 14),
      Text('LÍNEA DE TIEMPO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumMuted(context))),
      const SizedBox(height: 8),
      _filtrosTipo(conteo),
      const SizedBox(height: 10),
      if (vis.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(child: Text('Sin registros en esta categoría.', style: TextStyle(color: cessumMuted(context)))),
        ),
      for (final ev in vis) _evento(ev),
    ];
  }

  Widget _ficha(Map<String, dynamic> al, Map<String, dynamic>? riesgo, Map<String, dynamic>? asis) {
    final nivel = '${riesgo?['nivel'] ?? ''}';
    final colorRiesgo = RegExp(r'alto|crit', caseSensitive: false).hasMatch(nivel)
        ? cessumRed
        : (RegExp(r'medio|moder', caseSensitive: false).hasMatch(nivel) ? cessumGold : _verde);
    final sesiones = (asis?['sesiones'] as num?)?.toInt() ?? 0;
    final asistidas = (asis?['asistidas'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${al['nombre'] ?? ''}'.isEmpty ? 'Alumno $_matricula' : '${al['nombre']}',
            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          [
            _matricula,
            if ('${al['programa'] ?? ''}'.isNotEmpty) '${al['programa']}',
            if ('${al['generacion'] ?? ''}'.isNotEmpty) 'Gen. ${al['generacion']}',
            if ('${al['modalidad'] ?? ''}'.isNotEmpty) '${al['modalidad']}',
            if ('${al['estatus'] ?? ''}'.isNotEmpty) '${al['estatus']}',
          ].join(' · '),
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (nivel.isNotEmpty) _etiqueta('Riesgo: $nivel', colorRiesgo),
          if (sesiones > 0) _etiqueta('Asistencia $asistidas/$sesiones', asistidas / sesiones >= 0.8 ? _verde : cessumGold),
          if ('${al['correo'] ?? ''}'.isNotEmpty) _etiqueta('${al['correo']}', Colors.white),
        ]),
      ]),
    );
  }

  Widget _etiqueta(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _cajaIa() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, size: 16, color: cessumGold),
          const SizedBox(width: 6),
          Text('LA SITUACIÓN EN CINCO LÍNEAS',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumInk(context))),
          const Spacer(),
          IconButton(
            tooltip: 'Copiar',
            iconSize: 18,
            onPressed: () => Helpers.copiarAlPortapapeles(context, _lineasIa.map((l) => '• $l').join('\n'), 'Situación'),
            icon: const Icon(Icons.copy_outlined),
          ),
        ]),
        for (final l in _lineasIa)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('• ', style: TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              Expanded(child: Text(l, style: TextStyle(fontSize: 13.5, height: 1.4, color: cessumInk(context)))),
            ]),
          ),
        if (_avisoIa.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_avisoIa, style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cessumMuted(context))),
        ],
      ]),
    );
  }

  Widget _filtrosTipo(Map<String, dynamic> conteo) {
    const nombres = {
      'calificacion': 'Calificaciones',
      'pago': 'Pagos',
      'tramite': 'Trámites',
      'justificacion': 'Justificaciones',
      'mesa': 'Mesa de ayuda',
      'baja': 'Bajas',
      'horario': 'Horario',
      'programa': 'Programa',
    };
    final tipos = conteo.keys.toList()..sort((a, b) => ((conteo[b] as num?) ?? 0).compareTo((conteo[a] as num?) ?? 0));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        ChoiceChip(label: const Text('Todo'), selected: _filtro.isEmpty, onSelected: (_) => setState(() => _filtro = '')),
        for (final t in tipos) ...[
          const SizedBox(width: 6),
          ChoiceChip(
            avatar: Icon(iconoCentro(t), size: 15, color: _colorTipo(t)),
            label: Text('${nombres[t] ?? t} (${conteo[t]})'),
            selected: _filtro == t,
            onSelected: (_) => setState(() => _filtro = _filtro == t ? '' : t),
          ),
        ],
      ]),
    );
  }

  Widget _evento(Map<String, dynamic> ev) {
    final c = _colorTipo('${ev['tipo']}');
    final estado = '${ev['estado'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 74,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('${ev['fecha'] ?? ''}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          ),
        ),
        Column(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(iconoCentro('${ev['tipo']}'), size: 15, color: c),
          ),
          Container(width: 2, height: 22, color: Theme.of(context).dividerColor),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${ev['titulo'] ?? ''}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cessumInk(context))),
              if ('${ev['detalle'] ?? ''}'.isNotEmpty)
                Text('${ev['detalle']}', style: TextStyle(fontSize: 12, height: 1.35, color: cessumMuted(context))),
              if (estado.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(estado, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
