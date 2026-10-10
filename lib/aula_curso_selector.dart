// =====================================================================
//  aula_curso_selector.dart · CESSUM · App CESSUM · (5-oct-2026)
//
//  SELECTOR DEL CURSO DEL AULA para un recursamiento (autogestivo o
//  cualquiera que pida el curso). En lugar de pegar el enlace a mano:
//   · busca los cursos de Moodle de la materia (la IA descarta los de otra
//     materia con nombre parecido, aunque vengan con clave o generación);
//   · mide qué tan completo está cada uno (tareas, cuestionarios,
//     materiales, secciones con contenido) y PRESELECCIONA el más completo;
//   · cada curso se puede ABRIR en otra pestaña antes de matricular;
//   · si ninguno sirve, se busca otro por nombre.
//  Escribe el enlace elegido en el controlador que recibe (el mismo campo
//  de siempre, que sigue ahí para pegar uno a mano si hace falta).
//  Ruta: GET recurso_cursos_sugeridos&materia=…&programa=…[&q=…]&actor=…
// =====================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';

class AulaCursoSelector extends StatefulWidget {
  final String materia;
  final String programa;
  final TextEditingController link;
  const AulaCursoSelector({super.key, required this.materia, this.programa = '', required this.link});

  @override
  State<AulaCursoSelector> createState() => _AulaCursoSelectorState();
}

class _AulaCursoSelectorState extends State<AulaCursoSelector> {
  bool _cargando = false;
  String _error = '', _nota = '';
  List<Map<String, dynamic>> _cursos = [];
  final _q = TextEditingController();
  Timer? _espera;
  String _ultimaBusqueda = '';
  String _autoLink = '';   // el enlace que puso la preselección (si cambia la materia, se reemplaza)
  bool _liberarAuto = false;

  static const Color _verde = Color(0xFF1E8E3E);

  @override
  void initState() {
    super.initState();
    widget.link.addListener(_alCambiarLink);
    _programar();
  }

  @override
  void didUpdateWidget(covariant AulaCursoSelector old) {
    super.didUpdateWidget(old);
    if (old.link != widget.link) {
      old.link.removeListener(_alCambiarLink);
      widget.link.addListener(_alCambiarLink);
    }
    if (old.materia.trim() != widget.materia.trim()) {
      // Si el enlace lo había puesto la preselección, se libera para la materia nueva; lo elegido a mano se respeta.
      _liberarAuto = true;   // se aplica en la búsqueda (fuera del dibujado), no aquí
      _programar();
    }
  }

  @override
  void dispose() {
    widget.link.removeListener(_alCambiarLink);
    _espera?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _alCambiarLink() {
    if (mounted) setState(() {});
  }

  /// Espera a que se deje de escribir la materia antes de buscar.
  void _programar() {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 700), () => _buscar());
  }

  Future<void> _buscar({String q = ''}) async {
    final materia = widget.materia.trim();
    if (q.isEmpty && materia.length < 3) {
      if (mounted) setState(() { _cursos = []; _nota = ''; _error = ''; });
      return;
    }
    if (_liberarAuto) {
      _liberarAuto = false;
      if (_autoLink.isNotEmpty && widget.link.text.trim() == _autoLink) widget.link.text = '';
    }
    final clave = '$materia|$q';
    if (clave == _ultimaBusqueda && _cursos.isNotEmpty) return;
    _ultimaBusqueda = clave;
    setState(() { _cargando = true; _error = ''; });
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'recurso_cursos_sugeridos', 'materia': materia, 'programa': widget.programa, if (q.isNotEmpty) 'q': q, 'actor': actor,
          }))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo buscar.');
      if (!mounted) return;
      final l = ((d['cursos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _cursos = l;
        _nota = '${d['nota'] ?? ''}';
        _cargando = false;
        // Preselecciona el recomendado si todavía no hay enlace.
        if (widget.link.text.trim().isEmpty && l.isNotEmpty) {
          final rec = l.firstWhere((c) => c['recomendado'] == true, orElse: () => l.first);
          widget.link.text = '${rec['link']}';
          _autoLink = widget.link.text;
        }
      });
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _abrir(String url) async {
    await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  }

  Widget _chip(String t, {Color? c}) => Container(
        margin: const EdgeInsets.only(right: 5, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: (c ?? cessumMuted(context)).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c ?? cessumMuted(context))),
      );

  @override
  Widget build(BuildContext context) {
    final elegido = widget.link.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.auto_awesome, size: 16, color: cessumGold),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            widget.materia.trim().isEmpty ? 'Elige la materia y te sugiero el curso del aula.' : 'Cursos del aula para «${widget.materia.trim()}»',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
        if (_cargando) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      if (_nota.isNotEmpty && !_cargando) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_nota, style: TextStyle(fontSize: 11.5, color: cessumMuted(context)))),
      if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error, style: const TextStyle(fontSize: 11.5, color: cessumRed))),
      const SizedBox(height: 6),
      if (_cursos.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView(shrinkWrap: true, children: [
            for (final c in _cursos)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: elegido == '${c['link']}' ? cessumRed : Theme.of(context).dividerColor, width: elegido == '${c['link']}' ? 1.6 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => widget.link.text = '${c['link']}'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(elegido == '${c['link']}' ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: cessumRed),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${c['nombre']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                          Text('${c['categoria']} · ${c['inscritos']} inscrito(s)${c['modificado'] != '' ? ' · modificado ${c['modificado']}' : ''}',
                              style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                          Wrap(children: [
                            if (c['recomendado'] == true) _chip('★ Recomendado: el más completo', c: _verde),
                            _chip('${c['tareas']} tarea(s)'),
                            _chip('${c['cuestionarios']} cuestionario(s)'),
                            _chip('${c['materiales']} material(es)'),
                            _chip('${c['secciones']} sección(es) con contenido'),
                            if (c['visible'] != true) _chip('oculto a los alumnos', c: cessumRed),
                          ]),
                          if ('${c['motivo'] ?? ''}'.isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 3), child: Text('${c['motivo']}', style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: cessumMuted(context)))),
                        ]),
                      ),
                      TextButton.icon(
                        onPressed: () => _abrir('${c['link']}'),
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: const Text('Abrir', style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => _buscar(q: v.trim()),
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: '¿No es ninguno? Busca otro curso por nombre', border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: 6),
        OutlinedButton(onPressed: _cargando ? null : () => _buscar(q: _q.text.trim()), child: const Text('Buscar')),
      ]),
      const SizedBox(height: 8),
    ]);
  }
}
