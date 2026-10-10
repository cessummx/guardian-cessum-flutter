// =====================================================================
//  calidad_plataforma_screen.dart · CESSUM · Aula CESSUM
//  Qué opinan los alumnos de la plataforma, ordenado por lo que hay que
//  arreglar primero.
//
//  Por qué existe: las respuestas sobre la app se mezclaban con las de
//  docentes, procesos y mercadeo en un solo resumen de 55 promedios.
//  Nadie iba a leer eso buscando si la app está fallando, así que la
//  información existía y no servía para nada.
//
//  Backend: ?accion=calidad_plataforma[&dias=90]  (Code.gs V594)
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class CalidadPlataformaScreen extends StatefulWidget {
  const CalidadPlataformaScreen({super.key});
  @override
  State<CalidadPlataformaScreen> createState() =>
      _CalidadPlataformaScreenState();
}

class _CalidadPlataformaScreenState extends State<CalidadPlataformaScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _d = {};
  int _dias = 90;

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
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'calidad_plataforma',
        'dias': '$_dias',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  int _n(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  /// Verde arriba de 85, dorado hasta 70, rojo abajo. El mismo criterio que
  /// las dimensiones del escalafón, para que un número se lea igual en toda
  /// la aplicación.
  Color _col(int v) => v >= 85
      ? const Color(0xFF1E8E3E)
      : (v >= 70 ? cessumGold : const Color(0xFFC62828));

  @override
  Widget build(BuildContext context) {
    final preguntas = (_d['preguntas'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final grupos = (_d['porGrupo'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final comentarios = (_d['comentarios'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Calidad de la plataforma'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Periodo',
            icon: const Icon(Icons.date_range),
            onSelected: (v) {
              setState(() => _dias = v);
              _cargar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 30, child: Text('Últimos 30 días')),
              PopupMenuItem(value: 90, child: Text('Últimos 90 días')),
              PopupMenuItem(value: 365, child: Text('Último año')),
            ],
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
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
                      if (preguntas.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: CessumEmptyState(
                            title: 'Todavía no hay respuestas',
                            subtitle:
                                'Cuando los alumnos contesten el pulso sobre '
                                'la app, aquí aparecerá qué les funciona y '
                                'qué no.',
                            icon: Icons.insights_outlined,
                          ),
                        )
                      else ...[
                        const SizedBox(height: 14),
                        if (grupos.isNotEmpty) ...[
                          _titulo('Por área'),
                          for (final g in grupos) _fichaGrupo(g),
                          const SizedBox(height: 14),
                        ],
                        _titulo('Pregunta por pregunta'),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                              'De peor a mejor. Lo de arriba es lo que más '
                              'alumnos están sufriendo.',
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.black54)),
                        ),
                        for (final p in preguntas) _fichaPregunta(p),
                        if (comentarios.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _titulo('Lo que escribieron'),
                          for (final c in comentarios) _fichaComentario(c),
                        ],
                      ],
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

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: cessumRed)),
      );

  Widget _cabecera() {
    final general = _d['general'];
    final g = general is num ? general.toInt() : null;
    return Container(
      padding: const EdgeInsets.all(16),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(g == null ? '—' : '$g',
                  style: CessumType.display(40, color: Colors.white)),
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 4),
                child: Text('/100',
                    style: TextStyle(fontSize: 14, color: Colors.white70)),
              ),
            ],
          ),
          const Text('cómo ven la app tus alumnos',
              style: TextStyle(fontSize: 12.5, color: Colors.white70)),
          const SizedBox(height: 10),
          // (2-sep) MÁS CONTEXTO ARRIBA. Un 89 sin saber cuántos lo dijeron
          // invita a decidir sobre nada. Aquí va participación, tamaño de
          // muestra y cuántas preguntas son confiables.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _pastilla('${_n(_d['alumnosQueRespondieron'])} de '
                  '${_n(_d['alumnosActivos'])} alumnos'),
              if (_d['participacionPct'] != null)
                _pastilla('${_n(_d['participacionPct'])} % participación'),
              _pastilla('${_n(_d['totalRespuestas'])} respuestas'),
              _pastilla('últimos ${_n(_d['dias'])} días'),
              if (_n(_d['preguntasConMuestraSuficiente']) > 0)
                _pastilla('${_n(_d['preguntasConMuestraSuficiente'])} '
                    'con muestra firme'),
            ],
          ),
          if ('${_d['aviso'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 17, color: Colors.white),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text('${_d['aviso']}',
                        style: const TextStyle(
                            fontSize: 11.5, height: 1.35, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
          if ('${_d['lectura'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${_d['lectura']}',
                style: const TextStyle(
                    fontSize: 12.5, height: 1.35, color: Colors.white)),
          ],
        ],
      ),
    );
  }

  Widget _pastilla(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      );

  Widget _fichaGrupo(Map<String, dynamic> g) {
    final v = _n(g['promedio']);
    final col = _col(v);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text('$v',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: col)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${g['grupo']}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (v / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: const Color(0xFFEEEAE2),
                    valueColor: AlwaysStoppedAnimation<Color>(col),
                  ),
                ),
                const SizedBox(height: 2),
                Text('${_n(g['preguntas'])} pregunta(s) · '
                    '${_n(g['respuestas'])} respuesta(s)',
                    style: const TextStyle(
                        fontSize: 10.5, color: Colors.black45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fichaPregunta(Map<String, dynamic> p) {
    final v = _n(p['promedio']);
    final col = _col(v);
    final reparto = (p['reparto'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('${p['texto']}',
                    style: const TextStyle(fontSize: 12.5, height: 1.35)),
              ),
              const SizedBox(width: 8),
              Text('$v',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: col)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (v / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: const Color(0xFFEEEAE2),
              valueColor: AlwaysStoppedAnimation<Color>(col),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text('${p['grupo']} · ${_n(p['respuestas'])} respuesta(s)',
                    style: const TextStyle(
                        fontSize: 10.5, color: Colors.black45)),
              ),
              // (2-sep) CUÁNTA CONFIANZA MERECE ESTE NÚMERO. Un 77 con tres
              // respuestas y uno con cuarenta se veían idénticos.
              _selloConfianza('${p['confianza'] ?? ''}'),
            ],
          ),
          // Qué contestaron exactamente. El promedio esconde si el problema
          // es de unos pocos muy molestos o de todos un poco.
          // (2-sep) El reparto ahora se ve como barras: de un vistazo se
          // distingue «a casi todos les parece bien y a uno muy mal» de
          // «a todos les parece regular», que exigen respuestas distintas.
          if (reparto.isNotEmpty) ...[
            const SizedBox(height: 7),
            for (final r in reparto)
              _barraOpcion('${r['opcion']}', _n(r['veces']),
                  _n(p['respuestas'])),
          ],
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _verDetalle(p),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Text('Ver respuesta por respuesta',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cessumRed)),
                Icon(Icons.chevron_right, size: 16, color: cessumRed),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // (2-sep) Sello de tamaño de muestra.
  Widget _selloConfianza(String c) {
    if (c.isEmpty) return const SizedBox.shrink();
    final firme = c.startsWith('sufi');
    final media = c.startsWith('indic');
    final col = firme
        ? const Color(0xFF1E8E3E)
        : (media ? cessumGold : const Color(0xFF8A8A8A));
    final txt = firme
        ? 'muestra firme'
        : (media ? 'solo indicativa' : 'anecdótica');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: col.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(txt,
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w700, color: col)),
    );
  }

  // (2-sep) Una barra por opción, proporcional a cuántos la eligieron.
  Widget _barraOpcion(String opcion, int veces, int total) {
    final frac = total > 0 ? veces / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Text(opcion,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: Colors.black87)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: frac.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0xFFF0EDE6),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF9AA0A6)),
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text('  $veces · ${(frac * 100).round()}%',
                style: const TextStyle(fontSize: 10, color: Colors.black45)),
          ),
        ],
      ),
    );
  }

  /* (2-sep) RESPUESTA POR RESPUESTA. El promedio esconde lo que de verdad
     sirve para decidir: qué contestó cada quien, cuándo, y si dejó un
     comentario. Con muestras de tres respuestas, leerlas una por una vale
     más que cualquier promedio. No trae matrícula: la encuesta se contesta
     en confianza. */
  Future<void> _verDetalle(Map<String, dynamic> p) async {
    final id = '${p['id']}';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _pedirDetalle(id),
            builder: (ctx2, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final d = snap.data ?? {};
              final lista = (d['lista'] as List? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('${p['texto']}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.35)),
                  const SizedBox(height: 4),
                  Text('$id · ${lista.length} respuesta(s) · '
                      'últimos ${_n(_d['dias'])} días',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45)),
                  const Divider(height: 20),
                  if (lista.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 26),
                      child: Text('Sin respuestas en este periodo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54)),
                    )
                  else
                    for (final r in lista) _filaDetalle(r),
                  const SizedBox(height: 10),
                  Text('${d['nota'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.black38,
                          fontStyle: FontStyle.italic)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _pedirDetalle(String id) async {
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'calidad_detalle',
        'pregunta': id,
        'dias': '$_dias',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 90));
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false, 'lista': []};
    }
  }

  Widget _filaDetalle(Map<String, dynamic> r) {
    final v = r['sobre100'];
    final val = v is num ? v.toInt() : null;
    final com = '${r['comentario'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F7F3),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: (val == null ? Colors.black12 : _col(val))
                .withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${r['respuesta']}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              if (val != null)
                Text('$val',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _col(val))),
            ],
          ),
          const SizedBox(height: 3),
          Text([
            '${r['cuando'] ?? ''}',
            if ('${r['programa'] ?? ''}'.isNotEmpty) '${r['programa']}',
            if ('${r['generacion'] ?? ''}'.isNotEmpty) 'gen. ${r['generacion']}',
          ].where((e) => e.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          if (com.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('“$com”',
                style: const TextStyle(
                    fontSize: 12, height: 1.35, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  Widget _fichaComentario(Map<String, dynamic> c) => Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xFFF7F5F0),
            borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('“${c['texto']}”',
                style: const TextStyle(
                    fontSize: 12, height: 1.4, fontStyle: FontStyle.italic)),
            const SizedBox(height: 3),
            Text('sobre ${c['pregunta']}',
                style: const TextStyle(fontSize: 10, color: Colors.black38)),
          ],
        ),
      );
}
