import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// El docente ve, de sus materias, los alumnos en riesgo (rojo/amarillo) y
/// registra seguimiento (contacté, justificó, en recuperación).
class RiesgoDocenteScreen extends StatefulWidget {
  final String correo;
  const RiesgoDocenteScreen({super.key, required this.correo});

  @override
  State<RiesgoDocenteScreen> createState() => _RiesgoDocenteScreenState();
}

class _RiesgoDocenteScreenState extends State<RiesgoDocenteScreen> {
  List<Map<String, dynamic>> _alumnos = [];
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  final TextEditingController _busqueda = TextEditingController();

  List<Map<String, dynamic>> get _visibles {
    final q = _busqueda.text.trim().toLowerCase();
    if (q.isEmpty) return _alumnos;
    return _alumnos.where((a) {
      return (a['nombre'] ?? '').toString().toLowerCase().contains(q) ||
          (a['matricula'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Copia la lista de alumnos en riesgo (TSV) para pegar en Excel.
  void _copiarExcel() {
    if (_alumnos.isEmpty) return;
    final b = StringBuffer()
      ..writeln('Nivel\tMatrícula\tNombre\tPrograma\tGeneración\t'
          'Modalidad\tDías sin conexión\tÚltima conexión\tReprobadas');
    for (final a in _alumnos) {
      b.writeln([
        a['nivel'] ?? '',
        a['matricula'] ?? '',
        a['nombre'] ?? '',
        a['programa'] ?? '',
        a['generacion'] ?? '',
        a['modalidad'] ?? '',
        a['diasSinConexion'] ?? '',
        a['ultimaConexion'] ?? '',
        a['reprobadas'] ?? 0,
      ].join('\t'));
    }
    Helpers.copiarAlPortapapeles(
        context, b.toString(), 'Mis alumnos en riesgo (${_alumnos.length})');
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=riesgo_docente&correo=${Uri.encodeComponent(widget.correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _alumnos = (data['alumnos'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la lista.';
      });
    }
  }

  Color _color(String nivel) =>
      nivel == 'Rojo' ? const Color(0xFFB11D29) : const Color(0xFFB8842C);

  Future<void> _seguimiento(Map<String, dynamic> a) async {
    String accion = 'Contacté al alumno';
    final nota = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text('Seguimiento · ${a['nombre']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: accion,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Acción',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'Contacté al alumno',
                        child: Text('Contacté al alumno')),
                    DropdownMenuItem(
                        value: 'Justificó su ausencia',
                        child: Text('Justificó su ausencia')),
                    DropdownMenuItem(
                        value: 'En recuperación',
                        child: Text('En recuperación')),
                    DropdownMenuItem(
                        value: 'Sin respuesta', child: Text('Sin respuesta')),
                    DropdownMenuItem(value: 'Otro', child: Text('Otro')),
                  ],
                  onChanged: (v) => setS(() => accion = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nota,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    border: OutlineInputBorder(),
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
              onPressed: () => Navigator.pop(ctx2, true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'riesgo_seguimiento',
                'matricula': a['matricula'],
                'alumno': a['nombre'],
                'correoDocente': widget.correo,
                'tipo': accion,
                'nota': nota.text.trim(),
              }))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Seguimiento registrado.'),
        ));
      }
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo registrar: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis alumnos en riesgo',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _alumnos.isEmpty ? null : _copiarExcel,
              icon: const Icon(Icons.copy_all),
              tooltip: 'Copiar para Excel'),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      body: Column(
        children: [
          if (_guardando) const LinearProgressIndicator(color: cessumRed),
          if (!_cargando && _error == null && _alumnos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _busqueda,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o matrícula',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: _busqueda.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _busqueda.clear()),
                        ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 8),
                            TextButton(
                                onPressed: _cargar,
                                child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : _alumnos.isEmpty
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                '¡Buenas noticias! Ninguno de tus alumnos está en riesgo según el último cálculo (inactividad en Moodle y reprobación).',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: cessumMuted(context), height: 1.5),
                              ),
                            ),
                          )
                        : _visibles.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('Sin coincidencias.',
                                      style:
                                          TextStyle(color: cessumMuted(context))),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _visibles.length,
                                itemBuilder: (ctx, i) {
                                  final a = _visibles[i];
                                  final nivel = (a['nivel'] ?? '') as String;
                              final dias =
                                  (a['diasSinConexion'] ?? '').toString();
                              final rep = a['reprobadas'] ?? 0;
                              final seg = a['ultimoSeguimiento']
                                  as Map<String, dynamic>?;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      14, 12, 14, 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                              radius: 7,
                                              backgroundColor:
                                                  _color(nivel)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${a['nombre']} (${a['matricula']})',
                                              style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight:
                                                      FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${a['programa']} · ${a['generacion']}\n'
                                        '${dias == 'Nunca' ? 'Nunca se ha conectado' : '$dias días sin conectarse'}'
                                        '${rep > 0 ? ' · $rep reprobada(s)' : ''}',
                                        style: const TextStyle(
                                            fontSize: 12, height: 1.4),
                                      ),
                                      if (seg != null) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: cessumGold.withValues(alpha: 0.08), // (24-sep) modo oscuro
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'Último seguimiento: ${seg['accion']} (${seg['fecha']})'
                                            '${(seg['nota'] ?? '').toString().isNotEmpty ? '\n${seg['nota']}' : ''}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                height: 1.35,
                                                color: cessumInk(context)),
                                          ),
                                        ),
                                      ],
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: _guardando
                                              ? null
                                              : () => _seguimiento(a),
                                          icon: const Icon(Icons.edit_note,
                                              size: 18, color: cessumRed),
                                          label: const Text(
                                              'Registrar seguimiento',
                                              style: TextStyle(
                                                  color: cessumRed,
                                                  fontSize: 12.5)),
                                        ),
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
