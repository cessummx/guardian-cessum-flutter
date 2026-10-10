// ADMIN: Seguimiento docente (ago-2026). Ranking de desempeño en revisiones:
// puntaje = 70% revisar en tiempo y forma (dentro de 24 h) + 30% revisar
// aunque sea tarde. Pensado para irse alimentando con más dimensiones.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';

class SeguimientoDocenteScreen extends StatefulWidget {
  const SeguimientoDocenteScreen({super.key});

  @override
  State<SeguimientoDocenteScreen> createState() =>
      _SeguimientoDocenteScreenState();
}

class _SeguimientoDocenteScreenState extends State<SeguimientoDocenteScreen> {
  bool _cargando = true;
  String _error = '';
  String _corte = '';
  /// Umbrales y advertencias de lectura del escalafón, servidos por el
  /// backend para que la leyenda y el cálculo nunca se separen.
  Map<String, dynamic>? _reglas;
  String _filtro = '';
  List<Map<String, dynamic>> _ranking = [];

  /// (ago-17) Orden y filtro por nivel. El backend entrega ordenado por
  /// integral, pero para trabajar hace falta poder ver "quién tiene más
  /// pendientes" o "quiénes están en Inicial", que son otras preguntas.
  String _orden = 'puntaje';
  String _nivelSel = 'Todos';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=seguimiento_docentes'))
          .timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _ranking = ((d['ranking'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _corte = (d['corte'] ?? '').toString();
        _reglas = d['reglas'] is Map
            ? Map<String, dynamic>.from(d['reglas'] as Map)
            : null;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _registrarObservacion() async {
    // Elegir docente del ranking (ya cargado) con buscador.
    Map<String, dynamic>? doc;
    if (_ranking.isNotEmpty) {
      doc = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) {
          var filtro = '';
          return StatefulBuilder(builder: (ctx, setLocal) {
            final vis = _ranking.where((r) {
              if (filtro.isEmpty) return true;
              return '${r['docente']} ${r['correo']}'
                  .toLowerCase()
                  .contains(filtro.toLowerCase());
            }).toList();
            return AlertDialog(
              title: const Text('¿A qué docente observaste?'),
              content: SizedBox(
                width: 460,
                height: 380,
                child: Column(children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 18),
                        hintText: 'Buscar docente…',
                        isDense: true,
                        border: OutlineInputBorder()),
                    onChanged: (v) => setLocal(() => filtro = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(children: [
                      for (final r in vis)
                        ListTile(
                          dense: true,
                          title: Text('${r['docente']}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text('${r['correo']}',
                              style: const TextStyle(fontSize: 11)),
                          onTap: () => Navigator.pop(ctx, r),
                        ),
                    ]),
                  ),
                ]),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar')),
              ],
            );
          });
        },
      );
      if (doc == null) return;
    }
    if (!mounted) return;
    final correoCtrl =
        TextEditingController(text: (doc?['correo'] ?? '').toString());
    final materiaCtrl = TextEditingController();
    final durCtrl = TextEditingController();
    final fortCtrl = TextEditingController();
    final recCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(doc == null
            ? 'Registrar observación'
            : 'Observación de ${doc['docente']}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (doc == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                      controller: correoCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Correo del docente',
                          border: OutlineInputBorder(),
                          isDense: true)),
                ),
              TextField(
                  controller: materiaCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Materia / sesión observada',
                      border: OutlineInputBorder(),
                      isDense: true)),
              const SizedBox(height: 8),
              TextField(
                  controller: durCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Duración real de la sesión (minutos)',
                      hintText: 'Mínimo institucional: 50',
                      border: OutlineInputBorder(),
                      isDense: true)),
              const SizedBox(height: 8),
              TextField(
                  controller: fortCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Fortalezas observadas',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      isDense: true)),
              const SizedBox(height: 8),
              TextField(
                  controller: recCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Recomendaciones de mejora',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      isDense: true)),
              const SizedBox(height: 6),
              const Text(
                  'El docente recibirá aviso y la verá completa en su '
                  '"Mi informe de evaluación".',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar')),
        ],
      ),
    );
    if (ok != true) return;
    final quien = await SessionStore.validEmail();
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'observacion_registrar',
                'correoDocente': correoCtrl.text.trim(),
                'materia': materiaCtrl.text.trim(),
                'duracionMin': durCtrl.text.trim(),
                'fortalezas': fortCtrl.text.trim(),
                'recomendaciones': recCtrl.text.trim(),
                'observador': quien ?? '',
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: d['ok'] == true
              ? const Color(0xFF1E8E3E)
              : cessumRed,
          content: Text(d['ok'] == true
              ? 'Observación registrada; el docente ya puede verla en su informe.'
              : '${d['error']}')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('Error: $e')));
      }
    }
  }

  // ---------- Lecturas seguras de cada renglón ----------
  num? _pt(Map r) => (r['puntajeIntegral'] ?? r['puntaje']) as num?;

  String _nivelDe(Map r) => (r['escalafon'] is Map)
      ? '${(r['escalafon'] as Map)['nivel'] ?? 'Sin historial'}'
      : 'Sin historial';

  int _entero(Map r, String k) =>
      (r[k] is num) ? (r[k] as num).toInt() : 0;

  /// Panorama de toda la planta, antes de la lista. Un ranking sin agregados
  /// obliga a contar tarjetas a mano para saber cómo va la institución.
  Widget _resumen() {
    if (_ranking.isEmpty) return const SizedBox.shrink();
    final conPuntaje =
        _ranking.where((r) => _pt(r) != null).toList();
    final prom = conPuntaje.isEmpty
        ? null
        : (conPuntaje.fold<num>(0, (a, r) => a + (_pt(r) ?? 0)) /
                conPuntaje.length)
            .round();
    final sinRevisar =
        _ranking.fold<int>(0, (a, r) => a + _entero(r, 'sinRevisar'));
    final docsConAtraso =
        _ranking.where((r) => _entero(r, 'sinRevisar') > 0).length;
    final porNivel = <String, int>{};
    for (final r in _ranking) {
      final n = _nivelDe(r);
      porNivel[n] = (porNivel[n] ?? 0) + 1;
    }
    final orden = [
      'Titular', 'Consolidado', 'En desarrollo', 'Inicial', 'Sin historial'
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('La planta docente hoy',
              style: CessumType.heading(13, color: cessumInk(context))),
          const SizedBox(height: 8),
          Row(children: [
            _cifra('${_ranking.length}', 'docentes'),
            _cifra(prom == null ? '—' : '$prom', 'promedio'),
            _cifra('$docsConAtraso', 'con atrasos',
                rojo: docsConAtraso > 0),
            _cifra('$sinRevisar', 'entregas sin revisar',
                rojo: sinRevisar > 0),
          ]),
          const SizedBox(height: 10),
          // Distribución por nivel, en barra proporcional.
          Row(
            children: [
              for (final n in orden)
                if ((porNivel[n] ?? 0) > 0)
                  Expanded(
                    flex: porNivel[n]!,
                    child: Container(
                      height: 8,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: _colorNivel(n),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              for (final n in orden)
                if ((porNivel[n] ?? 0) > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: _colorNivel(n), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('$n ${porNivel[n]}',
                        style: TextStyle(
                            fontSize: 10.5, color: cessumMuted(context))),
                  ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cifra(String valor, String etiqueta, {bool rojo = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: rojo ? const Color(0xFFC62828) : cessumRed)),
          Text(etiqueta,
              style: TextStyle(fontSize: 10, color: cessumMuted(context))),
        ],
      ),
    );
  }

  /// Filtro por nivel y criterio de orden.
  Widget _controles() {
    final niveles = <String>['Todos'];
    for (final n in [
      'Titular', 'Consolidado', 'En desarrollo', 'Inicial', 'Sin historial'
    ]) {
      if (_ranking.any((r) => _nivelDe(r) == n)) niveles.add(n);
    }
    Widget chip(String txt, bool sel, VoidCallback onTap, Color color) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(txt),
            selected: sel,
            selectedColor: color.withValues(alpha: 0.16),
            labelStyle: TextStyle(
              fontSize: 11.5,
              color: sel ? color : cessumMuted(context),
              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            ),
            onSelected: (_) => onTap(),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final n in niveles)
              chip(n, _nivelSel == n, () => setState(() => _nivelSel = n),
                  n == 'Todos' ? cessumRed : _colorNivel(n)),
          ]),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Text('Ordenar por  ',
                style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            chip('Puntaje', _orden == 'puntaje',
                () => setState(() => _orden = 'puntaje'), cessumRed),
            chip('Sin revisar', _orden == 'pendientes',
                () => setState(() => _orden = 'pendientes'), cessumRed),
            chip('Nombre', _orden == 'nombre',
                () => setState(() => _orden = 'nombre'), cessumRed),
          ]),
        ),
      ],
    );
  }

  /// (ago-17) PLAN DE MEJORA de un docente. El ranking dice cuánto; esto dice
  /// qué hacer, con el objeto concreto, la fecha y cómo se verifica. No envía
  /// nada: devuelve el texto para que Vicerrectoría decida.
  Future<void> _plan(Map<String, dynamic> r) async {
    final correo = '${r['correo'] ?? ''}';
    if (correo.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: cessumRed)),
    );
    Map<String, dynamic>? d;
    String err = '';
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=docente_plan'
              '&correo=${Uri.encodeComponent(correo)}'))
          .timeout(const Duration(seconds: 90));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['ok'] != true) {
        err = '${j['error'] ?? 'No se pudo generar el plan.'}';
      } else {
        d = j;
      }
    } catch (e) {
      err = '$e';
    }
    if (!mounted) return;
    Navigator.pop(context); // cierra el spinner
    if (d == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err), backgroundColor: cessumRed));
      return;
    }
    final tareas = (d['tareas'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final mensaje = '${d['mensaje'] ?? ''}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Plan de mejora · ${d!['docente']}',
            style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 560,
          height: 460,
          child: ListView(
            children: [
              Text(
                  'Integral ${d['integral'] ?? '—'}'
                  '${d['bonoProgramacion'] != null && (d['bonoProgramacion'] as num) > 0 ? ' (incluye +${d['bonoProgramacion']} de bono)' : ''}'
                  ' · ${d['nivel'] ?? ''}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              if (d['meta'] is Map &&
                  (d['meta'] as Map)['mensaje'] != null) ...[
                const SizedBox(height: 6),
                Text('${(d['meta'] as Map)['mensaje']}',
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 12),
              if (tareas.isEmpty)
                Text('${d['nota'] ?? ''}',
                    style: const TextStyle(fontSize: 13)),
              for (var i = 0; i < tareas.length; i++)
                _fichaTarea(tareas[i], i + 1),
              if (mensaje.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Mensaje sugerido',
                    style: CessumType.heading(12.5, color: cessumInk(context))),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(mensaje,
                      style: const TextStyle(fontSize: 12, height: 1.45)),
                ),
                const SizedBox(height: 6),
                Text(
                    'Nada se envió. Revísalo, ajústalo y decide tú si lo mandas.',
                    style: TextStyle(
                        fontSize: 11, color: cessumMuted(context))),
              ],
            ],
          ),
        ),
        actions: [
          if (mensaje.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: mensaje));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mensaje copiado.')));
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copiar mensaje'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _fichaTarea(Map<String, dynamic> t, int n) {
    final gana = t['ganaPuntos'];
    final urgente = '${t['dimension']}' == 'revision';
    final color = urgente ? cessumRed : cessumGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text('$n',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${t['tarea']}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${t['porQue']}',
              style: TextStyle(
                  fontSize: 11.5, height: 1.4, color: cessumMuted(context))),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 4, children: [
            _dato('📅 Para el', '${t['para']}', color),
            if (gana is num && gana > 0)
              _dato('📈 Ganaría', '+$gana pts', const Color(0xFF1E8E3E)),
          ]),
          const SizedBox(height: 4),
          Text('Se verifica: ${t['comoSeVerifica']}',
              style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: cessumMuted(context))),
        ],
      ),
    );
  }

  /// (ago-18) Qué sumó y qué restó, con su motivo. Va aparte de las ocho
  /// dimensiones a propósito: las dimensiones miden cómo trabaja; esto
  /// registra hechos puntuales, y son los únicos números que el docente puede
  /// impugnar señalando un caso concreto.
  Widget _ajustes(List<Map<String, dynamic>> lista) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: cessumBg(context),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ajustes sobre el promedio',
              style: CessumType.heading(12, color: cessumInk(context))),
          const SizedBox(height: 2),
          Text(
              'Hechos puntuales, no promedios. Nadie baja de 0 ni pasa de 100.',
              style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
          const SizedBox(height: 8),
          for (final a in lista)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 44,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (a['signo'] == '+'
                            ? const Color(0xFF1E8E3E)
                            : const Color(0xFFC62828))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${a['signo']}${a['puntos']}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: a['signo'] == '+'
                              ? const Color(0xFF1E8E3E)
                              : const Color(0xFFC62828))),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a['etiqueta']}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('${a['detalle']}',
                          style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: cessumMuted(context))),
                    ],
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Color _colorPuntaje(num? p) {
    if (p == null) return Colors.black38;
    if (p >= 90) return const Color(0xFF1E8E3E);
    if (p >= 75) return const Color(0xFF7CB342);
    if (p >= 50) return cessumGold;
    return cessumRed;
  }

  /// (ago-12) LAS REGLAS, A LA VISTA. El escalafón etiquetaba a la gente sin
  /// decir con qué criterio, y eso lo vuelve un juicio en vez de una guía.
  /// Aquí van los umbrales, qué significa cada nivel, qué hacer con quien
  /// está ahí, y las advertencias de lectura — sobre todo la de no comparar
  /// a alguien medido sobre tres factores con alguien medido sobre seis.
  Widget _leyendaEscalafon() {
    final reglas = _reglas;
    if (reglas == null) return const SizedBox.shrink();
    final niveles = (reglas['niveles'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final advert = (reglas['advertencias'] as List? ?? []).cast<dynamic>();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFBF6EE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CC.goldBorder),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: const Icon(Icons.rule, size: 20, color: cessumGold),
          title: const Text('Cómo se lee este escalafón',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          subtitle: const Text('Umbrales, qué significa cada nivel y qué hacer',
              style: TextStyle(fontSize: 11, color: Colors.black54)),
          children: [
            if ('${reglas['comoSeCalcula'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${reglas['comoSeCalcula']}',
                    style: const TextStyle(fontSize: 11.5, height: 1.4)),
              ),
            if ('${reglas['factores'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('${reglas['factores']}',
                    style: const TextStyle(fontSize: 11.5, height: 1.4)),
              ),
            for (final n in niveles)
              Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _colorNivel('${n['nivel']}')
                          .withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${n['emoji'] ?? ''} ',
                            style: const TextStyle(fontSize: 14)),
                        Text('${n['nivel']}',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: _colorNivel('${n['nivel']}'))),
                        const Spacer(),
                        Text('${n['umbral'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.black54)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('${n['significa'] ?? ''}',
                        style: const TextStyle(fontSize: 11.5, height: 1.3)),
                    if ('${n['queHacer'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('→ ${n['queHacer']}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.3,
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
            if (advert.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final a in advert)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('· ',
                          style: TextStyle(fontSize: 11.5)),
                      Expanded(
                        child: Text('$a',
                            style: const TextStyle(
                                fontSize: 11,
                                height: 1.35,
                                fontStyle: FontStyle.italic,
                                color: Colors.black54)),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Color _colorNivel(String n) => n == 'Sin base suficiente'
      ? const Color(0xFF7E57C2)
      : n == 'Titular'
      ? const Color(0xFFB8860B)
      : n == 'Consolidado'
          ? const Color(0xFF6A1B9A)
          : n == 'En desarrollo'
              ? const Color(0xFF1565C0)
              // (ago-9) "Sin historial" en gris, NO en verde. Antes caía en el
              // mismo color que "Inicial" y parecía una calificación baja;
              // es lo contrario: todavía no hay con qué calificarlo.
              : n == 'Sin historial'
                  ? const Color(0xFF757575)
                  : const Color(0xFF2E7D32);

  /// (ago-9) Desglose de las seis dimensiones. Un número solo —"integral 82"—
  /// no le dice al docente qué mejorar ni a Vicerrectoría en qué apoyarlo.
  /// Aquí se ve de dónde sale cada punto, y qué factores no se midieron.
  Widget _dimensiones(Map r) {
    final dims = (r['dimensiones'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (dims.isEmpty) return const SizedBox.shrink();
    final pesoEval = r['pesoEvaluado'] is num
        ? (r['pesoEvaluado'] as num).toInt()
        : 100;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 6),
          leading: const Icon(Icons.donut_small, size: 18, color: cessumRed),
          title: Text('De dónde sale su puntaje (${dims.length} factores)',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
          subtitle: pesoEval < 100
              ? Text('Calculado sobre el $pesoEval% de los factores',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFFC62828)))
              : null,
          children: [
            for (final d in dims) _filaDimension(d),
            if ('${r['notaIntegral'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${r['notaIntegral']}',
                    style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        fontStyle: FontStyle.italic,
                        color: Colors.black54)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filaDimension(Map<String, dynamic> d) {
    final cuenta = d['cuenta'] == true;
    final valor = d['valor'];
    final v = valor is num ? valor.toDouble() : null;
    // Color por desempeño, no por dimensión: lo que importa a simple vista es
    // dónde está flojo.
    final col = !cuenta
        ? Colors.black26
        : (v == null
            ? Colors.black26
            : (v >= 85
                ? const Color(0xFF1E8E3E)
                : (v >= 65 ? cessumGold : const Color(0xFFC62828))));
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(cuenta && v != null ? '${v.round()}' : '—',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: col)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${d['etiqueta']}',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: cuenta
                                  ? Colors.black87
                                  : Colors.black45)),
                    ),
                    Text('${d['peso']}%',
                        style: const TextStyle(
                            fontSize: 10.5, color: Colors.black38)),
                  ],
                ),
                if (cuenta && v != null) ...[
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (v / 100).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: const Color(0xFFEEEAE2),
                      valueColor: AlwaysStoppedAnimation<Color>(col),
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                    cuenta
                        ? '${d['detalle'] ?? ''}'
                        : '${d['detalle'] ?? ''} · no cuenta para el puntaje',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: cuenta ? Colors.black54 : Colors.black38)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _medalla(int lugar) =>
      lugar == 1 ? '🥇' : lugar == 2 ? '🥈' : lugar == 3 ? '🥉' : '$lugar°';

  @override
  Widget build(BuildContext context) {
    final vis = _ranking.where((r) {
      if (_nivelSel != 'Todos' && _nivelDe(r) != _nivelSel) return false;
      if (_filtro.isEmpty) return true;
      return '${r['docente']} ${r['correo']}'
          .toLowerCase()
          .contains(_filtro.toLowerCase());
    }).toList();
    // El lugar en el ranking se calcula SIEMPRE contra la lista completa
    // ordenada por puntaje: filtrar por nivel no debe renumerar a nadie.
    final porPuntaje = [..._ranking]..sort((a, b) {
        final pa = _pt(a) ?? -1, pb = _pt(b) ?? -1;
        return pb.compareTo(pa);
      });
    if (_orden == 'nombre') {
      vis.sort((a, b) => '${a['docente']}'
          .toLowerCase()
          .compareTo('${b['docente']}'.toLowerCase()));
    } else if (_orden == 'pendientes') {
      vis.sort((a, b) =>
          _entero(b, 'sinRevisar').compareTo(_entero(a, 'sinRevisar')));
    } else {
      vis.sort((a, b) {
        final pa = _pt(a) ?? -1, pb = _pt(b) ?? -1;
        return pb.compareTo(pa);
      });
    }
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Seguimiento docente',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _registrarObservacion,
        icon: const Icon(Icons.rate_review),
        label: const Text('Registrar observación'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      // (ago-12) Este texto decía "70% en tiempo + 30% tarde",
                      // que era el criterio VIEJO de dos factores. El puntaje
                      // ya es de seis dimensiones, así que la pantalla estaba
                      // explicando una regla que ya no se usa.
                      Text('Corte al $_corte.',
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.black54)),
                      const SizedBox(height: 8),
                      _resumen(),
                      const SizedBox(height: 10),
                      _leyendaEscalafon(),
                      const SizedBox(height: 10),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search, size: 18),
                          hintText: 'Buscar docente…',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _filtro = v),
                      ),
                      const SizedBox(height: 8),
                      _controles(),
                      const SizedBox(height: 6),
                      if (vis.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                              'Mostrando ${vis.length} de ${_ranking.length}',
                              style: TextStyle(
                                  fontSize: 11, color: cessumMuted(context))),
                        ),
                      if (vis.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                              'Sin datos todavía: el seguimiento se alimenta '
                              'de la hoja de revisiones (corre el escaneo).',
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.black54)),
                        ),
                      for (var i = 0; i < vis.length; i++)
                        _tarjeta(vis[i], porPuntaje.indexOf(vis[i]) + 1),
                    ],
                  ),
                ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> r, int lugar) {
    final p = (r['puntajeIntegral'] ?? r['puntaje']) as num?;
    final c = _colorPuntaje(p);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: c.withValues(alpha: 0.5),
            width: lugar <= 3 ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_medalla(lugar),
                style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r['docente']}',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text('${r['correo']}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(p == null ? '—' : '$p',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: c)),
                const Text('puntos',
                    style:
                        TextStyle(fontSize: 10, color: Colors.black45)),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: p == null ? 0 : (p / 100).clamp(0, 1).toDouble(),
              minHeight: 7,
              backgroundColor: Colors.black12,
              color: c,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _dato('✅ En tiempo', '${r['enTiempo']}',
                  const Color(0xFF1E8E3E)),
              _dato('🕐 Tarde', '${r['tarde']}', cessumGold),
              _dato('🔴 Sin revisar', '${r['sinRevisar']}', cessumRed),
              _dato('⏳ En plazo', '${r['pendientesVivas']}',
                  Colors.black45),
              if (r['pctEnTiempo'] != null)
                _dato('% en tiempo y forma', '${r['pctEnTiempo']}%',
                    Colors.black87),
              if (r['evalPromedio'] != null)
                _dato(
                    '🎓 Eval. estudiantil',
                    '${r['evalPromedio']} (${r['evalRespuestas']} resp.)',
                    const Color(0xFF6A1B9A)),
              if (r['puntajeIntegral'] != null)
                _dato('⭐ Integral', '${r['puntajeIntegral']}',
                    Colors.black87),
              // (ago-18) Los ajustes se muestran uno por uno, con su signo.
              // Un puntaje que sube o baja sin decir por qué se lee como
              // arbitrario, y estos son justo los que el docente puede
              // discutir: son hechos, no promedios.
              if (r['sumaAjustes'] is num && (r['sumaAjustes'] as num) != 0)
                _dato(
                    (r['sumaAjustes'] as num) > 0 ? '➕ Ajustes' : '➖ Ajustes',
                    '${(r['sumaAjustes'] as num) > 0 ? '+' : ''}${r['sumaAjustes']} pts sobre el promedio',
                    (r['sumaAjustes'] as num) > 0
                        ? const Color(0xFF00695C)
                        : const Color(0xFFC62828)),
              if (r['pesoEvaluado'] is num &&
                  (r['pesoEvaluado'] as num) < 100)
                _dato('⚠️ Medido sobre', '${r['pesoEvaluado']}% de los factores',
                    const Color(0xFFC62828)),
            ],
          ),
          if (r['escalafon'] is Map)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _colorNivel(
                          '${(r['escalafon'] as Map)['nivel']}')
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _colorNivel(
                              '${(r['escalafon'] as Map)['nivel']}')
                          .withValues(alpha: 0.5)),
                ),
                child: Text(
                  '${(r['escalafon'] as Map)['emoji']} Escalafón: '
                  '${(r['escalafon'] as Map)['nivel']}'
                  '${(r['escalafon'] as Map)['promedio4'] != null ? ' · prom. 4 sem: ${(r['escalafon'] as Map)['promedio4']}' : ''}'
                  '${(r['escalafon'] as Map)['tendencia'] == 'sube' ? ' ▲' : (r['escalafon'] as Map)['tendencia'] == 'baja' ? ' ▼' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _colorNivel(
                          '${(r['escalafon'] as Map)['nivel']}')),
                ),
              ),
            ),
          // (ago-18) Quien no tiene base suficiente no se compara con nadie.
          // Decirlo en la tarjeta evita que alguien lea el número como un
          // juicio cuando lo único que dice es que faltan datos.
          if (r['baseSuficiente'] == false)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF7E57C2).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF7E57C2).withValues(alpha: 0.35)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.balance, size: 18, color: Color(0xFF7E57C2)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Fuera de la clasificación por ahora: su puntaje se '
                      'calculó sobre ${r['pesoEvaluado'] ?? '—'} de 100 puntos '
                      'de peso. No es un puntaje bajo, es que todavía no hay '
                      'con qué compararlo.',
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: cessumInk(context))),
                ),
              ]),
            ),
          // El desglose de cada ajuste, para que se pueda revisar hecho por
          // hecho en lugar de discutir un total.
          if (r['ajustes'] is List && (r['ajustes'] as List).isNotEmpty)
            _ajustes((r['ajustes'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()),
          if (r['dimensiones'] is List) _dimensiones(r),
          if (r['checklist'] is Map) _checklist(r['checklist'] as Map),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: cessumRed,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _plan(r),
                icon: const Icon(Icons.checklist_rtl, size: 16),
                label: const Text('Plan de mejora',
                    style: TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: cessumGold,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _revisionAulas(r),
                icon: const Icon(Icons.class_outlined, size: 16),
                label: const Text('Revisión de aulas',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // (ago-3) Checklist automático de elementos de forma: la plataforma
  // revisa sola y palomea lo que el docente debe poseer para una buena
  // calificación. Expandible por profesor.
  // (ago-5) REVISIÓN DE AULAS: la plataforma entra a aula.cessum.mx y
  // palomea sola los recursos de cada aula vigente del docente (visible,
  // programa/carta, foro, tareas, fechas, materiales).
  Future<void> _revisionAulas(Map<String, dynamic> r) async {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
          child: FutureBuilder<Map<String, dynamic>>(
            future: () async {
              final uri = Uri.parse(guardianUrl).replace(queryParameters: {
                'accion': 'aula_revision',
                'correo': (r['correo'] ?? '').toString(),
              });
              final resp = await http
                  .get(uri)
                  .timeout(const Duration(seconds: 120));
              return jsonDecode(resp.body) as Map<String, dynamic>;
            }(),
            builder: (ctx2, snap) {
              Widget cuerpo;
              if (!snap.hasData) {
                cuerpo = const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: cessumRed),
                      SizedBox(height: 12),
                      Text('Revisando sus aulas en aula.cessum.mx…',
                          style: TextStyle(fontSize: 12.5)),
                    ])));
              } else if (snap.data!['ok'] != true) {
                cuerpo = Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error: ${snap.data!['error']}',
                        style: const TextStyle(color: cessumRed)));
              } else {
                final aulas = ((snap.data!['aulas'] as List?) ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                cuerpo = aulas.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Sin aulas vigentes de este docente.'))
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(14),
                        children: [
                          for (final a in aulas) ...[
                            Text(
                                '${a['materia']}  ·  ${a['cumplidos']} de ${a['aplicables']} ✓',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: a['cumplidos'] == a['aplicables']
                                        ? const Color(0xFF1E8E3E)
                                        : cessumRed)),
                            Text('${a['grupos']}',
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.black45)),
                            const SizedBox(height: 4),
                            for (final it in (a['items'] as List))
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 2),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(it['ok'] == true ? '✅ ' : '⬜ ',
                                          style: const TextStyle(
                                              fontSize: 12)),
                                      Expanded(
                                        child: Text(
                                            '${it['titulo']}'
                                            '${(it['detalle'] ?? '').toString().isNotEmpty ? ' — ${it['detalle']}' : ''}',
                                            style: TextStyle(
                                                fontSize: 11.5,
                                                height: 1.35,
                                                color: it['ok'] == true
                                                    ? Colors.black87
                                                    : const Color(
                                                        0xFFB11D29))),
                                      ),
                                    ]),
                              ),
                            const Divider(height: 18),
                          ],
                        ],
                      );
              }
              return Column(children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: cessumRed,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                          '🏫 Revisión de aulas · ${r['docente']}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close,
                            color: Colors.white)),
                  ]),
                ),
                Expanded(child: cuerpo),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _checklist(Map ck) {
    final cumplidos = (ck['cumplidos'] ?? 0) as num;
    final aplicables = (ck['aplicables'] ?? 0) as num;
    final items = ((ck['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final completo = aplicables > 0 && cumplidos >= aplicables;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        title: Row(
          children: [
            Icon(completo ? Icons.verified : Icons.checklist,
                size: 16,
                color: completo ? const Color(0xFF1E8E3E) : cessumGold),
            const SizedBox(width: 6),
            Text(
              'Elementos de forma: $cumplidos de $aplicables ✓',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color:
                      completo ? const Color(0xFF1E8E3E) : cessumGold),
            ),
          ],
        ),
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    it['cumple'] == true
                        ? '✅'
                        : it['cumple'] == false
                            ? '⬜'
                            : '➖',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${it['etiqueta']}',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: it['cumple'] == false
                                    ? cessumRed
                                    : Colors.black87)),
                        if ((it['detalle'] ?? '').toString().isNotEmpty)
                          Text('${it['detalle']}',
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.black45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dato(String etiqueta, String valor, Color c) {
    return Text('$etiqueta: $valor',
        style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w600, color: c));
  }
}
