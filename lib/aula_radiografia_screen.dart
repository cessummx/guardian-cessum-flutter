// =====================================================================
//  RADIOGRAFÍA DEL AULA (3-oct-2026) — paso 1 del generador de diapositivas.
//  Antes de generar o colocar nada, el docente ve semana por semana qué hay
//  en su aula y quién lo puso (él, a mano, o el Guardián), y decide qué
//  semanas entran al flujo: «Respetar» (el generador no la toca) o «Libre».
//  Lee aula_radiografia y guarda con aula_radiografia_marcar. Lo que el
//  docente puso a mano queda protegido por omisión; liberarlo es decisión
//  suya y queda registrada con su correo.
// =====================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

class AulaRadiografiaScreen extends StatefulWidget {
  final String? courseid;
  final String programa, generacion, grupo, materia;
  const AulaRadiografiaScreen({super.key, this.courseid, this.programa = '', this.generacion = '', this.grupo = '', this.materia = ''});
  @override
  State<AulaRadiografiaScreen> createState() => _AulaRadiografiaScreenState();
}

class _AulaRadiografiaScreenState extends State<AulaRadiografiaScreen> {
  Map<String, dynamic>? _r;
  bool _cargando = true;
  String _error = '', _correo = '';
  final Set<int> _ocupadas = {};

  @override
  void initState() { super.initState(); _cargar(); }

  Map<String, String> get _ident => {
    if ((widget.courseid ?? '').isNotEmpty) 'courseid': widget.courseid!,
    'programa': widget.programa, 'generacion': widget.generacion, 'grupo': widget.grupo, 'materia': widget.materia,
  };

  Future<Map<String, dynamic>> _get(Map<String, String> params) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
    final resp = await http.get(uri).timeout(const Duration(seconds: 120));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      _correo = (await SessionStore.validEmail()) ?? '';
      final j = await _get({'accion': 'aula_radiografia', ..._ident, 'actor': _correo});
      if (!mounted) return;
      setState(() { _r = j['ok'] == true ? j : null; _error = j['ok'] == true ? '' : '${j['error'] ?? 'No se pudo leer el aula.'}'; _cargando = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = 'Error de conexión: $e'; });
    }
  }

  Future<void> _marcar(int seccion, String estado) async {
    setState(() => _ocupadas.add(seccion));
    try {
      final j = await _get({'accion': 'aula_radiografia_marcar', ..._ident, 'courseid': '${_r?['courseid'] ?? widget.courseid ?? ''}', 'seccion': '$seccion', 'estado': estado, 'actor': _correo});
      if (!mounted) return;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo guardar.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${j['nota'] ?? 'Guardado.'}')));
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
    } finally { if (mounted) setState(() => _ocupadas.remove(seccion)); }
  }

  Color _colorDe(Map s) {
    if (s['estado'] == 'respetar') return const Color(0xFFB7791F);
    if (s['clasificacion'] == 'vacia') return const Color(0xFF2E7D32);
    return const Color(0xFF1565C0);
  }
  String _etiquetaDe(Map s) {
    if (s['estado'] == 'respetar') return 'SE RESPETA';
    if (s['clasificacion'] == 'vacia') return 'VACÍA · libre';
    return 'DEL GUARDIÁN · libre';
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(title: const Text('Radiografía del aula'), actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))]),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Padding(padding: const EdgeInsets.all(16), child: Text(_error, style: const TextStyle(color: cessumRed)))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text('${r?['curso'] ?? ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  if (r?['asignacion'] is Map)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(
                        '${r!['asignacion']['docente']} · ${r['asignacion']['generacion']} · Grupo ${r['asignacion']['grupo']} · ${r['asignacion']['inicio']} a ${r['asignacion']['termino']}',
                        style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF5F1E8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE7C98A))),
                    child: Text('${r?['nota'] ?? ''}\n\nLo que pusiste a mano queda protegido: el generador no colocará nada en esas semanas. Si quieres que sí lo haga, tócalas y elige «Liberar».',
                        style: const TextStyle(fontSize: 12.5, height: 1.4)),
                  ),
                  const SizedBox(height: 12),
                  ...((r?['secciones'] as List?) ?? const []).map((s) => _tarjetaSemana(s as Map)),
                ]),
    );
  }

  Widget _tarjetaSemana(Map s) {
    final n = int.tryParse('${s['numero']}') ?? 0;
    final detalle = (s['detalle'] as List?) ?? const [];
    final color = _colorDe(s);
    final ocupada = _ocupadas.contains(n);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Container(width: 6, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        title: Row(children: [
          Expanded(child: Text(n == 0 ? 'Bienvenida' : '${s['nombre'] ?? 'Semana $n'}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
          if (s['pasada'] == true) Padding(padding: const EdgeInsets.only(left: 6), child: Text('ya pasó', style: TextStyle(fontSize: 11, color: cessumMuted(context)))),
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('${_etiquetaDe(s)} · ${s['motivo']}'
              '${(s['entregasDeAlumnos'] ?? 0) != 0 ? ' · ${s['entregasDeAlumnos']} entrega(s) de alumnos' : ''}',
              style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (detalle.isEmpty) Text('Sin recursos.', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              ...detalle.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(children: [
                  Icon(d['origen'] == 'guardian' ? Icons.smart_toy_outlined : Icons.person_outline, size: 15, color: d['origen'] == 'guardian' ? const Color(0xFF1565C0) : const Color(0xFFB7791F)),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${d['nombre']}  ·  ${d['tipo']}${d['visible'] == 0 ? '  (oculto)' : ''}', style: const TextStyle(fontSize: 12))),
                ]),
              )),
              if (n > 0) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (s['estado'] != 'respetar')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB7791F), side: const BorderSide(color: Color(0xFFB7791F))),
                      onPressed: ocupada ? null : () => _marcar(n, 'respetar'),
                      icon: const Icon(Icons.lock_outline, size: 15), label: const Text('Respetar: no tocar')),
                  if (s['estado'] == 'respetar')
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
                      onPressed: ocupada ? null : () => _marcar(n, 'libre'),
                      icon: const Icon(Icons.lock_open, size: 15), label: const Text('Liberar para el generador')),
                  if (s['motivo'].toString().startsWith('decisión del docente'))
                    TextButton(onPressed: ocupada ? null : () => _marcar(n, 'quitar'), child: const Text('Volver a lo automático')),
                ]),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}
