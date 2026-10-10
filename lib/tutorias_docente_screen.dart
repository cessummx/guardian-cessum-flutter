import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// El docente registra y da seguimiento a las asesorías/tutorías que brinda.
/// Convierte el acompañamiento en un expediente (Abierta / En seguimiento /
/// Cerrada), útil como evidencia de calidad.
class TutoriasDocenteScreen extends StatefulWidget {
  const TutoriasDocenteScreen({super.key});

  @override
  State<TutoriasDocenteScreen> createState() => _TutoriasDocenteScreenState();
}

class _TutoriasDocenteScreenState extends State<TutoriasDocenteScreen> {
  String _correo = '';
  List<Map<String, dynamic>> _tutorias = [];
  String _filtro = 'Todas';
  bool _cargando = true;
  bool _procesando = false;

  static const _estatuses = ['Abierta', 'En seguimiento', 'Cerrada'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      _correo = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse('$guardianUrl?accion=tutorias_docente'
          '&correo=${Uri.encodeComponent(_correo)}'
          '${_filtro != 'Todas' ? '&estatus=${Uri.encodeComponent(_filtro)}' : ''}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _tutorias = ((data['tutorias'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Color _color(String est) {
    switch (est) {
      case 'Cerrada':
        return const Color(0xFF1E8E3E);
      case 'En seguimiento':
        return cessumGold;
      default:
        return cessumRed;
    }
  }

  Future<void> _editar([Map<String, dynamic>? t]) async {
    final esNueva = t == null;
    final matricula =
        TextEditingController(text: (t?['matricula'] ?? '').toString());
    final nombre = TextEditingController(text: (t?['nombre'] ?? '').toString());
    final grupo = TextEditingController(text: (t?['grupo'] ?? '').toString());
    final fecha =
        TextEditingController(text: (t?['fechaAsesoria'] ?? '').toString());
    final motivo = TextEditingController(text: (t?['motivo'] ?? '').toString());
    final acuerdo = TextEditingController(text: (t?['acuerdo'] ?? '').toString());
    final notas = TextEditingController(text: (t?['notas'] ?? '').toString());
    String estatus = (t?['estatus'] ?? 'Abierta').toString();
    if (!_estatuses.contains(estatus)) estatus = 'Abierta';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text(esNueva ? 'Nueva asesoría' : 'Editar asesoría',
              style: const TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: matricula,
                        enabled: esNueva,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Matrícula *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: grupo,
                        enabled: esNueva,
                        decoration: const InputDecoration(
                          labelText: 'Grupo',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nombre,
                  enabled: esNueva,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del alumno',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fecha,
                  decoration: const InputDecoration(
                    labelText: 'Fecha de la asesoría',
                    hintText: 'dd/mm/aaaa',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: motivo,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Motivo *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: acuerdo,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Acuerdo / compromiso',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: estatus,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Estatus',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _estatuses
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setS(() => estatus = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notas,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notas de seguimiento',
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
                if (matricula.text.trim().isEmpty ||
                    motivo.text.trim().isEmpty) return;
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
        'accion': 'tutoria_registrar',
        'correo': _correo,
        'matricula': matricula.text.trim(),
        'nombre': nombre.text.trim(),
        'grupo': grupo.text.trim(),
        'fechaAsesoria': fecha.text.trim(),
        'motivo': motivo.text.trim(),
        'acuerdo': acuerdo.text.trim(),
        'estatus': estatus,
        'notas': notas.text.trim(),
      };
      if (!esNueva) body['id'] = t['id'];
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(body))
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

  Future<void> _eliminar(Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar asesoría'),
        content: Text('¿Quitar la asesoría de ${t['nombre']} (${t['matricula']})?'),
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
                'accion': 'tutoria_eliminar',
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
    final filtros = ['Todas', ..._estatuses];
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tutorías y asesorías',
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
        onPressed: _procesando ? null : () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva asesoría'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : Column(
              children: [
                if (_procesando) const LinearProgressIndicator(color: cessumRed),
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: filtros.map((f) {
                      final activo = _filtro == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f, style: const TextStyle(fontSize: 12)),
                          selected: activo,
                          selectedColor: cessumRed.withValues(alpha: 0.15),
                          labelStyle: TextStyle(
                            color: activo ? cessumRed : cessumInk(context),
                            fontWeight:
                                activo ? FontWeight.w700 : FontWeight.w400,
                          ),
                          onSelected: (_) {
                            setState(() => _filtro = f);
                            _cargar();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Expanded(
                  child: _tutorias.isEmpty
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Sin asesorías en este filtro. Usa "Nueva asesoría" para registrar un acompañamiento.',
                              style: TextStyle(color: cessumMuted(context)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                          itemCount: _tutorias.length,
                          itemBuilder: (ctx, i) {
                            final t = _tutorias[i];
                            final est = (t['estatus'] ?? 'Abierta').toString();
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
                                            '${t['nombre']} (${t['matricula']})',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _color(est)
                                                .withValues(alpha: 0.14),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(est,
                                              style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: _color(est))),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('Motivo: ${t['motivo']}',
                                        style: const TextStyle(
                                            fontSize: 12.5, height: 1.4)),
                                    if ((t['acuerdo'] ?? '')
                                        .toString()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text('Acuerdo: ${t['acuerdo']}',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              height: 1.4,
                                              color: cessumInk(context))),
                                    ],
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        if ((t['fechaAsesoria'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text('${t['fechaAsesoria']}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: cessumFaint(context))),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: _procesando
                                              ? null
                                              : () => _editar(t),
                                          child: const Text('Seguimiento',
                                              style: TextStyle(fontSize: 12)),
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
