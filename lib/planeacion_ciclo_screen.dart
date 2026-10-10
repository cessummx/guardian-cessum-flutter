// planeacion_ciclo_screen.dart · CESSUM · (24-sep-2026)
//
// PLANEACIÓN DEL CICLO, ASISTIDA · fase 4 de los centros inteligentes.
// Un tablero de principio a fin: 1 oferta y claves, 2 programación, 3
// docentes sin choques ni sobrecarga, 4 invitaciones aceptadas. Cada paso
// dice qué falta y abre la herramienta que lo resuelve. Con IA: «Huecos y
// sobrecargas», la lectura de qué impide publicar y qué resolver primero.
// Base: GET planeacion_ciclo y planeacion_ciclo_ia (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'centros_nav.dart';
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

class PlaneacionCicloScreen extends StatefulWidget {
  const PlaneacionCicloScreen({super.key});

  @override
  State<PlaneacionCicloScreen> createState() => _PlaneacionCicloScreenState();
}

class _PlaneacionCicloScreenState extends State<PlaneacionCicloScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String _error = '';
  Map<String, dynamic>? _d;
  bool _pidiendoIa = false;
  List<String> _lineas = [];

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
      final r = await http.get(Uri.parse('$guardianUrl?accion=planeacion_ciclo')).timeout(const Duration(seconds: 180));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo revisar la planeación.');
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

  Future<void> _lectura() async {
    setState(() => _pidiendoIa = true);
    try {
      final r = await http.get(Uri.parse('$guardianUrl?accion=planeacion_ciclo_ia')).timeout(const Duration(seconds: 180));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar la lectura.');
      if (!mounted) return;
      setState(() => _lineas = ((d['lineas'] as List?) ?? []).map((e) => '$e').toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
    if (mounted) setState(() => _pidiendoIa = false);
  }

  // (8-oct-2026) Antes castaba directo a `List?` y cada elemento a `Map` sin protección:
  // si el backend mandaba esa clave con otra forma (un objeto en vez de arreglo) o con un
  // elemento nulo/mal formado, tronaba toda la pantalla. Ahora se descarta en silencio lo
  // que no tenga la forma esperada, en vez de tronar por su culpa.
  // (8-oct-2026) `pendientes` venía casteado con `as num?`: si el backend lo manda como texto
  // (p. ej. "0" en vez de 0, algo que Apps Script produce fácilmente), ese cast truena en vez
  // de devolver null. Este parser acepta número o texto numérico y, si no reconoce la forma,
  // regresa 0 en vez de tronar.
  int _n(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? (double.tryParse(v.trim())?.toInt() ?? 0);
    return 0;
  }

  List<Map<String, dynamic>> _l(String k) {
    final v = _d?[k];
    if (v is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in v) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final pasos = _l('pasos');
    final pendTotal = pasos.fold<int>(0, (s, p) => s + _n(p['pendientes']));
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Planeación del ciclo', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Huecos y sobrecargas (IA)',
            onPressed: (_cargando || _pidiendoIa) ? null : _lectura,
            icon: _pidiendoIa ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_awesome),
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
                      Icon(Icons.event_note_outlined, size: 44, color: cessumFaint(context)),
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
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]), borderRadius: BorderRadius.circular(16)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(pendTotal == 0 ? 'Planeación lista para publicar' : '$pendTotal pendiente(s) antes de publicar', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('${_d?['cursosVigentes'] ?? 0} cursos vigentes · ${_d?['asignacionesActivas'] ?? 0} asignaciones · ${_d?['generado'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                          if (_lineas.isEmpty) ...[
                            const SizedBox(height: 10),
                            TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white.withValues(alpha: 0.14)),
                              onPressed: _pidiendoIa ? null : _lectura,
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: Text(_pidiendoIa ? 'Pensando…' : 'Huecos y sobrecargas'),
                            ),
                          ],
                        ]),
                      ),
                      if (_lineas.isNotEmpty) ...[const SizedBox(height: 12), _cajaIa()],
                      const SizedBox(height: 14),
                      for (var i = 0; i < pasos.length; i++) _paso(pasos[i], i == pasos.length - 1),
                      const SizedBox(height: 8),
                      if (_l('proximas').isNotEmpty) _bloque('INICIAN EN LOS PRÓXIMOS 14 DÍAS', _l('proximas').map((p) => (p['sinDocente'] == true ? '⚠ ' : '') + '${p['inicio']} · ${p['materia']} · ${p['programa']}${'${p['grupo'] ?? ''}'.isNotEmpty ? ' G${p['grupo']}' : ''} · ${p['docente']}').toList()),
                      if (_l('sobrecarga').isNotEmpty) _bloque('DOCENTES CON 4 O MÁS MATERIAS', _l('sobrecarga').map((s) => '${s['docente']} · ${s['materias']} materias').toList()),
                      if (_l('choques').isNotEmpty) _bloque('CHOQUES DE HORARIO', _l('choques').map((c) => '${c['docente']} · ${c['materia']} · ${c['dia']} ${c['hora']} · ${c['motivo']}').toList()),
                      if (_l('invitacionesPendientes').isNotEmpty) _bloque('INVITACIONES SIN ACEPTAR', _l('invitacionesPendientes').map((i) => '${i['docente']} · ${i['materia']} · ${i['estado']}${'${i['inicio'] ?? ''}'.isNotEmpty ? ' · inicia ${i['inicio']}' : ''}').toList()),
                      const SizedBox(height: 24),
                    ],
                  ),
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
          Text('HUECOS Y SOBRECARGAS', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumInk(context))),
          const Spacer(),
          IconButton(tooltip: 'Copiar', iconSize: 18, onPressed: () => Helpers.copiarAlPortapapeles(context, _lineas.map((l) => '• $l').join('\n'), 'Lectura'), icon: const Icon(Icons.copy_outlined)),
        ]),
        for (final l in _lineas)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('• ', style: TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              Expanded(child: Text(l, style: TextStyle(fontSize: 13.5, height: 1.4, color: cessumInk(context)))),
            ]),
          ),
      ]),
    );
  }

  Widget _paso(Map<String, dynamic> p, bool ultimo) {
    final n = _n(p['pendientes']);
    final c = n == 0 ? _verde : cessumRed;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          child: Icon(n == 0 ? Icons.check : Icons.priority_high, color: Colors.white, size: 16),
        ),
        if (!ultimo) Container(width: 2, height: 46, color: Theme.of(context).dividerColor),
      ]),
      const SizedBox(width: 12),
      Expanded(
        child: Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.withValues(alpha: 0.45))),
          child: ListTile(
            onTap: () => abrirPantallaCentro(context, '${p['pantalla'] ?? ''}'),
            title: Text('${p['titulo'] ?? ''}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: cessumInk(context))),
            subtitle: Text('${p['detalle'] ?? ''}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            trailing: Icon(Icons.chevron_right, color: cessumFaint(context)),
          ),
        ),
      ),
    ]);
  }

  Widget _bloque(String titulo, List<String> lineas) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumMuted(context))),
        const SizedBox(height: 6),
        for (final l in lineas.take(25)) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• $l', style: TextStyle(fontSize: 12.5, color: cessumInk(context)))),
        if (lineas.length > 25) Text('… y ${lineas.length - 25} más', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: cessumMuted(context))),
      ]),
    );
  }
}
