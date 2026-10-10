import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// MEJORA 2 — Grupos sin maestro (huecos por programar).
///
/// Lista los grupos que ya tienen alumnos pero todavía NO tienen ningún
/// docente activo asignado, para no dejar huecos al programar. Se alimenta
/// de la acción `grupos_sin_maestro`, que devuelve
/// {programa, generacion, grupo, alumnos}. No toca nada más de la app.
class MateriasSinMaestroScreen extends StatefulWidget {
  const MateriasSinMaestroScreen({super.key});

  @override
  State<MateriasSinMaestroScreen> createState() =>
      _MateriasSinMaestroScreenState();
}

class _MateriasSinMaestroScreenState extends State<MateriasSinMaestroScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _grupos = [];
  String _filtroPrograma = 'Todos';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'grupos_sin_maestro'});
      final resp = await http.get(uri).timeout(Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final lista = (data['grupos'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _grupos = lista;
          _cargando = false;
        });
      } else {
        setState(() {
          _error = (data['error'] ?? 'No se pudo cargar').toString();
          _cargando = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Sin conexión o error: $e';
        _cargando = false;
      });
    }
  }

  List<String> get _programas {
    final s = <String>{};
    for (final g in _grupos) {
      final p = (g['programa'] ?? '').toString().trim();
      if (p.isNotEmpty) s.add(p);
    }
    final l = s.toList()..sort();
    return ['Todos', ...l];
  }

  List<Map<String, dynamic>> get _filtrados {
    if (_filtroPrograma == 'Todos') return _grupos;
    return _grupos
        .where((g) => (g['programa'] ?? '').toString() == _filtroPrograma)
        .toList();
  }

  void _aviso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Color(0xFF1E8E3E),
    ));
  }

  Future<void> _copiar(Map<String, dynamic> g) async {
    final texto =
        '${g['programa']} | Gen. ${g['generacion']} | Grupo ${g['grupo']}';
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) _aviso('Datos copiados: $texto');
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtrados;
    final totalAlumnos = items.fold<int>(
        0, (s, g) => s + (int.tryParse('${g['alumnos']}') ?? 0));

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text('Grupos sin maestro'),
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
                    _resumen(items.length, totalAlumnos),
                    if (_programas.length > 2) _filtroProg(),
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

  Widget _resumen(int grupos, int alumnos) {
    Widget chip(String etq, String val, Color color, IconData ic) {
      return Expanded(
        child: Container(
          margin: EdgeInsets.all(4),
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(ic, color: color, size: 20),
              SizedBox(height: 4),
              Text(val,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              Text(etq,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Row(
        children: [
          chip('Grupos sin maestro', '$grupos', cessumRed,
              Icons.warning_amber_rounded),
          chip('Alumnos afectados', '$alumnos', cessumGold, Icons.groups),
        ],
      ),
    );
  }

  Widget _filtroProg() {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: DropdownButtonFormField<String>(
        value: _filtroPrograma,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          labelText: 'Programa',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: _programas
            .map((p) => DropdownMenuItem(
                value: p,
                child: Text(p, overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: (v) =>
            setState(() => _filtroPrograma = v ?? 'Todos'),
      ),
    );
  }

  Widget _lista(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 48, color: Color(0xFF1E8E3E)),
              SizedBox(height: 12),
              Text('Todos los grupos tienen maestro asignado.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cessumMuted(context))),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: items.length,
        itemBuilder: (_, i) => _tarjeta(items[i]),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> g) {
    final alumnos = int.tryParse('${g['alumnos']}') ?? 0;
    return Card(
      margin: EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.person_off_outlined, color: cessumRed),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Grupo ${g['grupo']}  ·  Gen. ${g['generacion']}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 2),
                  Text((g['programa'] ?? '').toString(),
                      style: TextStyle(
                          color: cessumMuted(context), fontSize: 12)),
                  SizedBox(height: 4),
                  Text('$alumnos alumno(s) sin docente asignado',
                      style: TextStyle(
                          color: cessumGold,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copiar datos para programar',
              icon: Icon(Icons.copy, size: 20),
              color: cessumRed,
              onPressed: () => _copiar(g),
            ),
          ],
        ),
      ),
    );
  }
}
