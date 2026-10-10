import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Tablero de Inteligencia Institucional (BI) — vista admin.
/// Consume la acción `tablero_bi` del Guardián y muestra los
/// indicadores en tarjetas: matrícula, aprobación, carga docente,
/// actas, contratos y documentos emitidos.
class TableroBiScreen extends StatefulWidget {
  const TableroBiScreen({super.key});

  @override
  State<TableroBiScreen> createState() => _TableroBiScreenState();
}

class _TableroBiScreenState extends State<TableroBiScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  String _generado = '';
  int _umbral = 8;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final correo = (await SessionStore.realEmail()) ?? '';
      final uri = Uri.parse(
          '$guardianUrl?accion=tablero_bi&actor=${Uri.encodeComponent(correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        if (mounted) setState(() {
          _error = (data['error'] ?? 'No se pudo cargar el tablero.').toString();
          _cargando = false;
        });
        return;
      }
      if (mounted) setState(() {
        _d = data;
        _generado = (data['generado'] ?? '').toString();
        _umbral = (data['umbral'] is num) ? (data['umbral'] as num).toInt() : 8;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'No se pudo conectar. Revisa tu internet e inténtalo de nuevo.';
        _cargando = false;
      });
    }
  }

  // --- Lectura segura ---
  Map<String, dynamic> _m(String k) =>
      (_d[k] is Map) ? Map<String, dynamic>.from(_d[k] as Map) : <String, dynamic>{};
  String _t(dynamic v) => (v ?? 0).toString();
  int _i(dynamic v) => (v is num) ? v.toInt() : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text('Tablero institucional'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _vistaError()
              : _contenido(),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.black38),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context))),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    final mat = _m('matricula');
    final aca = _m('academico');
    final act = _m('actas');
    final doc = _m('docentes');
    final con = _m('contratos');
    final progs = (mat['porPrograma'] is List) ? mat['porPrograma'] as List : const [];
    final gens = (mat['porGeneracion'] is List) ? mat['porGeneracion'] as List : const [];
    final totMat = _i(mat['total']);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _kpi('Matrícula', _t(mat['total']), Icons.school, cessumRed)),
              const SizedBox(width: 10),
              Expanded(child: _kpi('Aprobación', '${_t(aca['pctAprobacion'])}%',
                  Icons.verified, const Color(0xFF1E8E3E))),
              const SizedBox(width: 10),
              Expanded(child: _kpi('Docentes', _t(doc['total']), Icons.groups, cessumGold)),
            ],
          ),
          const SizedBox(height: 16),

          if (progs.isNotEmpty)
            _seccion('Matrícula por programa', [
              for (final p in progs)
                _barra((p is Map ? p['nombre'] : '').toString(),
                    _i(p is Map ? p['total'] : 0), totMat),
            ]),
          if (progs.isNotEmpty) const SizedBox(height: 12),

          if (gens.isNotEmpty)
            _seccion('Matrícula por generación', [
              for (final g in gens)
                _barra((g is Map ? g['nombre'] : '').toString(),
                    _i(g is Map ? g['total'] : 0), totMat),
            ]),
          if (gens.isNotEmpty) const SizedBox(height: 12),

          _tarjetaDatos('Académico', cessumRed, [
            ['Calificaciones registradas', _t(aca['calificaciones'])],
            ['Promedio general', _t(aca['promedio'])],
            ['Aprobados', _t(aca['aprobados'])],
            ['Reprobados', _t(aca['reprobados'])],
            ['% de aprobación', '${_t(aca['pctAprobacion'])}%'],
          ], nota: 'Umbral de aprobación: $_umbral'),
          const SizedBox(height: 12),

          _tarjetaDatos('Actas', const Color(0xFF1E8E3E), [
            ['Total de actas', _t(act['total'])],
            ['En validación', _t(act['enValidacion'])],
            ['Validadas', _t(act['validadas'])],
            ['Devueltas', _t(act['devueltas'])],
          ]),
          const SizedBox(height: 12),

          _tarjetaDatos('Docentes y carga', cessumGold, [
            ['Docentes activos', _t(doc['total'])],
            ['Materias activas', _t(doc['materiasActivas'])],
            ['Carga promedio', _t(doc['cargaPromedio'])],
            ['Carga máxima', _t(doc['cargaMax'])],
            ['Materias sin docente', _t(doc['sinDocente'])],
            ['Materias sin link', _t(doc['sinLink'])],
          ]),
          const SizedBox(height: 12),

          _tarjetaDatos('Contratos', cessumRed, [
            ['Total', _t(con['total'])],
            ['Validados', _t(con['validado'])],
            ['Pendientes', _t(con['pendiente'])],
            ['Rechazados', _t(con['rechazado'])],
          ]),
          const SizedBox(height: 12),

          _tarjetaDatos('Documentos', cessumGold, [
            ['Emitidos (histórico)', _t(_d['documentosEmitidos'])],
          ]),

          if (_generado.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text('Generado el $_generado',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: cessumFaint(context))),
            ),
        ],
      ),
    );
  }

  Widget _kpi(String titulo, String valor, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        children: [
          Icon(icono, color: color, size: 26),
          const SizedBox(height: 8),
          Text(valor,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(titulo,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ],
      ),
    );
  }

  Widget _seccion(String titulo, List<Widget> hijos) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: cessumInk(context))),
          const SizedBox(height: 12),
          ...hijos,
        ],
      ),
    );
  }

  Widget _barra(String nombre, int valor, int total) {
    final frac = (total > 0) ? (valor / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cessumInk(context))),
              ),
              const SizedBox(width: 8),
              Text('$valor',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: cessumInk(context))),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              backgroundColor: cessumGold.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(cessumRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaDatos(String titulo, Color color, List<List<String>> filas,
      {String nota = ''}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 10),
          for (final f in filas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(f[0],
                        style: TextStyle(fontSize: 13, color: cessumInk(context))),
                  ),
                  Text(f[1],
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: cessumInk(context))),
                ],
              ),
            ),
          if (nota.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(nota, style: TextStyle(fontSize: 11, color: cessumFaint(context))),
          ],
        ],
      ),
    );
  }
}
