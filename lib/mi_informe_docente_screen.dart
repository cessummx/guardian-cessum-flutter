// DOCENTE: Mi informe de evaluación (ago-2026). Lo que el docente viene a
// ver aquí es SU evaluación: lo que dicen sus alumnos, su lugar y escalafón,
// su retroalimentación de la semana, el seguimiento de revisiones y las
// observaciones de clase de Coordinación Académica.
// (ago-22) Las revisiones pendientes ya NO se listan aquí: tienen su propia
// pantalla y su propio mosaico. Aquí solo queda el aviso con el atajo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'revisiones_screen.dart';
import 'auth/session_store.dart';
import 'helpers.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class MiInformeDocenteScreen extends StatefulWidget {
  const MiInformeDocenteScreen({super.key});

  @override
  State<MiInformeDocenteScreen> createState() =>
      _MiInformeDocenteScreenState();
}

class _MiInformeDocenteScreenState extends State<MiInformeDocenteScreen> {
  /// (ago-18) Las reglas del escalafón, tal como las publica el backend.
  /// Que el docente pueda leerlas en la misma pantalla donde ve su número es
  /// la diferencia entre una evaluación que se puede discutir y un veredicto.
  Map<String, dynamic>? _reglas;
  List<Map<String, dynamic>> _serie = [];
  List<Map<String, dynamic>> _bitacora = [];
  bool _cargandoExtra = true;
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic>? _seguimiento;
  Map<String, dynamic>? _retro;
  // Las revisiones pendientes, con sus dos relojes.
  Map<String, dynamic>? _revisiones;
  List<Map<String, dynamic>> _observaciones = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  bool _planeando = false;

