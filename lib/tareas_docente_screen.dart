import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';

/// El docente publica tareas a sus grupos y revisa quién entregó.
class TareasDocenteScreen extends StatefulWidget {
  const TareasDocenteScreen({super.key});

  @override
  State<TareasDocenteScreen> createState() => _TareasDocenteScreenState();
}

class _TareasDocenteScreenState extends State<TareasDocenteScreen> {
  String _correo = '';
  List<Map<String, dynamic>> _grupos = [];
  List<Map<String, dynamic>> _tareas = [];
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      _correo = (await SessionStore.validEmail()) ?? '';
      final g = await http
          .get(Uri.parse('$guardianUrl?accion=mis_grupos'
              '&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final gd = jsonDecode(g.body) as Map<String, dynamic>;
      final t = await http
          .get(Uri.parse('$guardianUrl?accion=tareas_docente'
              '&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final td = jsonDecode(t.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _grupos = ((gd['grupos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _tareas = ((td['tareas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevaTarea() async {
    if (_grupos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No tienes grupos asignados.'),
      ));
      return;
    }
    Map<String, dynamic>? grupoSel = _grupos.first;
    final titulo = TextEditingController();
    final desc = TextEditingController();
    final fecha = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: const Text('Nueva tarea', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: grupoSel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Materia / grupo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _grupos.map((g) {
                    return DropdownMenuItem(
                      value: g,
                      child: Text(
                        '${g['materia']} · ${g['generacion']} G${g['grupo']}',
                        style: const TextStyle(fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setS(() => grupoSel = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titulo,
                  decoration: const InputDecoration(
                    labelText: 'Título *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: desc,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / instrucciones',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fecha,
                  decoration: const InputDecoration(
                    labelText: 'Fecha límite',
                    hintText: 'dd/mm/aaaa',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                if (titulo.text.trim().isEmpty) return;
                Navigator.pop(ctx2, true);
              },
              child: const Text('Publicar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || grupoSel == null) return;

    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'tarea_crear',
                'correo': _correo,
                'programa': grupoSel!['programa'],
                'generacion': grupoSel!['generacion'],
                'grupo': grupoSel!['grupo'],
                'clave': grupoSel!['clave'],
                'materia': grupoSel!['materia'],
                'titulo': titulo.text.trim(),
                'descripcion': desc.text.trim(),
                'fechaLimite': fecha.text.trim(),
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _verEntregas(Map<String, dynamic> t) async {
    showDialog(
      context: context,
      builder: (ctx) => _DialogoEntregas(
          tareaId: t['id'].toString(), titulo: t['titulo'].toString()),
    );
  }

  Future<void> _eliminar(Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text('¿Quitar la tarea "${t['titulo']}"?'),
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
              body: jsonEncode({
                'accion': 'tarea_eliminar',
                'id': t['id'],
                'correo': _correo,
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _cargar();
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
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tareas de mis grupos',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _procesando ? null : _nuevaTarea,
        icon: const Icon(Icons.add),
        label: const Text('Nueva tarea'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : Column(
              children: [
                if (_procesando) const LinearProgressIndicator(color: cessumRed),
                Expanded(
                  child: _tareas.isEmpty
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Aún no publicas tareas. Usa "Nueva tarea".',
                              style: TextStyle(color: cessumMuted(context)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                          itemCount: _tareas.length,
                          itemBuilder: (ctx, i) {
                            final t = _tareas[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text('${t['titulo']}',
                                              style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight:
                                                      FontWeight.w800)),
                                        ),
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: Icon(Icons.delete_outline,
                                              size: 20, color: cessumFaint(context)),
                                          onPressed: _procesando
                                              ? null
                                              : () => _eliminar(t),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${t['materia']} · ${t['generacion']} G${t['grupo']}',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: cessumMuted(context)),
                                    ),
                                    if ((t['fechaLimite'] ?? '')
                                        .toString()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text('Entrega: ${t['fechaLimite']}',
                                          style: const TextStyle(
                                              fontSize: 11.5,
                                              color: cessumGold,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E8E3E)
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                              '${t['entregados']} entregada(s)',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF1E8E3E))),
                                        ),
                                        const Spacer(),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact),
                                          onPressed: () => _verEntregas(t),
                                          icon: const Icon(Icons.list_alt,
                                              size: 16),
                                          label: const Text('Ver entregas',
                                              style: TextStyle(fontSize: 11.5)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/* ---------------- Diálogo: entregas de una tarea ---------------- */
class _DialogoEntregas extends StatefulWidget {
  final String tareaId;
  final String titulo;
  const _DialogoEntregas({required this.tareaId, required this.titulo});

  @override
  State<_DialogoEntregas> createState() => _DialogoEntregasState();
}

class _DialogoEntregasState extends State<_DialogoEntregas> {
  List<Map<String, dynamic>> _alumnos = [];
  int _entregados = 0;
  int _total = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=tarea_entregas'
              '&id=${Uri.encodeComponent(widget.tareaId)}'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _alumnos = ((data['alumnos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _entregados = (data['entregados'] ?? 0) as int;
        _total = (data['total'] ?? 0) as int;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo, style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: double.maxFinite,
        child: _cargando
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: CircularProgressIndicator(color: cessumRed)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$_entregados de $_total entregaron',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13)),
                  const Divider(),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: _alumnos.map((a) {
                        final entregado = a['estatus'] == 'Entregado';
                        final enlace = (a['enlace'] ?? '').toString();
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                              entregado
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 18,
                              color: entregado
                                  ? const Color(0xFF1E8E3E)
                                  : cessumFaint(context)),
                          title: Text('${a['nombre']}',
                              style: const TextStyle(fontSize: 12.5)),
                          subtitle: entregado && a['fecha'] != ''
                              ? Text('${a['fecha']}',
                                  style: const TextStyle(fontSize: 10.5))
                              : null,
                          trailing: enlace.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.link,
                                      size: 18, color: cessumRed),
                                  onPressed: () =>
                                      Helpers.abrirUrlExterna(enlace, context),
                                )
                              : null,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }
}
