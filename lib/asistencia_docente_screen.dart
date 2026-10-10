import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'helpers.dart';

/// ASISTENCIA DE MIS ALUMNOS (docente)
///
/// POR QUÉ ESTA PANTALLA
/// El registro de asistencia ya existía y funcionaba —se levanta solo de las
/// conexiones a las videollamadas— pero no había dónde consultarlo: el dato
/// estaba en el sistema y el profesor no podía verlo. Sin eso, quien quiere
/// saber por qué un alumno va mal no tiene cómo distinguir entre el que no
/// entrega y el que ni siquiera se está conectando.
///
/// CÓMO ESTÁ ORDENADA
/// Primero la materia, porque el docente piensa por grupo. Dentro, los
/// alumnos ordenados de MENOR a mayor asistencia: quien necesita atención
/// aparece arriba, no enterrado en una lista alfabética.
class AsistenciaDocenteScreen extends StatefulWidget {
  const AsistenciaDocenteScreen({super.key});

  @override
  State<AsistenciaDocenteScreen> createState() =>
      _AsistenciaDocenteScreenState();
}

class _AsistenciaDocenteScreenState extends State<AsistenciaDocenteScreen> {
  String _correo = '';
  List<Map<String, dynamic>> _grupos = [];
  Map<String, dynamic>? _sel;

  bool _cargandoGrupos = true;
  bool _cargandoAsist = false;
  String? _error;

  List<Map<String, dynamic>> _alumnos = [];
  int _sesiones = 0;
  String _lectura = '';
  // (24-sep) Lectura y borradores de mensaje con IA (no envía nada).
  Map<String, dynamic>? _ia;
  bool _iaCargando = false;

  @override
  void initState() {
    super.initState();
    _cargarGrupos();
  }

