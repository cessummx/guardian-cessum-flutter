import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Admin: genera una lista de asistencia (PDF, matriz con columnas de fechas)
/// para cualquier grupo/modalidad. Permite EXCLUIR momentáneamente a alumnos
/// (p.ej. con adaptación de modalidad este periodo) destildándolos: solo
/// afecta este PDF, nada más. Backend: ?accion=lista_asistencia (&excluir=).
class ListaAsistenciaScreen extends StatefulWidget {
  const ListaAsistenciaScreen({super.key});

  @override
  State<ListaAsistenciaScreen> createState() => _ListaAsistenciaScreenState();
}

class _ListaAsistenciaScreenState extends State<ListaAsistenciaScreen> {
  List<Map<String, dynamic>> _catalogo = [];
  bool _cargandoCat = true;
  bool _cargandoAlumnos = false;
  bool _generando = false;

  String? _programa;
  String? _generacion;
  String? _grupo;
  final _cMateria = TextEditingController();
  final _cInicio = TextEditingController();
  final _cTermino = TextEditingController();
  final _cSesiones = TextEditingController(text: '10');

  List<Map<String, dynamic>> _alumnos = [];
  final Set<String> _incluidos = {};

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
    } catch (_) {
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
    final g = _generacionesDe.firstWhere((e) => e['generacion'] == _generacion,
        orElse: () => {});
    return ((g['grupos'] as List?) ?? []).map((e) => e.toString()).toList();
  }

  Future<void> _cargarAlumnos() async {
    if (_programa == null || _generacion == null || _grupo == null) return;
    setState(() {
      _cargandoAlumnos = true;
      _alumnos = [];
      _incluidos.clear();
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'alumnos',
        'programa': _programa!,
        'generacion': _generacion!,
        'grupo': _grupo!,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      final lista = ((data['alumnos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      lista.sort((a, b) => (a['nombre'] ?? '')
          .toString()
          .compareTo((b['nombre'] ?? '').toString()));
      setState(() {
        _alumnos = lista;
        for (final a in lista) {
          _incluidos.add((a['matricula'] ?? '').toString().trim());
        }
        _cargandoAlumnos = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoAlumnos = false);
    }
  }

  Future<void> _generar() async {
    if (_programa == null || _generacion == null || _grupo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Elige programa, generación y grupo.')));
      return;
    }
    final excluir = _alumnos
        .map((a) => (a['matricula'] ?? '').toString().trim())
        .where((m) => m.isNotEmpty && !_incluidos.contains(m))
        .join(',');
    setState(() => _generando = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'lista_asistencia',
        'programa': _programa!,
        'generacion': _generacion!,
        'grupo': _grupo!,
        'materia': _cMateria.text.trim(),
        'inicio': _cInicio.text.trim(),
        'termino': _cTermino.text.trim(),
        'sesiones': _cSesiones.text.trim(),
        'excluir': excluir,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true && (data['pdfUrl'] ?? '').toString().isNotEmpty) {
        final u = Uri.tryParse(data['pdfUrl'].toString());
        if (u != null) {
          await launchUrl(u, mode: LaunchMode.externalApplication);
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Lista generada: ${data['alumnos']} alumnos, ${data['columnas']} columnas.'),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo: ${data['error'] ?? 'error'}')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión. Intenta de nuevo.')));
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  int get _numIncluidos => _incluidos.length;

  /// (24-sep) Las fechas se eligen en un calendario: escritas a mano, un error
  /// de dedo («2026-7-2O») rompía la lista sin decir por qué.
  Future<void> _elegirFecha(TextEditingController c, {TextEditingController? desde}) async {
    DateTime base = DateTime.now();
    final previa = DateTime.tryParse((desde ?? c).text.trim());
    if (previa != null) base = previa;
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('es', 'MX'),
    );
    if (d == null) return;
    setState(() => c.text =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Listas de asistencia'),
      ),
      body: _cargandoCat
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Genera una lista de asistencia en PDF para cualquier grupo. '
                  'Si pones fechas de inicio y término, se crea una columna por '
                  'día; si no, columnas en blanco para palomear.',
                  style: TextStyle(fontSize: 13, color: cessumMuted(context)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _programa,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Programa', border: OutlineInputBorder()),
                  items: _programas
                      .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _programa = v;
                    _generacion = null;
                    _grupo = null;
                    _alumnos = [];
                    _incluidos.clear();
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _generacion,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Generación', border: OutlineInputBorder()),
                  items: _generacionesDe
                      .map((g) => DropdownMenuItem(
                          value: (g['generacion'] ?? '').toString(),
                          child: Text((g['generacion'] ?? '').toString())))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _generacion = v;
                    _grupo = null;
                    _alumnos = [];
                    _incluidos.clear();
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _grupo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Grupo', border: OutlineInputBorder()),
                  items: _gruposDe
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _grupo = v);
                    _cargarAlumnos();
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cMateria,
                  decoration: const InputDecoration(
                      labelText: 'Asignatura (opcional)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                if (_cargandoAlumnos)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                        child: CircularProgressIndicator(color: cessumRed)),
                  )
                else if (_alumnos.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Alumnos ($_numIncluidos de ${_alumnos.length})',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              _incluidos.clear();
                              for (final a in _alumnos) {
                                _incluidos.add(
                                    (a['matricula'] ?? '').toString().trim());
                              }
                            }),
                            child: const Text('Todos'),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => _incluidos.clear()),
                            child: const Text('Ninguno'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    'Destilda a quien NO debe salir en esta lista (p. ej. con '
                    'adaptación de modalidad este periodo). Solo afecta el PDF.',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        for (final a in _alumnos)
                          _filaAlumno(
                            (a['matricula'] ?? '').toString().trim(),
                            (a['nombre'] ?? '').toString(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Columnas de fechas (opcional):',
                    style:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cInicio,
                        readOnly: true,
                        onTap: () => _elegirFecha(_cInicio),
                        decoration: InputDecoration(
                            labelText: 'Inicio',
                            hintText: 'Toca para elegir',
                            suffixIcon: _cInicio.text.isEmpty
                                ? const Icon(Icons.calendar_today, size: 18)
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setState(() => _cInicio.clear())),
                            border: const OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _cTermino,
                        readOnly: true,
                        onTap: () => _elegirFecha(_cTermino, desde: _cInicio.text.isEmpty ? null : _cInicio),
                        decoration: InputDecoration(
                            labelText: 'Término',
                            hintText: 'Toca para elegir',
                            suffixIcon: _cTermino.text.isEmpty
                                ? const Icon(Icons.calendar_today, size: 18)
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setState(() => _cTermino.clear())),
                            border: const OutlineInputBorder(),
                            isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _cSesiones,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'O nº de columnas en blanco (si no hay fechas)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: cessumRed),
                    onPressed: _generando ? null : _generar,
                    icon: _generando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.picture_as_pdf),
                    label: Text(_generando
                        ? 'Generando…'
                        : 'Generar lista de asistencia PDF'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _filaAlumno(String matricula, String nombre) {
    final incluido = _incluidos.contains(matricula);
    return CheckboxListTile(
      value: incluido,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: cessumRed,
      title: Text(nombre,
          style: TextStyle(
            fontSize: 13.5,
            color: incluido ? cessumInk(context) : cessumFaint(context),
            decoration: incluido ? null : TextDecoration.lineThrough,
          )),
      subtitle: Text('Mat. $matricula',
          style: TextStyle(fontSize: 11, color: cessumFaint(context))),
      onChanged: (v) => setState(() {
        if (v == true) {
          _incluidos.add(matricula);
        } else {
          _incluidos.remove(matricula);
        }
      }),
    );
  }
}
