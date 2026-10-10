import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// MEJORA DOCENTE — Mis alumnos.
///
/// Lista en un solo lugar a todos los alumnos de los grupos que imparte el
/// profesor, con su grupo, las materias que les da y su correo para
/// contactarlos. Usa la acción `mis_alumnos` (por correo de sesión).
class MisAlumnosDocenteScreen extends StatefulWidget {
  const MisAlumnosDocenteScreen({super.key});

  @override
  State<MisAlumnosDocenteScreen> createState() =>
      _MisAlumnosDocenteScreenState();
}

class _MisAlumnosDocenteScreenState extends State<MisAlumnosDocenteScreen> {
  bool _cargando = true;
  String? _error;
  int _grupos = 0;
  List<Map<String, dynamic>> _alumnos = [];
  final TextEditingController _busqueda = TextEditingController();
  String _fGrupo = 'Todos';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      if (correo.isEmpty) {
        if (mounted) setState(() {
          _error = 'No se pudo identificar tu correo de docente.';
          _cargando = false;
        });
        return;
      }
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_alumnos',
        'correo': correo.toLowerCase(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final lista = (data['alumnos'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (mounted) setState(() {
          _alumnos = lista;
          _grupos = (data['grupos'] ?? 0) as int;
          _cargando = false;
        });
      } else {
        if (mounted) setState(() {
          _error = (data['error'] ?? 'No se pudo cargar').toString();
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = 'Sin conexión o error: $e';
        _cargando = false;
      });
    }
  }

  List<String> get _opcionesGrupo {
    final s = <String>{};
    for (final a in _alumnos) {
      final g = '${a['programa']} · ${a['grupo']} · ${a['generacion']}';
      s.add(g);
    }
    final l = s.toList()..sort();
    return ['Todos', ...l];
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _busqueda.text.trim().toLowerCase();
    return _alumnos.where((a) {
      if (_fGrupo != 'Todos') {
        final g = '${a['programa']} · ${a['grupo']} · ${a['generacion']}';
        if (g != _fGrupo) return false;
      }
      if (q.isEmpty) return true;
      final blob =
          '${a['nombre']} ${a['matricula']} ${a['correo']}'.toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtrados;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis alumnos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _vistaError()
              : Column(
                  children: [
                    _cabecera(items.length),
                    _filtros(),
                    Expanded(child: _lista(items)),
                  ],
                ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _cabecera(int mostrados) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text('${_alumnos.length}',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: cessumRed)),
                  Text('Alumnos',
                      style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text('$_grupos',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: cessumGold)),
                  Text('Grupos',
                      style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        children: [
          TextField(
            controller: _busqueda,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Buscar nombre, matrícula o correo…',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (_opcionesGrupo.length > 2) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _fGrupo,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Grupo',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: _opcionesGrupo
                  .map((g) => DropdownMenuItem(
                      value: g,
                      child: Text(g, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _fGrupo = v ?? 'Todos'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lista(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Text('Sin alumnos para mostrar.',
            style: TextStyle(color: cessumMuted(context))),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (_, i) => _tarjeta(items[i]),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final materias = (a['materias'] ?? '').toString().trim();
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((a['nombre'] ?? '').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Grupo ${a['grupo']}',
                      style: const TextStyle(
                          color: cessumRed,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text('${a['programa']} · Gen. ${a['generacion']}',
                style: TextStyle(color: cessumMuted(context), fontSize: 12)),
            const SizedBox(height: 4),
            Text('Mat. ${a['matricula']}',
                style: const TextStyle(fontSize: 12)),
            Text((a['correo'] ?? '').toString(),
                style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
            if (materias.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Le impartes: $materias',
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: cessumGold,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
