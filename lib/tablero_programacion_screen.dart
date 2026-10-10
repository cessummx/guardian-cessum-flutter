import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// MEJORA 5 — Tablero de programación por grupo.
///
/// Muestra, agrupado por grupo (programa · generación · grupo), qué materias
/// ya tienen docente y horario y cuáles faltan, con el estado de cada
/// invitación (Pendiente / Aceptada / Rechazada). Cruza `grupos_admin_todos`
/// (universo de grupos con alumnos) con `asignaciones_listar` (materias
/// programadas). No toca nada más de la app.
class TableroProgramacionScreen extends StatefulWidget {
  const TableroProgramacionScreen({super.key});

  @override
  State<TableroProgramacionScreen> createState() =>
      _TableroProgramacionScreenState();
}

class _GrupoProg {
  final String programa;
  final String generacion;
  final String grupo;
  final int alumnos;
  final List<Map<String, dynamic>> materias;
  _GrupoProg(this.programa, this.generacion, this.grupo, this.alumnos,
      this.materias);

  String get clave => '$programa||$generacion||$grupo';
}

class _TableroProgramacionScreenState extends State<TableroProgramacionScreen> {
  bool _cargando = true;
  String? _error;
  List<_GrupoProg> _grupos = [];
  String _fPrograma = 'Todos';
  bool _soloIncompletos = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, dynamic>> _get(String accion) async {
    final uri =
        Uri.parse(guardianUrl).replace(queryParameters: {'accion': accion});
    final resp = await http.get(uri).timeout(const Duration(seconds: 40));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    if (mounted) setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final dataG = await _get('grupos_admin_todos');
      if (dataG['ok'] != true) {
        throw Exception((dataG['error'] ?? 'No se pudo cargar grupos').toString());
      }
      final dataA = await _get('asignaciones_listar');
      final asignaciones = (dataA['asignaciones'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Contar alumnos por grupo (clave programa||generacion||grupo).
      final cuenta = <String, int>{};
      final info = <String, List<String>>{};
      for (final r in (dataG['grupos'] as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(r as Map);
        final prog = (m['programa'] ?? '').toString().trim();
        final gen = (m['generacion'] ?? '').toString().trim();
        final grp = (m['grupo'] ?? '').toString().trim();
        if (grp.isEmpty || grp == 'BAJA') continue;
        final k = '$prog||$gen||$grp';
        cuenta[k] = (cuenta[k] ?? 0) + 1;
        info[k] = [prog, gen, grp];
      }

      // Materias por grupo.
      final matsPorGrupo = <String, List<Map<String, dynamic>>>{};
      for (final a in asignaciones) {
        final prog = (a['programa'] ?? '').toString().trim();
        final gen = (a['generacion'] ?? '').toString().trim();
        final grp = (a['grupo'] ?? '').toString().trim();
        final k = '$prog||$gen||$grp';
        (matsPorGrupo[k] ??= []).add(a);
      }

      final grupos = <_GrupoProg>[];
      final claves = {...cuenta.keys, ...matsPorGrupo.keys};
      for (final k in claves) {
        final partes = info[k] ?? k.split('||');
        grupos.add(_GrupoProg(
          partes[0],
          partes.length > 1 ? partes[1] : '',
          partes.length > 2 ? partes[2] : '',
          cuenta[k] ?? 0,
          matsPorGrupo[k] ?? [],
        ));
      }
      grupos.sort((a, b) => a.clave.compareTo(b.clave));

      if (mounted) setState(() {
        _grupos = grupos;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'Sin conexión o error: $e';
        _cargando = false;
      });
    }
  }

  List<String> get _programas {
    final s = <String>{};
    for (final g in _grupos) {
      if (g.programa.isNotEmpty) s.add(g.programa);
    }
    final l = s.toList()..sort();
    return ['Todos', ...l];
  }

  List<_GrupoProg> get _filtrados {
    return _grupos.where((g) {
      if (_fPrograma != 'Todos' && g.programa != _fPrograma) return false;
      if (_soloIncompletos && g.materias.isNotEmpty &&
          !g.materias.any(_pendiente)) {
        // si no tiene materias o tiene alguna pendiente -> es "incompleto"
        return g.materias.isEmpty;
      }
      if (_soloIncompletos) {
        return g.materias.isEmpty || g.materias.any(_pendiente);
      }
      return true;
    }).toList();
  }

  bool _pendiente(Map<String, dynamic> m) {
    final est = (m['invitacionEstado'] ?? '').toString().trim();
    final correo = (m['correo'] ?? '').toString().trim();
    if (!correo.contains('@')) return true; // sin docente con correo
    return est != 'Aceptada' && est != 'Rechazada';
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtrados;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Programación por grupo'),
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

  Widget _filtros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _fPrograma,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Programa',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: _programas
                  .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _fPrograma = v ?? 'Todos'),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Text('Incompletos',
                  style: TextStyle(fontSize: 10, color: cessumMuted(context))),
              Switch(
                value: _soloIncompletos,
                activeThumbColor: cessumRed,
                onChanged: (v) => setState(() => _soloIncompletos = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lista(List<_GrupoProg> items) {
    if (items.isEmpty) {
      return Center(
        child: Text('Sin grupos con ese filtro.',
            style: TextStyle(color: cessumMuted(context))),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
        itemCount: items.length,
        itemBuilder: (_, i) => _tarjetaGrupo(items[i]),
      ),
    );
  }

  Color _colorEstado(String est, String correo) {
    if (!correo.contains('@')) return Colors.grey;
    switch (est) {
      case 'Aceptada':
        return const Color(0xFF1E8E3E);
      case 'Rechazada':
        return cessumRed;
      default:
        return cessumGold;
    }
  }

  Widget _tarjetaGrupo(_GrupoProg g) {
    final total = g.materias.length;
    final aceptadas = g.materias.where((m) {
      return (m['invitacionEstado'] ?? '').toString().trim() == 'Aceptada';
    }).length;
    final completo = total > 0 && !g.materias.any(_pendiente);
    final colorBorde = total == 0
        ? Colors.grey
        : (completo ? const Color(0xFF1E8E3E) : cessumGold);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorBorde.withValues(alpha: 0.5)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          title: Text('Grupo ${g.grupo} · Gen. ${g.generacion}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(g.programa,
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(total == 0 ? 'Sin materias' : '$aceptadas/$total ok',
                  style: TextStyle(
                      color: colorBorde,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
              Text('${g.alumnos} alumnos',
                  style: TextStyle(fontSize: 10, color: cessumFaint(context))),
            ],
          ),
          children: g.materias.isEmpty
              ? [
                  const ListTile(
                    dense: true,
                    leading:
                        Icon(Icons.warning_amber_rounded, color: cessumGold),
                    title: Text('Aún no tiene materias programadas.',
                        style: TextStyle(fontSize: 13)),
                  )
                ]
              : g.materias.map((m) {
                  final est = (m['invitacionEstado'] ?? '').toString().trim();
                  final correo = (m['correo'] ?? '').toString().trim();
                  final estView = correo.contains('@')
                      ? (est.isEmpty ? 'Pendiente' : est)
                      : 'Sin docente';
                  final color = _colorEstado(est, correo);
                  final dia = (m['dia'] ?? '').toString().trim();
                  final hora = (m['hora'] ?? '').toString().trim();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cessumMuted(context).withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text((m['materia'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(estView,
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                            (m['docente'] ?? '(sin docente)').toString() +
                                (dia.isNotEmpty || hora.isNotEmpty
                                    ? '  ·  $dia ${hora.isNotEmpty ? hora : ''}'
                                    : ''),
                            style: TextStyle(
                                fontSize: 11.5, color: cessumMuted(context))),
                      ],
                    ),
                  );
                }).toList(),
        ),
      ),
    );
  }
}
