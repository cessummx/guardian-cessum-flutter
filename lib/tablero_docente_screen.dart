import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'mis_interacciones_screen.dart';

/// Tablero del docente: el profesor ve sus materias, las calificaciones que
/// ha puesto, su % de aprobación y el promedio de su evaluación docente.
class TableroDocenteScreen extends StatefulWidget {
  final String correo;
  const TableroDocenteScreen({super.key, required this.correo});

  @override
  State<TableroDocenteScreen> createState() => _TableroDocenteScreenState();
}

class _TableroDocenteScreenState extends State<TableroDocenteScreen> {
  Map<String, dynamic>? _retro;
  Map<String, dynamic>? _d;
  bool _cargando = true;
  String? _error;

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
      final uri = Uri.parse(
          '$guardianUrl?accion=tablero_docente&correo=${Uri.encodeComponent(widget.correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      // (ago-5) Desglose integral en la PANTALLA PRINCIPAL: evaluaciones,
      // lugar en el ranking, oportunidades y retroalimentación.
      try {
        final rr = await http
            .get(Uri.parse(guardianUrl).replace(queryParameters: {
              'accion': 'docente_retro',
              'correo': widget.correo,
            }))
            .timeout(const Duration(seconds: 90));
        final dr = jsonDecode(rr.body) as Map<String, dynamic>;
        if (dr['ok'] == true) _retro = dr;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _d = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar tu tablero.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi desempeño',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : _contenido(),
    );
  }

