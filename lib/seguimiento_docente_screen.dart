// ADMIN: Seguimiento docente (ago-2026). Ranking de desempeño en revisiones:
// puntaje = 70% revisar en tiempo y forma (dentro de 24 h) + 30% revisar
// aunque sea tarde. Pensado para irse alimentando con más dimensiones.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'eval_respuestas_screen.dart';
import 'mis_interacciones_screen.dart';
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

  Color _colorNivel(String n) => n == 'Titular'
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
      if (_filtro.isEmpty) return true;
      return '${r['docente']} ${r['correo']}'
          .toLowerCase()
          .contains(_filtro.toLowerCase());
    }).toList();
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
                      const SizedBox(height: 10),
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
                        _tarjeta(vis[i], _ranking.indexOf(vis[i]) + 1),
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
          // (ago-21) LA CAÍDA FUERTE SE VE, AUNQUE EL NIVEL AGUANTE.
          //
          // El escalafón promedia cuatro semanas, así que amortigua: alguien
          // que venía en 92 y cayó a 68 sigue saliendo «Consolidado» porque
          // el promedio da 82. El nivel está bien —mide trayectoria— pero
          // quien revisa necesita ver que algo pasó ESTA semana, no dentro de
          // un mes cuando el promedio por fin baje.
          if (r['escalafon'] is Map &&
              '${(r['escalafon'] as Map)['alertaCaida'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.trending_down,
                          size: 15, color: cessumRed),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            '${(r['escalafon'] as Map)['alertaCaida']}',
                            style: const TextStyle(
                                fontSize: 11.5, height: 1.4)),
                      ),
                    ]),
              ),
            ),
          if (r['dimensiones'] is List) _dimensiones(r),
          if (r['checklist'] is Map) _checklist(r['checklist'] as Map),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: cessumGold,
                  visualDensity: VisualDensity.compact),
              onPressed: () => _revisionAulas(r),
              icon: const Icon(Icons.class_outlined, size: 16),
              label: const Text('Revisión de aulas (recursos en Moodle)',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
          // (ago-22) Las respuestas crudas de sus alumnos, anónimas. El
          // promedio dice cuánto; esto dice quién opinó qué y si hubo acuerdo.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: cessumRed,
                  visualDensity: VisualDensity.compact),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EvalRespuestasScreen(
                    correo: (r['correo'] ?? '').toString(),
                    docente: (r['docente'] ?? '').toString(),
                  ),
                ),
              ),
              icon: const Icon(Icons.forum_outlined, size: 16),
              label: const Text('Respuestas de los alumnos (anónimas)',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
          // (4-oct-2026) El informe de interacciones de clase de este docente: histórico, por materia y su bono de escalafón.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF2F5D8A), visualDensity: VisualDensity.compact),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MisInteraccionesScreen(
                correo: (r['correo'] ?? '').toString(), nombre: (r['docente'] ?? '').toString()))),
              icon: const Icon(Icons.record_voice_over_outlined, size: 16),
              label: const Text('Interacciones de sus clases', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
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