  Future<void> _cargarGrupos() async {
    setState(() {
      _cargandoGrupos = true;
      _error = null;
    });
    try {
      _correo = (await SessionStore.validEmail()) ?? '';
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=mis_grupos'
              '&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      final lista = ((data['grupos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _grupos = lista;
        _cargandoGrupos = false;
      });
      // Con una sola materia no tiene sentido hacerlo elegir.
      if (lista.length == 1) _verAsistencia(lista.first);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoGrupos = false;
        _error = 'No se pudieron cargar tus materias.';
      });
    }
  }

  Future<void> _verAsistencia(Map<String, dynamic> g) async {
    setState(() {
      _sel = g;
      _cargandoAsist = true;
      _alumnos = [];
      _lectura = '';
      _sesiones = 0;
      _ia = null;
    });
    try {
      final uri = Uri.parse('$guardianUrl?accion=asistencia_materia'
          '&programa=${Uri.encodeComponent((g['programa'] ?? '').toString())}'
          '&generacion=${Uri.encodeComponent((g['generacion'] ?? '').toString())}'
          '&grupo=${Uri.encodeComponent((g['grupo'] ?? '').toString())}'
          '&materia=${Uri.encodeComponent((g['materia'] ?? '').toString())}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;

      final als = ((data['alumnos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // De menor a mayor asistencia: primero quien necesita atención.
      als.sort((a, b) {
        final pa = (a['porcentaje'] as num?)?.toDouble() ?? 0;
        final pb = (b['porcentaje'] as num?)?.toDouble() ?? 0;
        return pa.compareTo(pb);
      });

      setState(() {
        _alumnos = als;
        _sesiones = (data['sesionesRegistradas'] as num?)?.toInt() ?? 0;
        _lectura = (data['lectura'] ?? '').toString();
        _cargandoAsist = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoAsist = false;
        _lectura = 'No se pudo cargar la asistencia de esta materia.';
      });
    }
  }

  /// (24-sep) Pide a la IA una lectura del grupo y borradores de mensaje. No
  /// envía nada: el docente revisa, copia y decide.
  Future<void> _pedirIa() async {
    final g = _sel;
    if (g == null) return;
    setState(() {
      _iaCargando = true;
      _ia = null;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'asistencia_ia_lectura',
        'programa': '${g['programa'] ?? ''}',
        'generacion': '${g['generacion'] ?? ''}',
        'grupo': '${g['grupo'] ?? ''}',
        'materia': '${g['materia'] ?? ''}',
        'correo': _correo,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar.');
      if (mounted) setState(() => _ia = d);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _iaCargando = false);
  }

  /// (24-sep) La lista en columnas, lista para pegar en Excel.
  void _copiarLista() {
    final g = _sel;
    final sb = StringBuffer()
      ..writeln('${g?['materia'] ?? ''}\t${g?['programa'] ?? ''} ${g?['generacion'] ?? ''} Grupo ${g?['grupo'] ?? ''}')
      ..writeln('Alumno\tMatrícula\tAsistió\tDe\tPorcentaje\tConexiones breves');
    for (final a in _alumnos) {
      sb.writeln('${a['alumno']}\t${a['matricula']}\t${a['asistio'] ?? 0}\t${a['deSesiones'] ?? 0}\t'
          '${((a['porcentaje'] as num?) ?? 0).round()}%\t${a['conexionesBreves'] ?? 0}');
    }
    Helpers.copiarAlPortapapeles(context, sb.toString(), 'Lista de asistencia');
  }

  Widget _bloqueIa() {
    final d = _ia!;
    final atender = ((d['alumnosAtender'] as List?) ?? []).map((e) => '$e').toList();
    Widget copiable(String titulo, String texto) => texto.trim().isEmpty
        ? const SizedBox.shrink()
        : Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(titulo,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: cessumRed))),
                IconButton(
                  tooltip: 'Copiar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => Helpers.copiarAlPortapapeles(context, texto, titulo),
                ),
              ]),
              SelectableText(texto, style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumInk(context))),
            ]),
          );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.auto_awesome, size: 18, color: cessumGold),
          SizedBox(width: 6),
          Text('Lectura con IA', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        Text('${d['lectura'] ?? ''}', style: TextStyle(fontSize: 12.8, height: 1.45, color: cessumInk(context))),
        if (atender.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Conviene buscar a: ${atender.join(', ')}.',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumRed)),
        ],
        copiable('Mensaje para todo el grupo', '${d['mensajeGrupo'] ?? ''}'),
        copiable('Mensaje para quien va bajo (cambie [Nombre])', '${d['mensajeIndividual'] ?? ''}'),
        const SizedBox(height: 8),
        Text('${d['aviso'] ?? 'Borradores generados con IA: revíselos antes de enviarlos.'}',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cessumMuted(context))),
      ]),
    );
  }

  /// El color dice de un vistazo a quién hay que buscar. Los cortes no son
  /// arbitrarios: bajo el 60 % el alumno ya está en riesgo de no acreditar
  /// por inasistencia, según el reglamento.
  Color _colorDe(double pct) {
    if (pct >= 80) return const Color(0xFF1E7F52);
    if (pct >= 60) return cessumGold;
    return cessumRed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Asistencia de mis alumnos',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            onPressed: _cargandoGrupos
                ? null
                : (_sel != null ? () => _verAsistencia(_sel!) : _cargarGrupos),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargandoGrupos
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: _cargarGrupos,
                        child: const Text('Reintentar')),
                  ]),
                )
              : _grupos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                            'No tienes materias asignadas en este momento.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cessumMuted(context))),
                      ),
                    )
                  : _contenido(),
    );
  }

  Widget _contenido() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'La asistencia se registra sola con la conexión de cada alumno a las '
          'videollamadas de la materia.',
          style: TextStyle(
              fontSize: 13, height: 1.5, color: cessumMuted(context)),
        ),
        const SizedBox(height: 14),

        // ── Elegir materia ──
        if (_grupos.length > 1) ...[
          Text('Elige la materia',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: cessumInk(context))),
          const SizedBox(height: 8),
          ..._grupos.map((g) {
            final activo = _sel != null &&
                '${_sel!['materia']}|${_sel!['grupo']}|${_sel!['generacion']}' ==
                    '${g['materia']}|${g['grupo']}|${g['generacion']}';
            return Container(
              margin: const EdgeInsets.only(bottom: 7),
              decoration: BoxDecoration(
                color: activo
                    ? cessumRed.withValues(alpha: 0.07)
                    : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                    color: activo
                        ? cessumRed.withValues(alpha: 0.4)
                        : cessumMuted(context).withValues(alpha: 0.18)),
              ),
              child: ListTile(
                dense: true,
                onTap: () => _verAsistencia(g),
                title: Text('${g['materia']}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${g['programa']} · ${g['generacion']} · Grupo ${g['grupo']}',
                    style: TextStyle(
                        fontSize: 11.5, color: cessumMuted(context))),
                trailing: Icon(
                    activo ? Icons.check_circle : Icons.chevron_right,
                    size: 20,
                    color: activo ? cessumRed : cessumMuted(context)),
              ),
            );
          }),
          const SizedBox(height: 18),
        ],

        if (_cargandoAsist)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator(color: cessumRed)),
          )
        else if (_sel != null) ...[
          // ── Encabezado de la materia ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: cessumRed,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_sel!['materia']}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    '${_sel!['generacion']} · Grupo ${_sel!['grupo']} · '
                    '$_sesiones ${_sesiones == 1 ? "sesión registrada" : "sesiones registradas"}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // (24-sep) IA y exportación.
          if (_alumnos.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                onPressed: _iaCargando ? null : _pedirIa,
                icon: _iaCargando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_iaCargando ? 'Analizando…' : 'Lectura y mensajes con IA'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                onPressed: _copiarLista,
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Copiar lista para Excel'),
              ),
            ]),
          const SizedBox(height: 14),
          if (_ia != null) _bloqueIa(),

          if (_lectura.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(_lectura,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: cessumInk(context))),
            ),
            const SizedBox(height: 14),
          ],

          if (_alumnos.isEmpty && !_cargandoAsist)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                  'Todavía no hay registros de asistencia en esta materia.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cessumMuted(context))),
            )
          else
            ..._alumnos.map(_tarjetaAlumno),

          const SizedBox(height: 30),
        ],
      ],
    );
  }

  Widget _tarjetaAlumno(Map<String, dynamic> a) {
    final pct = (a['porcentaje'] as num?)?.toDouble() ?? 0;
    final asistio = (a['asistio'] as num?)?.toInt() ?? 0;
    final de = (a['deSesiones'] as num?)?.toInt() ?? 0;
    final breves = (a['conexionesBreves'] as num?)?.toInt() ?? 0;
    final c = _colorDe(pct);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Porcentaje, que es lo que se lee primero.
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              children: [
                Text('${pct.round()}%',
                    style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: c)),
                Text('$asistio de $de',
                    style: TextStyle(
                        fontSize: 9.5, color: cessumMuted(context))),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a['alumno']}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${a['matricula']}',
                    style: TextStyle(
                        fontSize: 11.5, color: cessumMuted(context))),
                // Las conexiones muy cortas se avisan: entrar un minuto y
                // salir no es haber estado en clase, y conviene que el
                // docente lo sepa antes de dar por buena la asistencia.
                if (breves > 0) ...[
                  const SizedBox(height: 5),
                  Row(children: [
                    Icon(Icons.info_outline,
                        size: 13, color: cessumGold),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                          '$breves ${breves == 1 ? "conexión muy breve" : "conexiones muy breves"}',
                          style: TextStyle(
                              fontSize: 11, color: cessumGold)),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
