// =====================================================================
//  eval_grupo_screen.dart · CESSUM · Aula CESSUM
//  Dos caras de lo mismo:
//    · PERFIL — lo que otros profesores ya saben de este grupo.
//    · EVALUAR — lo que tú dejas para el que venga después.
//
//  Por qué existe: cuando termina una materia, lo que el docente aprendió
//  del grupo se va con él. El siguiente llega a ciegas y tarda tres
//  sesiones en descubrir lo que el anterior ya sabía. Esto lo convierte
//  en un perfil que viaja con el grupo.
//
//  No califica alumnos ni toca su expediente. Se lo decimos al docente en
//  la pantalla, porque si cree que está juzgando gente, no contesta con
//  honestidad — o no contesta.
//
//  Backend (Code.gs V595):
//    eval_grupo_preguntas · eval_grupo_perfil · eval_grupo_pendientes
//    eval_grupo_guardar (POST)
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class EvalGrupoScreen extends StatefulWidget {
  final String correo;
  final String docente;

  /// Si viene un grupo, la pantalla abre directo en ese. Si no, muestra la
  /// lista de los que le faltan por evaluar.
  final String? programa;
  final String? generacion;
  final String? grupo;
  final String? materia;

  const EvalGrupoScreen({
    super.key,
    required this.correo,
    required this.docente,
    this.programa,
    this.generacion,
    this.grupo,
    this.materia,
  });

  @override
  State<EvalGrupoScreen> createState() => _EvalGrupoScreenState();
}

class _EvalGrupoScreenState extends State<EvalGrupoScreen> {
  bool _cargando = true;
  String? _error;

  List<Map<String, dynamic>> _porEvaluar = [];
  List<Map<String, dynamic>> _evaluados = [];
  List<Map<String, dynamic>> _dims = [];
  List<Map<String, dynamic>> _abiertas = [];
  List<Map<String, dynamic>> _escala = [];
  String _notaInstrumento = '';

  Map<String, dynamic>? _seleccion;
  Map<String, dynamic>? _perfil;
  bool _cargandoPerfil = false;

