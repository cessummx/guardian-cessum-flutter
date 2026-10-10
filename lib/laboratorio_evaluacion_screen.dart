// =====================================================================
//  laboratorio_evaluacion_screen.dart · CESSUM · Aula CESSUM
//  LABORATORIO DE EVALUACIÓN — de las actividades del aula a la
//  calificación del acta.
//
//  (9-oct-2026) El docente veía las notas de cada tarea en Moodle, la
//  asistencia en otra pantalla y las justificaciones en otra, y hacía la
//  cuenta de cabeza antes de capturar. Aquí está todo junto, por materia:
//
//    · Las actividades calificables del aula (tareas, foros, cuestionarios…)
//      con la nota de cada alumno normalizada a 0-10 y la marca de entrega
//      extemporánea.
//    · La asistencia a las sesiones síncronas de ESA materia, con las faltas
//      justificadas (validadas) contadas como asistencia.
//    · La regla del programa: Maestría en Educación = 80% actividades + 20%
//      asistencia; los demás posgrados = 100% actividades.
//    · Pesos editables por actividad (por defecto todas pesan igual), y una
//      sugerencia por alumno: promedio exacto y el entero 6-10 del acta.
//
//  «Pasar a captura» registra el desglose (hoja LaboratorioEvaluacion) y
//  lleva los enteros a «Capturar calificaciones»; el acta se guarda ahí,
//  como siempre. Nada de esto escribe en Moodle ni envía correos.
//
//  Backend:
//    GET  lab_evaluacion&programa=&generacion=&grupo=&materia=[&clave=]
//    POST lab_evaluacion_registrar (JSON)
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart';
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

// ---------- Modelos ----------

class _Nota {
  final double? nota; // 0-10 (ya normalizada por el Guardián)
  final double? bruta; // tal como está en Moodle
  final bool tarde;
  final bool? entregado;
  final int? participaciones;
  final bool excluida;
  const _Nota({
    this.nota,
    this.bruta,
    this.tarde = false,
    this.entregado,
    this.participaciones,
    this.excluida = false,
  });
  bool get sinCalificar => nota == null;
}

class _Act {
  final String itemid;
  final String nombre;
  final String tipo;
  final String tipoTexto;
  final String vence;
  final String link;
  final String categoria;
  final int seccion;
  final double max;
  final bool oculta;
  final bool visible;
  final bool escala;
  final int calificadas;
  final int sinCalificar;
  final int entregadas;
  final int tardias;
  bool incluida;
  double peso;
  String etiqueta;
  final TextEditingController pesoCtrl;
  _Act({
    required this.itemid,
    required this.nombre,
    required this.tipo,
    required this.tipoTexto,
    required this.vence,
    required this.link,
    required this.categoria,
    required this.seccion,
    required this.max,
    required this.oculta,
    required this.visible,
    required this.escala,
    required this.calificadas,
    required this.sinCalificar,
    required this.entregadas,
    required this.tardias,
    required this.incluida,
    this.peso = 0,
    this.etiqueta = '',
  }) : pesoCtrl = TextEditingController();
}

class _Al {
  final String matricula;
  final String nombre;
  final String correo;
  final String leyenda;
  final String estatusActa;
  final bool enAula;
  final bool recursamiento;
  final int? calificacionActa;
  final double? totalAula;
  final Map<String, _Nota> notas;
  final int sesiones;
  final int asistidas;
  final int justificadas;
  final int breves;
  final int pendientes;
  final List<String> faltas;
  final double? puntosAsis; // 0-10
  int? ajuste; // el docente fijó otro entero (6-10)
  bool abierto = false;
  _Al({
    required this.matricula,
    required this.nombre,
    required this.correo,
    required this.leyenda,
    required this.estatusActa,
    required this.enAula,
    required this.recursamiento,
    required this.calificacionActa,
    required this.totalAula,
    required this.notas,
    required this.sesiones,
    required this.asistidas,
    required this.justificadas,
    required this.breves,
    required this.pendientes,
    required this.faltas,
    required this.puntosAsis,
  });
}

/// Resultado del cálculo para un alumno con los pesos y opciones actuales.
class _Res {
  final double? promedio; // promedio ponderado de actividades (0-10)
  final double? sugerida; // exacta, ya con asistencia si aplica
  final int? entero; // 6-10 (sin ajuste manual)
  final bool sinDatos; // ninguna actividad calificada
  final int calificadas;
  final int usadas;
  const _Res({
    this.promedio,
    this.sugerida,
    this.entero,
    this.sinDatos = false,
    this.calificadas = 0,
    this.usadas = 0,
  });
}

// ---------- Pantalla ----------

class LaboratorioEvaluacionScreen extends StatefulWidget {
  final String programa;
  final String generacion;
  final String grupo;
  final String materia;
  final String clave;
  final String ciclo;
  final String modalidad;
  final String docente;

  /// true: se abrió desde «Capturar calificaciones» con el grupo ya cargado.
  /// «Pasar a captura» devuelve Map<String,int> (matrícula → entero) con
  /// Navigator.pop. false: se abrió desde «Mi horario» u otra pantalla;
  /// «Pasar a captura» abre la captura con la materia preseleccionada y las
  /// sugerencias ya puestas.
  final bool desdeCaptura;

  const LaboratorioEvaluacionScreen({
    super.key,
    required this.programa,
    required this.generacion,
    required this.grupo,
    required this.materia,
    this.clave = '',
    this.ciclo = '',
    this.modalidad = '',
    this.docente = '',
    this.desdeCaptura = false,
  });

  @override
  State<LaboratorioEvaluacionScreen> createState() =>
      _LaboratorioEvaluacionScreenState();
}

