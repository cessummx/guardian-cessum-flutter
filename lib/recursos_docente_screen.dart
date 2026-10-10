import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'generador_diapositivas_screen.dart';

const _tipos = ['Lectura', 'Video', 'Presentación', 'Enlace', 'Otro'];

/// El docente comparte material (enlaces) a sus grupos.
class RecursosDocenteScreen extends StatefulWidget {
  const RecursosDocenteScreen({super.key});

  @override
  State<RecursosDocenteScreen> createState() => _RecursosDocenteScreenState();
}

class _RecursosDocenteScreenState extends State<RecursosDocenteScreen> {
  String _correo = '';
  List<Map<String, dynamic>> _grupos = [];
  List<Map<String, dynamic>> _recursos = [];
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
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=recursos_docente'
              '&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final rd = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _grupos = ((gd['grupos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _recursos = ((rd['recursos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  IconData _iconoTipo(String tipo) {
    switch (tipo) {
      case 'Lectura':
        return Icons.menu_book;
      case 'Video':
        return Icons.play_circle;
      case 'Presentación':
        return Icons.slideshow;
      default:
        return Icons.link;
    }
  }

  Future<void> _nuevo() async {
    if (_grupos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No tienes grupos asignados.'),
      ));
      return;
    }
    Map<String, dynamic>? grupoSel = _grupos.first;
    String tipo = 'Enlace';
    final titulo = TextEditingController();
    final url = TextEditingController();
    final desc = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: const Text('Compartir material', style: TextStyle(fontSize: 16)),
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
                DropdownButtonFormField<String>(
                  value: tipo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _tipos
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setS(() => tipo = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: 'Enlace (URL) *',
                    hintText: 'https://...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: desc,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
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
                if (titulo.text.trim().isEmpty || url.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(ctx2, true);
              },
              child: const Text('Compartir'),
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
                'accion': 'recurso_crear',
                'correo': _correo,
                'programa': grupoSel!['programa'],
                'generacion': grupoSel!['generacion'],
                'grupo': grupoSel!['grupo'],
                'clave': grupoSel!['clave'],
                'materia': grupoSel!['materia'],
                'titulo': titulo.text.trim(),
                'tipo': tipo,
                'url': url.text.trim(),
                'descripcion': desc.text.trim(),
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

  Future<void> _eliminar(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar material'),
        content: Text('¿Quitar "${r['titulo']}"?'),
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
                'accion': 'recurso_eliminar',
                'id': r['id'],
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
        title: const Text('Material de mis grupos',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          // (sep-2026) Generador de diapositivas con IA: el docente sube su
          // material y recibe un PowerPoint con la identidad de CESSUM y
          // preguntas de interacción compleja al margen.
          TextButton.icon(
            onPressed: _cargando
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GeneradorDiapositivasScreen())),
            icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            label: const Text('Crear presentación',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _procesando ? null : _nuevo,
        icon: const Icon(Icons.add),
        label: const Text('Compartir material'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : Column(
              children: [
                if (_procesando) const LinearProgressIndicator(color: cessumRed),
                Expanded(
                  child: _recursos.isEmpty
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Aún no compartes material. Usa "Compartir material".',
                              style: TextStyle(color: cessumMuted(context)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                          itemCount: _recursos.length,
                          itemBuilder: (ctx, i) {
                            final r = _recursos[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: Icon(_iconoTipo((r['tipo'] ?? '').toString()),
                                    color: cessumRed),
                                title: Text('${r['titulo']}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  '${r['materia']} · G${r['grupo']} · ${r['tipo']}',
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.open_in_new,
                                          size: 20, color: cessumGold),
                                      onPressed: () => Helpers.abrirUrlExterna(
                                          (r['url'] ?? '').toString(), context),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline,
                                          size: 20, color: cessumFaint(context)),
                                      onPressed: _procesando
                                          ? null
                                          : () => _eliminar(r),
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
