import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_config.dart';
import 'auth/session_store.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'laboratorio_evaluacion_screen.dart';
import 'teacher_profile.dart';

// =====================================================
// DIRECCION DEL PUENTE (proxy PHP en app.cessum.mx)
// =====================================================
const String guardianUrl = '/guardian.php';

// ---------- Modelos ----------
class _GenCat {
  final String generacion;
  final List<String> grupos;
  const _GenCat(this.generacion, this.grupos);
}

class _ProgCat {
  final String programa;
  final List<_GenCat> generaciones;
  const _ProgCat(this.programa, this.generaciones);
}

class _MateriaCarta {
  final String denominacion;
  final String clave;
  final String semestre;
  const _MateriaCarta({
    required this.denominacion,
    required this.clave,
    required this.semestre,
  });
}

class _FilaAlumno {
  final String matricula;
  final String nombre;
  final String correo;
  int? calificacion;

  _FilaAlumno({
    required this.matricula,
    required this.nombre,
    required this.correo,
    this.calificacion,
  });
}

class _MateriaAsignada {
  final String programa;
  final String generacion;
  final String grupo;
  final String dia;
  final String hora;
  final String materia;
  final String clave;
  final String ciclo;
  final String modalidad;
  final String inicio;
  final String termino;
  final bool terminada;
  const _MateriaAsignada({
    required this.programa,
    required this.generacion,
    required this.grupo,
    required this.dia,
    required this.hora,
    required this.materia,
    required this.clave,
    required this.ciclo,
    required this.modalidad,
    required this.inicio,
    required this.termino,
    this.terminada = false,
  });
}

// Convierte una fecha a algo legible en espanol: "25 may 2026".
// Entiende dos formatos:
//   1) ISO corta:  "2026-05-25"
//   2) Texto largo en ingles (que manda el Guardian/JS):
//      "Mon May 25 2026 00:00:00 GMT-0700 (Pacific Daylight Time)"
// Si no la reconoce, devuelve el texto original.
/// Lee una fecha en ISO "2026-05-25" o el toString nativo de Date
/// "Mon Jul 20 2026 ..." y devuelve un DateTime (o null).
DateTime? _fechaMateria(String s) {
  s = s.trim();
  if (s.isEmpty) return null;
  // ISO corta
  if (s.length >= 10 && s[4] == '-' && s[7] == '-') {
    final p = s.substring(0, 10).split('-');
    final a = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (a != null && m != null && d != null) return DateTime(a, m, d);
  }
  // toString nativo: "Mon Jul 20 2026 00:00:00 ..."
  const mi = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
  };
  final parts = s.split(RegExp(r'\s+'));
  if (parts.length >= 4) {
    final m = mi[parts[1].toLowerCase()];
    final d = int.tryParse(parts[2]);
    final a = int.tryParse(parts[3]);
    if (m != null && d != null && a != null) return DateTime(a, m, d);
  }
  return null;
}

String _fechaBonita(String s) {
  if (s.trim().isEmpty) return '';
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  const mesesIngles = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
  };

  // --- Formato 1: ISO corta "2026-05-25" ---
  final base = s.length >= 10 ? s.substring(0, 10) : s;
  final partesIso = base.split('-');
  if (partesIso.length == 3) {
    final anio = int.tryParse(partesIso[0]);
    final mes = int.tryParse(partesIso[1]);
    final dia = int.tryParse(partesIso[2]);
    if (anio != null && mes != null && dia != null &&
        mes >= 1 && mes <= 12 && anio > 1900) {
      return '$dia ${meses[mes - 1]} $anio';
    }
  }

  // --- Formato 2: texto largo en ingles ---
  // Ej: "Mon May 25 2026 00:00:00 GMT-0700 (Pacific Daylight Time)"
  // Buscamos el nombre del mes en ingles, el dia y el anio.
  final lower = s.toLowerCase();
  for (final entry in mesesIngles.entries) {
    final idx = lower.indexOf(entry.key);
    if (idx >= 0) {
      // Despues del mes viene el dia; el anio es el primer numero de 4 digitos.
      final resto = s.substring(idx + 3);
      final numeros = RegExp(r'\d+').allMatches(resto).map((m) => m.group(0)!).toList();
      int? dia;
      int? anio;
      for (final n in numeros) {
        if (n.length == 4 && anio == null) {
          anio = int.tryParse(n);
        } else if (dia == null && int.tryParse(n) != null && int.parse(n) >= 1 && int.parse(n) <= 31) {
          dia = int.tryParse(n);
        }
        if (dia != null && anio != null) break;
      }
      if (dia != null && anio != null) {
        return '$dia ${meses[entry.value - 1]} $anio';
      }
    }
  }

  return s;
}

class CapturaCalificacionesScreen extends StatefulWidget {
  /// (9-oct-2026) Materia preseleccionada al abrir (la manda el Laboratorio de
  /// evaluación cuando se abre desde «Mi horario»): programa, generacion,
  /// grupo, materia, clave, ciclo y, opcionalmente, dia, hora, inicio, termino.
  final Map<String, String>? preseleccion;

  /// (9-oct-2026) Calificaciones sugeridas por el laboratorio (matrícula → 6-10).
  /// Se aplican al cargar la lista y quedan como cambios SIN guardar: el
  /// docente las revisa y decide si guarda el avance o genera el acta.
  final Map<String, int>? sugerencias;

  const CapturaCalificacionesScreen({
    super.key,
    this.preseleccion,
    this.sugerencias,
  });

  @override
  State<CapturaCalificacionesScreen> createState() =>
      _CapturaCalificacionesScreenState();
}

