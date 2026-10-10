import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// MEJORA ADMIN — Evaluación manual del grupo (versión reforzada).
///
/// Elige programa / generación / grupo / materia, carga a TODOS los alumnos
/// con su calificación ACTUAL precargada, corrige o digita a mano y guarda en
/// masa DIRECTO en la hoja Calificaciones + kardex (acciones
/// `calificaciones_grupo_listar` y `calificaciones_grupo_guardar`).
///
/// Refuerzos: re-búsqueda de fila en el Guardián para no duplicar; aviso si la
/// hoja ya trae duplicados; fallback de materia manual si cartas.json no cubre
/// el programa; protección contra salir sin guardar; manejo de grupo vacío.
class _GenCat {
  final String generacion;
  final List<String> grupos;
  _GenCat(this.generacion, this.grupos);
}

class _ProgCat {
  final String programa;
  final List<_GenCat> generaciones;
  _ProgCat(this.programa, this.generaciones);
}

class _MatCarta {
  final String denominacion;
  final String clave;
  _MatCarta(this.denominacion, this.clave);
}

class _FilaCalif {
  final String matricula;
  final String nombre;
  final String correo;
  final int fila;
  final String estatus;
  final bool duplicado;
  final String calRaw; // nota actual tal cual está en la hoja (informativa)
  int? calificacion;
  // (ago-27) Quien RECURSA no pertenece a este grupo: viene de otra
  // generación y conserva SUS datos. Se marca para mostrarlo aparte y para
  // que el acta no lo registre con la generación de sus compañeros.
  final bool recursa;
  final String programaOrigen;
  final String generacionOrigen;
  _FilaCalif({
    required this.matricula,
    required this.nombre,
    required this.correo,
    required this.fila,
    required this.estatus,
    required this.duplicado,
    required this.calRaw,
    this.calificacion,
    this.recursa = false,
    this.programaOrigen = '',
    this.generacionOrigen = '',
  });
}

class EvaluacionGrupoScreen extends StatefulWidget {
  const EvaluacionGrupoScreen({super.key});

  @override
  State<EvaluacionGrupoScreen> createState() => _EvaluacionGrupoScreenState();
}

class _EvaluacionGrupoScreenState extends State<EvaluacionGrupoScreen> {
  bool _cargandoCat = true;
  String? _errorCat;
  List<_ProgCat> _catalogo = [];
  Map<String, List<_MatCarta>> _materiasPorPrograma = {};

  String? _programa;
  String? _generacion;
  String? _grupo;
  _MatCarta? _materia;
  final TextEditingController _materiaManual = TextEditingController();
  final TextEditingController _claveManual = TextEditingController();
  final TextEditingController _ciclo = TextEditingController();
  final TextEditingController _docente = TextEditingController();

  bool _cargandoAlumnos = false;
  // (ago-27) DOCENTE OBLIGATORIO, DE LA LISTA REAL.
  // Era un campo de texto libre y opcional: un acta sin docente no dice quién
  // calificó, y escrito a mano cada quien lo ponía distinto («Mtro. Pérez»,
  // «perez», «J. Pérez»), así que ni siquiera se podía agrupar después.
  List<Map<String, dynamic>> _docentes = [];
  String? _docenteSel;
  bool _cargandoDocentes = false;
  // (ago-27) El docente del acta es el que se reporta a la autoridad en el
  // formato SIGA. Por eso se propone el REALMENTE ASIGNADO a este grupo y
  // materia, no una lista suelta: elegir de entre los treinta permite
  // reportarle a la SEC un profesor que nunca dio esa clase.
  // (ago-27) El «Ciclo» del acta es el ciclo del PLAN (1, 2, 3…), no el ciclo
  // escolar AAAA-AAAA de SIGA. Escrito a mano llegaba como «2», «Ciclo 2»,
  // «2do» o «Segundo», y así el mismo ciclo se contaba como cuatro distintos.
  // Los valores salen del plan de cada programa: la licenciatura tiene nueve
  // cuatrimestres y una maestría cuatro.
  // (ago-27) Los que RECURSAN esta materia. Van aparte de _alumnos a
  // propósito: pertenecen a otra generación y conservan SUS datos. Meterlos
  // en la lista del grupo haría que su acta dijera que cursaron en una
  // generación que no es la suya.
  List<Map<String, dynamic>> _recursadores = [];
  List<Map<String, dynamic>> _ciclosPlan = [];
  String? _cicloSel;
  String _docenteAsignado = '';
  String _notaAsignado = '';
  bool _asignadoExacto = false;
  bool _guardando = false;
  bool _cambiosSinGuardar = false;
  bool _hayDuplicados = false;
  bool _grupoSinAlumnos = false;
  List<_FilaCalif> _alumnos = [];

