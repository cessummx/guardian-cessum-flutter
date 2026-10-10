// =====================================================================
//  asistencia_grupo_screen.dart · CESSUM · Aula CESSUM
//  ASISTENCIA DEL GRUPO — lo que el docente necesita ver.
//
//  La ruta asistencia_grupo existía desde el 6-ago pero nunca tuvo
//  pantalla: el dato se calculaba y nadie podía verlo. Ahora que los
//  informes de Meet sí se están leyendo, esta lista tiene contenido real.
//
//  Backend: GET asistencia_grupo&programa=&generacion=&grupo=
//  (solo lectura, no envía correos)
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'helpers.dart';
import 'laboratorio_evaluacion_screen.dart';

class AsistenciaGrupoScreen extends StatefulWidget {
  final String programa;
  final String generacion;
  final String grupo;
  final String materia;
  const AsistenciaGrupoScreen({
    super.key,
    required this.programa,
    required this.generacion,
    required this.grupo,
    this.materia = '',
  });

  @override
  State<AsistenciaGrupoScreen> createState() => _AsistenciaGrupoScreenState();
}

class _AsistenciaGrupoScreenState extends State<AsistenciaGrupoScreen> {
  bool _cargando = true;
  String? _error;
  int _sesiones = 0;
  List<Map<String, dynamic>> _alumnos = [];
  final _busca = TextEditingController();
  bool _soloBajos = false;

