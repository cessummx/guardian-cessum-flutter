// RECURSAMIENTOS · panel de Vicerrectoría  (20-ago-2026)
//
// QUÉ RESUELVE
// Las solicitudes de recursamiento llegaban a una hoja y ahí se quedaban.
// Nadie sabía quién había pagado, quién esperaba grupo, ni a quién faltaba
// matricular — y con eso, un alumno que pagó podía quedarse fuera del curso
// que ya empezó.
//
// DOS DECISIONES
//
// 1. PRIMERO LOS QUE YA PAGARON Y NO ESTÁN MATRICULADOS. Son los únicos que
//    se pueden resolver hoy, y los únicos donde la demora tiene costo real:
//    esa persona ya puso su dinero y está esperando entrar.
//
// 2. NO SE MATRICULA SIN PAGO VERIFICADO. Meter a alguien al grupo sin
//    comprobante deja a la institución sin cómo cobrarlo después, y a la
//    persona sin saber si debe. Se puede forzar, pero hay que decidirlo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'recursamiento_autogestivo_admin.dart';
import 'recursamiento_seguimiento_screen.dart';

class RecursamientosPanelScreen extends StatefulWidget {
  const RecursamientosPanelScreen({super.key});

  @override
  State<RecursamientosPanelScreen> createState() =>
      _RecursamientosPanelScreenState();
}

class _RecursamientosPanelScreenState extends State<RecursamientosPanelScreen> {
  List<Map<String, dynamic>> _lista = [];
  Map<String, dynamic> _oferta = {};
  /// (1-sep) La oferta de grupos se pedía en segundo plano y se descartaba
  /// cualquier error en silencio. Si esa consulta fallaba o llegaba tarde,
  /// la pantalla decía «no hay ningún grupo vigente» —que parece un dato— en
  /// vez de decir que no se pudo consultar. Ahora se distingue.
  /// Estado de la consulta POR ALUMNO: 'cargando' | 'ok' | 'error'. Antes era
  /// uno solo para toda la pantalla, así que el fallo de una consulta general
  /// que nadie pidió marcaba en rojo todas las tarjetas.
  final Map<String, String> _ofertaEstadoDe = {};
  final Map<String, String> _ofertaErrorDe = {};
  String _estadoDe(String mat) => _ofertaEstadoDe[mat] ?? 'sin-consultar';
  String _errorDe(String mat) => _ofertaErrorDe[mat] ?? '';
  bool _cargando = true;
  String _error = '';
  String _filtro = 'listos';

