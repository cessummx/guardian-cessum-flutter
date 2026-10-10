import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Importador de calificaciones desde Excel (pegado). El docente elige el
/// contexto (programa, materia, grupo...), pega las filas copiadas de Excel,
/// previsualiza con validación y, solo entonces, confirma la escritura.
class ImportadorScreen extends StatefulWidget {
  const ImportadorScreen({super.key});

  @override
  State<ImportadorScreen> createState() => _ImportadorScreenState();
}

class _ImportadorScreenState extends State<ImportadorScreen> {
  // contexto
  final _programa = TextEditingController();
  final _generacion = TextEditingController();
  final _grupo = TextEditingController();
  final _materia = TextEditingController();
  final _clave = TextEditingController();
  final _ciclo = TextEditingController();
  final _periodo = TextEditingController();
  final _docente = TextEditingController();
  final _pegado = TextEditingController();

  // generaciones para autocompletar programa/generación
  List<Map<String, dynamic>> _generaciones = [];

  // preview
  Map<String, dynamic>? _preview;
  bool _cargandoCtx = true;
  bool _previsualizando = false;
  bool _confirmando = false;

  @override
  void initState() {
    super.initState();
    _cargarGeneraciones();
  }

  @override
  void dispose() {
    for (final c in [
      _programa, _generacion, _grupo, _materia, _clave,
      _ciclo, _periodo, _docente, _pegado
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarGeneraciones() async {
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=circular_generaciones'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _generaciones = ((data['generaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargandoCtx = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargandoCtx = false);
    }
  }

  List<String> get _programas {
    final set = <String>{};
    for (final g in _generaciones) {
      set.add((g['programa'] ?? '').toString());
    }
    return set.toList()..sort();
  }

  List<String> get _generacionesDe {
    final p = _programa.text.trim();
    if (p.isEmpty) return [];
    return _generaciones
        .where((g) => (g['programa'] ?? '') == p)
        .map((g) => (g['generacion'] ?? '').toString())
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  bool get _contextoCompleto =>
      _programa.text.trim().isNotEmpty &&
      _grupo.text.trim().isNotEmpty &&
      _materia.text.trim().isNotEmpty &&
      _clave.text.trim().isNotEmpty;

  Future<void> _previsualizar() async {
    if (!_contextoCompleto) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Completa programa, grupo, materia y clave primero.'),
      ));
      return;
    }
    if (_pegado.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pega las filas copiadas de Excel.'),
      ));
      return;
    }
    setState(() {
      _previsualizando = true;
      _preview = null;
    });
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'importar_preview',
                'texto': _pegado.text,
                'claveMateria': _clave.text.trim(),
                'grupo': _grupo.text.trim(),
              }))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() => _preview = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo previsualizar: $e'
              .replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _previsualizando = false);
    }
  }

  Future<void> _confirmar() async {
    final p = _preview;
    if (p == null) return;
    final validas = (p['validas'] ?? 0) as int;
    final advertencias = (p['advertencias'] ?? 0) as int;
    final aEscribir = validas + advertencias;
    if (aEscribir == 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar importación'),
        content: Text(
            'Se escribirán $aEscribir calificación(es) en:\n\n'
            '${_materia.text.trim()} (${_clave.text.trim()})\n'
            'Grupo ${_grupo.text.trim()} · ${_programa.text.trim()}\n\n'
            'Quedarán como "En validación", igual que la captura normal. '
            '${(p['errores'] ?? 0) as int > 0 ? 'Las filas con error se omitirán.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _confirmando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'importar_confirmar',
                'texto': _pegado.text,
                'contexto': {
                  'programa': _programa.text.trim(),
                  'generacion': _generacion.text.trim(),
                  'grupo': _grupo.text.trim(),
                  'materia': _materia.text.trim(),
                  'claveMateria': _clave.text.trim(),
                  'ciclo': _ciclo.text.trim(),
                  'periodo': _periodo.text.trim(),
                  'docente': _docente.text.trim(),
                },
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¡Importación lista!'),
          content: Text(
              '${data['escritas']} calificación(es) escritas como "En validación".'
              '${(data['omitidas'] ?? 0) as int > 0 ? '\n${data['omitidas']} fila(s) con error fueron omitidas.' : ''}\n\n'
              'Revísalas y valídalas en "Validación de actas".'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido')),
          ],
        ),
      );
      setState(() {
        _pegado.clear();
        _preview = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo importar: $e'
              .replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Importar calificaciones',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _cargandoCtx
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _instrucciones(),
                const SizedBox(height: 18),
                _seccionContexto(),
                const SizedBox(height: 18),
                _seccionPegado(),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: _previsualizando ? null : _previsualizar,
                    icon: _previsualizando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.visibility),
                    label: Text(
                        _previsualizando ? 'Revisando...' : 'Previsualizar'),
                  ),
                ),
                if (_preview != null) ...[
                  const SizedBox(height: 22),
                  _seccionPreview(),
                ],
                const SizedBox(height: 28),
              ],
            ),
    );
  }

  Widget _instrucciones() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cómo importar',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF8A6118))),
          SizedBox(height: 6),
          Text(
            '1. Elige el contexto (programa, grupo, materia, clave).\n'
            '2. En Excel selecciona dos columnas: matrícula y calificación '
            '(opcional una tercera con el nombre). Cópialas (Ctrl+C).\n'
            '3. Pégalas abajo (Ctrl+V) y pulsa Previsualizar.\n'
            '4. Revisa el resultado y confirma. Las calificaciones quedan '
            '"En validación".',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF6B5316)),
          ),
        ],
      ),
    );
  }

  Widget _seccionContexto() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('1. Contexto de la importación',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _programa.text.trim().isEmpty ? null : _programa.text.trim(),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Programa *',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _programas
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => setState(() {
              _programa.text = v ?? '';
              _generacion.text = '';
            }),
          ),
          const SizedBox(height: 10),
          if (_generacionesDe.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _generacion.text.trim().isEmpty
                  ? null
                  : _generacion.text.trim(),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Generación',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _generacionesDe
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _generacion.text = v ?? ''),
            ),
          if (_generacionesDe.isNotEmpty) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _campo(_grupo, 'Grupo *')),
              const SizedBox(width: 10),
              Expanded(child: _campo(_clave, 'Clave materia *')),
            ],
          ),
          const SizedBox(height: 10),
          _campo(_materia, 'Materia *'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _campo(_ciclo, 'Ciclo')),
              const SizedBox(width: 10),
              Expanded(child: _campo(_periodo, 'Periodo')),
            ],
          ),
          const SizedBox(height: 10),
          _campo(_docente, 'Docente'),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController c, String label) {
    return TextField(
      controller: c,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _seccionPegado() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('2. Pega los datos de Excel',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 4),
          Text('Una fila por alumno: matrícula, calificación, (nombre).',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          const SizedBox(height: 10),
          TextField(
            controller: _pegado,
            maxLines: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              hintText: '25010123\t9\n25010124\t8\n25010125\t10',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionPreview() {
    final p = _preview!;
    final filas = (p['filas'] as List?) ?? [];
    final validas = (p['validas'] ?? 0) as int;
    final advertencias = (p['advertencias'] ?? 0) as int;
    final errores = (p['errores'] ?? 0) as int;
    final aEscribir = validas + advertencias;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('3. Previsualización',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _contador('$validas válidas', const Color(0xFF1E8E3E)),
              _contador('$advertencias con aviso', cessumGold),
              _contador('$errores con error', cessumRed),
            ],
          ),
          const SizedBox(height: 14),
          ...filas.map((raw) {
            final r = Map<String, dynamic>.from(raw as Map);
            final estado = (r['estado'] ?? '').toString();
            final color = estado == 'ok'
                ? const Color(0xFF1E8E3E)
                : (estado == 'advertencia' ? cessumGold : cessumRed);
            final icono = estado == 'ok'
                ? Icons.check_circle
                : (estado == 'advertencia'
                    ? Icons.warning_amber_rounded
                    : Icons.cancel);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icono, size: 18, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r['matricula']}  ·  ${r['calificacion']}'
                          '${(r['nombre'] ?? '').toString().isNotEmpty ? '  ·  ${r['nombre']}' : ''}',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        if ((r['mensaje'] ?? '').toString().isNotEmpty)
                          Text('${r['mensaje']}',
                              style: TextStyle(fontSize: 11, color: color)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: aEscribir > 0 ? cessumRed : Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed:
                  (_confirmando || aEscribir == 0) ? null : _confirmar,
              icon: _confirmando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload),
              label: Text(_confirmando
                  ? 'Importando...'
                  : 'Confirmar e importar ($aEscribir)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contador(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(texto,
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
    );
  }
}