  /// Debajo de este porcentaje se marca al alumno en rojo. No es una regla
  /// institucional: es un umbral de LECTURA para que el docente ubique rápido
  /// a quién le está faltando. La decisión sigue siendo suya.
  static const double _umbralBajo = 0.7;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'asistencia_grupo',
        'programa': widget.programa,
        'generacion': widget.generacion,
        'grupo': widget.grupo,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _sesiones = (d['sesiones'] ?? 0) as int;
        _alumnos = (d['alumnos'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // Peor asistencia primero: es a quien hay que mirar.
        _alumnos.sort((a, b) =>
            ((a['asistidas'] ?? 0) as int).compareTo((b['asistidas'] ?? 0) as int));
      });
    } catch (e) {
      // (24-sep) El motivo limpio, sin «Exception:»; lo técnico, como falla de conexión.
      final m = '$e'.replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() => _error = (m.contains('TimeoutException') || m.contains('ClientException') ||
                m.contains('SocketException') || m.startsWith('FormatException'))
            ? 'No se pudo cargar la asistencia. Revisa tu conexión e intenta de nuevo.'
            : m);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _norm(String s) {
    s = s.toLowerCase();
    const a = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const b = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < a.length; i++) {
      s = s.replaceAll(a[i], b[i]);
    }
    return s.trim();
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _norm(_busca.text);
    return _alumnos.where((al) {
      if (_soloBajos && _sesiones > 0) {
        final pct = ((al['asistidas'] ?? 0) as int) / _sesiones;
        if (pct >= _umbralBajo) return false;
      }
      if (q.isEmpty) return true;
      return _norm((al['nombre'] ?? '').toString()).contains(q) ||
          (al['matricula'] ?? '').toString().contains(q);
    }).toList();
  }

  /// (24-sep) La lista en columnas, lista para pegar en Excel.
  void _copiarLista() {
    final sb = StringBuffer()
      ..writeln('${widget.materia}\t${widget.programa} ${widget.generacion} Grupo ${widget.grupo}\t$_sesiones sesiones')
      ..writeln('Alumno\tMatrícula\tAsistidas\tPorcentaje');
    for (final al in _alumnos) {
      final asis = (al['asistidas'] ?? 0) as int;
      sb.writeln('${al['nombre']}\t${al['matricula']}\t$asis\t${_sesiones > 0 ? (asis * 100 / _sesiones).round() : 0}%');
    }
    Helpers.copiarAlPortapapeles(context, sb.toString(), 'Lista de asistencia');
  }

  @override
  Widget build(BuildContext context) {
    final vis = _cargando ? <Map<String, dynamic>>[] : _visibles;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Asistencia del grupo'),
        actions: [
          // (9-oct-2026) De la asistencia al laboratorio de evaluación de la
          // misma materia (solo cuando se sabe cuál es).
          if (widget.materia.trim().isNotEmpty)
            IconButton(
              tooltip: 'Laboratorio de evaluación',
              icon: const Icon(Icons.science_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LaboratorioEvaluacionScreen(
                    programa: widget.programa,
                    generacion: widget.generacion,
                    grupo: widget.grupo,
                    materia: widget.materia,
                    desdeCaptura: false,
                  ),
                ),
              ),
            ),
          IconButton(
              tooltip: 'Copiar la lista para Excel',
              icon: const Icon(Icons.table_chart_outlined),
              onPressed: _cargando || _alumnos.isEmpty ? null : _copiarLista),
          IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _cargando ? null : _cargar),
        ],
      ),
      body: _cargando
          ? const Padding(
              padding: EdgeInsets.all(12), child: CessumSkeletonList())
          : _error != null
              ? _vistaError()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
                    children: [
                      _cabecera(),
                      const SizedBox(height: 14),
                      if (_sesiones == 0)
                        _sinSesiones()
                      else ...[
                        TextField(
                          controller: _busca,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Buscar alumno o matrícula…',
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                            filled: true,
                            fillColor: Theme.of(context).cardColor,
                            border: const OutlineInputBorder(),
                            suffixIcon: _busca.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () =>
                                        setState(() => _busca.clear()),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilterChip(
                            label: const Text('Solo los que van bajos'),
                            selected: _soloBajos,
                            selectedColor: cessumRed.withValues(alpha: 0.14),
                            labelStyle: const TextStyle(fontSize: 12),
                            onSelected: (v) => setState(() => _soloBajos = v),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...vis.map(_fila),
                        if (vis.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                                child: Text('Nadie coincide con el filtro.',
                                    style: TextStyle(color: cessumMuted(context)))),
                          ),
                      ],
                      const SizedBox(height: 14),
                      _nota(),
                    ],
                  ),
                ),
    );
  }

  Widget _vistaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 46, color: Colors.grey),
              const SizedBox(height: 10),
              Text(_error ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ElevatedButton(
                  onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _cabecera() {
    final total = _alumnos.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB11D29), Color(0xFF8E1720)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.materia.isNotEmpty)
            Text(widget.materia,
                style: CessumType.heading(15, color: Colors.white)),
          const SizedBox(height: 2),
          Text(
              '${widget.programa} · ${widget.generacion} · Grupo ${widget.grupo}',
              style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_sesiones',
                        style: CessumType.display(30, color: Colors.white)),
                    const Text('sesiones registradas',
                        style:
                            TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$total',
                        style: CessumType.display(30, color: Colors.white)),
                    const Text('alumnos en el grupo',
                        style:
                            TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sinSesiones() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.08),
            border: Border.all(color: CC.goldBorder),
            borderRadius: BorderRadius.circular(12)),
        child: const Text(
            'Todavía no hay sesiones registradas de este grupo.\n\n'
            'La asistencia se toma del informe que Google genera al terminar '
            'cada reunión. Para que llegue, la sesión debe crearse desde la '
            'agenda de la plataforma y tener activado el seguimiento de '
            'asistencia. Si tus sesiones no aparecen, avísale a Vicerrectoría: '
            'no es algo que puedas activar tú desde aquí.',
            style: TextStyle(fontSize: 12.5, height: 1.4)),
      );

  Widget _fila(Map<String, dynamic> al) {
    final asis = (al['asistidas'] ?? 0) as int;
    final pct = _sesiones > 0 ? asis / _sesiones : 0.0;
    final bajo = _sesiones > 0 && pct < _umbralBajo;
    final color = bajo
        ? const Color(0xFFC62828)
        : (pct >= 0.9 ? const Color(0xFF1E8E3E) : cessumGold);
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: bajo ? 0.5 : 0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((al['nombre'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text((al['matricula'] ?? '').toString(),
                    style: TextStyle(
                        fontSize: 10.5, color: cessumFaint(context))),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: cessumMuted(context).withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$asis de $_sesiones',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: color)),
              Text('${(pct * 100).round()}%',
                  style: TextStyle(
                      fontSize: 11, color: cessumMuted(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nota() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10)),
        child: Text(
            'Cómo leer esta lista: cuenta las sesiones EN VIVO de las materias '
            'que el grupo lleva ahora, y solo reconoce a quien entró con su '
            'correo institucional. Un alumno que entró con su correo personal '
            'aparece sin asistencia aunque haya estado toda la clase. Úsala '
            'como apoyo, no como acta: la decisión sobre la calificación '
            'sigue siendo tuya.',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: cessumInk(context))),
      );
}
