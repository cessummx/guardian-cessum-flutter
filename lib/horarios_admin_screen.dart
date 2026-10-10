import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

const _dias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo'
];

/// Admin: construye y edita el horario de cada grupo.
class HorariosAdminScreen extends StatefulWidget {
  const HorariosAdminScreen({super.key});

  @override
  State<HorariosAdminScreen> createState() => _HorariosAdminScreenState();
}

class _HorariosAdminScreenState extends State<HorariosAdminScreen> {
  List<Map<String, dynamic>> _catalogo = [];
  String? _programa;
  String? _generacion;
  String? _grupo;
  List<Map<String, dynamic>> _clases = [];
  bool _cargandoCat = true;
  bool _cargandoClases = false;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() async {
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=catalogo_grupos'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _catalogo = ((data['catalogo'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargandoCat = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargandoCat = false);
    }
  }

  List<String> get _programas =>
      _catalogo.map((p) => (p['programa'] ?? '').toString()).toList();

  List<Map<String, dynamic>> get _generacionesDe {
    if (_programa == null) return [];
    final p = _catalogo.firstWhere((e) => e['programa'] == _programa,
        orElse: () => {});
    return ((p['generaciones'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  List<String> get _gruposDe {
    if (_generacion == null) return [];
    final g = _generacionesDe.firstWhere(
        (e) => e['generacion'] == _generacion,
        orElse: () => {});
    return ((g['grupos'] as List?) ?? []).map((e) => e.toString()).toList();
  }

  Future<void> _cargarClases() async {
    if (_programa == null || _grupo == null) return;
    setState(() => _cargandoClases = true);
    try {
      final uri = Uri.parse('$guardianUrl?accion=horario_grupo'
          '&programa=${Uri.encodeComponent(_programa!)}'
          '&generacion=${Uri.encodeComponent(_generacion ?? '')}'
          '&grupo=${Uri.encodeComponent(_grupo!)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _clases = ((data['clases'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargandoClases = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargandoClases = false);
    }
  }

  Future<void> _abrirLink(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final uri = Uri.tryParse(u.startsWith('http') ? u : 'https://$u');
    if (uri == null) return;
    await launchUrl(uri,
        webOnlyWindowName: '_blank', mode: LaunchMode.externalApplication);
  }

  Future<void> _editarClase([Map<String, dynamic>? clase]) async {
    final esNueva = clase == null;
    String dia = (clase?['dia'] ?? 'Lunes').toString();
    if (!_dias.contains(dia)) dia = 'Lunes';
    final hIni = TextEditingController(text: (clase?['horaInicio'] ?? '').toString());
    final hFin = TextEditingController(text: (clase?['horaFin'] ?? '').toString());
    final materia = TextEditingController(text: (clase?['materia'] ?? '').toString());
    final docente = TextEditingController(text: (clase?['docente'] ?? '').toString());
    final aula = TextEditingController(text: (clase?['aula'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text(esNueva ? 'Agregar clase' : 'Editar clase',
              style: const TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: dia,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Día',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _dias
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => setS(() => dia = v!),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: hIni,
                        decoration: const InputDecoration(
                          labelText: 'Hora inicio',
                          hintText: '08:00',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: hFin,
                        decoration: const InputDecoration(
                          labelText: 'Hora fin',
                          hintText: '10:00',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: materia,
                  decoration: const InputDecoration(
                    labelText: 'Materia *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: docente,
                  decoration: const InputDecoration(
                    labelText: 'Docente',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: aula,
                  decoration: const InputDecoration(
                    labelText: 'Aula',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (!esNueva)
              TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancelar'),
              ),
            if (esNueva)
              TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancelar'),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                if (materia.text.trim().isEmpty) return;
                Navigator.pop(ctx2, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final body = {
        'accion': 'horario_guardar',
        'programa': _programa,
        'generacion': _generacion ?? '',
        'grupo': _grupo,
        'dia': dia,
        'horaInicio': hIni.text.trim(),
        'horaFin': hFin.text.trim(),
        'materia': materia.text.trim(),
        'docente': docente.text.trim(),
        'aula': aula.text.trim(),
      };
      if (!esNueva) body['id'] = clase['id'];
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _cargarClases();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> clase) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar clase'),
        content: Text(
            '¿Quitar ${clase['materia']} (${clase['dia']} ${clase['horaInicio']}) del horario?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(
                  {'accion': 'horario_eliminar', 'id': clase['id']}))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _cargarClases();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grupoElegido = _programa != null && _grupo != null;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Horarios por grupo',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: grupoElegido
          ? FloatingActionButton.extended(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              onPressed: _procesando ? null : () => _editarClase(),
              icon: const Icon(Icons.add),
              label: const Text('Agregar clase'),
            )
          : null,
      body: _cargandoCat
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : Column(
              children: [
                if (_procesando) const LinearProgressIndicator(color: cessumRed),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _programa,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Programa',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _programas
                            .map((p) =>
                                DropdownMenuItem(value: p, child: Text(p)))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _programa = v;
                          _generacion = null;
                          _grupo = null;
                          _clases = [];
                        }),
                      ),
                      if (_generacionesDe.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _generacion,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Generación',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _generacionesDe
                              .map((g) => DropdownMenuItem(
                                  value: (g['generacion'] ?? '').toString(),
                                  child: Text((g['generacion'] ?? '').toString())))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _generacion = v;
                            _grupo = null;
                            _clases = [];
                          }),
                        ),
                      ],
                      if (_gruposDe.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _grupo,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Grupo',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _gruposDe
                              .map((g) =>
                                  DropdownMenuItem(value: g, child: Text('Grupo $g')))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _grupo = v);
                            _cargarClases();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: !grupoElegido
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Elige programa, generación y grupo para ver y armar su horario.',
                              style: TextStyle(color: cessumMuted(context)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _cargandoClases
                          ? const Center(
                              child: CircularProgressIndicator(color: cessumRed))
                          : _clases.isEmpty
                              ? Center(
                                  child: Text(
                                      'Este grupo aún no tiene horario. Usa "Agregar clase".',
                                      style: TextStyle(color: cessumMuted(context))),
                                )
                              : _vistaPorDia(),
                ),
              ],
            ),
    );
  }

  Widget _vistaPorDia() {
    final porDia = <String, List<Map<String, dynamic>>>{};
    for (final c in _clases) {
      porDia.putIfAbsent((c['dia'] ?? '').toString(), () => []).add(c);
    }
    final diasConClase = _dias.where((d) => porDia.containsKey(d)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      children: diasConClase.map((dia) {
        final clases = porDia[dia]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(dia,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: cessumRed)),
            ),
            ...clases.map((c) {
              final editable = c['editable'] != false;
              final link = (c['link'] ?? '').toString().trim();
              final horas = [c['horaInicio'], c['horaFin']]
                  .where((x) => (x ?? '').toString().trim().isNotEmpty)
                  .join('\n');
              final infoParts = <String>[
                if ((c['docente'] ?? '').toString().isNotEmpty) '${c['docente']}',
                if ((c['aula'] ?? '').toString().isNotEmpty) 'Aula ${c['aula']}',
              ];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      leading: Container(
                        width: 56,
                        alignment: Alignment.center,
                        child: Text(
                          horas,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: cessumGold),
                        ),
                      ),
                      title: Text('${c['materia']}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (infoParts.isNotEmpty)
                            Text(infoParts.join(' · '),
                                style: const TextStyle(fontSize: 11.5)),
                          if (!editable)
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Text('Programación',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: cessumGold,
                                      fontWeight: FontWeight.w800)),
                            ),
                        ],
                      ),
                      trailing: editable
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      size: 20, color: cessumRed),
                                  onPressed: _procesando
                                      ? null
                                      : () => _editarClase(c),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      size: 20, color: cessumFaint(context)),
                                  onPressed: _procesando
                                      ? null
                                      : () => _eliminar(c),
                                ),
                              ],
                            )
                          : (link.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.videocam,
                                      size: 22, color: cessumRed),
                                  tooltip: 'Abrir enlace',
                                  onPressed: () => _abrirLink(link),
                                )
                              : const SizedBox(width: 8)),
                    ),
                    if (link.isNotEmpty)
                      InkWell(
                        onTap: () => _abrirLink(link),
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Row(
                            children: [
                              const Icon(Icons.link,
                                  size: 16, color: cessumRed),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  link,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: cessumRed,
                                      decoration:
                                          TextDecoration.underline),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        );
      }).toList(),
    );
  }
}