  Widget _contenido() {
    final d = _d!;
    final cal = (d['calificaciones'] ?? {}) as Map<String, dynamic>;
    final ev = (d['evaluacion'] ?? {}) as Map<String, dynamic>;
    final materias = (d['materias'] as List?) ?? [];
    final porMateria = (cal['porMateria'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Hola, ${d['nombre']}',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: cessumRed)),
        const SizedBox(height: 12),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 150,
          ),
          children: [
            _kpi('Materias asignadas', '${materias.length}',
                Icons.menu_book, cessumRed),
            _kpi('Calificaciones puestas', '${cal['total'] ?? 0}',
                Icons.grading, cessumGold,
                sub: '${cal['enValidacion'] ?? 0} en validación'),
            _kpi('Aprobación', '${cal['aprobacion'] ?? 0}%',
                Icons.verified, const Color(0xFF1E8E3E)),
            // (ago-12) LA ESCALA, SIEMPRE VISIBLE. El número salía solo
            // —"5.32"— y una docente entendió que era sobre 10 y que estaba
            // reprobada, cuando el cuestionario va de 1 a 5. Un puntaje sin
            // su escala no es información: es un susto.
            _kpi(
                'Mi evaluación',
                _retro?['evalPromedio'] != null
                    ? '${_retro!['evalPromedio']} / 10'
                    : '${ev['promedioMediacion'] ?? 0} / 5',
                Icons.star,
                cessumGold,
                sub: _retro?['evalPromedio'] != null
                    ? '${_retro!['evalRespuestas']} respuestas · lugar ${_retro!['lugar']} de ${_retro!['deTotal']}'
                    : '${ev['respuestas'] ?? 0} respuestas'),
          ],
        ),
        const SizedBox(height: 8),
        // (4-oct-2026) Acceso directo al informe de interacciones: es parte de su escalafón (bono que solo suma).
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MisInteraccionesScreen(correo: widget.correo))),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cessumRed,
              borderRadius: BorderRadius.circular(14),
              border: const Border(bottom: BorderSide(color: cessumGold, width: 4)),
            ),
            child: Row(children: [
              const Icon(Icons.forum_outlined, color: Colors.white),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mis interacciones de clase', style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Tus clases analizadas, tu histórico y lo que suma a tu escalafón', style: TextStyle(color: Color(0xFFF7DCDC), fontSize: 12)),
              ])),
              const Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
        if (_retro != null) _desgloseEvaluaciones(_retro!),
        if (_retro != null) _desgloseRetro(_retro!),
        if ((ev['dificultadPromedio'] ?? 0) != 0)
          _card(Text(
            'Dificultad percibida de tus materias: ${ev['dificultadPromedio']} / 10 '
            '(según tus alumnos).',
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          )),
        _seccion('Mis materias asignadas'),
        if (materias.isEmpty)
          _card(Text('No tienes materias asignadas registradas.',
              style: TextStyle(color: cessumMuted(context))))
        else
          ...materias.map((raw) {
            final m = Map<String, dynamic>.from(raw as Map);
            final activa =
                (m['activa'] ?? '').toString().toUpperCase() != 'NO';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.book,
                    color: activa ? cessumRed : cessumFaint(context)),
                title: Text('${m['materia']}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${m['programa']} · ${m['generacion']} · '
                  '${(m['grupo'] ?? '').toString() == '2' ? 'Sabatino' : 'Entre semana'}'
                  '${activa ? '' : ' · inactiva'}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            );
          }),
        if (porMateria.isNotEmpty) ...[
          _seccion('Aprobación por materia'),
          _card(Column(
            children: porMateria.map<Widget>((raw) {
              final e = Map<String, dynamic>.from(raw as Map);
              final ap = (e['aprobacion'] ?? 0) as num;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${e['materia']}',
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('Prom. ${e['promedio']} · ',
                        style: const TextStyle(fontSize: 11.5)),
                    Text('$ap%',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: ap >= 80
                                ? const Color(0xFF1E8E3E)
                                : (ap >= 60 ? cessumGold : cessumRed))),
                  ],
                ),
              );
            }).toList(),
          )),
        ],
        _seccion('Distribución de tus calificaciones'),
        _card(Column(
            children: _distribucion(
                (cal['distribucion'] ?? {}) as Map<String, dynamic>))),
        const SizedBox(height: 24),
      ],
    );
  }

  // (ago-5) DESGLOSE EN PANTALLA PRINCIPAL: áreas de oportunidad y
  // fortalezas (con el nombre real de cada dimensión), escalafón,
  // sugerencias del motor y comentarios de los alumnos.
  /// Una dimensión, en el lenguaje del docente: no "peso 15%" sino qué se
  /// midió y cómo va. Lo que no se pudo medir se dice, en vez de mostrar un
  /// cero que parecería un reproche.
  int _n(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  String _medallaLugar(int l) =>
      l == 1 ? '🥇' : (l == 2 ? '🥈' : (l == 3 ? '🥉' : '📊'));

  /// Un criterio de evaluación con su promedio. La escala es de 1 a 10, así
  /// que la barra se calcula sobre 10 y no sobre 100 como las dimensiones.
  Widget _filaCriterio(Map<String, dynamic> c) {
    final p = c['promedio'] is num ? (c['promedio'] as num).toDouble() : null;
    final col = p == null
        ? cessumFaint(context)
        : (p >= 9
            ? const Color(0xFF1E8E3E)
            : (p >= 7.5 ? cessumGold : const Color(0xFFC62828)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('${c['texto'] ?? c['pregunta'] ?? ''}',
                    style: const TextStyle(fontSize: 11.5, height: 1.3)),
              ),
              const SizedBox(width: 8),
              Text(p == null ? '—' : p.toStringAsFixed(1),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: col)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p == null ? 0 : (p / 10).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: cessumMuted(context).withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(col),
            ),
          ),
          if (_n(c['n']) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('${_n(c['n'])} respuesta(s)',
                  style: TextStyle(
                      fontSize: 10, color: cessumFaint(context))),
            ),
        ],
      ),
    );
  }

  Widget _miDimension(Map<String, dynamic> d) {
    final cuenta = d['cuenta'] == true;
    final v = d['valor'] is num ? (d['valor'] as num).toDouble() : null;
    final col = (!cuenta || v == null)
        ? cessumFaint(context)
        : (v >= 85
            ? const Color(0xFF1E8E3E)
            : (v >= 65 ? cessumGold : const Color(0xFFC62828)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${d['etiqueta']}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cuenta ? cessumInk(context) : cessumFaint(context))),
              ),
              Text(cuenta && v != null ? '${v.round()}' : '—',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: col)),
            ],
          ),
          if (cuenta && v != null) ...[
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (v / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: cessumMuted(context).withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(col),
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
              cuenta
                  ? '${d['detalle'] ?? ''}'
                  : '${d['detalle'] ?? ''} · no cuenta en tu puntaje',
              style: TextStyle(
                  fontSize: 10.5,
                  height: 1.3,
                  color: cuenta ? cessumMuted(context) : cessumFaint(context))),
        ],
      ),
    );
  }

  Widget _desgloseEvaluaciones(Map<String, dynamic> r) {
    final ops = ((r['oportunidades'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final fts = ((r['fortalezas'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final esc = r['escalafon'];
    // (ago-9) Las seis dimensiones del puntaje. Al docente le importa MÁS que
    // el número: un "integral 78" no le dice qué hacer, y ver que su flojera
    // está en retroalimentación escrita sí.
    final dims = ((r['dimensiones'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final crits = ((r['criterios'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (ops.isEmpty && fts.isEmpty && esc == null && dims.isEmpty) {
      return const SizedBox.shrink();
    }
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.insights, size: 18, color: cessumRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'MI EVALUACIÓN DOCENTE'
                '${r['puntajeIntegral'] != null ? ' · integral ${r['puntajeIntegral']}' : ''}'
                '${esc is Map ? ' · ${esc['emoji'] ?? ''} ${esc['nivel'] ?? ''}' : ''}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: cessumRed)),
          ),
        ]),
        if (esc is Map && '${esc['nivel'] ?? ''}' == 'Sin historial') ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: cessumMuted(context).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8)),
            child: const Text(
                'Todavía no tienes escalafón porque hace falta historial de '
                'al menos dos semanas. No es una calificación baja: es que '
                'apenas estamos midiendo.',
                style: TextStyle(fontSize: 11.5, height: 1.35)),
          ),
        ],
        // (ago-21) SI CAYÓ FUERTE ESTA SEMANA, SE LE DICE.
        //
        // El escalafón promedia cuatro semanas y amortigua: quien venía en 92
        // y cayó a 68 sigue viendo «Consolidado». Enterarse un mes después,
        // cuando el promedio por fin baje, le quita la única ventaja de un
        // aviso a tiempo — que todavía se puede remontar.
        //
        // El tono importa: esto lo lee el docente, no su jefe. Se dice como
        // dato, no como reproche.
        if (esc is Map && '${esc['alertaCaida'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFB07D12).withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: const Color(0xFFB07D12).withValues(alpha: 0.4)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.trending_down,
                      size: 16, color: Color(0xFFB07D12)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tu puntaje bajó esta semana',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('${esc['alertaCaida']}',
                            style: const TextStyle(
                                fontSize: 11.5, height: 1.4)),
                        const SizedBox(height: 4),
                        const Text(
                            'Todavía estás a tiempo: el nivel se calcula sobre '
                            'cuatro semanas, así que una buena semana lo '
                            'compensa.',
                            style: TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ]),
          ),
        ],
        // (ago-12) RANKING. Estaba en la respuesta desde siempre y no se
        // mostraba: el docente veía su puntaje pero no en qué lugar quedó ni
        // de cuántos. Va arriba porque es lo primero que se busca.
        if (_n(r['lugar']) > 0) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB11D29), Color(0xFF8E1720)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(_medallaLugar(_n(r['lugar'])),
                    style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Lugar ${_n(r['lugar'])} de ${_n(r['deTotal'])} '
                          'docentes',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      const Text(
                          'Por puntaje integral. El lugar se mueve cada '
                          'semana y no es una calificación: es una foto del '
                          'momento.',
                          style: TextStyle(
                              fontSize: 10.5,
                              height: 1.3,
                              color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (dims.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('📊 CÓMO SE FORMA TU PUNTAJE',
              style:
                  TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          Padding(
            padding: EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
                'Cada factor se muestra sobre 100. Tu evaluación de alumnos '
                'va sobre 10.',
                style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
          ),
          const SizedBox(height: 6),
          for (final d in dims) _miDimension(d),
          if ('${r['notaIntegral'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${r['notaIntegral']}',
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      fontStyle: FontStyle.italic,
                      color: cessumMuted(context))),
            ),
        ],
        // (ago-12) CRITERIOS COMPLETOS. Antes solo se veían 3 fortalezas y 3
        // oportunidades; el docente no sabía sobre qué MÁS lo estaban
        // midiendo. Un sistema de evaluación que no enseña sus criterios se
        // vive como un juicio, no como una guía.
        if (crits.isNotEmpty) ...[
          const SizedBox(height: 10),
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 6),
              leading: const Icon(Icons.checklist_rtl,
                  size: 18, color: cessumRed),
              title: Text(
                  'Con qué te evalúan tus alumnos (${crits.length} criterios)',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${_n(r['evalRespuestas'])} respuesta(s) recibidas',
                  style: TextStyle(
                      fontSize: 11, color: cessumMuted(context))),
              children: [
                for (final c in crits) _filaCriterio(c),
                const SizedBox(height: 4),
                Text(
                    'Tus alumnos contestan del 1 al 5 y aquí se muestra sobre '
                    '10, para que se lea igual que una calificación. Nadie ve '
                    'quién contestó qué: los promedios salen de todas las '
                    'respuestas juntas.',
                    style: TextStyle(
                        fontSize: 10.5,
                        height: 1.3,
                        fontStyle: FontStyle.italic,
                        color: cessumMuted(context))),
              ],
            ),
          ),
        ],
        if (ops.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('🎯 ÁREAS DE OPORTUNIDAD (según tus alumnos)',
              style:
                  TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final o in ops)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                  // (ago-12) Decía "(null resp.)" cuando el conteo no venía.
                  // Un "null" en pantalla no le dice nada al docente y le
                  // hace dudar del resto del número.
                  '· ${o['texto']} — ${o['promedio']}'
                  '${_n(o['n']) > 0 ? ' (${_n(o['n'])} resp.)' : ''}',
                  style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Color(0xFFB11D29))),
            ),
        ],
        if (fts.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('💪 TUS FORTALEZAS',
              style:
                  TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final f in fts)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('· ${f['texto']} — ${f['promedio']}',
                  style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Color(0xFF1B5E20))),
            ),
        ],
      ],
    ));
  }

  Widget _desgloseRetro(Map<String, dynamic> r) {
    final coms = ((r['comentarios'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    final sugs = ((r['sugerencias'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    if (coms.isEmpty && sugs.isEmpty) return const SizedBox.shrink();
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sugs.isNotEmpty) ...[
          const Text('🧭 RETROALIMENTACIÓN DE LA SEMANA',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF8A5A0F))),
          const SizedBox(height: 6),
          for (final sg in sugs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(sg,
                  style: const TextStyle(fontSize: 11.5, height: 1.4)),
            ),
        ],
        if (coms.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('💬 LO QUE DICEN TUS ALUMNOS',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF8A5A0F))),
          const SizedBox(height: 6),
          for (final c in coms)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('“$c”',
                  style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      fontStyle: FontStyle.italic)),
            ),
        ],
      ],
    ));
  }

  Widget _kpi(String titulo, String valor, IconData icono, Color color,
      {String sub = ''}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 20),
          const Spacer(),
          Text(valor,
              style: TextStyle(
                  fontSize: 23, fontWeight: FontWeight.w800, color: color)),
          Text(titulo,
              style:
                  const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          if (sub.isNotEmpty)
            Text(sub,
                style:
                    const TextStyle(fontSize: 10.5, color: Colors.black45),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
        ),
        child: child,
      );

  List<Widget> _distribucion(Map<String, dynamic> dist) {
    final orden = ['10', '9', '8', '7', '6', 'Reprobado'];
    final total = dist.values.fold<num>(0, (a, b) => a + (b as num));
    if (total == 0) {
      return [
        Text('Aún no tienes calificaciones validadas.',
            style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))
      ];
    }
    return orden.where((k) => dist.containsKey(k)).map((k) {
      final v = (dist[k] ?? 0) as num;
      final pct = total > 0 ? (v / total) : 0.0;
      final color = k == 'Reprobado' ? cessumRed : cessumGold;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
                width: 78,
                child: Text(k == 'Reprobado' ? 'Reprobado' : 'Calif. $k',
                    style: const TextStyle(fontSize: 11.5))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct.toDouble(),
                  minHeight: 8,
                  backgroundColor: color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('$v', style: const TextStyle(fontSize: 11.5)),
          ],
        ),
      );
    }).toList();
  }
}
