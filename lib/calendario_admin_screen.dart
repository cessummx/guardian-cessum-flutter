import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

const _tiposCal = [
  'Inscripciones',
  'Exámenes',
  'Suspensión',
  'Pago',
  'Evento',
  'Trámite',
  'Otro'
];

/// Admin: publica y administra el calendario académico institucional.
class CalendarioAdminScreen extends StatefulWidget {
  const CalendarioAdminScreen({super.key});

  @override
  State<CalendarioAdminScreen> createState() => _CalendarioAdminScreenState();
}

class _CalendarioAdminScreenState extends State<CalendarioAdminScreen> {
  List<Map<String, dynamic>> _eventos = [];
  bool _cargando = true;
  bool _procesando = false;
  String _correoActor = '';

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarActor();
  }

  Future<void> _cargarActor() async {
    // (24-sep) Correo REAL: en «Ver como profesor» el de la vista es el del profesor.
    final c = await SessionStore.realEmail();
    if (mounted && c != null) setState(() => _correoActor = c);
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=calendario_listar'))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _eventos = ((data['eventos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Color _colorTipo(String tipo) {
    switch (tipo) {
      case 'Exámenes':
        return cessumRed;
      case 'Pago':
        return cessumGold;
      case 'Suspensión':
        return Colors.blueGrey;
      case 'Inscripciones':
        return const Color(0xFF1E8E3E);
      default:
        return Colors.blueGrey.shade400;
    }
  }

  Future<void> _nuevo() async {
    String tipo = 'Evento';
    final titulo = TextEditingController();
    final inicio = TextEditingController();
    final fin = TextEditingController();
    final desc = TextEditingController();
    final dirigido = TextEditingController(text: 'Todos');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: const Text('Nuevo evento', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  items: _tiposCal
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setS(() => tipo = v!),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: inicio,
                        readOnly: true,
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx2,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            locale: const Locale('es', 'MX'),
                          );
                          if (d != null) {
                            setS(() => inicio.text =
                                '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}');
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Fecha inicio',
                          hintText: 'Toca para elegir',
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: fin,
                        readOnly: true,
                        onTap: () async {
                          DateTime ini = DateTime.now();
                          if (inicio.text.trim().isNotEmpty) {
                            final p = inicio.text.trim().split('/');
                            if (p.length == 3) {
                              ini = DateTime(int.tryParse(p[0]) ?? ini.year,
                                  int.tryParse(p[1]) ?? ini.month,
                                  int.tryParse(p[2]) ?? ini.day);
                            }
                          }
                          final d = await showDatePicker(
                            context: ctx2,
                            initialDate: ini,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            locale: const Locale('es', 'MX'),
                          );
                          if (d != null) {
                            setS(() => fin.text =
                                '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}');
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Fecha fin',
                          hintText: 'Toca para elegir',
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
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
                const SizedBox(height: 10),
                TextField(
                  controller: dirigido,
                  decoration: const InputDecoration(
                    labelText: 'Dirigido a',
                    hintText: 'Todos, o el nombre de un programa',
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
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'calendario_crear',
                'actor': _correoActor,
                'titulo': titulo.text.trim(),
                'tipo': tipo,
                'fechaInicio': inicio.text.trim(),
                'fechaFin': fin.text.trim(),
                'descripcion': desc.text.trim(),
                'dirigido': dirigido.text.trim().isEmpty
                    ? 'Todos'
                    : dirigido.text.trim(),
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

  Future<void> _eliminar(Map<String, dynamic> ev) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar evento'),
        content: Text('¿Quitar "${ev['titulo']}" del calendario?'),
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
                'accion': 'calendario_eliminar',
                'id': ev['id'],
                'actor': _correoActor,
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
        title: const Text('Calendario académico',
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
        onPressed: _procesando ? null : _nuevo,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo evento'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : Column(
              children: [
                if (_procesando) const LinearProgressIndicator(color: cessumRed),
                Expanded(
                  child: _eventos.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Aún no hay eventos. Usa "Nuevo evento" para armar el calendario.',
                              style: TextStyle(color: cessumMuted(context)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                          itemCount: _eventos.length,
                          itemBuilder: (ctx, i) {
                            final ev = _eventos[i];
                            final tipo = (ev['tipo'] ?? '').toString();
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: Container(
                                  width: 6,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _colorTipo(tipo),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                title: Text('${ev['titulo']}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  [
                                    tipo,
                                    if ((ev['fechaInicio'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      '${ev['fechaInicio']}'
                                          '${(ev['fechaFin'] ?? '').toString().isNotEmpty ? ' a ${ev['fechaFin']}' : ''}',
                                    'Para: ${ev['dirigido']}',
                                  ].join(' · '),
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      size: 20, color: cessumFaint(context)),
                                  onPressed: _procesando
                                      ? null
                                      : () => _eliminar(ev),
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
