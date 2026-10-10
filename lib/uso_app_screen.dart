// =====================================================================
//  uso_app_screen.dart · CESSUM · (25-sep-2026)
//  USO DE LA APP Y SUGERENCIAS (administración)
//
//  Pestaña «Uso»: a qué pantallas entran los alumnos (aperturas, alumnos
//  distintos, % del total), horas de uso y recomendaciones de qué accesos
//  agrandar, cuáles van primero y cuáles reagrupar; análisis con IA.
//  Pestaña «Sugerencias»: el buzón del alumno, con estado y respuesta; al
//  atender una, el alumno recibe el aviso en su campanita.
//
//  Guardián: GET uso_app_reporte · POST uso_app_ia
//            GET sugerencias_app_listar · POST sugerencia_app_resolver
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

const _verde = Color(0xFF1E7F52);
const _azul = Color(0xFF2F5D8A);

class UsoAppScreen extends StatefulWidget {
  const UsoAppScreen({super.key});
  @override
  State<UsoAppScreen> createState() => _UsoAppScreenState();
}

class _UsoAppScreenState extends State<UsoAppScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  int _dias = 30;
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _rep = {};
  Map<String, dynamic>? _ia;
  bool _iaCargando = false;
  List<Map<String, dynamic>> _sug = [];
  Map<String, dynamic> _conteo = {};
  String _filtroEstado = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp, {int segundos = 120}) async {
    final actor = await SessionStore.realEmail() ?? await SessionStore.validEmail() ?? '';
    final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: {...qp, 'actor': actor})).timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body, {int segundos = 150}) async {
    final actor = await SessionStore.realEmail() ?? await SessionStore.validEmail() ?? '';
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode({...body, 'actor': actor}))
        .timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await _get({'accion': 'uso_app_reporte', 'dias': '$_dias'});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo leer el uso.');
      final s = await _get({'accion': 'sugerencias_app_listar', if (_filtroEstado.isNotEmpty) 'estado': _filtroEstado});
      if (!mounted) return;
      setState(() {
        _rep = r;
        _sug = ((s['sugerencias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _conteo = Map<String, dynamic>.from((s['conteo'] as Map?) ?? {});
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

  Future<void> _analizarIa() async {
    setState(() => _iaCargando = true);
    try {
      final r = await _post({'accion': 'uso_app_ia', 'dias': _dias});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo analizar.');
      if (!mounted) return;
      setState(() => _ia = r['analisis'] is Map ? Map<String, dynamic>.from(r['analisis'] as Map) : {'lectura': '${r['texto'] ?? ''}'});
    } catch (e) {
      if (mounted) _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _iaCargando = false);
  }

  Future<void> _resolver(Map<String, dynamic> s) async {
    var estado = '${s['estado'] ?? 'Nueva'}';
    final ctl = TextEditingController(text: '${s['respuesta'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Atender sugerencia ${s['id']}', style: const TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['nombre']} · ${s['programa']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              Text('${s['texto']}', style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: estado,
                decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'Nueva', child: Text('Nueva')),
                  DropdownMenuItem(value: 'En proceso', child: Text('En proceso · se le avisa al alumno')),
                  DropdownMenuItem(value: 'Hecha', child: Text('Hecha · se le avisa al alumno')),
                  DropdownMenuItem(value: 'No procede', child: Text('No procede · se le avisa al alumno')),
                ],
                onChanged: (v) => setLocal(() => estado = v ?? estado),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctl,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Respuesta para el alumno (opcional)',
                    hintText: 'Ej. Ya se ve tu horario en la pantalla principal',
                    border: OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final resp = ctl.text.trim();
    ctl.dispose();
    if (ok != true) return;
    try {
      final r = await _post({'accion': 'sugerencia_app_resolver', 'id': s['id'], 'estado': estado, 'respuesta': resp});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo guardar.');
      _aviso(r['avisado'] == true ? 'Guardado. El alumno recibió el aviso en su campanita.' : 'Guardado.');
      _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _aviso(String t, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: error ? cessumRed : _verde, content: Text(t)));
  }

  List<Map<String, dynamic>> _lista(dynamic v) =>
      ((v as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Uso de la app y sugerencias'),
        actions: [
          IconButton(tooltip: 'Recargar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(text: 'Uso'),
            Tab(text: 'Sugerencias${(_conteo['Nueva'] ?? 0) != 0 ? ' (${_conteo['Nueva']} nuevas)' : ''}'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : TabBarView(controller: _tabs, children: [_pestanaUso(), _pestanaSugerencias()]),
    );
  }

  // ───────────────────────────── Uso ─────────────────────────────
  Widget _pestanaUso() {
    final pantallas = _lista(_rep['pantallas']);
    final rec = Map<String, dynamic>.from((_rep['recomendaciones'] as Map?) ?? {});
    final porHora = ((_rep['porHora'] as List?) ?? []).map((e) => (e as num).toInt()).toList();
    final maxHora = porHora.isEmpty ? 1 : porHora.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    final maxAp = pantallas.isEmpty ? 1 : ((pantallas.first['aperturas'] ?? 1) as num).toInt().clamp(1, 1 << 30);
    return ListView(padding: const EdgeInsets.all(14), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Periodo:', style: TextStyle(fontSize: 13)),
        for (final d in [7, 30, 90])
          ChoiceChip(
            label: Text('$d días'),
            selected: _dias == d,
            onSelected: (_) {
              setState(() => _dias = d);
              _cargar();
            },
          ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        _kpi('${_rep['usuarios'] ?? 0}', 'alumnos que\nusaron la app', cessumRed),
        _kpi('${_rep['cobertura'] ?? 0} %', 'de los ${_rep['activos'] ?? 0}\nactivos', cessumGold),
        _kpi('${_rep['sesiones'] ?? 0}', 'días-alumno\ncon uso', _azul),
        _kpi('${_rep['eventos'] ?? 0}', 'pantallas\nabiertas', _verde),
      ]),
      if ('${_rep['nota'] ?? ''}'.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 10), child: Text('${_rep['nota']}', style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))),
      if (pantallas.isNotEmpty) ...[
        _titulo('Qué recomienda el uso'),
        _rec('Hacer más grandes', rec['agrandar'], cessumRed, 'Las abre 40 % o más de los alumnos.'),
        _rec('Poner primero', rec['primero'], cessumGold, 'Orden por alumnos distintos que las abren.'),
        _rec('Reagrupar o bajar', rec['reagrupar'], _azul, 'Las abre menos del 5 % de los alumnos.'),
        _titulo('Pantallas más usadas'),
        for (final p in pantallas.take(30))
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${p['pantalla']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                Text('${p['usuarios']} alumnos · ${p['pctUsuarios']} %', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              ]),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (((p['aperturas'] ?? 0) as num) / maxAp).clamp(0, 1).toDouble(),
                  minHeight: 7,
                  backgroundColor: cessumMuted(context).withValues(alpha: 0.15),
                  color: cessumRed,
                ),
              ),
              Text('${p['aperturas']} aperturas · ${p['porUsuario']} por alumno · ${((p['programas'] as List?) ?? []).join(', ')}',
                  style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            ]),
          ),
        _titulo('Horas del día en que se usa'),
        SizedBox(
          height: 90,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var h = 0; h < porHora.length; h++)
              Expanded(
                child: Tooltip(
                  message: '$h:00 · ${porHora[h]}',
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    height: 8 + 70 * porHora[h] / maxHora,
                    decoration: BoxDecoration(color: h >= 18 ? cessumRed : cessumGold, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
          ]),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('0 h', style: TextStyle(fontSize: 10, color: cessumMuted(context))),
          Text('12 h', style: TextStyle(fontSize: 10, color: cessumMuted(context))),
          Text('23 h', style: TextStyle(fontSize: 10, color: cessumMuted(context))),
        ]),
        _titulo('Análisis con IA'),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: cessumRed),
          onPressed: _iaCargando ? null : _analizarIa,
          icon: _iaCargando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(_iaCargando ? 'Analizando…' : (_ia == null ? 'Analizar uso y sugerencias' : 'Volver a analizar')),
        ),
        if (_ia != null) _bloqueIa(),
      ],
    ]);
  }

  Widget _bloqueIa() {
    final ia = _ia!;
    Widget lista(String t, dynamic v) {
      final l = (v as List?) ?? [];
      if (l.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cessumRed)),
          for (final x in l)
            Text('• ${x is Map ? '${x['grupo']}: ${((x['pantallas'] as List?) ?? []).join(', ')}' : x}',
                style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ]),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${ia['lectura'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.45)),
        lista('Hacer más grandes', ia['agrandar']),
        lista('Orden sugerido', ia['primero']),
        lista('Reagrupar', ia['reagrupar']),
        lista('Pueden ir a un menú secundario', ia['quitarDelFrente']),
        lista('Lo que más piden los alumnos', ia['sugerenciasClave']),
        lista('Acciones para esta semana', ia['acciones']),
      ]),
    );
  }

  // ───────────────────────── Sugerencias ─────────────────────────
  Widget _pestanaSugerencias() {
    return ListView(padding: const EdgeInsets.all(14), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in ['', 'Nueva', 'En proceso', 'Hecha', 'No procede'])
          ChoiceChip(
            label: Text(e.isEmpty ? 'Todas' : '$e${(_conteo[e] ?? 0) != 0 ? ' (${_conteo[e]})' : ''}'),
            selected: _filtroEstado == e,
            onSelected: (_) {
              setState(() => _filtroEstado = e);
              _cargar();
            },
          ),
      ]),
      const SizedBox(height: 10),
      if (_sug.isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Todavía no hay sugerencias. Aparecerán aquí en cuanto los alumnos usen el buzón del menú.',
              textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context))),
        ),
      for (final s in _sug)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => _resolver(s),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${s['nombre']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
                  _chipEstado('${s['estado']}'),
                ]),
                Text('${s['programa']} · ${s['fecha']} · ${s['id']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                const SizedBox(height: 6),
                Text('${s['texto']}', style: const TextStyle(fontSize: 13, height: 1.4)),
                if ('${s['respuesta'] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Respuesta: ${s['respuesta']}', style: const TextStyle(fontSize: 12.5, color: _verde, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _chipEstado(String e) {
    final c = e == 'Hecha' ? _verde : e == 'En proceso' ? cessumGold : e == 'No procede' ? Colors.grey : cessumRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(e, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
    );
  }

  Widget _kpi(String v, String t, Color c) => Container(
        width: 118,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: c)),
          Text(t, style: TextStyle(fontSize: 10.5, height: 1.2, color: cessumMuted(context))),
        ]),
      );

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: cessumRed)),
      );

  Widget _rec(String t, dynamic v, Color c, String nota) {
    final l = ((v as List?) ?? []).map((e) => '$e').toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
        Text(l.isEmpty ? 'Ninguna por ahora.' : l.join(' · '), style: const TextStyle(fontSize: 12.5, height: 1.4)),
        Text(nota, style: TextStyle(fontSize: 11, color: cessumMuted(context))),
      ]),
    );
  }
}
