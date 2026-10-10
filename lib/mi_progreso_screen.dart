import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'student_profile.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'avance_multiprograma_screen.dart';
import 'cessum_ui.dart';

/// Pantalla "Mi progreso académico" del alumno.
///
/// Muestra sus calificaciones agrupadas por periodo (trimestre o semestre,
/// según el programa). Reglas de color:
///   - "Validada" y aprobatoria (7 o más): VERDE con palomita (definitiva).
///   - "Validada" pero reprobatoria (menor a 7): ROJO (alerta real).
///   - "En validación": GRIS, con la leyenda "En proceso de validación".
class MiProgresoScreen extends StatefulWidget {
  const MiProgresoScreen({super.key});

  @override
  State<MiProgresoScreen> createState() => _MiProgresoScreenState();
}

// Verde institucional para calificaciones definitivas aprobatorias.
const Color _verdeOk = Color(0xFF1E8E3E);

class _Calif {
  final String programa;
  final String materia;
  final String ciclo;
  final String periodo; // forma canónica del periodo según cartas.json
  final String calificacion;
  final String enLetra;
  final String estatus; // "En validación" | "Validada"
  const _Calif({
    required this.programa,
    required this.materia,
    required this.ciclo,
    this.periodo = '',
    required this.calificacion,
    required this.enLetra,
    required this.estatus,
  });

  bool get enValidacion => estatus == 'En validación';

  // Valor numérico de la calificación (null si no es un número).
  double? get valor => double.tryParse(calificacion.replaceAll(',', '.'));

  // Reprobatoria solo si ya está validada y el número es menor a 7.
  bool get reprobada => !enValidacion && valor != null && valor! < 7;

  // Aprobada y definitiva.
  bool get aprobadaValidada => !enValidacion && valor != null && valor! >= 7;

  // No cursada: marcada así por el admin o validada pero sin número (p. ej.
  // alumno que regresa de baja temporal). No cuenta como reprobada ni aprobada.
  bool get noCursada =>
      estatus == 'No cursada' ||
      (!enValidacion && calificacion.trim().isEmpty);
}

class _MiProgresoScreenState extends State<MiProgresoScreen> {
  List<_Calif> _califs = [];
  List<Map<String, dynamic>> _faltantes = [];
  bool _cargando = true;
  String? _error;
  String _nombre = '';
  String _matricula = '';
  int _planTotal = 0;
  int _planValidadas = 0;

  /* (8-sep) PANTALLA ÚNICA DE AVANCE ACADÉMICO.
   * El alumno tenía cuatro tarjetas en el menú para la misma pregunta —Mis
   * calificaciones, Mi progreso, Mi avance del plan y Plan de estudios— y
   * ninguna respondía completa: el promedio oficial y la alerta de riesgo
   * vivían en una, los créditos y el egreso aproximado en otra, el historial
   * por ciclo en esta. Las tres leen la MISMA hoja de Calificaciones; el
   * propio Guardián cachea ese bloque diez minutos justo porque «el kardex,
   * la boleta y el avance leen lo mismo».
   * Ahora esta pantalla consulta las tres acciones a la vez y las junta. Cada
   * consulta falla por su cuenta: si el avance del plan no responde, se
   * pierden los créditos pero el historial se sigue viendo. */
  String _promedioOficial = '';
  num _aprobatoria = 7;
  List<Map<String, dynamic>> _riesgo = [];
  num _credTot = 0;
  num _credAprob = 0;
  int _porcCreditos = 0;
  String _egresoAprox = '';
  int _reprobadasPlan = 0;

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
      final perfil = await StudentProfile.load();
      final matricula = perfil?.matricula ?? '';
      _nombre = perfil?.nombreCompleto ?? '';
      _matricula = matricula;

      if (matricula.isEmpty) {
        setState(() {
          _cargando = false;
          _error = 'No encontramos tu matrícula. Revisa tu perfil.';
        });
        return;
      }

      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'progreso_alumno',
        'matricula': matricula,
        // Anti-caché: fuerza una URL única para que el GET no sirva una
        // respuesta vieja en caché (refleja al instante cambios de calificación).
        '_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      final planTotal = (data['totalPlan'] as num?)?.toInt() ?? 0;
      final planValidadas = (data['validadas'] as num?)?.toInt() ?? 0;
      final lista = (data['progreso'] as List<dynamic>? ?? []);
      final califs = lista.map((e) {
        final m = e as Map<String, dynamic>;
        return _Calif(
          programa: (m['programa'] ?? '').toString(),
          materia: (m['materia'] ?? '').toString(),
          ciclo: (m['ciclo'] ?? '').toString(),
          periodo: (m['periodo'] ?? '').toString(),
          calificacion: (m['calificacion'] ?? '').toString(),
          enLetra: (m['enLetra'] ?? '').toString(),
          estatus: (m['estatus'] ?? '').toString(),
        );
      }).toList();

