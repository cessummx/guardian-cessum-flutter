import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// El docente publica avisos (recados) a sus grupos y ve/borra los suyos.
class AvisosDocenteScreen extends StatefulWidget {
  const AvisosDocenteScreen({super.key});

  @override
  State<AvisosDocenteScreen> createState() => _AvisosDocenteScreenState();
}

class _AvisosDocenteScreenState extends State<AvisosDocenteScreen> {
  String _correo = '';
  List<Map<String, dynamic>> _grupos = [];
  List<Map<String, dynamic>> _avisos = [];
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
      final a = await http
          .get(Uri.parse('$guardianUrl?accion=avisos_docente_listar'
              '&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final ad = jsonDecode(a.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _grupos = ((gd['grupos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _avisos = ((ad['avisos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevoAviso() async {
    if (_grupos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No tienes grupos asignados para avisar.'),
      ));
      return;
    }
    Map<String, dynamic>? grupoSel = _grupos.first;
    final mensaje = TextEditingController();
    // (24-sep) Mejorar redacción con IA (el docente ve el resultado y puede deshacer).
    var mejorando = false;
    String? anterior;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: const Text('Nuevo aviso', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: grupoSel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Grupo / materia',
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
                const SizedBox(height: 12),
                TextField(
                  controller: mensaje,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Mensaje',
                    hintText: 'Ej. La clase del jueves cambia al aula 3.',
                    border: OutlineInputBorder(),
                  ),
                ),
                Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
                  if (anterior != null)
                    TextButton(
                      onPressed: mejorando
                          ? null
                          : () => setS(() {
                                mensaje.text = anterior!;
                                anterior = null;
                              }),
                      child: const Text('Deshacer'),
                    ),
                  TextButton.icon(
                    onPressed: mejorando
                        ? null
                        : () async {
                            if (mensaje.text.trim().length < 5) return;
                            setS(() => mejorando = true);
                            try {
                              final r = await http
                                  .post(Uri.parse(guardianUrl),
                                      headers: {'Content-Type': 'text/plain;charset=utf-8'},
                                      body: jsonEncode({
                                        'accion': 'texto_ia_mejorar',
                                        'texto': mensaje.text.trim(),
                                        'proposito': 'aviso de un docente a su grupo',
                                        'correo': _correo,
                                      }))
                                  .timeout(const Duration(seconds: 60));
                              final d = jsonDecode(r.body) as Map<String, dynamic>;
                              final nuevo = '${d['texto'] ?? ''}'.trim();
                              if (d['ok'] == true && nuevo.isNotEmpty) {
                                anterior = mensaje.text;
                                mensaje.text = nuevo;
                              } else if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('${d['error'] ?? 'No se pudo mejorar la redacción.'}')));
                              }
                            } catch (_) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                    content: Text('No se pudo conectar para mejorar la redacción.')));
                              }
                            }
                            setS(() => mejorando = false);
                          },
                    icon: mejorando
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(mejorando ? 'Mejorando…' : 'Mejorar redacción con IA'),
                  ),
                ]),
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
                if (mensaje.text.trim().isEmpty) return;
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
                'accion': 'aviso_docente_crear',
                'correo': _correo,
                'programa': grupoSel!['programa'],
                'generacion': grupoSel!['generacion'],
                'grupo': grupoSel!['grupo'],
                'clave': grupoSel!['clave'],
                'materia': grupoSel!['materia'],
                'mensaje': mensaje.text.trim(),
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Aviso publicado a tu grupo.'),
        ));
      }
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

  Future<void> _eliminar(Map<String, dynamic> aviso) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar aviso'),
        content: const Text('¿Quitar este aviso? Tus alumnos dejarán de verlo.'),
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
                'accion': 'aviso_docente_eliminar',
                'id': aviso['id'],
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
        title: const Text('Avisos a mi grupo',
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
        onPressed: _procesando ? null : _nuevoAviso,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo aviso'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : Column(
              children: [
                if (_procesando) const LinearProgressIndicator(color: cessumRed),
                Expanded(
                  child: _avisos.isEmpty
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Aún no has publicado avisos. Usa "Nuevo aviso" para mandar un recado a un grupo tuyo.',
                              style: TextStyle(color: cessumMuted(context)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          color: cessumRed,
                          onRefresh: _cargar,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(16, 12, 16, 90),
                            itemCount: _avisos.length,
                            itemBuilder: (ctx, i) {
                              final a = _avisos[i];
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
                                            child: Text(
                                              '${a['materia']} · ${a['generacion']} G${a['grupo']}',
                                            style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w800,
                                                color: cessumRed),
                                          ),
                                        ),
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: Icon(Icons.delete_outline,
                                              size: 20, color: cessumFaint(context)),
                                          onPressed: _procesando
                                              ? null
                                              : () => _eliminar(a),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('${a['mensaje']}',
                                        style: const TextStyle(
                                            fontSize: 13, height: 1.4)),
                                    const SizedBox(height: 6),
                                    Text('${a['fecha']}',
                                        style: TextStyle(
                                            fontSize: 11, color: cessumFaint(context))),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        ),
                ),
              ],
            ),
    );
  }
}