class _CapturaCalificacionesScreenState
    extends State<CapturaCalificacionesScreen> {
  List<_ProgCat> _catalogo = [];
  bool _cargandoCatalogo = true;
  String? _errorCatalogo;

  Map<String, List<_MateriaCarta>> _materiasPorPrograma = {};
  _MateriaCarta? _materiaSeleccionada;

  String? _programa;
  String? _generacion;
  String? _grupo;

  final TextEditingController _materia = TextEditingController();
  final TextEditingController _clave = TextEditingController();
  final TextEditingController _ciclo = TextEditingController();
  final TextEditingController _modalidad =
      TextEditingController(text: 'No Escolarizada');

  List<_FilaAlumno> _alumnos = [];
  bool _cargandoAlumnos = false;

  // Matrículas con estatus "Baja" en la clasificación de alumnos.
  // Los dados de baja NO aparecen en las listas a calificar.
  Set<String> _bajas = {};

  String _docente = '';
  bool _enviando = false;

  // Modo administrador / prueba
  bool _esAdminUsuario = false;
  bool _modoPrueba = false;

  // Mis materias asignadas (para docentes no-admin)
  List<_MateriaAsignada> _misMaterias = [];
  /// La barra de diagnóstico solo aparece tras tocar el título 3 veces.
  bool _verDiag = false;
  int _toquesTitulo = 0;
  bool _cargandoMisMaterias = false;
  // Diagnóstico temporal (quitar después): qué correo y rol detecta.
  String _diagCorreo = '';
  bool _falloCargaMaterias = false;
  bool _diagAdmin = false;
  _MateriaAsignada? _materiaAsignadaActiva;
  // Cuando el docente elige "Otra asignatura", entra al llenado manual
  // (igual que el admin, con selección de grupo del catálogo).
  bool _modoManualDocente = false;

  // Semáforo de captura (lo controla el admin desde su menú)
  bool _capturaCerradaParaDocente = false;

  // Filtros operativos de la lista de alumnos.
  String _busquedaAlumno = '';
  bool _soloPendientes = false;
  String _orden = 'nombre'; // 'nombre' (A-Z) o 'pendientes' (pendientes primero)

  // Protección contra pérdida de datos: se activa al modificar notas y se
  // desactiva al guardar avance o generar acta.
  bool _cambiosSinGuardar = false;

  // (9-oct-2026) Sugerencias del Laboratorio de evaluación que se aplican en
  // cuanto llega la lista de alumnos (matrícula → entero 6-10).
  Map<String, int>? _sugerenciasPendientes;

  // (9-oct-2026) ALERTA DE POSIBLE BAJA. Lo que el docente ya reportó de este
  // grupo y materia (matrícula normalizada → alerta del Guardián), para pintar
  // la bandera en cada renglón y no duplicar reportes.
  Map<String, Map<String, dynamic>> _alertasBaja = {};
  bool _cargandoAlertas = false;
  String _ayudaBaja = '';

  @override
  void initState() {
    super.initState();
    _sugerenciasPendientes = widget.sugerencias;
    _cargarPerfil();
    _cargarCartas();
    _cargarBajas();
    _arrancarSegunRol();
  }

  Future<void> _arrancarSegunRol() async {
    final correo = await SessionStore.validEmail();
    final admin = esAdmin(correo);
    _diagCorreo = correo ?? '(vacío)';
    _diagAdmin = admin;
    if (mounted) {
      setState(() => _esAdminUsuario = admin);
    }
    if (admin) {
      // Admin (p.ej. vicerrectoría): al arrancar carga SUS materias asignadas
      // como docente, para poder calificar como profesor (vista "Mis materias").
      // El catálogo completo (para capturar cualquier grupo) se carga bajo
      // demanda al tocar "Otra asignatura (capturar manualmente)".
      _abrirPreseleccion();
      _cargarMisGrupos(correo ?? '');
    } else {
      // Docente normal: primero revisamos el semáforo de captura.
      final abierta = await _consultarSemaforo();
      if (!abierta) {
        if (mounted) {
          setState(() {
            _capturaCerradaParaDocente = true;
            _cargandoCatalogo = false;
            _cargandoMisMaterias = false;
          });
        }
        return;
      }
      // Semáforo abierto: cargamos sus materias asignadas.
      _abrirPreseleccion();
      _cargarMisGrupos(correo ?? '');
    }
  }

  /// (9-oct-2026) Si la pantalla se abrió con una materia preseleccionada
  /// (desde el Laboratorio de evaluación), se entra directo a su captura sin
  /// esperar la lista de «Mis materias»; esa lista se carga detrás para que
  /// «Cambiar» siga funcionando.
  void _abrirPreseleccion() {
    final pre = widget.preseleccion;
    if (pre == null) return;
    if ((pre['programa'] ?? '').trim().isEmpty ||
        (pre['generacion'] ?? '').trim().isEmpty ||
        (pre['grupo'] ?? '').trim().isEmpty) {
      return;
    }
    if (!mounted) return;
    _seleccionarMateriaAsignada(_MateriaAsignada(
      programa: (pre['programa'] ?? '').trim(),
      generacion: (pre['generacion'] ?? '').trim(),
      grupo: (pre['grupo'] ?? '').trim(),
      dia: (pre['dia'] ?? '').trim(),
      hora: (pre['hora'] ?? '').trim(),
      materia: (pre['materia'] ?? '').trim(),
      clave: (pre['clave'] ?? '').trim(),
      ciclo: (pre['ciclo'] ?? '').trim(),
      modalidad: (pre['modalidad'] ?? '').trim(),
      inicio: (pre['inicio'] ?? '').trim(),
      termino: (pre['termino'] ?? '').trim(),
    ));
  }

  Future<bool> _consultarSemaforo() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'estado_captura'});
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        return data['abierta'] == true;
      }
      // Si algo sale mal leyendo el semáforo, por seguridad permitimos
      // (no bloqueamos al docente por un error de red puntual).
      return true;
    } catch (_) {
      return true;
    }
  }

  @override
  void dispose() {
    _materia.dispose();
    _clave.dispose();
    _ciclo.dispose();
    _modalidad.dispose();
    super.dispose();
  }

  Future<void> _cargarPerfil() async {
    final p = await TeacherProfile.load();
    if (mounted && p != null) {
      setState(() => _docente = p.saludoCompleto);
    }
  }

  /// Lee la clasificación de alumnos del Guardián y guarda las matrículas
  /// con estatus "Baja", para excluirlas de las listas a calificar.
  /// Si falla, no bloquea nada: solo no se filtran en esta carga.
  Future<void> _cargarBajas() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'clasificacion_alumnos'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) return;
      final lista = (data['alumnos'] as List<dynamic>? ?? []);
      final bajas = <String>{};
      for (final e in lista) {
        final m = Map<String, dynamic>.from(e as Map);
        if ((m['tipo'] ?? '').toString() == 'Baja') {
          final mat = (m['matricula'] ?? '').toString().trim();
          if (mat.isNotEmpty) bajas.add(mat);
        }
      }
      if (mounted) {
        setState(() {
          _bajas = bajas;
          // Si ya había una lista cargada, se filtra al instante.
          if (_alumnos.isNotEmpty) {
            _alumnos = _alumnos
                .where((a) => !_bajas.contains(a.matricula.trim()))
                .toList();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _verificarAdmin() async {
    final correo = await SessionStore.validEmail();
    if (mounted) {
      setState(() => _esAdminUsuario = esAdmin(correo));
    }
  }

  Future<void> _cargarMisGrupos(String correo) async {
    setState(() {
      _cargandoMisMaterias = true;
      _cargandoCatalogo = false;
      _errorCatalogo = null;
    });
    // (ago-9) EL CATÁLOGO ARRANCA EN PARALELO, NO DESPUÉS.
    // Antes se esperaba a que terminara `mis_grupos_capturables` (60 s de
    // tope) y solo entonces empezaba el catálogo. Para un administrador sin
    // materias propias esa primera espera es inútil pero se pagaba completa:
    // dos cargas en fila para ver una. Ahora las dos salen juntas y la
    // pantalla responde en el tiempo de la más lenta, no en la suma.
    if (_esAdminUsuario && _catalogo.isEmpty) {
      _cargarCatalogo();
    }
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_grupos_capturables',
        'correo': correo,
        'ligero': '1',
      });
      // 60 s: misGruposCapturables calcula montos/letras por materia y para un
      // docente con muchas asignaciones (p.ej. vicerrectoría, 16) puede tardar
      // >25 s. Con el timeout viejo caía al catch y, siendo admin, la pantalla
      // se iba a la vista de catálogo mostrando "0 materias".
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      final lista = (data['grupos'] as List<dynamic>? ?? []);
      final mats = lista.map((e) {
        final m = e as Map<String, dynamic>;
        return _MateriaAsignada(
          programa: (m['programa'] ?? '').toString(),
          generacion: (m['generacion'] ?? '').toString(),
          grupo: (m['grupo'] ?? '').toString(),
          dia: (m['dia'] ?? '').toString(),
          hora: (m['hora'] ?? '').toString(),
          materia: (m['materia'] ?? '').toString(),
          clave: (m['clave'] ?? '').toString(),
          ciclo: (m['ciclo'] ?? '').toString(),
          modalidad: (m['modalidad'] ?? '').toString(),
          inicio: (m['inicio'] ?? '').toString(),
          termino: (m['termino'] ?? '').toString(),
          terminada: (m['terminada'] == true),
        );
      }).toList();
      // Orden: primero las PENDIENTES de calificar (ya terminaron), luego las
      // en curso, luego las futuras. Dentro de cada grupo, por fecha de término
      // (la que cierra antes, arriba: es la más urgente).
      final hoy = DateTime.now();
      int rango(_MateriaAsignada m) {
        final ini = _fechaMateria(m.inicio);
        final fin = _fechaMateria(m.termino);
        if (m.terminada) return 0; // pendiente de evaluar → primero
        if (ini != null && ini.isAfter(hoy)) return 2; // futura → al final
        return 1; // en curso
      }
      mats.sort((a, b) {
        final ra = rango(a), rb = rango(b);
        if (ra != rb) return ra.compareTo(rb);
        final fa = _fechaMateria(a.termino), fb = _fechaMateria(b.termino);
        if (fa == null && fb == null) return 0;
        if (fa == null) return 1;
        if (fb == null) return -1;
        return fa.compareTo(fb);
      });
      if (mounted) {
        setState(() {
          _misMaterias = mats;
          _cargandoMisMaterias = false;
        });
        // Respaldo: si el arranque en paralelo no alcanzó a dispararse
        // —por ejemplo si el rol de admin se resolvió tarde—, se carga aquí
        // como antes. La guarda de _catalogo.isEmpty evita pedirlo dos veces.
        if (_esAdminUsuario && mats.isEmpty && _catalogo.isEmpty &&
            !_cargandoCatalogo) {
          _cargarCatalogo();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargandoMisMaterias = false;
          _errorCatalogo =
              'No se pudieron cargar tus materias asignadas (la consulta tardó demasiado). Toca "Reintentar".';
          _falloCargaMaterias = true;
        });
      }
    }
  }

  void _seleccionarMateriaAsignada(_MateriaAsignada m) {
    setState(() {
      _materiaAsignadaActiva = m;
      _programa = m.programa;
      _generacion = m.generacion;
      _grupo = m.grupo;
      _materia.text = m.materia;
      _clave.text = m.clave;
      _ciclo.text = m.ciclo;
      // El campo modalidad lo dejamos como está (suele ser "No Escolarizada")
      _alumnos = [];
    });
    _cargarAlumnos();
  }

  void _volverAMisMaterias() {
    _sugerenciasPendientes = null;
    setState(() {
      _materiaAsignadaActiva = null;
      _modoManualDocente = false;
      _programa = null;
      _generacion = null;
      _grupo = null;
      _materia.clear();
      _clave.clear();
      _ciclo.clear();
      _alumnos = [];
    });
  }

  // El docente elige "Otra asignatura": entra al llenado manual con el
  // catálogo de grupos (igual que el admin). Carga el catálogo si hace falta.
  void _activarModoManualDocente() {
    setState(() {
      _modoManualDocente = true;
      _materiaAsignadaActiva = null;
      _programa = null;
      _generacion = null;
      _grupo = null;
      _materia.clear();
      _clave.clear();
      _ciclo.clear();
      _alumnos = [];
    });
    if (_catalogo.isEmpty) _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() async {
    setState(() {
      _cargandoCatalogo = true;
      _errorCatalogo = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'grupos'});
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      final lista = (data['catalogo'] as List<dynamic>? ?? []);
      final cat = <_ProgCat>[];
      for (final p in lista) {
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
      if (mounted) {
        setState(() {
          _catalogo = cat;
          _cargandoCatalogo = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargandoCatalogo = false;
          _errorCatalogo =
              'No se pudo cargar la lista de grupos. Revisa tu conexion e intenta de nuevo.';
        });
      }
    }
  }

  Future<void> _cargarCartas() async {
    try {
      final resp = await http
          .get(Uri.parse(cartasJsonUrl))
          .timeout(const Duration(seconds: 20));
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final progs = (data['programas'] as List<dynamic>? ?? []);
      final mapa = <String, List<_MateriaCarta>>{};
      for (final p in progs) {
        final pm = p as Map<String, dynamic>;
        final progName = (pm['programa'] ?? '').toString();
        final asigs = <_MateriaCarta>[];
        for (final a in (pm['asignaturas'] as List<dynamic>? ?? [])) {
          final am = a as Map<String, dynamic>;
          asigs.add(_MateriaCarta(
            denominacion: (am['denominacion'] ?? '').toString(),
            clave: (am['clave'] ?? '').toString(),
            semestre: (am['semestre'] ?? '').toString(),
          ));
        }
        mapa[progName] = asigs;
      }
      if (mounted) setState(() => _materiasPorPrograma = mapa);
    } catch (_) {}
  }

  // Convierte la calificación que viene del servidor (num o texto) a int?.
  int? _parseCalif(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    final t = v.toString().trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final d = double.tryParse(t);
    return d?.round();
  }

  Future<void> _cargarAlumnos() async {
    if (_programa == null || _generacion == null || _grupo == null) return;
    setState(() {
      _cargandoAlumnos = true;
      _alumnos = [];
    });
    try {
      final params = <String, String>{
        'accion': 'alumnos',
        'programa': _programa!,
        'generacion': _generacion!,
        'grupo': _grupo!,
      };
      final matSel = _materia.text.trim();
      if (matSel.isNotEmpty) params['materia'] = matSel;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final lista = (data['alumnos'] as List<dynamic>? ?? []);
      final filas = lista
          .map((e) {
            final m = e as Map<String, dynamic>;
            return _FilaAlumno(
              matricula: (m['matricula'] ?? '').toString(),
              nombre: (m['nombre'] ?? '').toString(),
              correo: (m['correo'] ?? '').toString(),
              calificacion: _parseCalif(m['calificacion']),
            );
          })
          // Los alumnos con estatus "Baja" no se califican.
          .where((f) => !_bajas.contains(f.matricula.trim()))
          .toList();
      // (9-oct-2026) Sugerencias del laboratorio: se ponen en la lista como
      // cambios sin guardar. Solo enteros válidos del acta (6-10).
      final aplicadas = _aplicarSugerencias(filas, _sugerenciasPendientes);
      _sugerenciasPendientes = null;
      if (mounted) {
        setState(() {
          _alumnos = filas;
          _cargandoAlumnos = false;
          if (aplicadas > 0) _cambiosSinGuardar = true;
        });
        if (aplicadas > 0) {
          _aviso('Se aplicaron $aplicadas calificación(es) sugerida(s) por el '
              'Laboratorio de evaluación. Revísalas y guarda el avance o genera el acta.');
        }
        _cargarAlertasBaja();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargandoAlumnos = false);
        _aviso('No se pudo cargar la lista de alumnos. Intenta de nuevo.');
      }
    }
  }

  // ---------------------------------------------------------------------
  // (9-oct-2026) ALERTA DE POSIBLE BAJA REPORTADA POR EL DOCENTE
  // Un reprobado (6) lleva una bandera: tocarla abre el reporte a
  // Vicerrectoría (motivo, detalle, si intentó contactarlo). La alerta NO da
  // de baja: avisa a tiempo. El «?» explica cuándo marcarla.
  // ---------------------------------------------------------------------
  static String _matNorm(String m) =>
      m.trim().replaceFirst(RegExp(r'^0+(?=\d)'), '');

  Future<void> _cargarAlertasBaja() async {
    if (_programa == null || _generacion == null || _grupo == null) return;
    final actor = await SessionStore.validEmail() ?? '';
    if (actor.isEmpty) return;
    if (mounted) setState(() => _cargandoAlertas = true);
    try {
      final params = <String, String>{
        'accion': 'baja_docente_mias',
        'actor': actor,
        'programa': _programa!,
        'generacion': _generacion!,
        'grupo': _grupo!,
      };
      final matSel = _materia.text.trim();
      if (matSel.isNotEmpty) params['materia'] = matSel;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) return;
      final mapa = <String, Map<String, dynamic>>{};
      for (final it in ((data['items'] as List?) ?? [])) {
        final m = Map<String, dynamic>.from(it as Map);
        final k = _matNorm('${m['matricula'] ?? ''}');
        if (k.isEmpty) continue;
        // La abierta manda; si todas están resueltas, se muestra la última.
        final previa = mapa[k];
        if (previa == null ||
            (m['abierta'] == true && previa['abierta'] != true)) {
          mapa[k] = m;
        }
      }
      if (mounted) {
        setState(() {
          _alertasBaja = mapa;
          _ayudaBaja = '${data['ayuda'] ?? ''}';
        });
      }
    } catch (_) {
      // Sin alertas no pasa nada: la bandera sigue disponible.
    } finally {
      if (mounted) setState(() => _cargandoAlertas = false);
    }
  }

  static const Map<String, String> _motivosBaja = {
    'no_conecto': 'No se conectó a las sesiones',
    'abandono': 'Dejó de conectarse a medio curso',
    'sin_entregas': 'No entregó evidencias',
    'reprobo': 'Reprobó aunque participó',
    'aviso_baja': 'Avisó que deja el programa',
    'otro': 'Otro',
  };

  static const String _ayudaBajaFija =
      'Marca «posible baja» cuando el alumno reprobó (6) y además: no se conectó '
      'a las sesiones o dejó de conectarse, no entregó las evidencias, avisó que '
      'deja el programa o no responde a tus mensajes.\n\n'
      'No la uses por una sola falta ni cuando sí trabajó y solo le faltó puntaje: '
      'para eso está la retroalimentación.\n\n'
      'La alerta NO da de baja a nadie: avisa a Vicerrectoría para que lo contacte a '
      'tiempo y decida conforme al Reglamento (Art. 40). Si vuelves a reportar al '
      'mismo alumno en la misma materia, se actualiza la alerta abierta, no se duplica.';

  Future<void> _ayudaPosibleBaja() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.help_outline, color: cessumRed),
          SizedBox(width: 8),
          Expanded(child: Text('¿Cuándo marcar posible baja?')),
        ]),
        content: SingleChildScrollView(
          child: Text(
            _ayudaBaja.isNotEmpty ? _ayudaBaja : _ayudaBajaFija,
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _dialogoAlertaBaja(_FilaAlumno a) async {
    final previa = _alertasBaja[_matNorm(a.matricula)];
    final abierta = previa != null && previa['abierta'] == true;
    String motivo = abierta ? '${previa['motivo'] ?? ''}' : 'no_conecto';
    if (!_motivosBaja.containsKey(motivo)) motivo = 'no_conecto';
    final detalle = TextEditingController(
        text: abierta ? '${previa['detalle'] ?? ''}' : '');
    final desde =
        TextEditingController(text: abierta ? '${previa['desde'] ?? ''}' : '');
    bool contacto =
        abierta && '${previa['contacto'] ?? ''}'.toLowerCase().startsWith('s');
    bool enviando = false;
    String error = '';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          title: Row(children: [
            const Icon(Icons.flag, color: cessumRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Posible baja · ${a.nombre}',
                  style: const TextStyle(fontSize: 16)),
            ),
            IconButton(
              tooltip: '¿Cuándo marcarlo?',
              icon: const Icon(Icons.help_outline, color: cessumGold),
              onPressed: _ayudaPosibleBaja,
            ),
          ]),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${a.matricula} · ${_materia.text.trim()}'
                    '${a.calificacion != null ? ' · calificación ${a.calificacion}' : ''}',
                    style: TextStyle(fontSize: 12, color: _textoSuave),
                  ),
                  if (previa != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: abierta
                            ? cessumGold.withValues(alpha: 0.12)
                            : Colors.green.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        abierta
                            ? 'Ya reportaste a este alumno en esta materia el '
                                '${previa['fecha'] ?? ''} (${previa['estadoTexto'] ?? previa['estado'] ?? ''}). '
                                'Si envías de nuevo, se actualiza la alerta ${previa['folio'] ?? ''}; no se duplica.'
                            : 'Hubo una alerta anterior (${previa['folio'] ?? ''}) que ya se resolvió: '
                                '${previa['estadoTexto'] ?? previa['estado'] ?? ''}. Si vuelves a reportar, se abre una nueva.',
                        style: const TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text('¿Qué observaste?',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _motivosBaja.entries.map((e) {
                      final sel = motivo == e.key;
                      return ChoiceChip(
                        label: Text(e.value,
                            style: const TextStyle(fontSize: 12)),
                        selected: sel,
                        selectedColor: cessumRed.withValues(alpha: 0.15),
                        onSelected: enviando
                            ? null
                            : (_) => setD(() => motivo = e.key),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: detalle,
                    enabled: !enviando,
                    maxLines: 4,
                    minLines: 2,
                    maxLength: 900,
                    decoration: InputDecoration(
                      labelText: motivo == 'otro'
                          ? 'Describe qué observaste (obligatorio)'
                          : 'Detalle (opcional, pero ayuda): qué pasó, desde cuándo, qué intentaste',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  TextField(
                    controller: desde,
                    enabled: !enviando,
                    decoration: const InputDecoration(
                      labelText:
                          '¿Desde cuándo? (ej. sesión 3, 20 de septiembre)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  CheckboxListTile(
                    value: contacto,
                    onChanged: enviando
                        ? null
                        : (v) => setD(() => contacto = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: cessumRed,
                    title: const Text(
                        'Intenté contactarlo/a (mensaje, llamada o correo)',
                        style: TextStyle(fontSize: 13)),
                  ),
                  Text(
                    'La alerta llega a Vicerrectoría para contactar al alumno. No lo da de baja.',
                    style: TextStyle(fontSize: 11.5, color: _textoSuave),
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(error,
                        style:
                            const TextStyle(color: cessumRed, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: enviando ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: enviando
                  ? null
                  : () async {
                      if (motivo == 'otro' &&
                          detalle.text.trim().length < 10) {
                        setD(() =>
                            error = 'Con «Otro», describe qué observaste.');
                        return;
                      }
                      setD(() {
                        enviando = true;
                        error = '';
                      });
                      final actor = await SessionStore.validEmail() ?? '';
                      final payload = {
                        'accion': 'baja_docente_alertar',
                        'actor': actor,
                        'matricula': a.matricula,
                        'alumno': a.nombre,
                        'correoAlumno': a.correo,
                        'programa': _programa ?? '',
                        'generacion': _generacion ?? '',
                        'grupo': _grupo ?? '',
                        'materia': _materia.text.trim(),
                        'clave': _clave.text.trim(),
                        'ciclo': _ciclo.text.trim(),
                        'calificacion': a.calificacion == null
                            ? ''
                            : '${a.calificacion}',
                        'motivo': motivo,
                        'detalle': detalle.text.trim(),
                        'contacto': contacto ? '1' : '0',
                        'desde': desde.text.trim(),
                      };
                      try {
                        final resp = await http
                            .post(Uri.parse(guardianUrl),
                                headers: {
                                  'Content-Type': 'text/plain;charset=utf-8'
                                },
                                body: jsonEncode(payload))
                            .timeout(const Duration(seconds: 60));
                        final data =
                            jsonDecode(resp.body) as Map<String, dynamic>;
                        if (data['ok'] != true) {
                          setD(() {
                            enviando = false;
                            error =
                                '${data['error'] ?? 'No se pudo enviar.'}';
                          });
                          return;
                        }
                        if (mounted) {
                          setState(() {
                            _alertasBaja[_matNorm(a.matricula)] = {
                              'folio': data['folio'],
                              'estado': data['estado'] ?? 'reportada',
                              'estadoTexto':
                                  data['estadoTexto'] ?? 'Reportada',
                              'abierta': true,
                              'motivo': motivo,
                              'motivoTexto': data['motivoTexto'] ??
                                  _motivosBaja[motivo],
                              'detalle': detalle.text.trim(),
                              'desde': desde.text.trim(),
                              'contacto': contacto ? 'Sí' : 'No',
                              'fecha': 'hoy',
                            };
                          });
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _aviso('${data['nota'] ?? 'Alerta enviada.'}');
                      } on TimeoutException {
                        setD(() {
                          enviando = false;
                          error = 'Tardó demasiado. Intenta de nuevo.';
                        });
                      } catch (e) {
                        setD(() {
                          enviando = false;
                          error = 'No se pudo enviar: $e';
                        });
                      }
                    },
              icon: enviando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.flag),
              label: Text(enviando
                  ? 'Enviando…'
                  : (abierta
                      ? 'Actualizar la alerta'
                      : 'Alertar a Vicerrectoría')),
            ),
          ],
        ),
      ),
    );
  }

  /// La bandera del renglón: visible para reprobados (6) y para quien ya tiene
  /// alerta. Dorada y llena si ya se reportó; roja hueca si está disponible.
  Widget _banderaBaja(_FilaAlumno a) {
    final alerta = _alertasBaja[_matNorm(a.matricula)];
    final abierta = alerta != null && alerta['abierta'] == true;
    final esReprobado = a.calificacion == 6;
    if (!esReprobado && alerta == null) return const SizedBox(width: 4);
    return IconButton(
      icon: Icon(
        abierta ? Icons.flag : Icons.flag_outlined,
        size: 20,
        color: abierta
            ? cessumGold
            : (alerta != null ? _textoSuave : cessumRed),
      ),
      tooltip: abierta
          ? 'Posible baja reportada · ${alerta['estadoTexto'] ?? alerta['estado'] ?? ''} · toca para ver o actualizar'
          : (alerta != null
              ? 'Alerta anterior resuelta: ${alerta['estadoTexto'] ?? ''} · toca para reportar de nuevo'
              : 'Alertar posible baja (reprobado)'),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      onPressed: () => _dialogoAlertaBaja(a),
    );
  }

  int get _conAlertaBaja => _alumnos
      .where((a) => (_alertasBaja[_matNorm(a.matricula)]?['abierta']) == true)
      .length;

  /// Una línea bajo las métricas: qué es la bandera y el «?» de ayuda.
  Widget _notaPosibleBaja() {
    if (_reprobados == 0 && _conAlertaBaja == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(_conAlertaBaja > 0 ? Icons.flag : Icons.flag_outlined,
              size: 16, color: _conAlertaBaja > 0 ? cessumGold : cessumRed),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _conAlertaBaja > 0
                  ? '$_conAlertaBaja con alerta de posible baja enviada a Vicerrectoría. '
                      'Los demás reprobados tienen su bandera para alertar.'
                  : 'Los reprobados (6) llevan una bandera: úsala para alertar una posible baja, '
                      'sobre todo si no se conectó a las sesiones.',
              style: TextStyle(fontSize: 11.5, color: _textoSuave, height: 1.3),
            ),
          ),
          IconButton(
            tooltip: '¿Cuándo marcar posible baja?',
            icon: const Icon(Icons.help_outline, size: 18, color: cessumGold),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            onPressed: _ayudaPosibleBaja,
          ),
          if (_cargandoAlertas)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
    );
  }

  /// (9-oct-2026) Aplica [sug] (matrícula → entero) a [filas]. Devuelve
  /// cuántas calificaciones cambiaron. No toca a quien no tiene sugerencia.
  int _aplicarSugerencias(List<_FilaAlumno> filas, Map<String, int>? sug) {
    if (sug == null || sug.isEmpty) return 0;
    String norm(String m) => m.trim().replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final idx = <String, int>{};
    sug.forEach((k, v) => idx[norm(k)] = v);
    var n = 0;
    for (final f in filas) {
      final v = idx[norm(f.matricula)];
      if (v != null && v >= 6 && v <= 10) {
        f.calificacion = v;
        n++;
      }
    }
    return n;
  }

  /// (9-oct-2026) Abre el Laboratorio de evaluación con el grupo y la materia
  /// que están en pantalla. Si devuelve sugerencias, se aplican a la lista.
  Future<void> _abrirLaboratorio() async {
    if (_programa == null || _generacion == null || _grupo == null) {
      _aviso('Primero elige programa, generación y grupo.');
      return;
    }
    if (_materia.text.trim().isEmpty) {
      _aviso('Escribe o elige la materia: el laboratorio lee las actividades de su aula.');
      return;
    }
    if (_cambiosSinGuardar) {
      final ok = await _confirmar(
        'Abrir el laboratorio',
        'Tienes calificaciones capturadas sin guardar. Si el laboratorio te '
            'devuelve sugerencias, reemplazarán las de los alumnos que tengan '
            'sugerencia; el resto no cambia. ¿Continuar?',
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final r = await Navigator.push<Map<String, int>>(
      context,
      MaterialPageRoute(
        builder: (_) => LaboratorioEvaluacionScreen(
          programa: _programa!,
          generacion: _generacion!,
          grupo: _grupo!,
          materia: _materia.text.trim(),
          clave: _clave.text.trim(),
          ciclo: _ciclo.text.trim(),
          modalidad: _modalidad.text.trim(),
          docente: _docente,
          desdeCaptura: true,
        ),
      ),
    );
    if (!mounted || r == null) return;
    final n = _aplicarSugerencias(_alumnos, r);
    setState(() {
      if (n > 0) _cambiosSinGuardar = true;
    });
    _aviso(n > 0
        ? 'Se aplicaron $n calificación(es) sugerida(s). Revísalas y guarda el avance o genera el acta.'
        : 'El laboratorio no devolvió sugerencias para los alumnos de esta lista.');
  }

  /// (9-oct-2026) Desde la tarjeta de «Mis materias»: abre el laboratorio de
  /// esa materia y, si devuelve sugerencias, entra a su captura con ellas puestas.
  Future<void> _laboratorioDesdeTarjeta(_MateriaAsignada m) async {
    final r = await Navigator.push<Map<String, int>>(
      context,
      MaterialPageRoute(
        builder: (_) => LaboratorioEvaluacionScreen(
          programa: m.programa,
          generacion: m.generacion,
          grupo: m.grupo,
          materia: m.materia,
          clave: m.clave,
          ciclo: m.ciclo,
          modalidad: _modalidad.text.trim(),
          docente: _docente,
          desdeCaptura: true,
        ),
      ),
    );
    if (!mounted || r == null) return;
    _sugerenciasPendientes = r;
    _seleccionarMateriaAsignada(m);
  }

  /// (9-oct-2026) Acceso al laboratorio desde la captura.
  Widget _botonLaboratorio() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.science_outlined, color: cessumGold, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Laboratorio de evaluación',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _textoFuerte)),
                const SizedBox(height: 2),
                Text(
                  'Trae las notas de las actividades del aula y la asistencia, '
                  'deja ajustar los pesos y sugiere la calificación de cada alumno.',
                  style: TextStyle(fontSize: 11, color: _textoSuave, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumGold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            onPressed: _abrirLaboratorio,
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
  }

  List<String> get _generacionesDisponibles {
    final p = _catalogo.where((e) => e.programa == _programa);
    if (p.isEmpty) return [];
    return p.first.generaciones.map((g) => g.generacion).toList();
  }

  List<String> get _gruposDisponibles {
    final p = _catalogo.where((e) => e.programa == _programa);
    if (p.isEmpty) return [];
    final g =
        p.first.generaciones.where((e) => e.generacion == _generacion);
    if (g.isEmpty) return [];
    return g.first.grupos;
  }

  List<_MateriaCarta> get _materiasDelPrograma =>
      _materiasPorPrograma[_programa] ?? const [];

  int get _capturados =>
      _alumnos.where((a) => a.calificacion != null).length;
  int get _aprobados => _alumnos
      .where((a) => a.calificacion != null && a.calificacion! >= 7)
      .length;
  int get _reprobados =>
      _alumnos.where((a) => a.calificacion == 6).length;

  void _eliminarAlumno(int i) {
    final eliminado = _alumnos[i];
    setState(() => _alumnos.removeAt(i));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Se quitó "${eliminado.nombre}" de la lista'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        action: SnackBarAction(
          label: 'Deshacer',
          textColor: Colors.amber,
          onPressed: () => setState(() => _alumnos.insert(i, eliminado)),
        ),
      ),
    );
  }

  Future<void> _dialogoAgregarAlumno() async {
    final matricula = TextEditingController();
    final nombre = TextEditingController();
    final correo = TextEditingController();
    final busqueda = TextEditingController();
    List<Map<String, dynamic>> resultados = [];
    bool buscando = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar alumno'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> buscarEnPadron() async {
              final q = busqueda.text.trim();
              if (q.length < 2) {
                setLocal(() => resultados = []);
                return;
              }
              setLocal(() => buscando = true);
              try {
                final uri = Uri.parse(guardianUrl).replace(queryParameters: {
                  'accion': 'buscar_alumno',
                  'q': q,
                });
                final resp =
                    await http.get(uri).timeout(const Duration(seconds: 20));
                final data = jsonDecode(resp.body) as Map<String, dynamic>;
                final r = (data['alumnos'] as List<dynamic>? ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                setLocal(() {
                  resultados = r;
                  buscando = false;
                });
              } catch (_) {
                setLocal(() => buscando = false);
              }
            }

            return SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Búscalo en la base de datos por nombre o matrícula, o captúralo manualmente.',
                    style: TextStyle(fontSize: 12, color: _textoSuave),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: busqueda,
                    onChanged: (_) => buscarEnPadron(),
                    decoration: InputDecoration(
                      labelText: 'Buscar alumno (nombre o matrícula)',
                      prefixIcon: const Icon(Icons.search, color: cessumRed),
                      suffixIcon: buscando
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: cessumRed)))
                          : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (resultados.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: resultados.map((a) {
                          final baja = a['baja'] == true;
                          return ListTile(
                            dense: true,
                            title: Text((a['nombre'] ?? '').toString(),
                                style: const TextStyle(fontSize: 13.5)),
                            subtitle: Text(
                                '${a['matricula']} · ${a['programa'] ?? ''} ${baja ? '· BAJA' : ''}',
                                style: const TextStyle(fontSize: 11.5)),
                            onTap: () {
                              matricula.text = (a['matricula'] ?? '').toString();
                              nombre.text = (a['nombre'] ?? '').toString();
                              correo.text = (a['correo'] ?? '').toString();
                              setLocal(() => resultados = []);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),
                  TextField(
                    controller: matricula,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nombre,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: correo,
                    decoration: const InputDecoration(
                      labelText: 'Correo (opcional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (matricula.text.trim().isEmpty ||
                  nombre.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        _alumnos.add(_FilaAlumno(
          matricula: matricula.text.trim(),
          nombre: nombre.text.trim(),
          correo: correo.text.trim(),
        ));
      });
    }
  }

  /// Muestra un resumen del acta (aprobados, no acreditados, promedio) y pide
  /// confirmación antes de generar el documento oficial.
  Future<bool> _confirmarActa() async {
    final total = _alumnos.length;
    final cap = _capturados;
    final pend = total - cap;
    final notas = _alumnos
        .where((a) => a.calificacion != null)
        .map((a) => a.calificacion!)
        .toList();
    final prom =
        notas.isEmpty ? 0.0 : notas.reduce((a, b) => a + b) / notas.length;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            _modoPrueba ? 'Generar acta de PRUEBA' : 'Generar acta oficial',
            style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vas a registrar el acta con estos datos:',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            _filaResumen('Alumnos en el grupo', '$total'),
            _filaResumen('Calificados', '$cap'),
            _filaResumen('Aprobados (7-10)', '$_aprobados', const Color(0xFF1E8E3E)),
            _filaResumen('No acreditados (6)', '$_reprobados', cessumRed),
            if (pend > 0) _filaResumen('Sin calificar', '$pend', cessumRed),
            _filaResumen('Promedio del grupo', prom.toStringAsFixed(1)),
            if (pend > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Los $pend alumno(s) sin calificar aparecerán en blanco en el acta.',
                  style: const TextStyle(fontSize: 12, color: cessumRed),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _modoPrueba ? cessumGold : cessumRed,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generar acta'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Widget _filaResumen(String etiqueta, String valor, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: const TextStyle(fontSize: 13)),
          Text(valor,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color ?? _textoFuerte)),
        ],
      ),
    );
  }

  /// Comparte un resumen de texto del grupo (no un archivo), por lo que no
  /// depende de permisos de Drive. Útil para enviarlo por WhatsApp o correo.
  Future<void> _compartirResumen() async {
    if (_alumnos.isEmpty) {
      _aviso('Primero carga un grupo con alumnos.');
      return;
    }
    final notas = _alumnos
        .where((a) => a.calificacion != null)
        .map((a) => a.calificacion!)
        .toList();
    final prom =
        notas.isEmpty ? 0.0 : notas.reduce((a, b) => a + b) / notas.length;
    final b = StringBuffer()
      ..writeln('Resumen de calificaciones — CESSUM')
      ..writeln('Materia: ${_materia.text.trim()}')
      ..writeln(
          'Grupo: ${_programa ?? ''} ${_generacion ?? ''} ${_grupo ?? ''}'.trim())
      ..writeln('')
      ..writeln('Alumnos en el grupo: ${_alumnos.length}')
      ..writeln('Calificados: $_capturados')
      ..writeln('Aprobados (7-10): $_aprobados')
      ..writeln('No acreditados (6): $_reprobados')
      ..writeln('Promedio del grupo: ${prom.toStringAsFixed(1)}');
    await Share.share(b.toString(),
        subject: 'Resumen de calificaciones — CESSUM');
  }

  Future<void> _enviar({required bool generarActa}) async {
    if (_programa == null || _generacion == null || _grupo == null) {
      _aviso('Primero elige programa, generación y grupo.');
      return;
    }
    if (_materia.text.trim().isEmpty || _clave.text.trim().isEmpty) {
      _aviso('Escribe el nombre de la materia y su clave.');
      return;
    }
    final capturados =
        _alumnos.where((a) => a.calificacion != null).toList();
    if (capturados.isEmpty) {
      _aviso('Aún no has puesto ninguna calificación.');
      return;
    }
    if (generarActa) {
      final ok = await _confirmarActa();
      if (ok != true) return;
    }

    setState(() => _enviando = true);

    final capturadoPor = await SessionStore.validEmail() ?? '';
    final payload = {
      'accion': generarActa ? 'acta' : 'guardar',
      'capturadoPor': capturadoPor,
      'modoPrueba': _modoPrueba,
      'programa': _programa,
      'generacion': _generacion,
      'grupo': _grupo,
      'claveMateria': _clave.text.trim(),
      'materia': _materia.text.trim(),
      'ciclo': _ciclo.text.trim(),
      'modalidad': _modalidad.text.trim(),
      'docente': _docente,
      'alumnos': (generarActa ? _alumnos : capturados)
          .map((a) => {
                'matricula': a.matricula,
                'correo': a.correo,
                'nombre': a.nombre,
                'calificacion': a.calificacion,
              })
          .toList(),
    };

    http.Response? resp;
    String detalleError = '';
    try {
      resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));

      if (resp.statusCode != 200) {
        detalleError =
            'El servidor respondió con código ${resp.statusCode}.\n\n'
            'Respuesta:\n${_recorta(resp.body, 400)}';
        throw Exception('http ${resp.statusCode}');
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (e) {
        detalleError = 'La respuesta del servidor no es JSON.\n\n'
            '${_recorta(resp.body, 400)}';
        rethrow;
      }

      if (data['ok'] != true) {
        detalleError = 'El guardián reportó un error.\n\n${data['error']}';
        throw Exception('respuesta no ok');
      }

      if (!mounted) return;
      setState(() {
        _enviando = false;
        _cambiosSinGuardar = false; // ya quedó guardado/enviado en el servidor
      });

      if (generarActa) {
        final sheetUrl = (data['actaUrl'] ?? '').toString();
        final pdfUrl = (data['pdfUrl'] ?? '').toString();
        await _dialogoActa(sheetUrl, pdfUrl, _modoPrueba);
      } else {
        _aviso('Calificaciones guardadas: ${data['guardadas']}.');
      }
    } on TimeoutException {
      if (mounted) setState(() => _enviando = false);
      await _mostrarErrorDetalle(
        'La solicitud tardó demasiado (más de 90 segundos). '
        'Esto suele pasar al generar el acta cuando Google está lento. '
        'Vuelve a intentarlo en un momento.',
      );
    } catch (e) {
      if (mounted) setState(() => _enviando = false);
      if (detalleError.isEmpty) {
        detalleError = 'Detalle técnico:\n$e';
      }
      await _mostrarErrorDetalle(detalleError);
    }
  }

  String _recorta(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}...';
  }

  Future<void> _mostrarErrorDetalle(String detalle) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.error_outline, color: cessumRed),
            SizedBox(width: 8),
            Expanded(child: Text('No se pudo enviar')),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            detalle,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogoActa(
      String sheetUrl, String pdfUrl, bool esPrueba) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              esPrueba ? Icons.science : Icons.check_circle,
              color: esPrueba ? cessumGold : Colors.green,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(esPrueba ? 'Acta de PRUEBA generada' : 'Acta generada'),
            ),
          ],
        ),
        content: Text(
          esPrueba
              ? 'Este es un documento de PRUEBA. No se guardó en la base de calificaciones. '
                  'Los archivos se llaman "PRUEBA - ..." para que se distingan en el Drive.'
              : 'El acta quedó pública con enlace. Cualquiera con el enlace puede verla sin pedir acceso. '
                  'Puedes abrir la vista previa en PDF o la hoja editable.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          if (sheetUrl.isNotEmpty)
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(sheetUrl),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.table_chart, size: 18),
              label: const Text('Abrir Sheet'),
            ),
          if (pdfUrl.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => launchUrl(Uri.parse(pdfUrl),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Vista PDF'),
            ),
        ],
      ),
    );
  }

  Future<bool?> _confirmar(String titulo, String mensaje) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          backgroundColor: _modoPrueba ? cessumGold : cessumRed,
          foregroundColor: Colors.white,
          // Tres toques en el título revelan la barra de diagnóstico. Sigue
          // disponible para cuando haga falta, sin estar a la vista de todos.
          title: GestureDetector(
            onTap: () {
              _toquesTitulo++;
              if (_toquesTitulo >= 3) {
                setState(() {
                  _verDiag = !_verDiag;
                  _toquesTitulo = 0;
                });
              }
            },
            child: Text(
              _modoPrueba
                  ? 'Capturar calificaciones (PRUEBA)'
                  : 'Capturar calificaciones',
            ),
          ),
          actions: [
            if (_alumnos.isNotEmpty)
              IconButton(
                onPressed: _compartirResumen,
                icon: const Icon(Icons.share),
                tooltip: 'Compartir resumen del grupo',
              ),
          ],
        ),
        body: Column(
          children: [
            // (ago-9) La barra amarilla de DIAG estaba a la vista de CUALQUIERA
            // que entrara a capturar, docentes incluidos: "correo=... admin=true
            // · cargCat=false · cargMat=true". Es información de depuración, no
            // de usuario, y transmite que el sistema está a medio hacer. Se
            // conserva porque sirve para diagnosticar, pero solo se muestra al
            // tocar el título de la pantalla tres veces.
            if (_verDiag)
              Container(
                width: double.infinity,
                color: Colors.amber.shade100,
                padding: const EdgeInsets.all(8),
                child: Text(
                  'DIAG: correo="$_diagCorreo" · admin=$_diagAdmin · '
                  'misMaterias=${_misMaterias.length} · '
                  'cargCat=$_cargandoCatalogo · cargMat=$_cargandoMisMaterias',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            Expanded(
              child: _capturaCerradaParaDocente
                  ? _vistaCapturaCerrada()
                  : (_materiaAsignadaActiva == null &&
                          (_cargandoCatalogo || _cargandoMisMaterias))
                      // Esqueleto en vez de una rueda sola en pantalla blanca:
                      // el usuario ve la forma de lo que viene y la espera se
                      // percibe más corta, aunque tarde lo mismo.
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CessumSkeletonList())
                      : (_errorCatalogo != null &&
                              _materiaAsignadaActiva == null)
                          ? _vistaError()
                          : _vistaPrincipal(),
            ),
          ],
        ),
      ),
    );
  }

  /// Confirma con el docente antes de salir si hay calificaciones sin guardar.
  Future<bool> _confirmarSalida() async {
    if (!_cambiosSinGuardar) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir sin guardar', style: TextStyle(fontSize: 16)),
        content: const Text(
          'Tienes calificaciones capturadas que aún no has guardado. Si sales '
          'ahora se perderán. ¿Qué deseas hacer?',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir capturando')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir y descartar'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Widget _vistaCapturaCerrada() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_clock, color: cessumGold, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              'La captura no está habilitada',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textoFuerte,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'En este momento no es período de captura de calificaciones. '
              'Cuando la Vicerrectoría habilite la captura, podrás registrar '
              'las calificaciones de tus grupos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _textoSuave, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Mientras tanto, puedes consultar tus materias asignadas desde '
              '"Mis materias" en el menú.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textoSuave, height: 1.5),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed, width: 1.5),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Volver al menú'),
            ),
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
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            const SizedBox(height: 12),
            Text(
              _errorCatalogo!,
              textAlign: TextAlign.center,
              style: TextStyle(color: _textoSuave, height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _cargarCatalogo,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bandaModoPrueba() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.science, color: cessumGold, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modo prueba (administrador)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textoFuerte,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No se guarda en la base. Genera acta y PDF ficticios para demos.',
                  style: TextStyle(fontSize: 11, color: _textoSuave, height: 1.3),
                ),
              ],
            ),
          ),
          Switch(
            value: _modoPrueba,
            activeThumbColor: cessumGold,
            onChanged: (v) => setState(() => _modoPrueba = v),
          ),
        ],
      ),
    );
  }

  Widget _vistaPrincipal() {
    // DOCENTE NORMAL (no admin): si aun no eligio materia, ve la lista de
    // sus materias asignadas en tarjetas. Si ya eligio una, ve la captura.
    if (_materiaAsignadaActiva == null && !_modoManualDocente &&
        (!_esAdminUsuario || _misMaterias.isNotEmpty)) {
      return _vistaMisMaterias();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_esAdminUsuario && _materiaAsignadaActiva == null)
          _bandaModoPrueba(),
        if (_materiaAsignadaActiva != null) _bandaMateriaActiva(),
        if (!_esAdminUsuario && _modoManualDocente)
          _bandaModoManualDocente(),
        // Dropdowns solo cuando NO hay una materia elegida de la lista.
        if ((_esAdminUsuario || _modoManualDocente) &&
            _materiaAsignadaActiva == null)
          _tarjeta(
            titulo: 'Grupo a calificar',
            hijo: Column(
              children: [
                _dropdown(
                  etiqueta: 'Programa',
                  valor: _programa,
                  opciones: _catalogo.map((e) => e.programa).toList(),
                  onChanged: (v) {
                    setState(() {
                      _programa = v;
                      _generacion = null;
                      _grupo = null;
                      _alumnos = [];
                      _materiaSeleccionada = null;
                      _materia.clear();
                      _clave.clear();
                      _ciclo.clear();
                    });
                  },
                ),
                const SizedBox(height: 10),
                _dropdown(
                  etiqueta: 'Generación',
                  valor: _generacion,
                  opciones: _generacionesDisponibles,
                  onChanged: _programa == null
                      ? null
                      : (v) {
                          setState(() {
                            _generacion = v;
                            _grupo = null;
                            _alumnos = [];
                          });
                        },
                ),
                const SizedBox(height: 10),
                _dropdown(
                  etiqueta: 'Grupo',
                  valor: _grupo,
                  opciones: _gruposDisponibles,
                  onChanged: _generacion == null
                      ? null
                      : (v) {
                          setState(() => _grupo = v);
                          _cargarAlumnos();
                        },
                ),
              ],
            ),
          ),
        if ((_esAdminUsuario || _modoManualDocente) &&
            _materiaAsignadaActiva == null)
          const SizedBox(height: 12),
        _tarjeta(
          titulo: 'Datos de la materia',
          hijo: Column(
            children: [
              if (_materiasDelPrograma.isNotEmpty) ...[
                DropdownButtonFormField<_MateriaCarta>(
                  value: _materiaSeleccionada,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Materia (cartas descriptivas)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: _materiasDelPrograma
                      .map((m) => DropdownMenuItem<_MateriaCarta>(
                            value: m,
                            child: Text(m.denominacion,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _materiaSeleccionada = v;
                      if (v != null) {
                        _materia.text = v.denominacion;
                        _clave.text = v.clave;
                        _ciclo.text = v.semestre;
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
              ],
              _campo(_materia, 'Nombre de la asignatura'),
              const SizedBox(height: 10),
              _campo(_clave, 'Clave de la asignatura'),
              const SizedBox(height: 10),
              _campo(_ciclo, 'Ciclo'),
              const SizedBox(height: 10),
              _campo(_modalidad, 'Modalidad'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_cargandoAlumnos)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator(color: cessumRed)),
          )
        else if (_grupo != null && _alumnos.isEmpty)
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Este grupo no tiene alumnos en la base.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textoSuave),
                ),
              ),
              _botonAgregarAlumno(),
            ],
          )
        else if (_alumnos.isNotEmpty) ...[
          _botonLaboratorio(),
          const SizedBox(height: 10),
          _barraMetricas(),
          _notaPosibleBaja(),
          const SizedBox(height: 10),
          _filtrosAlumnos(),
          const SizedBox(height: 10),
          ..._alumnosFiltrados().map((e) => _filaAlumno(e.key, e.value)),
          if (_alumnosFiltrados().isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _soloPendientes
                      ? '¡Sin pendientes! Todos los alumnos visibles tienen calificación.'
                      : 'Ningún alumno coincide con la búsqueda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textoSuave),
                ),
              ),
            ),
          const SizedBox(height: 8),
          _botonAgregarAlumno(),
          const SizedBox(height: 16),
          _botones(),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  /// Devuelve los alumnos que pasan los filtros, conservando su índice REAL
  /// dentro de [_alumnos] (clave del MapEntry), para que guardar/eliminar
  /// sigan apuntando al alumno correcto.
  Iterable<MapEntry<int, _FilaAlumno>> _alumnosFiltrados() {
    final q = _busquedaAlumno.trim().toLowerCase();
    final res = _alumnos.asMap().entries.where((e) {
      final a = e.value;
      if (_soloPendientes && a.calificacion != null) return false;
      if (q.isNotEmpty &&
          !a.nombre.toLowerCase().contains(q) &&
          !a.matricula.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    if (_orden == 'pendientes') {
      res.sort((x, y) {
        final px = x.value.calificacion == null ? 0 : 1;
        final py = y.value.calificacion == null ? 0 : 1;
        if (px != py) return px - py; // pendientes (0) primero
        return x.value.nombre
            .toLowerCase()
            .compareTo(y.value.nombre.toLowerCase());
      });
    } else {
      res.sort((x, y) =>
          x.value.nombre.toLowerCase().compareTo(y.value.nombre.toLowerCase()));
    }
    return res;
  }

  Widget _filtrosAlumnos() {
    final pendientes = _alumnos.length - _capturados;
    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar por nombre o matrícula',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _busquedaAlumno.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _busquedaAlumno = ''),
                  ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) => setState(() => _busquedaAlumno = v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilterChip(
              selected: _soloPendientes,
              label: Text(
                _soloPendientes
                    ? 'Solo pendientes ($pendientes)'
                    : 'Solo pendientes',
                style: const TextStyle(fontSize: 12.5),
              ),
              avatar: Icon(
                _soloPendientes ? Icons.filter_alt : Icons.filter_alt_outlined,
                size: 18,
                color: _soloPendientes ? Colors.white : cessumRed,
              ),
              selectedColor: cessumRed,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                  color: _soloPendientes ? Colors.white : _textoFuerte),
              onSelected: (v) => setState(() => _soloPendientes = v),
            ),
            const SizedBox(width: 8),
            if (pendientes > 0)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: cessumGold,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: _dialogoLlenarPendientes,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Llenar', style: TextStyle(fontSize: 12.5)),
              ),
            const Spacer(),
            Text(
              'Faltan $pendientes de ${_alumnos.length}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: pendientes == 0 ? Colors.green : cessumRed,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Ordenar',
              icon: Icon(Icons.sort, size: 20, color: _textoSuave),
              onSelected: (v) => setState(() => _orden = v),
              itemBuilder: (_) => [
                CheckedPopupMenuItem<String>(
                  value: 'nombre',
                  checked: _orden == 'nombre',
                  child: const Text('Nombre (A-Z)'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'pendientes',
                  checked: _orden == 'pendientes',
                  child: const Text('Pendientes primero'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Asigna una misma calificación a todos los alumnos que aún NO tienen nota.
  /// No modifica a quienes ya fueron calificados.
  Future<void> _dialogoLlenarPendientes() async {
    final pendientes = _alumnos.where((a) => a.calificacion == null).length;
    if (pendientes == 0) return;
    int? sel;
    final aplicar = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Llenar pendientes',
              style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se asignará la misma calificación a los $pendientes alumno(s) '
                'que aún no tienen nota. Los que ya tienen no se modifican.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [6, 7, 8, 9, 10].map((n) {
                  final activo = sel == n;
                  return ChoiceChip(
                    label: Text('$n'),
                    selected: activo,
                    selectedColor: cessumRed,
                    labelStyle: TextStyle(
                      color: activo ? Colors.white : _textoFuerte,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => setLocal(() => sel = n),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: sel == null ? null : () => Navigator.pop(ctx, sel),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (aplicar == null) return;
    setState(() {
      for (final a in _alumnos) {
        if (a.calificacion == null) a.calificacion = aplicar;
      }
      _cambiosSinGuardar = true;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Se asignó $aplicar a $pendientes alumno(s) pendiente(s).'),
        ),
      );
    }
  }

  Widget _botonAgregarAlumno() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: cessumGold,
          side: const BorderSide(color: cessumGold, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: _dialogoAgregarAlumno,
        icon: const Icon(Icons.person_add_alt, size: 20),
        label: const Text('Agregar alumno'),
      ),
    );
  }

  Widget _barraMetricas() {
    Widget item(String n, String etq, Color c) => Column(
          children: [
            Text(n,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: c)),
            Text(etq,
                style: TextStyle(fontSize: 11, color: _textoSuave)),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          item('${_alumnos.length}', 'Alumnos', _textoFuerte),
          item('$_capturados', 'Capturados', cessumGold),
          item('$_aprobados', 'Aprobados', Colors.green),
          item('$_reprobados', 'Reprobados', cessumRed),
        ],
      ),
    );
  }

  Widget _filaAlumno(int i, _FilaAlumno a) {
    final pendiente = a.calificacion == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: pendiente
            ? (cessumIsDark(context)
                ? const Color(0xFF2A2410)
                : const Color(0xFFFFFBF0))
            : _superficie,
        borderRadius: BorderRadius.circular(10),
        border: pendiente
            ? const Border(left: BorderSide(color: cessumGold, width: 4))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.nombre,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textoFuerte),
                ),
                Text(
                  a.matricula,
                  style: TextStyle(fontSize: 11, color: _textoSuave),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _selectorCalif(a),
          _banderaBaja(a),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: _textoSuave),
            tooltip: 'Quitar de la lista',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            onPressed: () => _eliminarAlumno(i),
          ),
        ],
      ),
    );
  }

  Widget _selectorCalif(_FilaAlumno a) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: _bordeFuerte),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<int?>(
        value: a.calificacion,
        hint: const Text('--', style: TextStyle(fontSize: 14)),
        underline: const SizedBox.shrink(),
        items: <int?>[null, 6, 7, 8, 9, 10].map((n) {
          return DropdownMenuItem<int?>(
            value: n,
            child: Text(
              n == null ? '--' : '$n',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: n == 6 ? cessumRed : _textoFuerte,
              ),
            ),
          );
        }).toList(),
        onChanged: (v) => setState(() {
          a.calificacion = v;
          _cambiosSinGuardar = true;
        }),
      ),
    );
  }

  Widget _botones() {
    // En modo prueba se oculta "Guardar avance" (no tiene sentido) y el boton
    // principal queda dorado con la leyenda de PRUEBA.
    if (_modoPrueba) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: cessumGold,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _enviando ? null : () => _enviar(generarActa: true),
          icon: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.science),
          label: Text(_enviando ? 'Procesando...' : 'Generar acta de PRUEBA'),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: cessumRed,
              side: const BorderSide(color: cessumRed, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _enviando ? null : () => _enviar(generarActa: false),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar avance'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _enviando ? null : () => _enviar(generarActa: true),
            icon: _enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.description),
            label: Text(_enviando ? 'Procesando...' : 'Generar acta oficial'),
          ),
        ),
      ],
    );
  }

  // Colores que responden al tema (sin alterar el modo claro).
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : Colors.black87;
  Color get _textoSuave => cessumMuted(context);
  Color get _borde => cessumIsDark(context) ? Colors.white12 : Colors.black12;
  Color get _bordeFuerte =>
      cessumIsDark(context) ? Colors.white24 : Colors.black26;

  Widget _tarjeta({required String titulo, required Widget hijo}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cessumRed,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          hijo,
        ],
      ),
    );
  }

  Widget _dropdown({
    required String etiqueta,
    required String? valor,
    required List<String> opciones,
    required void Function(String?)? onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: valor,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: etiqueta,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: opciones
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _campo(TextEditingController c, String etiqueta) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: etiqueta,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  // ===== VISTAS PARA DOCENTE NO-ADMIN =====

  Widget _vistaMisMaterias() {
    if (_misMaterias.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, color: cessumFaint(context), size: 48),
              const SizedBox(height: 12),
              Text(
                'No tienes materias asignadas en este momento.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textoSuave, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                'Si crees que esto es un error, comunícate con la Vicerrectoría.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textoSuave, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: const BorderSide(color: cessumRed, width: 1.5),
                ),
                onPressed: () async {
                  final correo = await SessionStore.validEmail();
                  _cargarMisGrupos(correo ?? '');
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: cessumRed),
                onPressed: _activarModoManualDocente,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Capturar otra asignatura manualmente'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            'Mis materias asignadas',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textoFuerte,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16, left: 4),
          child: Text(
            'Selecciona la materia que vas a calificar.',
            style: TextStyle(fontSize: 13, color: _textoSuave),
          ),
        ),
        ..._misMaterias.map(_tarjetaMateriaAsignada),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: cessumRed,
            side: const BorderSide(color: cessumRed, width: 1.2),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _activarModoManualDocente,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Otra asignatura (capturar manualmente)'),
        ),
      ],
    );
  }

  Widget _tarjetaMateriaAsignada(_MateriaAsignada m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borde),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _seleccionarMateriaAsignada(m),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.fact_check, color: cessumRed, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.materia,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textoFuerte,
                        ),
                      ),
                      if (m.terminada)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cessumGold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Ya terminó · pendiente de evaluar',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: cessumGold,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        )
                      else if (_fechaMateria(m.inicio) != null &&
                          _fechaMateria(m.inicio)!.isAfter(DateTime.now()))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _textoSuave.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Aún no inicia',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: _textoSuave,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      const SizedBox(height: 3),
                      Text(
                        '${m.programa} • Gen. ${m.generacion} • ${m.grupo}',
                        style: TextStyle(
                            fontSize: 12, color: _textoSuave, height: 1.3),
                      ),
                      if (m.dia.isNotEmpty || m.hora.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            [m.dia, m.hora]
                                .where((x) => x.isNotEmpty)
                                .join(' • '),
                            style: const TextStyle(
                                fontSize: 11,
                                color: cessumGold,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      if (m.inicio.isNotEmpty || m.termino.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'Vigente: ${_fechaBonita(m.inicio)} → ${_fechaBonita(m.termino)}',
                            style: TextStyle(
                                fontSize: 11, color: _textoSuave),
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => _seleccionarMateriaAsignada(m),
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: const Text('Calificar'),
                    ),
                    const SizedBox(height: 4),
                    // (9-oct-2026) El laboratorio de esa materia: actividades
                    // del aula + asistencia → sugerencia de calificación.
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: cessumGold,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        textStyle: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => _laboratorioDesdeTarjeta(m),
                      icon: const Icon(Icons.science_outlined, size: 16),
                      label: const Text('Laboratorio'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bandaModoManualDocente() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_note, color: cessumGold, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Captura manual: elige el grupo y la materia. '
              'Para volver a tus materias asignadas, toca "Mis materias".',
              style: TextStyle(fontSize: 11.5, color: _textoSuave, height: 1.3),
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: cessumRed,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            onPressed: _volverAMisMaterias,
            icon: const Icon(Icons.list_alt, size: 18),
            label: const Text('Mis materias', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _bandaMateriaActiva() {
    final m = _materiaAsignadaActiva!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.fact_check, color: cessumRed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.materia,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textoFuerte,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${m.programa} • Gen. ${m.generacion} • ${m.grupo}',
                  style: TextStyle(
                      fontSize: 11, color: _textoSuave, height: 1.3),
                ),
                if (m.dia.isNotEmpty || m.hora.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [m.dia, m.hora].where((x) => x.isNotEmpty).join(' • '),
                      style: const TextStyle(
                          fontSize: 11,
                          color: cessumGold,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: cessumRed,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            onPressed: _volverAMisMaterias,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Cambiar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
