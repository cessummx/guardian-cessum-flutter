import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'avance_temas_screen.dart';
import 'auth/session_store.dart';

/// El docente registra el avance de sus materias, sesión por sesión, y ve
/// su progreso contra la meta de sesiones (si administración la fijó).
class AvanceDocenteScreen extends StatefulWidget {
  const AvanceDocenteScreen({super.key});

  @override
  State<AvanceDocenteScreen> createState() => _AvanceDocenteScreenState();
}

class _AvanceDocenteScreenState extends State<AvanceDocenteScreen> {
  String _correo = '';
  List<Map<String, dynamic>> _grupos = [];
  Map<String, dynamic>? _grupoSel;
  Map<String, dynamic>? _avance;
  bool _cargando = true;
  bool _cargandoAvance = false;
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
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=mis_grupos'
              '&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _grupos = ((data['grupos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarAvance() async {
    final g = _grupoSel;
    if (g == null) return;
    setState(() => _cargandoAvance = true);
    try {
      final uri = Uri.parse('$guardianUrl?accion=avance_grupo'
          '&programa=${Uri.encodeComponent((g['programa'] ?? '').toString())}'
          '&generacion=${Uri.encodeComponent((g['generacion'] ?? '').toString())}'
          '&grupo=${Uri.encodeComponent((g['grupo'] ?? '').toString())}'
          '&clave=${Uri.encodeComponent((g['clave'] ?? '').toString())}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _avance = data;
        _cargandoAvance = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargandoAvance = false);
    }
  }

  Future<void> _registrar() async {
    final g = _grupoSel;
    if (g == null) return;
    final numSesion = TextEditingController();
    final fechaSesion = TextEditingController();
    final tema = TextEditingController();
    final obs = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar sesión', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: numSesion,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'N.° sesión',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: fechaSesion,
                      decoration: const InputDecoration(
                        labelText: 'Fecha',
                        hintText: 'dd/mm',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tema,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Tema cubierto *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: obs,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observaciones',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () {
              if (tema.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Registrar'),
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
                'accion': 'avance_registrar',
                'correo': _correo,
                'programa': g['programa'],
                'generacion': g['generacion'],
                'grupo': g['grupo'],
                'clave': g['clave'],
                'materia': g['materia'],
                'numSesion': numSesion.text.trim(),
                'fechaSesion': fechaSesion.text.trim(),
                'tema': tema.text.trim(),
                'observaciones': obs.text.trim(),
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _cargarAvance();
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

  Future<void> _eliminar(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar sesión'),
        content: Text('¿Quitar la sesión "${s['tema']}"?'),
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
                'accion': 'avance_eliminar',
                'id': s['id'],
                'correo': _correo,
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _cargarAvance();
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
        title: const Text('Mi avance programático',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          if (_grupoSel != null)
            IconButton(
              tooltip: 'Temas de la carta',
              icon: const Icon(Icons.checklist),
              onPressed: () {
                final g = _grupoSel!;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AvanceTemasScreen(
                      programa: (g['programa'] ?? '').toString(),
                      generacion: (g['generacion'] ?? '').toString(),
                      grupo: (g['grupo'] ?? '').toString(),
                      clave: (g['clave'] ?? '').toString(),
                      materia: (g['materia'] ?? '').toString(),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      floatingActionButton: _grupoSel == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              onPressed: _procesando ? null : _registrar,
              icon: const Icon(Icons.add),
              label: const Text('Registrar sesión'),
            ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _grupos.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No tienes grupos asignados.',
                        style: TextStyle(color: cessumMuted(context))),
                  ),
                )
              : Column(
                  children: [
                    if (_procesando)
                      const LinearProgressIndicator(color: cessumRed),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<Map<String, dynamic>>(
                        value: _grupoSel,
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
                        onChanged: (v) {
                          setState(() {
                            _grupoSel = v;
                            _avance = null;
                          });
                          _cargarAvance();
                        },
                      ),
                    ),
                    Expanded(
                      child: _grupoSel == null
                          ? Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Elige una materia para ver y registrar tu avance.',
                                  style: TextStyle(color: cessumMuted(context)),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : _cargandoAvance
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: cessumRed))
                              : _vistaAvance(),
                    ),
                  ],
                ),
    );
  }

  Widget _vistaAvance() {
    final av = _avance ?? {};
    final sesiones = (av['sesiones'] as List?) ?? [];
    final meta = (av['meta'] ?? 0) as int;
    final registradas = (av['registradas'] ?? 0) as int;
    final pct = (av['porcentaje'] ?? 0) as int;

    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargarAvance,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                  const Text('Avance',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text(
                    meta > 0
                        ? '$registradas de $meta sesiones'
                        : '$registradas sesiones registradas',
                    style: TextStyle(
                        fontSize: 12.5, color: cessumMuted(context)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (meta > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 10,
                    backgroundColor: cessumMuted(context).withValues(alpha: 0.18),
                    color: pct >= 80
                        ? const Color(0xFF1E8E3E)
                        : (pct >= 50 ? cessumGold : cessumRed),
                  ),
                ),
                const SizedBox(height: 6),
                Text('$pct% del programa',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ] else
                Text(
                  'Administración aún no fija la meta de sesiones de esta materia; se muestra el conteo de sesiones registradas.',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (sesiones.isEmpty)
          Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('Aún no registras sesiones de esta materia.',
                  style: TextStyle(color: cessumMuted(context))),
            ),
          )
        else
          ...sesiones.map((raw) {
            final s = Map<String, dynamic>.from(raw as Map);
            final num = (s['numSesion'] ?? '').toString();
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: cessumRed.withValues(alpha: 0.12),
                  child: Text(num.isEmpty ? '·' : num,
                      style: const TextStyle(
                          color: cessumRed,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ),
                title: Text('${s['tema']}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  [
                    if ((s['fechaSesion'] ?? '').toString().isNotEmpty)
                      '${s['fechaSesion']}',
                    if ((s['observaciones'] ?? '').toString().isNotEmpty)
                      '${s['observaciones']}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: cessumFaint(context)),
                  onPressed: _procesando ? null : () => _eliminar(s),
                ),
              ),
            );
          }),
      ],
    ),
    );
  }
}