class _LaboratorioEvaluacionScreenState
    extends State<LaboratorioEvaluacionScreen> {
  bool _cargando = true;
  bool _enviando = false;
  String? _error;

  // Lo que respondió el Guardián.
  bool _esME = false;
  String _reglaTexto = '';
  String _clave = '';
  String _ciclo = '';
  String _modalidad = '';
  String _docente = '';
  String _courseid = '';
  String _curso = '';
  String _linkAula = '';
  String _linkLibro = '';
  int _sesiones = 0;
  List<String> _fechasSesiones = [];
  int _minimoMinutos = 0;
  String _notaAsistencia = '';
  Map<String, dynamic> _materiasConRegistro = {};
  List<String> _sinAula = [];
  List<Map<String, dynamic>> _sinMapear = [];
  String _generado = '';

  List<_Act> _actividades = [];
  List<_Al> _alumnos = [];

  // Opciones de cálculo (las decide el docente; se registran con el desglose).
  bool _proyeccion = false; // ignorar actividades sin calificar
  bool _topeTardias = false; // tope 8.0 a entregas extemporáneas
  bool _sugerirSinDatos = false; // sugerir 6 a quien no tiene nada calificado
  bool _soloSinDatos = false; // filtro de la lista
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final a in _actividades) {
      a.pesoCtrl.dispose();
    }
    super.dispose();
  }

  // ---------- Carga ----------

  double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  int _i(dynamic v, [int def = 0]) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? def;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final params = <String, String>{
        'accion': 'lab_evaluacion',
        'programa': widget.programa,
        'generacion': widget.generacion,
        'grupo': widget.grupo,
        'materia': widget.materia,
      };
      if (widget.clave.trim().isNotEmpty) params['clave'] = widget.clave.trim();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final r = await http.get(uri).timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;

      // Los controladores de la carga anterior se sueltan después del cuadro,
      // cuando ya ningún campo los usa.
      final viejos = _actividades.map((a) => a.pesoCtrl).toList();
      if (viejos.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final c in viejos) {
            c.dispose();
          }
        });
      }
      final regla = (d['regla'] as Map?) ?? {};
      final aula = (d['aula'] as Map?) ?? {};
      final asis = (d['asistencia'] as Map?) ?? {};

      final acts = <_Act>[];
      int nT = 0, nF = 0, nC = 0, nO = 0;
      for (final e in (d['actividades'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(e as Map);
        final tipo = (m['tipo'] ?? '').toString();
        String etq;
        if (tipo == 'assign') {
          etq = 'T${++nT}';
        } else if (tipo == 'forum') {
          etq = 'F${++nF}';
        } else if (tipo == 'quiz') {
          etq = 'C${++nC}';
        } else {
          etq = 'A${++nO}';
        }
        acts.add(_Act(
          itemid: (m['itemid'] ?? '').toString(),
          nombre: (m['nombre'] ?? '').toString(),
          tipo: tipo,
          tipoTexto: (m['tipoTexto'] ?? tipo).toString(),
          vence: (m['vence'] ?? '').toString(),
          link: (m['link'] ?? '').toString(),
          categoria: (m['categoria'] ?? '').toString(),
          seccion: _i(m['seccion']),
          max: _d(m['max']) ?? 0,
          oculta: m['oculta'] == true,
          visible: m['visible'] != false,
          escala: m['escala'] == true,
          calificadas: _i(m['calificadas']),
          sinCalificar: _i(m['sinCalificar']),
          entregadas: _i(m['entregadas']),
          tardias: _i(m['tardias']),
          incluida: m['incluida'] == true,
          etiqueta: etq,
        ));
      }

      final als = <_Al>[];
      for (final e in (d['alumnos'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(e as Map);
        final notas = <String, _Nota>{};
        final nm = (m['notas'] as Map?) ?? {};
        nm.forEach((k, v) {
          final x = Map<String, dynamic>.from(v as Map);
          notas[k.toString()] = _Nota(
            nota: _d(x['nota']),
            bruta: _d(x['bruta']),
            tarde: x['tarde'] == true,
            entregado: x['entregado'] == null ? null : (x['entregado'] == true),
            participaciones:
                x['participaciones'] == null ? null : _i(x['participaciones']),
            excluida: x['excluida'] == true,
          );
        });
        final am = (m['asistencia'] as Map?) ?? {};
        final califActa = _d(m['calificacionActa']);
        als.add(_Al(
          matricula: (m['matricula'] ?? '').toString(),
          nombre: (m['nombre'] ?? '').toString(),
          correo: (m['correo'] ?? '').toString(),
          leyenda: (m['leyenda'] ?? '').toString(),
          estatusActa: (m['estatusActa'] ?? '').toString(),
          enAula: m['enAula'] == true,
          recursamiento: m['recursamiento'] == true,
          calificacionActa: califActa?.round(),
          totalAula: _d(m['totalAula']),
          notas: notas,
          sesiones: _i(am['sesiones']),
          asistidas: _i(am['asistidas']),
          justificadas: _i(am['justificadas']),
          breves: _i(am['breves']),
          pendientes: _i(am['pendientes']),
          faltas: (am['faltas'] as List? ?? []).map((x) => x.toString()).toList(),
          puntosAsis: _d(am['puntos']),
        ));
      }
      als.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

      setState(() {
        _esME = d['esME'] == true;
        _reglaTexto = (regla['texto'] ?? '').toString();
        _clave = (d['clave'] ?? widget.clave).toString();
        _ciclo = (d['ciclo'] ?? widget.ciclo).toString();
        _modalidad = (d['modalidad'] ?? widget.modalidad).toString();
        _docente = (d['docente'] ?? widget.docente).toString();
        _courseid = (aula['courseid'] ?? '').toString();
        _curso = (aula['curso'] ?? '').toString();
        _linkAula = (aula['link'] ?? '').toString();
        _linkLibro = (aula['libro'] ?? '').toString();
        _sesiones = _i(asis['sesiones']);
        _fechasSesiones =
            (asis['fechas'] as List? ?? []).map((x) => x.toString()).toList();
        _minimoMinutos = _i(asis['minimoMinutos']);
        _notaAsistencia = (asis['nota'] ?? '').toString();
        _materiasConRegistro =
            Map<String, dynamic>.from((asis['materiasConRegistro'] as Map?) ?? {});
        _sinAula = (d['sinAula'] as List? ?? []).map((x) => x.toString()).toList();
        _sinMapear = (d['sinMapear'] as List? ?? [])
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        _generado = (d['generado'] ?? '').toString();
        _actividades = acts;
        _alumnos = als;
        _igualarPesos();
      });
    } catch (e) {
      final m = '$e'.replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() => _error = (m.contains('TimeoutException') ||
                m.contains('ClientException') ||
                m.contains('SocketException') ||
                m.startsWith('FormatException'))
            ? 'No se pudo cargar el laboratorio. Revisa tu conexión e intenta de nuevo.'
            : m);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ---------- Pesos ----------

  List<_Act> get _incluidas => _actividades.where((a) => a.incluida).toList();

  double get _sumaPesos =>
      _incluidas.fold(0.0, (s, a) => s + (a.peso > 0 ? a.peso : 0));

  /// Todas las actividades incluidas pesan igual (la regla ordinaria).
  void _igualarPesos() {
    final inc = _incluidas;
    for (final a in _actividades) {
      if (!a.incluida) {
        a.peso = 0;
        a.pesoCtrl.text = '';
        continue;
      }
      a.peso = inc.isEmpty ? 0.0 : 100.0 / inc.length;
      a.pesoCtrl.text = _pesoTxt(a.peso);
    }
  }

  String _pesoTxt(double p) {
    if (p <= 0) return '';
    final r = (p * 100).round() / 100;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2);
  }

  void _toggleActividad(_Act a, bool v) {
    setState(() {
      a.incluida = v;
      _igualarPesos();
    });
  }

  void _pesoCambiado(_Act a, String txt) {
    final v = double.tryParse(txt.trim().replaceAll(',', '.'));
    setState(() => a.peso = (v == null || v < 0) ? 0.0 : v);
  }

  // ---------- Cálculo ----------

  _Res _calcular(_Al al) {
    double suma = 0, sumaPeso = 0;
    int usadas = 0, calificadas = 0;
    for (final act in _actividades) {
      if (!act.incluida) continue;
      final n = al.notas[act.itemid];
      double? v = n?.nota;
      if (v == null) {
        if (_proyeccion) continue; // se proyecta sin esa actividad
        v = 0; // al cierre, lo no calificado cuenta cero
      } else {
        calificadas++;
        if (_topeTardias && (n?.tarde ?? false) && v > 8) v = 8;
      }
      final p = act.peso > 0 ? act.peso : 0.0;
      suma += v * p;
      sumaPeso += p;
      usadas++;
    }
    final prom = sumaPeso > 0 ? suma / sumaPeso : null;
    final sinDatos = calificadas == 0;
    if (sinDatos && !_sugerirSinDatos) {
      return _Res(
          promedio: prom, sinDatos: true, calificadas: 0, usadas: usadas);
    }
    double? sug;
    if (prom != null) {
      if (_esME && al.sesiones > 0 && al.puntosAsis != null) {
        sug = prom * 0.8 + al.puntosAsis! * 0.2;
      } else {
        sug = prom;
      }
    } else if (sinDatos && _sugerirSinDatos) {
      sug = 0;
    }
    final ent = sug == null ? null : sug.round().clamp(6, 10).toInt();
    return _Res(
        promedio: prom,
        sugerida: sug,
        entero: ent,
        sinDatos: sinDatos,
        calificadas: calificadas,
        usadas: usadas);
  }

  int? _enteroFinal(_Al al, _Res r) => al.ajuste ?? r.entero;

  Map<int, int> get _distribucion {
    final m = <int, int>{6: 0, 7: 0, 8: 0, 9: 0, 10: 0};
    for (final al in _alumnos) {
      final e = _enteroFinal(al, _calcular(al));
      if (e != null) m[e] = (m[e] ?? 0) + 1;
    }
    return m;
  }

  List<_Al> get _visibles {
    final q = _busqueda.trim().toLowerCase();
    return _alumnos.where((al) {
      if (_soloSinDatos) {
        final r = _calcular(al);
        if (!r.sinDatos && al.enAula) return false;
      }
      if (q.isEmpty) return true;
      return al.nombre.toLowerCase().contains(q) ||
          al.matricula.toLowerCase().contains(q);
    }).toList();
  }

  String _f1(double? v) => v == null ? '—' : v.toStringAsFixed(1);
  String _f2(double? v) => v == null ? '—' : v.toStringAsFixed(2);

  // ---------- Pasar a captura ----------

  Future<void> _pasarACaptura() async {
    final mapa = <String, int>{};
    int sinSug = 0, seis = 0;
    double suma = 0;
    for (final al in _alumnos) {
      final e = _enteroFinal(al, _calcular(al));
      if (e == null) {
        sinSug++;
        continue;
      }
      mapa[al.matricula] = e;
      suma += e;
      if (e == 6) seis++;
    }
    if (mapa.isEmpty) {
      _aviso('No hay ninguna calificación sugerida todavía.');
      return;
    }
    final prom = suma / mapa.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pasar a captura', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Las calificaciones sugeridas se llevarán a «Capturar '
              'calificaciones», donde podrás revisarlas antes de guardar el acta.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            _filaResumen('Alumnos con sugerencia', '${mapa.length}'),
            _filaResumen('Aprobados (7-10)', '${mapa.length - seis}',
                const Color(0xFF1E8E3E)),
            _filaResumen('No acreditados (6)', '$seis', cessumRed),
            if (sinSug > 0)
              _filaResumen('Sin sugerencia (quedan en blanco)', '$sinSug',
                  cessumGold),
            _filaResumen('Promedio del grupo', prom.toStringAsFixed(1)),
            const SizedBox(height: 10),
            Text(
              'El desglose (pesos y notas por actividad) queda registrado para '
              'consulta. El acta NO se guarda aquí.',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _enviando = true);
    final registrado = await _registrarDesglose();
    if (!mounted) return;
    setState(() => _enviando = false);
    if (!registrado) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No se pudo registrar el desglose',
              style: TextStyle(fontSize: 16)),
          content: const Text(
            'Las sugerencias se calcularon, pero el registro del desglose no '
            'llegó al servidor. ¿Quieres pasarlas a captura de todos modos?',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pasar de todos modos'),
            ),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }

    if (widget.desdeCaptura) {
      Navigator.pop(context, mapa);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CapturaCalificacionesScreen(
          preseleccion: {
            'programa': widget.programa,
            'generacion': widget.generacion,
            'grupo': widget.grupo,
            'materia': widget.materia,
            'clave': _clave,
            'ciclo': _ciclo,
            'modalidad': _modalidad,
          },
          sugerencias: mapa,
        ),
      ),
    );
  }

  Future<bool> _registrarDesglose() async {
    try {
      final capturadoPor = await SessionStore.validEmail() ?? '';
      final pesos = _actividades
          .map((a) => {
                'itemid': a.itemid,
                'etiqueta': a.etiqueta,
                'nombre': a.nombre,
                'tipo': a.tipo,
                'incluida': a.incluida,
                'peso': a.incluida ? a.peso : 0,
              })
          .toList();
      final alumnos = _alumnos.map((al) {
        final r = _calcular(al);
        final notas = <String, dynamic>{};
        for (final act in _actividades) {
          if (!act.incluida) continue;
          final n = al.notas[act.itemid];
          notas[act.etiqueta] = {
            'nota': n?.nota,
            'tarde': n?.tarde ?? false,
          };
        }
        final e = _enteroFinal(al, r);
        return {
          'matricula': al.matricula,
          'nombre': al.nombre,
          'correo': al.correo,
          'notas': notas,
          'promedio': r.promedio,
          'sugerida': r.sugerida,
          'entero': e,
          'ajustada': al.ajuste != null,
          'pasaACaptura': e != null,
          'asistencia': {
            'sesiones': al.sesiones,
            'asistidas': al.asistidas,
            'justificadas': al.justificadas,
            'puntos': al.puntosAsis,
          },
          'observacion': [
            if (!al.enAula) 'No está inscrito en el aula',
            if (r.sinDatos) 'Sin actividades calificadas',
            if (al.ajuste != null) 'Entero ajustado por el docente',
            if (al.pendientes > 0) '${al.pendientes} justificación(es) pendiente(s)',
          ].join('; '),
        };
      }).toList();
      final payload = {
        'accion': 'lab_evaluacion_registrar',
        'capturadoPor': capturadoPor,
        'modoPrueba': false,
        'programa': widget.programa,
        'generacion': widget.generacion,
        'grupo': widget.grupo,
        'materia': widget.materia,
        'clave': _clave,
        'ciclo': _ciclo,
        'docente': _docente,
        'courseid': _courseid,
        'esME': _esME,
        'regla': _esME
            ? '80% actividades + 20% asistencia'
            : '100% actividades',
        'opciones': {
          'proyeccion': _proyeccion,
          'topeTardias': _topeTardias,
          'sugerirSinDatos': _sugerirSinDatos,
        },
        'pesos': pesos,
        'alumnos': alumnos,
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Copiar ----------

  void _copiarResumen() {
    final inc = _incluidas;
    final sb = StringBuffer()
      ..writeln('${widget.materia}\t${widget.programa} ${widget.generacion} Grupo ${widget.grupo}')
      ..writeln(_esME
          ? 'Regla: 80% actividades + 20% asistencia'
          : 'Regla: 100% actividades');
    sb.write('Alumno\tMatrícula');
    for (final a in inc) {
      sb.write('\t${a.etiqueta} ${a.nombre} (${_pesoTxt(a.peso)}%)');
    }
    sb.writeln('\tPromedio actividades\tAsistencia\tExacta\tEntero');
    for (final al in _alumnos) {
      final r = _calcular(al);
      sb.write('${al.nombre}\t${al.matricula}');
      for (final a in inc) {
        final n = al.notas[a.itemid];
        sb.write('\t${n?.nota == null ? '' : _f1(n!.nota)}${(n?.tarde ?? false) ? ' (tarde)' : ''}');
      }
      final asisTxt = al.sesiones > 0
          ? '${al.asistidas + al.justificadas} de ${al.sesiones}'
          : '';
      final e = _enteroFinal(al, r);
      sb.writeln('\t${_f2(r.promedio)}\t$asisTxt\t${_f2(r.sugerida)}\t${e ?? ''}');
    }
    Helpers.copiarAlPortapapeles(context, sb.toString(), 'Resumen del laboratorio');
  }

  // ---------- UI ----------

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  Widget _filaResumen(String etiqueta, String valor, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(etiqueta, style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 8),
          Text(valor,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color ?? cessumInk(context))),
        ],
      ),
    );
  }

  Color get _superficie => Theme.of(context).cardColor;
  Color get _borde => cessumIsDark(context) ? Colors.white12 : Colors.black12;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Laboratorio de evaluación'),
        actions: [
          IconButton(
              tooltip: 'Copiar el resumen para Excel',
              icon: const Icon(Icons.table_chart_outlined),
              onPressed:
                  _cargando || _alumnos.isEmpty ? null : _copiarResumen),
          IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _cargando ? null : _cargar),
        ],
      ),
      body: _cargando
          ? const Padding(
              padding: EdgeInsets.all(12), child: CessumSkeletonList())
          : _error != null
              ? _vistaError()
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
                    children: [
                      _cabecera(),
                      const SizedBox(height: 14),
                      _tarjetaActividades(),
                      const SizedBox(height: 12),
                      _tarjetaAsistencia(),
                      const SizedBox(height: 12),
                      _tarjetaOpciones(),
                      const SizedBox(height: 14),
                      _tituloAlumnos(),
                      const SizedBox(height: 8),
                      _filtros(),
                      const SizedBox(height: 10),
                      ..._visibles.map(_filaAlumno),
                      if (_visibles.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                              child: Text('Nadie coincide con el filtro.',
                                  style: TextStyle(color: cessumMuted(context)))),
                        ),
                      const SizedBox(height: 14),
                      _distribucionWidget(),
                      const SizedBox(height: 12),
                      if (_sinMapear.isNotEmpty) _notaSinMapear(),
                      _notaFinal(),
                    ],
                  ),
                ),
      bottomNavigationBar: _cargando || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _enviando ? null : _pasarACaptura,
                    icon: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.edit_note),
                    label: Text(_enviando
                        ? 'Registrando…'
                        : 'Pasar a captura de calificaciones'),
                  ),
                ),
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
              Text(_error ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.4)),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white),
                  onPressed: _cargar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _cabecera() {
    final inc = _incluidas.length;
    return Container(
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
          Text(widget.materia,
              style: CessumType.heading(15, color: Colors.white)),
          const SizedBox(height: 2),
          Text(
              '${widget.programa} · ${widget.generacion} · Grupo ${widget.grupo}'
              '${_clave.isNotEmpty ? ' · $_clave' : ''}',
              style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
          if (_docente.isNotEmpty)
            Text(_docente,
                style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.rule, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _reglaTexto.isNotEmpty
                        ? _reglaTexto
                        : (_esME
                            ? 'Maestría en Educación: 80% actividades + 20% asistencia.'
                            : 'Las actividades constituyen el 100% de la calificación.'),
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.white, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('$inc', 'actividades\nincluidas'),
              _stat('${_alumnos.length}', 'alumnos\nen el grupo'),
              _stat('$_sesiones', 'sesiones\nsíncronas'),
              _stat('${_sinAula.length}', 'sin cuenta\nen el aula'),
            ],
          ),
          if (_linkLibro.isNotEmpty || _linkAula.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                if (_linkLibro.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: () =>
                        Helpers.abrirUrlExterna(_linkLibro, context),
                    icon: const Icon(Icons.grid_on, size: 15),
                    label: const Text('Libro de calificaciones',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                if (_linkAula.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: () =>
                        Helpers.abrirUrlExterna(_linkAula, context),
                    icon: const Icon(Icons.school, size: 15),
                    label: Text(
                        _curso.isNotEmpty ? 'Aula · $_curso' : 'Aula',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String n, String etq) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n, style: CessumType.display(24, color: Colors.white)),
            Text(etq,
                style: const TextStyle(
                    fontSize: 10, color: Colors.white70, height: 1.2)),
          ],
        ),
      );

  Widget _tarjeta({required String titulo, Widget? accion, required Widget hijo}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cessumRed,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (accion != null) accion,
            ],
          ),
          const SizedBox(height: 10),
          hijo,
        ],
      ),
    );
  }

  Widget _chip(String txt, Color fg, Color bg, {IconData? icono}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono, size: 11, color: fg),
              const SizedBox(width: 3),
            ],
            Text(txt,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      );

  Widget _tarjetaActividades() {
    final suma = _sumaPesos;
    final incN = _incluidas.length;
    final sumaOk = incN == 0 || (suma - 100).abs() < 0.05;
    return _tarjeta(
      titulo: 'ACTIVIDADES DEL AULA Y SU PESO',
      accion: TextButton.icon(
        style: TextButton.styleFrom(
            foregroundColor: cessumGold,
            padding: const EdgeInsets.symmetric(horizontal: 6)),
        onPressed: _actividades.isEmpty ? null : () => setState(_igualarPesos),
        icon: const Icon(Icons.balance, size: 16),
        label: const Text('Igualar pesos', style: TextStyle(fontSize: 11.5)),
      ),
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_actividades.isEmpty)
            Text(
              'El aula no tiene actividades calificables (tareas, foros o '
              'cuestionarios con calificación). Revisa el libro de '
              'calificaciones del aula.',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.4),
            )
          else ...[
            Text(
              'Entran por defecto las tareas y los foros con calificación, todas '
              'con el mismo peso. Desmarca la que no deba contar o cambia su '
              'porcentaje si una actividad vale más.',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.4),
            ),
            const SizedBox(height: 8),
            ..._actividades.map(_filaActividad),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(sumaOk ? Icons.check_circle : Icons.info_outline,
                    size: 16,
                    color: sumaOk ? const Color(0xFF1E8E3E) : cessumGold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    incN == 0
                        ? 'No hay actividades incluidas.'
                        : sumaOk
                            ? 'Los pesos suman 100% del bloque de actividades'
                                '${_esME ? ' (que vale el 80% de la calificación)' : ''}.'
                            : 'Los pesos suman ${_pesoTxt(suma)}%: se normalizan en proporción para calcular.',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: sumaOk ? cessumMuted(context) : cessumInk(context),
                        height: 1.3),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _filaActividad(_Act a) {
    final tipoColor = a.tipo == 'assign'
        ? cessumRed
        : a.tipo == 'forum'
            ? const Color(0xFF1E7B34)
            : const Color(0xFF6A4FB0);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: a.incluida
            ? tipoColor.withValues(alpha: 0.05)
            : cessumMuted(context).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: a.incluida,
            activeColor: cessumRed,
            visualDensity: VisualDensity.compact,
            onChanged: (v) => _toggleActividad(a, v ?? false),
          ),
          Expanded(
            child: InkWell(
              onTap: a.link.isEmpty
                  ? null
                  : () => Helpers.abrirUrlExterna(a.link, context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(a.etiqueta,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: tipoColor)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(a.nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: a.incluida
                                    ? cessumInk(context)
                                    : cessumMuted(context))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 4,
                    runSpacing: 3,
                    children: [
                      _chip(a.tipoTexto, tipoColor,
                          tipoColor.withValues(alpha: 0.12)),
                      if (a.seccion > 0)
                        _chip('Semana ${a.seccion}', cessumMuted(context),
                            cessumMuted(context).withValues(alpha: 0.12)),
                      if (a.vence.isNotEmpty)
                        _chip('Vence ${a.vence.substring(0, a.vence.length >= 10 ? 10 : a.vence.length)}',
                            cessumMuted(context),
                            cessumMuted(context).withValues(alpha: 0.12),
                            icono: Icons.event),
                      _chip('${a.calificadas} calif.', const Color(0xFF1E7B34),
                          const Color(0xFF1E7B34).withValues(alpha: 0.12)),
                      if (a.sinCalificar > 0)
                        _chip('${a.sinCalificar} sin calif.', cessumGold,
                            cessumGold.withValues(alpha: 0.14)),
                      if (a.tardias > 0)
                        _chip('${a.tardias} extemp.', cessumRed,
                            cessumRed.withValues(alpha: 0.10),
                            icono: Icons.schedule),
                      if (a.oculta)
                        _chip('Oculta al alumno', cessumMuted(context),
                            cessumMuted(context).withValues(alpha: 0.12),
                            icono: Icons.visibility_off),
                      if (a.escala)
                        _chip('Escala', cessumMuted(context),
                            cessumMuted(context).withValues(alpha: 0.12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 68,
            child: TextField(
              controller: a.pesoCtrl,
              enabled: a.incluida,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                isDense: true,
                suffixText: '%',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                border: OutlineInputBorder(),
              ),
              onChanged: (t) => _pesoCambiado(a, t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaAsistencia() {
    final sinRegistro = _sesiones == 0;
    return _tarjeta(
      titulo: _esME
          ? 'ASISTENCIA · 20% DE LA CALIFICACIÓN'
          : 'ASISTENCIA · INFORMATIVA (NO PONDERA)',
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sinRegistro
                ? 'Todavía no hay sesiones síncronas registradas de esta materia.'
                    '${_esME ? ' Mientras tanto la sugerencia se calcula solo con las actividades; cuando lleguen los informes de Meet, vuelve a abrir el laboratorio.' : ''}'
                : 'Sesiones síncronas registradas: $_sesiones'
                    '${_fechasSesiones.isNotEmpty ? ' (${_fechasSesiones.join(', ')})' : ''}. '
                    'Una falta con justificación VALIDADA cuenta como asistencia. '
                    '${_minimoMinutos > 0 ? 'Solo cuenta permanecer al menos $_minimoMinutos minutos. ' : ''}'
                    '${_esME ? 'Puntos de asistencia = (asistidas + justificadas) ÷ sesiones × 10, y pesan 20%.' : 'Aquí solo se muestra como referencia para tu decisión.'}',
            style: TextStyle(fontSize: 12, color: cessumInk(context), height: 1.4),
          ),
          if (sinRegistro && _materiasConRegistro.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Este grupo sí tiene registros de: ${_materiasConRegistro.keys.take(4).join(', ')}. '
              'Si tu materia aparece con otro nombre en los informes, avísale a Vicerrectoría.',
              style: TextStyle(fontSize: 11, color: cessumMuted(context), height: 1.35),
            ),
          ],
          if (_notaAsistencia.isNotEmpty && !sinRegistro) ...[
            const SizedBox(height: 4),
            Text(
              'Solo reconoce a quien entró a la sesión con su correo institucional.',
              style: TextStyle(fontSize: 11, color: cessumMuted(context), height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaOpciones() {
    Widget sw(String t, String sub, bool v, void Function(bool) f) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: cessumInk(context))),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: TextStyle(
                            fontSize: 11,
                            color: cessumMuted(context),
                            height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: v,
                activeThumbColor: cessumRed,
                onChanged: f,
              ),
            ],
          ),
        );
    return _tarjeta(
      titulo: 'CÓMO SE CALCULA LA SUGERENCIA',
      hijo: Column(
        children: [
          sw(
            'Proyección: ignorar lo que aún no está calificado',
            'Apagado = al cierre, una actividad sin calificar cuenta 0. '
                'Enciéndelo para ver cómo va el grupo con lo calificado hasta hoy.',
            _proyeccion,
            (v) => setState(() => _proyeccion = v),
          ),
          sw(
            'Tope de 8.0 a las entregas extemporáneas',
            'Política institucional: una entrega fuera de plazo vale como máximo '
                '80/100. Enciéndelo solo si NO aplicaste ya ese tope al calificar en el aula.',
            _topeTardias,
            (v) => setState(() => _topeTardias = v),
          ),
          sw(
            'Sugerir 6 a quien no tiene ninguna actividad calificada',
            'Apagado = esos alumnos quedan sin sugerencia (en blanco en la captura), '
                'para que decidas tú caso por caso.',
            _sugerirSinDatos,
            (v) => setState(() => _sugerirSinDatos = v),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 15, color: cessumMuted(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Entero del acta = promedio exacto redondeado al entero más '
                  'cercano (.5 sube), nunca menor que 6 ni mayor que 10. '
                  'Puedes ajustar el entero de cualquier alumno en su fila.',
                  style: TextStyle(fontSize: 11, color: cessumMuted(context), height: 1.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tituloAlumnos() {
    int conSug = 0;
    for (final al in _alumnos) {
      if (_enteroFinal(al, _calcular(al)) != null) conSug++;
    }
    return Row(
      children: [
        Expanded(
          child: Text('Alumnos y sugerencia',
              style: CessumType.heading(15, color: cessumInk(context))),
        ),
        Text('$conSug de ${_alumnos.length} con sugerencia',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: conSug == _alumnos.length
                    ? const Color(0xFF1E8E3E)
                    : cessumGold)),
      ],
    );
  }

  Widget _filtros() {
    return Column(
      children: [
        TextField(
          onChanged: (v) => setState(() => _busqueda = v),
          decoration: InputDecoration(
            hintText: 'Buscar alumno o matrícula…',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: _superficie,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            label: const Text('Solo sin datos o sin cuenta en el aula',
                style: TextStyle(fontSize: 12)),
            selected: _soloSinDatos,
            selectedColor: cessumRed.withValues(alpha: 0.14),
            onSelected: (v) => setState(() => _soloSinDatos = v),
          ),
        ),
      ],
    );
  }

  Widget _filaAlumno(_Al al) {
    final r = _calcular(al);
    final entero = _enteroFinal(al, r);
    final colorEnt = entero == null
        ? cessumMuted(context)
        : (entero == 6 ? cessumRed : const Color(0xFF1E8E3E));
    final inc = _incluidas;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
            color: !al.enAula
                ? cessumGold.withValues(alpha: 0.6)
                : colorEnt.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () => setState(() => al.abierto = !al.abierto),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(al.nombre,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cessumInk(context))),
                        Text(al.matricula,
                            style: TextStyle(
                                fontSize: 10.5, color: cessumFaint(context))),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final a in inc) _pillNota(a, al.notas[a.itemid]),
                            if (al.sesiones > 0)
                              _chip(
                                  'Asist. ${al.asistidas + al.justificadas}/${al.sesiones}'
                                  '${al.justificadas > 0 ? ' (+${al.justificadas} just.)' : ''}',
                                  _esME ? cessumRed : cessumMuted(context),
                                  (_esME ? cessumRed : cessumMuted(context))
                                      .withValues(alpha: 0.10),
                                  icono: Icons.fact_check_outlined),
                            if (al.pendientes > 0)
                              _chip('${al.pendientes} justif. pendiente(s)', cessumGold,
                                  cessumGold.withValues(alpha: 0.14),
                                  icono: Icons.hourglass_top),
                            if (!al.enAula)
                              _chip('Sin cuenta en el aula', cessumGold,
                                  cessumGold.withValues(alpha: 0.14),
                                  icono: Icons.person_off),
                            if (al.recursamiento)
                              _chip(al.leyenda.isNotEmpty ? al.leyenda : 'Recursamiento',
                                  const Color(0xFF6A4FB0),
                                  const Color(0xFF6A4FB0).withValues(alpha: 0.12)),
                            if (al.calificacionActa != null)
                              _chip(
                                  'Acta: ${al.calificacionActa}'
                                  '${al.estatusActa.isNotEmpty ? ' · ${al.estatusActa}' : ''}',
                                  cessumMuted(context),
                                  cessumMuted(context).withValues(alpha: 0.12),
                                  icono: Icons.description_outlined),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          r.sinDatos && entero == null
                              ? 'Sin actividades calificadas · sin sugerencia'
                              : 'Actividades ${_f2(r.promedio)}'
                                  '${_esME && al.sesiones > 0 ? ' · Asistencia ${_f1(al.puntosAsis)}' : ''}'
                                  ' → exacta ${_f2(r.sugerida)}'
                                  '${_proyeccion && r.usadas < inc.length ? ' (proyección: ${r.usadas} de ${inc.length})' : ''}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cessumMuted(context),
                              height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(entero == null ? '—' : '$entero',
                          style: CessumType.display(30, color: colorEnt)),
                      Text(al.ajuste != null ? 'ajustada' : 'sugerida',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: al.ajuste != null
                                  ? cessumGold
                                  : cessumMuted(context))),
                      Icon(al.abierto ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: cessumFaint(context)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (al.abierto) _detalleAlumno(al, r),
        ],
      ),
    );
  }

  Widget _pillNota(_Act a, _Nota? n) {
    final v = n?.nota;
    final tarde = n?.tarde ?? false;
    Color fg, bg;
    String txt;
    if (v == null) {
      fg = cessumGold;
      bg = cessumGold.withValues(alpha: 0.14);
      txt = (n?.entregado == true) ? '${a.etiqueta} entregada' : '${a.etiqueta} —';
    } else {
      final cap = _topeTardias && tarde && v > 8;
      fg = (cap ? 8.0 : v) < 6 ? cessumRed : const Color(0xFF1E7B34);
      bg = fg.withValues(alpha: 0.10);
      txt = '${a.etiqueta} ${_f1(v)}${cap ? '→8.0' : ''}';
    }
    return _chip(txt, fg, bg, icono: tarde ? Icons.schedule : null);
  }

  Widget _detalleAlumno(_Al al, _Res r) {
    final inc = _incluidas;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: _borde),
          for (final a in inc)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${a.etiqueta} · ${a.nombre}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: cessumInk(context)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _detalleNota(a, al.notas[a.itemid]),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context)),
                  ),
                ],
              ),
            ),
          if (al.sesiones > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Asistencia: ${al.asistidas} asistida(s)'
              '${al.justificadas > 0 ? ' + ${al.justificadas} justificada(s)' : ''}'
              ' de ${al.sesiones}'
              '${al.breves > 0 ? ' · ${al.breves} conexión(es) breve(s) que no cuentan' : ''}'
              '${al.faltas.isNotEmpty ? ' · faltas: ${al.faltas.join(', ')}' : ''}'
              '${_esME ? ' → ${_f1(al.puntosAsis)} puntos' : ''}',
              style: TextStyle(fontSize: 11, color: cessumMuted(context), height: 1.35),
            ),
          ],
          if (al.totalAula != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Total del curso en el libro de Moodle: ${_f2(al.totalAula)} (referencia; el libro usa sus propios pesos).',
                style: TextStyle(fontSize: 11, color: cessumMuted(context), height: 1.35),
              ),
            ),
          if (!al.enAula)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Este alumno no aparece inscrito en el aula con su correo institucional (${al.correo}). '
                'Sus actividades no se pueden leer; captura su calificación directamente.',
                style: const TextStyle(fontSize: 11, color: cessumGold, height: 1.35),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Entero para el acta:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cessumInk(context))),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: cessumIsDark(context)
                          ? Colors.white24
                          : Colors.black26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<int>(
                  value: al.ajuste ?? 0,
                  underline: const SizedBox.shrink(),
                  items: <int>[0, 6, 7, 8, 9, 10]
                      .map((n) => DropdownMenuItem<int>(
                            value: n,
                            child: Text(
                              n == 0
                                  ? (r.entero == null
                                      ? 'Sugerida (—)'
                                      : 'Sugerida (${r.entero})')
                                  : '$n',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: n == 6 ? cessumRed : cessumInk(context)),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => al.ajuste = (v == null || v == 0) ? null : v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _detalleNota(_Act a, _Nota? n) {
    if (n == null || n.nota == null) {
      if (n?.entregado == true) return 'entregada, sin calificar';
      if (n?.participaciones != null && n!.participaciones! > 0) {
        return '${n.participaciones} aportación(es), sin calificar';
      }
      return n?.entregado == false ? 'sin entregar' : 'sin calificar';
    }
    final b = n.bruta;
    final base = b == null
        ? _f1(n.nota)
        : '${_f1(n.nota)}  (${b.toStringAsFixed(b == b.roundToDouble() ? 0 : 1)}/${a.max.toStringAsFixed(a.max == a.max.roundToDouble() ? 0 : 1)})';
    return '$base${n.tarde ? ' · extemporánea' : ''}${n.excluida ? ' · excluida en el libro' : ''}';
  }

  Widget _distribucionWidget() {
    final dist = _distribucion;
    final total = dist.values.fold(0, (s, v) => s + v);
    if (total == 0) return const SizedBox.shrink();
    double suma = 0;
    dist.forEach((k, v) => suma += k * v);
    return _tarjeta(
      titulo: 'DISTRIBUCIÓN DE LAS SUGERENCIAS',
      hijo: Column(
        children: [
          Row(
            children: [6, 7, 8, 9, 10].map((n) {
              final c = dist[n] ?? 0;
              return Expanded(
                child: Column(
                  children: [
                    Text('$c',
                        style: CessumType.display(22,
                            color: n == 6 ? cessumRed : cessumInk(context))),
                    Text('$n', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            'Promedio del grupo: ${(suma / total).toStringAsFixed(1)} · $total con sugerencia'
            '${_alumnos.length - total > 0 ? ' · ${_alumnos.length - total} sin sugerencia' : ''}',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _notaSinMapear() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.08),
            border: Border.all(color: CC.goldBorder),
            borderRadius: BorderRadius.circular(10)),
        child: Text(
          'En el aula hay ${_sinMapear.length} cuenta(s) que no están en el padrón de este grupo: '
          '${_sinMapear.map((m) => (m['nombre'] ?? m['correo'] ?? '').toString()).take(5).join(', ')}'
          '${_sinMapear.length > 5 ? '…' : ''}. '
          'Puede ser un correo personal o un alumno de otro grupo; sus notas no se asignan a nadie.',
          style: TextStyle(fontSize: 11.5, height: 1.4, color: cessumInk(context)),
        ),
      );

  Widget _notaFinal() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10)),
        child: Text(
          'Cómo leer esta pantalla: las notas vienen del libro de calificaciones '
          'del aula tal como las pusiste (ya convertidas a 0-10); la asistencia, '
          'de los informes de Meet de esta materia; las justificaciones, de las '
          'que Vicerrectoría ya validó. La sugerencia es un apoyo: la calificación '
          'del acta sigue siendo tu decisión y se guarda en «Capturar calificaciones».'
          '${_generado.isNotEmpty ? '\nDatos leídos: $_generado.' : ''}',
          style: TextStyle(fontSize: 11.5, height: 1.4, color: cessumInk(context)),
        ),
      );
}