      // Las dos consultas complementarias van en paralelo y NO son críticas:
      // lo que falle deja su bloque vacío en vez de tumbar la pantalla.
      await Future.wait([
        _cargarCalificaciones(matricula),
        _cargarAvancePlan(perfil),
      ]);

      if (mounted) {
        setState(() {
          _califs = califs;
          _planTotal = planTotal;
          _planValidadas = planValidadas;
          // (7-sep) El Guardián manda DOS listas: «faltantes» con los
          // nombres en texto plano y «faltantesDetalle» con el objeto que
          // incluye el periodo. Aquí se leía «faltantes» y se convertía cada
          // elemento a Map: con un texto eso revienta, el error caía en el
          // catch de abajo y el alumno veía «revisa tu conexión» aunque el
          // Guardián hubiera respondido bien.
          // Se usa el detalle, y si no viniera, se arma desde los nombres.
          final detalle = (data['faltantesDetalle'] as List?) ?? [];
          if (detalle.isNotEmpty) {
            _faltantes = detalle
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else {
            _faltantes = ((data['faltantes'] as List?) ?? [])
                .map((e) => e is Map
                    ? Map<String, dynamic>.from(e)
                    : <String, dynamic>{'materia': '$e', 'periodo': 99})
                .toList();
          }
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          // Antes este mensaje culpaba siempre a la conexión, y por eso un
          // error de formato en la respuesta parecía un problema de red:
          // el alumno reintentaba veinte veces sin que nada cambiara.
          final esRed = e is TimeoutException ||
              '$e'.contains('SocketException') ||
              '$e'.contains('Failed to fetch') ||
              '$e'.contains('XMLHttpRequest');
          _error = esRed
              ? 'No se pudo conectar. Revisa tu conexión e intenta de nuevo.'
              : 'No se pudo mostrar tu progreso. Ya avisamos a Vicerrectoría; '
                  'inténtalo más tarde.';
        });
      }
    }
  }

  /// Promedio oficial, mínima aprobatoria y materias en riesgo. Es lo que
  /// aportaba «Mis calificaciones»: el promedio no se recalcula aquí, se toma
  /// el que la institución reporta.
  Future<void> _cargarCalificaciones(String matricula) async {
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_calificaciones',
        'matricula': matricula,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) return;
      _promedioOficial = '${d['promedioGeneral'] ?? ''}'.trim();
      final ap = d['aprobatoria'];
      _aprobatoria =
          ap is num ? ap : (num.tryParse('${ap ?? ''}') ?? 7);
      _riesgo = ((d['riesgo'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final res = Map<String, dynamic>.from((d['resumen'] as Map?) ?? {});
      _reprobadasPlan =
          int.tryParse('${res['reprobadas'] ?? 0}') ?? 0;
    } catch (_) {
      // Silencioso a propósito: es información complementaria.
    }
  }

  /// Créditos y egreso aproximado. Es lo que aportaba «Mi avance del plan».
  Future<void> _cargarAvancePlan(StudentProfile? p) async {
    if (p == null || p.matricula.isEmpty) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'avance_plan',
        'matricula': p.matricula,
        'programa': p.programa,
        'generacion': p.generacion,
        'modalidad': p.modalidad,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 45));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) return;
      _credTot = (d['creditosTotales'] ?? 0) as num;
      _credAprob = (d['creditosAprobados'] ?? 0) as num;
      _porcCreditos =
          int.tryParse('${d['porcentajeCreditos'] ?? 0}') ?? 0;
      _egresoAprox = '${d['egresoAprox'] ?? ''}'.trim();
    } catch (_) {
      // Silencioso a propósito: es información complementaria.
    }
  }

  // ---- Utilidades de programa / periodo ----

  // Quita acentos y pasa a minúsculas para comparar sin depender de tildes.
  String _norm(String s) {
    s = s.toLowerCase();
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sin = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    return s;
  }

  // Normaliza el "ciclo" sin importar cómo venga el dato: "1", "Primero",
  // "Ciclo Primero", "Segundo Trimestre", "1er", etc. Devuelve 1..12, o 0
  // si no se reconoce.
  int _numCiclo(String texto) {
    var t = texto.toLowerCase().trim();
    const acentos = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u'};
    acentos.forEach((k, v) => t = t.replaceAll(k, v));
    final mDig = RegExp(r'\d+').firstMatch(t);
    if (mDig != null) {
      final n = int.tryParse(mDig.group(0)!);
      if (n != null && n >= 1 && n <= 12) return n;
    }
    // De más específico (12, 11) a menos, para no confundir "decimo".
    const palabras = <String, int>{
      'duodecimo': 12,
      'undecimo': 11,
      'decimo': 10,
      'noveno': 9,
      'octavo': 8,
      'septimo': 7,
      'sexto': 6,
      'quinto': 5,
      'cuarto': 4,
      'tercer': 3,
      'segundo': 2,
      'primer': 1,
    };
    for (final e in palabras.entries) {
      if (t.contains(e.key)) return e.value;
    }
    return 0;
  }

  // Encabezado consistente del ciclo: "Primer ciclo", "Segundo ciclo", etc.
  String _tituloPeriodo(String cicloTexto) {
    final n = int.tryParse(cicloTexto.trim()) ?? 0;
    if (n <= 0) return 'Sin ciclo asignado';
    const ordinal = {
      1: 'Primer',
      2: 'Segundo',
      3: 'Tercer',
      4: 'Cuarto',
      5: 'Quinto',
      6: 'Sexto',
      7: 'Séptimo',
      8: 'Octavo',
      9: 'Noveno',
      10: 'Décimo',
      11: 'Undécimo',
      12: 'Duodécimo',
    };
    final o = ordinal[n] ?? '$n.º';
    return '$o ciclo';
  }

  // Capitaliza cada palabra: "primer trimestre" -> "Primer Trimestre".
  String _cap(String s) {
    return s
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  // Agrupa por ciclo NORMALIZADO y usa la forma canónica del periodo según
  // cómo se organiza el posgrado (trimestre / semestre / cuatrimestre), que el
  // Guardián deriva de cartas.json. Si esa forma no está disponible, cae al
  // genérico "Primer ciclo", "Segundo ciclo", etc.
  List<MapEntry<String, List<_Calif>>> _agruparPorCiclo() {
    int numDe(_Calif c) =>
        _numCiclo(c.periodo.isNotEmpty ? c.periodo : c.ciclo);

    // Etiqueta canónica por número (la que trae cartas.json), si existe.
    final canonPorNum = <int, String>{};
    for (final c in _califs) {
      if (c.periodo.trim().isEmpty) continue;
      final n = numDe(c);
      if (n >= 1) canonPorNum.putIfAbsent(n, () => _cap(c.periodo.trim()));
    }

    final mapa = <int, List<_Calif>>{};
    for (final c in _califs) {
      mapa.putIfAbsent(numDe(c), () => []).add(c);
    }
    final entradas = mapa.entries.toList()
      ..sort((a, b) {
        final na = a.key == 0 ? 999 : a.key;
        final nb = b.key == 0 ? 999 : b.key;
        return na.compareTo(nb);
      });
    return entradas.map((e) {
      final etq = canonPorNum[e.key] ?? _tituloPeriodo(e.key.toString());
      return MapEntry(etq, e.value);
    }).toList();
  }

  // ---- Resumen (materias, validadas, promedio) ----
  int get _totalMaterias => _califs.length;
  int get _totalValidadas => _califs.where((c) => !c.enValidacion).length;

  // Si el Guardián nos dio el total del PLAN, el % se calcula contra el plan
  // completo (no solo contra las materias que ya tienen calificación).
  bool get _usaPlan => _planTotal > 0;
  int get _totalRef => _usaPlan ? _planTotal : _totalMaterias;
  int get _validadasRef => _usaPlan ? _planValidadas : _totalValidadas;

  // Colores que responden al tema (sin alterar el modo claro).
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : cessumInk(context);
  Color get _textoSuave => cessumMuted(context);
  Color get _gris => cessumIsDark(context) ? Colors.white54 : cessumFaint(context);

  // Promedio solo de las calificaciones validadas con número.
  String get _promedio {
    final nums = _califs
        .where((c) => !c.enValidacion && c.valor != null)
        .map((c) => c.valor!)
        .toList();
    if (nums.isEmpty) return '—';
    final prom = nums.reduce((a, b) => a + b) / nums.length;
    return prom.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi progreso académico'),
        actions: [
          IconButton(
            icon: const Icon(Icons.timeline),
            tooltip: 'Avance por programa',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AvanceMultiprogramaScreen(
                  matriculaInicial: _matricula,
                  soloPropio: true,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error != null
              ? _vistaError()
              : _califs.isEmpty
                  ? _vistaVacia()
                  : _vistaLista(),
    );
  }

  Widget _vistaLista() {
    final grupos = _agruparPorCiclo();
    final hayEnValidacion = _califs.any((c) => c.enValidacion);

    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Encabezado con nombre y matrícula
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: cessumRed, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nombre.isNotEmpty ? _nombre : 'Alumno',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _textoFuerte,
                        ),
                      ),
                      if (_matricula.isNotEmpty)
                        Text(
                          'Matrícula: $_matricula',
                          style: TextStyle(
                              fontSize: 12, color: _textoSuave),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Resumen: materias, validadas, promedio
          _resumen(),
          const SizedBox(height: 14),
          if (_credTot > 0 || _egresoAprox.isNotEmpty) ...[
            _tarjetaCreditos(),
            const SizedBox(height: 14),
          ],
          _tarjetaTitulacion(),
          const SizedBox(height: 14),
          if (_riesgo.isNotEmpty) ...[
            _tarjetaRiesgo(),
            const SizedBox(height: 14),
          ],
          // (ago-5) La meta completa: lo que falta para terminar, por ciclo.
          if (_faltantes.isNotEmpty) ...[
            _tarjetaFaltantes(),
            const SizedBox(height: 14),
          ],

          // Aviso si hay calificaciones en validación
          if (hayEnValidacion)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: cessumGold, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Las calificaciones en gris están en proceso de validación '
                      'por la Vicerrectoría. Aún no son definitivas.',
                      style: TextStyle(
                          fontSize: 12, color: _textoSuave, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),

          ...grupos.map((g) => _seccionCiclo(g.key, g.value)),
          const SizedBox(height: 20),
          _avisoRevision(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// (ago-25) Qué hacer si una calificación está mal o no aparece.
  ///
  /// Sin esto, el alumno que ve un error escribe por WhatsApp al docente o a
  /// quien le conteste primero, y el reclamo se pierde sin que nadie lleve la
  /// cuenta. Con un ticket queda folio, responsable y respuesta.
  ///
  /// Va al final: se lee después de revisar el avance, que es cuando surge la
  /// duda. Arriba sería una alarma antes de que hubiera algo que reclamar.
  Widget _avisoRevision() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: Colors.amber.shade800, width: 4),
          top: BorderSide(color: Colors.amber.withValues(alpha: 0.25)),
          right: BorderSide(color: Colors.amber.withValues(alpha: 0.25)),
          bottom: BorderSide(color: Colors.amber.withValues(alpha: 0.25)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.report_problem_outlined,
                size: 20, color: Colors.amber.shade900),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '¿Falta una calificación o crees que hay un error?',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.amber.shade900),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          const Text(
            'No lo dejes pasar ni lo reportes por WhatsApp: levanta un ticket '
            'en la Mesa de ayuda, en la categoría «Calificaciones». Así queda '
            'registrado con folio, se revisa con tu docente y te avisamos el '
            'resultado por este mismo sistema.',
            style: TextStyle(fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 10),
          Text(
            'Indica la materia, el ciclo y qué calificación esperabas. Si '
            'tienes el trabajo entregado o el correo del docente, adjúntalo: '
            'con evidencia se resuelve mucho más rápido.',
            style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.support_agent, size: 17, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Menú principal → Mesa de ayuda → Calificaciones',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _resumen() {
    final avance = _totalRef == 0 ? 0.0 : _validadasRef / _totalRef;
    final pct = (avance * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          StatRing(
            value: avance,
            centerText: '$pct%',
            label: 'Avance',
            color: cessumRed,
            size: 92,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Promedio', style: CessumType.label(12)),
                const SizedBox(height: 2),
                // (8-sep) Se prefiere el promedio que reporta la institución
                // sobre el calculado aquí: es el que aparece en el kárdex y en
                // los certificados, y era la razón por la que el alumno abría
                // «Mis calificaciones» aparte.
                Text(
                    _promedioOficial.isNotEmpty ? _promedioOficial : _promedio,
                    style: CessumType.display(34, color: cessumRed)),
                const SizedBox(height: 8),
                Text('$_validadasRef de $_totalRef materias validadas',
                    style: CessumType.body(12, color: cessumMuted(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Créditos y egreso aproximado. Venía de «Mi avance del plan», donde el
  /// alumno tenía que entrar aparte para saber cuánto lleva en créditos —que
  /// es la unidad con la que se mide un plan, no el número de materias.
  Widget _tarjetaCreditos() {
    final pct = (_porcCreditos.clamp(0, 100)) / 100.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Créditos', style: CessumType.label(12)),
                    const SizedBox(height: 2),
                    Text(
                        _credTot > 0
                            ? '${_sinCola(_credAprob)} de ${_sinCola(_credTot)}'
                            : '—',
                        style: CessumType.display(26, color: cessumGold)),
                  ],
                ),
              ),
              if (_egresoAprox.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Egreso aproximado', style: CessumType.label(12)),
                    const SizedBox(height: 4),
                    Text(_egresoAprox,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
            ],
          ),
          if (_credTot > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 9,
                backgroundColor: cessumGold.withValues(alpha: 0.18),
                valueColor: const AlwaysStoppedAnimation(cessumGold),
              ),
            ),
            const SizedBox(height: 6),
            Text('$_porcCreditos % de los créditos de tu plan',
                style: CessumType.body(12, color: cessumMuted(context))),
          ],
        ],
      ),
    );
  }

  String _sinCola(num v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Las dos vías de titulación por promedio, con la condición que casi nadie
  /// recuerda: una sola materia reprobada las anula aunque el promedio dé.
  /// El Reglamento pide además haber cursado sin interrupciones de ciclo, algo
  /// que esta pantalla no puede verificar y por eso se advierte.
  Widget _tarjetaTitulacion() {
    final prom = double.tryParse(_promedioOficial.replaceAll(',', '.')) ??
        double.tryParse(_promedio.replaceAll(',', '.'));
    final rep = _reprobadasPlan;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hacia dónde vas', style: CessumType.label(12)),
          const SizedBox(height: 10),
          _umbralTit('Excelencia Académica', 9.5, prom, rep),
          const SizedBox(height: 8),
          _umbralTit('Mención honorífica', 9.0, prom, rep),
          const SizedBox(height: 10),
          Text(
              rep > 0
                  ? (rep == 1
                      ? 'Tienes 1 materia reprobada. Mientras no la acredites, ninguna de las dos vías procede aunque el promedio alcance.'
                      : 'Tienes $rep materias reprobadas. Mientras no las acredites, ninguna de las dos vías procede aunque el promedio alcance.')
                  : 'Ambas piden además haber cursado el programa sin interrupciones de ciclo.',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: rep > 0
                      ? const Color(0xFFB3261E)
                      : cessumMuted(context))),
        ],
      ),
    );
  }

  Widget _umbralTit(String nombre, double meta, double? prom, int rep) {
    String detalle;
    Color color;
    if (prom == null) {
      detalle = 'aún sin promedio';
      color = cessumMuted(context);
    } else if (prom >= meta && rep == 0) {
      detalle = 'vas dentro';
      color = _verdeOk;
    } else if (prom >= meta) {
      detalle = 'el promedio alcanza, falta acreditar lo reprobado';
      color = const Color(0xFF8A5A0F);
    } else {
      detalle = 'te faltan ${(meta - prom).toStringAsFixed(2)} de promedio';
      color = cessumMuted(context);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 46,
          child: Text(meta.toStringAsFixed(1),
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(detalle,
                  style: TextStyle(fontSize: 12, color: color, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }

  /// Materias en riesgo. Venía de «Mis calificaciones» y es lo más accionable
  /// de toda la pantalla: dice qué hacer todavía a tiempo.
  Widget _tarjetaRiesgo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.09), // (24-sep) modo oscuro
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumRed.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.warning_amber_rounded, size: 18, color: cessumRed),
            SizedBox(width: 8),
            Text('Atención: materias en riesgo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          ..._riesgo.map((m) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${m['materia'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(
                        [
                          '${m['ciclo'] ?? ''}',
                          '${m['estatus'] ?? ''}',
                          '${m['necesita'] ?? ''}'
                        ].where((t) => t.trim().isNotEmpty).join(' · '),
                        style: TextStyle(
                            fontSize: 11.5, color: cessumMuted(context))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // (ago-5) LO QUE TE FALTA PARA TERMINAR: materias del plan aún no
  // cursadas, agrupadas por ciclo — la meta se ve completa y alcanzable.
  Widget _tarjetaFaltantes() {
    final porCiclo = <int, List<String>>{};
    for (final f in _faltantes) {
      final per = (f['periodo'] as num?)?.toInt() ?? 99;
      porCiclo.putIfAbsent(per, () => []).add(_capitaliza('${f['materia']}'));
    }
    final ciclos = porCiclo.keys.toList()..sort();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.flag, size: 17, color: Color(0xFF8A5A0F)),
            const SizedBox(width: 8),
            Text(
                _faltantes.length == 1
                    ? '🎯 ¡Solo te falta 1 materia para terminar!'
                    : '🎯 Te faltan ${_faltantes.length} materias para terminar',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A5A0F))),
          ]),
          const SizedBox(height: 8),
          for (final per in ciclos) ...[
            Text(per == 99 ? 'Por definir en tu plan' : 'Ciclo $per',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: cessumFaint(context),
                    letterSpacing: 0.5)),
            const SizedBox(height: 3),
            for (final m in porCiclo[per]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 2),
                child: Text('○ $m',
                    style:
                        const TextStyle(fontSize: 12.5, height: 1.35)),
              ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  String _capitaliza(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.length > 2
            ? '${w[0].toUpperCase()}${w.substring(1)}'
            : w)
        .join(' ');
  }

  Widget _seccionCiclo(String cicloTexto, List<_Calif> califs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado del periodo: "Primer trimestre" / "Primer semestre"
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: cessumRed.withValues(alpha: 0.08),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: cessumRed, size: 16),
                const SizedBox(width: 8),
                Text(
                  cicloTexto,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _textoFuerte,
                  ),
                ),
              ],
            ),
          ),
          // Materias del periodo
          ...califs.map(_renglonMateria),
        ],
      ),
    );
  }

  Widget _renglonMateria(_Calif c) {
    // Color de la calificación según estatus y aprobación.
    final Color color;
    if (c.enValidacion) {
      color = _gris; // gris: aún no definitiva
    } else if (c.noCursada) {
      color = _gris; // gris: no cursada / pendiente
    } else if (c.reprobada) {
      color = cessumRed; // rojo: reprobatoria validada
    } else {
      color = _verdeOk; // verde: validada y aprobatoria
    }
    final Color colorTexto = c.enValidacion ? _textoSuave : _textoFuerte;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.materia,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorTexto,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                _chipEstatus(c),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Calificación con palomita si es validada aprobatoria.
          Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  c.noCursada && c.calificacion.trim().isEmpty
                      ? '—'
                      : c.calificacion,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              if (c.aprobadaValidada)
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.check_circle, color: _verdeOk, size: 16),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Etiqueta de estatus debajo de cada materia.
  Widget _chipEstatus(_Calif c) {
    late final Color fondo;
    late final Color texto;
    late final IconData icono;
    late final String etiqueta;

    if (c.enValidacion) {
      fondo = cessumGold.withValues(alpha: 0.12);
      texto = const Color(0xFF8A6418);
      icono = Icons.hourglass_top;
      etiqueta = 'En proceso de validación';
    } else if (c.noCursada) {
      fondo = cessumIsDark(context)
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.06);
      texto = _textoSuave;
      icono = Icons.remove_circle_outline;
      etiqueta = 'No cursada';
    } else if (c.reprobada) {
      fondo = cessumRed.withValues(alpha: 0.12);
      texto = cessumRed;
      icono = Icons.warning_amber_rounded;
      etiqueta = 'Validada · no aprobatoria';
    } else {
      fondo = _verdeOk.withValues(alpha: 0.12);
      texto = _verdeOk;
      icono = Icons.verified;
      etiqueta = 'Validada';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: texto),
          const SizedBox(width: 4),
          Text(
            etiqueta,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: texto,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaVacia() {
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        children: const [
          SizedBox(height: 40),
          SizedBox(
            height: 360,
            child: CessumEmptyState(
              icon: Icons.school_outlined,
              title: 'Aún no tienes calificaciones',
              subtitle:
                  'Cuando tus profesores capturen tus calificaciones, aparecerán aquí.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: _textoSuave, height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
