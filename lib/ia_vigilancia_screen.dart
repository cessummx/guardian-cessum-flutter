// =====================================================================
//  ia_vigilancia_screen.dart · CESSUM · (24-sep-2026)
//  IA · FASE 4 (administración)
//   · VigilanteAdmisionesScreen: lee el panel de prospectos y los formularios
//     de inscripción y dice qué se rompió. El correo va SOLO a Vicerrectoría.
//   · ResumenesClaseScreen: resúmenes de clases grabadas (transcripción de
//     Meet + IA). Se revisan y se publican a los alumnos del grupo como aviso
//     en la app (campanita), con confirmación previa. No se envían correos.
//  Guardián: GET admisiones_vigilar · GET fase4_instalar · GET clases_resumir
//            GET resumenes_clase_listar · POST resumen_clase_publicar
//            POST resumen_clase_descartar
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

const _verde = Color(0xFF1E7F52);

Future<Map<String, dynamic>> _getF4(Map<String, String> qp, {int segundos = 120}) async {
  final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: qp)).timeout(Duration(seconds: segundos));
  return jsonDecode(r.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _postF4(Map<String, dynamic> body) async {
  final r = await http
      .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
      .timeout(const Duration(seconds: 120));
  return jsonDecode(r.body) as Map<String, dynamic>;
}

void _snackF4(BuildContext context, String t, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    backgroundColor: error ? cessumRed : _verde,
    duration: const Duration(seconds: 6),
    content: Text(t),
  ));
}

Future<void> _programarF4(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Programar las tareas diarias?'),
      content: const Text(
          'Vigilante de admisiones: cada día a las 7:30, solo si hay alertas (y los lunes con resumen semanal). '
          'El correo va SOLO a vicerrectoria@cessum.mx.\n\n'
          'Resúmenes de clase: cada día a las 22:00 se preparan los de las clases nuevas y quedan «Por revisar». '
          'A los alumnos solo les llega cuando usted publica cada uno.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cessumRed),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Programar'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    final d = await _getF4({'accion': 'fase4_instalar'});
    if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo programar.');
    if (context.mounted) _snackF4(context, 'Programado: vigilante 7:30 y resúmenes 22:00.');
  } catch (e) {
    if (context.mounted) _snackF4(context, '$e'.replaceFirst('Exception: ', ''), error: true);
  }
}

// =====================================================================
//  VIGILANTE DE ADMISIONES
// =====================================================================
class VigilanteAdmisionesScreen extends StatefulWidget {
  const VigilanteAdmisionesScreen({super.key});
  @override
  State<VigilanteAdmisionesScreen> createState() => _VigilanteAdmisionesScreenState();
}