  /// Quién imparte realmente este grupo y materia. Se consulta al elegir la
  /// materia y se propone ya seleccionado.
  Future<void> _cargarRecursadores() async {
    if (_matNombre.isEmpty) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'recursadores_de_grupo',
        'programa': _programa ?? '',
        'generacion': _generacion ?? '',
        'grupo': _grupo ?? '',
        'materia': _matNombre,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted || d['ok'] != true) return;
      setState(() {
        _recursadores = ((d['recursadores'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // Se agregan al final de la lista de captura, marcados. Van después
        // de los del grupo para que se lean como lo que son: alumnos de otra
        // generación que se integraron a esta materia.
        for (final rc in _recursadores) {
          final ya = _alumnos.any(
              (x) => x.matricula == '${rc['matricula'] ?? ''}');
          if (ya) continue;
          _alumnos.add(_FilaCalif(
            matricula: '${rc['matricula'] ?? ''}',
            nombre: '${rc['nombre'] ?? ''}',
            correo: '${rc['correo'] ?? ''}',
            fila: 0,
            estatus: 'Recursa',
            duplicado: false,
            calRaw: '',
            recursa: true,
            programaOrigen: '${rc['programa'] ?? ''}',
            generacionOrigen: '${rc['generacion'] ?? ''}',
          ));
        }
      });
    } catch (_) {}
  }

  Future<void> _cargarAsignado() async {
    // _programa, _generacion y _grupo son String? en esta pantalla: se
    // validan antes y se mandan como texto, nunca nulos.
    final prog = _programa ?? '';
    if (prog.isEmpty || _matNombre.isEmpty) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'docente_asignado',
        'programa': prog,
        'generacion': _generacion ?? '',
        'grupo': _grupo ?? '',
        'materia': _matNombre,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted || d['ok'] != true) return;
      setState(() {
        _docenteAsignado = '${d['sugerido'] ?? ''}';
        _notaAsignado = '${d['nota'] ?? ''}';
        _asignadoExacto = d['exacto'] == true && d['varios'] != true;
        // Se propone solo si la coincidencia es exacta y hay un único
        // docente. Si son varios, que elija: el sistema no debe adivinar
        // quién de dos impartió el grupo.
        if (_asignadoExacto && _docenteAsignado.isNotEmpty) {
          _docenteSel = _docenteAsignado;
          _docente.text = _docenteAsignado;
        }
      });
    } catch (_) {}
  }

  Future<void> _cargarCiclos() async {
    final prog = _programa ?? '';
    if (prog.isEmpty) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'ciclos_de_programa',
        'programa': prog,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted || d['ok'] != true) return;
      setState(() {
        _ciclosPlan = ((d['ciclos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // Si el ciclo elegido no existe en este plan, se limpia: dejarlo
        // pegado del programa anterior es peor que dejarlo vacío.
        if (_cicloSel != null &&
            !_ciclosPlan.any((c) => '${c['valor']}' == _cicloSel)) {
          _cicloSel = null;
          _ciclo.text = '';
        }
      });
    } catch (_) {}
  }

  Future<void> _cargarDocentes() async {
    setState(() => _cargandoDocentes = true);
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'docentes_lista'});
      final r = await http.get(uri).timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _cargandoDocentes = false;
        if (d['ok'] == true) {
          _docentes = ((d['docentes'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _docentes.sort((a, b) =>
              '${a['nombre'] ?? ''}'.compareTo('${b['nombre'] ?? ''}'));
        }
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoDocentes = false);
    }
  }

  /// Selector de docente CON BUSCADOR.
  /// Con más de treinta profesores, una lista plana obliga a recorrerla toda
  /// para encontrar uno — y ahí es donde se elige el equivocado por prisa.
  Future<void> _elegirDocente() async {
    if (_docentes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo cargar la lista de docentes. '
            'Revisa tu conexión e intenta de nuevo.'),
      ));
      _cargarDocentes();
      return;
    }
    String filtro = '';
    final elegido = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setLocal) {
          final q = filtro.toLowerCase().trim();
          final lista = _docentes.where((d) {
            if (q.isEmpty) return true;
            return '${d['nombre'] ?? ''}'.toLowerCase().contains(q) ||
                '${d['correo'] ?? ''}'.toLowerCase().contains(q);
          }).toList();
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx2).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx2).size.height * 0.75,
              child: Column(children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: 'Buscar docente por nombre…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setLocal(() => filtro = v),
                  ),
                ),
                Expanded(
                  child: lista.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Ningún docente coincide.'),
                          ),
                        )
                      : ListView.builder(
                          itemCount: lista.length,
                          itemBuilder: (c, i) {
                            final d = lista[i];
                            final nom = '${d['nombre'] ?? ''}';
                            return ListTile(
                              dense: true,
                              title: Text(nom,
                                  style: const TextStyle(fontSize: 14.5)),
                              subtitle: '${d['correo'] ?? ''}'.isNotEmpty
                                  ? Text('${d['correo']}',
                                      style: const TextStyle(fontSize: 12))
                                  : null,
                              onTap: () => Navigator.pop(ctx2, nom),
                            );
                          },
                        ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (elegido != null && mounted) {
      setState(() {
        _docenteSel = elegido;
        _docente.text = elegido;   // el guardado sigue leyendo este campo
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarTodo();
    _cargarDocentes();
  }

  @override
  void dispose() {
    _materiaManual.dispose();
    _claveManual.dispose();
    _ciclo.dispose();
    _docente.dispose();
    super.dispose();
  }

  // Materia/clave efectivas (dropdown si hay catálogo; manual si no).
  bool get _modoManual => _materias.isEmpty;
  String get _matNombre =>
      _modoManual ? _materiaManual.text.trim() : (_materia?.denominacion ?? '');
  String get _matClave =>
      _modoManual ? _claveManual.text.trim() : (_materia?.clave ?? '');

  Future<void> _cargarTodo() async {
    setState(() {
      _cargandoCat = true;
      _errorCat = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'grupos'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Catálogo inválido');
      final cat = <_ProgCat>[];
      for (final p in (data['catalogo'] as List<dynamic>? ?? [])) {
        final pm = p as Map<String, dynamic>;
        final gens = <_GenCat>[];
        for (final g in (pm['generaciones'] as List<dynamic>? ?? [])) {
          final gm = g as Map<String, dynamic>;
          final grupos = (gm['grupos'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
          gens.add(_GenCat(gm['generacion'].toString(), grupos));
        }
        cat.add(_ProgCat(pm['programa'].toString(), gens));
      }
      final mapa = <String, List<_MatCarta>>{};
      try {
        final r2 = await http
            .get(Uri.parse(cartasJsonUrl))
            .timeout(const Duration(seconds: 20));
        final d2 = jsonDecode(utf8.decode(r2.bodyBytes)) as Map<String, dynamic>;
        for (final p in (d2['programas'] as List<dynamic>? ?? [])) {
          final pm = p as Map<String, dynamic>;
          final prog = (pm['programa'] ?? '').toString();
          final mats = <_MatCarta>[];
          for (final a in (pm['asignaturas'] as List<dynamic>? ?? [])) {
            final am = a as Map<String, dynamic>;
            mats.add(_MatCarta(
              (am['denominacion'] ?? '').toString(),
              (am['clave'] ?? '').toString(),
            ));
          }
          mapa[prog] = mats;
        }
      } catch (_) {}
      setState(() {
        _catalogo = cat;
        _materiasPorPrograma = mapa;
        _cargandoCat = false;
      });
    } catch (e) {
      setState(() {
        _errorCat = 'No se pudo cargar el catálogo. Revisa tu conexión.';
        _cargandoCat = false;
      });
    }
  }

  List<String> get _generaciones {
    final p = _catalogo.where((e) => e.programa == _programa);
    if (p.isEmpty) return [];
    return p.first.generaciones.map((g) => g.generacion).toList();
  }

  List<String> get _grupos {
    final p = _catalogo.where((e) => e.programa == _programa);
    if (p.isEmpty) return [];
    final g = p.first.generaciones.where((e) => e.generacion == _generacion);
    if (g.isEmpty) return [];
    return g.first.grupos;
  }

  List<_MatCarta> get _materias => _materiasPorPrograma[_programa] ?? const [];

  Future<bool> _confirmarSalida() async {
    if (!_cambiosSinGuardar) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: const Text(
            'Tienes calificaciones digitadas que no has guardado. Si sales se perderán.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Seguir editando')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: cessumRed),
              child: const Text('Salir sin guardar')),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _cargarAlumnos() async {
    if (_programa == null || _generacion == null || _grupo == null) {
      _aviso('Elige programa, generación y grupo.', error: true);
      return;
    }
    if (_matNombre.isEmpty) {
      _aviso('Indica la materia.', error: true);
      return;
    }
    // Al cargar el grupo ya se sabe programa, generación, grupo y materia:
    // es el momento de proponer al docente que realmente lo imparte.
    _cargarAsignado();
    _cargarRecursadores();
    if (_cambiosSinGuardar) {
      final seguir = await _confirmarSalida();
      if (!seguir) return;
    }
    setState(() {
      _cargandoAlumnos = true;
      _alumnos = [];
      _hayDuplicados = false;
      _grupoSinAlumnos = false;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'calificaciones_grupo_listar',
        'programa': _programa!,
        'generacion': _generacion!,
        'grupo': _grupo!,
        'materia': _matNombre,
        'claveMateria': _matClave,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final lista = (data['alumnos'] as List<dynamic>? ?? []).map((e) {
          final m = e as Map<String, dynamic>;
          final calRaw = m['calificacion'];
          int? cal;
          final calStr = (calRaw ?? '').toString().trim();
          if (calStr.isNotEmpty) {
            final n = int.tryParse(calStr.split('.').first);
            if (n != null && n >= 6 && n <= 10) cal = n;
          }
          return _FilaCalif(
            matricula: (m['matricula'] ?? '').toString(),
            nombre: (m['nombre'] ?? '').toString(),
            correo: (m['correo'] ?? '').toString(),
            fila: int.tryParse('${m['fila']}') ?? 0,
            estatus: (m['estatus'] ?? '').toString(),
            duplicado: m['duplicado'] == true,
            calRaw: calStr,
            calificacion: cal,
          );
        }).toList();
        setState(() {
          _alumnos = lista;
          _hayDuplicados = data['hayDuplicados'] == true;
          _grupoSinAlumnos = data['sinAlumnos'] == true || lista.isEmpty;
          _cambiosSinGuardar = false;
          _cargandoAlumnos = false;
        });
      } else {
        setState(() => _cargandoAlumnos = false);
        _aviso((data['error'] ?? 'No se pudo cargar').toString(), error: true);
      }
    } catch (e) {
      setState(() => _cargandoAlumnos = false);
      _aviso('Error al cargar: $e', error: true);
    }
  }

  Future<void> _guardar() async {
    final conNota = _alumnos.where((a) => a.calificacion != null).toList();
    if (conNota.isEmpty) {
      _aviso('No hay calificaciones para guardar.', error: true);
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Guardar en las listas'),
        content: Text(
            'Se guardarán ${conNota.length} calificación(es) de "$_matNombre" '
            'a nombre de ${_docente.text.trim()} (así se reporta en SIGA). '
            'directamente en la hoja Calificaciones y el kardex. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              child: const Text('Guardar',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmar != true) return;

    // (ago-27) Sin docente no se guarda. Un acta que no dice quién calificó
    // no se sostiene ante nadie: ni ante el alumno que reclama una nota, ni
    // ante la autoridad que revisa el expediente.
    // El ciclo del plan también es obligatorio: sin él, el acta no dice a qué
    // punto del programa corresponde y no se puede agrupar para SIGA.
    if (_ciclo.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Falta elegir el ciclo del plan.'),
        backgroundColor: cessumRed,
        duration: Duration(seconds: 5),
      ));
      return;
    }
    if (_docente.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Falta elegir al docente. El acta debe decir quién '
            'calificó.'),
        backgroundColor: cessumRed,
        duration: Duration(seconds: 5),
      ));
      return;
    }

    setState(() => _guardando = true);
    try {
      final payload = {
        'accion': 'calificaciones_grupo_guardar',
        'programa': _programa,
        'generacion': _generacion,
        'grupo': _grupo,
        'materia': _matNombre,
        'claveMateria': _matClave,
        'ciclo': _ciclo.text.trim(),
        'docente': _docente.text.trim(),
        'periodo': '',
        // (ago-27) Quien RECURSA viaja con SU programa y SU generación, no
        // con los del grupo. Si se guardara con los del grupo, su kárdex y su
        // certificado dirían que cursó en una generación que no es la suya, y
        // el reporte a la SEC lo declararía en un grupo al que no pertenece.
        'alumnos': _alumnos
            .map((a) => {
                  'matricula': a.matricula,
                  'nombre': a.nombre,
                  'correo': a.correo,
                  'fila': a.fila,
                  'calificacion': a.calificacion ?? '',
                  if (a.recursa) 'recursa': true,
                  if (a.recursa) 'programa': a.programaOrigen,
                  if (a.recursa) 'generacion': a.generacionOrigen,
                })
            .toList(),
      };
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        final g = data['guardados'] ?? 0;
        final ag = data['agregados'] ?? 0;
        final ed = data['editados'] ?? 0;
        final errs = (data['errores'] as List<dynamic>? ?? []);
        _cambiosSinGuardar = false;
        if (errs.isNotEmpty) {
          _mostrarErrores(g, ag, ed, errs);
        } else {
          _aviso('Guardado: $g (nuevas $ag, corregidas $ed).');
        }
        await _cargarAlumnos();
      } else {
        _aviso((data['error'] ?? 'No se pudo guardar').toString(), error: true);
      }
    } catch (e) {
      if (mounted) {
        _aviso(
            'Error al guardar. Antes de reintentar, vuelve a cargar el grupo para confirmar qué quedó guardado. ($e)',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mostrarErrores(dynamic g, dynamic ag, dynamic ed, List<dynamic> errs) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Guardado con avisos'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Se guardaron $g (nuevas $ag, corregidas $ed).'),
              const SizedBox(height: 8),
              const Text('No se guardaron:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...errs.map((e) => Text('• $e',
                  style: const TextStyle(fontSize: 12.5, color: cessumRed))),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  void _aviso(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
      duration: Duration(seconds: error ? 5 : 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final conNota = _alumnos.where((a) => a.calificacion != null).length;
    final sinNota = _alumnos.length - conNota;
    return PopScope(
      canPop: !_cambiosSinGuardar,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final salir = await _confirmarSalida();
        if (salir && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Evaluación manual del grupo'),
        ),
        body: _cargandoCat
            ? const Center(child: CircularProgressIndicator())
            : _errorCat != null
                ? _vistaError()
                : Column(
                    children: [
                      _selectores(),
                      if (_hayDuplicados) _bannerDuplicados(),
                      if (_alumnos.isNotEmpty) _resumen(conNota, sinNota),
                      Expanded(child: _lista()),
                      if (_alumnos.isNotEmpty) _barraGuardar(conNota),
                    ],
                  ),
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
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_errorCat ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _cargarTodo, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _bannerDuplicados() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: const [
          Icon(Icons.warning_amber_rounded, color: cessumGold, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hay alumnos con calificaciones duplicadas en esta materia (marcados abajo). Al guardar se corrige la primera; revisa los duplicados en "Editar calificaciones".',
              style: TextStyle(fontSize: 11.5, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectores() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          _dd('Programa', _programa, _catalogo.map((e) => e.programa).toList(),
              (v) {
                setState(() {
                  _programa = v;
                  _generacion = null;
                  _grupo = null;
                  _materia = null;
                  _alumnos = [];
                  _hayDuplicados = false;
                  // Los ciclos son los del plan de ESTE programa: se vuelven
                  // a pedir y se limpia lo elegido antes.
                  _ciclosPlan = [];
                  _cicloSel = null;
                  _ciclo.text = '';
                  _docenteAsignado = '';
                  _notaAsignado = '';
                });
                _cargarCiclos();
              }),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _dd('Generación', _generacion, _generaciones,
                    (v) => setState(() {
                          _generacion = v;
                          _grupo = null;
                          _alumnos = [];
                        })),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dd('Grupo', _grupo, _grupos,
                    (v) => setState(() {
                          _grupo = v;
                          _alumnos = [];
                        })),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _materiaSelector(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  // 'value', como el resto del proyecto: con 'initialValue' el
                  // selector no se refrescaría al cambiar de programa y
                  // quedaría mostrando un ciclo que ya no existe en el plan.
                  value: _cicloSel,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Ciclo del plan *',
                    errorText: (_cicloSel == null || _cicloSel!.isEmpty)
                        ? 'Obligatorio'
                        : null,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  hint: Text(
                    _ciclosPlan.isEmpty ? 'Elige el programa' : 'Elige',
                    style: const TextStyle(fontSize: 14),
                  ),
                  items: _ciclosPlan
                      .map((c) => DropdownMenuItem<String>(
                            value: '${c['valor']}',
                            child: Text('${c['etiqueta']}',
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _cicloSel = v;
                    // Se guarda SIEMPRE el número, aunque el plan lo llame
                    // «Segundo cuatrimestre»: es lo que permite agrupar.
                    _ciclo.text = v ?? '';
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _cargandoDocentes ? null : _elegirDocente,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Docente *',
                      errorText: (_docenteSel == null || _docenteSel!.isEmpty)
                          ? 'Obligatorio'
                          : null,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          _cargandoDocentes
                              ? 'Cargando…'
                              : (_docenteSel?.isNotEmpty == true
                                  ? _docenteSel!
                                  : 'Elige de la lista'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: _docenteSel?.isNotEmpty == true
                                ? null
                                : Colors.black45,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 20),
                    ]),
                  ),
                ),
              ),
            ],
          ),
          // (ago-27) Se dice a dónde va este dato. Sin eso, el docente se
          // elige "el que suene" y termina reportado a la autoridad.
          if (_notaAsignado.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _asignadoExacto ? Icons.verified_outlined
                                    : Icons.info_outline,
                    size: 15,
                    color: _asignadoExacto
                        ? Colors.green.shade700
                        : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$_notaAsignado Este dato se reporta a la autoridad '
                      'educativa en el formato SIGA.',
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: cessumMuted(context)),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _cargandoAlumnos ? null : _cargarAlumnos,
              icon: _cargandoAlumnos
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download),
              label: Text(_cargandoAlumnos ? 'Cargando…' : 'Cargar alumnos'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumGold, foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _materiaSelector() {
    // Si el programa tiene materias en cartas.json -> dropdown.
    // Si no (programa no cubierto) -> campos manuales, para no bloquear.
    if (_programa != null && _materias.isEmpty) {
      return Column(
        children: [
          Row(
            children: const [
              Icon(Icons.edit_note, size: 16, color: Colors.black45),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                    'Este programa no tiene materias en el catálogo: escríbela igual que en tus listas.',
                    style: TextStyle(fontSize: 11, color: Colors.black54)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _materiaManual,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Materia',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _claveManual,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Clave de la materia (opcional)',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      );
    }
    return DropdownButtonFormField<_MatCarta>(
      value: _materia,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Materia',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items: _materias
          .map((m) => DropdownMenuItem(
                value: m,
                child: Text(
                    m.clave.isNotEmpty
                        ? '${m.denominacion} (${m.clave})'
                        : m.denominacion,
                    overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) => setState(() {
        _materia = v;
        _alumnos = [];
        _hayDuplicados = false;
      }),
    );
  }

  Widget _dd(String label, String? value, List<String> ops,
      ValueChanged<String?> onCh) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items: ops
          .map((o) => DropdownMenuItem(
              value: o, child: Text(o, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: onCh,
    );
  }

  Widget _resumen(int conNota, int sinNota) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _chip('Alumnos', '${_alumnos.length}', Colors.black54),
          const SizedBox(width: 8),
          _chip('Con nota', '$conNota', const Color(0xFF1E8E3E)),
          const SizedBox(width: 8),
          _chip('Sin nota', '$sinNota',
              sinNota > 0 ? cessumRed : const Color(0xFF1E8E3E)),
        ],
      ),
    );
  }

  Widget _chip(String etq, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(val,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(etq,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _lista() {
    if (_cargandoAlumnos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_grupoSinAlumnos) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'Este grupo no tiene alumnos activos (o todos están en baja).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54)),
        ),
      );
    }
    if (_alumnos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'Elige los datos arriba y pulsa "Cargar alumnos" para ver y evaluar al grupo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      itemCount: _alumnos.length,
      itemBuilder: (_, i) => _filaAlumno(_alumnos[i]),
    );
  }

  Widget _filaAlumno(_FilaCalif a) {
    final sinNota = a.calificacion == null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: a.duplicado
                ? cessumGold
                : (sinNota
                    ? cessumRed.withValues(alpha: 0.35)
                    : Colors.transparent)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(a.nombre,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ),
                      if (a.duplicado) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.warning_amber_rounded,
                            size: 15, color: cessumGold),
                      ],
                      // La marca va junto al nombre, no al final de la fila:
                      // el docente tiene que verla ANTES de poner la nota.
                      if (a.recursa) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: cessumGold,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('RECURSA',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4)),
                        ),
                      ],
                    ],
                  ),
                  Text('Mat. ${a.matricula}',
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black54)),
                  if (a.recursa)
                    Text(
                      'Recursa · ${a.programaOrigen} · Gen. ${a.generacionOrigen}',
                      style: const TextStyle(
                          fontSize: 10.5,
                          color: cessumGold,
                          fontWeight: FontWeight.w700),
                    ),
                  if (a.calificacion == null && a.calRaw.isNotEmpty)
                    Text('Tiene "${a.calRaw}" (fuera de 6–10): corrígela en Editar calificaciones',
                        style: const TextStyle(
                            fontSize: 10.5,
                            color: cessumRed,
                            fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: DropdownButtonFormField<int?>(
                value: a.calificacion,
                isDense: true,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  hintText: '—',
                ),
                items: <int?>[null, 6, 7, 8, 9, 10]
                    .map((n) => DropdownMenuItem<int?>(
                          value: n,
                          child: Text(n == null ? '—' : '$n'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  a.calificacion = v;
                  _cambiosSinGuardar = true;
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barraGuardar(int conNota) {
    return SafeArea(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                  '$conNota con calificación'
                  '${_cambiosSinGuardar ? '  ·  sin guardar' : ''}',
                  style: TextStyle(
                      color: _cambiosSinGuardar ? cessumRed : Colors.black54,
                      fontWeight: _cambiosSinGuardar
                          ? FontWeight.w600
                          : FontWeight.normal)),
            ),
            ElevatedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_guardando ? 'Guardando…' : 'Guardar en las listas'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
