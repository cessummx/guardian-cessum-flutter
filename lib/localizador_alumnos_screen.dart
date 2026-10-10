import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// MEJORA 4 — Localizador de alumnos.
///
/// Permite ubicar alumnos filtrando por programa, generación, grupo y
/// modalidad, además de búsqueda libre por nombre / matrícula / correo.
/// El GRUPO viene en vivo de `grupos_admin_todos` (base oficial) y la
/// MODALIDAD se cruza por matrícula desde alumnos.json. Todo dentro de la
/// app; no toca nada más.
class LocalizadorAlumnosScreen extends StatefulWidget {
  const LocalizadorAlumnosScreen({
    super.key,
    this.initialPrograma,
    this.initialGeneracion,
    this.initialGrupo,
  });

  /// Filtros con los que abre la pantalla (p. ej. desde el buscador global).
  final String? initialPrograma;
  final String? initialGeneracion;
  final String? initialGrupo;

  @override
  State<LocalizadorAlumnosScreen> createState() =>
      _LocalizadorAlumnosScreenState();
}

class _LocalizadorAlumnosScreenState extends State<LocalizadorAlumnosScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _alumnos = [];

  final TextEditingController _busqueda = TextEditingController();
  String _fPrograma = 'Todos';
  String _fGeneracion = 'Todas';
  String _fGrupo = 'Todos';
  String _fModalidad = 'Todas';
  bool _filtrosInicialesAplicados = false;

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
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // 1) Padrón con GRUPO (base oficial, en vivo).
      final uriG = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'grupos_admin_todos'});
      final respG = await http.get(uriG).timeout(Duration(seconds: 40));
      final dataG = jsonDecode(respG.body) as Map<String, dynamic>;
      if (dataG['ok'] != true) {
        throw Exception((dataG['error'] ?? 'No se pudo cargar el padrón').toString());
      }
      final base = (dataG['grupos'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // 2) Modalidad por matrícula desde alumnos.json (mejor esfuerzo).
      final modPorMat = <String, String>{};
      try {
        final respA = await http
            .get(Uri.parse(alumnosJsonUrl))
            .timeout(Duration(seconds: 20));
        if (respA.statusCode == 200) {
          final dataA =
              jsonDecode(utf8.decode(respA.bodyBytes)) as Map<String, dynamic>;
          for (final item in (dataA['alumnos'] as List<dynamic>? ?? [])) {
            final m = Map<String, dynamic>.from(item as Map);
            final mat = (m['matricula'] ?? '').toString().trim();
            if (mat.isNotEmpty) {
              modPorMat[mat] = (m['modalidad'] ?? '').toString().trim();
            }
          }
        }
      } catch (_) {
        // Si falla, seguimos sin modalidad.
      }

      String normMod(String v, String grupo) {
        final x = v.toLowerCase();
        if (x == 'virtual') return 'No Escolarizada';
        if (x == 'mixta') return 'Mixta';
        if (v.isNotEmpty) return v;
        if (grupo == 'Mixta') return 'Mixta';
        if (grupo.isNotEmpty && grupo != 'BAJA') return 'No Escolarizada';
        return '';
      }

      final lista = base.map((r) {
        final mat = (r['matricula'] ?? '').toString().trim();
        final grupo = (r['grupo'] ?? '').toString().trim();
        return {
          'matricula': mat,
          'nombre': (r['nombre'] ?? '').toString(),
          'correo': (r['correo'] ?? '').toString(),
          'programa': (r['programa'] ?? '').toString(),
          'generacion': (r['generacion'] ?? '').toString(),
          'grupo': grupo,
          'modalidad': normMod(modPorMat[mat] ?? '', grupo),
        };
      }).toList();

      if (!_filtrosInicialesAplicados) {
        _filtrosInicialesAplicados = true;
        if (widget.initialPrograma != null &&
            lista.any((a) => a['programa'] == widget.initialPrograma)) {
          _fPrograma = widget.initialPrograma!;
        }
        if (widget.initialGeneracion != null &&
            lista.any((a) => a['generacion'] == widget.initialGeneracion)) {
          _fGeneracion = widget.initialGeneracion!;
        }
        if (widget.initialGrupo != null &&
            lista.any((a) => a['grupo'] == widget.initialGrupo)) {
          _fGrupo = widget.initialGrupo!;
        }
      }
      setState(() {
        _alumnos = lista;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Sin conexión o error: $e';
        _cargando = false;
      });
    }
  }

  List<String> _opciones(String campo, String todos) {
    final s = <String>{};
    for (final a in _alumnos) {
      final v = (a[campo] ?? '').toString().trim();
      if (v.isNotEmpty) s.add(v);
    }
    final l = s.toList()..sort();
    return [todos, ...l];
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _busqueda.text.trim().toLowerCase();
    return _alumnos.where((a) {
      if (_fPrograma != 'Todos' && a['programa'] != _fPrograma) return false;
      if (_fGeneracion != 'Todas' && a['generacion'] != _fGeneracion) {
        return false;
      }
      if (_fGrupo != 'Todos' && a['grupo'] != _fGrupo) return false;
      if (_fModalidad != 'Todas' && a['modalidad'] != _fModalidad) return false;
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
        title: Text('Localizador de alumnos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? _vistaError()
              : Column(
                  children: [
                    _filtros(),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 2),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${items.length} de ${_alumnos.length} alumnos',
                            style: TextStyle(
                                fontSize: 12, color: cessumMuted(context))),
                      ),
                    ),
                    Expanded(child: _lista(items)),
                  ],
                ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: cessumFaint(context)),
            SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center),
            SizedBox(height: 16),
            ElevatedButton(onPressed: _cargar, child: Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _filtros() {
    Widget dd(String label, String value, List<String> ops,
        ValueChanged<String> onCh) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: ops
              .map((o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => onCh(v ?? ops.first),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Column(
        children: [
          TextField(
            controller: _busqueda,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Buscar nombre, matrícula o correo…',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: dd('Programa', _fPrograma,
                      _opciones('programa', 'Todos'),
                      (v) => setState(() => _fPrograma = v))),
              Expanded(
                  child: dd('Generación', _fGeneracion,
                      _opciones('generacion', 'Todas'),
                      (v) => setState(() => _fGeneracion = v))),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: dd('Grupo', _fGrupo, _opciones('grupo', 'Todos'),
                      (v) => setState(() => _fGrupo = v))),
              Expanded(
                  child: dd('Modalidad', _fModalidad,
                      _opciones('modalidad', 'Todas'),
                      (v) => setState(() => _fModalidad = v))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lista(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Text('Sin resultados con esos filtros.',
            style: TextStyle(color: cessumMuted(context))),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(height: 4),
        itemBuilder: (_, i) => _tarjeta(items[i]),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final mod = (a['modalidad'] ?? '').toString();
    final grupo = (a['grupo'] ?? '').toString();
    Color cMod = mod == 'Mixta'
        ? cessumGold
        : (mod.isNotEmpty ? Color(0xFF1F5B9C) : Colors.grey);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((a['nombre'] ?? '').toString(),
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                if (mod.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cMod.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(mod,
                        style: TextStyle(
                            color: cMod,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            SizedBox(height: 3),
            Text('${a['programa']} · Gen. ${a['generacion']}',
                style: TextStyle(color: cessumMuted(context), fontSize: 12)),
            SizedBox(height: 4),
            Row(
              children: [
                Text('Mat. ${a['matricula']}',
                    style: TextStyle(fontSize: 12)),
                SizedBox(width: 10),
                if (grupo.isNotEmpty)
                  Text('Grupo $grupo',
                      style: TextStyle(
                          fontSize: 12,
                          color: cessumRed,
                          fontWeight: FontWeight.w600)),
              ],
            ),
            SizedBox(height: 2),
            Text((a['correo'] ?? '').toString(),
                style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          ],
        ),
      ),
    );
  }
}
