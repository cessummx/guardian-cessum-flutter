import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Tablero rápido: números clave, búsqueda de alumno, directorio de docentes,
/// resumen por programa y cumpleaños del día.
class TableroRapidoScreen extends StatefulWidget {
  const TableroRapidoScreen({super.key});

  @override
  State<TableroRapidoScreen> createState() => _TableroRapidoScreenState();
}

class _TableroRapidoScreenState extends State<TableroRapidoScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _programas = [];
  List<Map<String, dynamic>> _docentes = [];
  List<Map<String, dynamic>> _cumple = [];
  List<Map<String, dynamic>> _busqueda = [];
  final _q = TextEditingController();
  bool _cargando = true;
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(String accion) async {
    final resp = await http
        .get(Uri.parse('$guardianUrl?accion=$accion'))
        .timeout(const Duration(seconds: 45));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final s = await _get('stats_rapidas');
      final p = await _get('resumen_programa');
      final d = await _get('directorio_docentes');
      final c = await _get('cumpleanos_hoy');
      if (!mounted) return;
      setState(() {
        _stats = s;
        _programas = ((p['programas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _docentes = ((d['docentes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cumple = ((c['festejados'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _buscar(String q) async {
    if (q.trim().length < 2) {
      setState(() => _busqueda = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final resp = await http
          .get(Uri.parse(
              '$guardianUrl?accion=buscar_alumno&q=${Uri.encodeComponent(q.trim())}'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _busqueda = ((data['resultados'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _buscando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tablero rápido',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _numeros(),
                const SizedBox(height: 18),
                _buscador(),
                const SizedBox(height: 18),
                if (_cumple.isNotEmpty) ...[
                  _cumpleanos(),
                  const SizedBox(height: 18),
                ],
                _seccionPrograma(),
                const SizedBox(height: 18),
                _seccionDocentes(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _numeros() {
    final s = _stats ?? {};
    final items = [
      ['Alumnos activos', '${s['alumnosActivos'] ?? 0}', cessumRed],
      ['Docentes activos', '${s['docentesActivos'] ?? 0}', cessumGold],
      ['Programas', '${s['programas'] ?? 0}', const Color(0xFF1E8E3E)],
      ['Generaciones', '${s['generaciones'] ?? 0}', Colors.blueGrey],
      ['Bajas', '${s['bajas'] ?? 0}', cessumMuted(context)],
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((it) {
        final color = it[2] as Color;
        return Container(
          width: 105,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              Text(it[1] as String,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: color)),
              const SizedBox(height: 2),
              Text(it[0] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11, color: cessumMuted(context))),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buscador() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Buscar alumno',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
        const SizedBox(height: 8),
        TextField(
          controller: _q,
          onChanged: _buscar,
          decoration: InputDecoration(
            hintText: 'Nombre o matrícula...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _buscando
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
            border: const OutlineInputBorder(),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).cardColor,
          ),
        ),
        ..._busqueda.map((a) => Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                dense: true,
                leading: Icon(
                    a['baja'] == true ? Icons.person_off : Icons.person,
                    color: a['baja'] == true ? cessumFaint(context) : cessumRed),
                title: Text('${a['nombre']}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${a['matricula']} · ${a['programa']} · ${a['generacion']}'
                  '${a['baja'] == true ? ' · BAJA' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            )),
      ],
    );
  }

  Widget _cumpleanos() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cake, color: Color(0xFF8A6118), size: 20),
              SizedBox(width: 8),
              Text('Cumpleaños de hoy',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8A6118))),
            ],
          ),
          const SizedBox(height: 8),
          ..._cumple.map((c) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('🎂 ${c['nombre']} · ${c['programa']}',
                    style: const TextStyle(fontSize: 12.5)),
              )),
        ],
      ),
    );
  }

  Widget _seccionPrograma() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Alumnos por programa',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
        const SizedBox(height: 8),
        ..._programas.map((p) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text('${p['programa']}',
                    style: const TextStyle(fontSize: 12.5)),
                trailing: Text('${p['alumnos']}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cessumRed)),
              ),
            )),
      ],
    );
  }

  Widget _seccionDocentes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Directorio de docentes (${_docentes.length})',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
        const SizedBox(height: 8),
        ..._docentes.map((d) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.school, color: cessumGold, size: 20),
                title: Text('${d['docente']}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${d['correo']}\n${(d['materias'] as List?)?.join(', ') ?? ''}',
                  style: const TextStyle(fontSize: 10.5, height: 1.3),
                ),
                isThreeLine: true,
              ),
            )),
      ],
    );
  }
}