  /// (24-sep) Recursamientos autogestivos que esperan revisión.
  int _autogPorRevisar = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
    _contarAutog();
  }

  Future<void> _contarAutog() async {
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'autogestivo_admin'}))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() => _autogPorRevisar = (d['porRevisar'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {}
  }

  /* (22-sep) QUIÉN LLAMA. Verificar pagos, matricular y ver los datos de
     todas las solicitudes ahora es solo de Rectoría y Vicerrectoría: el
     Guardián lo comprueba con el correo de la sesión. Sin esto, cualquiera
     con el folio de una solicitud podía marcar un pago como verificado. */
  String? _actorCache;
  Future<Map<String, String>> _conActor(Map<String, String> params) async {
    _actorCache ??= await SessionStore.validEmail();
    return {...params, 'actor': _actorCache ?? ''};
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final qp = await _conActor({'accion': 'recurso_panel'});
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: qp))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');

      // (1-sep) La oferta YA NO se pide al abrir el panel. Esa consulta
      // recorre a todos los alumnos y tardaba minutos: hacía esperar de
      // balde y, al vencerse, pintaba «no se pudo consultar los grupos» en
      // tarjetas que nadie había abierto. Ahora se pide por alumno, cuando
      // se pulsa Matricular, y solo la primera vez de cada uno.

      if (!mounted) return;
      setState(() {
        _lista = ((d['lista'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar. $e';
      });
    }
  }

  List<Map<String, dynamic>> get _visibles {
    switch (_filtro) {
      case 'listos':
        return _lista
            .where((x) =>
                x['pagoVerificado'] == true && x['estado'] != 'Matriculado')
            .toList();
      case 'porpagar':
        // (2-oct-2026) "Interés" (materia sin ofertar, sin grupo todavía)
        // se excluye de aquí a propósito: antes caía en "Falta pago", que
        // es engañoso —no le falta pagar nada, ni siquiera hay grupo que
        // ofrecerle. Tiene su propio tab.
        return _lista
            .where((x) =>
                x['pagoVerificado'] != true &&
                x['estado'] != 'Matriculado' &&
                x['estado'] != 'Interés')
            .toList();
      case 'interes':
        return _lista.where((x) => x['estado'] == 'Interés').toList();
      case 'matriculados':
        return _lista.where((x) => x['estado'] == 'Matriculado').toList();
      default:
        return _lista;
    }
  }

  Future<void> _verificarPago(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verificar pago', style: TextStyle(fontSize: 16)),
        content: Text(
            '¿Confirmas que revisaste el comprobante de ${s['nombre']} '
            'por \$${s['costo']}?\n\nSe le avisa por correo que su pago quedó '
            'verificado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E7B34)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, verificado'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _llamar({'accion': 'recurso_pago_verificar', 'id': '${s['id']}'});
  }

  /// Matricula al alumno en un grupo. Se eligen las opciones que el backend
  /// detectó para SU materia y SU programa: escribir el grupo a mano invita a
  /// equivocarse justo en el dato que importa.
  Future<void> _matricular(Map<String, dynamic> s) async {
    final mat = '${s['matricula']}';
    /* (1-sep) EL DIÁLOGO SE ABRE DE INMEDIATO. Antes se esperaba la consulta
       ANTES de abrirlo: la persona pulsaba «Matricular» y no pasaba nada
       visible durante un minuto o dos, sin saber si había funcionado. Ahora
       el diálogo aparece al instante mostrando «Consultando grupos…» y se
       rellena solo cuando llega la respuesta.
       Se consulta una vez por alumno: si ya se consultó —haya grupos o no—
       no se vuelve a preguntar al reabrir. */
    final faltaConsultar = _estadoDe(mat) == 'sin-consultar';
    var opciones = _opcionesPara(s);
    Map<String, dynamic>? elegido = opciones.isNotEmpty ? opciones.first : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // La consulta arranca con el diálogo ya en pantalla, pero DESPUÉS
          // de que termine de dibujarse: _cargarOferta hace setState, y
          // llamarlo durante el build lanza excepción en Flutter.
          if (faltaConsultar && _estadoDe(mat) == 'sin-consultar') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_estadoDe(mat) != 'sin-consultar') return;
              _cargarOferta(matricula: mat).then((_) {
                if (ctx.mounted) {
                  setLocal(() {
                    opciones = _opcionesPara(s);
                    elegido = opciones.isNotEmpty ? opciones.first : null;
                  });
                }
              });
            });
          }
          return AlertDialog(
          title: Text('Matricular a ${s['nombre']}',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${s['materia']}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              if (opciones.isEmpty &&
                  (_estadoDe(mat) == 'cargando' || _estadoDe(mat) == 'sin-consultar'))
                const Row(children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text('Consultando los grupos disponibles…',
                          style: TextStyle(
                              fontSize: 12.5, color: Color(0xFF95590E)))),
                ])
              else if (opciones.isEmpty && _estadoDe(mat) == 'error')
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      'No se pudo consultar la lista de grupos '
                      '(${_errorDe(mat)}), así que NO se sabe si hay alguno '
                      'vigente. Vuelva a consultar antes de decidir: '
                      'matricular sin grupo cuando sí existe uno deja al '
                      'alumno fuera de la clase.',
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFFB11D29))),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () async {
                      await _cargarOferta(matricula: mat);
                      if (ctx.mounted) {
                        setLocal(() {
                          opciones = _opcionesPara(s);
                          elegido = opciones.isNotEmpty ? opciones.first : null;
                        });
                      }
                    },
                    icon: const Icon(Icons.refresh, size: 17),
                    label: const Text('Volver a consultar los grupos'),
                  ),
                ])
              else if (opciones.isEmpty)
                const Text(
                    'No hay ningún grupo vigente de esta materia, ni en su '
                    'programa ni en los planes hermanos. Puedes matricularlo '
                    'de todos modos y anotar el grupo después, o esperar a '
                    'que se abra uno.',
                    style: TextStyle(fontSize: 12.5))
              else
                // (ago-29) Los grupos de OTRO programa ya no se esconden: los
                // planes de CESSUM comparten asignaturas, y el panel decía
                // "no hay ningún grupo vigente" mientras la materia se estaba
                // impartiendo en un plan hermano. Se muestran, pero MARCADOS:
                // matricular fuera del programa propio es una decisión de
                // Vicerrectoría, no algo que deba pasar sin que se note.
                ...opciones.map((g) {
                  final otro = g['mismoPrograma'] == false;
                  // (1-sep) La modalidad se enseña siempre: un alumno sabatino
                  // que va a recursar entre semana debe saberlo antes, no el
                  // primer día de clase. Los imposibles ya no llegan aquí.
                  final mod = '${g['modalidad'] ?? ''}';
                  final modTxt = mod == 'sabatino'
                      ? 'sabatino'
                      : mod == 'entresemana'
                          ? 'entre semana'
                          : mod == 'mixta'
                              ? 'mixta'
                              : '';
                  final cambia = modTxt.isNotEmpty &&
                      '${g['modalidadAlumno'] ?? ''}' != mod &&
                      '${g['modalidadAlumno'] ?? ''}'.isNotEmpty;
                  return RadioListTile<Map<String, dynamic>>(
                    value: g,
                    groupValue: elegido,
                    onChanged: (v) => setLocal(() => elegido = v),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Row(children: [
                      Flexible(
                        child: Text(
                            'Grupo ${g['grupo']} · ${g['generacion'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      if (cambia) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E7B34).withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('cambia a $modTxt',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF14612C))),
                        ),
                      ],
                      if (otro) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            color: cessumGold.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('OTRO PROGRAMA',
                              style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: .4,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF8A6100))),
                        ),
                      ],
                    ]),
                    subtitle: Text(
                        '${otro ? '${g['programa'] ?? ''} · ' : ''}'
                        'Del ${_fechaEs(g['inicio'])} al ${_fechaEs(g['termino'])}'
                        '${g['docente'] != null && '${g['docente']}'.isNotEmpty ? ' · ${g['docente']}' : ''}'
                        '${g['yaEmpezo'] == true ? ' · YA INICIÓ' : ''}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: g['yaEmpezo'] == true
                                ? cessumRed
                                : Colors.black54)),
                  );
                }),
              if (_choquesPara(s) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      '${_choquesPara(s)} grupo(s) de esta materia no se muestran '
                      'porque chocan con el horario que ya cursa.',
                      style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Matricular'),
            ),
          ],
        );
        },
      ),
    );
    if (ok != true) return;

    await _llamar({
      'accion': 'recurso_matricular',
      'id': '${s['id']}',
      if (elegido != null) 'grupo': '${elegido!['grupo'] ?? ''}',
      if (elegido != null) 'generacion': '${elegido!['generacion'] ?? ''}',
      if (elegido != null) 'inicio': '${elegido!['inicio'] ?? ''}',
      if (elegido != null) 'termino': '${elegido!['termino'] ?? ''}',
      if (elegido != null) 'linkAula': '${elegido!['linkAula'] ?? ''}',
      // (1-sep) Estos cuatro faltaban y son justo lo que el alumno necesita
      // saber: con quién, qué día, a qué hora y si el grupo ya empezó.
      if (elegido != null) 'docente': '${elegido!['docente'] ?? ''}',
      if (elegido != null) 'dia': '${elegido!['dia'] ?? ''}',
      if (elegido != null) 'hora': '${elegido!['hora'] ?? ''}',
      if (elegido != null) 'yaEmpezo': '${elegido!['yaEmpezo'] == true}',
    });
  }

  /// (1-sep) Fecha legible en español. La hoja devuelve el objeto Date como
  /// «Mon Aug 17 2026 00:00:00 GMT-0700 (Mexican Pacific Standard Time)», que
  /// es ilegible en pantalla. Si no se reconoce, se muestra tal cual en vez
  /// de inventar una fecha.
  static const _mesesEs = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];
  static const _mesIng = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
  };
  String _fechaEs(dynamic v) {
    final t = '${v ?? ''}'.trim();
    if (t.isEmpty) return '?';
    // ISO: 2026-08-17
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
    if (iso != null) {
      final mes = int.parse(iso.group(2)!);
      if (mes >= 1 && mes <= 12) {
        return '${int.parse(iso.group(3)!)} de ${_mesesEs[mes - 1]} de ${iso.group(1)}';
      }
    }
    // Texto en inglés: Mon Aug 17 2026 …
    final ing = RegExp(r'\b([A-Za-z]{3})[a-z]*\s+(\d{1,2})\s+(\d{4})\b').firstMatch(t);
    if (ing != null) {
      final m = _mesIng[ing.group(1)!.toLowerCase()];
      if (m != null) {
        return '${int.parse(ing.group(2)!)} de ${_mesesEs[m - 1]} de ${ing.group(3)}';
      }
    }
    return t;
  }

  /// (1-sep) Consulta los grupos vigentes. Antes iba embebida en la carga
  /// del panel y cualquier error se descartaba en silencio: la pantalla
  /// decía «no hay ningún grupo vigente» —que parece un dato— cuando en
  /// realidad no se había podido preguntar. Ahora se puede reintentar sin
  /// recargar todo el panel.
  Future<void> _cargarOferta({String? matricula}) async {
    final k = matricula ?? '*';
    if (mounted) {
      setState(() {
        _ofertaEstadoDe[k] = 'cargando';
        _ofertaErrorDe[k] = '';
      });
    }
    try {
      final qpo = await _conActor({
        'accion': 'recurso_oferta',
        // Pedir solo el alumno que se está mirando: la respuesta completa
        // (34 alumnos con todos sus grupos) se pasaba del tiempo de espera.
        if (matricula != null && matricula.isNotEmpty) 'matricula': matricula,
      });
      final ro = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: qpo))
          // (1-sep) 90 s: Apps Script se pone lento en horas pico y 60 s
          // dejaba a medias consultas que sí iban a llegar.
          .timeout(const Duration(seconds: 90));
      if (!mounted) return;
      final o = jsonDecode(ro.body) as Map<String, dynamic>;
      if (o['ok'] == true) {
        setState(() {
          _ofertaEstadoDe[k] = 'ok';
          _ofertaErrorDe[k] = '';
          if (matricula == null || matricula.isEmpty) {
            _oferta = o;
          } else {
            // Consulta de un solo alumno: se añade a lo que ya se tenga, sin
            // borrar la oferta de los demás.
            final previa = List<dynamic>.from((_oferta['lista'] as List?) ?? []);
            previa.removeWhere((x) => '${x['matricula']}' == matricula);
            previa.addAll((o['lista'] as List?) ?? []);
            _oferta = {..._oferta, 'ok': true, 'lista': previa};
          }
        });
      } else {
        setState(() {
          _ofertaEstadoDe[k] = 'error';
          _ofertaErrorDe[k] = '${o['error'] ?? 'el Guardián rechazó la consulta'}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ofertaEstadoDe[k] = 'error';
        _ofertaErrorDe[k] = 'no respondió a tiempo';
      });
    }
  }

  /// Grupos vigentes que corresponden a la materia y programa de esta
  /// solicitud, según lo que detectó el backend.
  List<Map<String, dynamic>> _opcionesPara(Map<String, dynamic> s) {
    final out = <Map<String, dynamic>>[];
    final lista = (_oferta['lista'] as List?) ?? [];
    for (final a in lista) {
      final al = Map<String, dynamic>.from(a as Map);
      if ('${al['matricula']}' != '${s['matricula']}') continue;
      for (final m in (al['materias'] as List? ?? [])) {
        final mm = Map<String, dynamic>.from(m as Map);
        if (_norm('${mm['materia']}') != _norm('${s['materia']}')) continue;
        for (final g in (mm['opciones'] as List? ?? [])) {
          out.add(Map<String, dynamic>.from(g as Map));
        }
      }
    }
    return out;
  }

  /// (22-sep) Cuántos grupos de esta materia se descartaron porque chocan con
  /// el horario que el alumno ya cursa. Se dice en el diálogo: si no, «no hay
  /// grupos» parecería que la materia no se imparte.
  int _choquesPara(Map<String, dynamic> s) {
    var n = 0;
    for (final a in (_oferta['lista'] as List?) ?? []) {
      final al = Map<String, dynamic>.from(a as Map);
      if ('${al['matricula']}' != '${s['matricula']}') continue;
      for (final m in (al['materias'] as List? ?? [])) {
        final mm = Map<String, dynamic>.from(m as Map);
        if (_norm('${mm['materia']}') != _norm('${s['materia']}')) continue;
        n += (mm['descartadosPorChoque'] as num?)?.toInt() ?? 0;
      }
    }
    return n;
  }

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàä]'), 'a')
      .replaceAll(RegExp('[éèë]'), 'e')
      .replaceAll(RegExp('[íìï]'), 'i')
      .replaceAll(RegExp('[óòö]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> _llamar(Map<String, String> params) async {
    try {
      final qpl = await _conActor(params);
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: qpl));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor:
            d['ok'] == true ? const Color(0xFF1E7B34) : cessumRed,
        content: Text('${d['nota'] ?? d['error'] ?? 'Listo'}'),
      ));
      if (d['ok'] == true) _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final listos = _lista
        .where(
            (x) => x['pagoVerificado'] == true && x['estado'] != 'Matriculado')
        .length;
    final porPagar = _lista
        .where((x) =>
            x['pagoVerificado'] != true &&
            x['estado'] != 'Matriculado' &&
            x['estado'] != 'Interés')
        .length;
    final matriculados =
        _lista.where((x) => x['estado'] == 'Matriculado').length;
    final interesados =
        _lista.where((x) => x['estado'] == 'Interés').length;

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Recursamientos'),
        actions: [
          // (24-sep) Alumnos con reprobadas, verificación de avisos y WhatsApp.
          IconButton(
              tooltip: 'Seguimiento de reprobados y avisos',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RecursamientoSeguimientoScreen())),
              icon: const Icon(Icons.fact_check_outlined)),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error),
                    TextButton(
                        onPressed: _cargar, child: const Text('Reintentar')),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _chip('listos', 'Listos para matricular', listos,
                            const Color(0xFF1E7B34)),
                        _chip('porpagar', 'Falta pago', porPagar, cessumGold),
                        // (2-oct-2026) PREINSCRIPCIÓN DE INTERÉS — el alumno
                        // pidió recursar una materia que hoy no está
                        // ofertada. No hay grupo que asignar todavía: cae
                        // aquí para que decidas si abres un grupo, la
                        // ofreces autogestiva, o esperas.
                        _chip('interes', 'Interés · sin ofertar', interesados,
                            const Color(0xFF1565C0)),
                        _chip('matriculados', 'Matriculados', matriculados,
                            Colors.black54),
                        _chip('todos', 'Todos', _lista.length, Colors.black54),
                        _chip('autogestivo', 'Autogestivo · por revisar', _autogPorRevisar, cessumRed),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    if (_filtro == 'autogestivo')
                      AutogestivoAdminVista(
                        alCambiar: (n) {
                          if (mounted && n != _autogPorRevisar) setState(() => _autogPorRevisar = n);
                        },
                      )
                    else if (_visibles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                              _filtro == 'listos'
                                  ? 'Nadie espera matrícula. Todo al día.'
                                  : 'Sin registros en esta vista.',
                              style: TextStyle(color: cessumMuted(context))),
                        ),
                      )
                    else
                      ..._visibles.map(_tarjeta),
                  ],
                ),
    );
  }

  Widget _chip(String clave, String texto, int n, Color color) {
    final activo = _filtro == clave;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        onTap: () => setState(() => _filtro = clave),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: activo ? color : color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text('$texto ($n)',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: activo ? Colors.white : color)),
        ),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> s) {
    final esInteres = s['estado'] == 'Interés';
    final pagado = s['pagoVerificado'] == true;
    final matriculado = s['estado'] == 'Matriculado';
    final tieneComprobante = '${s['comprobante'] ?? ''}'.isNotEmpty;
    final opciones = _opcionesPara(s);

    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
              color: (esInteres
                      ? const Color(0xFF1565C0)
                      : matriculado
                          ? Colors.black26
                          : pagado
                              ? const Color(0xFF1E7B34)
                              : cessumGold)
                  .withValues(alpha: 0.4))),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s['nombre']}',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text(
                '${s['matricula']} · ${s['programa']}'
                '${'${s['generacion']}'.isNotEmpty ? ' · ${s['generacion']}' : ''}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${s['materia']}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  // (22-sep) EL ALUMNO YA PUEDE PEDIR CUALQUIER MATERIA DE SU
                  // PLAN, no solo una reprobada. Decir «Reprobada con » y
                  // dejar el hueco vacío haría ver como reprobada una materia
                  // que no lo está, justo cuando hay que valorar el caso.
                  Text(
                      ((s['calificacion'] ?? '').toString().trim().isEmpty
                              ? 'Solicitud de su plan de estudios (sin reprobación registrada)'
                              : 'Reprobada con ${s['calificacion']}') +
                          ' · solicitó el ${s['fecha']}'
                          '${(s['costo'] as num? ?? 0) > 0 ? ' · \$${s['costo']}' : ''}',
                      style: TextStyle(
                          fontSize: 11.5, color: cessumMuted(context))),
                  // (2-oct-2026) El bloque de "grupos disponibles" asume que
                  // hay algo que consultar; una solicitud de Interés no tiene
                  // eso todavía —se le muestra su propio aviso más abajo.
                  if (!matriculado && !esInteres)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                          opciones.isEmpty
                              ? (_estadoDe('${s['matricula']}') == 'sin-consultar'
                                  ? 'Pulse Matricular para ver los grupos'
                                  : _estadoDe('${s['matricula']}') == 'cargando'
                                      ? 'Consultando grupos…'
                                      : _estadoDe('${s['matricula']}') == 'error'
                                          ? 'No se pudo consultar los grupos'
                                          : 'Sin grupo vigente en ningún plan')
                              : '${opciones.length} grupo(s) disponible(s)',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              // Gris mientras no se ha consultado: no es un
                              // problema, es que todavía no se ha preguntado.
                              color: !opciones.isEmpty
                                  ? const Color(0xFF1565C0)
                                  : _estadoDe('${s['matricula']}') ==
                                          'sin-consultar'
                                      ? cessumMuted(context)
                                      : _estadoDe('${s['matricula']}') ==
                                              'cargando'
                                          ? const Color(0xFF95590E)
                                          : cessumRed)),
                    ),
                ],
              ),
            ),
            if ('${s['notas'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('${s['notas']}',
                  style: TextStyle(
                      fontSize: 11.5, color: cessumMuted(context))),
            ],
            const SizedBox(height: 9),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (tieneComprobante)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 33),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () {},
                  icon: const Icon(Icons.receipt_long, size: 15),
                  label: const Text('Ver comprobante',
                      style: TextStyle(fontSize: 12)),
                ),
              if (!pagado && tieneComprobante)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E7B34),
                      minimumSize: const Size(0, 33),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _verificarPago(s),
                  icon: const Icon(Icons.verified, size: 15),
                  label: const Text('Verificar pago',
                      style: TextStyle(fontSize: 12)),
                ),
              if (pagado && !matriculado)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: cessumRed,
                      minimumSize: const Size(0, 33),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _matricular(s),
                  icon: const Icon(Icons.how_to_reg, size: 15),
                  label: const Text('Matricular',
                      style: TextStyle(fontSize: 12)),
                ),
              if (matriculado)
                Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.check_circle, size: 16, color: Color(0xFF1E7B34)),
                  SizedBox(width: 5),
                  Text('Matriculado',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E7B34))),
                ]),
              if (esInteres)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.event_busy_outlined,
                      size: 16, color: Color(0xFF1565C0)),
                  const SizedBox(width: 5),
                  Text('Sin grupo ofertado · decide si abres uno o la ofreces autogestiva',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1565C0))),
                ])
              else if (!tieneComprobante && !matriculado)
                Text('Esperando su comprobante de pago',
                    style: TextStyle(
                        fontSize: 12, color: cessumMuted(context))),
            ]),
          ],
        ),
      ),
    );
  }
}