  final Map<String, int> _resp = {};
  final Map<String, TextEditingController> _textos = {};
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _textos.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> p) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: p);
    final r = await http.get(uri).timeout(const Duration(seconds: 90));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final preg = await _get({'accion': 'eval_grupo_preguntas'});
      final pend = await _get({
        'accion': 'eval_grupo_pendientes',
        'correo': widget.correo,
      });
      if (!mounted) return;
      setState(() {
        _dims = (preg['dimensiones'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _abiertas = (preg['abiertas'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _escala = (preg['escala'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _notaInstrumento = '${preg['nota'] ?? ''}';
        _porEvaluar = (pend['porEvaluar'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _evaluados = (pend['evaluados'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
      for (final a in _abiertas) {
        _textos.putIfAbsent('${a['id']}', () => TextEditingController());
      }
      // Si entró desde una clase concreta, se abre esa directo.
      if (widget.grupo != null && widget.grupo!.isNotEmpty) {
        _abrir({
          'programa': widget.programa ?? '',
          'generacion': widget.generacion ?? '',
          'grupo': widget.grupo ?? '',
          'materia': widget.materia ?? '',
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrir(Map<String, dynamic> g) async {
    setState(() {
      _seleccion = g;
      _perfil = null;
      _cargandoPerfil = true;
      _resp.clear();
      for (final c in _textos.values) {
        c.clear();
      }
    });
    try {
      final d = await _get({
        'accion': 'eval_grupo_perfil',
        'programa': '${g['programa']}',
        'generacion': '${g['generacion'] ?? ''}',
        'grupo': '${g['grupo']}',
        // El docente no ve su propia evaluación: el perfil sirve para saber
        // lo que otros vieron.
        'excluir': widget.correo,
      });
      if (mounted && d['ok'] == true) setState(() => _perfil = d);
    } catch (_) {
      // sin perfil se puede evaluar igual
    }
    if (mounted) setState(() => _cargandoPerfil = false);
  }

  int _n(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  /// El promedio viene como número con decimal (4.2). Se lee una sola vez
  /// aquí para no repetir el casteo en cada uso.
  double _prom(Map<String, dynamic> d) {
    final v = d['promedio'];
    return v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
  }

  Color _colProm(num p) => p >= 4
      ? const Color(0xFF1E8E3E)
      : (p >= 3 ? cessumGold : const Color(0xFFC62828));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text(_seleccion == null ? 'Mis grupos' : 'Perfil del grupo'),
        leading: _seleccion == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _seleccion = null;
                  _perfil = null;
                }),
              ),
      ),
      body: _cargando
          ? const Padding(
              padding: EdgeInsets.all(12), child: CessumSkeletonList())
          : _error != null
              ? _vistaError()
              : _seleccion == null
                  ? _listaGrupos()
                  : _detalleGrupo(),
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

  // ---------------------------------------------------------------- lista
  Widget _listaGrupos() {
    if (_porEvaluar.isEmpty && _evaluados.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: CessumEmptyState(
          title: 'No tienes grupos asignados',
          subtitle: 'Cuando te asignen una clase, aquí podrás consultar su '
              'perfil y dejar el tuyo.',
          icon: Icons.groups_outlined,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF6EE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CC.goldBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Lo que sabes del grupo le sirve al que sigue',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  _notaInstrumento.isNotEmpty
                      ? _notaInstrumento
                      : 'Esto no califica a tus alumnos ni afecta su '
                          'expediente.',
                  style: const TextStyle(fontSize: 11.5, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_porEvaluar.isNotEmpty) ...[
          _titulo('Por evaluar (${_porEvaluar.length})'),
          for (final g in _porEvaluar) _fichaGrupo(g, false),
          const SizedBox(height: 12),
        ],
        if (_evaluados.isNotEmpty) ...[
          _titulo('Ya evaluaste (${_evaluados.length})'),
          for (final g in _evaluados) _fichaGrupo(g, true),
        ],
      ],
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: cessumRed)),
      );

  Widget _fichaGrupo(Map<String, dynamic> g, bool hecha) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(
            hecha ? Icons.check_circle : Icons.rate_review_outlined,
            color: hecha ? const Color(0xFF1E8E3E) : cessumRed,
            size: 22),
        title: Text('${g['materia']}',
            style:
                const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
            '${g['programa']} · ${g['generacion'] ?? ''} · ${g['grupo']}',
            style: const TextStyle(fontSize: 11.5)),
        trailing: const Icon(Icons.chevron_right, color: Colors.black38),
        onTap: () => _abrir(g),
      ),
    );
  }

  // -------------------------------------------------------------- detalle
  Widget _detalleGrupo() {
    final g = _seleccion!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
      children: [
        Container(
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
              Text('${g['materia']}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 3),
              Text('${g['programa']} · ${g['generacion'] ?? ''} · ${g['grupo']}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_cargandoPerfil)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
                child: CircularProgressIndicator(color: cessumRed)),
          )
        else
          _bloquePerfil(),
        const SizedBox(height: 16),
        _titulo('Tu lectura del grupo'),
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
              'Contesta al menos 3. Cada respuesta dice para qué le sirve al '
              'siguiente profesor.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54)),
        ),
        for (final d in _dims) _preguntaDim(d),
        const SizedBox(height: 8),
        for (final a in _abiertas) _preguntaAbierta(a),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: Text(_guardando ? 'Guardando…' : 'Guardar mi lectura'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
            'Puedes volver a enviarla cuando quieras: se reemplaza la '
            'anterior. Tu lectura de un grupo puede cambiar a mitad del curso.',
            style: TextStyle(fontSize: 11, color: Colors.black45)),
      ],
    );
  }

  /// Lo que otros profesores dejaron. Va ARRIBA del formulario a propósito:
  /// es lo que el docente vino a buscar cuando le asignan un grupo nuevo.
  Widget _bloquePerfil() {
    final p = _perfil;
    if (p == null || _n(p['profesoresQueLoEvaluaron']) == 0) {
      return Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F2ED),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
            'Nadie ha evaluado a este grupo todavía. Si tú lo haces al '
            'terminar tu materia, el siguiente profesor no empezará a ciegas.',
            style: TextStyle(fontSize: 12, height: 1.4)),
      );
    }
    final dims = (p['dimensiones'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final recs = (p['recomendaciones'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titulo('Lo que otros profesores ya saben'),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('${p['resumen'] ?? ''}',
              style: const TextStyle(fontSize: 12, height: 1.35)),
        ),
        for (final d in dims)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _colProm(_prom(d)).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${d['dimension']}',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    Text('${d['promedio']}/5',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _colProm(_prom(d)))),
                  ],
                ),
                const SizedBox(height: 2),
                Text('${d['lectura'] ?? ''}',
                    style: const TextStyle(fontSize: 11.5, height: 1.3)),
                Text('${d['leSirvePara'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.3,
                        fontStyle: FontStyle.italic,
                        color: Colors.black45)),
              ],
            ),
          ),
        if (recs.isNotEmpty) ...[
          const SizedBox(height: 6),
          _titulo('Lo que te dirían'),
          for (final r in recs)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF6EE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: CC.goldBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('“${r['recomendacion']}”',
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontStyle: FontStyle.italic)),
                  const SizedBox(height: 4),
                  Text('${r['docente']} · ${r['materia']}',
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.black45)),
                  if ('${r['funciono'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text('Le funcionó: ${r['funciono']}',
                          style: const TextStyle(
                              fontSize: 11, height: 1.3)),
                    ),
                  if ('${r['costo'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Le costó: ${r['costo']}',
                          style: const TextStyle(
                              fontSize: 11, height: 1.3)),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _preguntaDim(Map<String, dynamic> d) {
    final id = '${d['id']}';
    final sel = _resp[id];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: sel == null ? Colors.black12 : cessumRed.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${d['pregunta']}',
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('${d['leSirvePara'] ?? ''}',
              style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.3,
                  fontStyle: FontStyle.italic,
                  color: Colors.black45)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in _escala)
                InkWell(
                  onTap: () => setState(() => _resp[id] = _n(o['v'])),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel == _n(o['v'])
                          ? cessumRed.withValues(alpha: 0.12)
                          : const Color(0xFFF4F2ED),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel == _n(o['v'])
                              ? cessumRed
                              : Colors.transparent,
                          width: 1.3),
                    ),
                    child: Text('${o['t']}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: sel == _n(o['v'])
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: sel == _n(o['v'])
                                ? cessumRed
                                : Colors.black87)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _preguntaAbierta(Map<String, dynamic> a) {
    final id = '${a['id']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _textos[id],
        maxLines: 3,
        style: const TextStyle(fontSize: 12.5),
        decoration: InputDecoration(
          labelText: '${a['etiqueta']}',
          helperText: '${a['ayuda'] ?? ''}',
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
          alignLabelWithHint: true,
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    if (_resp.length < 3) {
      _aviso('Contesta al menos 3 dimensiones para que el perfil sirva.');
      return;
    }
    final g = _seleccion!;
    setState(() => _guardando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'eval_grupo_guardar',
                'correo': widget.correo,
                'docente': widget.docente,
                'programa': '${g['programa']}',
                'generacion': '${g['generacion'] ?? ''}',
                'grupo': '${g['grupo']}',
                'materia': '${g['materia']}',
                'respuestas': _resp,
                'funciono': _textos['funciono']?.text.trim() ?? '',
                'costo': _textos['costo']?.text.trim() ?? '',
                'recomendacion':
                    _textos['recomendacion']?.text.trim() ?? '',
              }))
          .timeout(const Duration(seconds: 90));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] != true) {
        _aviso('${d['error'] ?? 'No se pudo guardar'}');
      } else {
        _aviso('${d['aviso'] ?? 'Guardado.'}');
        setState(() {
          _seleccion = null;
          _perfil = null;
        });
        await _cargar();
      }
    } catch (e) {
      _aviso('$e');
    }
    if (mounted) setState(() => _guardando = false);
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), duration: const Duration(seconds: 4)));
  }
}
