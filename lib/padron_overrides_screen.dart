import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cartas_service.dart';
import 'auth/session_store.dart';

/// Correcciones del padrón (alumnos.json) sin editar el archivo a mano.
/// Crea/edita una hoja de overrides que el sistema fusiona con el padrón:
/// arreglar modalidad, correo, nombre, programa, generación, grupo o estatus,
/// o agregar un alumno que no está. La identificación es por matrícula.
class PadronOverridesScreen extends StatefulWidget {
  const PadronOverridesScreen({super.key});

  @override
  State<PadronOverridesScreen> createState() => _PadronOverridesScreenState();
}

class _PadronOverridesScreenState extends State<PadronOverridesScreen> {
  bool _cargando = true;
  String? _error;
  List<dynamic> _overrides = [];
  List<String> _programas = []; // nombres oficiales (cartas.json)

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarProgramas();
  }

  Future<void> _cargarProgramas() async {
    try {
      final progs = await CartasService.obtener();
      final nombres = progs
          .map((p) => p.programa.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (mounted) setState(() => _programas = nombres);
    } catch (_) {
      // Sin lista oficial, el formulario permite escribir el programa a mano.
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'padron_override_listar',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      if (!mounted) return;
      setState(() {
        _overrides = (data['overrides'] as List?) ?? [];
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar ($e)';
      });
    }
  }

  Future<void> _guardar(Map<String, String> campos) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'padron_override_set',
                'actor': actor,
                ...campos,
              }))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF1E8E3E),
          content: Text('Corrección guardada.'),
        ));
        await _cargar();
      } else {
        throw Exception(data['error'] ?? 'No se pudo');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumRed, content: Text('No se pudo: $e')));
    }
  }

  Future<void> _borrar(String matricula) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar corrección'),
        content: Text(
            'Se quitará la corrección de la matrícula $matricula. El alumno '
            'volverá a leerse tal cual del padrón. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final actor = await SessionStore.realEmail() ?? '';
      await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'padron_override_borrar',
                'actor': actor,
                'matricula': matricula,
              }))
          .timeout(const Duration(seconds: 60));
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumRed, content: Text('No se pudo: $e')));
    }
  }

  Future<void> _formulario({Map? existente}) async {
    final mat = TextEditingController(
        text: (existente?['matricula'] ?? '').toString());
    final nom =
        TextEditingController(text: (existente?['nombre'] ?? '').toString());
    final cor =
        TextEditingController(text: (existente?['correo'] ?? '').toString());
    String programaSel = (existente?['programa'] ?? '').toString();
    final gen = TextEditingController(
        text: (existente?['generacion'] ?? '').toString());
    final gru =
        TextEditingController(text: (existente?['grupo'] ?? '').toString());
    String modalidad = (existente?['modalidad'] ?? '').toString();
    String estatus = (existente?['estatus'] ?? '').toString();
    String? err;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existente == null ? 'Nueva corrección' : 'Editar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deja en blanco los campos que NO quieras cambiar. '
                  'La matrícula es obligatoria.',
                  style: TextStyle(fontSize: 12, color: cessumFaint(context)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: mat,
                  enabled: existente == null,
                  decoration: const InputDecoration(
                      labelText: 'Matrícula *',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nom,
                  decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cor,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Correo (@cessum.mx)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  // Lista de programas oficiales (cartas.json) + el valor actual
                  // si no estuviera en la lista. Evita escribir el nombre mal.
                  final opciones = <String>[..._programas];
                  if (programaSel.isNotEmpty &&
                      !opciones.contains(programaSel)) {
                    opciones.insert(0, programaSel);
                  }
                  return DropdownButtonFormField<String>(
                    value: programaSel.isEmpty ? null : programaSel,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Programa',
                        border: OutlineInputBorder(),
                        isDense: true),
                    hint: const Text('(sin cambiar)'),
                    items: [
                      const DropdownMenuItem<String>(
                          value: '', child: Text('(sin cambiar)')),
                      ...opciones.map((p) => DropdownMenuItem<String>(
                            value: p,
                            child: Text(p,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) => setSt(() => programaSel = v ?? ''),
                  );
                }),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: gen,
                        decoration: const InputDecoration(
                            labelText: 'Generación',
                            border: OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: gru,
                        decoration: const InputDecoration(
                            labelText: 'Grupo',
                            border: OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: modalidad.isEmpty ? null : modalidad,
                  decoration: const InputDecoration(
                      labelText: 'Modalidad',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'Mixta', child: Text('Mixta')),
                    DropdownMenuItem(
                        value: 'No Escolarizada',
                        child: Text('No Escolarizada')),
                  ],
                  onChanged: (v) => setSt(() => modalidad = v ?? ''),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: estatus.isEmpty ? null : estatus,
                  decoration: const InputDecoration(
                      labelText: 'Estatus',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'Activo', child: Text('Activo')),
                    DropdownMenuItem(value: 'Baja', child: Text('Baja')),
                  ],
                  onChanged: (v) => setSt(() => estatus = v ?? ''),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child:
                        Text(err!, style: const TextStyle(color: cessumRed)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () {
                if (mat.text.trim().isEmpty) {
                  setSt(() => err = 'La matrícula es obligatoria.');
                  return;
                }
                final c = cor.text.trim().toLowerCase();
                if (c.isNotEmpty && !c.endsWith('@cessum.mx')) {
                  setSt(() => err = 'El correo debe ser @cessum.mx.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    final campos = {
      'matricula': mat.text.trim(),
      'nombre': nom.text.trim(),
      'correo': cor.text.trim().toLowerCase(),
      'programa': programaSel.trim(),
      'generacion': gen.text.trim(),
      'grupo': gru.text.trim(),
      'modalidad': modalidad,
      'estatus': estatus,
    };
    mat.dispose();
    nom.dispose();
    cor.dispose();
    gen.dispose();
    gru.dispose();
    if (ok == true) await _guardar(campos);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Padrón — correcciones'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        onPressed: () => _formulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cessumGold.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Estas correcciones se fusionan con alumnos.json sin '
                        'editar el archivo. Sirven para arreglar modalidad, '
                        'correo, programa, etc., o agregar un alumno faltante. '
                        'Para dos personas con la misma matrícula, agrega a una '
                        'con su matrícula correcta.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    if (_overrides.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aún no hay correcciones.',
                            style: TextStyle(color: cessumMuted(context))),
                      )
                    else
                      ..._overrides.map((e) {
                        final o = e as Map;
                        final detalle = [
                          if ((o['programa'] ?? '').toString().isNotEmpty)
                            o['programa'],
                          if ((o['generacion'] ?? '').toString().isNotEmpty)
                            'Gen ${o['generacion']}',
                          if ((o['grupo'] ?? '').toString().isNotEmpty)
                            'G${o['grupo']}',
                          if ((o['modalidad'] ?? '').toString().isNotEmpty)
                            o['modalidad'],
                          if ((o['estatus'] ?? '').toString().isNotEmpty)
                            o['estatus'],
                          if ((o['correo'] ?? '').toString().isNotEmpty)
                            o['correo'],
                        ].join(' · ');
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              '${o['matricula']}'
                              '${(o['nombre'] ?? '').toString().isNotEmpty ? ' · ${o['nombre']}' : ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: detalle.isEmpty ? null : Text(detalle),
                            onTap: () => _formulario(existente: o),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: cessumRed),
                              onPressed: () =>
                                  _borrar(o['matricula'].toString()),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}