  /// (24-sep) Plan de mejora con IA: la IA recibe los mismos bloques que el
  /// docente ve aquí (el Guardián les quita los correos) y devuelve una lectura
  /// breve y tres acciones concretas, cada una con el dato que la origina.
  Future<void> _planMejora() async {
    setState(() => _planeando = true);
    Map<String, dynamic> d;
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final informe = {
        'seguimiento': _seguimiento,
        'retroalimentacion': _retro,
        'revisionesDeAula': _revisiones,
        'observaciones': _observaciones.take(6).toList(),
      };
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'docente_ia_plan', 'correo': correo, 'informe': informe}))
          .timeout(const Duration(seconds: 120));
      d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar el plan.');
    } catch (e) {
      if (mounted) {
        setState(() => _planeando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _planeando = false);
    final acciones = ((d['acciones'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final lectura = '${d['lectura'] ?? ''}';
    final texto = StringBuffer()
      ..writeln(lectura)
      ..writeln('')
      ..writeln([for (var i = 0; i < acciones.length; i++)
        '${i + 1}. ${acciones[i]['accion']}\n   (${acciones[i]['porque']})'].join('\n'));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mi plan de mejora', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(lectura, style: TextStyle(fontSize: 13.5, height: 1.45, color: cessumInk(ctx))),
              const SizedBox(height: 12),
              for (var i = 0; i < acciones.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(radius: 12, backgroundColor: cessumRed,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${acciones[i]['accion'] ?? ''}',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.35, color: cessumInk(ctx))),
                        const SizedBox(height: 3),
                        Text('${acciones[i]['porque'] ?? ''}',
                            style: TextStyle(fontSize: 12, height: 1.35, color: cessumMuted(ctx))),
                      ]),
                    ),
                  ]),
                ),
              Text('${d['aviso'] ?? ''}',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Helpers.copiarAlPortapapeles(ctx, texto.toString(), 'Plan de mejora'),
            child: const Text('Copiar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final correo = await SessionStore.validEmail();
      if (correo == null || correo.isEmpty) {
        throw Exception('Inicia sesión de nuevo.');
      }
      // Las revisiones pendientes se piden aparte y en paralelo: si esa
      // consulta falla, el resto del informe se ve igual.
      http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'mis_revisiones',
            'correo': correo,
          }))
          .timeout(const Duration(seconds: 45))
          .then((rr) {
        if (!mounted) return;
        try {
          final d = jsonDecode(rr.body) as Map<String, dynamic>;
          if (d['ok'] == true) setState(() => _revisiones = d);
        } catch (_) {}
      }).catchError((_) {});

      final rs = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'seguimiento_docente',
            'correo': correo,
          }))
          .timeout(const Duration(seconds: 60));
      final ds = jsonDecode(rs.body) as Map<String, dynamic>;
      final ro = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'observaciones_docente',
            'correo': correo,
          }))
          .timeout(const Duration(seconds: 60));
      final dobs = jsonDecode(ro.body) as Map<String, dynamic>;
      // (ago-19) Trayectoria y bitácora. Van en paralelo y si fallan no
      // tumban la pantalla: son complemento, no el informe.
      () async {
        try {
          final rt = await http
              .get(Uri.parse(guardianUrl).replace(queryParameters: {
                'accion': 'docente_trayectoria',
                'correo': correo,
                'semanas': '12',
              }))
              .timeout(const Duration(seconds: 60));
          final dt = jsonDecode(rt.body) as Map<String, dynamic>;
          final rb = await http
              .get(Uri.parse(guardianUrl).replace(queryParameters: {
                'accion': 'reflexion_listar',
                'correo': correo,
              }))
              .timeout(const Duration(seconds: 60));
          final db = jsonDecode(rb.body) as Map<String, dynamic>;
          if (!mounted) return;
          setState(() {
            _serie = ((dt['serie'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _bitacora = ((db['entradas'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _cargandoExtra = false;
          });
        } catch (_) {
          if (mounted) setState(() => _cargandoExtra = false);
        }
      }();

      // (ago-5) Retro integral: evaluaciones por dimensión, oportunidades,
      // fortalezas, comentarios de alumnos y sugerencias del motor.
      Map<String, dynamic>? retro;
      try {
        final rr = await http
            .get(Uri.parse(guardianUrl).replace(queryParameters: {
              'accion': 'docente_retro',
              'correo': correo,
            }))
            .timeout(const Duration(seconds: 90));
        final dr = jsonDecode(rr.body) as Map<String, dynamic>;
        if (dr['ok'] == true) retro = dr;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _seguimiento = (ds['ok'] == true && ds['seguimiento'] != null)
            ? Map<String, dynamic>.from(ds['seguimiento'] as Map)
            : null;
        _reglas = (ds['reglas'] is Map)
            ? Map<String, dynamic>.from(ds['reglas'] as Map)
            : null;
        _observaciones = ((dobs['observaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _retro = retro;
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

  Color _colorPuntaje(num? p) {
    if (p == null) return cessumFaint(context);
    if (p >= 90) return const Color(0xFF1E8E3E);
    if (p >= 75) return const Color(0xFF7CB342);
    if (p >= 50) return cessumGold;
    return cessumRed;
  }

  /// Las preguntas se arman con SUS cifras, no con una lista genérica.
  /// «¿Cómo vas con la retroalimentación?» no le sirve a nadie; «tu retro va
  /// en 41 y es lo que más peso tiene sin cubrir» sí obliga a pensar.
  /// (ago-22) AVISO DE REVISIONES, NO LA PANTALLA DE REVISIONES.
  ///
  /// Aquí vivía la lista completa de entregas pendientes, con sus dos relojes
  /// y sus diez tarjetas, encabezando el informe. El resultado era que tres
  /// mosaicos del menú docente —Revisiones pendientes, Mi informe de
  /// evaluación y Mi desempeño— abrían con lo mismo, y quien entraba a ver su
  /// evaluación recibía primero su deuda de calificaciones.
  ///
  /// Las revisiones tienen su propia pantalla y su propio mosaico. Aquí queda
  /// una línea que avisa y lleva allá: el pendiente no se esconde, pero deja
  /// de suplantar al informe.
  Widget _avisoRevisiones() {
    final r = _revisiones!;
    final lista = (r['pendientes'] as List?) ?? [];
    if (lista.isEmpty) return const SizedBox.shrink();
    final vencidas = (r['vencidas'] as num?)?.toInt() ?? 0;
    final urgentes = (r['porVencer12h'] as num?)?.toInt() ?? 0;
    final detalle = [
      if (vencidas > 0) '$vencidas vencida(s)',
      if (urgentes > 0) '$urgentes en menos de 12 h',
    ].join(' · ');
    final color = vencidas > 0 ? cessumRed : cessumGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(children: [
        Icon(Icons.pending_actions, size: 19, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  lista.length == 1
                      ? 'Tienes 1 revisión pendiente'
                      : 'Tienes ${lista.length} revisiones pendientes',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              if (detalle.isNotEmpty)
                Text(detalle,
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: color)),
            ],
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: color),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const RevisionesScreen())),
          child: const Text('Ver y calificar',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _reflexion(Map<String, dynamic> r) {
    final dims = (r['dimensiones'] as List?) ?? [];
    final preguntas = <String>[];

    Map<String, dynamic>? peor, mejor;
    for (final e in dims) {
      final d = e as Map;
      if (d['aplica'] != true || d['valor'] == null) continue;
      if (peor == null || (d['valor'] as num) < (peor['valor'] as num)) {
        peor = Map<String, dynamic>.from(d);
      }
      if (mejor == null || (d['valor'] as num) > (mejor['valor'] as num)) {
        mejor = Map<String, dynamic>.from(d);
      }
    }

    if (peor != null) {
      preguntas.add(
          '${peor['etiqueta']} va en ${peor['valor']} de 100. ¿Qué te lo '
          'impide: falta de tiempo, que no sabes qué esperan de ti, o que no '
          'te parece que ayude a tus alumnos?');
    }
    if (mejor != null && (mejor['valor'] as num) >= 70) {
      preguntas.add(
          'En ${mejor['etiqueta']} vas en ${mejor['valor']}. ¿Qué haces ahí '
          'que podrías trasladar a lo demás?');
    }
    final ajustes = (r['ajustes'] as List?) ?? [];
    for (final a in ajustes) {
      final m = a as Map;
      if ('${m['signo']}' == '-') {
        preguntas.add(
            'Te restó ${m['puntos']} por ${m['etiqueta']}. ¿Fue una vez o se '
            'está volviendo costumbre? ¿Qué tendría que cambiar para que no '
            'se repita?');
        break;
      }
    }
    if (_serie.length >= 3) {
      preguntas.add(
          'Mira tu línea de las últimas semanas. ¿La forma que ves coincide '
          'con cómo recuerdas que fueron esas semanas?');
    }
    preguntas.add(
        'Si solo pudieras cambiar una cosa de aquí al próximo lunes, y nadie '
        'lo fuera a revisar, ¿cuál elegirías?');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E7B34).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF1E7B34).withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PARA PENSAR',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E7B34))),
          const SizedBox(height: 6),
          for (final q in preguntas)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('· ', style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(
                    child: Text(q,
                        style: const TextStyle(fontSize: 12.5, height: 1.45))),
              ]),
            ),
          const SizedBox(height: 4),
          Row(children: [
            TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1E7B34),
                  padding: EdgeInsets.zero),
              onPressed: () => _abrirBitacora(r),
              icon: const Icon(Icons.edit_note, size: 19),
              label: Text(_bitacora.isEmpty
                  ? 'Escribir en mi bitácora'
                  : 'Mi bitácora · ${_bitacora.length} entrada(s)'),
            ),
          ]),
          Text(
              'Tu bitácora es tuya: no cuenta para tu evaluación ni suma ni '
              'resta puntos. Si contara, dejaría de servir para pensar.',
              style: TextStyle(
                  fontSize: 10.5, height: 1.4, color: cessumMuted(context))),
        ],
      ),
    );
  }

  Future<void> _abrirBitacora(Map<String, dynamic> r) async {
    final obs = TextEditingController();
    final hare = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mi bitácora'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: obs,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Qué observo de mi trabajo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: hare,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Qué haré distinto',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_bitacora.isNotEmpty) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Lo que has escrito antes',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: .7,
                          fontWeight: FontWeight.w800,
                          color: cessumMuted(context))),
                ),
                const SizedBox(height: 4),
                for (final b in _bitacora.take(6))
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${b['fecha']}${b['puntaje'] != '' ? ' · iba en ${b['puntaje']}' : ''}',
                            style: TextStyle(
                                fontSize: 10.5, color: cessumMuted(context))),
                        if ('${b['observo']}'.isNotEmpty)
                          Text('${b['observo']}',
                              style: const TextStyle(fontSize: 12, height: 1.4)),
                        if ('${b['hare']}'.isNotEmpty)
                          Text('→ ${b['hare']}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () async {
              final correo = await SessionStore.validEmail();
              if (correo == null) return;
              final uri = Uri.parse(guardianUrl).replace(queryParameters: {
                'accion': 'reflexion_guardar',
                'correo': correo,
                'observo': obs.text.trim(),
                'hare': hare.text.trim(),
                'puntaje': '${r['puntajeIntegral'] ?? ''}',
              });
              try {
                await http.get(uri).timeout(const Duration(seconds: 40));
              } catch (_) {}
              if (ctx.mounted) Navigator.pop(ctx);
              _cargar();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  /// Una de las dos cajas de puntaje. Se distinguen por color y por la
  /// línea que dice QUÉ mide cada una: sin eso, dos números distintos en la
  /// misma pantalla solo confunden.
  Widget _cajaPuntaje(
      String titulo, String valor, String formula, String nota, Color color) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 2),
          Text(valor,
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800, color: color)),
          Text(formula,
              style: const TextStyle(fontSize: 10, height: 1.3)),
          const SizedBox(height: 4),
          Text(nota,
              style: TextStyle(
                  fontSize: 10.5, height: 1.35, color: cessumMuted(context))),
        ],
      ),
    );
  }

  /// Las reglas completas, plegadas para no competir con el puntaje pero
  /// disponibles siempre en la misma pantalla.
  Widget _reglasEscalafon() {
    final rg = _reglas!;
    final factores = (rg['factores'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final suman = (rg['suman'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final restan = (rg['restan'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final justicia = (rg['justicia'] as List? ?? []).map((e) => '$e').toList();

    Widget titulo(String t, Color c) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(t,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
        );

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: const Text('Cómo se calcula tu puntaje',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        subtitle: Text('Qué suma, qué resta y por qué',
            style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        children: [
          titulo('LOS FACTORES Y SU PESO', const Color(0xFFB11D29)),
          for (final f in factores)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 30,
                  child: Text('${f['peso']}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB11D29))),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${f['etiqueta']}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('${f['comoSube']}',
                          style: TextStyle(
                              fontSize: 11, height: 1.35, color: cessumMuted(context))),
                    ],
                  ),
                ),
              ]),
            ),
          titulo('LO QUE SUMA', const Color(0xFF1E8E3E)),
          for (final x in suman)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('+  ${x['etiqueta']} · ${x['cuanto']} — ${x['porQue']}',
                  style: const TextStyle(fontSize: 11.5, height: 1.4)),
            ),
          titulo('LO QUE RESTA', const Color(0xFFC62828)),
          for (final x in restan)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('−  ${x['etiqueta']} · ${x['cuanto']}',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700)),
                  Text('${x['porQue']}',
                      style: TextStyle(
                          fontSize: 11, height: 1.35, color: cessumMuted(context))),
                  if (x['salida'] != null)
                    Text('Salida: ${x['salida']}',
                        style: const TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: Color(0xFF1E8E3E))),
                ],
              ),
            ),
          titulo('REGLAS DE JUSTICIA', const Color(0xFF8A5A0F)),
          for (final j in justicia)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('· $j',
                  style: const TextStyle(fontSize: 11, height: 1.4)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi informe de evaluación',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          // (24-sep) Plan de mejora con IA a partir de su propio informe.
          IconButton(
              tooltip: 'Plan de mejora con IA',
              onPressed: (_cargando || _planeando) ? null : _planMejora,
              icon: _planeando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome)),
          IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
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
                      if (_revisiones != null) _avisoRevisiones(),
                      // (ago-22) EL INFORME ABRE CON LO SUYO.
                      // El orden anterior ponía la lista de revisiones y un
                      // párrafo que prometía «se irá enriqueciendo con la
                      // evaluación de tus alumnos» cuando esa evaluación ya
                      // estaba más abajo, en esta misma pantalla, desde el 5
                      // de agosto. Prometer lo que ya se entrega hace dudar
                      // de todo lo demás que dice la pantalla.
                      if (_retro != null) _tarjetaEvaluaciones(_retro!),
                      if (_retro != null) _tarjetaRetro(_retro!),
                      const SizedBox(height: 6),
                      const Text('SEGUIMIENTO DE REVISIONES',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: cessumRed)),
                      const SizedBox(height: 6),
                      // El `!` de _tarjetaChecklist estaba FUERA de este
                      // else, sobre el mismo valor que la línea de arriba
                      // admite que puede ser nulo: a un docente sin historial
                      // la pantalla le reventaba entera.
                      if (_seguimiento == null)
                        Text(
                            'Aún sin historial de revisiones registrado.',
                            style: TextStyle(
                                fontSize: 12, color: cessumMuted(context)))
                      else ...[
                        _tarjetaSeguimiento(_seguimiento!),
                        _tarjetaChecklist(_seguimiento!),
                      ],
                      const SizedBox(height: 18),
                      Text(
                          'OBSERVACIONES DE CLASE (${_observaciones.length})',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: cessumRed)),
                      const SizedBox(height: 6),
                      if (_observaciones.isEmpty)
                        Text(
                            'Sin observaciones registradas todavía. Cuando '
                            'Coordinación observe una de tus clases, aquí '
                            'verás la retroalimentación completa.',
                            style: TextStyle(
                                fontSize: 12, color: cessumMuted(context))),
                      for (final o in _observaciones) _tarjetaObs(o),
                    ],
                  ),
                ),
    );
  }

  Widget _tarjetaSeguimiento(Map<String, dynamic> s) {
    final p = (s['puntajeIntegral'] ?? s['puntaje']) as num?;
    final c = _colorPuntaje(p);
    final pct = s['pctEnTiempo'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.55), width: 1.3),
      ),
      child: Row(
        children: [
          Column(children: [
            Text(p == null ? '—' : '$p',
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w900, color: c)),
            Text('puntos',
                style: TextStyle(fontSize: 10, color: cessumFaint(context))),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              pct == null
                  ? 'Aún sin historial suficiente.'
                  : 'Has revisado el $pct% de las actividades en tiempo y '
                      'forma (dentro del plazo de 72 horas). '
                      '${s['enTiempo']} en tiempo · ${s['tarde']} tarde · '
                      '${s['sinRevisar']} sin revisar.'
                      '${s['evalPromedio'] != null ? '\n🎓 Evaluación de tus alumnos: ${s['evalPromedio']} (${s['evalRespuestas']} respuestas) · ⭐ Puntaje integral: ${s['puntajeIntegral']}.' : ''}'
                      '${s['escalafon'] is Map ? '\n${(s['escalafon'] as Map)['emoji']} Escalafón: ${(s['escalafon'] as Map)['nivel']}${(s['escalafon'] as Map)['promedio4'] != null ? ' (promedio 4 semanas: ${(s['escalafon'] as Map)['promedio4']})' : ' — se construye con tus semanas registradas'}.' : ''}'
                      '${s['lugar'] != null ? '\nLugar ${s['lugar']} de ${s['deTotal']} docentes.' : ''}',
              style: const TextStyle(fontSize: 11.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  // (ago-5) MIS EVALUACIONES: promedio de alumnos, lugar en el ranking,
  // áreas de oportunidad y fortalezas con el nombre real de la dimensión.
  Widget _tarjetaEvaluaciones(Map<String, dynamic> r) {
    final ops = ((r['oportunidades'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final fts = ((r['fortalezas'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: cessumRed.withValues(alpha: 0.35), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.school, size: 18, color: cessumRed),
            SizedBox(width: 8),
            Text('MIS EVALUACIONES',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: cessumRed)),
          ]),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(children: [
                Text('${r['evalPromedio'] ?? '—'}',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: cessumRed)),
                Text('${r['evalRespuestas']} respuestas',
                    style: TextStyle(
                        fontSize: 10.5, color: cessumMuted(context))),
              ]),
              Column(children: [
                Text('${r['lugar']}º',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF8A5A0F))),
                Text('de ${r['deTotal']} docentes',
                    style: TextStyle(
                        fontSize: 10.5, color: cessumMuted(context))),
              ]),
              if (r['puntajeIntegral'] != null)
                Column(children: [
                  Text('${r['puntajeIntegral']}',
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E8E3E))),
                  Text('integral',
                      style: TextStyle(
                          fontSize: 10.5, color: cessumMuted(context))),
                ]),
            ],
          ),
          // ── (ago-19) LOS DOS PUNTAJES, LADO A LADO ──
          // Son distintos a propósito y mostrar uno solo obliga al docente a
          // adivinar cuál está viendo. Aquí se ven juntos, cada uno con lo
          // que mide y con el peso que le da a la revisión.
          if (r['puntajeSemanal'] is num) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _cajaPuntaje(
                  'ESTA SEMANA',
                  '${r['puntajeSemanal']}',
                  'Revisión 55% · Retro 22% · Sesiones 15% · Aula 8%',
                  'Lo que se mueve en siete días. Es el que puedes cambiar '
                      'antes del próximo lunes.',
                  const Color(0xFFB11D29),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _cajaPuntaje(
                  'GLOBAL',
                  '${r['puntajeIntegral'] ?? '—'}',
                  'Los ocho factores con su peso institucional',
                  r['baseSuficiente'] == false
                      ? 'Medido sobre ${r['pesoEvaluado'] ?? '—'} de 100 puntos '
                          'de peso: aún no es comparable.'
                      : 'El panorama completo, con ajustes.',
                  const Color(0xFF8A5A0F),
                ),
              ),
            ]),
            if (r['dimensionesSemana'] is List &&
                (r['dimensionesSemana'] as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Tu semana se compone así: ' +
                        (r['dimensionesSemana'] as List)
                            .map((e) =>
                                '${(e as Map)['etiqueta']} ${e['valor']} (${e['pesoSemanal']}%)')
                            .join(' · '),
                    style: TextStyle(
                        fontSize: 11, height: 1.4, color: cessumMuted(context))),
              ),
          ],

          // ── Tu trayectoria ──
          const SizedBox(height: 20),
          const Text('TU TRAYECTORIA',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF8A5A0F))),
          const SizedBox(height: 2),
          Text(
              'Un puntaje suelto no dice nada: 73 puede ser una recuperación o '
              'una caída. La línea gris es el promedio de toda la planta — si '
              'bajaron las dos, la semana estuvo dura para todos.',
              style: TextStyle(fontSize: 11.5, height: 1.45, color: cessumMuted(context))),
          const SizedBox(height: 10),
          if (_cargandoExtra)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: cessumRed)),
            )
          else
            _LineaTrayectoria(serie: _serie),

          // ── Preguntas para pensar ──
          const SizedBox(height: 20),
          _reflexion(r),

          // ── Qué sumó y qué restó ──
          if (r['ajustes'] is List && (r['ajustes'] as List).isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('AJUSTES SOBRE TU PROMEDIO',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
                'Hechos puntuales, no promedios. Si alguno no corresponde, '
                'avisa a Vicerrectoría con el caso concreto.',
                style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            const SizedBox(height: 6),
            for (final a in (r['ajustes'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map)))
              Container(
                margin: const EdgeInsets.only(bottom: 5),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: (a['signo'] == '+'
                          ? const Color(0xFF1E8E3E)
                          : const Color(0xFFC62828))
                      .withValues(alpha: 0.07),
                  border: Border(
                    left: BorderSide(
                        width: 3,
                        color: a['signo'] == '+'
                            ? const Color(0xFF1E8E3E)
                            : const Color(0xFFC62828)),
                  ),
                ),
                child: Text(
                    '${a['signo']}${a['puntos']}  ·  ${a['etiqueta']} — ${a['detalle']}',
                    style: const TextStyle(fontSize: 11.5, height: 1.4)),
              ),
          ],

          // ── Las reglas, completas ──
          if (_reglas != null) ...[
            const SizedBox(height: 12),
            _reglasEscalafon(),
          ],

          if (ops.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('🎯 ÁREAS DE OPORTUNIDAD (según tus alumnos)',
                style:
                    TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final o in ops)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                    '· ${o['texto']} — ${o['promedio']} (${o['n']} resp.)',
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
      ),
    );
  }

  // (ago-5) RETROALIMENTACIÓN: comentarios de mis alumnos y sugerencias
  // puntuales del motor institucional (las mismas del informe semanal).
  Widget _tarjetaRetro(Map<String, dynamic> r) {
    final coms = ((r['comentarios'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    final sugs = ((r['sugerencias'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    if (coms.isEmpty && sugs.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: cessumGold.withValues(alpha: 0.4), width: 1.3),
      ),
      child: Column(
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
                    style:
                        const TextStyle(fontSize: 11.5, height: 1.4)),
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
            // (ago-25) Ver TODOS los comentarios, no solo los tres últimos.
            // Con 39 respuestas, tres frases son una muestra que no permite
            // ver un patrón: un promedio dice dónde está parado el docente,
            // pero lo que le deja cambiar algo son las palabras de sus
            // alumnos, y se estaban tirando.
            if (((r['totalComentarios'] as num?)?.toInt() ?? 0) > coms.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InkWell(
                  onTap: () => _verTodosLosComentarios(r),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.forum_outlined,
                        size: 15, color: Color(0xFF8A5A0F)),
                    const SizedBox(width: 5),
                    Text(
                      'Leer los ${r['totalComentarios']} comentarios',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8A5A0F),
                          decoration: TextDecoration.underline),
                    ),
                  ]),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Todo lo que escribieron los alumnos, textual y anónimo.
  ///
  /// Se abre a pantalla completa y no en un cuadro pequeño: leer treinta
  /// comentarios en un recuadro de cuatro líneas es no leerlos. Y son
  /// seleccionables, para que el docente pueda copiarlos a su bitácora o a
  /// su informe.
  void _verTodosLosComentarios(Map<String, dynamic> r) {
    final todos = ((r['comentariosTodos'] as List?) ?? [])
        .map((e) => e.toString())
        .where((t) => t.trim().isNotEmpty)
        .toList();
    if (todos.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx2, scroll) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lo que escribieron tus alumnos',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cessumRed)),
                  const SizedBox(height: 4),
                  Text(
                    '${todos.length} comentario(s), del más reciente al más '
                    'antiguo. Son anónimos y textuales: nadie los editó.',
                    style: TextStyle(
                        fontSize: 12.5, color: cessumMuted(context)),
                  ),
                ],
              ),
            ),
            const Divider(height: 18),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: todos.length,
                itemBuilder: (c, i) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border(
                      left: BorderSide(
                          color: cessumGold.withValues(alpha: 0.6), width: 3),
                    ),
                  ),
                  child: SelectableText(
                    '“${todos[i]}”',
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.5,
                        fontStyle: FontStyle.italic),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // (ago-3) Checklist automático: lo que la plataforma revisa de mí para
  // una buena calificación en el ranking, palomeado en vivo.
  Widget _tarjetaChecklist(Map<String, dynamic> s) {
    final ck = s['checklist'];
    if (ck is! Map) return const SizedBox.shrink();
    final items = ((ck['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final cumplidos = (ck['cumplidos'] ?? 0) as num;
    final aplicables = (ck['aplicables'] ?? 0) as num;
    final completo = aplicables > 0 && cumplidos >= aplicables;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (completo ? const Color(0xFF1E8E3E) : cessumGold)
                .withValues(alpha: 0.5),
            width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(completo ? Icons.verified : Icons.checklist,
                size: 18,
                color: completo ? const Color(0xFF1E8E3E) : cessumGold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'MI CHECKLIST DE CALIDAD · $cumplidos de $aplicables ✓',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: completo
                        ? const Color(0xFF1E8E3E)
                        : cessumGold),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              'La plataforma verifica esto automáticamente; es lo que '
              'sostiene tu calificación en el ranking docente.',
              style: TextStyle(fontSize: 10.5, color: cessumFaint(context))),
          const SizedBox(height: 8),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      it['cumple'] == true
                          ? '✅'
                          : it['cumple'] == false
                              ? '⬜'
                              : '➖',
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${it['etiqueta']}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: it['cumple'] == false
                                    ? cessumRed
                                    : cessumInk(context))),
                        if ((it['detalle'] ?? '').toString().isNotEmpty)
                          Text('${it['detalle']}',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: cessumMuted(context))),
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

  Widget _tarjetaObs(Map<String, dynamic> o) {
    final cumple = (o['cumpleMinimo'] ?? '').toString();
    final dur = o['duracionMin'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: cumple == 'NO'
                ? const Color(0xFFE65100).withValues(alpha: 0.6)
                : cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  '${o['materia']}'.isEmpty
                      ? 'Observación de clase'
                      : '${o['materia']}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            Text('${o['fecha']}',
                style: TextStyle(
                    fontSize: 11, color: cessumFaint(context))),
          ]),
          if (dur != null)
            Text(
              'Duración de la sesión: $dur min '
              '${cumple == 'NO' ? '· ⚠ por debajo del mínimo de 50 min' : cumple == 'SI' ? '· ✓ cumple el mínimo' : ''}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cumple == 'NO'
                      ? const Color(0xFFE65100)
                      : const Color(0xFF1E8E3E)),
            ),
          if ((o['fortalezas'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('FORTALEZAS',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E8E3E))),
            Text('${o['fortalezas']}',
                style: const TextStyle(fontSize: 12, height: 1.4)),
          ],
          if ((o['recomendaciones'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('RECOMENDACIONES',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: cessumGold)),
            Text('${o['recomendaciones']}',
                style: const TextStyle(fontSize: 12, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  GRÁFICA DE TRAYECTORIA Y REFLEXIÓN DOCENTE  ·  19-ago-2026
//
//  Se pega al final de mi_informe_docente_screen.dart, fuera de la clase.
//
//  POR QUÉ UNA GRÁFICA Y NO OTRA TABLA
//  Un puntaje suelto no dice nada: «73» puede ser una recuperación o una
//  caída. La línea lo resuelve de un vistazo, y sobre todo permite ver la
//  forma —si viene subiendo despacio, si cayó de golpe, si lleva meses igual.
//
//  LA SEGUNDA LÍNEA IMPORTA MÁS QUE LA PRIMERA
//  Va el promedio de toda la planta. Sin él, cualquier bajada parece culpa
//  propia; con él, el docente ve si bajó él o si esa semana bajó todo el
//  mundo. Esa distinción es la diferencia entre culparse y entender.
//
//  NO SE DIBUJA CON MENOS DE TRES PUNTOS
//  Dos puntos siempre forman una recta perfecta y sugieren una tendencia que
//  no existe. Con menos de tres se dice cuántas semanas faltan.
// ═══════════════════════════════════════════════════════════════════════

class _LineaTrayectoria extends StatelessWidget {
  final List<Map<String, dynamic>> serie;
  const _LineaTrayectoria({required this.serie});

  @override
  Widget build(BuildContext context) {
    final puntos = serie
        .where((s) => s['integral'] is num)
        .toList();
    if (puntos.length < 3) {
      final faltan = 3 - puntos.length;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
            puntos.isEmpty
                ? 'Todavía no hay cortes guardados, así que no hay trayectoria '
                    'que mostrar. El primero se guarda el domingo.'
                : 'Llevas ${puntos.length} corte(s). Con $faltan más se dibuja '
                    'tu línea: con dos puntos cualquier par de números parece '
                    'una tendencia, y no lo es.',
            style: const TextStyle(fontSize: 12, height: 1.45)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 190,
          child: CustomPaint(
            size: const Size(double.infinity, 190),
            painter: _PintorLinea(puntos),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          _leyenda(cessumRed, 'Tu puntaje'),
          const SizedBox(width: 14),
          _leyenda(const Color(0xFF9E9E9E), 'Promedio de la planta'),
        ]),
      ],
    );
  }

  Widget _leyenda(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 3, color: c),
        const SizedBox(width: 5),
        Text(t, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
      ]);
}

class _PintorLinea extends CustomPainter {
  final List<Map<String, dynamic>> p;
  _PintorLinea(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    const izq = 30.0, abajo = 22.0, arriba = 10.0, der = 8.0;
    final w = size.width - izq - der;
    final h = size.height - abajo - arriba;

    // Escala fija de 0 a 100: es una calificación, y una escala que se ajusta
    // sola convierte una subida de dos puntos en una montaña.
    double x(int i) => izq + (p.length == 1 ? w / 2 : w * i / (p.length - 1));
    double y(num v) => arriba + h * (1 - v / 100);

    final guia = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 1;
    final texto = TextPainter(textDirection: TextDirection.ltr);
    for (final v in [0, 25, 50, 75, 100]) {
      final yy = y(v);
      canvas.drawLine(Offset(izq, yy), Offset(size.width - der, yy), guia);
      texto
        ..text = TextSpan(
            text: '$v',
            style: const TextStyle(fontSize: 9, color: Colors.black38))
        ..layout();
      texto.paint(canvas, Offset(izq - texto.width - 4, yy - 5));
    }

    // Banda del nivel esperado (70 a 100): da referencia sin juzgar.
    canvas.drawRect(
      Rect.fromLTRB(izq, y(100), size.width - der, y(70)),
      Paint()..color = const Color(0xFF1E8E3E).withValues(alpha: 0.05),
    );

    void linea(String campo, Color color, double grosor, bool puntos) {
      final trazo = Path();
      var primero = true;
      for (var i = 0; i < p.length; i++) {
        final v = p[i][campo];
        if (v is! num) continue;
        final o = Offset(x(i), y(v));
        if (primero) {
          trazo.moveTo(o.dx, o.dy);
          primero = false;
        } else {
          trazo.lineTo(o.dx, o.dy);
        }
        if (puntos) {
          canvas.drawCircle(o, 3.5, Paint()..color = color);
          canvas.drawCircle(
              o, 3.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
        }
      }
      canvas.drawPath(
          trazo,
          Paint()
            ..color = color
            ..strokeWidth = grosor
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
    }

    linea('promedioPlanta', const Color(0xFF9E9E9E), 1.6, false);
    linea('integral', cessumRed, 2.6, true);

    // Solo la primera y la última fecha: con doce semanas, doce etiquetas se
    // encinan y no se lee ninguna.
    void fecha(int i, TextAlign a) {
      texto
        ..text = TextSpan(
            text: '${p[i]['fecha'] ?? p[i]['semana'] ?? ''}',
            style: const TextStyle(fontSize: 9, color: Colors.black45))
        ..layout();
      final dx = a == TextAlign.left ? izq : size.width - der - texto.width;
      texto.paint(canvas, Offset(dx, size.height - abajo + 6));
    }
    fecha(0, TextAlign.left);
    if (p.length > 1) fecha(p.length - 1, TextAlign.right);
  }

  @override
  bool shouldRepaint(covariant _PintorLinea old) => old.p != p;
}