class _VigilanteAdmisionesScreenState extends State<VigilanteAdmisionesScreen> {
  bool _cargando = true;
  bool _enviando = false;
  String _error = '';
  Map<String, dynamic> _inf = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool semanal = false}) async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final d = await _getF4({'accion': 'admisiones_vigilar', 'semanal': semanal ? '1' : '0'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo revisar.');
      _inf = d;
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    try {
      final d = await _getF4({'accion': 'admisiones_vigilar', 'enviar': '1', 'semanal': '1'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo enviar.');
      if (mounted) _snackF4(context, 'Enviado a ${d['enviadoA']}.');
    } catch (e) {
      if (mounted) _snackF4(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    final alertas = ((_inf['alertas'] as List?) ?? []).map((e) => '$e').toList();
    final forms = ((_inf['formularios'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final panel = Map<String, dynamic>.from((_inf['panel'] as Map?) ?? {});
    final fuera = Map<String, dynamic>.from((_inf['fueraDelPanel'] as Map?) ?? {});
    final semana = Map<String, dynamic>.from((_inf['semana'] as Map?) ?? {});
    final paginas = ((_inf['paginas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Vigilante de admisiones'),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error, textAlign: TextAlign.center),
                  TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                ]))
              : ListView(padding: const EdgeInsets.all(14), children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: cessumRed),
                      onPressed: _enviando ? null : _enviar,
                      icon: const Icon(Icons.mark_email_unread_outlined, size: 18),
                      label: Text(_enviando ? 'Enviando…' : 'Enviarme el correo ahora'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                      onPressed: () => _cargar(semanal: true),
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Ver resumen semanal con IA'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                      onPressed: () => _programarF4(context),
                      icon: const Icon(Icons.schedule, size: 18),
                      label: const Text('Programar vigilancia diaria'),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Text(alertas.isEmpty ? 'Sin alertas: el embudo funciona con normalidad.' : 'Para atender (${alertas.length})',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: alertas.isEmpty ? _verde : cessumRed)),
                  const SizedBox(height: 6),
                  for (final a in alertas)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: cessumRed.withValues(alpha: 0.3)),
                      ),
                      child: Text(a, style: const TextStyle(fontSize: 13, height: 1.4)),
                    ),
                  if ('${semana['lectura'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                      child: Text('Lectura con IA: ${semana['lectura']}', style: const TextStyle(fontSize: 13, height: 1.45)),
                    ),
                  ],
                  // (25-sep) Páginas públicas y formularios de inscripción.
                  if (paginas.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Páginas y formularios', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    for (final p in paginas)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(p['ok'] == true ? Icons.check_circle : Icons.error,
                            color: p['ok'] == true ? _verde : cessumRed, size: 20),
                        title: Text('${p['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${p['detalle']} · ${p['segundos']} s'),
                        onTap: () => launchUrl(Uri.parse('${p['url']}'), webOnlyWindowName: '_blank'),
                      ),
                  ],
                  const SizedBox(height: 14),
                  const Text('Formularios de inscripción', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  for (final f in forms)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${f['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('Esta semana ${f['ult7']} · la anterior ${f['prev7']} · total ${f['total']} · última ${f['ultima']}'),
                    ),
                  const SizedBox(height: 6),
                  const Text('Panel de prospectos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  Text(
                    '${panel['prospectos'] ?? 0} registros · último ${panel['ultimo'] ?? '—'} · «Nuevo» sin contacto: ${panel['nuevosSinContacto'] ?? 0}\n'
                    'Último gasto de publicidad registrado: ${panel['ultimoGasto'] ?? '—'} · último movimiento del bot: ${panel['ultimoEventoBot'] ?? '—'}',
                    style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumMuted(context)),
                  ),
                  if ((fuera['total'] ?? 0) > 0) ...[
                    const SizedBox(height: 14),
                    Text('Inscritos que no pasaron por el panel (30 días): ${fuera['total']}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    for (final a in ((fuera['alumnos'] as List?) ?? []))
                      Text('• $a', style: const TextStyle(fontSize: 12.5, height: 1.45)),
                  ],
                  const SizedBox(height: 20),
                  Text('Generado: ${_inf['generado'] ?? ''}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                ]),
    );
  }
}

// =====================================================================
//  RESÚMENES DE CLASE
// =====================================================================
class ResumenesClaseScreen extends StatefulWidget {
  const ResumenesClaseScreen({super.key});
  @override
  State<ResumenesClaseScreen> createState() => _ResumenesClaseScreenState();
}

class _ResumenesClaseScreenState extends State<ResumenesClaseScreen> {
  bool _cargando = true;
  bool _buscando = false;
  String _error = '';
  List<Map<String, dynamic>> _items = [];
  bool _soloPendientes = true;
  final Map<int, TextEditingController> _textos = {};
  final Set<int> _ocupados = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _textos.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final d = await _getF4({'accion': 'resumenes_clase_listar'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cargar.');
      _items = ((d['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _buscar() async {
    setState(() => _buscando = true);
    try {
      final d = await _getF4({'accion': 'clases_resumir', 'max': '3'}, segundos: 400);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo buscar.');
      if (mounted) {
        _snackF4(context,
            'Transcripciones nuevas: ${d['encontradas']} · resumidas: ${d['resumidas']}${(d['sinMateria'] ?? 0) > 0 ? ' · sin materia identificada: ${d['sinMateria']}' : ''}');
      }
      await _cargar();
    } catch (e) {
      if (mounted) _snackF4(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _buscando = false);
  }

  TextEditingController _ctl(Map<String, dynamic> x) {
    final fila = (x['fila'] as num).toInt();
    return _textos.putIfAbsent(fila, () {
      final r = Map<String, dynamic>.from((x['resumen'] as Map?) ?? {});
      final tareas = ((r['tareas'] as List?) ?? [])
          .map((t) => t is Map ? '${t['tarea']}${'${t['fecha'] ?? ''}'.isNotEmpty ? ' (${t['fecha']})' : ''}' : '$t')
          .toList();
      return TextEditingController(
          text: '${r['resumen'] ?? ''}${tareas.isNotEmpty ? '\n\nTareas: ${tareas.join('; ')}' : ''}');
    });
  }

  Future<void> _publicar(Map<String, dynamic> x) async {
    final fila = (x['fila'] as num).toInt();
    final texto = _ctl(x).text.trim();
    setState(() => _ocupados.add(fila));
    try {
      final pre = await _postF4({'accion': 'resumen_clase_publicar', 'fila': fila, 'resumen': texto});
      if (pre['ok'] != true) throw Exception(pre['error'] ?? 'No se pudo preparar.');
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('¿Publicar a ${pre['alumnos']} alumno(s)?', style: const TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${pre['nota']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Text('${pre['titulo']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${pre['texto']}', style: const TextStyle(fontSize: 13, height: 1.4)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: (pre['alumnos'] ?? 0) == 0 ? null : () => Navigator.pop(ctx, true),
              child: const Text('Publicar'),
            ),
          ],
        ),
      );
      if (ok == true) {
        final d = await _postF4({'accion': 'resumen_clase_publicar', 'fila': fila, 'resumen': texto, 'confirmar': true});
        if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo publicar.');
        if (mounted) _snackF4(context, 'Publicado: les llegó a ${d['avisados']} alumno(s).');
        await _cargar();
      }
    } catch (e) {
      if (mounted) _snackF4(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _ocupados.remove(fila));
  }

  Future<void> _descartar(Map<String, dynamic> x) async {
    final fila = (x['fila'] as num).toInt();
    try {
      final d = await _postF4({'accion': 'resumen_clase_descartar', 'fila': fila});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo.');
      await _cargar();
    } catch (e) {
      if (mounted) _snackF4(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vis = _soloPendientes ? _items.where((x) => x['estado'] == 'Por revisar').toList() : _items;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Resúmenes de clase'),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error, textAlign: TextAlign.center),
                  TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                ]))
              : ListView(padding: const EdgeInsets.all(14), children: [
                  Text(
                    'La IA resume las clases que Meet transcribió: temas, ideas clave y tareas. Revíselo, ajústelo y publíquelo: '
                    'a los alumnos del grupo les llega como aviso en la app. No se envían correos.',
                    style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumMuted(context)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: cessumRed),
                      onPressed: _buscando ? null : _buscar,
                      icon: _buscando
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_buscando ? 'Resumiendo… (1-3 min)' : 'Buscar clases nuevas'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                      onPressed: () => _programarF4(context),
                      icon: const Icon(Icons.schedule, size: 18),
                      label: const Text('Programar diario'),
                    ),
                    ChoiceChip(
                      label: const Text('Por revisar'),
                      selected: _soloPendientes,
                      onSelected: (_) => setState(() => _soloPendientes = true),
                    ),
                    ChoiceChip(
                      label: Text('Todos (${_items.length})'),
                      selected: !_soloPendientes,
                      onSelected: (_) => setState(() => _soloPendientes = false),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  if (vis.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          _items.isEmpty
                              ? 'Todavía no hay resúmenes. Toque «Buscar clases nuevas».\nSolo hay transcripción de las clases cuyo Meet se creó después de activar la transcripción automática.'
                              : 'Nada por revisar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cessumMuted(context)),
                        ),
                      ),
                    )
                  else
                    ...vis.map(_tarjeta),
                ]),
    );
  }

  Widget _tarjeta(Map<String, dynamic> x) {
    final r = Map<String, dynamic>.from((x['resumen'] as Map?) ?? {});
    final temas = ((r['temas'] as List?) ?? []).map((e) => '$e').toList();
    final ideas = ((r['ideas'] as List?) ?? []).map((e) => '$e').toList();
    final est = '${x['estado']}';
    final fila = (x['fila'] as num).toInt();
    final pendiente = est == 'Por revisar';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${x['materia']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
            Text(est,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: est == 'Publicado' ? _verde : (pendiente ? cessumGold : Colors.grey))),
          ]),
          Text('${x['programa']} · ${x['generacion']} · ${x['grupo']} · ${x['fecha']} · ${x['docente']}',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          if (temas.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Temas: ${temas.join(' · ')}', style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ],
          if (ideas.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final i in ideas) Text('• $i', style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ],
          if (pendiente) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _ctl(x),
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Lo que recibirán los alumnos (editable)'),
            ),
          ] else if (est == 'Publicado')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Publicado el ${x['publicado']} por ${x['publicadoPor']} · ${x['avisados']} alumno(s)',
                  style: const TextStyle(fontSize: 12, color: _verde, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if ('${x['transcripcion']}'.isNotEmpty)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
                onPressed: () => launchUrl(Uri.parse('${x['transcripcion']}'), webOnlyWindowName: '_blank'),
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('Ver transcripción'),
              ),
            if (pendiente) ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: cessumRed, visualDensity: VisualDensity.compact),
                onPressed: _ocupados.contains(fila) ? null : () => _publicar(x),
                icon: const Icon(Icons.campaign_outlined, size: 16),
                label: const Text('Publicar al grupo'),
              ),
              TextButton(onPressed: () => _descartar(x), child: const Text('Descartar', style: TextStyle(color: Colors.grey))),
            ],
          ]),
        ]),
      ),
    );
  }
}
